//! Cluster-safe font fallback over an ordered list of parsed faces.
//!
//! Selection is deliberately independent of paragraph/layout orchestration.
//! Callers supply a borrowed cascade and an optional glyph-index cache.

const std = @import("std");

const arabic_normalization = @import("../../../arabic_normalization.zig");
const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const GlyphIndexCache =
    @import("../../context/cache/glyph.zig").GlyphIndexCache;
const unicode = @import("../../../unicode.zig");

pub const Cascade = struct {
    fonts: []const *const Font,
    /// Precomputed rejection filter for cache grouping. Cache hits still
    /// compare every font pointer, so hash collisions cannot alias cascades.
    identity_hash: u64,

    pub fn init(fonts: []const *const Font) Cascade {
        return .{
            .fonts = fonts,
            .identity_hash = cascadeHash(fonts),
        };
    }

    /// Pick the first font that maps the codepoint to a non-zero glyph id.
    /// Glyph id zero is `.notdef` and therefore does not establish coverage.
    pub fn selectFont(self: Cascade, codepoint: u21) !usize {
        return try selectFontFrom(self.fonts, null, codepoint);
    }

    /// Pick one font for a complete, valid UTF-8 shaping cluster.
    pub fn selectFontForCluster(
        self: Cascade,
        cluster: []const u8,
    ) !usize {
        if (!std.unicode.utf8ValidateSlice(cluster)) return error.InvalidUtf8;
        return try selectFontForClusterFrom(self.fonts, null, cluster);
    }
};

pub fn selectFontFrom(
    fonts: []const *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    codepoint: u21,
) !usize {
    if (fonts.len == 0) return error.EmptyFontCascade;
    for (fonts, 0..) |font, index| {
        if (try glyphIndex(font, glyph_index_cache, codepoint) != 0) {
            return index;
        }
    }
    return 0;
}

pub fn selectFontForClusterFrom(
    fonts: []const *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    cluster: []const u8,
) !usize {
    if (fonts.len == 0) return error.EmptyFontCascade;

    if (clusterHasVariationSelector(cluster)) {
        // Prefer a font with explicit/default cmap-14 support for every UVS.
        // Only then fall back to ignoring unsupported selectors.
        for (fonts, 0..) |font, index| {
            if (try fontCoversCluster(
                font,
                glyph_index_cache,
                cluster,
                true,
            )) return index;
        }
    }
    for (fonts, 0..) |font, index| {
        if (try fontCoversCluster(
            font,
            glyph_index_cache,
            cluster,
            false,
        )) return index;
    }

    // If no face covers the entire cluster, retain it in the face selected for
    // its first visible scalar. Missing continuation glyphs then remain
    // diagnosable rather than becoming detached fallback runs.
    var iterator = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (unicode.isVariationSelector(codepoint) or
            isClusterCoverageIgnorable(codepoint))
        {
            continue;
        }
        return try selectFontFrom(fonts, glyph_index_cache, codepoint);
    }
    return 0;
}

pub fn isClusterCoverageIgnorable(codepoint: u21) bool {
    // Join controls and other default-ignorables participate in shaping but do
    // not need nominal cmap glyphs. Variation selectors refine the preceding
    // scalar and are handled separately through cmap format 14.
    return !unicode.isVariationSelector(codepoint) and
        unicode.isDefaultIgnorableForShaping(codepoint);
}

fn clusterHasVariationSelector(cluster: []const u8) bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (unicode.isVariationSelector(codepoint)) return true;
    }
    return false;
}

fn fontCoversCluster(
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    cluster: []const u8,
    require_variation_mapping: bool,
) !bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    var previous_visible: ?u21 = null;
    while (iterator.nextCodepoint()) |codepoint| {
        if (unicode.isVariationSelector(codepoint)) {
            if (!require_variation_mapping) continue;
            const base = previous_visible orelse return false;
            const glyph_id =
                (try font.variationGlyphIndex(base, codepoint)) orelse
                return false;
            if (glyph_id == 0) return false;
            continue;
        }
        if (isClusterCoverageIgnorable(codepoint)) continue;
        if (try arabic_normalization.composeAtForFont(
            font,
            glyph_index_cache,
            codepoint,
            cluster,
            iterator.i,
        )) |composition| {
            iterator.i = composition.byte_end;
            previous_visible = composition.codepoint;
            continue;
        }
        if (try glyphIndex(font, glyph_index_cache, codepoint) == 0) {
            return false;
        }
        previous_visible = codepoint;
    }
    return true;
}

fn glyphIndex(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    codepoint: u21,
) !GlyphId {
    if (cache) |glyph_cache| {
        return try glyph_cache.glyphIndex(font, codepoint);
    }
    return try font.glyphIndex(codepoint);
}

fn cascadeHash(fonts: []const *const Font) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (fonts) |font| {
        const addr = @intFromPtr(font);
        hasher.update(std.mem.asBytes(&addr));
    }
    return hasher.final();
}
