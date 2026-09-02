//! Direct retained bidi permutation for one-scalar/one-glyph paragraphs.
//!
//! The preparation-time proof makes scalar indexes usable as glyph indexes.
//! This module keeps only the run-owner sidecars needed when fallback runs
//! fragment under UAX #9 L2; cluster lookup and duplicate suppression remain
//! unnecessary for the complete transaction.

const std = @import("std");

const mapping = @import("mapping.zig");
const runs = @import("runs.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const run_types = @import("../../types/runs.zig");
const bidi = @import("../../../text/bidi.zig");
const unicode = @import("../../../unicode.zig");

/// Apply line-local bidi when preparation proved scalar index == glyph index.
///
/// Returns false before mutation if the restored output no longer satisfies
/// the proof. Run offsets are intentionally left to the presentation layer's
/// single shared offset pass.
pub fn apply(
    buffer: anytype,
    paragraph: unicode.BidiParagraph,
) !bool {
    const glyphs = buffer.glyphs.items;
    if (glyphs.len == 0 or buffer.lines.items.len == 0 or
        glyphs.len != paragraph.scalars.len or
        paragraph.classes.len != paragraph.scalars.len or
        paragraph.levels.len != paragraph.scalars.len or
        !runsOwnCompleteGlyphStream(buffer.runs.items, glyphs.len))
    {
        return false;
    }
    for (glyphs, paragraph.scalars, paragraph.classes) |glyph, scalar, class| {
        if (glyph.cluster != scalar.byte_start or
            glyph.source_byte_len != scalar.byte_len or
            glyph.codepoint != scalar.codepoint or
            glyph.synthetic_glyph_id != null or
            glyph.isDiscretionaryHyphen() or
            glyph.isAutomaticHyphen() or
            glyph.isInlineObject() or
            glyph.isKashida() or
            glyph.isTab() or
            scalarRemovedByX9(class))
        {
            return false;
        }
    }

    // Validate every source range before swapping either owner. Trimmed line
    // whitespace can create gaps, so containment is weaker than equality.
    var previous_glyph_end: usize = 0;
    for (buffer.lines.items) |line| {
        const glyph_end = std.math.add(
            usize,
            line.glyph_start,
            line.glyph_len,
        ) catch return false;
        const byte_end = std.math.add(
            usize,
            line.byte_start,
            line.byte_len,
        ) catch return false;
        if (line.glyph_start < previous_glyph_end or glyph_end > glyphs.len)
            return false;
        const scalar_start = paragraph.scalarIndexForByte(
            line.byte_start,
        ) orelse return false;
        const scalar_end = paragraph.scalarIndexForByte(
            byte_end,
        ) orelse return false;
        if (line.glyph_start < scalar_start or glyph_end > scalar_end)
            return false;
        previous_glyph_end = glyph_end;
    }

    const single_owning_run = buffer.runs.items.len == 1 and
        buffer.runs.items[0].glyph_start == 0 and
        buffer.runs.items[0].glyph_len == glyphs.len;
    const scratch = &buffer.bidi_reorder_scratch;
    if (single_owning_run)
        try scratch.beginDirectSingleOwningRun(
            buffer.allocator,
            &buffer.glyphs,
        )
    else
        try scratch.beginDirect(
            buffer.allocator,
            &buffer.runs,
            &buffer.glyphs,
        );
    var transaction_open = true;
    errdefer if (transaction_open) {
        if (single_owning_run)
            scratch.rollbackSingleOwningRun(&buffer.glyphs)
        else
            scratch.rollback(&buffer.runs, &buffer.glyphs);
    };
    try scratch.line_levels.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );
    try scratch.visual_order.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );

    const old_glyphs = scratch.old_glyphs.items;
    const old_runs = if (single_owning_run)
        buffer.runs.items
    else
        scratch.old_runs.items;
    const glyph_run_indices = scratch.glyph_run_indices.items;
    const visual_glyphs = &buffer.glyphs;
    const visual_run_indices = &scratch.visual_run_indices;
    for (buffer.lines.items) |line| {
        const old_line_start = line.glyph_start;
        const old_line_end = old_line_start + line.glyph_len;
        if (line.byte_len == 0 or old_line_start == old_line_end) continue;
        const scalar_start = paragraph.scalarIndexForByte(
            line.byte_start,
        ).?;
        const scalar_end = paragraph.scalarIndexForByte(
            line.byte_start + line.byte_len,
        ).?;
        try paragraph.visualOrderAndLevelsRetaining(
            buffer.allocator,
            scalar_start,
            scalar_end,
            &.{},
            &scratch.line_levels,
            &scratch.visual_order,
        );
        for (scratch.visual_order.items) |scalar_index| {
            if (scalar_index < old_line_start or scalar_index >= old_line_end)
                continue;
            const owner = if (single_owning_run)
                @as(usize, 0)
            else
                glyph_run_indices[scalar_index];
            if (owner >= old_runs.len) return error.InvalidBidiMap;
            const scalar = paragraph.scalars[scalar_index];
            const level = scratch.line_levels.items[
                scalar_index - scalar_start
            ];
            appendVisualizedDirectGlyph(
                old_glyphs[scalar_index],
                old_runs[owner],
                scalar.codepoint,
                level,
                visual_glyphs,
            );
            if (!single_owning_run)
                visual_run_indices.appendAssumeCapacity(owner);
        }
    }

    // Match the general unseen pass: every glyph excluded from visible line
    // ranges becomes one stable logical suffix, including inter-line spaces.
    var logical_cursor: usize = 0;
    for (buffer.lines.items) |line| {
        for (logical_cursor..line.glyph_start) |glyph_index| {
            appendGapGlyph(
                single_owning_run,
                old_glyphs,
                glyph_run_indices,
                glyph_index,
                visual_glyphs,
                visual_run_indices,
            );
        }
        logical_cursor = line.glyph_start + line.glyph_len;
    }
    for (logical_cursor..old_glyphs.len) |glyph_index| {
        appendGapGlyph(
            single_owning_run,
            old_glyphs,
            glyph_run_indices,
            glyph_index,
            visual_glyphs,
            visual_run_indices,
        );
    }
    if (visual_glyphs.items.len != old_glyphs.len or
        (!single_owning_run and
            visual_run_indices.items.len != old_glyphs.len))
    {
        return error.InvalidBidiMap;
    }

    // Rebuilding can allocate, so line records remain pristine until it
    // succeeds and the existing rollback can restore both swapped owners.
    if (!single_owning_run)
        try runs.rebuild(buffer, old_runs, visual_run_indices.items);
    var visual_start: usize = 0;
    for (buffer.lines.items) |*line| {
        line.glyph_start = visual_start;
        visual_start += line.glyph_len;
        if (single_owning_run) {
            line.run_start = 0;
            line.run_len = @intFromBool(line.glyph_len != 0);
        } else {
            const run_range = runs.range(
                buffer.runs.items,
                line.glyph_start,
                line.glyph_start + line.glyph_len,
            );
            line.run_start = run_range.start;
            line.run_len = run_range.len;
        }
    }
    transaction_open = false;
    return true;
}

/// Emit final visual output directly from an immutable retained paragraph.
///
/// Callers select this only after the strict scalar/glyph proof and simple
/// line builder succeed. Unlike `apply`, there is no mutable logical snapshot
/// to validate, copy, or swap: all allocation completes before the first
/// output append, and the caller clears partial output on error.
pub fn applyFromSource(
    buffer: anytype,
    logical_glyphs: []const GlyphPosition,
    logical_runs: []const run_types.CascadeRun,
    paragraph: unicode.BidiParagraph,
) !void {
    if (buffer.lines.items.len !=
        buffer.bidi_reorder_scratch.direct_line_ranges.items.len or
        buffer.glyphs.items.len != 0 or
        buffer.runs.items.len != 0 or
        logical_glyphs.len != paragraph.scalars.len or
        !runsOwnCompleteGlyphStream(logical_runs, logical_glyphs.len))
    {
        return error.InvalidBidiMap;
    }
    // The immutable paragraph proof established these identities once. Keep
    // debug checks close to the unchecked direct indexing without charging
    // optimized retained reflows for another whole-paragraph validation.
    std.debug.assert(paragraph.classes.len == paragraph.scalars.len);
    std.debug.assert(paragraph.levels.len == paragraph.scalars.len);
    for (logical_glyphs, paragraph.scalars, paragraph.classes) |glyph, scalar, class| {
        std.debug.assert(glyph.cluster == scalar.byte_start);
        std.debug.assert(glyph.source_byte_len == scalar.byte_len);
        std.debug.assert(glyph.codepoint == scalar.codepoint);
        std.debug.assert(!scalarRemovedByX9(class));
    }
    const single_owning_run = logical_runs.len == 1;
    const scratch = &buffer.bidi_reorder_scratch;
    try scratch.prepareDirectFromSource(
        buffer.allocator,
        logical_runs,
        logical_glyphs.len,
        single_owning_run,
    );
    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        logical_glyphs.len,
    );
    try buffer.runs.ensureTotalCapacity(
        buffer.allocator,
        if (single_owning_run) 1 else logical_glyphs.len,
    );
    try scratch.line_levels.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );

    const glyph_run_indices = scratch.glyph_run_indices.items;
    const visual_run_indices = &scratch.visual_run_indices;
    const line_ranges = scratch.direct_line_ranges.items;

    // Validate every source interval before changing output or line metadata.
    // Besides making InvalidBidiMap atomic, the ordered partition proves that
    // each visible slice stays inside its complete L1 context. The strict line
    // builder advances the next range start to the prior range end, including
    // every trimmed space/tab in exactly one source range.
    var source_cursor: usize = 0;
    for (buffer.lines.items, line_ranges) |line, scalar_range| {
        const visible_end = std.math.add(
            usize,
            line.glyph_start,
            line.glyph_len,
        ) catch return error.InvalidBidiMap;
        if (scalar_range.scalar_start != source_cursor or
            scalar_range.scalar_start > scalar_range.scalar_end or
            scalar_range.scalar_end > paragraph.scalars.len or
            line.glyph_start < scalar_range.scalar_start or
            visible_end > scalar_range.scalar_end)
        {
            return error.InvalidBidiMap;
        }
        source_cursor = scalar_range.scalar_end;
    }
    if (source_cursor != logical_glyphs.len) return error.InvalidBidiMap;

    for (buffer.lines.items, line_ranges) |line, scalar_range| {
        const scalar_start = scalar_range.scalar_start;
        const scalar_end = scalar_range.scalar_end;
        const logical_start = line.glyph_start;
        const visible_end = logical_start + line.glyph_len;
        if (line.glyph_len == 0) continue;

        // L1 is line-local and includes whitespace omitted from the visible
        // glyph slice. Copy the visible records once, then permute those copies
        // directly; the scalar==glyph proof makes gathering through a usize
        // visual-order array unnecessary.
        try paragraph.lineLevelsInto(
            buffer.allocator,
            scalar_start,
            scalar_end,
            &scratch.line_levels,
        );
        const output_start = buffer.glyphs.items.len;
        buffer.glyphs.appendSliceAssumeCapacity(
            logical_glyphs[logical_start..visible_end],
        );
        if (!single_owning_run) visual_run_indices.appendSliceAssumeCapacity(
            glyph_run_indices[logical_start..visible_end],
        );
        const output_end = buffer.glyphs.items.len;
        const visible_level_start = logical_start - scalar_start;
        const visible_levels = scratch.line_levels.items[visible_level_start .. visible_level_start + line.glyph_len];

        reorderVisibleL2(
            buffer.glyphs.items[output_start..output_end],
            if (single_owning_run)
                null
            else
                visual_run_indices.items[output_start..output_end],
            visible_levels,
        );

        // Levels and owners followed their glyphs through every L2 reversal,
        // so mirroring can now scan final visual order while still selecting
        // the exact font that produced each positioned source glyph.
        for (
            buffer.glyphs.items[output_start..output_end],
            visible_levels,
            0..,
        ) |*glyph, level, visual_index| {
            if (level & 1 == 0 or
                !bidi.mayHaveBidiMirror(glyph.codepoint)) continue;
            const owner = if (single_owning_run)
                @as(usize, 0)
            else
                visual_run_indices.items[output_start + visual_index];
            if (owner >= logical_runs.len) return error.InvalidBidiMap;
            glyph.* = mapping.visualizedGlyph(
                glyph.*,
                run_types.fontForBackend(logical_runs[owner]),
                unicode.mirroredCodepoint(glyph.codepoint),
            );
        }
    }

    // Omitted wrapping whitespace is metadata-only. Preserve every source
    // interval outside visible lines as one stable logical suffix, without
    // applying line mirroring or L2 to records that no line exposes.
    source_cursor = 0;
    for (buffer.lines.items) |line| {
        appendGapSlice(
            single_owning_run,
            logical_glyphs,
            glyph_run_indices,
            source_cursor,
            line.glyph_start,
            &buffer.glyphs,
            visual_run_indices,
        );
        source_cursor = line.glyph_start + line.glyph_len;
    }
    appendGapSlice(
        single_owning_run,
        logical_glyphs,
        glyph_run_indices,
        source_cursor,
        logical_glyphs.len,
        &buffer.glyphs,
        visual_run_indices,
    );
    if (buffer.glyphs.items.len != logical_glyphs.len or
        (!single_owning_run and
            visual_run_indices.items.len != logical_glyphs.len))
    {
        return error.InvalidBidiMap;
    }

    if (single_owning_run) {
        var run = logical_runs[0];
        run.glyph_start = 0;
        run.glyph_len = logical_glyphs.len;
        run.x_offset = 0;
        run.y_offset = 0;
        buffer.runs.appendAssumeCapacity(run);
    } else {
        try runs.rebuild(buffer, logical_runs, visual_run_indices.items);
    }
    var visual_start: usize = 0;
    for (buffer.lines.items) |*line| {
        line.glyph_start = visual_start;
        visual_start += line.glyph_len;
        if (single_owning_run) {
            line.run_start = 0;
            line.run_len = @intFromBool(line.glyph_len != 0);
        } else {
            const run_range = runs.range(
                buffer.runs.items,
                line.glyph_start,
                line.glyph_start + line.glyph_len,
            );
            line.run_start = run_range.start;
            line.run_len = run_range.len;
        }
    }
}

/// Apply UAX #9 L2 to already-copied visible records. Levels move with their
/// records because later thresholds must inspect the current permutation.
fn reorderVisibleL2(
    glyphs: []GlyphPosition,
    owner_indices: ?[]usize,
    levels: []u8,
) void {
    std.debug.assert(glyphs.len == levels.len);
    std.debug.assert(owner_indices == null or owner_indices.?.len == glyphs.len);
    var max_level: u8 = 0;
    var minimum_odd: u8 = 0xff;
    for (levels) |level| {
        max_level = @max(max_level, level);
        if (level & 1 != 0) minimum_odd = @min(minimum_odd, level);
    }
    if (minimum_odd == 0xff) return;

    var threshold = max_level;
    while (true) : (threshold -= 1) {
        var cursor: usize = 0;
        while (cursor < levels.len) {
            if (levels[cursor] < threshold) {
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < levels.len and levels[cursor] >= threshold) {
                cursor += 1;
            }
            bidi.reverseRecords(GlyphPosition, glyphs[start..cursor]);
            bidi.reverseRecords(u8, levels[start..cursor]);
            if (owner_indices) |indices|
                bidi.reverseRecords(usize, indices[start..cursor]);
        }
        if (threshold == minimum_odd) break;
    }
}

fn appendVisualizedDirectGlyph(
    source: GlyphPosition,
    owner: run_types.CascadeRun,
    codepoint: u21,
    level: u8,
    output: *std.ArrayList(GlyphPosition),
) void {
    if (level & 1 != 0 and bidi.mayHaveBidiMirror(codepoint)) {
        output.appendAssumeCapacity(mapping.visualizedGlyph(
            source,
            run_types.fontForBackend(owner),
            unicode.mirroredCodepoint(codepoint),
        ));
    } else {
        // The direct proof already establishes source.codepoint == codepoint.
        // Keep this helper out of the large caller so the rare mirroring path
        // does not inflate the common identity-copy loop's register pressure.
        output.appendAssumeCapacity(source);
    }
}

fn appendGapGlyph(
    single_owning_run: bool,
    old_glyphs: anytype,
    glyph_run_indices: []const usize,
    glyph_index: usize,
    visual_glyphs: anytype,
    visual_run_indices: *std.ArrayList(usize),
) void {
    visual_glyphs.appendAssumeCapacity(old_glyphs[glyph_index]);
    if (!single_owning_run) visual_run_indices.appendAssumeCapacity(
        glyph_run_indices[glyph_index],
    );
}

fn appendGapSlice(
    single_owning_run: bool,
    logical_glyphs: []const GlyphPosition,
    glyph_run_indices: []const usize,
    start: usize,
    end: usize,
    visual_glyphs: *std.ArrayList(GlyphPosition),
    visual_run_indices: *std.ArrayList(usize),
) void {
    visual_glyphs.appendSliceAssumeCapacity(logical_glyphs[start..end]);
    if (!single_owning_run) visual_run_indices.appendSliceAssumeCapacity(
        glyph_run_indices[start..end],
    );
}

fn scalarRemovedByX9(class: unicode.ExactBidiClass) bool {
    return switch (class) {
        .rle, .lre, .rlo, .lro, .pdf, .bn => true,
        else => false,
    };
}

fn runsOwnCompleteGlyphStream(font_runs: anytype, glyph_count: usize) bool {
    if (font_runs.len == 0) return false;
    var glyph_cursor: usize = 0;
    for (font_runs) |run| {
        if (run.glyph_start != glyph_cursor or run.glyph_len == 0) return false;
        glyph_cursor = std.math.add(
            usize,
            run.glyph_start,
            run.glyph_len,
        ) catch return false;
        if (glyph_cursor > glyph_count) return false;
    }
    return glyph_cursor == glyph_count;
}

test "direct retained bidi visible L2 matches full-line oracle" {
    const cases = [_]struct {
        text: []const u8,
        base: unicode.BidiBaseDirection,
    }{
        .{ .text = "abc אב 12 (גד) xyz", .base = .ltr },
        .{ .text = "אב ABC 12, גד", .base = .rtl },
        .{ .text = "مرحبا 12 (abc) عالم", .base = .rtl },
        .{ .text = "abc \u{2067}אב 12\u{2069} xyz", .base = .ltr },
    };

    for (cases) |case| {
        var paragraph = try unicode.resolveBidiParagraph(
            std.testing.allocator,
            case.text,
            case.base,
        );
        defer paragraph.deinit();
        try std.testing.expect(paragraph.scalars.len <= 64);
        for (paragraph.levels) |level|
            try std.testing.expect(level != 0xff);

        var effective_levels = std.ArrayList(u8).empty;
        defer effective_levels.deinit(std.testing.allocator);
        var full_order = std.ArrayList(usize).empty;
        defer full_order.deinit(std.testing.allocator);
        for (0..paragraph.scalars.len + 1) |line_start| {
            for (line_start..paragraph.scalars.len + 1) |line_end| {
                try paragraph.visualOrderAndLevelsRetaining(
                    std.testing.allocator,
                    line_start,
                    line_end,
                    &.{},
                    &effective_levels,
                    &full_order,
                );
                // The former source path reordered the complete line and then
                // filtered this contiguous visible interval. Exercise every
                // such interval so clipping levels before L2 is proven to
                // preserve the induced order, including line-local L1 resets.
                for (line_start..line_end + 1) |visible_start| {
                    for (visible_start..line_end + 1) |visible_end| {
                        const visible_len = visible_end - visible_start;
                        var glyphs: [64]GlyphPosition = undefined;
                        var owners: [64]usize = undefined;
                        var levels: [64]u8 = undefined;
                        for (0..visible_len) |index| {
                            const scalar_index = visible_start + index;
                            const scalar = paragraph.scalars[scalar_index];
                            glyphs[index] = .{
                                .glyph_id = @intCast(scalar_index + 1),
                                .codepoint = scalar.codepoint,
                                .cluster = scalar_index,
                                .x_advance = 1,
                            };
                            owners[index] = scalar_index;
                            levels[index] = effective_levels.items[
                                scalar_index - line_start
                            ];
                        }

                        reorderVisibleL2(
                            glyphs[0..visible_len],
                            owners[0..visible_len],
                            levels[0..visible_len],
                        );

                        var expected_index: usize = 0;
                        for (full_order.items) |scalar_index| {
                            if (scalar_index < visible_start or
                                scalar_index >= visible_end) continue;
                            try std.testing.expectEqual(
                                scalar_index,
                                glyphs[expected_index].cluster,
                            );
                            try std.testing.expectEqual(
                                scalar_index,
                                owners[expected_index],
                            );
                            try std.testing.expectEqual(
                                effective_levels.items[scalar_index - line_start],
                                levels[expected_index],
                            );
                            expected_index += 1;
                        }
                        try std.testing.expectEqual(visible_len, expected_index);
                    }
                }
            }
        }
    }
}
