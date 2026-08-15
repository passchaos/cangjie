//! Arabic/Syriac OpenType `stch` post-processing.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const cache_mod = @import("../../context/cache/root.zig");
const GlyphMetricsCache = cache_mod.GlyphMetricsCache;
const ligature_provenance = @import("../../../ligature_provenance.zig");
const actions = @import("actions.zig");
const stretch = @import("stretch.zig");

pub const recordSubstitutions = actions.recordSubstitutions;
pub const appendOutput = actions.appendOutput;

pub fn apply(
    allocator: std.mem.Allocator,
    glyphs: *std.ArrayList(GlyphPosition),
    stch_actions: []u8,
    segment_start: usize,
    rtl: bool,
    reverse_after_stch: bool,
    scale: f32,
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
) !void {
    if (stch_actions.len == 0) return;
    actions.markContext(glyphs.items[segment_start..], stch_actions);
    return try stretch.apply(
        allocator,
        glyphs,
        stch_actions,
        segment_start,
        rtl,
        reverse_after_stch,
        scale,
        font,
        metrics_cache,
        normalized_variation_coords,
    );
}

test {
    // Ensure action semantics remain instantiated even if a build filters out
    // all layout-level Syriac fixtures.
    _ = ligature_provenance.StchAction.fixed;
}
