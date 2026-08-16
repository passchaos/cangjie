//! Horizontal, vertical, decoration, and script metric records.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

pub const Decoration = font.FontDecorationMetrics;
pub const DecorationSource = font.FontDecorationMetricSource;
pub const ScaledDecoration = font.ScaledFontDecorationMetrics;
pub const Script = font.FontScriptMetrics;
pub const ScaledScript = font.ScaledFontScriptMetrics;

pub const Header = font.MetricHeaderInfo;
pub const Horizontal = font.HorizontalMetricInfo;
pub const Vertical = font.VerticalMetricInfo;
pub const VerticalMetrics = font.VerticalMetrics;
pub const VerticalOrigins = font.VerticalOriginInfo;
pub const VerticalOrigin = font.VerticalOriginMetric;

pub const DeviceWidths = font.HdmxInfo;
pub const DeviceWidthRecord = font.HdmxRecord;
pub const LinearThresholds = font.LtshInfo;

/// Borrowed metric-table inspection view. Allocating methods return caller-
/// owned arrays; nested metadata exposes matching free methods.
pub const Inspection = struct {
    face: *const face_mod.Face,

    fn implementation(self: Inspection) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn horizontalHeader(self: Inspection) font.FontError!Header {
        return self.implementation().horizontalHeaderInfo();
    }

    pub fn verticalHeader(self: Inspection) font.FontError!?Header {
        return self.implementation().verticalHeaderInfo();
    }

    pub fn horizontal(
        self: Inspection,
        glyph_id: glyph.GlyphId,
    ) font.FontError!Horizontal {
        return self.implementation().horizontalMetrics(glyph_id);
    }

    pub fn horizontalTable(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]Horizontal {
        return self.implementation().horizontalMetricsTable(allocator);
    }

    pub fn vertical(
        self: Inspection,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?VerticalMetrics {
        return self.implementation().verticalMetrics(glyph_id);
    }

    pub fn verticalTable(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?[]Vertical {
        return self.implementation().verticalMetricsTable(allocator);
    }

    pub fn decoration(self: Inspection) font.FontError!Decoration {
        return self.implementation().decorationMetrics();
    }

    pub fn scaledDecoration(
        self: Inspection,
        font_size: f32,
    ) font.FontError!ScaledDecoration {
        return self.implementation().scaledDecorationMetrics(font_size);
    }

    pub fn script(self: Inspection) font.FontError!?Script {
        return self.implementation().scriptMetrics();
    }

    pub fn scaledScript(
        self: Inspection,
        font_size: f32,
    ) font.FontError!?ScaledScript {
        return self.implementation().scaledScriptMetrics(font_size);
    }

    pub fn deviceWidths(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?DeviceWidths {
        return self.implementation().hdmxInfo(allocator);
    }

    pub fn freeDeviceWidths(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: DeviceWidths,
    ) void {
        self.implementation().freeHdmxInfo(allocator, info);
    }

    pub fn deviceWidth(
        self: Inspection,
        ppem: u8,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?u8 {
        return self.implementation().hdmxWidth(ppem, glyph_id);
    }

    pub fn linearThresholds(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?LinearThresholds {
        return self.implementation().ltshInfo(allocator);
    }

    pub fn freeLinearThresholds(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: LinearThresholds,
    ) void {
        self.implementation().freeLtshInfo(allocator, info);
    }

    pub fn linearThreshold(
        self: Inspection,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?u8 {
        return self.implementation().linearThreshold(glyph_id);
    }

    pub fn verticalOrigins(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?VerticalOrigins {
        return self.implementation().verticalOrigins(allocator);
    }

    pub fn freeVerticalOrigins(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: VerticalOrigins,
    ) void {
        self.implementation().freeVerticalOrigins(allocator, info);
    }

    pub fn verticalOrigin(
        self: Inspection,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?i16 {
        return self.implementation().verticalOriginY(glyph_id);
    }
};

pub fn inspect(face: *const face_mod.Face) Inspection {
    return .{ .face = face };
}
