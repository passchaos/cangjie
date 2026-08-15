//! Character mapping, glyph geometry, and outline access.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");

pub const View = opaque {
    pub fn index(
        self: *const View,
        codepoint: u21,
    ) font_mod.FontError!glyph_mod.GlyphId {
        return font(self).glyphIndex(codepoint);
    }

    pub fn indexForVariation(
        self: *const View,
        codepoint: u21,
        selector: u21,
    ) font_mod.FontError!?glyph_mod.GlyphId {
        return font(self).glyphIndexWithVariation(codepoint, selector);
    }

    pub fn variationKind(
        self: *const View,
        codepoint: u21,
        selector: u21,
    ) font_mod.FontError!font_mod.VariationSequenceKind {
        return font(self).variationSequenceKind(codepoint, selector);
    }

    pub fn hasOutlines(self: *const View) bool {
        return font(self).hasOutlineData();
    }

    pub fn bounds(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.Bounds {
        return font(self).glyphBounds(glyph_id);
    }

    pub fn boundsAt(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!glyph_mod.Bounds {
        return font(self).glyphBoundsAtCoords(glyph_id, normalized_coords);
    }

    pub fn outline(
        self: *const View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return font(self).glyphOutline(allocator, glyph_id);
    }

    pub fn outlineAt(
        self: *const View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return font(self).glyphOutlineAtCoords(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn name(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?[]const u8 {
        return font(self).glyphName(glyph_id);
    }
};

fn font(view: *const View) *const font_mod.Font {
    return @ptrCast(@alignCast(view));
}
