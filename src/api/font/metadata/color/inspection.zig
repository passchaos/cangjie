//! COLR/CPAL, SVG, and embedded-bitmap table inspection.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

pub const View = struct {
    face: *const face_mod.Face,

    fn implementation(self: View) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn palettes(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError![]font.PaletteInfo {
        return self.implementation().colorPalettes(allocator);
    }

    pub fn paletteColors(
        self: View,
        allocator: std.mem.Allocator,
        palette_index: u16,
    ) font.FontError![]font.PaletteColor {
        return self.implementation().paletteColors(
            allocator,
            palette_index,
        );
    }

    pub fn paletteEntryLabels(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError![]?u16 {
        return self.implementation().paletteEntryLabels(allocator);
    }

    pub fn layerPaint(
        self: View,
        layer_index: u32,
        normalized_coords: []const f32,
    ) font.FontError!?font.ColorPaint {
        return self.implementation().colorPaintLayerAtCoords(
            layer_index,
            normalized_coords,
        );
    }

    pub fn childPaint(
        self: View,
        child: font.ColorPaint.ChildRef,
        normalized_coords: []const f32,
    ) font.FontError!font.ColorPaint {
        return self.implementation().colorPaintChildAtCoords(
            child,
            normalized_coords,
        );
    }

    pub fn glyphPaint(
        self: View,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?font.ColorPaint {
        return self.implementation().colorGlyphPaintAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn colorStop(
        self: View,
        line: font.ColorPaint.ColorLine,
        index: usize,
        normalized_coords: []const f32,
    ) font.FontError!?font.ColorPaint.ColorStop {
        return self.implementation().colorStopAtCoords(
            line,
            index,
            normalized_coords,
        );
    }

    pub fn colorStops(
        self: View,
        allocator: std.mem.Allocator,
        line: font.ColorPaint.ColorLine,
        normalized_coords: []const f32,
    ) font.FontError![]font.ColorPaint.ColorStop {
        return self.implementation().colorStopsAtCoords(
            allocator,
            line,
            normalized_coords,
        );
    }

    pub fn svg(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?font.SvgGlyphDocument {
        return self.implementation().svgGlyphDocument(glyph_id);
    }

    pub fn resolvedSvg(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?font.ResolvedSvgGlyphDocument {
        return self.implementation().resolvedSvgGlyphDocument(
            allocator,
            glyph_id,
        );
    }

    pub fn bitmapStrikes(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError![]font.BitmapStrikeInfo {
        return self.implementation().bitmapStrikes(allocator);
    }

    pub fn bestBitmapPpem(
        self: View,
        size_px: f32,
    ) font.FontError!?u16 {
        return self.implementation().bestBitmapStrikePpem(size_px);
    }

    pub fn bitmapMask(
        self: View,
        glyph_id: glyph.GlyphId,
        size_px: f32,
    ) font.FontError!?font.BitmapGlyphMask {
        return self.implementation().bitmapGlyphMask(glyph_id, size_px);
    }

    pub fn bitmapBgra(
        self: View,
        glyph_id: glyph.GlyphId,
        size_px: f32,
    ) font.FontError!?font.BitmapGlyphBgra {
        return self.implementation().bitmapGlyphBgra(glyph_id, size_px);
    }

    pub fn bitmapData(
        self: View,
        glyph_id: glyph.GlyphId,
        size_px: f32,
    ) font.FontError!?font.BitmapGlyphData {
        return self.implementation().bitmapGlyphData(glyph_id, size_px);
    }

    pub fn compoundBitmapAlloc(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        size_px: f32,
    ) font.FontError!?font.OwnedBitmapGlyphData {
        return self.implementation().compoundBitmapGlyphAlloc(
            allocator,
            glyph_id,
            size_px,
        );
    }
};

pub fn inspect(face: *const face_mod.Face) View {
    return .{ .face = face };
}
