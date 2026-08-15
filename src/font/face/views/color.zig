//! Portable color-glyph assets and COLR/CPAL inspection.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");

pub const View = opaque {
    pub fn layers(
        self: *const View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError![]font_mod.ColorLayer {
        return font(self).colorLayers(allocator, glyph_id);
    }

    pub fn paletteColor(
        self: *const View,
        palette_index: u16,
        color_index: u16,
    ) font_mod.FontError!?font_mod.PaletteColor {
        return font(self).paletteColor(palette_index, color_index);
    }

    pub fn paint(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.ColorPaint {
        return font(self).colorPaintAtCoords(glyph_id, normalized_coords);
    }

    pub fn clip(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.ColorClipBox {
        return font(self).colorClipBoxAtCoords(glyph_id, normalized_coords);
    }

    pub fn svg(
        self: *const View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?font_mod.ResolvedSvgGlyphDocument {
        return font(self).resolvedSvgGlyphDocument(allocator, glyph_id);
    }

    pub fn bitmap(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphPng {
        return font(self).bitmapGlyphPng(glyph_id, size_px);
    }

    pub fn bitmapInfo(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphInfo {
        return font(self).bitmapGlyphInfo(glyph_id, size_px);
    }
};

fn font(view: *const View) *const font_mod.Font {
    return @ptrCast(@alignCast(view));
}
