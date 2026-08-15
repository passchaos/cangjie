//! Thai/Lao SARA AM decomposition before script shaping.

const Font = @import("../../../font.zig").Font;
const cache_mod = @import("../../context/cache/root.zig");
const GlyphIndexCache = cache_mod.GlyphIndexCache;
const scratch_mod = @import("../../context/scratch.zig");
const shaping_metadata = @import("../../../shaping_metadata.zig");
const unicode = @import("../../../unicode.zig");
const source_buffer = @import("buffer.zig");
const support = @import("support.zig");

pub fn usesPreprocess(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .thai or script_tag == .lao;
}

pub fn isSaraAm(codepoint: u21) bool {
    return (codepoint & ~@as(u21, 0x80)) == 0x0e33;
}

pub fn isClusterExtender(codepoint: u21) bool {
    const normalized = codepoint & ~@as(u21, 0x80);
    return normalized == 0x0e31 or
        (normalized >= 0x0e34 and normalized <= 0x0e3a) or
        (normalized >= 0x0e47 and normalized <= 0x0e4e);
}

pub fn appendSaraAm(
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    scratch: *scratch_mod.ShapeScratch,
    codepoint: u21,
    local_cluster: usize,
    cluster_base: usize,
    local_source_end: usize,
    requested_cluster_level: anytype,
) !void {
    const cluster_level =
        requested_cluster_level orelse .monotone_graphemes;
    const source_cluster = if (cluster_level.groupsGraphemes() and
        scratch.clusters.items.len != 0)
        scratch.clusters.items[scratch.clusters.items.len - 1] - cluster_base
    else
        local_cluster;
    const nikhahit = codepoint - 0x0e33 + 0x0e4d;
    const sara_aa = codepoint - 1;
    const source_end = cluster_base + local_source_end;
    const owner = if (source_cluster != local_cluster and
        scratch.glyph_cluster_indices.items.len != 0)
        scratch.glyph_cluster_indices.items[
            scratch.glyph_cluster_indices.items.len - 1
        ]
    else
        scratch.glyph_cluster_indices.items.len;

    const nikhahit_index = scratch.glyph_ids.items.len;
    source_buffer.append(
        scratch,
        try support.fallbackGlyphIndex(font, glyph_index_cache, nikhahit),
        nikhahit,
        cluster_base + source_cluster,
        source_end,
        owner,
    );
    source_buffer.append(
        scratch,
        try support.fallbackGlyphIndex(font, glyph_index_cache, sara_aa),
        sara_aa,
        cluster_base + source_cluster,
        source_end,
        owner,
    );

    var destination = nikhahit_index;
    while (destination > 0) {
        const previous_source =
            scratch.glyph_source_indices.items[destination - 1];
        if (previous_source >= scratch.codepoints.items.len or
            !isAboveBaseMark(scratch.codepoints.items[previous_source]))
        {
            break;
        }
        destination -= 1;
    }
    if (destination != nikhahit_index) {
        shaping_metadata.move(
            &scratch.glyph_ids,
            &scratch.glyph_source_indices,
            &scratch.glyph_cluster_indices,
            &scratch.glyph_substituted,
            &scratch.ligature_components,
            nikhahit_index,
            destination,
        );
    }
    const merge_end = scratch.glyph_ids.items.len;
    if (destination < merge_end and
        destination < scratch.glyph_cluster_indices.items.len and
        cluster_level.isMonotone())
    {
        shaping_metadata.mergeMonotoneClusters(
            scratch.glyph_cluster_indices.items,
            destination,
            merge_end,
        );
    }
    const grapheme_start = if (destination > 0) destination - 1 else 0;
    if (grapheme_start < merge_end and cluster_level.groupsGraphemes()) {
        if (cluster_level.isMonotone()) {
            shaping_metadata.mergeMonotoneClusters(
                scratch.glyph_cluster_indices.items,
                grapheme_start,
                merge_end,
            );
        } else {
            shaping_metadata.mergeClusterRange(
                scratch.glyph_cluster_indices.items,
                grapheme_start,
                merge_end,
            );
        }
    }
}

fn isAboveBaseMark(codepoint: u21) bool {
    const normalized = codepoint & ~@as(u21, 0x80);
    return (normalized >= 0x0e34 and normalized <= 0x0e37) or
        (normalized >= 0x0e47 and normalized <= 0x0e4e) or
        normalized == 0x0e31 or
        normalized == 0x0e3b;
}
