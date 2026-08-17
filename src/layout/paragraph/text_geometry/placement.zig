//! Mapping final visual glyph advances onto logical source graphemes.

const draft = @import("draft.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_types = @import("../../types/paragraph.zig");
const source = @import("source.zig");
const types = @import("types.zig");

pub fn applyLine(
    layout: paragraph_types.ParagraphLayout,
    line: paragraph_types.ParagraphLine,
    drafts: []draft.Grapheme,
) void {
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
