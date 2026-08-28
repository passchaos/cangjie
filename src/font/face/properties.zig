//! Core scalar properties shared by lightweight and fully validated faces.

const font_mod = @import("../../font.zig");

pub const Properties = struct {
    format: font_mod.FontFormat,
    units_per_em: u16,
    glyph_count: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
};
