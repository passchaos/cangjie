//! Shared value records and prefix-sum helpers for vertical wrapping.

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;

pub const Range = struct {
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
};

pub const SoftCandidate = struct {
    /// Visible glyph prefix; boundary whitespace can make this smaller than
    /// `next_glyph_start`.
    glyph_end: usize,
    next_glyph_start: usize,
    byte_end: usize,
};

pub fn fillPrefix(prefix: []f32, glyphs: []const GlyphPosition) void {
    prefix[0] = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        prefix[glyph_index + 1] = prefix[glyph_index] + glyph.y_advance;
    }
}

pub fn advance(prefix: []const f32, start: usize, end: usize) f32 {
    return prefix[end] - prefix[start];
}
