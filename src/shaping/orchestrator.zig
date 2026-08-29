//! Ordinary shaping, fallback, paragraph, and measurement orchestration.
//!
//! This module owns the concrete shaper below the public extended facade. It
//! deliberately depends only on focused layout-domain modules; ranged feature
//! shaping can layer on top without creating a dependency cycle.

const std = @import("std");

const face_mod = @import("../font/face/root.zig");
const Font = @import("../font.zig").Font;
const cache_mod = @import("context/cache/root.zig");
const context_output = @import("context/output.zig");
const pipeline_types = @import("pipeline/types.zig");
const segment_pipeline = @import("pipeline/segment.zig");
const shaping_plan = @import("plan/root.zig");
const plan_bidi = @import("plan/bidi.zig");
const plan_resolution = @import("plan/resolution.zig");
const plan_validation = @import("plan/validation.zig");
const font_fallback = @import("fallback/font/root.zig");
const fallback_segment = @import("fallback/segment.zig");
const script_run_itemization = @import("itemization/script_runs.zig");
const bidi_reorder = @import("../layout/bidi/reorder/root.zig");
const glyph_position = @import("../layout/glyph_position.zig");
const inline_object = @import("../layout/inline_object/root.zig");
const font_expansion =
    @import("../layout/justification/font_expansion.zig");
const jstf_justification =
    @import("../layout/justification/jstf.zig");
const jstf_extender =
    @import("../layout/justification/jstf/extender.zig");
const kashida_justification =
    @import("../layout/justification/kashida.zig");
const paragraph_options = @import("../layout/paragraph/options.zig");
const paragraph_source_items =
    @import("../layout/paragraph/source_items.zig");
const paragraph_tabs = @import("../layout/paragraph/tabs.zig");
const retained_paragraph = @import("../layout/paragraph/retained.zig");
const paragraph_reshape = @import("../layout/paragraph/reshape.zig");
const vertical_hanging = @import("../layout/paragraph/vertical_hanging.zig");
const vertical_justification =
    @import("../layout/paragraph/vertical_justification.zig");
const styled_paragraph_layout = @import("../layout/paragraph/styled.zig");
const paragraph_types = @import("../layout/types/paragraph.zig");
const run_types = @import("../layout/types/runs.zig");
const line_break_analysis = @import("../layout/line_break/analysis.zig");
const line_break_opportunity =
    @import("../layout/line_break/opportunity.zig");
const paragraph_reflow = @import("../layout/line_break/reflow/root.zig");
const punctuation_compression =
    @import("../layout/punctuation/compression.zig");
const punctuation_hanging = @import("../layout/punctuation/hanging.zig");
const segmentation = @import("../text/segmentation/root.zig");
const unicode = @import("../unicode.zig");
const shape_profile_mod = @import("../shape_profile.zig");

const FontFallbackCache = cache_mod.FontFallbackCache;
const GlyphIndexCache = cache_mod.GlyphIndexCache;
const GlyphMetricsCache = cache_mod.GlyphMetricsCache;
const ShapedRunCache = cache_mod.ShapedRunCache;
const LayoutBuffer = context_output.Buffer;
const FontCascade = font_fallback.Cascade;
const ShapeOptions = shaping_plan.ShapeOptions;
const ShapePlanKey = shaping_plan.ShapePlanKey;
const bidi_order = @import("../text/bidi.zig");
const GlyphPosition = glyph_position.GlyphPosition;
const GlyphRun = run_types.GlyphRun;
const CascadeRun = run_types.CascadeRun;
const ShapedText = run_types.ShapedText;
const ScriptedText = run_types.ScriptedText;
const ParagraphOptions = paragraph_options.Options;
const ParagraphLayout = paragraph_types.ParagraphLayout;
const TextMetrics = paragraph_types.TextMetrics;
const ShapedParagraph = retained_paragraph.ShapedParagraph;
const StyledParagraphSpan = @import("../layout/styled_paragraph.zig").Span;
const StyledParagraphBuffer = @import("../layout/styled_buffer.zig").Buffer;
const BaselineMetrics = paragraph_reflow.BaselineMetrics;
const TextDirection = pipeline_types.TextDirection;

pub const TextShaper = struct {
    pub fn shapeUtf8(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !GlyphRun {
        return try shapeUtf8WithOptions(font, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8WithOptions(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        return try shapeSingleFontInto(font, null, null, buffer, text, font_size, options, &.{});
    }

    pub fn shapeUtf8WithCaches(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        return try shapeSingleFontInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, options, &.{});
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
                try buffer.variation_coords.appendSlice(
                    buffer.allocator,
                    entry.variation_coords,
                );
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
    /// Unlike `layoutParagraphUtf8`, this performs whole-paragraph GSUB/GPOS
    /// and fallback only once. Call `ShapedParagraph.layout` with different
    /// `ParagraphOptions` to rebuild visual lines. Justified Arabic lines may
    /// still run bounded, line-local shaping after real U+0640 insertion.
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
        try paragraph_options.validateForText(text, options);
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;
        const shape_options = paragraph_options.shapeOptions(options);
        try shapeParagraphContent(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            shaped_cache,
            buffer,
            text,
            font_size,
            shape_options,
            options.inline_objects,
        );
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        const logical_shaped = buffer.shapedText();

        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);
        const owned_glyphs = try allocator.dupe(GlyphPosition, logical_shaped.glyphs);
        errdefer allocator.free(owned_glyphs);
        const owned_runs = try allocator.dupe(CascadeRun, logical_shaped.runs);
        errdefer allocator.free(owned_runs);
        const owned_variation_coords = try allocator.dupe(
            f32,
            logical_shaped.normalized_variation_coords,
        );
        errdefer allocator.free(owned_variation_coords);
        const grapheme_clusters = try unicode.itemizeGraphemeClusters(allocator, text);
        errdefer allocator.free(grapheme_clusters);
        const line_breaks = try line_break_analysis.itemizeWithHyphenation(
            allocator,
            text,
            grapheme_clusters,
            options.word_break_dictionary,
            options.hyphenation.dictionary,
            .{
                .wrap_mode = .word,
                .word_break = .normal,
                .overflow_wrap = .break_word,
            },
            &.{},
        );
        errdefer allocator.free(line_breaks);
        const inline_object_indexes = try allocator.alloc(
            usize,
            options.inline_objects.len,
        );
        errdefer allocator.free(inline_object_indexes);
        for (inline_object_indexes, options.inline_objects) |*index, object| {
            index.* = object.byte_index;
        }
        const cascade_fonts = try allocator.dupe(
            *const Font,
            cascade.fonts,
        );
        errdefer allocator.free(cascade_fonts);
        const needs_bidi_reorder = plan_bidi.paragraphNeedsReorder(
            text,
            options.direction,
        );
        const pure_rtl_lines = options.direction == .rtl and
            bidi_order.visualOrderInputKind(owned_text, true) == .pure_rtl;
        const pure_rtl_may_have_mirroring = pure_rtl_lines and
            bidi_order.runMayHaveBidiMirroring(owned_glyphs);
        const simple_reflow = simpleRetainedReflowShape(
            owned_text,
            owned_glyphs,
        );
        const inferred_script_tag = if (shape_options.script_tag == null)
            ShapePlanKey.fromText(text, shape_options).script_tag
        else
            unicode.openTypeScriptTag(unicode.inferOpenTypeScript(text));
        const inferred_language_tag = if (shape_options.language_tag == null)
            ShapePlanKey.fromText(text, shape_options).language_tag
        else
            unicode.inferOpenTypeLanguageTag(text);
        var bidi_paragraph = if (needs_bidi_reorder)
            try unicode.resolveBidiParagraph(
                allocator,
                owned_text,
                if (options.direction == .rtl) .rtl else .ltr,
            )
        else
            null;
        errdefer if (bidi_paragraph) |*paragraph| paragraph.deinit();

        return .{
            .allocator = allocator,
            .text = owned_text,
            .glyphs = owned_glyphs,
            .runs = owned_runs,
            .normalized_variation_coords = owned_variation_coords,
            .grapheme_clusters = grapheme_clusters,
            .line_breaks = line_breaks,
            .inline_object_indexes = inline_object_indexes,
            .word_break_dictionary = options.word_break_dictionary,
            .hyphenation_dictionary = options.hyphenation.dictionary,
            .default_metrics = defaultBaselineMetrics(cascade.fonts[0], font_size),
            .shape_key = ShapePlanKey.fromText(text, shape_options),
            .inferred_script_tag = inferred_script_tag,
            .inferred_language_tag = inferred_language_tag,
            .needs_bidi_reorder = needs_bidi_reorder,
            .pure_rtl_lines = pure_rtl_lines,
            .pure_rtl_may_have_mirroring = pure_rtl_may_have_mirroring,
            .simple_reflow = simple_reflow,
            .bidi_paragraph = bidi_paragraph,
            .cascade_fonts = cascade_fonts,
            .font_size = font_size,
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
        try paragraph_options.validateForText(text, options);
        // Paragraph layout is deliberately staged: shape first, then line-wrap
        // the finished glyph advances. That keeps OpenType substitution and
        // positioning independent from wrapping policy.
        try shapeParagraphContent(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            null,
            buffer,
            text,
            font_size,
            paragraph_options.shapeOptions(options),
            options.inline_objects,
        );
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        const recipe = paragraph_reshape.Uniform{
            .cascade = cascade,
            .fallback_cache = fallback_cache,
            .metrics_cache = metrics_cache,
            .glyph_index_cache = glyph_index_cache,
            .text = text,
            .font_size = font_size,
            .options = options,
        };
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
            options.hyphenation.dictionary,
            recipe,
        );
        try finishUniformParagraph(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            buffer,
            text,
            font_size,
            options,
        );
        return buffer.paragraphLayout(options.writing_mode);
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try paragraph_options.validateForText(text, options);
        try shapeParagraphContent(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            shaped_cache,
            buffer,
            text,
            font_size,
            paragraph_options.shapeOptions(options),
            options.inline_objects,
        );
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        const recipe = paragraph_reshape.Uniform{
            .cascade = cascade,
            .fallback_cache = fallback_cache,
            .metrics_cache = metrics_cache,
            .glyph_index_cache = glyph_index_cache,
            .text = text,
            .font_size = font_size,
            .options = options,
        };
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
            options.hyphenation.dictionary,
            recipe,
        );
        try finishUniformParagraph(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            buffer,
            text,
            font_size,
            options,
        );
        return buffer.paragraphLayout(options.writing_mode);
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

    /// Styled layout without the independent intrinsic-width calculation.
    pub fn layoutStyledParagraphUtf8WithoutContentWidths(
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
            .compute_content_widths = false,
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
    return paragraph_types.metrics(paragraph);
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

pub fn shapeSingleFontInto(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions, feature_ranges: []const unicode.GsubFeatureRange) !GlyphRun {
    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const total_start = shape_profile_mod.now(shape_profile, profile_io);
    defer {
        if (shape_profile) |p| p.total_ns += shape_profile_mod.elapsed(total_start, profile_io);
    }

    const options_start = shape_profile_mod.now(shape_profile, profile_io);
    const lookup_options = plan_resolution.forText(text, options);
    var ranged_lookup_options = lookup_options;
    ranged_lookup_options.lookup.feature_ranges = feature_ranges;
    if (shape_profile) |p| p.options_ns += shape_profile_mod.elapsed(options_start, profile_io);

    const validate_start = shape_profile_mod.now(shape_profile, profile_io);
    if (lookup_options.all_ascii) {
        try plan_validation.inputAfterAsciiTextProof(font_size, options);
    } else {
        try plan_validation.input(text, font_size, options);
    }
    if (shape_profile) |p| p.validate_ns += shape_profile_mod.elapsed(validate_start, profile_io);

    buffer.clear();

    try segment_pipeline.run(.{
        .font = font,
        .metrics_cache = metrics_cache,
        .glyph_index_cache = glyph_index_cache,
        .buffer = buffer,
        .text = text,
        .font_size = font_size,
        .cluster_base = 0,
        .lookup_options = ranged_lookup_options,
    });
    const bidi_start = shape_profile_mod.now(shape_profile, profile_io);
    if (plan_bidi.shouldReorderResolvedRun(
        options,
        buffer.shape_scratch.may_need_bidi_reorder,
    )) {
        try applyBidiVisualOrder(buffer, text, options.direction, font);
    }
    if (shape_profile) |p| p.bidi_ns += shape_profile_mod.elapsed(bidi_start, profile_io);
    return try buffer.run(
        font,
        font_size,
        options.normalized_variation_coords,
    );
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

fn shapeParagraphContent(
    cascade: FontCascade,
    fallback_cache: ?*FontFallbackCache,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    shaped_cache: ?*ShapedRunCache,
    buffer: *LayoutBuffer,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
    objects: []const inline_object.Object,
) !void {
    try plan_validation.input(text, font_size, options);
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    try inline_object.validate(text, objects);
    if (objects.len == 0 and std.mem.indexOfScalar(u8, text, '\t') == null) {
        _ = try TextShaper.shapeUtf8CascadeWithCaches(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            shaped_cache,
            buffer,
            text,
            font_size,
            options,
        );
        return;
    }

    buffer.clear();
    var pen = PenPosition{};
    var items = paragraph_source_items.Cursor.init(
        text,
        objects,
        0,
        text.len,
    );
    while (items.next()) |item| {
        switch (item) {
            .text => |range| {
                var context = DynamicFallbackContext{
                    .buffer = buffer,
                    .metrics_cache = metrics_cache,
                    .glyph_index_cache = glyph_index_cache,
                    .font_size = font_size,
                    .options = options,
                };
                pen = try fallback_segment.shape(&context, .{
                    .cascade = cascade,
                    .fallback_cache = fallback_cache,
                    .glyph_index_cache = glyph_index_cache,
                    .text = text[range.start..range.end],
                    .cluster_base = range.start,
                    .pen = pen,
                });
            },
            .object => |object| {
                const in_flow = object.kind == .in_flow;
                try buffer.glyphs.append(buffer.allocator, .{
                    .glyph_id = 0,
                    .codepoint = inline_object.object_replacement_character,
                    .cluster = object.byte_index,
                    .source_byte_len = inline_object.object_replacement_utf8.len,
                    .x_advance = if (in_flow) object.width else 0,
                    .y_advance = if (in_flow and options.writing_mode.isVertical())
                        object.height
                    else
                        0,
                    .flags = .{ .inline_object = true },
                });
                if (options.writing_mode.isVertical()) {
                    pen.y += if (in_flow) object.height else 0;
                } else {
                    pen.x += if (in_flow) object.width else 0;
                }
            },
            .tab => |byte_index| {
                try buffer.glyphs.append(
                    buffer.allocator,
                    paragraph_tabs.marker(byte_index),
                );
            },
        }
    }
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
    if (direction == .rtl and
        (bidi_reorder.tryApplyPureRtlLines(buffer, text) or
            try bidi_reorder.tryApplyPureRtlLinesWithObject(buffer, text)))
    {
        return;
    }
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
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../text/hyphenation/root.zig").Dictionary,
    recipe: anytype,
) !void {
    return try paragraph_reflow.buildWithJstfShrinkage(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
        recipe,
    );
}

fn reshapeUniformParagraph(
    cascade: FontCascade,
    fallback_cache: ?*FontFallbackCache,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    buffer: *LayoutBuffer,
    text: []const u8,
    font_size: f32,
    options: ParagraphOptions,
) !void {
    const recipe = paragraph_reshape.Uniform{
        .cascade = cascade,
        .fallback_cache = fallback_cache,
        .metrics_cache = metrics_cache,
        .glyph_index_cache = glyph_index_cache,
        .text = text,
        .font_size = font_size,
        .options = options,
    };
    try jstf_justification.apply(
        buffer,
        options,
        recipe,
    );
    try jstf_extender.apply(
        buffer,
        text,
        options,
        recipe,
    );
    try font_expansion.apply(
        buffer,
        options,
        recipe,
    );
    try kashida_justification.apply(
        buffer,
        text,
        options,
        recipe,
    );
    paragraph_reflow.applyPendingJustification(buffer);
}

fn finishUniformParagraph(
    cascade: FontCascade,
    fallback_cache: ?*FontFallbackCache,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    buffer: *LayoutBuffer,
    text: []const u8,
    font_size: f32,
    options: ParagraphOptions,
) !void {
    if (options.writing_mode.isVertical()) {
        // Vertical column construction has already completed its admitted
        // y-axis presentation stages, including ellipsis fitting. UAX #9 then
        // permutes each final column along positive-down y. Source-level JSTF,
        // variable-axis, and Kashida reshaping remain horizontal-only; generic
        // spacing and compression are inline-axis transforms and run before the
        // visual permutation.
        vertical_justification.apply(buffer, options);
        try punctuation_compression.apply(buffer, options);
        if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
            try applyParagraphLineBidiVisualOrder(
                buffer,
                text,
                options.direction,
            );
        }
        vertical_hanging.apply(buffer, options);
        bidi_reorder.recomputeRunOffsets(buffer);
        try inline_object.position(
            buffer,
            options.inline_objects,
            options.out_of_flow_placements,
            options.writing_mode,
        );
        return;
    }
    try reshapeUniformParagraph(
        cascade,
        fallback_cache,
        metrics_cache,
        glyph_index_cache,
        buffer,
        text,
        font_size,
        options,
    );
    try punctuation_compression.apply(buffer, options);
    if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
        try applyParagraphLineBidiVisualOrder(
            buffer,
            text,
            options.direction,
        );
    }
    punctuation_hanging.apply(buffer, options);
    bidi_reorder.recomputeRunOffsets(buffer);
    try inline_object.position(
        buffer,
        options.inline_objects,
        options.out_of_flow_placements,
        options.writing_mode,
    );
}

const defaultBaselineMetrics = paragraph_reflow.defaultBaselineMetrics;

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
    const variation_range = try buffer.internVariationCoords(
        lookup_options.lookup.normalized_variation_coords,
    );
    try buffer.runs.append(buffer.allocator, .{
        .font = face_mod.backend.face(font),
        .font_index = font_index,
        .font_size = font_size,
        .glyph_start = glyph_start,
        .glyph_len = glyph_len,
        .x_offset = pen.x,
        .y_offset = pen.y,
        .variation_coord_start = variation_range.start,
        .variation_coord_len = variation_range.len,
    });
    var next_pen = pen;
    for (buffer.glyphs.items[glyph_start..]) |glyph| {
        next_pen.x += glyph.x_advance;
        next_pen.y += glyph.y_advance;
    }
    return next_pen;
}

/// Prove the immutable shaped stream accepted by the narrow retained-reflow
/// loop once, during paragraph preparation. Besides moving an O(glyph-count)
/// check out of every layout call, keeping the proof next to the owned copy
/// makes it impossible for one-shot layout to opt into the retained path.
fn simpleRetainedReflowShape(
    text: []const u8,
    glyphs: []const GlyphPosition,
) bool {
    if (glyphs.len == 0) return false;
    var expected_byte_start: usize = 0;
    var active_cluster: ?usize = null;
    for (glyphs) |glyph| {
        if (glyph.source_byte_len == 0 or
            glyph.codepoint == 0x00ad or
            glyph.isTab() or
            glyph.isDiscretionaryHyphen() or
            glyph.isAutomaticHyphen() or
            glyph.codepoint == '\n' or
            glyph.codepoint == '\r' or
            glyph.codepoint == 0x0085 or
            glyph.codepoint == 0x2028 or
            glyph.codepoint == 0x2029)
        {
            return false;
        }
        const source_end = glyph.sourceByteEnd();
        if (active_cluster != null and glyph.cluster == active_cluster.?) {
            // GSUB may emit multiple adjacent outputs for one source cluster,
            // and those outputs need not all retain the same byte length. The
            // next cluster must still begin after their widest source extent.
            expected_byte_start = @max(expected_byte_start, source_end);
            continue;
        }
        if (glyph.cluster != expected_byte_start or source_end <= glyph.cluster) {
            return false;
        }
        active_cluster = glyph.cluster;
        expected_byte_start = source_end;
    }
    return expected_byte_start == text.len;
}

const ResolvedLookupOptions = pipeline_types.ResolvedLookupOptions;
