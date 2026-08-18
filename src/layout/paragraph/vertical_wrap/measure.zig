//! Inline-size helpers for vertical wrapping and whitespace edge policy.

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_options = @import("../options.zig");
const white_space = @import("../white_space.zig");

pub fn fillPrefix(prefix: []f32, glyphs: []const GlyphPosition) void {
    prefix[0] = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        prefix[glyph_index + 1] = prefix[glyph_index] + glyph.y_advance;
    }
}

pub fn inlineSize(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    options: paragraph_options.Options,
) f32 {
    return white_space.measureVerticalRange(
        glyphs,
        prefix,
        start,
        end,
        options.white_space_collapse,
    );
}

pub fn firstOverflow(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    glyph_start: usize,
    glyph_end: usize,
    limit: f32,
    options: paragraph_options.Options,
) usize {
    var index = glyph_start + 1;
    while (index <= glyph_end and
        inlineSize(glyphs, prefix, glyph_start, index, options) <= limit)
    {
        index += 1;
    }
    return @min(index, glyph_end);
}
