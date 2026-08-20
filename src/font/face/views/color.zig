//! Portable color-glyph assets and COLR/CPAL inspection.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");

pub const View = struct {
    /// Borrowed source-level view backing; use the methods below.
    implementation: *const font_mod.Font,

    pub fn layers(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError![]font_mod.ColorLayer {
        return self.implementation.colorLayers(allocator, glyph_id);
    }

    pub fn paletteColor(
        self: View,
        palette_index: u16,
        color_index: u16,
    ) font_mod.FontError!?font_mod.PaletteColor {
        return self.implementation.paletteColor(
            palette_index,
            color_index,
        );
    }

    pub fn paint(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.ColorPaint {
        return self.implementation.colorPaintAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn clip(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.ColorClipBox {
        return self.implementation.colorClipBoxAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn svg(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?font_mod.ResolvedSvgGlyphDocument {
        return self.implementation.resolvedSvgGlyphDocument(
            allocator,
            glyph_id,
        );
    }

    pub fn bitmap(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphPng {
        return self.implementation.bitmapGlyphPng(glyph_id, size_px);
    }

    pub fn bitmapInfo(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphInfo {
        return self.implementation.bitmapGlyphInfo(glyph_id, size_px);
    }

    pub fn bitmapBgra(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphBgra {
        return self.implementation.bitmapGlyphBgra(glyph_id, size_px);
    }

    pub fn bitmapData(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphData {
        return font_mod.immutable_face_backend.bitmapGlyphData(
            self.implementation,
            glyph_id,
            size_px,
        );
    }

    pub fn compoundBitmapAlloc(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.OwnedBitmapGlyphData {
        return self.implementation.compoundBitmapGlyphAlloc(
            allocator,
            glyph_id,
            size_px,
        );
    }

    pub fn bitmapMask(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        size_px: f32,
    ) font_mod.FontError!?font_mod.BitmapGlyphMask {
        return self.implementation.bitmapGlyphMask(glyph_id, size_px);
    }
};
