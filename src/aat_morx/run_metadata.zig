const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;
const gsub = @import("../gsub.zig");
const ligature_provenance = @import("../ligature_provenance.zig");

/// Reverses the complete glyph stream and every post-cmap metadata sidecar.
///
/// AAT coverage flags choose between logical and layout order independently
/// for each subtable. Keeping this operation centralized prevents a temporary
/// direction change from desynchronizing later `morx`, GPOS, or output stages.
pub fn reverse(glyphs: *std.ArrayList(GlyphId), options: gsub.runtime.Options) void {
    reverseSlice(GlyphId, glyphs.items);
    if (options.glyph_source_indices) |values| reverseSlice(usize, values.items);
    if (options.glyph_cluster_indices) |values| reverseSlice(usize, values.items);
    if (options.glyph_substituted) |values| reverseSlice(bool, values.items);
    if (options.glyph_stage_substituted) |values| reverseSlice(bool, values.items);
    if (options.ligature_components) |store| reverseSlice(ligature_provenance.Info, store.infos.items);
}

fn reverseSlice(comptime T: type, values: []T) void {
    std.mem.reverse(T, values);
}
