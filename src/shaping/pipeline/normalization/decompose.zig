//! Font-aware canonical decomposition for missing precomposed source scalars.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const cache_mod = @import("../../context/cache/root.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const scratch_mod = @import("../../context/scratch.zig");
const unicode = @import("../../../unicode.zig");

/// Replace a missing precomposed source with the shortest supported canonical
/// decomposition. This follows HarfBuzz's recursive 1:2 normalizer: an
/// existing cmap glyph remains authoritative, a supported direct left branch
/// stops recursion early, and recursive NFD is the final fallback. Every
/// emitted component retains the original UTF-8 source range.
pub fn missingPrecomposed(
    allocator: std.mem.Allocator,
    font: *const Font,
    glyph_index_cache: ?*cache_mod.GlyphIndexCache,
    scratch: *scratch_mod.ShapeScratch,
) !void {
    var source_index: usize = 0;
    var glyph_index: usize = 0;
    while (source_index < scratch.codepoints.items.len) {
        while (glyph_index < scratch.glyph_source_indices.items.len and
            scratch.glyph_source_indices.items[glyph_index] < source_index)
        {
            glyph_index += 1;
        }
        if (glyph_index >= scratch.glyph_source_indices.items.len or
            scratch.glyph_source_indices.items[glyph_index] != source_index)
        {
            source_index += 1;
            continue;
        }
        if (scratch.glyph_ids.items[glyph_index] != 0) {
            glyph_index += 1;
            source_index += 1;
            continue;
        }
        const codepoint = scratch.codepoints.items[source_index];
        const direct_components = unicode.canonicalDecompositionDirect(
            codepoint,
        ) orelse {
            glyph_index += 1;
            source_index += 1;
            continue;
        };
        if (direct_components.len > 4) {
            glyph_index += 1;
            source_index += 1;
            continue;
        }

        var component_glyphs: [4]GlyphId = undefined;
        const recursive_components =
            unicode.canonicalDecompositionAll(codepoint) orelse
            direct_components;
        const components = if (try mapComponents(
            font,
            glyph_index_cache,
            direct_components,
            &component_glyphs,
        ))
            direct_components
        else if (try mapComponents(
            font,
            glyph_index_cache,
            recursive_components,
            &component_glyphs,
        ))
            recursive_components
        else {
            glyph_index += 1;
            source_index += 1;
            continue;
        };

        const extra = components.len - 1;
        try scratch.codepoints.ensureUnusedCapacity(allocator, extra);
        try scratch.clusters.ensureUnusedCapacity(allocator, extra);
        try scratch.source_ends.ensureUnusedCapacity(allocator, extra);
        try scratch.glyph_ids.ensureUnusedCapacity(allocator, extra);
        try scratch.glyph_source_indices.ensureUnusedCapacity(allocator, extra);
        try scratch.glyph_cluster_indices.ensureUnusedCapacity(allocator, extra);
        try scratch.glyph_substituted.ensureUnusedCapacity(allocator, extra);
        try scratch.ligature_components.infos.ensureUnusedCapacity(
            allocator,
            extra,
        );

        const source_start = scratch.clusters.items[source_index];
        const source_end = scratch.source_ends.items[source_index];
        const cluster_owner = scratch.glyph_cluster_indices.items[glyph_index];
        for (scratch.glyph_source_indices.items) |*source| {
            if (source.* > source_index) source.* += extra;
        }
        for (scratch.glyph_cluster_indices.items) |*owner| {
            if (owner.* > source_index) owner.* += extra;
        }
        scratch.ligature_components.shiftSourceIndices(source_index + 1, extra);

        try scratch.codepoints.replaceRange(
            allocator,
            source_index,
            1,
            components,
        );
        var starts: [4]usize = undefined;
        var ends: [4]usize = undefined;
        var sources: [4]usize = undefined;
        var owners: [4]usize = undefined;
        var substituted: [4]bool = .{ false, false, false, false };
        var infos: [4]ligature_provenance.Info = undefined;
        for (0..components.len) |index| {
            starts[index] = source_start;
            ends[index] = source_end;
            sources[index] = source_index + index;
            owners[index] = cluster_owner;
            infos[index] = .{};
        }
        try scratch.clusters.replaceRange(allocator, source_index, 1, starts[0..components.len]);
        try scratch.source_ends.replaceRange(allocator, source_index, 1, ends[0..components.len]);
        try scratch.glyph_ids.replaceRange(allocator, glyph_index, 1, component_glyphs[0..components.len]);
        try scratch.glyph_source_indices.replaceRange(allocator, glyph_index, 1, sources[0..components.len]);
        try scratch.glyph_cluster_indices.replaceRange(allocator, glyph_index, 1, owners[0..components.len]);
        try scratch.glyph_substituted.replaceRange(allocator, glyph_index, 1, substituted[0..components.len]);
        try scratch.ligature_components.infos.replaceRange(allocator, glyph_index, 1, infos[0..components.len]);
        glyph_index += components.len;
        source_index += components.len;
    }
}

fn mapComponents(
    font: *const Font,
    glyph_index_cache: ?*cache_mod.GlyphIndexCache,
    components: []const u21,
    out: *[4]GlyphId,
) !bool {
    if (components.len > out.len) return false;
    for (components, 0..) |component, index| {
        const glyph = if (glyph_index_cache) |cache|
            try cache.glyphIndex(font, component)
        else
            try font.glyphIndex(component);
        if (glyph == 0) return false;
        out[index] = glyph;
    }
    return true;
}
