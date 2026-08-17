//! Glyph shaping requests, options, results, and diagnostics.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const layout = @import("../../layout.zig");
const unicode = @import("../../unicode.zig");
const context = @import("../../shaping/context/root.zig");

/// Reusable owner of shaping, fallback, paragraph output, and font-derived
/// caches. One engine serves one worker at a time; returned views remain valid
/// until its next operation.
pub const Engine = context.Engine;
pub const Request = context.ShapeRequest;
pub const TextRequest = context.CascadeRequest;
pub const Options = layout.ShapeOptions;
pub const Direction = layout.TextDirection;
pub const WritingMode = layout.WritingMode;
pub const Orientation = layout.TextOrientation;
pub const ScriptPosition = layout.ScriptPosition;
pub const ClusterLevel = layout.ClusterLevel;
pub const Feature = unicode.FeatureOverride;
pub const FeatureRange = unicode.GsubFeatureRange;

pub const Metrics = layout.GlyphMetrics;
pub const Glyph = layout.GlyphPosition;
pub const Run = layout.GlyphRun;
pub const FontRun = layout.CascadeRun;
pub const Text = layout.ShapedText;
pub const ScriptRun = layout.ScriptedRun;
pub const ItemizedText = layout.ScriptedText;

pub const FontFallbackDecision = layout.FontFallbackDecision;
pub const MissingGlyphDiagnostic = layout.MissingGlyphDiagnostic;
pub const QualityFontRunDiagnostic = layout.ShapeQualityFontRunDiagnostic;
pub const QualityScriptRunDiagnostic = layout.ShapeQualityScriptRunDiagnostic;
pub const QualityReport = layout.ShapeQualityReport;
pub const CaretIssueKind = layout.ClusterCaretIssueKind;
pub const CaretDiagnostic = layout.ClusterCaretDiagnostic;
pub const CaretConsistencyReport = layout.ClusterCaretConsistencyReport;

pub const diagnostics = struct {
    pub fn fontFallback(
        allocator: std.mem.Allocator,
        cascade: face_mod.Cascade,
        text: []const u8,
    ) ![]FontFallbackDecision {
        return layout.diagnoseFontFallbackUtf8(
            allocator,
            internalCascade(cascade),
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
        return layout.diagnoseClusterCaretConsistencyUtf8(
            allocator,
            internalCascade(cascade),
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
        return layout.diagnoseShapeQualityUtf8(
            allocator,
            internalCascade(cascade),
            text,
            font_size,
            options,
        );
    }

    fn internalCascade(cascade: face_mod.Cascade) layout.FontCascade {
        return .init(face_mod.backend.fonts(cascade.faces));
    }
};
