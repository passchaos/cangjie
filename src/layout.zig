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
const positioning = @import("shaping/pipeline/positioning/root.zig");
const position_attachments = positioning.attachments;
const diagnostics = @import("shaping/diagnostics/root.zig");
const diagnostic_fallback = diagnostics.fallback;
const diagnostic_orchestration = diagnostics.orchestration;
const diagnostic_types = diagnostics.types;
const font_fallback = @import("shaping/fallback/font/root.zig");
const fallback_segment = @import("shaping/fallback/segment.zig");
const script_run_itemization =
    @import("shaping/itemization/script_runs.zig");
const bidi_reorder = @import("layout/bidi/reorder/root.zig");
const glyph_position = @import("layout/glyph_position.zig");
const paragraph_options = @import("layout/paragraph/options.zig");
const retained_paragraph = @import("layout/paragraph/retained.zig");
const styled_paragraph_layout = @import("layout/paragraph/styled.zig");
const paragraph_types = @import("layout/types/paragraph.zig");
const run_types = @import("layout/types/runs.zig");
const line_break_analysis = @import("layout/line_break/analysis.zig");
const paragraph_reflow = @import("layout/line_break/reflow/root.zig");
const shaped_boundary = @import("layout/line_break/shaped_boundary.zig");
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
        return try styled_paragraph_layout.layout(.{
            .cascade = cascade,
            .buffer = buffer,
            .styled = styled,
            .text = text,
            .default_font_size = default_font_size,
            .spans = spans,
            .options = options,
        });
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
