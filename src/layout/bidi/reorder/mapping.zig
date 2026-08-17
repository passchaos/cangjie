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
    const entries = try allocator.alloc(ClusterEntry, glyphs.len);
    var monotone = true;
    for (glyphs, entries, 0..) |glyph, *entry, glyph_index| {
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
            visual_cluster < entries[glyph_index - 1].cluster)
        {
            monotone = false;
        }
    }
    // Common shaping preserves monotone clusters, making this already sorted.
    // Script reordering needs the stable cluster/index tie-break below.
    if (monotone) return entries;
    std.sort.heap(ClusterEntry, entries, {}, entryLessThan);
    return entries;
}

pub fn appendItem(
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
    out_run_indices: *std.ArrayList(usize),
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
        );
    }
}

pub fn appendUnseen(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    start: usize,
    end: usize,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    for (start..@min(end, glyphs.len)) |glyph_index| {
        if (seen[glyph_index]) continue;
        try appendGlyph(
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
        );
    }
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

fn appendItemGlyph(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    glyph_index: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    const glyph = glyphs[glyph_index];
    const visual_codepoint =
        if (!glyph.isAutomaticHyphen() and
        @max(glyph.source_byte_len, 1) == item.byte_len)
            item.visual_codepoint
        else
            null;
    return try appendGlyph(
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
    );
}

fn appendGlyph(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: anytype,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    glyph_index: usize,
    visual_codepoint: ?u21,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    seen[glyph_index] = true;
    var glyph = glyphs[glyph_index];
    if (visual_codepoint) |codepoint| mirror: {
        if (codepoint == glyph.codepoint) break :mirror;
        const run_index = glyph_run_indices[glyph_index];
        if (run_index == @import("runs.zig").no_run) break :mirror;
        const font = if (run_index < old_runs.len)
            run_types.fontForBackend(old_runs[run_index])
        else
            single_font orelse break :mirror;
        const mirrored_glyph = font.glyphIndex(codepoint) catch break :mirror;
        if (mirrored_glyph == 0) break :mirror;
        // Mirroring happens after GSUB/GPOS. Retain positioning deltas while
        // selecting the mirrored glyph from the same cascade font.
        glyph.codepoint = codepoint;
        glyph.glyph_id = mirrored_glyph;
    }
    try out_glyphs.append(allocator, glyph);
    try out_run_indices.append(allocator, glyph_run_indices[glyph_index]);
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
