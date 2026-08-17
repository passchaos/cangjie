const std = @import("std");
const face_mod = @import("font/face/root.zig");
const font_shaping = @import("font.zig").shaping;
const attachment = @import("attachment.zig");
const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
const layout_cache = @import("shaping/context/cache/root.zig");
const context_output = @import("shaping/context/output.zig");
const pipeline_types = @import("shaping/pipeline/types.zig");
const segment_pipeline = @import("shaping/pipeline/segment.zig");
const shaping_plan = @import("shaping/plan/root.zig");
const plan_bidi = @import("shaping/plan/bidi.zig");
const plan_resolution = @import("shaping/plan/resolution.zig");
const plan_validation = @import("shaping/plan/validation.zig");
const source_pipeline = @import("shaping/pipeline/source/root.zig");
const positioning = @import("shaping/pipeline/positioning/root.zig");
const position_attachments = positioning.attachments;
const diagnostics = @import("shaping/diagnostics/root.zig");
const diagnostic_caret = diagnostics.caret;
const diagnostic_fallback = diagnostics.fallback;
const diagnostic_quality = diagnostics.quality;
const diagnostic_types = diagnostics.types;
const font_fallback = @import("shaping/fallback/font/root.zig");
const fallback_segment = @import("shaping/fallback/segment.zig");
const script_run_itemization =
    @import("shaping/itemization/script_runs.zig");
const bidi_reorder = @import("layout/bidi/reorder/root.zig");
const glyph_position = @import("layout/glyph_position.zig");
const paragraph_options = @import("layout/paragraph/options.zig");
const retained_paragraph = @import("layout/paragraph/retained.zig");
const paragraph_types = @import("layout/types/paragraph.zig");
const run_types = @import("layout/types/runs.zig");
const line_break_analysis = @import("layout/line_break/analysis.zig");
const paragraph_reflow = @import("layout/line_break/reflow/root.zig");
const shaped_boundary = @import("layout/line_break/shaped_boundary.zig");
const styled_bidi = @import("layout/styled_bidi.zig");
const styled_buffer = @import("layout/styled_buffer.zig");
const styled_paragraph = @import("layout/styled_paragraph.zig");
const segmentation = @import("text/segmentation/root.zig");
const unicode = @import("unicode.zig");
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
const positionByteOffset = paragraph_types.positionByteOffset;

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

/// Shape text and validate source cluster/caret invariants without depending on
/// a renderer, platform text API, or UI layer.
///
/// The paragraph is laid out with unbounded width so the report focuses on
/// shaper source metadata and caret normalization rather than line wrapping.
/// Callers can use this in fixtures and benchmarks as a cheap preflight before
/// asserting pixels or editor selection geometry.
pub fn diagnoseClusterCaretConsistencyUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ClusterCaretConsistencyReport {
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    _ = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &buffer, text, font_size, options);
    try buildParagraphLines(&buffer, text, .{
        .max_width = std.math.inf(f32),
        .direction = options.direction,
    }, defaultBaselineMetrics(cascade.fonts[0], font_size), null, null, null);
    return try diagnoseClusterCaretConsistencyForLayout(allocator, text, buffer.paragraphLayout());
}

/// Shape text and return a compact quality/coverage report.
///
/// The report owns only the `missing_glyphs` slice. All other values are scalar
/// aggregates computed from the shaped glyph stream and deterministic fallback
/// decisions, so this helper remains cheap enough to run in unit tests,
/// benchmarks, and CI quality gates.
pub fn diagnoseShapeQualityUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ShapeQualityReport {
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const scripted = try TextShaper.shapeUtf8ScriptRuns(
        cascade,
        &buffer,
        text,
        font_size,
        options,
    );
    const fallback = try diagnostic_fallback.analyze(
        allocator,
        cascade,
        text,
    );
    defer allocator.free(fallback);
    return try diagnostic_quality.summarize(allocator, scripted, fallback);
}

const diagnoseClusterCaretConsistencyForLayout = diagnostic_caret.analyze;

/// Caches codepoint-to-font decisions for a cascade. This is separate from the
/// glyph-id cache because the same codepoint can map to different glyph ids in
/// different fonts, while fallback only needs the winning font index.
pub const FontFallbackCache = layout_cache.FontFallbackCache;

pub const LayoutBuffer = context_output.Buffer;

pub const TextShaper = struct {
    pub fn shapeUtf8(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !GlyphRun {
        return try shapeUtf8WithOptions(font, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8WithOptions(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        return try shapeSingleFontInto(font, null, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8WithCaches(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        return try shapeSingleFontInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, options);
    }

    pub fn shapeUtf8Cascade(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeWithOptions(cascade, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeWithOptions(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeCachedWithOptions(cascade, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeCached(cascade: FontCascade, cache: *FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeCachedWithOptions(cascade, cache, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeCachedWithOptions(cascade: FontCascade, cache: ?*FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeFullyCachedWithOptions(cascade, cache, null, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeFullyCached(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeFullyCachedWithOptions(cascade, fallback_cache, metrics_cache, null, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeFullyCachedWithOptions(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeWithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        try plan_validation.input(text, font_size, options);
        const cache_key = if (shaped_cache != null) ShapedRunCache.key(cascade.fonts, text, font_size, options) else undefined;
        if (shaped_cache) |cache| {
            if (cache.lookup(cache_key)) |entry| {
                buffer.clear();
                try buffer.glyphs.appendSlice(buffer.allocator, entry.glyphs);
                try buffer.runs.appendSlice(buffer.allocator, entry.runs);
                return buffer.shapedText();
            }
        }
        buffer.clear();
        var fallback_context = DynamicFallbackContext{
            .buffer = buffer,
            .metrics_cache = metrics_cache,
            .glyph_index_cache = glyph_index_cache,
            .font_size = font_size,
            .options = options,
        };
        _ = try fallback_segment.shape(&fallback_context, .{
            .cascade = cascade,
            .fallback_cache = fallback_cache,
            .glyph_index_cache = glyph_index_cache,
            .text = text,
        });

        if (plan_bidi.shouldReorderShapedRun(text, options, false)) {
            try applyBidiVisualOrder(buffer, text, options.direction, null);
        }
        const shaped = buffer.shapedText();
        if (shaped_cache) |cache| {
            try cache.store(cache_key, shaped);
        }
        return shaped;
    }

    pub fn shapeUtf8ScriptRuns(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ScriptedText {
        try plan_validation.input(text, font_size, options);
        try shapeScriptRunsInto(cascade, buffer, text, font_size, options);
        if (plan_bidi.shouldReorderShapedRun(text, options, false)) {
            try applyBidiVisualOrder(buffer, text, options.direction, null);
        }
        try script_run_itemization.rebuild(
            buffer.allocator,
            &buffer.script_runs,
            buffer.glyphs.items,
            text,
            options.direction,
            options.language_tag,
        );
        return buffer.scriptedText();
    }

    /// Shape and retain a width-independent paragraph.
    ///
    /// Unlike `layoutParagraphUtf8`, this performs GSUB/GPOS and fallback only
    /// once. Call `ShapedParagraph.layout` with different `ParagraphOptions`
    /// to rebuild visual lines without reshaping.
    pub fn shapeParagraphUtf8(allocator: std.mem.Allocator, cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ShapedParagraph {
        return try shapeParagraphUtf8WithCaches(allocator, cascade, null, null, null, null, buffer, text, font_size, options);
    }

    pub fn shapeParagraphUtf8WithCaches(
        allocator: std.mem.Allocator,
        cascade: FontCascade,
        fallback_cache: ?*FontFallbackCache,
        metrics_cache: ?*GlyphMetricsCache,
        glyph_index_cache: ?*GlyphIndexCache,
        shaped_cache: ?*ShapedRunCache,
        buffer: *LayoutBuffer,
        text: []const u8,
        font_size: f32,
        options: ParagraphOptions,
    ) !ShapedParagraph {
        try paragraph_options.validate(options);
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;
        const shape_options = paragraph_options.shapeOptions(options);
        _ = try shapeUtf8CascadeWithCaches(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            shaped_cache,
            buffer,
            text,
            font_size,
            shape_options,
        );
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        const logical_shaped = buffer.shapedText();

        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);
        const owned_glyphs = try allocator.dupe(GlyphPosition, logical_shaped.glyphs);
        errdefer allocator.free(owned_glyphs);
        const owned_runs = try allocator.dupe(CascadeRun, logical_shaped.runs);
        errdefer allocator.free(owned_runs);
        const grapheme_clusters = try unicode.itemizeGraphemeClusters(allocator, text);
        errdefer allocator.free(grapheme_clusters);
        const line_breaks = try line_break_analysis.itemize(
            allocator,
            text,
            grapheme_clusters,
            options.word_break_dictionary,
        );
        errdefer allocator.free(line_breaks);

        return .{
            .allocator = allocator,
            .text = owned_text,
            .glyphs = owned_glyphs,
            .runs = owned_runs,
            .grapheme_clusters = grapheme_clusters,
            .line_breaks = line_breaks,
            .word_break_dictionary = options.word_break_dictionary,
            .default_metrics = defaultBaselineMetrics(cascade.fonts[0], font_size),
            .shape_key = ShapePlanKey.fromText(text, shape_options),
            .needs_bidi_reorder = plan_bidi.paragraphNeedsReorder(text, options.direction),
        };
    }

    pub fn layoutParagraphUtf8(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8WithOptions(cascade, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8WithOptions(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8CachedWithOptions(cascade, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8Cached(cascade: FontCascade, cache: *FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8CachedWithOptions(cascade, cache, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8CachedWithOptions(cascade: FontCascade, cache: ?*FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8FullyCachedWithOptions(cascade, cache, null, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8FullyCached(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8FullyCachedWithOptions(cascade, fallback_cache, metrics_cache, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8FullyCachedWithOptions(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try paragraph_options.validate(options);
        // Paragraph layout is deliberately staged: shape first, then line-wrap
        // the finished glyph advances. That keeps OpenType substitution and
        // positioning independent from wrapping policy.
        _ = try shapeUtf8CascadeFullyCachedWithOptions(cascade, fallback_cache, metrics_cache, glyph_index_cache, buffer, text, font_size, paragraph_options.shapeOptions(options));
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
        );
        if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        return buffer.paragraphLayout();
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try paragraph_options.validate(options);
        _ = try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, shaped_cache, buffer, text, font_size, paragraph_options.shapeOptions(options));
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
        );
        if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        return buffer.paragraphLayout();
    }

    /// Shape style items into one paragraph before line breaking.
    ///
    /// Unlike the legacy attributed-run helpers, style boundaries do not
    /// create independent paragraphs: all items share one source coordinate
    /// space, fallback stream, line breaker, bidi pass, and alignment result.
    pub fn layoutStyledParagraphUtf8(
        cascade: FontCascade,
        buffer: *LayoutBuffer,
        styled: *StyledParagraphBuffer,
        text: []const u8,
        default_font_size: f32,
        spans: []const StyledParagraphSpan,
        options: ParagraphOptions,
    ) !ParagraphLayout {
        try paragraph_options.validate(options);
        try plan_validation.utf8(text);
        try plan_validation.fontSize(default_font_size);
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;

        buffer.clear();
        styled.clear();
        var driver = StyledParagraphDriver{
            .cascade = cascade,
            .buffer = buffer,
            .styled = styled,
            .text = text,
            .default_font_size = default_font_size,
            .options = options,
        };
        try styled_paragraph.layout(&driver, text, spans);

        return buffer.paragraphLayout();
    }

    pub fn measureParagraphUtf8(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !TextMetrics {
        const paragraph = try layoutParagraphUtf8(cascade, buffer, text, font_size, options);
        return textMetricsFromParagraph(paragraph);
    }

    pub fn measureParagraphsUtf8(allocator: std.mem.Allocator, cascade: FontCascade, texts: []const []const u8, font_size: f32, options: ParagraphOptions) ![]TextMetrics {
        var buffer = LayoutBuffer.init(allocator);
        defer buffer.deinit();
        const metrics = try allocator.alloc(TextMetrics, texts.len);
        errdefer allocator.free(metrics);
        for (texts, 0..) |text, index| {
            metrics[index] = try measureParagraphUtf8(cascade, &buffer, text, font_size, options);
        }
        return metrics;
    }
};

fn textMetricsFromParagraph(paragraph: ParagraphLayout) TextMetrics {
    if (paragraph.lines.len == 0) {
        return .{ .width = 0, .height = 0, .baseline = 0, .ascent = 0, .descent = 0, .leading = 0 };
    }
    const first = paragraph.lines[0];
    return .{
        .width = paragraph.width,
        .height = paragraph.height,
        .baseline = first.y + first.baseline,
        .ascent = first.ascent,
        .descent = first.descent,
        .leading = first.leading,
    };
}

const StyledParagraphDriver = struct {
    cascade: FontCascade,
    buffer: *LayoutBuffer,
    styled: *StyledParagraphBuffer,
    text: []const u8,
    default_font_size: f32,
    options: ParagraphOptions,
    pen: PenPosition = .{},

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return self.buffer.allocator;
    }

    pub fn validateSpan(_: *@This(), span: StyledParagraphSpan) !void {
        try plan_validation.fontSize(span.font_size);
        if (span.faces) |faces| {
            if (faces.len == 0) return error.EmptyFontCascade;
        }
        try plan_validation.features(span.features);
        try plan_validation.variationCoords(span.normalized_variation_coords);
        if (!std.math.isFinite(span.letter_spacing) or
            !std.math.isFinite(span.word_spacing))
        {
            return error.InvalidStyleSpans;
        }
        if (span.minimum_line_height) |height| {
            if (!std.math.isFinite(height) or height <= 0) {
                return error.InvalidStyleSpans;
            }
        }
    }

    fn normalizeNewRunFontIndices(
        self: *@This(),
        run_start: usize,
    ) void {
        // `shapeCascadeSegmentInto` records indexes relative to the style-local
        // cascade. Public paragraph runs use the driver's union cascade so
        // diagnostics and render integrations see one stable index space.
        for (self.buffer.runs.items[run_start..]) |*run| {
            for (self.cascade.fonts, 0..) |font, font_index| {
                if (font != run_types.fontForBackend(run.*)) continue;
                run.font_index = font_index;
                break;
            }
        }
    }

    pub fn shapeItem(
        self: *@This(),
        byte_start: usize,
        byte_end: usize,
        inferred_script: unicode.Script,
        span: StyledParagraphSpan,
    ) !void {
        const item_text = self.text[byte_start..byte_end];
        const item_cascade = FontCascade.init(
            if (span.faces) |faces|
                face_mod.backend.fonts(faces)
            else
                self.cascade.fonts,
        );
        const run_start = self.buffer.runs.items.len;
        self.pen = try shapeCascadeSegmentInto(
            item_cascade,
            self.buffer,
            item_text,
            span.font_size,
            byte_start,
            self.pen,
            .{
                .lookup = .{
                    .script = inferred_script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(inferred_script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(item_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    .context_before = self.text[0..byte_start],
                    .context_after = self.text[byte_end..],
                    .beginning_of_text = byte_start == 0,
                    .end_of_text = byte_end == self.text.len,
                },
                .all_ascii = fallback_segment.isAscii(item_text),
            },
        );
        if (span.faces != null) {
            self.normalizeNewRunFontIndices(run_start);
        }
    }

    pub fn finish(self: *@This(), spans: []const StyledParagraphSpan) !void {
        try normalizeParagraphGlyphsToLogicalOrder(self.buffer);
        try rebuildStyledGlyphMetadata(self.buffer, self.styled, spans);
        try styled_buffer.applySpacing(
            self.styled.metadata.items,
            self.buffer.glyphs.items,
        );
        const shaped_glyph_count = self.buffer.glyphs.items.len;
        var line_options = self.options;
        // The established line engine remains style-agnostic. Defer synthetic
        // dots until its prefix truncation is complete so the sidecar can
        // capture the terminal visible style before the fit loop removes it.
        line_options.ellipsis = false;
        try buildParagraphLines(
            self.buffer,
            self.text,
            line_options,
            defaultBaselineMetrics(
                self.cascade.fonts[0],
                self.default_font_size,
            ),
            null,
            null,
            self.options.word_break_dictionary,
        );
        const content_omitted = self.buffer.glyphs.items.len < shaped_glyph_count or
            (self.buffer.lines.items.len != 0 and
                self.buffer.lines.items[self.buffer.lines.items.len - 1].byteEnd() <
                    self.text.len);
        try styled_buffer.synchronizeAfterTruncation(
            &self.styled.metadata,
            self.buffer.glyphs.items.len,
        );
        if (self.options.ellipsis and content_omitted and
            self.buffer.glyphs.items.len != 0)
        {
            try styled_buffer.appendEllipsis(
                &self.styled.metadata,
                self.styled.allocator,
                self.buffer,
                if (self.options.max_width > 0)
                    self.options.max_width
                else
                    std.math.inf(f32),
                resolvedAlignment(self.options),
                alignedLineX,
            );
        }
        styled_buffer.applyMinimumLineHeights(
            self.styled.metadata.items,
            self.buffer.glyphs.items.len,
            self.buffer.lines.items,
        );
        if (plan_bidi.paragraphNeedsReorder(self.text, self.options.direction)) {
            const visual_order = try styled_bidi.visualPermutation(
                self.buffer.allocator,
                self.text,
                self.options.direction == .rtl,
                self.buffer.lines.items,
                self.buffer.glyphs.items,
            );
            defer self.buffer.allocator.free(visual_order);
            try applyParagraphLineBidiVisualOrder(
                self.buffer,
                self.text,
                self.options.direction,
            );
            try styled_buffer.reorderByPermutation(
                &self.styled.metadata,
                self.styled.allocator,
                visual_order,
            );
        }
    }
};

fn rebuildStyledGlyphMetadata(
    buffer: *LayoutBuffer,
    styled: *StyledParagraphBuffer,
    spans: []const StyledParagraphSpan,
) !void {
    return try styled_buffer.rebuild(
        &styled.metadata,
        styled.allocator,
        buffer.glyphs.items,
        spans,
    );
}

fn shapeScriptRunsInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !void {
    buffer.clear();
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    const script_runs = try unicode.itemizeScriptRuns(buffer.allocator, text);
    defer buffer.allocator.free(script_runs);

    var pen = PenPosition{};
    for (script_runs) |script_run| {
        const run_text = text[script_run.byte_start .. script_run.byte_start + script_run.byte_len];
        pen = try shapeCascadeSegmentInto(
            cascade,
            buffer,
            run_text,
            font_size,
            script_run.byte_start,
            pen,
            plan_resolution.forScriptRun(
                run_text,
                script_run.script,
                options,
            ),
        );
    }
}

const PenPosition = fallback_segment.Pen;

const DynamicFallbackContext = struct {
    buffer: *LayoutBuffer,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    font_size: f32,
    options: ShapeOptions,

    pub fn appendSegment(
        self: *@This(),
        cascade: FontCascade,
        font_index: usize,
        text: []const u8,
        cluster_base: usize,
        pen: PenPosition,
    ) !PenPosition {
        return try appendCascadeRun(
            cascade.fonts[font_index],
            self.metrics_cache,
            self.glyph_index_cache,
            font_index,
            self.buffer,
            text,
            self.font_size,
            cluster_base,
            pen,
            plan_resolution.forText(text, self.options),
        );
    }
};

const FixedFallbackContext = struct {
    buffer: *LayoutBuffer,
    font_size: f32,
    lookup_options: ResolvedLookupOptions,

    pub fn appendSegment(
        self: *@This(),
        cascade: FontCascade,
        font_index: usize,
        text: []const u8,
        cluster_base: usize,
        pen: PenPosition,
    ) !PenPosition {
        return try appendCascadeRun(
            cascade.fonts[font_index],
            null,
            null,
            font_index,
            self.buffer,
            text,
            self.font_size,
            cluster_base,
            pen,
            self.lookup_options,
        );
    }
};

fn shapeSingleFontInto(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const total_start = shape_profile_mod.now(shape_profile, profile_io);
    defer {
        if (shape_profile) |p| p.total_ns += shape_profile_mod.elapsed(total_start, profile_io);
    }

    const validate_start = shape_profile_mod.now(shape_profile, profile_io);
    try plan_validation.input(text, font_size, options);
    if (shape_profile) |p| p.validate_ns += shape_profile_mod.elapsed(validate_start, profile_io);

    buffer.clear();
    const options_start = shape_profile_mod.now(shape_profile, profile_io);
    const lookup_options = plan_resolution.forText(text, options);
    if (shape_profile) |p| p.options_ns += shape_profile_mod.elapsed(options_start, profile_io);

    try segment_pipeline.run(.{
        .font = font,
        .metrics_cache = metrics_cache,
        .glyph_index_cache = glyph_index_cache,
        .buffer = buffer,
        .text = text,
        .font_size = font_size,
        .cluster_base = 0,
        .lookup_options = lookup_options,
    });
    const bidi_start = shape_profile_mod.now(shape_profile, profile_io);
    if (plan_bidi.shouldReorderShapedRun(text, options, lookup_options.all_ascii)) {
        try applyBidiVisualOrder(buffer, text, options.direction, font);
    }
    if (shape_profile) |p| p.bidi_ns += shape_profile_mod.elapsed(bidi_start, profile_io);
    return buffer.run(font, font_size);
}

fn shapeCascadeSegmentInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: ResolvedLookupOptions) !PenPosition {
    var fallback_context = FixedFallbackContext{
        .buffer = buffer,
        .font_size = font_size,
        .lookup_options = lookup_options,
    };
    return try fallback_segment.shape(&fallback_context, .{
        .cascade = cascade,
        .text = text,
        .cluster_base = cluster_base,
        .pen = pen,
    });
}

fn applyBidiVisualOrder(
    buffer: *LayoutBuffer,
    text: []const u8,
    direction: TextDirection,
    single_font: ?*const Font,
) !void {
    return try bidi_reorder.apply(
        buffer,
        text,
        direction == .rtl,
        single_font,
    );
}

const normalizeParagraphGlyphsToLogicalOrder = bidi_reorder.normalizeLogical;

fn applyParagraphLineBidiVisualOrder(
    buffer: *LayoutBuffer,
    text: []const u8,
    direction: TextDirection,
) !void {
    return try bidi_reorder.applyLines(buffer, text, direction == .rtl);
}

/// Typed adapter between public paragraph records and the internal generic
/// reflow module. Keeping concrete types here also gives struct literals their
/// complete `ParagraphOptions` result type at call sites.
fn buildParagraphLines(
    buffer: *LayoutBuffer,
    text: []const u8,
    options: ParagraphOptions,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const unicode.LineBreak,
    dictionary: ?*const segmentation.WordBreakDictionary,
) !void {
    return try paragraph_reflow.build(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
    );
}

const resolvedAlignment = paragraph_reflow.resolvedAlignment;
const alignedLineX = paragraph_reflow.alignedLineX;
const runRangeForGlyphs = paragraph_reflow.runRangeForGlyphs;
const defaultBaselineMetrics = paragraph_reflow.defaultBaselineMetrics;
const glyphSourceEnd = shaped_boundary.glyphSourceEnd;

fn appendCascadeRun(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, font_index: usize, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: ResolvedLookupOptions) !PenPosition {
    const glyph_start = buffer.glyphs.items.len;
    try segment_pipeline.run(.{
        .font = font,
        .metrics_cache = metrics_cache,
        .glyph_index_cache = glyph_index_cache,
        .buffer = buffer,
        .text = text,
        .font_size = font_size,
        .cluster_base = cluster_base,
        .lookup_options = lookup_options,
    });
    const glyph_len = buffer.glyphs.items.len - glyph_start;
    // A segment made solely of default-ignorables/variation selectors may
    // legitimately emit no glyphs. Do not retain a zero-length font run: it
    // has no owner in the flat glyph stream and destabilizes diagnostics and
    // line-to-run range calculations.
    if (glyph_len == 0) return pen;
    try buffer.runs.append(buffer.allocator, .{
        .font = face_mod.backend.face(font),
        .font_index = font_index,
        .font_size = font_size,
        .glyph_start = glyph_start,
        .glyph_len = glyph_len,
        .x_offset = pen.x,
        .y_offset = pen.y,
    });
    var next_pen = pen;
    for (buffer.glyphs.items[glyph_start..]) |glyph| {
        next_pen.x += glyph.x_advance;
        next_pen.y += glyph.y_advance;
    }
    return next_pen;
}

const ResolvedLookupOptions = pipeline_types.ResolvedLookupOptions;

test "attachment scratch is needed only for emitted attachment adjustments" {
    try std.testing.expect(!position_attachments.hasGpos(&.{
        .{ .index = 0, .x_advance = -20, .pair_positioned = true },
    }));
    try std.testing.expect(position_attachments.hasGpos(&.{
        .{ .index = 0, .attachment_type = .mark, .attachment_parent_index = 1 },
    }));
    try std.testing.expect(position_attachments.hasGpos(&.{
        .{ .index = 0, .attachment_type = .cursive, .attachment_parent_index = 1 },
    }));
}

test "attachment remapping scratch follows emitted adjustment type across runs" {
    const test_font = @import("test_font.zig");
    const mark_bytes = try test_font.buildMinimalGposMarkTtf(std.testing.allocator);
    defer std.testing.allocator.free(mark_bytes);
    var mark_font = try Font.parse(std.testing.allocator, mark_bytes);
    defer mark_font.deinit();
    const pair_bytes = try test_font.buildMinimalGposTtf(std.testing.allocator);
    defer std.testing.allocator.free(pair_bytes);
    var pair_font = try Font.parse(std.testing.allocator, pair_bytes);
    defer pair_font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const mark_run = try TextShaper.shapeUtf8(&mark_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), mark_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.glyph_output_indices.items.len);

    // Shape into the same reusable buffer. Its clear step drops the old lengths,
    // and PairPos does not regrow arrays that it cannot consume.
    const pair_run = try TextShaper.shapeUtf8(&pair_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), pair_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.glyph_output_indices.items.len);
}

test "ordinary shaping clears and leaves stch sidecar empty" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    // Model reuse after a prior stretch-bearing segment. ShapeScratch.clear
    // must drop that old length, and the ordinary output loop must not regrow
    // the sidecar with `.none` entries.
    try buffer.shape_scratch.stch_actions.append(
        std.testing.allocator,
        @intFromEnum(ligature_provenance.StchAction.fixed),
    );
    const run = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.stch_actions.items.len);
}

test "USE shaping zeroes synthesized nonspacing marks without a GDEF table" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const features = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "𑀓𑀸", // BRAHMI LETTER KA + Mn VOWEL SIGN AA.
        1000,
        .{ .script_tag = .brah, .features = &features },
    );

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -800), run.glyphs[1].x_offset, 0.001);
}

const fallbackGlyphIndexWithOptionalCache = source_pipeline.fallbackGlyphIndex;

test "mapped spaces use the glyph index cache before fallback" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildSingleCodepointTtf(allocator, ' ');
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, ' '));
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    const cmap = for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) break table;
    } else return error.TestUnexpectedResult;
    bytes[cmap.offset + cmap.length - 1] ^= 1;

    // Public cmap lookup remains deliberately defensive for borrowed bytes.
    // The explicit cache, however, is the caller's immutable-font proof and
    // must serve ordinary U+0020 just like every other cached codepoint.
    try std.testing.expectError(error.BadSfnt, font.glyphIndex(' '));
    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, ' '));
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);
}

test "missing Unicode spaces still fall back to the cached ASCII space" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildSingleCodepointTtf(allocator, ' ');
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, 0x2002));
    try std.testing.expectEqual(@as(usize, 2), cache.misses);
    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, 0x2002));
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 2), cache.misses);
}

test "font fallback diagnostics expose deterministic variation and missing glyph decisions" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const variant_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(variant_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var variant = try Font.parse(allocator, variant_bytes);
    defer variant.deinit();

    const fonts = [_]*const Font{ &primary, &variant };
    const cascade = FontCascade.init(&fonts);

    const text = "A\u{fe0f}B\u{fe0e}C";
    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, text);
    defer allocator.free(decisions);

    try std.testing.expectEqual(@as(usize, 3), decisions.len);

    try std.testing.expectEqual(@as(usize, 0), decisions[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), decisions[0].byte_len);
    try std.testing.expectEqual(@as(u21, 'A'), decisions[0].codepoint);
    try std.testing.expectEqual(@as(?u21, 0xfe0f), decisions[0].variation_selector);
    try std.testing.expectEqual(@as(usize, 1), decisions[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 3), decisions[0].glyph_id);
    try std.testing.expect(decisions[0].used_variation_mapping);
    try std.testing.expect(!decisions[0].missingGlyph());

    try std.testing.expectEqual(@as(usize, 4), decisions[1].byte_start);
    try std.testing.expectEqual(@as(usize, 4), decisions[1].byte_len);
    try std.testing.expectEqual(@as(u21, 'B'), decisions[1].codepoint);
    try std.testing.expectEqual(@as(?u21, 0xfe0e), decisions[1].variation_selector);
    try std.testing.expectEqual(@as(usize, 1), decisions[1].font_index);
    try std.testing.expectEqual(@as(GlyphId, 2), decisions[1].glyph_id);
    try std.testing.expect(!decisions[1].used_variation_mapping);

    try std.testing.expectEqual(@as(usize, 8), decisions[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), decisions[2].byte_len);
    try std.testing.expectEqual(@as(u21, 'C'), decisions[2].codepoint);
    try std.testing.expectEqual(@as(?u21, null), decisions[2].variation_selector);
    try std.testing.expectEqual(@as(usize, 0), decisions[2].font_index);
    try std.testing.expectEqual(@as(GlyphId, 0), decisions[2].glyph_id);
    try std.testing.expect(decisions[2].missingGlyph());

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, text, 20);
    try std.testing.expectEqual(decisions.len, shaped.glyphs.len);
    for (decisions, shaped.glyphs) |decision, glyph| {
        try std.testing.expectEqual(decision.byte_start, glyph.cluster);
        try std.testing.expectEqual(decision.byte_len, glyph.source_byte_len);
        try std.testing.expectEqual(decision.codepoint, glyph.codepoint);
        try std.testing.expectEqual(decision.glyph_id, glyph.glyph_id);
    }
}

test "font fallback keeps combining graphemes in a fully covering font" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 'A', 'B', 0x0301 });
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster("A\u{0301}"));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, "A\u{0301}B", 20);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, "A\u{0301}".len), shaped.glyphs[2].cluster);
    try std.testing.expect(shaped.glyphs[1].glyph_id != 0);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, "A\u{0301}B");
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 3), decisions.len);
    for (decisions) |decision| try std.testing.expectEqual(@as(usize, 1), decision.font_index);
    try std.testing.expect(!decisions[0].missingGlyph());
    try std.testing.expect(!decisions[1].missingGlyph());

    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var glyph_cache = GlyphIndexCache.init(allocator);
    defer glyph_cache.deinit();
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontForCluster(cascade, &glyph_cache, "A\u{0301}"));
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontForCluster(cascade, &glyph_cache, "A\u{0301}"));
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.misses);
}

test "Arabic normalization composes base mark pairs when the font has the precomposed glyph" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const composed_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0622});
    defer allocator.free(composed_bytes);
    var composed_font = try Font.parse(allocator, composed_bytes);
    defer composed_font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(
        &composed_font,
        &buffer,
        "آ",
        20,
        .{ .direction = .rtl, .script_tag = .arab },
    );

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x0622), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, "آ".len), run.glyphs[0].source_byte_len);

    const decomposed_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 0x0627, 0x0653 });
    defer allocator.free(decomposed_bytes);
    var decomposed_font = try Font.parse(allocator, decomposed_bytes);
    defer decomposed_font.deinit();
    const decomposed_run = try TextShaper.shapeUtf8WithOptions(
        &decomposed_font,
        &buffer,
        "آ",
        20,
        .{ .direction = .rtl, .script_tag = .arab },
    );

    try std.testing.expectEqual(@as(usize, 2), decomposed_run.glyphs.len);
    var saw_alef = false;
    var saw_maddah = false;
    for (decomposed_run.glyphs) |glyph| {
        saw_alef = saw_alef or glyph.codepoint == 0x0627;
        saw_maddah = saw_maddah or glyph.codepoint == 0x0653;
    }
    try std.testing.expect(saw_alef);
    try std.testing.expect(saw_maddah);
}

test "font fallback accepts Arabic clusters covered through normalization" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0627});
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0622});
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster("آ"));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &buffer, "آ", 20, .{ .direction = .rtl });
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), shaped.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x0622), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, "آ".len), shaped.glyphs[0].source_byte_len);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, "آ");
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 1), decisions.len);
    try std.testing.expectEqual(@as(usize, 1), decisions[0].font_index);
    try std.testing.expectEqual(@as(u21, 0x0622), decisions[0].codepoint);
    try std.testing.expectEqual(@as(usize, "آ".len), decisions[0].byte_len);
    try std.testing.expect(!decisions[0].missingGlyph());
}

test "font fallback keeps emoji ZWJ sequences atomic" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;
    const woman: u21 = 0x1f469;
    const laptop: u21 = 0x1f4bb;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{woman});
    defer allocator.free(primary_bytes);
    const emoji_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ woman, laptop });
    defer allocator.free(emoji_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var emoji = try Font.parse(allocator, emoji_bytes);
    defer emoji.deinit();

    const fonts = [_]*const Font{ &primary, &emoji };
    const cascade = FontCascade.init(&fonts);
    const sequence = "\u{1f469}\u{200d}\u{1f4bb}";
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster(sequence));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, sequence, 20);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    // ZWJ participates in shaping but emits no visible fallback glyph when it
    // is not substituted.
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expect(shaped.glyphs[0].glyph_id != 0);
    try std.testing.expect(shaped.glyphs[1].glyph_id != 0);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, sequence);
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 2), decisions.len);
    for (decisions) |decision| {
        try std.testing.expectEqual(@as(usize, 1), decision.font_index);
        try std.testing.expect(!decision.missingGlyph());
    }
}

test "font fallback does not split a partially covered grapheme" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const base_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(base_bytes);
    const mark_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0301});
    defer allocator.free(mark_bytes);

    var base_font = try Font.parse(allocator, base_bytes);
    defer base_font.deinit();
    var mark_font = try Font.parse(allocator, mark_bytes);
    defer mark_font.deinit();

    const fonts = [_]*const Font{ &base_font, &mark_font };
    const cascade = FontCascade.init(&fonts);
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, "A\u{0301}", 20);

    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expect(shaped.glyphs[0].glyph_id != 0);
    try std.testing.expectEqual(@as(GlyphId, 0), shaped.glyphs[1].glyph_id);
}

test "shape quality diagnostics summarize fallback coverage and missing glyphs" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Fallback", "Regular", "Fallback Regular");
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var report = try diagnoseShapeQualityUtf8(allocator, cascade, "AB\u{fe0f}C", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 3), report.font_run_count);
    try std.testing.expectEqual(@as(usize, 1), report.variation_selector_count);
    try std.testing.expectEqual(@as(usize, 1), report.fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyphs.len);
    try std.testing.expectEqual(@as(u21, 'C'), report.missing_glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 5), report.missing_glyphs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyphs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.missing_glyphs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 0), report.missing_glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs.len);
    // FE0F is Script=Inherited and remains inside the surrounding Latin run.
    try std.testing.expectEqual(@as(usize, 1), report.script_runs.len);
    var script_fallback_glyphs: usize = 0;
    var script_missing_glyphs: usize = 0;
    for (report.script_runs) |script_run| {
        script_fallback_glyphs += script_run.fallback_glyph_count;
        script_missing_glyphs += script_run.missing_glyph_count;
    }
    try std.testing.expectEqual(report.fallback_glyph_count, script_fallback_glyphs);
    try std.testing.expectEqual(report.missing_glyph_count, script_missing_glyphs);
    try std.testing.expect(report.horizontal_advance > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), report.vertical_advance, 0.001);
}

test "shape quality diagnostics expose per font and script run counters" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const latin_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Latin", "Regular", "Latin Regular");
    defer allocator.free(latin_bytes);
    const greek_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x03b2, "Greek", "Regular", "Greek Regular");
    defer allocator.free(greek_bytes);

    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var greek = try Font.parse(allocator, greek_bytes);
    defer greek.deinit();

    const fonts = [_]*const Font{ &latin, &greek };
    const cascade = FontCascade.init(&fonts);

    var report = try diagnoseShapeQualityUtf8(allocator, cascade, "AβZ", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs.len);
    try std.testing.expectEqual(@as(usize, 3), report.script_runs.len);
    try std.testing.expectEqual(@as(usize, 1), report.fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 1), report.font_runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), report.font_runs[1].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[1].missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 0), report.font_runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[2].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[2].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.latin, report.script_runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[0].font_run_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.greek, report.script_runs[1].script);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), report.script_runs[1].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].font_run_count);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[1].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.latin, report.script_runs[2].script);
    try std.testing.expectEqual(@as(usize, 3), report.script_runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].font_run_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[2].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].missing_glyph_count);
}

test "cluster caret diagnostics accept variation selectors and fallback runs" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const variant_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(variant_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var variant = try Font.parse(allocator, variant_bytes);
    defer variant.deinit();

    const fonts = [_]*const Font{ &primary, &variant };
    const cascade = FontCascade.init(&fonts);

    var report = try diagnoseClusterCaretConsistencyUtf8(allocator, cascade, "A\u{fe0f}B\u{fe0e}", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 4), report.caret_boundary_count);
    try std.testing.expectEqual(@as(usize, 4), report.grapheme_boundary_count);
    try std.testing.expectEqual(@as(usize, 0), report.issue_count);
    try std.testing.expectEqual(@as(usize, 0), report.issues.len);
}

test "unsupported variation selectors can report a synthetic not-found glyph" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text = "B\u{fe00}";
    const default_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{});
    try std.testing.expectEqual(@as(usize, 1), default_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), default_run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(?u32, null), default_run.glyphs[0].synthetic_glyph_id);
    try std.testing.expectEqual(@as(u32, 2), default_run.glyphs[0].outputGlyphId());
    try std.testing.expectEqual(@as(usize, text.len), default_run.glyphs[0].source_byte_len);

    const synthetic_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{
        .not_found_variation_selector_glyph = 1_000_000,
    });
    try std.testing.expectEqual(@as(usize, 2), synthetic_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), synthetic_run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u32, 2), synthetic_run.glyphs[0].outputGlyphId());
    try std.testing.expectEqual(@as(GlyphId, 0), synthetic_run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(?u32, 1_000_000), synthetic_run.glyphs[1].synthetic_glyph_id);
    try std.testing.expectEqual(@as(u32, 1_000_000), synthetic_run.glyphs[1].outputGlyphId());
    try std.testing.expectEqual(@as(usize, 0), synthetic_run.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, text.len), synthetic_run.glyphs[1].source_byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].y_offset, 0.001);
}

test "remove-default-ignorables deletes the font's fallback space glyph" {
    const test_font = @import("test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildDefaultIgnorableSpaceTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text = "A\u{200b}";
    const default_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{});
    try std.testing.expectEqual(@as(usize, 2), default_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), default_run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0), default_run.glyphs[1].x_advance, 0.001);

    const removed_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{
        .remove_default_ignorables = true,
    });
    try std.testing.expectEqual(@as(usize, 1), removed_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), removed_run.glyphs[0].glyph_id);

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    const default_key = ShapedRunCache.key(cascade.fonts, text, 20, .{});
    const removed_key = ShapedRunCache.key(cascade.fonts, text, 20, .{ .remove_default_ignorables = true });
    try std.testing.expect(!default_key.plan.eql(removed_key.plan));
}

test "cluster caret diagnostics catch invalid UTF-8 source spans" {
    const allocator = std.testing.allocator;
    const text = "Aβ";
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 0x03b2,
            .cluster = 2,
            .source_byte_len = 1,
            .x_advance = 10,
        },
    };
    const paragraph = ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &.{},
        .lines = &.{},
        .width = 10,
        .height = 0,
    };

    var report = try diagnoseClusterCaretConsistencyForLayout(allocator, text, paragraph);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 4), report.issue_count);
    try std.testing.expectEqual(ClusterCaretIssueKind.cluster_not_utf8_boundary, report.issues[0].kind);
    try std.testing.expectEqual(@as(?usize, 0), report.issues[0].glyph_index);
    try std.testing.expectEqual(@as(usize, 2), report.issues[0].cluster);
    try std.testing.expectEqual(@as(usize, 3), report.issues[0].source_end);
    try std.testing.expectEqual(ClusterCaretIssueKind.grapheme_boundary_roundtrip_mismatch, report.issues[1].kind);
    try std.testing.expectEqual(@as(usize, 0), report.issues[1].expected_byte_offset);
    try std.testing.expectEqual(@as(usize, 2), report.issues[1].actual_byte_offset);
}

test "vertical shaping uses vmtx and keeps horizontal behavior isolated" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const horizontal = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expect(horizontal.width() > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), horizontal.height(), 0.001);
    try std.testing.expect(!horizontal.glyphs[0].vertical);

    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 2), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    for (vertical.glyphs) |glyph| {
        try std.testing.expect(glyph.vertical);
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 8), glyph.x_offset, 0.001);
    }
}

test "vertical shaping centers glyph extents when vmtx is absent" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const bounds = try font.glyphBounds(1);
    const font_height = @as(i32, font.ascender) - @as(i32, font.descender);
    const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
    const expected_origin = @as(i32, bounds.y_max) + @divFloor(font_height - glyph_height, 2);
    try std.testing.expectEqual(
        expected_origin,
        try font_shaping.verticalOriginYAtCoords(&font, 1, &.{}),
    );

    const font_size: f32 = @floatFromInt(font.units_per_em);
    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "A",
        font_size,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatFromInt(expected_origin)),
        vertical.glyphs[0].y_offset,
        0.001,
    );
}

test "vertical sideways text uses horizontal advance for rotated glyphs" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const sideways = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .sideways },
    );
    try std.testing.expectEqual(@as(usize, 2), sideways.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), sideways.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), sideways.height(), 0.001);

    const mixed = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), mixed.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), mixed.height(), 0.001);

    const upright = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), upright.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), upright.height(), 0.001);
}

test "vertical presentation fallback survives bottom-to-top shaping" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(std.testing.allocator, &.{
        0x3008,
        0x3009,
        0xfe3f,
        0xfe40,
    });
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const ttb = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), ttb.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), ttb.glyphs[0].glyph_id);

    const btt = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .direction = .rtl, .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), btt.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 4), btt.glyphs[0].glyph_id);
}

test "vertical shaped cache and fallback runs preserve independent y pens" {
    const test_font = @import("test_font.zig");
    const primary_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(fallback_bytes);
    var primary = try Font.parse(std.testing.allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(std.testing.allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();
    var cache = ShapedRunCache.init(std.testing.allocator);
    defer cache.deinit();

    const horizontal = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{},
    );
    try std.testing.expect(horizontal.width() > 0);
    const vertical = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    try std.testing.expectEqual(@as(usize, 2), cache.entries.items.len);
    try std.testing.expectEqual(WritingMode.horizontal_tb, cache.entries.items[0].key.plan.writing_mode);
    try std.testing.expectEqual(WritingMode.vertical_lr, cache.entries.items[1].key.plan.writing_mode);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.runs[0].y_offset, 0.001);
}

test "mark attachment propagation keeps long advances in user space" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 50000 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 1, .x_advance = 0, .x_offset = 12 },
    };
    var links = [_]attachment.Link{
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    attachment.propagateOffsets(GlyphPosition, &glyphs, &links, .forward, .horizontal);

    // Large paragraphs can place a mark many glyph advances after its base
    // before MarkBase/MarkLig positioning pulls it back. This offset is well
    // within f32 layout range and must not be converted back through i16.
    try std.testing.expectApproxEqAbs(@as(f32, 12.0 - 50000.0), glyphs[1].x_offset, 0.01);
}
