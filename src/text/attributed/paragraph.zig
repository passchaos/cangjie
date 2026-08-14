const std = @import("std");
const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
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
        glyphs: []layout.GlyphPosition,
        font_runs: []layout.CascadeRun,
        lines: []layout.ParagraphLine,
        style_runs: []StyleRun(TextStyle),
        paragraph: layout.ParagraphLayout,

        /// `TextStyle` can contain borrowed strings and feature/variation
        /// slices. Callers keep those payloads alive until this result is no
        /// longer used; the geometry and run arrays themselves are owned here.
        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.style_runs);
            self.allocator.free(self.lines);
            self.allocator.free(self.font_runs);
            self.allocator.free(self.glyphs);
            self.* = undefined;
        }
    };
}

pub fn layoutAttributed(
    allocator: std.mem.Allocator,
    cascade: layout.FontCascade,
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
    cascade: layout.FontCascade,
    attributed: anytype,
    runs: anytype,
    spans: []const layout.StyledParagraphSpan,
    max_width: f32,
) !Result(@TypeOf(attributed.primaryTextStyle())) {
    const primary_style = attributed.primaryTextStyle();
    var options = attributed.paragraph_style.paragraphOptions(max_width);
    // Paragraph-wide line height is a minimum shared by every style. A style's
    // line height is carried separately and affects only intersecting lines.
    options.line_height = attributed.paragraph_style.line_height;

    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = layout.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const paragraph = try layout.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        attributed.text,
        primary_style.font_size,
        spans,
        options,
    );

    const glyphs = try allocator.dupe(layout.GlyphPosition, paragraph.glyphs);
    errdefer allocator.free(glyphs);
    const font_runs = try allocator.dupe(layout.CascadeRun, paragraph.runs);
    errdefer allocator.free(font_runs);
    const lines = try allocator.dupe(layout.ParagraphLine, paragraph.lines);
    errdefer allocator.free(lines);
    const styled_glyphs = styled.glyphMetadata();
    if (styled_glyphs.len != glyphs.len) return error.InvalidStyleSpans;
    const style_runs = try buildStyleRuns(
        @TypeOf(primary_style),
        allocator,
        styled_glyphs,
        runs,
    );
    errdefer allocator.free(style_runs);

    return .{
        .allocator = allocator,
        .glyphs = glyphs,
        .font_runs = font_runs,
        .lines = lines,
        .style_runs = style_runs,
        .paragraph = .{
            .glyphs = glyphs,
            .runs = font_runs,
            .lines = lines,
            .width = paragraph.width,
            .height = paragraph.height,
        },
    };
}

pub fn measureAttributed(
    cascade: layout.FontCascade,
    buffer: *layout.LayoutBuffer,
    attributed: anytype,
    max_width: f32,
) !layout.TextMetrics {
    const runs = try attributed.runs(buffer.allocator);
    defer buffer.allocator.free(runs);
    const spans = try layoutSpansForRuns(buffer.allocator, runs);
    defer buffer.allocator.free(spans);
    return try measureResolved(cascade, buffer, attributed, spans, max_width);
}

pub fn measureResolved(
    cascade: layout.FontCascade,
    buffer: *layout.LayoutBuffer,
    attributed: anytype,
    spans: []const layout.StyledParagraphSpan,
    max_width: f32,
) !layout.TextMetrics {
    const primary_style = attributed.primaryTextStyle();
    var styled = layout.StyledParagraphBuffer.init(buffer.allocator);
    defer styled.deinit();
    const paragraph = try layout.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        buffer,
        &styled,
        attributed.text,
        primary_style.font_size,
        spans,
        attributed.paragraph_style.paragraphOptions(max_width),
    );
    return metricsFromParagraph(paragraph);
}

fn layoutSpansForRuns(
    allocator: std.mem.Allocator,
    runs: anytype,
) ![]layout.StyledParagraphSpan {
    const spans = try allocator.alloc(layout.StyledParagraphSpan, runs.len);
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
        };
    }
    return spans;
}

pub fn layoutSpansForResolvedRuns(
    allocator: std.mem.Allocator,
    runs: anytype,
    fonts: []const []const *const Font,
) ![]layout.StyledParagraphSpan {
    if (fonts.len != runs.len) return error.InvalidStyleSpans;
    const spans = try layoutSpansForRuns(allocator, runs);
    errdefer allocator.free(spans);
    for (spans, fonts) |*span, run_fonts| {
        if (run_fonts.len == 0) return error.EmptyFontCascade;
        span.fonts = run_fonts;
    }
    return spans;
}

fn buildStyleRuns(
    comptime TextStyle: type,
    allocator: std.mem.Allocator,
    styled_glyphs: []const layout.StyledGlyphMetadata,
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

fn metricsFromParagraph(paragraph: layout.ParagraphLayout) layout.TextMetrics {
    if (paragraph.lines.len == 0) {
        return .{
            .width = 0,
            .height = 0,
            .baseline = 0,
            .ascent = 0,
            .descent = 0,
            .leading = 0,
        };
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
