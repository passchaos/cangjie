const std = @import("std");
const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const GlyphIndexCache =
    @import("shaping/context/cache/glyph.zig").GlyphIndexCache;

pub const Composition = struct {
    codepoint: u21,
    glyph_id: GlyphId,
};

pub const CompositionMatch = struct {
    codepoint: u21,
    glyph_id: GlyphId,
    byte_end: usize,
};

pub fn composePair(starter: u21, mark: u21) ?u21 {
    return switch (starter) {
        0x0627 => switch (mark) {
            0x0653 => 0x0622,
            0x0654 => 0x0623,
            0x0655 => 0x0625,
            else => null,
        },
        0x0648 => if (mark == 0x0654) 0x0624 else null,
        0x064a => if (mark == 0x0654) 0x0626 else null,
        0x06d5 => if (mark == 0x0654) 0x06c0 else null,
        0x06c1 => if (mark == 0x0654) 0x06c2 else null,
        0x06d2 => if (mark == 0x0654) 0x06d3 else null,
        else => null,
    };
}

pub fn canStartComposition(starter: u21) bool {
    return switch (starter) {
        0x0627, 0x0648, 0x064a, 0x06d5, 0x06c1, 0x06d2 => true,
        else => false,
    };
}

pub fn composePairForFont(font: *const Font, cache: ?*GlyphIndexCache, starter: u21, mark: u21) !?Composition {
    const composed = composePair(starter, mark) orelse return null;
    const glyph_id = if (cache) |glyph_cache|
        try glyph_cache.glyphIndex(font, composed)
    else
        try font.glyphIndex(composed);
    if (glyph_id == 0) return null;
    return .{ .codepoint = composed, .glyph_id = glyph_id };
}

/// Compose the starter with the scalar beginning at `mark_byte_start` when the
/// selected font contains the canonical precomposed glyph.
pub fn composeAtForFont(
    font: *const Font,
    cache: ?*GlyphIndexCache,
    starter: u21,
    text: []const u8,
    mark_byte_start: usize,
) !?CompositionMatch {
    if (!canStartComposition(starter) or mark_byte_start >= text.len) {
        return null;
    }
    var lookahead =
        std.unicode.Utf8Iterator{ .bytes = text, .i = mark_byte_start };
    const mark = lookahead.nextCodepoint() orelse return null;
    const composition = try composePairForFont(
        font,
        cache,
        starter,
        mark,
    ) orelse return null;
    return .{
        .codepoint = composition.codepoint,
        .glyph_id = composition.glyph_id,
        .byte_end = lookahead.i,
    };
}

test "Arabic canonical pairs compose to Unicode precomposed scalars" {
    try std.testing.expectEqual(@as(?u21, 0x0622), composePair(0x0627, 0x0653));
    try std.testing.expectEqual(@as(?u21, 0x0623), composePair(0x0627, 0x0654));
    try std.testing.expectEqual(@as(?u21, 0x0624), composePair(0x0648, 0x0654));
    try std.testing.expectEqual(@as(?u21, 0x0625), composePair(0x0627, 0x0655));
    try std.testing.expectEqual(@as(?u21, 0x0626), composePair(0x064a, 0x0654));
    try std.testing.expectEqual(@as(?u21, 0x06c0), composePair(0x06d5, 0x0654));
    try std.testing.expectEqual(@as(?u21, 0x06c2), composePair(0x06c1, 0x0654));
    try std.testing.expectEqual(@as(?u21, 0x06d3), composePair(0x06d2, 0x0654));
    try std.testing.expectEqual(@as(?u21, null), composePair(0x0628, 0x0654));
    try std.testing.expect(canStartComposition(0x0627));
    try std.testing.expect(!canStartComposition(0x0628));
}
