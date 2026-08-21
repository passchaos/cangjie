//! Glyph and font-run reordering for Unicode bidirectional visual order.
//!
//! Shaping produces source-cluster metadata; this module maps Unicode bidi
//! items back to that output, preserving one-to-many substitutions, mirrored
//! glyph selection, fallback-font ownership, and per-line source ranges.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const run_types = @import("../../types/runs.zig");
const mapping = @import("mapping.zig");
const runs = @import("runs.zig");
const bidi = @import("../../../text/bidi.zig");
const unicode = @import("../../../unicode.zig");

pub fn apply(
    buffer: anytype,
    text: []const u8,
    rtl: bool,
    single_font: ?*const Font,
) !void {
    if (buffer.glyphs.items.len == 0) return;
    const can_reverse_in_place =
        single_font != null or buffer.runs.items.len <= 1;
    if (can_reverse_in_place and
        bidi.visualOrderInputKind(text, rtl) == .pure_rtl)
    {
        bidi.applyPureRtlVisualOrder(&buffer.glyphs, single_font);
        runs.recomputeOffsets(buffer);
        return;
    }
    const base_direction: unicode.BidiClass = if (rtl) .rtl else .ltr;
    var bidi_map = try unicode.buildBidiMap(
        buffer.allocator,
        text,
        base_direction,
    );
    defer bidi_map.deinit();
    if (bidi_map.items.len == 0) return;

    const old_runs = try buffer.allocator.dupe(
        @TypeOf(buffer.runs.items[0]),
        buffer.runs.items,
    );
    defer buffer.allocator.free(old_runs);
    const old_glyphs = try buffer.allocator.dupe(
        GlyphPosition,
        buffer.glyphs.items,
    );
    defer buffer.allocator.free(old_glyphs);
    const glyph_run_indices = try runs.buildGlyphRunIndices(
        buffer.allocator,
        old_runs,
        old_glyphs.len,
    );
    defer buffer.allocator.free(glyph_run_indices);
    const glyph_cluster_index = try mapping.buildClusterIndex(
        buffer.allocator,
        old_glyphs,
    );
    defer buffer.allocator.free(glyph_cluster_index);

    const seen = try buffer.allocator.alloc(bool, old_glyphs.len);
    defer buffer.allocator.free(seen);
    @memset(seen, false);
    var visual_glyphs = std.ArrayList(GlyphPosition).empty;
    defer visual_glyphs.deinit(buffer.allocator);
    var visual_run_indices = std.ArrayList(usize).empty;
    defer visual_run_indices.deinit(buffer.allocator);

    for (bidi_map.items) |item| {
        try mapping.appendItem(
            false,
            buffer.allocator,
            old_glyphs,
            old_runs,
            single_font,
            glyph_run_indices,
            glyph_cluster_index,
            seen,
            0,
            old_glyphs.len,
            item,
            &visual_glyphs,
            &visual_run_indices,
            {},
        );
    }
    // GSUB ligatures or skipped variation selectors can make glyph count
    // differ from bidi scalar count. Preserve unmatched output in source order.
    try mapping.appendUnseen(
        false,
        buffer.allocator,
        old_glyphs,
        old_runs,
        single_font,
        glyph_run_indices,
        seen,
        0,
        old_glyphs.len,
        &visual_glyphs,
        &visual_run_indices,
        {},
    );
    if (visual_glyphs.items.len != old_glyphs.len) {
        return error.InvalidBidiMap;
    }

    var changed = false;
    for (old_glyphs, visual_glyphs.items) |old, visual| {
        if (old.cluster != visual.cluster or
            old.glyph_id != visual.glyph_id or
            old.codepoint != visual.codepoint)
        {
            changed = true;
            break;
        }
    }
    if (!changed) return;

    buffer.glyphs.clearRetainingCapacity();
    try buffer.glyphs.appendSlice(buffer.allocator, visual_glyphs.items);
    try runs.rebuild(buffer, old_runs, visual_run_indices.items);
    runs.recomputeOffsets(buffer);
}

pub fn normalizeLogical(buffer: anytype) !void {
    if (buffer.glyphs.items.len < 2) return;
    var monotonic = true;
    for (
        buffer.glyphs.items[1..],
        buffer.glyphs.items[0 .. buffer.glyphs.items.len - 1],
    ) |current, previous| {
        if (current.cluster < previous.cluster) {
            monotonic = false;
            break;
        }
    }
    if (monotonic) return;

    const old_runs = try buffer.allocator.dupe(
        @TypeOf(buffer.runs.items[0]),
        buffer.runs.items,
    );
    defer buffer.allocator.free(old_runs);
    const glyph_run_indices = try runs.buildGlyphRunIndices(
        buffer.allocator,
        old_runs,
        buffer.glyphs.items.len,
    );
    defer buffer.allocator.free(glyph_run_indices);

    const order = try buffer.allocator.alloc(
        usize,
        buffer.glyphs.items.len,
    );
    defer buffer.allocator.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    const Context = struct {
        glyphs: []const GlyphPosition,

        fn lessThan(context: @This(), lhs: usize, rhs: usize) bool {
            const lhs_cluster = context.glyphs[lhs].cluster;
            const rhs_cluster = context.glyphs[rhs].cluster;
            if (lhs_cluster == rhs_cluster) return lhs < rhs;
            return lhs_cluster < rhs_cluster;
        }
    };
    std.sort.heap(
        usize,
        order,
        Context{ .glyphs = buffer.glyphs.items },
        Context.lessThan,
    );

    const old_glyphs = try buffer.allocator.dupe(
        GlyphPosition,
        buffer.glyphs.items,
    );
    defer buffer.allocator.free(old_glyphs);
    const reordered_run_indices = try buffer.allocator.alloc(
        usize,
        order.len,
    );
    defer buffer.allocator.free(reordered_run_indices);
    for (order, 0..) |old_index, new_index| {
        buffer.glyphs.items[new_index] = old_glyphs[old_index];
        reordered_run_indices[new_index] = glyph_run_indices[old_index];
    }
    try runs.rebuild(buffer, old_runs, reordered_run_indices);
    runs.recomputeOffsets(buffer);
}

/// Refresh flat run pens after paragraph-only advance mutations.
///
/// Reflow can change tabs, spacing, justification, and punctuation after
/// shaping. This keeps public run metadata synchronized even when bidi does not
/// otherwise require a permutation/rebuild pass.
pub fn recomputeRunOffsets(buffer: anytype) void {
    runs.recomputeOffsets(buffer);
}

/// Try the allocation-free line permutation for a pure RTL paragraph.
///
/// A single run that owns every glyph is the important styled Arabic case. In
/// that configuration each line-local L2 permutation is just a reversal, run
/// ownership cannot fragment, and the caller's glyph-parallel sidecar can be
/// reversed in the same transaction. Mixed-direction text, bidi controls,
/// unowned inline objects, fallback runs, and synthetic run fragments remain
/// on the general resolver path below.
pub fn tryApplyPureRtlLinesWithParallel(
    buffer: anytype,
    text: []const u8,
    parallel: anytype,
) bool {
    const glyphs = buffer.glyphs.items;
    if (parallel.len != glyphs.len or
        bidi.visualOrderInputKind(text, true) != .pure_rtl)
    {
        return false;
    }
    if (buffer.runs.items.len != 1) return false;
    const run = buffer.runs.items[0];
    if (run.glyph_start != 0 or run.glyph_len != glyphs.len) return false;

    // Validate every range before the first mutation. Falling back after a
    // partial reversal would violate the general path's logical-order input
    // contract. The general path appends discarded wrapping whitespace after
    // the preceding visual line. Preserve that stable partition by rotating
    // each following line in front of its gap before reversing only the line.
    var previous_end: usize = 0;
    for (buffer.lines.items) |line| {
        const line_end = std.math.add(usize, line.glyph_start, line.glyph_len) catch
            return false;
        if (line.glyph_start < previous_end or line_end > glyphs.len) return false;
        previous_end = line_end;
    }

    const font = run_types.fontForBackend(run);
    var visual_start: usize = 0;
    for (buffer.lines.items) |*line| {
        const logical_start = line.glyph_start;
        const logical_end = logical_start + line.glyph_len;
        const gap_len = logical_start - visual_start;
        if (gap_len != 0 and line.glyph_len != 0) {
            const Glyph = @TypeOf(glyphs[0]);
            rotateRecords(Glyph, glyphs[visual_start..logical_end], gap_len);
            const Parallel = @TypeOf(parallel[0]);
            rotateRecords(
                Parallel,
                parallel[visual_start..logical_end],
                gap_len,
            );
        }
        bidi.applyPureRtlVisualOrderSlice(
            glyphs[visual_start .. visual_start + line.glyph_len],
            font,
        );
        const Parallel = @TypeOf(parallel[0]);
        bidi.reverseRecords(
            Parallel,
            parallel[visual_start .. visual_start + line.glyph_len],
        );
        // The sole run intersects every non-empty line and remains unchanged
        // globally, so rebuilding an O(glyph_count) ownership map is needless.
        line.glyph_start = visual_start;
        line.run_start = 0;
        line.run_len = @intFromBool(line.glyph_len != 0);
        visual_start += line.glyph_len;
    }
    return true;
}

fn rotateRecords(comptime T: type, items: []T, amount: usize) void {
    bidi.reverseRecords(T, items[0..amount]);
    bidi.reverseRecords(T, items[amount..]);
    bidi.reverseRecords(T, items);
}

pub fn applyLines(buffer: anytype, text: []const u8, rtl: bool) !void {
    if (buffer.glyphs.items.len == 0 or buffer.lines.items.len == 0) {
        return;
    }
    const base_direction: unicode.BidiBaseDirection =
        if (rtl) .rtl else .ltr;
    var paragraph = try unicode.resolveBidiParagraph(
        buffer.allocator,
        text,
        base_direction,
    );
    defer paragraph.deinit();
    return applyLinesResolved(buffer, paragraph);
}

/// Apply line-local visual order using a caller-owned UAX #9 resolution.
///
/// Styled layout needs the same immutable paragraph levels to permute its
/// glyph-parallel metadata. Accepting that shared resolution avoids a second
/// decode and paragraph-wide bidi pass; the ordinary entry point above still
/// owns resolution for all other callers.
pub fn applyLinesResolved(
    buffer: anytype,
    paragraph: unicode.BidiParagraph,
) !void {
    return applyLinesResolvedRecording(buffer, paragraph, false);
}

pub fn applyLinesResolvedRecording(
    buffer: anytype,
    paragraph: unicode.BidiParagraph,
    comptime record_permutation: bool,
) !void {
    if (buffer.glyphs.items.len == 0 or buffer.lines.items.len == 0) {
        return;
    }

    const scratch = &buffer.bidi_reorder_scratch;
    try scratch.begin(
        buffer.allocator,
        &buffer.runs,
        &buffer.glyphs,
    );
    var transaction_open = true;
    errdefer if (transaction_open) {
        scratch.rollback(&buffer.runs, &buffer.glyphs);
    };
    const old_runs = scratch.old_runs.items;
    const old_glyphs = scratch.old_glyphs.items;
    const glyph_run_indices = scratch.glyph_run_indices.items;
    const glyph_cluster_index = scratch.glyph_cluster_index.items;
    const seen = scratch.seen.items;
    const visual_glyphs = &buffer.glyphs;
    const visual_run_indices = &scratch.visual_run_indices;
    const permutation = if (record_permutation) &scratch.permutation else {};

    for (buffer.lines.items) |*line| {
        const visual_start = visual_glyphs.items.len;
        const old_line_start = line.glyph_start;
        const old_line_end = old_line_start + line.glyph_len;
        if (line.byte_len != 0 and old_line_start < old_line_end) {
            const scalar_start = paragraph.scalarIndexForByte(
                line.byte_start,
            ) orelse return error.InvalidBidiMap;
            const scalar_end = paragraph.scalarIndexForByte(
                line.byte_start + line.byte_len,
            ) orelse return error.InvalidBidiMap;
            var retained_x9: [1]usize = undefined;
            var retained_x9_count: usize = 0;
            for (old_glyphs[old_line_start..old_line_end]) |source_glyph| {
                if (!source_glyph.isDiscretionaryHyphen() or
                    source_glyph.isAutomaticHyphen())
                {
                    continue;
                }
                // A materialized U+00AD is removed by X9 and therefore needs
                // explicit retention. Automatic hyphens have no source
                // scalar; the cluster index attaches those outputs to the
                // preceding scalar solely for visual permutation.
                retained_x9[0] = paragraph.scalarIndexForByte(
                    source_glyph.cluster,
                ) orelse return error.InvalidBidiMap;
                retained_x9_count = 1;
                break;
            }
            const retained = retained_x9[0..retained_x9_count];
            try paragraph.visualOrderAndLevelsRetaining(
                buffer.allocator,
                scalar_start,
                scalar_end,
                retained,
                &scratch.line_levels,
                &scratch.visual_order,
            );
            for (scratch.visual_order.items) |scalar_index| {
                const scalar = paragraph.scalars[scalar_index];
                const level = scratch.line_levels.items[
                    scalar_index - scalar_start
                ];
                try mapping.appendItem(
                    record_permutation,
                    buffer.allocator,
                    old_glyphs,
                    old_runs,
                    null,
                    glyph_run_indices,
                    glyph_cluster_index,
                    seen,
                    old_line_start,
                    old_line_end,
                    .{
                        .logical_index = scalar_index,
                        .visual_index = 0,
                        .byte_start = scalar.byte_start,
                        .byte_len = scalar.byte_len,
                        .codepoint = scalar.codepoint,
                        .visual_codepoint = if (level & 1 != 0)
                            unicode.mirroredCodepoint(scalar.codepoint)
                        else
                            scalar.codepoint,
                        .direction = if (level & 1 != 0) .rtl else .ltr,
                    },
                    visual_glyphs,
                    visual_run_indices,
                    permutation,
                );
            }
        }
        // Keep unmatched outputs belonging to this line. Discarded wrapping
        // whitespace intentionally remains outside every visual line.
        try mapping.appendUnseen(
            record_permutation,
            buffer.allocator,
            old_glyphs,
            old_runs,
            null,
            glyph_run_indices,
            seen,
            old_line_start,
            old_line_end,
            visual_glyphs,
            visual_run_indices,
            permutation,
        );
        line.glyph_start = visual_start;
        line.glyph_len = visual_glyphs.items.len - visual_start;
    }

    // Preserve outputs omitted from visual lines as a metadata-only suffix.
    try mapping.appendUnseen(
        record_permutation,
        buffer.allocator,
        old_glyphs,
        old_runs,
        null,
        glyph_run_indices,
        seen,
        0,
        old_glyphs.len,
        visual_glyphs,
        visual_run_indices,
        permutation,
    );
    if (visual_glyphs.items.len != old_glyphs.len) {
        return error.InvalidBidiMap;
    }
    if (record_permutation and scratch.permutation.items.len != old_glyphs.len) {
        return error.InvalidBidiMap;
    }

    try runs.rebuild(buffer, old_runs, visual_run_indices.items);
    for (buffer.lines.items) |*line| {
        const range = runs.range(
            buffer.runs.items,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
        );
        line.run_start = range.start;
        line.run_len = range.len;
    }
    runs.recomputeOffsets(buffer);
    transaction_open = false;
}
