//! Primitive appends that keep initial source sidecars exactly parallel.

const GlyphId = @import("../../../glyph.zig").GlyphId;
const scratch_mod = @import("../../context/scratch.zig");

pub fn appendIdentity(
    scratch: *scratch_mod.ShapeScratch,
    glyph_id: GlyphId,
    codepoint: u21,
    cluster: usize,
    source_end: usize,
) void {
    append(
        scratch,
        glyph_id,
        codepoint,
        cluster,
        source_end,
        scratch.glyph_cluster_indices.items.len,
    );
}

pub fn append(
    scratch: *scratch_mod.ShapeScratch,
    glyph_id: GlyphId,
    codepoint: u21,
    cluster: usize,
    source_end: usize,
    cluster_owner: usize,
) void {
    scratch.glyph_ids.appendAssumeCapacity(glyph_id);
    scratch.codepoints.appendAssumeCapacity(codepoint);
    scratch.clusters.appendAssumeCapacity(cluster);
    scratch.source_ends.appendAssumeCapacity(source_end);
    scratch.glyph_source_indices.appendAssumeCapacity(
        scratch.glyph_source_indices.items.len,
    );
    scratch.glyph_cluster_indices.appendAssumeCapacity(cluster_owner);
    scratch.glyph_substituted.appendAssumeCapacity(false);
    scratch.ligature_components.infos.appendAssumeCapacity(.{});
}
