//! Glyph shaping requests, options, results, and diagnostics.

const layout = @import("../../layout.zig");
const unicode = @import("../../unicode.zig");
const context = @import("../../shaping/context/root.zig");

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
    pub const fontFallback = layout.diagnoseFontFallbackUtf8;
    pub const caretConsistency = layout.diagnoseClusterCaretConsistencyUtf8;
    pub const quality = layout.diagnoseShapeQualityUtf8;
};
