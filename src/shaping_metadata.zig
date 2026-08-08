const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");

/// Moves one glyph while preserving every array that carries post-cmap shaping
/// metadata. Keeping this operation centralized prevents script shapers from
/// silently desynchronizing cluster ownership or ligature attachment sources.
pub fn move(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
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
                ligature_components.items,
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
                ligature_components.items,
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
    ligature_components: []gpos.LigatureComponentInfo,
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
    std.mem.swap(gpos.LigatureComponentInfo, &ligature_components[a], &ligature_components[b]);
}

pub fn insert(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
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

    try ligature_components.replaceRange(
        allocator,
        index,
        0,
        &.{defaultLigatureComponentInfo(source_index)},
    );
}

fn assertParallelLengths(
    glyph_ids: *const std.ArrayList(GlyphId),
    glyph_source_indices: *const std.ArrayList(usize),
    glyph_cluster_indices: *const std.ArrayList(usize),
    glyph_substituted: *const std.ArrayList(bool),
    ligature_components: *const std.ArrayList(gpos.LigatureComponentInfo),
) void {
    const len = glyph_ids.items.len;
    std.debug.assert(glyph_source_indices.items.len == len);
    std.debug.assert(glyph_cluster_indices.items.len == len);
    std.debug.assert(glyph_substituted.items.len == len);
    std.debug.assert(ligature_components.items.len == len);
}

fn defaultLigatureComponentInfo(source: usize) gpos.LigatureComponentInfo {
    var info = gpos.LigatureComponentInfo{};
    info.component_sources[0] = source;
    return info;
}
