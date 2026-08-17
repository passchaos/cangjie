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
const paragraph_options = @import("../layout/paragraph/options.zig");
const retained_paragraph = @import("../layout/paragraph/retained.zig");
const styled_paragraph_layout = @import("../layout/paragraph/styled.zig");
const paragraph_types = @import("../layout/types/paragraph.zig");
const run_types = @import("../layout/types/runs.zig");
const line_break_analysis = @import("../layout/line_break/analysis.zig");
const line_break_opportunity =
    @import("../layout/line_break/opportunity.zig");
const paragraph_reflow = @import("../layout/line_break/reflow/root.zig");
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
        const grapheme_clusters = try unicode.itemizeGraphemeClusters(allocator, text);
        errdefer allocator.free(grapheme_clusters);
        const line_breaks = try line_break_analysis.itemizeWithHyphenation(
            allocator,
            text,
            grapheme_clusters,
            options.word_break_dictionary,
            options.hyphenation_dictionary,
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

        return .{
            .allocator = allocator,
            .text = owned_text,
            .glyphs = owned_glyphs,
            .runs = owned_runs,
            .grapheme_clusters = grapheme_clusters,
            .line_breaks = line_breaks,
            .inline_object_indexes = inline_object_indexes,
            .word_break_dictionary = options.word_break_dictionary,
            .hyphenation_dictionary = options.hyphenation_dictionary,
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
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
            options.hyphenation_dictionary,
        );
        if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        try inline_object.position(buffer, options.inline_objects);
        return buffer.paragraphLayout();
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try paragraph_options.validate(options);
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
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
            options.hyphenation_dictionary,
        );
        if (plan_bidi.paragraphNeedsReorder(text, options.direction)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        try inline_object.position(buffer, options.inline_objects);
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
    if (objects.len == 0) {
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
    var source_start: usize = 0;
    var pen = PenPosition{};
    for (objects) |object| {
        if (source_start < object.byte_index) {
            const segment = text[source_start..object.byte_index];
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
                .text = segment,
                .cluster_base = source_start,
                .pen = pen,
            });
        }
        const object_advance = if (object.kind == .in_flow) object.width else 0;
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = 0,
            .codepoint = inline_object.object_replacement_character,
            .cluster = object.byte_index,
            .source_byte_len = inline_object.object_replacement_utf8.len,
            .x_advance = object_advance,
            .flags = .{ .inline_object = true },
        });
        pen.x += object_advance;
        source_start =
            object.byte_index + inline_object.object_replacement_utf8.len;
    }
    if (source_start < text.len) {
        const segment = text[source_start..];
        var context = DynamicFallbackContext{
            .buffer = buffer,
            .metrics_cache = metrics_cache,
            .glyph_index_cache = glyph_index_cache,
            .font_size = font_size,
            .options = options,
        };
        _ = try fallback_segment.shape(&context, .{
            .cascade = cascade,
            .fallback_cache = fallback_cache,
            .glyph_index_cache = glyph_index_cache,
            .text = segment,
            .cluster_base = source_start,
            .pen = pen,
        });
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
) !void {
    return try paragraph_reflow.build(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
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
