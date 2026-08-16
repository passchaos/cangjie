//! OpenType variable-font axes, instances, deltas, and composite records.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

pub const Axis = font.VariationAxis;
pub const Coordinate = font.VariationCoordinate;
pub const Instance = font.VariationInstance;
pub const StatAxis = font.StatDesignAxis;
pub const StatValue = font.StatAxisValue;
pub const StatCoordinate = font.StatAxisValueCoordinate;

pub const GlyphVariations = font.GvarInfo;
pub const GlyphVariation = font.GvarGlyphInfo;
pub const Tuple = font.GvarTupleInfo;
pub const PointDelta = font.GvarScaledPointDelta;
pub const PhantomPointDeltas = font.GvarPhantomPointDeltas;
pub const ControlValueVariations = font.CvarInfo;
pub const ControlValueTuple = font.CvarTupleInfo;

pub const HorizontalMetrics = font.HvarInfo;
pub const VerticalMetrics = font.VvarInfo;
pub const Metrics = font.MvarInfo;
pub const MetricValue = font.MvarValueRecordInfo;
pub const MetricIndexMap = font.MetricVariationIndexMapInfo;
pub const MetricIndex = font.MetricVariationIndexMapEntryInfo;
pub const Composite = font.VarcInfo;

/// Borrowed table-level variable-font inspection view.
///
/// Common fvar/avar operations remain on `Face.variations()`. This view
/// exposes lower-level gvar/cvar/metric-variation/STAT/VARC data without
/// widening the normal face completion list.
pub const Inspection = struct {
    face: *const face_mod.Face,

    fn implementation(self: Inspection) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn glyphVariations(self: Inspection) font.FontError!?GlyphVariations {
        return self.implementation().gvarInfo();
    }

    pub fn glyphVariation(
        self: Inspection,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?GlyphVariation {
        return self.implementation().gvarGlyphInfo(glyph_id);
    }

    pub fn tuple(
        self: Inspection,
        glyph_id: glyph.GlyphId,
        tuple_index: usize,
    ) font.FontError!?Tuple {
        return self.implementation().gvarTupleInfo(
            glyph_id,
            tuple_index,
        );
    }

    pub fn pointDeltas(
        self: Inspection,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?[]PointDelta {
        return self.implementation().gvarPointDeltasAtCoords(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn phantomPointDeltas(
        self: Inspection,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?PhantomPointDeltas {
        return self.implementation().gvarPhantomPointDeltasAtCoords(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn controlValues(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]i16 {
        return self.implementation().cvtValues(allocator);
    }

    pub fn controlValueVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?ControlValueVariations {
        return self.implementation().cvarInfo(allocator);
    }

    pub fn freeControlValueVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: ControlValueVariations,
    ) void {
        self.implementation().freeCvarInfo(allocator, info);
    }

    pub fn horizontalMetrics(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?HorizontalMetrics {
        return self.implementation().hvarInfo(allocator);
    }

    pub fn freeHorizontalMetrics(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: HorizontalMetrics,
    ) void {
        self.implementation().freeHvarInfo(allocator, info);
    }

    pub fn horizontalAdvanceDelta(
        self: Inspection,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?i32 {
        return self.implementation().hvarAdvanceWidthDeltaAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn horizontalRightBearingDelta(
        self: Inspection,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?i32 {
        return self.implementation().hvarRightSideBearingDeltaAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn verticalMetrics(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?VerticalMetrics {
        return self.implementation().vvarInfo(allocator);
    }

    pub fn freeVerticalMetrics(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: VerticalMetrics,
    ) void {
        self.implementation().freeVvarInfo(allocator, info);
    }

    pub fn verticalAdvanceDelta(
        self: Inspection,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?i32 {
        return self.implementation().vvarAdvanceHeightDeltaAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn verticalBottomBearingDelta(
        self: Inspection,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?i32 {
        return self.implementation().vvarBottomSideBearingDeltaAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn metricVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?Metrics {
        return self.implementation().mvarInfo(allocator);
    }

    pub fn freeMetricVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: Metrics,
    ) void {
        self.implementation().freeMvarInfo(allocator, info);
    }

    pub fn statElidedFallbackNameId(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?u16 {
        return self.implementation().statElidedFallbackNameId(allocator);
    }

    pub fn statAxes(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]StatAxis {
        return self.implementation().statDesignAxes(allocator);
    }

    pub fn statValues(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]StatValue {
        return self.implementation().statAxisValues(allocator);
    }

    pub fn freeStatValues(
        self: Inspection,
        allocator: std.mem.Allocator,
        values: []StatValue,
    ) void {
        self.implementation().freeStatAxisValues(allocator, values);
    }

    pub fn compositeVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?Composite {
        return self.implementation().varcInfo(allocator);
    }

    pub fn freeCompositeVariations(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: Composite,
    ) void {
        self.implementation().freeVarcInfo(allocator, info);
    }
};

pub fn inspect(face: *const face_mod.Face) Inspection {
    return .{ .face = face };
}
