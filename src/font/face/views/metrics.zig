//! Horizontal, vertical, and text-decoration metrics.

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");

pub const View = opaque {
    pub fn horizontal(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!font_mod.HorizontalMetricInfo {
        return font(self).horizontalMetrics(glyph_id);
    }

    pub fn horizontalAt(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!font_mod.HorizontalMetricInfo {
        return font(self).horizontalMetricsAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn hasVertical(self: *const View) bool {
        return font(self).hasVerticalMetrics();
    }

    pub fn vertical(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?font_mod.VerticalMetrics {
        return font(self).verticalMetrics(glyph_id);
    }

    pub fn verticalAt(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.VerticalMetrics {
        return font(self).verticalMetricsAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn verticalOrigin(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?i16 {
        return font(self).verticalOriginY(glyph_id);
    }

    /// Vertical origin used by shaping when VORG is absent.
    pub fn shapingVerticalOrigin(
        self: *const View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!i32 {
        return font_mod.shaping.verticalOriginYAtCoords(
            font(self),
            glyph_id,
            normalized_coords,
        );
    }

    pub fn decoration(
        self: *const View,
    ) font_mod.FontError!font_mod.FontDecorationMetrics {
        return font(self).decorationMetrics();
    }
};

fn font(view: *const View) *const font_mod.Font {
    return @ptrCast(@alignCast(view));
}
