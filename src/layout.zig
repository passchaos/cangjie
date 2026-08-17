const std = @import("std");
const layout_cache = @import("shaping/context/cache/root.zig");
const context_output = @import("shaping/context/output.zig");
const pipeline_types = @import("shaping/pipeline/types.zig");
const shaping_plan = @import("shaping/plan/root.zig");
const diagnostics = @import("shaping/diagnostics/root.zig");
const diagnostic_fallback = diagnostics.fallback;
const diagnostic_orchestration = diagnostics.orchestration;
const diagnostic_types = diagnostics.types;
const font_fallback = @import("shaping/fallback/font/root.zig");
const glyph_position = @import("layout/glyph_position.zig");
const paragraph_options = @import("layout/paragraph/options.zig");
const retained_paragraph = @import("layout/paragraph/retained.zig");
const paragraph_types = @import("layout/types/paragraph.zig");
const run_types = @import("layout/types/runs.zig");
const paragraph_reflow = @import("layout/line_break/reflow/root.zig");
const styled_buffer = @import("layout/styled_buffer.zig");
const styled_paragraph = @import("layout/styled_paragraph.zig");
const shape_profile_mod = @import("shape_profile.zig");
pub const ShapeStageProfile = shape_profile_mod.ShapeStageProfile;
pub const GdefMetadataCache = layout_cache.GdefMetadataCache;
pub const GlyphIndexCache = layout_cache.GlyphIndexCache;
pub const GlyphMetrics = layout_cache.GlyphMetrics;
pub const GlyphMetricsCache = layout_cache.GlyphMetricsCache;
pub const GposTableProofCache = layout_cache.GposTableProofCache;
pub const GsubTableProofCache = layout_cache.GsubTableProofCache;
pub const LookupSelectionCache = layout_cache.LookupSelectionCache;
pub const VerticalGlyphMetrics = layout_cache.VerticalGlyphMetrics;
pub const ClusterLevel = pipeline_types.ClusterLevel;
pub const GlyphPosition = glyph_position.GlyphPosition;

pub const GlyphRun = run_types.GlyphRun;
pub const CascadeRun = run_types.CascadeRun;
pub const ShapedText = run_types.ShapedText;
pub const ScriptedRun = run_types.ScriptedRun;
pub const ScriptedText = run_types.ScriptedText;

pub const TextDirection = pipeline_types.TextDirection;
pub const WritingMode = pipeline_types.WritingMode;
pub const TextOrientation = pipeline_types.TextOrientation;
pub const ScriptPosition = pipeline_types.ScriptPosition;

pub const ShapeOptions = shaping_plan.ShapeOptions;
pub const ShapePlanKey = shaping_plan.ShapePlanKey;
pub const ShapePlan = shaping_plan.ShapePlan;
pub const ShapePlanCache = shaping_plan.ShapePlanCache;

pub const ShapedRunCacheKey = layout_cache.ShapedRunCacheKey;
pub const ShapedRunCacheEntry = layout_cache.ShapedRunCacheEntry;
pub const ShapedRunCache = layout_cache.ShapedRunCache;

pub const TextAlign = paragraph_types.TextAlign;
pub const WrapMode = paragraph_types.WrapMode;

pub const BaselineMetrics = paragraph_reflow.BaselineMetrics;

pub const TextMetrics = paragraph_types.TextMetrics;

pub const ParagraphOptions = paragraph_options.Options;

/// One contiguous style item for unified paragraph shaping.
///
/// Spans form an exact, ordered partition of the UTF-8 input. Font family
/// resolution remains the caller's responsibility through `FontCascade`;
/// these fields describe the shaping and geometry choices that are meaningful
/// after a cascade has been selected.
pub const StyledParagraphSpan = styled_paragraph.Span;
pub const StyledGlyphMetadata = styled_buffer.Metadata;
pub const StyledParagraphBuffer = styled_buffer.Buffer;

pub const ParagraphLine = paragraph_types.ParagraphLine;
pub const TextPosition = paragraph_types.TextPosition;
pub const TextRect = paragraph_types.TextRect;
pub const ParagraphLayout = paragraph_types.ParagraphLayout;

pub const ShapedParagraph = retained_paragraph.ShapedParagraph;
pub const ReflowBuffer = retained_paragraph.ReflowBuffer;

pub const FontCascade = font_fallback.Cascade;

pub const FontFallbackDecision = diagnostic_types.FontFallbackDecision;
pub const MissingGlyphDiagnostic = diagnostic_types.MissingGlyphDiagnostic;
pub const ShapeQualityFontRunDiagnostic = diagnostic_types.ShapeQualityFontRunDiagnostic;
pub const ShapeQualityScriptRunDiagnostic = diagnostic_types.ShapeQualityScriptRunDiagnostic;
pub const ShapeQualityReport = diagnostic_types.ShapeQualityReport;
pub const ClusterCaretIssueKind = diagnostic_types.ClusterCaretIssueKind;
pub const ClusterCaretDiagnostic = diagnostic_types.ClusterCaretDiagnostic;
pub const ClusterCaretConsistencyReport = diagnostic_types.ClusterCaretConsistencyReport;

pub const diagnoseFontFallbackUtf8 = diagnostic_fallback.analyze;

pub fn diagnoseClusterCaretConsistencyUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ClusterCaretConsistencyReport {
    return try diagnostic_orchestration.clusterCaretConsistency(
        TextShaper,
        allocator,
        cascade,
        text,
        font_size,
        options,
    );
}

pub fn diagnoseShapeQualityUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ShapeQualityReport {
    return try diagnostic_orchestration.shapeQuality(
        TextShaper,
        allocator,
        cascade,
        text,
        font_size,
        options,
    );
}

/// Caches codepoint-to-font decisions for a cascade. This is separate from the
/// glyph-id cache because the same codepoint can map to different glyph ids in
/// different fonts, while fallback only needs the winning font index.
pub const FontFallbackCache = layout_cache.FontFallbackCache;

pub const LayoutBuffer = context_output.Buffer;

pub const TextShaper = @import("shaping/orchestrator.zig").TextShaper;
