const std = @import("std");
const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const GlyphIndexCache = @import("layout_cache.zig").GlyphIndexCache;

pub const Composition = struct {
    codepoint: u21,
    glyph_id: GlyphId,
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

pub fn composePairForFont(font: *const Font, cache: ?*GlyphIndexCache, starter: u21, mark: u21) !?Composition {
    const composed = composePair(starter, mark) orelse return null;
    const glyph_id = if (cache) |glyph_cache|
        try glyph_cache.glyphIndex(font, composed)
    else
        try font.glyphIndex(composed);
    if (glyph_id == 0) return null;
    return .{ .codepoint = composed, .glyph_id = glyph_id };
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
}
