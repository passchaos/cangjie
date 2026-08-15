//! Cmap lookup, presentation forms, and initial cluster classification.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const arabic_normalization = @import("../../../arabic_normalization.zig");
const cache_mod = @import("../../context/cache/root.zig");
const GlyphIndexCache = cache_mod.GlyphIndexCache;
const space_fallback = @import("../../../space_fallback.zig");
const unicode = @import("../../../unicode.zig");
const unicode_glyph_fallback = @import("../../../unicode_glyph_fallback.zig");

pub const ArabicCompositionMatch = struct {
    codepoint: u21,
    glyph_id: GlyphId,
    byte_end: usize,
};

pub fn arabicCompositionForFontAt(
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    starter: u21,
    text: []const u8,
    mark_byte_start: usize,
) !?ArabicCompositionMatch {
    if (!arabic_normalization.canStartComposition(starter) or
        mark_byte_start >= text.len)
    {
        return null;
    }
    var lookahead =
        std.unicode.Utf8Iterator{ .bytes = text, .i = mark_byte_start };
    const mark = lookahead.nextCodepoint() orelse return null;
    const composition = try arabic_normalization.composePairForFont(
        font,
        glyph_index_cache,
        starter,
        mark,
    ) orelse return null;
    return .{
        .codepoint = composition.codepoint,
        .glyph_id = composition.glyph_id,
        .byte_end = lookahead.i,
    };
}

pub fn glyphIndex(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    codepoint: u21,
) !GlyphId {
    if (cache) |glyph_cache| {
        return try glyph_cache.glyphIndex(font, codepoint);
    }
    return try font.glyphIndex(codepoint);
}

pub fn fallbackGlyphIndex(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    codepoint: u21,
) !GlyphId {
    const glyph = try glyphIndex(font, cache, codepoint);
    if (glyph != 0) return glyph;
    if (space_fallback.mayUseSpaceGlyphFallback(codepoint)) {
        const space_glyph = try glyphIndex(font, cache, ' ');
        if (space_glyph != 0) return space_glyph;
    }
    return (try unicode_glyph_fallback.glyphForMissingCodepoint(
        font,
        codepoint,
    )) orelse glyph;
}

pub fn presentationCodepoint(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    codepoint: u21,
    options: anytype,
) !u21 {
    if (options.writing_mode.isVertical()) {
        const vertical_source = if (options.writing_mode == .vertical_lr)
            unicode.mirroredCodepoint(codepoint)
        else
            codepoint;
        if (unicode.verticalPresentationCodepoint(vertical_source)) |vertical| {
            if (try glyphIndex(font, cache, vertical) != 0) return vertical;
        }
        return codepoint;
    }
    if (options.direction != .rtl) return codepoint;
    const mirrored = unicode.mirroredCodepoint(codepoint);
    if (mirrored == codepoint) return codepoint;
    return if (try glyphIndex(font, cache, mirrored) != 0)
        mirrored
    else
        codepoint;
}

pub fn resolveInvisibleGlyph(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    stored: *?GlyphId,
) !GlyphId {
    if (stored.*) |glyph| return glyph;
    const glyph = try glyphIndex(font, cache, ' ');
    stored.* = glyph;
    return glyph;
}

pub fn isDecimalNumber(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

pub fn isLetter(codepoint: u21) bool {
    if (isDecimalNumber(codepoint) or
        unicode.isUnicodeMarkCodepoint(codepoint) or
        unicode.isDefaultIgnorableForShaping(codepoint) or
        isFormatControl(codepoint))
    {
        return false;
    }
    return switch (unicode.bidiClassForCodepoint(codepoint)) {
        .ltr, .rtl => true,
        else => false,
    };
}

pub fn inheritsLeadingDefaultIgnorableCluster(
    codepoints: []const u21,
    clusters: []const usize,
    invisible_glyph_id: GlyphId,
) bool {
    return codepoints.len == 1 and clusters.len == 1 and
        invisible_glyph_id == 0 and
        unicode.isDefaultIgnorableForShaping(codepoints[0]) and
        unicode.joiningTypeForCodepoint(codepoints[0]) != .join_causing;
}

pub fn inheritsPreviousZwnjCluster(
    rtl: bool,
    prior_codepoints: []const u21,
    invisible_glyph_id: GlyphId,
) bool {
    return rtl and invisible_glyph_id == 0 and
        prior_codepoints.len != 0 and
        prior_codepoints[prior_codepoints.len - 1] == 0x200c;
}

pub fn isTibetanExtender(codepoint: u21) bool {
    return codepoint == 0x0f35 or
        codepoint == 0x0f37 or
        codepoint == 0x0f39 or
        (codepoint >= 0x0f71 and codepoint <= 0x0f84) or
        (codepoint >= 0x0f86 and codepoint <= 0x0f87) or
        (codepoint >= 0x0f8d and codepoint <= 0x0f97) or
        (codepoint >= 0x0f99 and codepoint <= 0x0fbc) or
        codepoint == 0x0fc6;
}

fn isFormatControl(codepoint: u21) bool {
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or
        codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2 or
        codepoint == 0x0d4e or
        codepoint == 0x110bd or
        codepoint == 0x110cd;
}

test "RTL source after ZWNJ inherits the join-control cluster" {
    try std.testing.expect(inheritsPreviousZwnjCluster(
        true,
        &.{ 0x0628, 0x200c },
        0,
    ));
    try std.testing.expect(!inheritsPreviousZwnjCluster(
        true,
        &.{ 0x0628, 0x200c },
        3,
    ));
    try std.testing.expect(!inheritsPreviousZwnjCluster(
        false,
        &.{ 0x0628, 0x200c },
        0,
    ));
}
