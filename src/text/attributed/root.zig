//! Attributed UTF-8 model, owned results, and standalone layout operations.

const std = @import("std");
const glyph_position = @import("../../layout/glyph_position.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const paragraph_options = @import("../../layout/paragraph/options.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const unicode = @import("../../unicode.zig");
const style_model = @import("../style/root.zig");
const attributed_paragraph = @import("paragraph.zig");

const ByteRange = style_model.ByteRange;
const TextStyle = style_model.TextStyle;
const StyleSpan = style_model.StyleSpan;
const ParagraphStyle = style_model.ParagraphStyle;

pub const TextMetrics = paragraph_types.TextMetrics;

pub const AttributedRun = struct {
    byte_range: ByteRange,
    style: TextStyle,
};

pub const PositionedAttributedRun = struct {
    run: AttributedRun,
    x: f32,
    baseline: f32,
    metrics: TextMetrics,
};

pub const AttributedGlyphRun = struct {
    allocator: std.mem.Allocator,
    run: AttributedRun,
    x: f32,
    baseline: f32,
    glyphs: []glyph_position.GlyphPosition,
    metrics: TextMetrics,

    pub fn deinit(self: *AttributedGlyphRun) void {
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub const AttributedText = struct {
    text: []const u8,
    spans: []const StyleSpan,
    paragraph_style: ParagraphStyle = .{},
    inline_objects: []const inline_object.Object = &.{},

    pub fn validate(self: AttributedText) !void {
        if (!std.unicode.utf8ValidateSlice(self.text)) return error.InvalidUtf8;
        try inline_object.validate(self.text, self.inline_objects);
        for (self.spans) |span| {
            if (span.byte_range.end() > self.text.len) return error.InvalidRange;
            if (!isUtf8Boundary(self.text, span.byte_range.start)) return error.InvalidUtf8Boundary;
            if (!isUtf8Boundary(self.text, span.byte_range.end())) return error.InvalidUtf8Boundary;
        }
    }

    pub fn styleAtByte(self: AttributedText, byte_offset: usize) ?TextStyle {
        if (byte_offset >= self.text.len) return null;
        for (self.spans) |span| {
            if (span.byte_range.contains(byte_offset)) return span.style;
        }
        return null;
    }

    pub fn primaryTextStyle(self: AttributedText) TextStyle {
        if (self.text.len > 0) {
            if (self.styleAtByte(0)) |style| return style;
        }
        if (self.spans.len > 0) return self.spans[0].style;
        return .{};
    }

    pub fn paragraphOptions(self: AttributedText, max_width: f32) paragraph_options.Options {
        const style = self.primaryTextStyle();
        var options = self.paragraph_style.paragraphOptions(max_width);
        if (style.line_height) |line_height| options.line_height = line_height;
        options.letter_spacing = style.letter_spacing;
        options.word_spacing = style.word_spacing;
        options.normalized_variation_coords = style.normalized_variation_coords;
        options.inline_objects = self.inline_objects;
        return options;
    }

    pub fn runs(self: AttributedText, allocator: std.mem.Allocator) ![]AttributedRun {
        try self.validate();
        var boundaries = std.ArrayList(usize).empty;
        defer boundaries.deinit(allocator);
        try boundaries.append(allocator, 0);
        try boundaries.append(allocator, self.text.len);
        for (self.spans) |span| {
            try boundaries.append(allocator, span.byte_range.start);
            try boundaries.append(allocator, span.byte_range.end());
        }
        std.mem.sort(usize, boundaries.items, {}, usizeLessThan);
        const unique_len = uniqueSortedUsize(boundaries.items);
        boundaries.shrinkRetainingCapacity(unique_len);

        var output = std.ArrayList(AttributedRun).empty;
        errdefer output.deinit(allocator);
        var index: usize = 0;
        while (index + 1 < boundaries.items.len) : (index += 1) {
            const start = boundaries.items[index];
            const end = boundaries.items[index + 1];
            if (start == end) continue;
            try output.append(allocator, .{
                .byte_range = .{ .start = start, .len = end - start },
                .style = self.styleAtByte(start) orelse TextStyle{},
            });
        }
        return try output.toOwnedSlice(allocator);
    }
};

pub fn measureAttributedTextUtf8(cascade: font_fallback.Cascade, buffer: *context_output.Buffer, attributed: AttributedText, max_width: f32) !TextMetrics {
    return try attributed_paragraph.measureAttributed(
        cascade,
        buffer,
        attributed,
        max_width,
    );
}

pub fn measureAttributedRunsUtf8(allocator: std.mem.Allocator, cascade: font_fallback.Cascade, attributed: AttributedText) !TextMetrics {
    if (attributed.inline_objects.len != 0) {
        return error.InlineObjectsRequireParagraphLayout;
    }
    var positioned = try layoutAttributedRunsUtf8(allocator, cascade, attributed);
    defer positioned.deinit();
    return positioned.metrics;
}

fn paragraphOptionsForStyle(style: TextStyle) paragraph_options.Options {
    return .{
        .max_width = std.math.inf(f32),
        .line_height = style.line_height,
        .letter_spacing = style.letter_spacing,
        .word_spacing = style.word_spacing,
        .script_tag = if (style.script) |script| unicode.openTypeScriptTag(script) else null,
        .language_tag = if (style.locale) |locale| unicode.openTypeLanguageTagForLocale(locale) else null,
        .features = style.font_features,
        .normalized_variation_coords = style.normalized_variation_coords,
    };
}

pub const AttributedRunLayout = struct {
    allocator: std.mem.Allocator,
    runs: []PositionedAttributedRun,
    metrics: TextMetrics,

    pub fn deinit(self: *AttributedRunLayout) void {
        self.allocator.free(self.runs);
        self.* = undefined;
    }
};

pub const AttributedGlyphRunLayout = struct {
    allocator: std.mem.Allocator,
    runs: []AttributedGlyphRun,
    metrics: TextMetrics,

    pub fn deinit(self: *AttributedGlyphRunLayout) void {
        for (self.runs) |*run| run.deinit();
        self.allocator.free(self.runs);
        self.* = undefined;
    }
};

pub const AttributedStyleRun = attributed_paragraph.StyleRun(TextStyle);
pub const TextDecorationKind = @import("decorations.zig").Kind;
pub const TextDecorationSegment = @import("decorations.zig").Segment;
pub const AttributedParagraphLayout = attributed_paragraph.Result(TextStyle);

pub fn layoutAttributedParagraphUtf8(
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    attributed: AttributedText,
    max_width: f32,
) !AttributedParagraphLayout {
    return try attributed_paragraph.layoutAttributed(
        allocator,
        cascade,
        attributed,
        max_width,
    );
}

pub fn layoutAttributedRunsUtf8(allocator: std.mem.Allocator, cascade: font_fallback.Cascade, attributed: AttributedText) !AttributedRunLayout {
    if (attributed.inline_objects.len != 0) {
        return error.InlineObjectsRequireParagraphLayout;
    }
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    var positioned = std.ArrayList(PositionedAttributedRun).empty;
    errdefer positioned.deinit(allocator);
    var width: f32 = 0;
    var height: f32 = 0;
    var baseline: f32 = 0;
    var ascent: f32 = 0;
    var descent: f32 = 0;
    var leading: f32 = 0;
    for (runs) |run| {
        const run_text = attributed.text[run.byte_range.start..run.byte_range.end()];
        const options = paragraphOptionsForStyle(run.style);
        const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8WithOptions(cascade, &buffer, run_text, run.style.font_size, options);
        const metrics = textMetricsFromParagraph(paragraph);
        try positioned.append(allocator, .{
            .run = run,
            .x = width,
            .baseline = metrics.baseline,
            .metrics = metrics,
        });
        width += metrics.width;
        height = @max(height, metrics.height);
        baseline = @max(baseline, metrics.baseline);
        ascent = @max(ascent, metrics.ascent);
        descent = @max(descent, metrics.descent);
        leading = @max(leading, metrics.leading);
    }
    return .{
        .allocator = allocator,
        .runs = try positioned.toOwnedSlice(allocator),
        .metrics = .{ .width = width, .height = height, .baseline = baseline, .ascent = ascent, .descent = descent, .leading = leading },
    };
}

pub fn layoutAttributedGlyphRunsUtf8(allocator: std.mem.Allocator, cascade: font_fallback.Cascade, attributed: AttributedText) !AttributedGlyphRunLayout {
    if (attributed.inline_objects.len != 0) {
        return error.InlineObjectsRequireParagraphLayout;
    }
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    var positioned = std.ArrayList(AttributedGlyphRun).empty;
    errdefer {
        for (positioned.items) |*run| run.deinit();
        positioned.deinit(allocator);
    }
    var width: f32 = 0;
    var height: f32 = 0;
    var baseline: f32 = 0;
    var ascent: f32 = 0;
    var descent: f32 = 0;
    var leading: f32 = 0;
    for (runs) |run| {
        const run_text = attributed.text[run.byte_range.start..run.byte_range.end()];
        const options = paragraphOptionsForStyle(run.style);
        const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8WithOptions(cascade, &buffer, run_text, run.style.font_size, options);
        const metrics = textMetricsFromParagraph(paragraph);
        const glyphs = try allocator.dupe(glyph_position.GlyphPosition, paragraph.glyphs);
        errdefer allocator.free(glyphs);
        try positioned.append(allocator, .{
            .allocator = allocator,
            .run = run,
            .x = width,
            .baseline = metrics.baseline,
            .glyphs = glyphs,
            .metrics = metrics,
        });
        width += metrics.width;
        height = @max(height, metrics.height);
        baseline = @max(baseline, metrics.baseline);
        ascent = @max(ascent, metrics.ascent);
        descent = @max(descent, metrics.descent);
        leading = @max(leading, metrics.leading);
    }
    return .{
        .allocator = allocator,
        .runs = try positioned.toOwnedSlice(allocator),
        .metrics = .{ .width = width, .height = height, .baseline = baseline, .ascent = ascent, .descent = descent, .leading = leading },
    };
}

fn textMetricsFromParagraph(paragraph: paragraph_types.ParagraphLayout) TextMetrics {
    return paragraph_types.metrics(paragraph);
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0b1100_0000) != 0b1000_0000;
}

fn usizeLessThan(_: void, lhs: usize, rhs: usize) bool {
    return lhs < rhs;
}

fn uniqueSortedUsize(values: []usize) usize {
    if (values.len == 0) return 0;
    var write: usize = 1;
    for (values[1..]) |value| {
        if (value == values[write - 1]) continue;
        values[write] = value;
        write += 1;
    }
    return write;
}

test {
    _ = @import("model_tests.zig");
    _ = @import("tests.zig");
}
