//! Mapping final visual glyph advances onto logical source graphemes.

const std = @import("std");

const draft = @import("draft.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_types = @import("../../types/paragraph.zig");
const source = @import("source.zig");
const types = @import("types.zig");

pub fn applyLine(
    allocator: std.mem.Allocator,
    layout: paragraph_types.ParagraphLayout,
    line: paragraph_types.ParagraphLine,
    drafts: []draft.Grapheme,
) error{ OutOfMemory, InvalidParagraphLayout }!void {
    var pen_x = line.x;
    const glyph_end = line.glyph_start + line.glyph_len;
    for (
        layout.glyphs[line.glyph_start..glyph_end],
        line.glyph_start..,
    ) |glyph, glyph_index| {
        const run_index = source.runIndexForGlyph(layout.runs, glyph_index);
        const source_end = glyph.sourceByteEnd();
        if (source_end > glyph.cluster) {
            if (rangeOverlapping(
                drafts,
                glyph.cluster,
                source_end,
            )) |range| {
                const count = range.end - range.start;
                if (count > 1 and run_index != null and
                    try addAuthoredLigaturePortions(
                        allocator,
                        layout,
                        glyph,
                        run_index.?,
                        pen_x,
                        drafts,
                        range,
                    ))
                {
                    pen_x += glyph.x_advance;
                    continue;
                }
                const share = glyph.x_advance /
                    @as(f32, @floatFromInt(count));
                const direction = drafts[range.start].direction;
                for (range.start..range.end) |draft_index| {
                    const logical_index = draft_index - range.start;
                    const portion_x = switch (direction) {
                        .ltr => pen_x + share *
                            @as(f32, @floatFromInt(logical_index)),
                        .rtl => pen_x + glyph.x_advance - share *
                            @as(f32, @floatFromInt(logical_index + 1)),
                    };
                    addPortion(
                        &drafts[draft_index],
                        portion_x,
                        share,
                        run_index,
                        glyph.isInlineObject(),
                    );
                }
            }
        } else if (forInsertion(drafts, glyph)) |draft_index| {
            addPortion(
                &drafts[draft_index],
                pen_x,
                glyph.x_advance,
                run_index,
                false,
            );
        }
        pen_x += glyph.x_advance;
    }
}

fn addAuthoredLigaturePortions(
    allocator: std.mem.Allocator,
    layout: paragraph_types.ParagraphLayout,
    glyph: GlyphPosition,
    run_index: usize,
    pen_x: f32,
    drafts: []draft.Grapheme,
    range: draft.IndexRange,
) error{ OutOfMemory, InvalidParagraphLayout }!bool {
    if (run_index >= layout.runs.len) return error.InvalidParagraphLayout;
    const run = layout.runs[run_index];
    const coord_end = run.variation_coord_start + run.variation_coord_len;
    if (coord_end > layout.normalized_variation_coords.len) {
        return error.InvalidParagraphLayout;
    }
    const normalized_coords =
        layout.normalized_variation_coords[run.variation_coord_start..coord_end];
    const carets = run.font.glyphs().ligatureCarets(
        allocator,
        glyph.glyph_id,
        normalized_coords,
    ) catch |err| switch (err) {
        // TextGeometry is a convenience projection over an already accepted
        // paragraph. If caller-owned font bytes were mutated after shaping,
        // retain valid equal-split source geometry rather than making the
        // entire accessibility build fail because an optional GDEF hint can no
        // longer be trusted. Allocation failure still propagates normally.
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    defer allocator.free(carets);

    const component_count = range.end - range.start;
    if (carets.len + 1 != component_count or glyph.x_advance <= 0) {
        return false;
    }
    const properties = run.font.properties();
    if (properties.units_per_em == 0) return false;
    const scale = run.font_size /
        @as(f32, @floatFromInt(properties.units_per_em));

    // Convert authored design-unit boundaries into final layout units. GPOS,
    // letter spacing, and justification may change the output advance after
    // GDEF was authored; requiring every boundary to remain strictly inside
    // that final advance prevents malformed or stale metadata from producing
    // negative accessibility widths.
    var boundaries: [32]f32 = undefined;
    const positions = if (carets.len <= boundaries.len)
        boundaries[0..carets.len]
    else
        try allocator.alloc(f32, carets.len);
    defer if (carets.len > boundaries.len) allocator.free(positions);
    var previous: f32 = 0;
    for (carets, positions) |caret, *position| {
        position.* = caret.position * scale;
        if (!std.math.isFinite(position.*) or
            position.* <= previous or
            position.* >= glyph.x_advance)
        {
            return false;
        }
        previous = position.*;
    }

    for (range.start..range.end) |draft_index| {
        const logical_index = draft_index - range.start;
        const physical_index = switch (drafts[range.start].direction) {
            .ltr => logical_index,
            .rtl => component_count - logical_index - 1,
        };
        const component_start = if (physical_index == 0)
            0
        else
            positions[physical_index - 1];
        const component_end = if (physical_index == positions.len)
            glyph.x_advance
        else
            positions[physical_index];
        addPortion(
            &drafts[draft_index],
            pen_x + component_start,
            component_end - component_start,
            run_index,
            false,
        );
        drafts[draft_index].authored_ligature_caret = true;
    }
    return true;
}

pub fn resolveMissingPositions(
    line_x: f32,
    drafts: []draft.Grapheme,
) void {
    var group_start: usize = 0;
    while (group_start < drafts.len) {
        const direction = drafts[group_start].direction;
        var group_end = group_start + 1;
        while (group_end < drafts.len and
            drafts[group_end].direction == direction)
        {
            group_end += 1;
        }
        resolveDirectionGroup(
            line_x,
            drafts[group_start..group_end],
            direction,
        );
        group_start = group_end;
    }
}

pub fn resolveMissingOwners(drafts: []draft.Grapheme) void {
    for (drafts, 0..) |*item, index| {
        if (item.run_index != null or item.fontless) continue;
        var previous = index;
        while (previous > 0) {
            previous -= 1;
            if (drafts[previous].run_index) |owner| {
                item.run_index = owner;
                break;
            }
        }
        if (item.run_index != null) continue;
        var next = index + 1;
        while (next < drafts.len) : (next += 1) {
            if (drafts[next].run_index) |owner| {
                item.run_index = owner;
                break;
            }
        }
    }
}

fn rangeOverlapping(
    drafts: []const draft.Grapheme,
    byte_start: usize,
    byte_end: usize,
) ?draft.IndexRange {
    if (byte_start >= byte_end or drafts.len == 0) return null;
    var start: usize = 0;
    while (start < drafts.len and drafts[start].byteEnd() <= byte_start) {
        start += 1;
    }
    var end = start;
    while (end < drafts.len and drafts[end].byte_start < byte_end) {
        end += 1;
    }
    if (start == end) return null;
    return .{ .start = start, .end = end };
}

fn forInsertion(
    drafts: []const draft.Grapheme,
    glyph: GlyphPosition,
) ?usize {
    if (drafts.len == 0) return null;
    if (!glyph.isAutomaticHyphen()) {
        for (drafts, 0..) |item, index| {
            if (item.byte_start == glyph.cluster) return index;
        }
    }
    var index = drafts.len;
    while (index > 0) {
        index -= 1;
        if (drafts[index].byteEnd() <= glyph.cluster) return index;
    }
    return 0;
}

fn addPortion(
    item: *draft.Grapheme,
    position: f32,
    width: f32,
    run_index: ?usize,
    inline_object: bool,
) void {
    if (!item.positioned) {
        item.position = @min(position, position + width);
        item.positioned = true;
    } else {
        item.position = @min(
            item.position,
            @min(position, position + width),
        );
    }
    item.width += width;
    if (item.run_index == null and !inline_object) {
        item.run_index = run_index;
    }
    item.fontless = item.fontless or inline_object;
}

fn resolveDirectionGroup(
    line_x: f32,
    drafts: []draft.Grapheme,
    direction: types.Direction,
) void {
    const first_positioned = for (drafts, 0..) |item, index| {
        if (item.positioned) break index;
    } else null;
    const first = first_positioned orelse {
        for (drafts) |*item| {
            item.position = line_x;
            item.positioned = true;
        }
        return;
    };
    const leading_anchor = switch (direction) {
        .ltr => drafts[first].position,
        .rtl => drafts[first].position + drafts[first].width,
    };
    for (drafts[0..first]) |*item| {
        item.position = leading_anchor;
        item.positioned = true;
    }
    var previous = first;
    for (drafts[first + 1 ..], first + 1..) |*item, index| {
        if (!item.positioned) {
            item.position = switch (direction) {
                .ltr => drafts[previous].position + drafts[previous].width,
                .rtl => drafts[previous].position,
            };
            item.positioned = true;
        }
        previous = index;
    }
}
