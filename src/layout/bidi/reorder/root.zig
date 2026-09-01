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

/// Pure-RTL permutation for several adjacent style/font runs. Glyphs and their
/// metadata reverse together; a bounded ownership map then rebuilds visual run
/// fragments without invoking the general Unicode bidi transaction.
pub fn tryApplyPureRtlLinesWithParallelRuns(
    buffer: anytype,
    text: []const u8,
    parallel: anytype,
) !bool {
    const glyphs = buffer.glyphs.items;
    const run_count = buffer.runs.items.len;
    if (parallel.len != glyphs.len or
        bidi.visualOrderInputKind(text, true) != .pure_rtl or
        run_count < 2 or run_count > 16 or glyphs.len > 512)
    {
        return false;
    }
    var old_runs: [16]run_types.CascadeRun = undefined;
    @memcpy(old_runs[0..run_count], buffer.runs.items);
    var ownership: [512]usize = undefined;
    @memset(ownership[0..glyphs.len], runs.no_run);
    for (old_runs[0..run_count], 0..) |run, run_index| {
        const end = std.math.add(usize, run.glyph_start, run.glyph_len) catch
            return false;
        if (end > glyphs.len) return false;
        @memset(ownership[run.glyph_start..end], run_index);
    }
    var previous_end: usize = 0;
    for (buffer.lines.items) |line| {
        const line_end = std.math.add(usize, line.glyph_start, line.glyph_len) catch
            return false;
        if (line.glyph_start < previous_end or line_end > glyphs.len) return false;
        previous_end = line_end;
    }

    var visual_start: usize = 0;
    for (buffer.lines.items) |*line| {
        const logical_start = line.glyph_start;
        const logical_end = logical_start + line.glyph_len;
        const gap_len = logical_start - visual_start;
        if (gap_len != 0 and line.glyph_len != 0) {
            rotateRecords(
                @TypeOf(glyphs[0]),
                glyphs[visual_start..logical_end],
                gap_len,
            );
            rotateRecords(
                @TypeOf(parallel[0]),
                parallel[visual_start..logical_end],
                gap_len,
            );
            rotateRecords(
                usize,
                ownership[visual_start..logical_end],
                gap_len,
            );
        }
        const visual_end = visual_start + line.glyph_len;
        bidi.reverseRecords(@TypeOf(glyphs[0]), glyphs[visual_start..visual_end]);
        bidi.reverseRecords(@TypeOf(parallel[0]), parallel[visual_start..visual_end]);
        bidi.reverseRecords(usize, ownership[visual_start..visual_end]);
        for (glyphs[visual_start..visual_end], ownership[visual_start..visual_end]) |
            *glyph,
            run_index,
        | {
            if (run_index == runs.no_run) continue;
            const mirrored = unicode.mirroredCodepoint(glyph.codepoint);
            if (mirrored == glyph.codepoint) continue;
            const font = run_types.fontForBackend(old_runs[run_index]);
            const mirrored_glyph = @import("../../../font.zig").shaping
                .glyphIndexForShaping(font, mirrored) catch continue;
            if (mirrored_glyph == 0) continue;
            glyph.codepoint = mirrored;
            glyph.glyph_id = mirrored_glyph;
        }
        line.glyph_start = visual_start;
        visual_start = visual_end;
    }

    try runs.rebuild(buffer, old_runs[0..run_count], ownership[0..glyphs.len]);
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
    return true;
}

/// Apply the same pure-RTL proof without an attributed sidecar.
pub fn tryApplyPureRtlLines(buffer: anytype, text: []const u8) bool {
    if (bidi.visualOrderInputKind(text, true) != .pure_rtl) return false;
    return applyPureRtlLinesAfterProof(buffer);
}

/// Apply the single in-flow-object variant after proving the source is pure
/// RTL. This is the one-shot counterpart of the retained presentation path.
pub fn tryApplyPureRtlLinesWithObject(
    buffer: anytype,
    text: []const u8,
) !bool {
    if (bidi.visualOrderInputKind(text, true) != .pure_rtl) return false;
    return applyPureRtlLinesWithObjectAfterProof(buffer);
}

/// Apply pure-RTL line order after the caller retained the text-level proof.
/// Structural conditions are still checked before the first mutation.
pub fn applyPureRtlLinesAfterProof(buffer: anytype) bool {
    return applyPureRtlLinesAfterProofImpl(buffer, true);
}

/// Apply pure-RTL line order after the retained paragraph proved that no
/// emitted codepoint can require Unicode mirroring.
pub fn applyPureRtlLinesWithoutMirroringAfterProof(buffer: anytype) bool {
    return applyPureRtlLinesAfterProofImpl(buffer, false);
}

fn applyPureRtlLinesAfterProofImpl(
    buffer: anytype,
    comptime may_mirror: bool,
) bool {
    const glyphs = buffer.glyphs.items;
    if (buffer.runs.items.len != 1) return false;
    const run = buffer.runs.items[0];
    if (run.glyph_start != 0 or run.glyph_len != glyphs.len) return false;

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
        }
        if (may_mirror)
            bidi.applyPureRtlVisualOrderSlice(
                glyphs[visual_start .. visual_start + line.glyph_len],
                font,
            )
        else
            bidi.applyPureRtlVisualOrderSliceWithoutMirroring(
                glyphs[visual_start .. visual_start + line.glyph_len],
            );
        line.glyph_start = visual_start;
        line.run_start = 0;
        line.run_len = @intFromBool(line.glyph_len != 0);
        visual_start += line.glyph_len;
    }
    return true;
}

/// Pure-RTL variant for one unowned in-flow marker embedded in a single font
/// run. The marker is deliberately outside `runs`, but reversing each complete
/// line still preserves font ownership as at most two visual run fragments.
pub fn applyPureRtlLinesWithObjectAfterProof(buffer: anytype) !bool {
    return applyPureRtlLinesWithObjectAfterProofImpl(buffer, true);
}

/// Single-object pure-RTL permutation after a retained no-mirroring proof.
pub fn applyPureRtlLinesWithObjectWithoutMirroringAfterProof(
    buffer: anytype,
) !bool {
    return applyPureRtlLinesWithObjectAfterProofImpl(buffer, false);
}

fn applyPureRtlLinesWithObjectAfterProofImpl(
    buffer: anytype,
    comptime may_mirror: bool,
) !bool {
    const glyphs = buffer.glyphs.items;
    if (buffer.runs.items.len != 2) return false;
    const leading_run = buffer.runs.items[0];
    const trailing_run = buffer.runs.items[1];
    // The shaping boundary emits one unowned object atom exactly between the
    // two otherwise-identical font runs. Their ranges therefore identify the
    // marker without another whole-paragraph scan on every retained reflow.
    const logical_object_index = leading_run.glyph_start + leading_run.glyph_len;
    if (leading_run.glyph_start != 0 or
        logical_object_index >= glyphs.len or
        !glyphs[logical_object_index].isInlineObject() or
        trailing_run.glyph_start != logical_object_index + 1 or
        trailing_run.glyph_start + trailing_run.glyph_len != glyphs.len or
        leading_run.font != trailing_run.font or
        leading_run.font_index != trailing_run.font_index or
        leading_run.font_size != trailing_run.font_size or
        leading_run.variation_coord_start != trailing_run.variation_coord_start or
        leading_run.variation_coord_len != trailing_run.variation_coord_len)
    {
        return false;
    }

    var previous_end: usize = 0;
    for (buffer.lines.items) |line| {
        const line_end = std.math.add(usize, line.glyph_start, line.glyph_len) catch
            return false;
        if (line.glyph_start < previous_end or line_end > glyphs.len) return false;
        previous_end = line_end;
    }

    const font = run_types.fontForBackend(leading_run);
    var visual_start: usize = 0;
    var visual_object_index: ?usize = null;
    for (buffer.lines.items) |*line| {
        const logical_start = line.glyph_start;
        const logical_end = logical_start + line.glyph_len;
        const gap_len = logical_start - visual_start;
        if (gap_len != 0 and line.glyph_len != 0) {
            const Glyph = @TypeOf(glyphs[0]);
            rotateRecords(Glyph, glyphs[visual_start..logical_end], gap_len);
        }
        if (logical_object_index >= logical_start and
            logical_object_index < logical_end)
        {
            visual_object_index = visual_start + logical_end -
                logical_object_index - 1;
        }
        if (may_mirror)
            bidi.applyPureRtlVisualOrderSlice(
                glyphs[visual_start .. visual_start + line.glyph_len],
                font,
            )
        else
            bidi.applyPureRtlVisualOrderSliceWithoutMirroring(
                glyphs[visual_start .. visual_start + line.glyph_len],
            );
        line.glyph_start = visual_start;
        visual_start += line.glyph_len;
    }

    // The sole logical run covered every non-object glyph. Rebuild only its
    // one or two ranges around the marker now that line reversals placed it.
    const object_index = visual_object_index orelse return false;
    buffer.runs.clearRetainingCapacity();
    try buffer.runs.ensureTotalCapacity(buffer.allocator, 2);
    if (object_index != 0) {
        var leading = leading_run;
        leading.glyph_start = 0;
        leading.glyph_len = object_index;
        buffer.runs.appendAssumeCapacity(leading);
    }
    if (object_index + 1 < glyphs.len) {
        var trailing = leading_run;
        trailing.glyph_start = object_index + 1;
        trailing.glyph_len = glyphs.len - trailing.glyph_start;
        buffer.runs.appendAssumeCapacity(trailing);
    }
    for (buffer.lines.items) |*line| {
        const range = runs.range(
            buffer.runs.items,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
        );
        line.run_start = range.start;
        line.run_len = range.len;
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

/// Apply resolved line bidi without rebuilding a proven single owning run.
///
/// The general transaction carries one run index beside every glyph because a
/// visual permutation can fragment fallback ownership. When the only run owns
/// the complete stream, that index is invariantly zero and the run itself is
/// unchanged. The ordinary variant retains the general cluster index; a strict
/// retained source instead searches its proven monotone cluster slices and
/// omits that second glyph-sized sidecar too. Both retain UAX #9 L1/L2,
/// mirroring, and unmatched-output rules. Returns false before mutation when
/// the structural proof no longer holds.
pub fn applyLinesResolvedSingleRun(
    buffer: anytype,
    paragraph: unicode.BidiParagraph,
    comptime source_is_simple: bool,
) !bool {
    const glyphs = buffer.glyphs.items;
    if (glyphs.len == 0 or buffer.lines.items.len == 0) return false;
    if (buffer.runs.items.len != 1) return false;
    const run = buffer.runs.items[0];
    if (run.glyph_start != 0 or run.glyph_len != glyphs.len) return false;

    // All range checks precede the glyph-list swap. A false result is thus a
    // safe invitation for the caller to enter the general transaction.
    var previous_end: usize = 0;
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
        if (line.glyph_start < previous_end or glyph_end > glyphs.len)
            return false;
        // Keep the boundary indexes produced by each binary search instead of
        // repeating both lookups immediately below. This proof runs on every
        // retained reflow, including lines whose glyph range is empty.
        const scalar_start = paragraph.scalarIndexForByte(
            line.byte_start,
        ) orelse return false;
        const scalar_end = paragraph.scalarIndexForByte(
            byte_end,
        ) orelse return false;
        if (!source_is_simple) {
            // A materialized soft hyphen is the only post-validation mapping
            // path that requires an additional source lookup. Prove those
            // clusters now so every operation after the glyph-owner swap is
            // allocation-only and cannot leave partially updated lines.
            for (glyphs[line.glyph_start..glyph_end]) |source_glyph| {
                if (source_glyph.isDiscretionaryHyphen() and
                    !source_glyph.isAutomaticHyphen())
                {
                    const scalar_index = paragraph.scalarIndexForByte(
                        source_glyph.cluster,
                    ) orelse return false;
                    if (scalar_index < scalar_start or
                        scalar_index >= scalar_end)
                    {
                        return false;
                    }
                }
            }
        }
        previous_end = glyph_end;
    }

    const scratch = &buffer.bidi_reorder_scratch;
    if (source_is_simple)
        try scratch.beginMonotoneSingleOwningRun(
            buffer.allocator,
            &buffer.glyphs,
        )
    else
        try scratch.beginSingleOwningRun(
            buffer.allocator,
            &buffer.glyphs,
        );
    var transaction_open = true;
    errdefer if (transaction_open) {
        scratch.rollbackSingleOwningRun(&buffer.glyphs);
    };
    // Reserve every fallible line-local append before line metadata changes.
    // The output glyph capacity was likewise reserved by `beginSingleOwningRun`,
    // so an allocation failure leaves both glyphs and lines in logical order.
    try scratch.line_levels.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );
    try scratch.visual_order.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );
    const old_glyphs = scratch.old_glyphs.items;
    const glyph_cluster_index = if (source_is_simple)
        &.{}
    else
        scratch.glyph_cluster_index.items;
    const seen = scratch.seen.items;
    const visual_glyphs = &buffer.glyphs;
    const font = run_types.fontForBackend(run);

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
            if (!source_is_simple) {
                for (old_glyphs[old_line_start..old_line_end]) |source_glyph| {
                    if (!source_glyph.isDiscretionaryHyphen() or
                        source_glyph.isAutomaticHyphen())
                    {
                        continue;
                    }
                    retained_x9[0] = paragraph.scalarIndexForByte(
                        source_glyph.cluster,
                    ).?;
                    retained_x9_count = 1;
                    break;
                }
            }
            try paragraph.visualOrderAndLevelsRetaining(
                buffer.allocator,
                scalar_start,
                scalar_end,
                retained_x9[0..retained_x9_count],
                &scratch.line_levels,
                &scratch.visual_order,
            );
            for (scratch.visual_order.items) |scalar_index| {
                const scalar = paragraph.scalars[scalar_index];
                const level = scratch.line_levels.items[
                    scalar_index - scalar_start
                ];
                const item: unicode.BidiMapItem = .{
                    .logical_index = scalar_index,
                    .visual_index = 0,
                    .byte_start = scalar.byte_start,
                    .byte_len = scalar.byte_len,
                    .codepoint = scalar.codepoint,
                    .visual_codepoint = if (level & 1 != 0 and
                        bidi.mayHaveBidiMirror(scalar.codepoint))
                        unicode.mirroredCodepoint(scalar.codepoint)
                    else
                        scalar.codepoint,
                    .direction = if (level & 1 != 0) .rtl else .ltr,
                };
                try mapping.appendItemSingleRunMode(
                    source_is_simple,
                    buffer.allocator,
                    old_glyphs,
                    font,
                    glyph_cluster_index,
                    seen,
                    old_line_start,
                    old_line_end,
                    item,
                    visual_glyphs,
                );
            }
        }
        try mapping.appendUnseenSingleRun(
            buffer.allocator,
            old_glyphs,
            font,
            seen,
            old_line_start,
            old_line_end,
            visual_glyphs,
        );
        line.glyph_start = visual_start;
        line.glyph_len = visual_glyphs.items.len - visual_start;
        line.run_start = 0;
        line.run_len = @intFromBool(line.glyph_len != 0);
    }

    // Wrapping whitespace outside visible line ranges remains a stable logical
    // suffix, exactly as in the general mapper.
    try mapping.appendUnseenSingleRun(
        buffer.allocator,
        old_glyphs,
        font,
        seen,
        0,
        old_glyphs.len,
        visual_glyphs,
    );
    if (visual_glyphs.items.len != old_glyphs.len) {
        return error.InvalidBidiMap;
    }

    transaction_open = false;
    return true;
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
                        .visual_codepoint = if (level & 1 != 0 and
                            bidi.mayHaveBidiMirror(scalar.codepoint))
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

test "single owning run resolved path matches general mixed bidi mapping" {
    const output = @import("../../../shaping/context/output.zig");
    const paragraph_types = @import("../../types/paragraph.zig");
    const test_font = @import("../../../test_font.zig");

    const allocator = std.testing.allocator;
    const font_bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Mixed Mirror Sans",
        "Regular",
        "Mixed Mirror Sans Regular",
    );
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();

    // The blank after each visible range models wrapping whitespace retained
    // in the source line's byte range but excluded from its glyph range.
    const text = "(אב) A (אב) A ";
    const logical_glyphs = [_]GlyphPosition{
        .{ .glyph_id = try font.glyphIndex('('), .codepoint = '(', .cluster = 0, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d0), .codepoint = 0x05d0, .cluster = 1, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d1), .codepoint = 0x05d1, .cluster = 3, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(')'), .codepoint = ')', .cluster = 5, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = ' ', .cluster = 6, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = 'A', .cluster = 7, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = ' ', .cluster = 8, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex('('), .codepoint = '(', .cluster = 9, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d0), .codepoint = 0x05d0, .cluster = 10, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d1), .codepoint = 0x05d1, .cluster = 12, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(')'), .codepoint = ')', .cluster = 14, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = ' ', .cluster = 15, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = 'A', .cluster = 16, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = ' ', .cluster = 17, .source_byte_len = 1, .x_advance = 1 },
    };
    const logical_lines = [_]paragraph_types.ParagraphLine{
        .{ .glyph_start = 0, .glyph_len = 6, .run_start = 0, .run_len = 1, .byte_start = 0, .byte_len = 9, .x = 0, .y = 0, .width = 6, .height = 1, .baseline = 1, .ascent = 1, .descent = 0, .leading = 0 },
        .{ .glyph_start = 7, .glyph_len = 6, .run_start = 0, .run_len = 1, .byte_start = 9, .byte_len = 9, .x = 0, .y = 1, .width = 6, .height = 1, .baseline = 1, .ascent = 1, .descent = 0, .leading = 0 },
    };
    const logical_run = run_types.CascadeRun{
        .font = @import("../../../font/face/root.zig").backend.face(&font),
        .font_index = 0,
        .font_size = 12,
        .glyph_start = 0,
        .glyph_len = logical_glyphs.len,
        .x_offset = 0,
    };

    var paragraph = try unicode.resolveBidiParagraph(
        allocator,
        text,
        .rtl,
    );
    defer paragraph.deinit();
    var expected = output.Buffer.init(allocator);
    defer expected.deinit();
    try expected.glyphs.appendSlice(allocator, &logical_glyphs);
    try expected.runs.append(allocator, logical_run);
    try expected.lines.appendSlice(allocator, &logical_lines);
    try applyLinesResolved(&expected, paragraph);

    var actual = output.Buffer.init(allocator);
    defer actual.deinit();
    try actual.glyphs.appendSlice(allocator, &logical_glyphs);
    try actual.runs.append(allocator, logical_run);
    try actual.lines.appendSlice(allocator, &logical_lines);
    try std.testing.expect(
        try applyLinesResolvedSingleRun(&actual, paragraph, false),
    );

    try std.testing.expectEqualSlices(
        GlyphPosition,
        expected.glyphs.items,
        actual.glyphs.items,
    );
    try std.testing.expectEqualSlices(
        run_types.CascadeRun,
        expected.runs.items,
        actual.runs.items,
    );
    try std.testing.expectEqualSlices(
        paragraph_types.ParagraphLine,
        expected.lines.items,
        actual.lines.items,
    );
    try std.testing.expectEqual(@as(usize, 0), actual.runs.items[0].glyph_start);
    try std.testing.expectEqual(logical_glyphs.len, actual.runs.items[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), actual.bidi_reorder_scratch.old_runs.capacity);
    try std.testing.expectEqual(@as(usize, 0), actual.bidi_reorder_scratch.glyph_run_indices.capacity);
    try std.testing.expectEqual(@as(usize, 0), actual.bidi_reorder_scratch.visual_run_indices.capacity);
    // The RTL bracket pair is mirrored while the LTR scalar makes the source
    // genuinely mixed, rather than eligible for pure-RTL reversal.
    try std.testing.expectEqual(@as(u21, '('), actual.glyphs.items[2].codepoint);
    try std.testing.expectEqual(@as(usize, 5), actual.glyphs.items[2].cluster);
    try std.testing.expectEqual(@as(u21, ')'), actual.glyphs.items[5].codepoint);
    try std.testing.expectEqual(@as(usize, 0), actual.glyphs.items[5].cluster);
    try std.testing.expectEqual(@as(u21, ' '), actual.glyphs.items[12].codepoint);
    try std.testing.expectEqual(@as(u21, ' '), actual.glyphs.items[13].codepoint);
}

test "monotone single owning run matches generic clusters ligature X9 and gaps" {
    const output = @import("../../../shaping/context/output.zig");
    const paragraph_types = @import("../../types/paragraph.zig");
    const test_font = @import("../../../test_font.zig");

    const allocator = std.testing.allocator;
    const font_bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Monotone Mirror Sans",
        "Regular",
        "Monotone Mirror Sans Regular",
    );
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();

    // U+202B and U+202C are removed by X9, but their deliberately retained
    // glyph outputs must survive through the mapper's unmatched-output rule.
    // Cluster 5 expands to two outputs, while cluster 15 spans both bytes of
    // the synthetic "fi" ligature. Spaces at glyph indexes 9 and 11 are
    // wrapping gaps outside visible lines.
    const text = "A \u{202b}(אב)\u{202c} fi B \u{202b}(אב)\u{202c}";
    const logical_glyphs = [_]GlyphPosition{
        .{ .glyph_id = 100, .codepoint = 'A', .cluster = 0, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 101, .codepoint = ' ', .cluster = 1, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 102, .codepoint = 0x202b, .cluster = 2, .source_byte_len = 3, .x_advance = 0 },
        .{ .glyph_id = try font.glyphIndex('('), .codepoint = '(', .cluster = 5, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 104, .codepoint = '(', .cluster = 5, .source_byte_len = 1, .x_advance = 0 },
        .{ .glyph_id = try font.glyphIndex(0x05d0), .codepoint = 0x05d0, .cluster = 6, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d1), .codepoint = 0x05d1, .cluster = 8, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(')'), .codepoint = ')', .cluster = 10, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 108, .codepoint = 0x202c, .cluster = 11, .source_byte_len = 3, .x_advance = 0 },
        .{ .glyph_id = 109, .codepoint = ' ', .cluster = 14, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 110, .codepoint = 'f', .cluster = 15, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = 111, .codepoint = ' ', .cluster = 17, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 112, .codepoint = 'B', .cluster = 18, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 113, .codepoint = ' ', .cluster = 19, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 114, .codepoint = 0x202b, .cluster = 20, .source_byte_len = 3, .x_advance = 0 },
        .{ .glyph_id = try font.glyphIndex('('), .codepoint = '(', .cluster = 23, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d0), .codepoint = 0x05d0, .cluster = 24, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d1), .codepoint = 0x05d1, .cluster = 26, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(')'), .codepoint = ')', .cluster = 28, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 119, .codepoint = 0x202c, .cluster = 29, .source_byte_len = 3, .x_advance = 0 },
    };
    const logical_lines = [_]paragraph_types.ParagraphLine{
        .{ .glyph_start = 0, .glyph_len = 9, .run_start = 0, .run_len = 1, .byte_start = 0, .byte_len = 15, .x = 0, .y = 0, .width = 6, .height = 1, .baseline = 1, .ascent = 1, .descent = 0, .leading = 0 },
        .{ .glyph_start = 10, .glyph_len = 1, .run_start = 0, .run_len = 1, .byte_start = 15, .byte_len = 3, .x = 0, .y = 1, .width = 1, .height = 1, .baseline = 1, .ascent = 1, .descent = 0, .leading = 0 },
        .{ .glyph_start = 12, .glyph_len = 8, .run_start = 0, .run_len = 1, .byte_start = 18, .byte_len = 14, .x = 0, .y = 2, .width = 6, .height = 1, .baseline = 1, .ascent = 1, .descent = 0, .leading = 0 },
    };
    const logical_run = run_types.CascadeRun{
        .font = @import("../../../font/face/root.zig").backend.face(&font),
        .font_index = 0,
        .font_size = 12,
        .glyph_start = 0,
        .glyph_len = logical_glyphs.len,
        .x_offset = 0,
    };

    var paragraph = try unicode.resolveBidiParagraph(allocator, text, .ltr);
    defer paragraph.deinit();
    // Mirror the preparation-time simple stream proof in this hand-built
    // fixture: equal clusters are contiguous, each later cluster begins at the
    // widest preceding source end, and the final output reaches text.len.
    var expected_byte_start: usize = 0;
    var active_cluster: ?usize = null;
    for (logical_glyphs) |glyph| {
        const source_end = glyph.sourceByteEnd();
        if (active_cluster != null and glyph.cluster == active_cluster.?) {
            expected_byte_start = @max(expected_byte_start, source_end);
            continue;
        }
        try std.testing.expectEqual(expected_byte_start, glyph.cluster);
        try std.testing.expect(source_end > glyph.cluster);
        active_cluster = glyph.cluster;
        expected_byte_start = source_end;
    }
    try std.testing.expectEqual(text.len, expected_byte_start);
    for (logical_lines) |line| {
        const byte_end = line.byte_start + line.byte_len;
        for (logical_glyphs[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
            try std.testing.expect(glyph.cluster >= line.byte_start);
            try std.testing.expect(glyph.cluster < byte_end);
        }
    }
    var expected = output.Buffer.init(allocator);
    defer expected.deinit();
    try expected.glyphs.appendSlice(allocator, &logical_glyphs);
    try expected.runs.append(allocator, logical_run);
    try expected.lines.appendSlice(allocator, &logical_lines);
    try applyLinesResolved(&expected, paragraph);

    var actual = output.Buffer.init(allocator);
    defer actual.deinit();
    try actual.glyphs.appendSlice(allocator, &logical_glyphs);
    try actual.runs.append(allocator, logical_run);
    try actual.lines.appendSlice(allocator, &logical_lines);
    try std.testing.expect(
        try applyLinesResolvedSingleRun(&actual, paragraph, true),
    );

    try std.testing.expectEqualSlices(
        GlyphPosition,
        expected.glyphs.items,
        actual.glyphs.items,
    );
    try std.testing.expectEqualSlices(
        run_types.CascadeRun,
        expected.runs.items,
        actual.runs.items,
    );
    try std.testing.expectEqualSlices(
        paragraph_types.ParagraphLine,
        expected.lines.items,
        actual.lines.items,
    );
    try std.testing.expectEqual(@as(usize, 0), actual.bidi_reorder_scratch.glyph_cluster_index.items.len);
    try std.testing.expectEqual(@as(usize, 0), actual.bidi_reorder_scratch.glyph_cluster_index.capacity);
}

test "single owning run rejects invalid later-line source before mutation" {
    const output = @import("../../../shaping/context/output.zig");
    const paragraph_types = @import("../../types/paragraph.zig");
    const test_font = @import("../../../test_font.zig");

    const allocator = std.testing.allocator;
    const font_bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Rollback Mirror Sans",
        "Regular",
        "Rollback Mirror Sans Regular",
    );
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();

    const text = " (אב) A";
    const logical_glyphs = [_]GlyphPosition{
        .{ .glyph_id = 0, .codepoint = ' ', .cluster = 0, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex('('), .codepoint = '(', .cluster = 1, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d0), .codepoint = 0x05d0, .cluster = 2, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(0x05d1), .codepoint = 0x05d1, .cluster = 4, .source_byte_len = 2, .x_advance = 1 },
        .{ .glyph_id = try font.glyphIndex(')'), .codepoint = ')', .cluster = 6, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = 'A', .cluster = 8, .source_byte_len = 1, .x_advance = 1 },
        .{ .glyph_id = 0, .codepoint = 0x00ad, .cluster = 3, .source_byte_len = 1, .x_advance = 1, .flags = .{ .discretionary_hyphen = true } },
    };
    const logical_lines = [_]paragraph_types.ParagraphLine{
        .{ .glyph_start = 1, .glyph_len = 4, .run_start = 0, .run_len = 1, .byte_start = 1, .byte_len = 6, .x = 3, .y = 4, .indent = 5, .width = 4, .height = 10, .baseline = 7, .ascent = 8, .descent = 2, .leading = 1 },
        .{ .glyph_start = 5, .glyph_len = 2, .run_start = 0, .run_len = 1, .byte_start = 7, .byte_len = 2, .x = 13, .y = 14, .indent = 15, .width = 2, .height = 20, .baseline = 17, .ascent = 18, .descent = 2, .leading = 1 },
    };
    const logical_run = run_types.CascadeRun{
        .font = @import("../../../font/face/root.zig").backend.face(&font),
        .font_index = 0,
        .font_size = 12,
        .glyph_start = 0,
        .glyph_len = logical_glyphs.len,
        .x_offset = 0,
    };

    var paragraph = try unicode.resolveBidiParagraph(allocator, text, .rtl);
    defer paragraph.deinit();
    var actual = output.Buffer.init(allocator);
    defer actual.deinit();
    try actual.glyphs.appendSlice(allocator, &logical_glyphs);
    try actual.runs.append(allocator, logical_run);
    try actual.lines.appendSlice(allocator, &logical_lines);

    try std.testing.expect(
        !try applyLinesResolvedSingleRun(&actual, paragraph, false),
    );
    try std.testing.expectEqualSlices(
        GlyphPosition,
        &logical_glyphs,
        actual.glyphs.items,
    );
    try std.testing.expectEqualSlices(
        paragraph_types.ParagraphLine,
        &logical_lines,
        actual.lines.items,
    );
    try std.testing.expectEqualSlices(
        run_types.CascadeRun,
        &.{logical_run},
        actual.runs.items,
    );
}
