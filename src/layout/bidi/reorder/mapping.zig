//! Mapping Unicode bidi items to shaped glyph clusters.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const run_types = @import("../../types/runs.zig");
const unicode = @import("../../../unicode.zig");

pub const ClusterEntry = struct {
    cluster: usize,
    glyph_index: usize,
};

pub fn buildClusterIndex(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
) ![]ClusterEntry {
    var entries = std.ArrayList(ClusterEntry).empty;
    errdefer entries.deinit(allocator);
    try buildClusterIndexInto(allocator, &entries, glyphs);
    return try entries.toOwnedSlice(allocator);
}

pub fn buildClusterIndexInto(
    allocator: std.mem.Allocator,
    entries: *std.ArrayList(ClusterEntry),
    glyphs: []const GlyphPosition,
) !void {
    entries.clearRetainingCapacity();
    try entries.resize(allocator, glyphs.len);
    var monotone = true;
    for (glyphs, entries.items, 0..) |glyph, *entry, glyph_index| {
        // A generated hyphen is logically inserted at a source boundary and
        // intentionally keeps that boundary as its public caret cluster. For
        // bidi permutation only, attach it to the preceding source atom: LTR
        // emits it after that atom and RTL emits it before, which is exactly
        // the visual line-end behavior of a discretionary hyphen.
        const visual_cluster =
            if (glyph.isAutomaticHyphen() and glyph_index != 0)
                glyphs[glyph_index - 1].cluster
            else
                glyph.cluster;
        entry.* = .{
            .cluster = visual_cluster,
            .glyph_index = glyph_index,
        };
        if (glyph_index != 0 and
            visual_cluster < entries.items[glyph_index - 1].cluster)
        {
            monotone = false;
        }
    }
    // Common shaping preserves monotone clusters, making this already sorted.
    // Script reordering needs the stable cluster/index tie-break below.
    if (monotone) return;
    std.sort.heap(ClusterEntry, entries.items, {}, entryLessThan);
}

pub fn appendItem(
    comptime record_permutation: bool,
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    cluster_index: []const ClusterEntry,
    seen: []bool,
    allowed_start: usize,
    allowed_end: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: ?*std.ArrayList(usize),
    out_permutation: if (record_permutation) *std.ArrayList(usize) else void,
) !void {
    const item_range =
        clusterRange(cluster_index, item.byte_start) orelse return;
    if (item.direction == .rtl) {
        var entry_index = item_range.end;
        while (entry_index > item_range.start) {
            entry_index -= 1;
            const glyph_index = cluster_index[entry_index].glyph_index;
            if (glyph_index < allowed_start or glyph_index >= allowed_end or
                seen[glyph_index])
            {
                continue;
            }
            try appendItemGlyph(
                record_permutation,
                allocator,
                glyphs,
                old_runs,
                single_font,
                glyph_run_indices,
                seen,
                glyph_index,
                item,
                out_glyphs,
                out_run_indices,
                out_permutation,
            );
        }
        return;
    }

    for (cluster_index[item_range.start..item_range.end]) |entry| {
        const glyph_index = entry.glyph_index;
        if (glyph_index < allowed_start or glyph_index >= allowed_end or
            seen[glyph_index])
        {
            continue;
        }
        try appendItemGlyph(
            record_permutation,
            allocator,
            glyphs,
            old_runs,
            single_font,
            glyph_run_indices,
            seen,
            glyph_index,
            item,
            out_glyphs,
            out_run_indices,
            out_permutation,
        );
    }
}

/// Append one bidi item when every glyph has the same proven font owner.
///
/// This deliberately shares cluster lookup, intra-cluster ordering, and
/// mirroring with the general mapper. It only erases the run-index sidecar
/// whose value would be zero for every glyph.
pub fn appendItemSingleRun(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    font: *const Font,
    cluster_index: []const ClusterEntry,
    seen: []bool,
    allowed_start: usize,
    allowed_end: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
) !void {
    return appendItem(
        false,
        allocator,
        glyphs,
        &[_]run_types.CascadeRun{},
        font,
        &.{},
        cluster_index,
        seen,
        allowed_start,
        allowed_end,
        item,
        out_glyphs,
        null,
        {},
    );
}

/// Select the indexed or monotone mapper at compile time for one owning run.
/// Keeping this dispatch here makes both paths share the same public inputs and
/// leaves the line-level bidi loop independent of the lookup representation.
pub fn appendItemSingleRunMode(
    comptime source_is_simple: bool,
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    font: *const Font,
    cluster_index: []const ClusterEntry,
    seen: []bool,
    allowed_start: usize,
    allowed_end: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
) !void {
    if (source_is_simple) {
        return appendItemMonotoneSingleRun(
            allocator,
            glyphs,
            font,
            seen,
            allowed_start,
            allowed_end,
            item,
            out_glyphs,
        );
    }
    return appendItemSingleRun(
        allocator,
        glyphs,
        font,
        cluster_index,
        seen,
        allowed_start,
        allowed_end,
        item,
        out_glyphs,
    );
}

/// Append one bidi item from a proven monotone, contiguous cluster stream.
///
/// `source_is_simple` is established while retained shaping output is still
/// immutable: cluster starts strictly increase between source atoms and every
/// output sharing a cluster is adjacent. Restricting the search to the current
/// old line slice is important because wrapping whitespace may leave gaps
/// between visible lines. Once the equal-cluster range is found, emission uses
/// the exact general helpers so RTL intra-cluster order and mirroring remain
/// byte-for-byte equivalent. The caller has reserved room for every old glyph,
/// so these shared fallible appends cannot allocate during line mutation.
fn appendItemMonotoneSingleRun(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    font: *const Font,
    seen: []bool,
    allowed_start: usize,
    allowed_end: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
) !void {
    const item_range = monotoneClusterRange(
        glyphs,
        allowed_start,
        allowed_end,
        item.byte_start,
    ) orelse return;
    if (item.direction == .rtl) {
        var glyph_index = item_range.end;
        while (glyph_index > item_range.start) {
            glyph_index -= 1;
            if (seen[glyph_index]) continue;
            try appendItemGlyph(
                false,
                allocator,
                glyphs,
                &[_]run_types.CascadeRun{},
                font,
                &.{},
                seen,
                glyph_index,
                item,
                out_glyphs,
                null,
                {},
            );
        }
        return;
    }

    for (item_range.start..item_range.end) |glyph_index| {
        if (seen[glyph_index]) continue;
        try appendItemGlyph(
            false,
            allocator,
            glyphs,
            &[_]run_types.CascadeRun{},
            font,
            &.{},
            seen,
            glyph_index,
            item,
            out_glyphs,
            null,
            {},
        );
    }
}

pub fn appendUnseen(
    comptime record_permutation: bool,
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    start: usize,
    end: usize,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: ?*std.ArrayList(usize),
    out_permutation: if (record_permutation) *std.ArrayList(usize) else void,
) !void {
    for (start..@min(end, glyphs.len)) |glyph_index| {
        if (seen[glyph_index]) continue;
        try appendGlyph(
            record_permutation,
            allocator,
            glyphs,
            old_runs,
            single_font,
            glyph_run_indices,
            seen,
            glyph_index,
            null,
            out_glyphs,
            out_run_indices,
            out_permutation,
        );
    }
}

/// Preserve unmatched outputs for a single owning run.
pub fn appendUnseenSingleRun(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    font: *const Font,
    seen: []bool,
    start: usize,
    end: usize,
    out_glyphs: *std.ArrayList(GlyphPosition),
) !void {
    return appendUnseen(
        false,
        allocator,
        glyphs,
        &[_]run_types.CascadeRun{},
        font,
        &.{},
        seen,
        start,
        end,
        out_glyphs,
        null,
        {},
    );
}

fn entryLessThan(_: void, lhs: ClusterEntry, rhs: ClusterEntry) bool {
    if (lhs.cluster == rhs.cluster) return lhs.glyph_index < rhs.glyph_index;
    return lhs.cluster < rhs.cluster;
}

fn clusterRange(
    entries: []const ClusterEntry,
    cluster: usize,
) ?struct { start: usize, end: usize } {
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (entries[mid].cluster < cluster) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    const start = low;
    while (low < entries.len and entries[low].cluster == cluster) {
        low += 1;
    }
    if (start == low) return null;
    return .{ .start = start, .end = low };
}

fn monotoneClusterRange(
    glyphs: []const GlyphPosition,
    allowed_start: usize,
    allowed_end: usize,
    cluster: usize,
) ?struct { start: usize, end: usize } {
    const end = @min(allowed_end, glyphs.len);
    if (allowed_start >= end) return null;

    var low = allowed_start;
    var high = end;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (glyphs[mid].cluster < cluster) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    const start = low;
    while (low < end and glyphs[low].cluster == cluster) low += 1;
    if (start == low) return null;
    return .{ .start = start, .end = low };
}

fn appendItemGlyph(
    comptime record_permutation: bool,
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    glyph_index: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: ?*std.ArrayList(usize),
    out_permutation: if (record_permutation) *std.ArrayList(usize) else void,
) !void {
    const glyph = glyphs[glyph_index];
    const visual_codepoint =
        if (!glyph.isDiscretionaryHyphen() and
        @max(glyph.source_byte_len, 1) == item.byte_len)
            item.visual_codepoint
        else
            null;
    return try appendGlyph(
        record_permutation,
        allocator,
        glyphs,
        old_runs,
        single_font,
        glyph_run_indices,
        seen,
        glyph_index,
        visual_codepoint,
        out_glyphs,
        out_run_indices,
        out_permutation,
    );
}

fn appendGlyph(
    comptime record_permutation: bool,
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    glyph_index: usize,
    visual_codepoint: ?u21,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: ?*std.ArrayList(usize),
    out_permutation: if (record_permutation) *std.ArrayList(usize) else void,
) !void {
    seen[glyph_index] = true;
    const glyph = visualizedGlyph(
        glyphs[glyph_index],
        if (out_run_indices == null)
            single_font
        else owner: {
            const run_index = glyph_run_indices[glyph_index];
            break :owner if (run_index == @import("runs.zig").no_run or
                run_index >= old_runs.len)
                null
            else
                run_types.fontForBackend(old_runs[run_index]);
        },
        visual_codepoint,
    );
    try out_glyphs.append(allocator, glyph);
    if (out_run_indices) |indices| {
        try indices.append(allocator, glyph_run_indices[glyph_index]);
    }
    if (record_permutation) out_permutation.appendAssumeCapacity(glyph_index);
}

/// Copy one positioned glyph while applying UAX #9 mirroring in its owner.
///
/// Mirroring happens after GSUB/GPOS. A missing mirrored cmap entry therefore
/// preserves the original positioned glyph rather than changing its owner or
/// recomputing any positioning delta.
pub fn visualizedGlyph(
    source: GlyphPosition,
    font: ?*const Font,
    visual_codepoint: ?u21,
) GlyphPosition {
    var glyph = source;
    if (visual_codepoint) |codepoint| mirror: {
        if (codepoint == glyph.codepoint) break :mirror;
        const owning_font = font orelse break :mirror;
        // The font was parsed and remains immutable for the shaping/layout
        // transaction. Reuse that proof rather than revalidating the complete
        // cmap checksum for every mirrored scalar.
        const mirrored_glyph = @import("../../../font.zig").shaping
            .glyphIndexForShaping(owning_font, codepoint) catch break :mirror;
        if (mirrored_glyph == 0) break :mirror;
        // Mirroring happens after GSUB/GPOS. Retain positioning deltas while
        // selecting the mirrored glyph from the same cascade font.
        glyph.codepoint = codepoint;
        glyph.glyph_id = mirrored_glyph;
    }
    return glyph;
}

test "cluster index repairs non-monotone output" {
    const monotone = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 3, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
    };
    const monotone_index = try buildClusterIndex(
        std.testing.allocator,
        &monotone,
    );
    defer std.testing.allocator.free(monotone_index);
    try std.testing.expectEqualSlices(ClusterEntry, &.{
        .{ .cluster = 0, .glyph_index = 0 },
        .{ .cluster = 0, .glyph_index = 1 },
        .{ .cluster = 2, .glyph_index = 2 },
    }, monotone_index);

    const reordered = [_]GlyphPosition{
        .{ .glyph_id = 3, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
    };
    const reordered_index = try buildClusterIndex(
        std.testing.allocator,
        &reordered,
    );
    defer std.testing.allocator.free(reordered_index);
    try std.testing.expectEqualSlices(ClusterEntry, &.{
        .{ .cluster = 0, .glyph_index = 1 },
        .{ .cluster = 0, .glyph_index = 2 },
        .{ .cluster = 2, .glyph_index = 0 },
    }, reordered_index);
}

test "monotone cluster range is line local and keeps equal outputs contiguous" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = ' ', .cluster = 1, .x_advance = 1 },
        .{ .glyph_id = 3, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
        .{ .glyph_id = 4, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
        .{ .glyph_id = 5, .codepoint = ' ', .cluster = 3, .x_advance = 1 },
        .{ .glyph_id = 6, .codepoint = 'C', .cluster = 4, .x_advance = 1 },
    };

    const pair = monotoneClusterRange(&glyphs, 2, 4, 2).?;
    try std.testing.expectEqual(@as(usize, 2), pair.start);
    try std.testing.expectEqual(@as(usize, 4), pair.end);
    try std.testing.expect(monotoneClusterRange(&glyphs, 2, 4, 0) == null);
    try std.testing.expect(monotoneClusterRange(&glyphs, 5, 6, 3) == null);
    try std.testing.expect(monotoneClusterRange(&glyphs, 4, 4, 3) == null);
}
