const std = @import("std");
const decorations = @import("decorations.zig");
const face_mod = @import("../../font/face/root.zig");
const Font = @import("../../font.zig").Font;
const glyph_position = @import("../../layout/glyph_position.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
const styled_paragraph = @import("../../layout/styled_paragraph.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const run_types = @import("../../layout/types/runs.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const unicode = @import("../../unicode.zig");

pub fn StyleRun(comptime TextStyle: type) type {
    return struct {
        style_index: u32,
        style: TextStyle,
        glyph_start: usize,
        glyph_len: usize,
    };
}

pub fn Result(comptime TextStyle: type) type {
    return struct {
        allocator: std.mem.Allocator,
        glyphs: []glyph_position.GlyphPosition,
        font_runs: []run_types.CascadeRun,
        normalized_variation_coords: []f32,
        lines: []paragraph_types.ParagraphLine,
        inline_objects: []inline_object.Positioned,
        style_runs: []StyleRun(TextStyle),
        decorations: []decorations.Segment,
        content_widths: paragraph_types.ContentWidths,
        paragraph: paragraph_types.ParagraphLayout,

        /// `TextStyle` can contain borrowed strings and feature/variation
        /// slices. Callers keep those payloads alive until this result is no
        /// longer used; the geometry and run arrays themselves are owned here.
        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.decorations);
            self.allocator.free(self.style_runs);
            self.allocator.free(self.inline_objects);
            self.allocator.free(self.lines);
            self.allocator.free(self.font_runs);
            self.allocator.free(self.normalized_variation_coords);
            self.allocator.free(self.glyphs);
            self.* = undefined;
        }
    };
}

pub fn layoutAttributed(
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    attributed: anytype,
    max_width: f32,
) !Result(@TypeOf(attributed.primaryTextStyle())) {
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    const spans = try layoutSpansForRuns(allocator, runs);
    defer allocator.free(spans);
    return try layoutResolved(
        allocator,
        cascade,
        attributed,
        runs,
        spans,
        max_width,
    );
}

pub fn layoutResolved(
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    attributed: anytype,
    runs: anytype,
    spans: []const styled_paragraph.Span,
    max_width: f32,
) !Result(@TypeOf(attributed.primaryTextStyle())) {
    const primary_style = attributed.primaryTextStyle();
    var options = attributed.paragraph_style.paragraphOptions(max_width);
    // Paragraph-wide line height is a minimum shared by every style. A style's
    // line height is carried separately and affects only intersecting lines.
    options.line_height = attributed.paragraph_style.line_height;
    options.inline_objects = attributed.inline_objects;
    if (options.writing_mode.isVertical()) {
        for (runs) |run| {
            if (run.style.decoration.underline or
                run.style.decoration.strikethrough)
            {
                return error.UnsupportedVerticalParagraphOptions;
            }
        }
    }

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        attributed.text,
        primary_style.font_size,
        spans,
        options,
    );

    const glyphs = try allocator.dupe(glyph_position.GlyphPosition, paragraph.glyphs);
    errdefer allocator.free(glyphs);
    const font_runs = try allocator.dupe(run_types.CascadeRun, paragraph.runs);
    errdefer allocator.free(font_runs);
    const normalized_variation_coords = try allocator.dupe(
        f32,
        paragraph.normalized_variation_coords,
    );
    errdefer allocator.free(normalized_variation_coords);
    const lines = try allocator.dupe(paragraph_types.ParagraphLine, paragraph.lines);
    errdefer allocator.free(lines);
    const inline_objects =
        try allocator.dupe(inline_object.Positioned, paragraph.inline_objects);
    errdefer allocator.free(inline_objects);
    const styled_glyphs = styled.glyphMetadata();
    if (styled_glyphs.len != glyphs.len) return error.InvalidStyleSpans;
    const style_runs = try buildStyleRuns(
        @TypeOf(primary_style),
        allocator,
        styled_glyphs,
        runs,
    );
    errdefer allocator.free(style_runs);
    const decoration_segments = try decorations.build(
        allocator,
        paragraph,
        style_runs,
    );
    errdefer allocator.free(decoration_segments);

    return .{
        .allocator = allocator,
        .glyphs = glyphs,
        .font_runs = font_runs,
        .normalized_variation_coords = normalized_variation_coords,
        .lines = lines,
        .inline_objects = inline_objects,
        .style_runs = style_runs,
        .decorations = decoration_segments,
        .content_widths = styled.contentWidths() orelse
            return error.InvalidParagraphLayout,
        .paragraph = .{
            .glyphs = glyphs,
            .runs = font_runs,
            .normalized_variation_coords = normalized_variation_coords,
            .lines = lines,
            .inline_objects = inline_objects,
            .writing_mode = paragraph.writing_mode,
            .width = paragraph.width,
            .height = paragraph.height,
        },
    };
}

pub fn measureAttributed(
    cascade: font_fallback.Cascade,
    buffer: *context_output.Buffer,
    attributed: anytype,
    max_width: f32,
) !paragraph_types.TextMetrics {
    const runs = try attributed.runs(buffer.allocator);
    defer buffer.allocator.free(runs);
    const spans = try layoutSpansForRuns(buffer.allocator, runs);
    defer buffer.allocator.free(spans);
    return try measureResolved(cascade, buffer, attributed, spans, max_width);
}

pub fn measureResolved(
    cascade: font_fallback.Cascade,
    buffer: *context_output.Buffer,
    attributed: anytype,
    spans: []const styled_paragraph.Span,
    max_width: f32,
) !paragraph_types.TextMetrics {
    const primary_style = attributed.primaryTextStyle();
    var styled = styled_buffer.Buffer.init(buffer.allocator);
    defer styled.deinit();
    var options = attributed.paragraph_style.paragraphOptions(max_width);
    options.inline_objects = attributed.inline_objects;
    const paragraph = try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        buffer,
        &styled,
        attributed.text,
        primary_style.font_size,
        spans,
        options,
    );
    return metricsFromParagraph(paragraph);
}

fn layoutSpansForRuns(
    allocator: std.mem.Allocator,
    runs: anytype,
) ![]styled_paragraph.Span {
    const spans = try allocator.alloc(styled_paragraph.Span, runs.len);
    errdefer allocator.free(spans);
    for (runs, spans, 0..) |run, *span, style_index| {
        const public_style_index = std.math.cast(u32, style_index) orelse
            return error.TooManyStyleSpans;
        span.* = .{
            .byte_start = run.byte_range.start,
            .byte_len = run.byte_range.len,
            .style_index = public_style_index,
            .font_size = run.style.font_size,
            .script_tag = if (run.style.script) |script|
                unicode.openTypeScriptTag(script)
            else
                null,
            .language_tag = if (run.style.locale) |locale|
                unicode.openTypeLanguageTagForLocale(locale)
            else
                null,
            .features = run.style.font_features,
            .normalized_variation_coords = run.style.normalized_variation_coords,
            .letter_spacing = run.style.letter_spacing,
            .word_spacing = run.style.word_spacing,
            .minimum_line_height = run.style.line_height,
            .vertical_align = run.style.vertical_align,
            .wrap_mode = run.style.wrap_mode,
            .word_break = run.style.word_break,
            .overflow_wrap = run.style.overflow_wrap,
        };
    }
    return spans;
}

pub fn layoutSpansForResolvedRuns(
    allocator: std.mem.Allocator,
    runs: anytype,
    fonts: []const []const *const Font,
) ![]styled_paragraph.Span {
    if (fonts.len != runs.len) return error.InvalidStyleSpans;
    const spans = try layoutSpansForRuns(allocator, runs);
    errdefer allocator.free(spans);
    for (spans, fonts) |*span, run_fonts| {
        if (run_fonts.len == 0) return error.EmptyFontCascade;
        span.faces = face_mod.backend.faces(run_fonts);
    }
    return spans;
}

fn buildStyleRuns(
    comptime TextStyle: type,
    allocator: std.mem.Allocator,
    styled_glyphs: []const styled_buffer.Metadata,
    logical_runs: anytype,
) ![]StyleRun(TextStyle) {
    var output = std.ArrayList(StyleRun(TextStyle)).empty;
    errdefer output.deinit(allocator);
    if (styled_glyphs.len == 0) return try output.toOwnedSlice(allocator);

    var start: usize = 0;
    var style_index = styled_glyphs[0].style_index;
    var index: usize = 1;
    while (index <= styled_glyphs.len) : (index += 1) {
        if (index < styled_glyphs.len and
            styled_glyphs[index].style_index == style_index)
        {
            continue;
        }
        if (style_index >= logical_runs.len) return error.InvalidStyleSpans;
        try output.append(allocator, .{
            .style_index = style_index,
            .style = logical_runs[style_index].style,
            .glyph_start = start,
            .glyph_len = index - start,
        });
        if (index < styled_glyphs.len) {
            start = index;
            style_index = styled_glyphs[index].style_index;
        }
    }
    return try output.toOwnedSlice(allocator);
}

fn metricsFromParagraph(paragraph: paragraph_types.ParagraphLayout) paragraph_types.TextMetrics {
    return paragraph_types.metrics(paragraph);
}
