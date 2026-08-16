//! Positional cmap fallback for Arabic-family fonts without GSUB.

const font_shaping = @import("../../../../font.zig").shaping;
const cache = @import("../../../context/cache/root.zig");
const Font = @import("../../../../font.zig").Font;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const source_pipeline = @import("../../source/root.zig");
const unicode = @import("../../../../unicode.zig");

pub fn fallbackGlyph(
    font: *const Font,
    glyph_index_cache: ?*cache.GlyphIndexCache,
    glyph_id: GlyphId,
    codepoint: u21,
    source: usize,
    source_features: []const u32,
) !?GlyphId {
    if (font_shaping.hasGsubTableForShaping(
        font,
    )) return null;
    if (source >= source_features.len) return null;
    const fallback_codepoint = fallbackCodepoint(
        codepoint,
        source_features[source],
    ) orelse return null;
    const fallback_glyph = try source_pipeline.glyphIndex(
        font,
        glyph_index_cache,
        fallback_codepoint,
    );
    if (fallback_glyph == 0 or fallback_glyph == glyph_id) return null;
    return fallback_glyph;
}

pub fn fallbackCodepoint(codepoint: u21, source_feature: u32) ?u21 {
    const bare_features =
        source_feature & ~gsub.feature.source_mask_marker;
    const fina_mask =
        gsub.feature.sourceMaskForTag(unicode.tag("fina")).? &
        ~gsub.feature.source_mask_marker;
    const medi_mask =
        gsub.feature.sourceMaskForTag(unicode.tag("medi")).? &
        ~gsub.feature.source_mask_marker;
    if ((bare_features & fina_mask) != 0) {
        return switch (codepoint) {
            0x0627 => 0xfe8e,
            0x06cc => 0xfbfd,
            else => null,
        };
    }
    if ((bare_features & medi_mask) != 0) {
        return switch (codepoint) {
            0x062a => 0xfe98,
            0x0644 => 0xfee0,
            0x0645 => 0xfee4,
            0x06cc => 0xfbff,
            else => null,
        };
    }
    return null;
}

test "positional cmap fallback maps retained Arabic forms" {
    const std = @import("std");
    const fina_mask = gsub.feature.sourceMaskForTag(unicode.tag("fina")).?;
    const medi_mask = gsub.feature.sourceMaskForTag(unicode.tag("medi")).?;

    try std.testing.expectEqual(
        @as(?u21, 0xfe8e),
        fallbackCodepoint(0x0627, fina_mask),
    );
    try std.testing.expectEqual(
        @as(?u21, 0xfee0),
        fallbackCodepoint(0x0644, medi_mask),
    );
    try std.testing.expectEqual(
        @as(?u21, 0xfe98),
        fallbackCodepoint(0x062a, medi_mask),
    );
    try std.testing.expectEqual(
        @as(?u21, null),
        fallbackCodepoint(0x0644, fina_mask),
    );
}
