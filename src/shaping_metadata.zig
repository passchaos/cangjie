const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");

pub const ClusterLevel = enum(u2) {
    monotone_graphemes = 0,
    monotone_characters = 1,
    characters = 2,
    graphemes = 3,

    pub fn isMonotone(self: ClusterLevel) bool {
        return self == .monotone_graphemes or self == .monotone_characters;
    }

    pub fn groupsGraphemes(self: ClusterLevel) bool {
        return self == .monotone_graphemes or self == .graphemes;
    }

    pub fn usesCharacterClusters(self: ClusterLevel) bool {
        return self == .monotone_characters or self == .characters;
    }
};

/// Moves one glyph while preserving every array that carries post-cmap shaping
/// metadata. Keeping this operation centralized prevents script shapers from
/// silently desynchronizing cluster ownership or ligature attachment sources.
pub fn move(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    from: usize,
    to: usize,
) void {
    assertParallelLengths(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
    );
    std.debug.assert(from < glyph_ids.items.len);
    std.debug.assert(to < glyph_ids.items.len);
    if (from == to) return;

    if (from < to) {
        var index = from;
        while (index < to) : (index += 1) {
            swap(
                glyph_ids.items,
                glyph_source_indices.items,
                glyph_cluster_indices.items,
                glyph_substituted.items,
                ligature_components.infos.items,
                index,
                index + 1,
            );
        }
    } else {
        var index = from;
        while (index > to) {
            swap(
                glyph_ids.items,
                glyph_source_indices.items,
                glyph_cluster_indices.items,
                glyph_substituted.items,
                ligature_components.infos.items,
                index,
                index - 1,
            );
            index -= 1;
        }
    }
}

pub fn swap(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []ligature_provenance.Info,
    a: usize,
    b: usize,
) void {
    const len = glyph_ids.len;
    std.debug.assert(glyph_source_indices.len == len);
    std.debug.assert(glyph_cluster_indices.len == len);
    std.debug.assert(glyph_substituted.len == len);
    std.debug.assert(ligature_components.len == len);
    std.debug.assert(a < len and b < len);

    std.mem.swap(GlyphId, &glyph_ids[a], &glyph_ids[b]);
    std.mem.swap(usize, &glyph_source_indices[a], &glyph_source_indices[b]);
    std.mem.swap(usize, &glyph_cluster_indices[a], &glyph_cluster_indices[b]);
    std.mem.swap(bool, &glyph_substituted[a], &glyph_substituted[b]);
    std.mem.swap(ligature_provenance.Info, &ligature_components[a], &ligature_components[b]);
}

/// Merges a glyph range at a monotone cluster level without splitting an
/// existing cluster at either boundary. GSUB and script reorder both widen
/// clusters, so centralizing the boundary extension keeps their metadata
/// semantics identical when one stage merges through a range produced by the
/// other.
pub fn mergeMonotoneClusters(clusters: []usize, start_index: usize, end_index: usize) void {
    if (start_index >= clusters.len) return;
    var start = start_index;
    var end = @min(end_index, clusters.len);
    if (end <= start + 1) return;

    var merged = clusters[start];
    for (clusters[start..end]) |cluster| {
        merged = @min(merged, cluster);
    }

    if (merged != clusters[end - 1]) {
        while (end < clusters.len and clusters[end - 1] == clusters[end]) {
            end += 1;
        }
    }
    if (merged != clusters[start]) {
        while (start > 0 and clusters[start - 1] == clusters[start]) {
            start -= 1;
        }
    }
    @memset(clusters[start..end], merged);
}

pub fn mergeClusterRange(clusters: []usize, start_index: usize, end_index: usize) void {
    if (start_index >= clusters.len) return;
    const end = @min(end_index, clusters.len);
    if (end <= start_index + 1) return;

    var merged = clusters[start_index];
    for (clusters[start_index..end]) |cluster| {
        merged = @min(merged, cluster);
    }
    @memset(clusters[start_index..end], merged);
}

pub fn insert(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    index: usize,
    glyph_id: GlyphId,
    source_index: usize,
    cluster_owner: usize,
) std.mem.Allocator.Error!void {
    assertParallelLengths(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
    );
    std.debug.assert(index <= glyph_ids.items.len);

    try glyph_ids.replaceRange(allocator, index, 0, &.{glyph_id});
    errdefer _ = glyph_ids.orderedRemove(index);

    try glyph_source_indices.replaceRange(allocator, index, 0, &.{source_index});
    errdefer _ = glyph_source_indices.orderedRemove(index);

    try glyph_cluster_indices.replaceRange(allocator, index, 0, &.{cluster_owner});
    errdefer _ = glyph_cluster_indices.orderedRemove(index);

    try glyph_substituted.replaceRange(allocator, index, 0, &.{false});
    errdefer _ = glyph_substituted.orderedRemove(index);

    try ligature_components.infos.replaceRange(
        allocator,
        index,
        0,
        &.{.{}},
    );
}

fn assertParallelLengths(
    glyph_ids: *const std.ArrayList(GlyphId),
    glyph_source_indices: *const std.ArrayList(usize),
    glyph_cluster_indices: *const std.ArrayList(usize),
    glyph_substituted: *const std.ArrayList(bool),
    ligature_components: *const ligature_provenance.Store,
) void {
    const len = glyph_ids.items.len;
    std.debug.assert(glyph_source_indices.items.len == len);
    std.debug.assert(glyph_cluster_indices.items.len == len);
    std.debug.assert(glyph_substituted.items.len == len);
    std.debug.assert(ligature_components.infos.items.len == len);
}

test "monotone cluster merge extends through existing boundary clusters" {
    var clusters = [_]usize{ 0, 2, 2, 2, 5 };

    mergeMonotoneClusters(&clusters, 0, 3);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 5 }, &clusters);
}
