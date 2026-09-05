//! Glyph shaping requests, options, results, and diagnostics.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const glyph_position = @import("../../layout/glyph_position.zig");
const run_types = @import("../../layout/types/runs.zig");
const cache = @import("../../shaping/context/cache/root.zig");
const context = @import("../../shaping/context/root.zig");
const shaping_diagnostics = @import("../../shaping/diagnostics/root.zig");
const diagnostic_types = shaping_diagnostics.types;
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const ordinary_shaper = @import("../../shaping/orchestrator.zig").TextShaper;
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const unicode = @import("../../unicode.zig");

/// Reusable owner of shaping, fallback, paragraph output, and font-derived
/// caches. One engine serves one worker at a time; returned views remain valid
/// until its next operation.
pub const Engine = context.Engine;
pub const Request = context.ShapeRequest;
pub const TextRequest = context.CascadeRequest;
pub const Options = shaping_plan.ShapeOptions;
pub const Direction = pipeline_types.TextDirection;
pub const WritingMode = pipeline_types.WritingMode;
pub const Orientation = pipeline_types.TextOrientation;
pub const ScriptPosition = pipeline_types.ScriptPosition;
pub const ClusterLevel = pipeline_types.ClusterLevel;
pub const Feature = unicode.FeatureOverride;
pub const FeatureRange = unicode.GsubFeatureRange;

pub const Metrics = cache.GlyphMetrics;
pub const Glyph = glyph_position.GlyphPosition;
pub const GlyphOrientation = glyph_position.Orientation;
pub const Run = run_types.GlyphRun;
pub const FontRun = run_types.CascadeRun;
pub const Text = run_types.ShapedText;
pub const ScriptRun = run_types.ScriptedRun;
pub const ItemizedText = run_types.ScriptedText;

pub const FontFallbackDecision = diagnostic_types.FontFallbackDecision;
pub const MissingGlyphDiagnostic = diagnostic_types.MissingGlyphDiagnostic;
pub const QualityFontRunDiagnostic =
    diagnostic_types.ShapeQualityFontRunDiagnostic;
pub const QualityScriptRunDiagnostic =
    diagnostic_types.ShapeQualityScriptRunDiagnostic;
pub const QualityReport = diagnostic_types.ShapeQualityReport;
pub const CaretIssueKind = diagnostic_types.ClusterCaretIssueKind;
pub const CaretDiagnostic = diagnostic_types.ClusterCaretDiagnostic;
pub const CaretConsistencyReport =
    diagnostic_types.ClusterCaretConsistencyReport;

pub const diagnostics = struct {
    pub fn fontFallback(
        allocator: std.mem.Allocator,
        cascade: face_mod.Cascade,
        text: []const u8,
    ) ![]FontFallbackDecision {
        return shaping_diagnostics.fallback.analyze(
            allocator,
            try internalCascade(cascade),
            text,
        );
    }

    pub fn caretConsistency(
        allocator: std.mem.Allocator,
        cascade: face_mod.Cascade,
        text: []const u8,
        font_size: f32,
        options: Options,
    ) !CaretConsistencyReport {
        return shaping_diagnostics.orchestration.clusterCaretConsistency(
            ordinary_shaper,
            allocator,
            try internalCascade(cascade),
            text,
            font_size,
            options,
        );
    }

    pub fn quality(
        allocator: std.mem.Allocator,
        cascade: face_mod.Cascade,
        text: []const u8,
        font_size: f32,
        options: Options,
    ) !QualityReport {
        return shaping_diagnostics.orchestration.shapeQuality(
            ordinary_shaper,
            allocator,
            try internalCascade(cascade),
            text,
            font_size,
            options,
        );
    }

    fn internalCascade(cascade: face_mod.Cascade) !font_fallback.Cascade {
        const result = font_fallback.Cascade.initWithLocations(
            face_mod.backend.fonts(cascade.faces),
            cascade.normalized_variation_locations,
        );
        try result.validateLocations();
        return result;
    }
};
