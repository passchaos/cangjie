//! Horizontal, vertical, and text-decoration metrics.

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");
const global_metrics = @import("global_metrics.zig");

pub const Global = global_metrics.Metrics;

pub const View = struct {
    /// Borrowed source-level view backing; use the methods below.
    implementation: *const font_mod.Font,

    /// Return unscaled design metrics (`null`) or metrics scaled to `size`.
    pub fn global(self: View, size: ?f32) font_mod.FontError!Global {
        return global_metrics.readImmutableFace(self.implementation, size);
    }

    pub fn horizontal(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!font_mod.HorizontalMetricInfo {
        return font_mod.immutable_face_backend.horizontalMetrics(
            self.implementation,
            glyph_id,
        );
    }

    pub fn horizontalAt(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!font_mod.HorizontalMetricInfo {
        return self.implementation.horizontalMetricsAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn hasVertical(self: View) bool {
        return self.implementation.hasVerticalMetrics();
    }

    pub fn vertical(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?font_mod.VerticalMetrics {
        return self.implementation.verticalMetrics(glyph_id);
    }

    pub fn verticalAt(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!?font_mod.VerticalMetrics {
        return self.implementation.verticalMetricsAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn verticalOrigin(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?i16 {
        return self.implementation.verticalOriginY(glyph_id);
    }

    /// Vertical origin used by shaping when VORG is absent.
    pub fn shapingVerticalOrigin(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!i32 {
        return font_mod.shaping.verticalOriginYAtCoords(
            self.implementation,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn decoration(
        self: View,
    ) font_mod.FontError!font_mod.FontDecorationMetrics {
        return self.implementation.decorationMetrics();
    }

    /// Resolve one OpenType MVAR value tag in design units.
    pub fn variationDelta(
        self: View,
        value_tag: [4]u8,
        normalized_coords: []const f32,
    ) font_mod.FontError!?i32 {
        return self.implementation.mvarDeltaAtCoords(
            value_tag,
            normalized_coords,
        );
    }
};
