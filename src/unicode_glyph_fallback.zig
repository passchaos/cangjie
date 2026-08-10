const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;

pub fn glyphForMissingCodepoint(font: *const Font, codepoint: u21) !?GlyphId {
    if (codepoint != 0x2011) return null;

    const hyphen = try font.glyphIndex(0x2010);
    return if (hyphen != 0) hyphen else null;
}
