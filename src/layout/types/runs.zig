//! Public shaped glyph and run records.

const std = @import("std");
const face_mod = @import("../../font/face/root.zig");
const Face = face_mod.Face;
const Font = @import("../../font.zig").Font;
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const unicode = @import("../../unicode.zig");

/// A contiguous range of glyphs rendered by one font at one size.
pub const GlyphRun = struct {
    font: *const Face,
    font_size: f32,
    glyphs: []const GlyphPosition,
    /// Normalized fvar coordinates in the owning font's axis order.
    ///
    /// Like `glyphs`, this slice borrows the shaping output owner.
    normalized_variation_coords: []const f32 = &.{},

    pub fn width(self: GlyphRun) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.x_advance;
        return total;
    }

    pub fn height(self: GlyphRun) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.y_advance;
        return total;
    }
};

pub fn initGlyphRun(
    font: *const Font,
    font_size: f32,
    glyphs: []const GlyphPosition,
    normalized_variation_coords: []const f32,
) GlyphRun {
    return .{
        .font = face_mod.backend.face(font),
        .font_size = font_size,
        .glyphs = glyphs,
        .normalized_variation_coords = normalized_variation_coords,
    };
}

/// A subrange of the shaped glyph stream selected from a font cascade.
/// Multiple cascade runs can exist inside a single paragraph line.
pub const CascadeRun = struct {
    font: *const Face,
    font_index: usize,
    font_size: f32,
    glyph_start: usize,
    glyph_len: usize,
    x_offset: f32,
    y_offset: f32 = 0,
    /// Range in `ShapedText.normalized_variation_coords`.
    variation_coord_start: usize = 0,
    variation_coord_len: usize = 0,

    pub fn glyphs(self: CascadeRun, shaped: ShapedText) []const GlyphPosition {
        return shaped.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }

    pub fn glyphRun(self: CascadeRun, shaped: ShapedText) GlyphRun {
        return .{
            .font = self.font,
            .font_size = self.font_size,
            .glyphs = self.glyphs(shaped),
            .normalized_variation_coords = self.normalizedVariationCoords(shaped),
        };
    }

    pub fn normalizedVariationCoords(
        self: CascadeRun,
        shaped: ShapedText,
    ) []const f32 {
        const end = self.variation_coord_start + self.variation_coord_len;
        std.debug.assert(end <= shaped.normalized_variation_coords.len);
        return shaped.normalized_variation_coords[self.variation_coord_start..end];
    }
};

/// Internal bridge for layout/raster modules. Keeping this off the public
/// record's method set prevents implementation fonts from leaking through
/// `cangjie.shaping.FontRun`.
pub fn fontForBackend(run: CascadeRun) *const Font {
    return face_mod.backend.font(run.font);
}

/// Flat shaping result. Glyphs are stored once, while runs describe which font
/// owns each contiguous range.
pub const ShapedText = struct {
    glyphs: []const GlyphPosition,
    runs: []const CascadeRun,
    /// Flat owner for every run's normalized variation coordinate range.
    normalized_variation_coords: []const f32 = &.{},

    pub fn width(self: ShapedText) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.x_advance;
        return total;
    }

    pub fn height(self: ShapedText) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.y_advance;
        return total;
    }
};

pub const ScriptedRun = struct {
    script: unicode.Script,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,

    pub fn glyphs(self: ScriptedRun, text: ScriptedText) []const GlyphPosition {
        return text.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }
};

pub const ScriptedText = struct {
    glyphs: []const GlyphPosition,
    font_runs: []const CascadeRun,
    script_runs: []const ScriptedRun,
    normalized_variation_coords: []const f32 = &.{},
};
