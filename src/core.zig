const std = @import("std");
const layout = @import("layout.zig");
const raster = @import("raster.zig");
const unicode = @import("unicode.zig");

pub const ByteRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: ByteRange) usize {
        return self.start + self.len;
    }

    pub fn contains(self: ByteRange, byte_offset: usize) bool {
        return byte_offset >= self.start and byte_offset < self.end();
    }
};

pub const TextRange = ByteRange;

pub const CharRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: CharRange) usize {
        return self.start + self.len;
    }
};

pub const GraphemeRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: GraphemeRange) usize {
        return self.start + self.len;
    }
};

pub const GlyphRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: GlyphRange) usize {
        return self.start + self.len;
    }
};

pub const ClusterRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: ClusterRange) usize {
        return self.start + self.len;
    }
};

pub const FontId = struct {
    index: usize,

    pub const invalid: FontId = .{ .index = std.math.maxInt(usize) };

    pub fn isValid(self: FontId) bool {
        return self.index != invalid.index;
    }
};

pub const Language = struct {
    tag: []const u8,

    pub fn isValid(self: Language) bool {
        return isValidLanguageSubtag(self.tag);
    }
};

pub const LocaleParts = struct {
    language: []const u8,
    script: ?[]const u8 = null,
    region: ?[]const u8 = null,
    variants: [8][]const u8 = undefined,
    variant_count: usize = 0,

    pub fn variantSlice(self: *const LocaleParts) []const []const u8 {
        return self.variants[0..self.variant_count];
    }
};

pub const Locale = struct {
    tag: []const u8,

    pub fn language(self: Locale) Language {
        if (self.parse()) |parts| return .{ .tag = parts.language } else |_| {}
        const end = std.mem.indexOfAny(u8, self.tag, "-_") orelse self.tag.len;
        return .{ .tag = self.tag[0..end] };
    }

    pub fn isValid(self: Locale) bool {
        _ = self.parse() catch return false;
        return true;
    }

    pub fn parse(self: Locale) !LocaleParts {
        var subtags: [16][]const u8 = undefined;
        var count: usize = 0;
        var it = std.mem.tokenizeAny(u8, self.tag, "-_");
        while (it.next()) |subtag| {
            if (count >= subtags.len) return error.TooManySubtags;
            if (!isValidLocaleSubtag(subtag)) return error.InvalidLocale;
            subtags[count] = subtag;
            count += 1;
        }
        if (count == 0 or !isValidLanguageSubtag(subtags[0])) return error.InvalidLocale;

        var index: usize = 1;
        var script: ?[]const u8 = null;
        var region: ?[]const u8 = null;
        if (index < count and isScriptSubtag(subtags[index])) {
            script = subtags[index];
            index += 1;
        }
        if (index < count and isRegionSubtag(subtags[index])) {
            region = subtags[index];
            index += 1;
        }
        var variants: [8][]const u8 = undefined;
        const variant_count = count - index;
        if (variant_count > variants.len) return error.TooManySubtags;
        for (0..variant_count) |variant_index| {
            variants[variant_index] = subtags[index + variant_index];
        }
        return .{
            .language = subtags[0],
            .script = script,
            .region = region,
            .variants = variants,
            .variant_count = variant_count,
        };
    }

    pub fn canonicalize(self: Locale, allocator: std.mem.Allocator) ![]u8 {
        const parts = try self.parse();
        var output = std.ArrayList(u8).empty;
        errdefer output.deinit(allocator);

        try appendLower(allocator, &output, canonicalLanguageAlias(parts.language));
        if (parts.script) |script| {
            try output.append(allocator, '-');
            try appendTitle(allocator, &output, script);
        }
        if (parts.region) |region| {
            try output.append(allocator, '-');
            try appendUpper(allocator, &output, region);
        }
        for (parts.variantSlice()) |variant| {
            try output.append(allocator, '-');
            try appendLower(allocator, &output, variant);
        }
        return try output.toOwnedSlice(allocator);
    }
};

pub const GlyphCluster = struct {
    text_range: ByteRange,
    glyph_range: GlyphRange,

    pub fn containsByte(self: GlyphCluster, byte_offset: usize) bool {
        return self.text_range.contains(byte_offset);
    }
};

pub const FontWeight = enum(u16) {
    thin = 100,
    extra_light = 200,
    light = 300,
    regular = 400,
    medium = 500,
    semi_bold = 600,
    bold = 700,
    extra_bold = 800,
    black = 900,
};

pub const TextFontStyle = enum {
    normal,
    italic,
    oblique,
};

pub const TextDecoration = packed struct {
    underline: bool = false,
    strikethrough: bool = false,
};

pub const TextStyle = struct {
    font_family: ?[]const u8 = null,
    font_size: f32 = 16,
    font_weight: FontWeight = .regular,
    font_style: TextFontStyle = .normal,
    font_stretch: u16 = 100,
    font_features: []const unicode.FeatureOverride = &.{},
    color: raster.Rgba = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    background_color: ?raster.Rgba = null,
    decoration: TextDecoration = .{},
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    line_height: ?f32 = null,
    locale: ?[]const u8 = null,
    script: ?unicode.Script = null,
};

pub const VerticalAlign = enum {
    baseline,
    top,
    middle,
    bottom,
};

pub const WrapMode = enum {
    no_wrap,
    word,
};

pub const OverflowMode = enum {
    clip,
    visible,
    ellipsis,
};

pub const ParagraphStyle = struct {
    direction: layout.TextDirection = .ltr,
    text_align: layout.TextAlign = .left,
    vertical_align: VerticalAlign = .baseline,
    line_height: ?f32 = null,
    max_lines: ?usize = null,
    ellipsis: bool = false,
    wrap_mode: WrapMode = .word,
    overflow_mode: OverflowMode = .clip,
    tab_width: usize = 4,
    first_line_indent: f32 = 0,
    paragraph_spacing: f32 = 0,

    pub fn paragraphOptions(self: ParagraphStyle, max_width: f32) layout.ParagraphOptions {
        return .{
            .max_width = max_width,
            .alignment = self.text_align,
            .line_height = self.line_height,
            .direction = self.direction,
            .max_lines = self.max_lines,
            .ellipsis = self.ellipsis or self.overflow_mode == .ellipsis,
            .tab_width = self.tab_width,
            .letter_spacing = 0,
            .word_spacing = 0,
            .first_line_indent = self.first_line_indent,
            .paragraph_spacing = self.paragraph_spacing,
        };
    }
};

pub const StyleSpan = struct {
    byte_range: ByteRange,
    style: TextStyle,
};

pub const TextSpan = struct {
    byte_range: ByteRange,
    text: []const u8,
};

pub const TextMetrics = layout.TextMetrics;
pub const CoreBaselineMetrics = layout.BaselineMetrics;

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
    glyphs: []layout.GlyphPosition,
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

    pub fn validate(self: AttributedText) !void {
        if (!std.unicode.utf8ValidateSlice(self.text)) return error.InvalidUtf8;
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

    pub fn paragraphOptions(self: AttributedText, max_width: f32) layout.ParagraphOptions {
        const style = self.primaryTextStyle();
        var options = self.paragraph_style.paragraphOptions(max_width);
        if (style.line_height) |line_height| options.line_height = line_height;
        options.letter_spacing = style.letter_spacing;
        options.word_spacing = style.word_spacing;
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

pub fn measureAttributedTextUtf8(cascade: layout.FontCascade, buffer: *layout.LayoutBuffer, attributed: AttributedText, max_width: f32) !TextMetrics {
    try attributed.validate();
    const style = attributed.primaryTextStyle();
    return try layout.TextShaper.measureParagraphUtf8(cascade, buffer, attributed.text, style.font_size, attributed.paragraphOptions(max_width));
}

pub fn measureAttributedRunsUtf8(allocator: std.mem.Allocator, cascade: layout.FontCascade, attributed: AttributedText) !TextMetrics {
    var positioned = try layoutAttributedRunsUtf8(allocator, cascade, attributed);
    defer positioned.deinit();
    return positioned.metrics;
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

pub fn layoutAttributedRunsUtf8(allocator: std.mem.Allocator, cascade: layout.FontCascade, attributed: AttributedText) !AttributedRunLayout {
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var buffer = layout.LayoutBuffer.init(allocator);
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
        const options = layout.ParagraphOptions{
            .max_width = std.math.inf(f32),
            .line_height = run.style.line_height,
            .letter_spacing = run.style.letter_spacing,
            .word_spacing = run.style.word_spacing,
        };
        const metrics = try layout.TextShaper.measureParagraphUtf8(cascade, &buffer, run_text, run.style.font_size, options);
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

pub fn layoutAttributedGlyphRunsUtf8(allocator: std.mem.Allocator, cascade: layout.FontCascade, attributed: AttributedText) !AttributedGlyphRunLayout {
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var buffer = layout.LayoutBuffer.init(allocator);
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
        const options = layout.ParagraphOptions{
            .max_width = std.math.inf(f32),
            .line_height = run.style.line_height,
            .letter_spacing = run.style.letter_spacing,
            .word_spacing = run.style.word_spacing,
        };
        const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &buffer, run_text, run.style.font_size, options);
        const metrics = textMetricsFromParagraph(paragraph);
        const glyphs = try allocator.dupe(layout.GlyphPosition, paragraph.glyphs);
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

fn textMetricsFromParagraph(paragraph: layout.ParagraphLayout) TextMetrics {
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

fn isValidLocaleSubtag(tag_value: []const u8) bool {
    if (tag_value.len == 0) return false;
    for (tag_value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        return false;
    }
    return true;
}

fn isValidLanguageSubtag(tag_value: []const u8) bool {
    if (tag_value.len < 2 or tag_value.len > 8) return false;
    for (tag_value) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    return true;
}

fn isScriptSubtag(tag_value: []const u8) bool {
    if (tag_value.len != 4) return false;
    for (tag_value) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    return true;
}

fn isRegionSubtag(tag_value: []const u8) bool {
    if (tag_value.len == 2) {
        for (tag_value) |byte| {
            if (!std.ascii.isAlphabetic(byte)) return false;
        }
        return true;
    }
    if (tag_value.len == 3) {
        for (tag_value) |byte| {
            if (!std.ascii.isDigit(byte)) return false;
        }
        return true;
    }
    return false;
}

fn appendLower(allocator: std.mem.Allocator, output: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| {
        try output.append(allocator, std.ascii.toLower(byte));
    }
}

fn appendUpper(allocator: std.mem.Allocator, output: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| {
        try output.append(allocator, std.ascii.toUpper(byte));
    }
}

fn appendTitle(allocator: std.mem.Allocator, output: *std.ArrayList(u8), text: []const u8) !void {
    if (text.len == 0) return;
    try output.append(allocator, std.ascii.toUpper(text[0]));
    for (text[1..]) |byte| {
        try output.append(allocator, std.ascii.toLower(byte));
    }
}

fn canonicalLanguageAlias(language: []const u8) []const u8 {
    if (asciiEqlIgnoreCase(language, "iw")) return "he";
    if (asciiEqlIgnoreCase(language, "in")) return "id";
    if (asciiEqlIgnoreCase(language, "ji")) return "yi";
    return language;
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (std.ascii.toLower(lhs) != std.ascii.toLower(rhs)) return false;
    }
    return true;
}

test "core ranges and attributed text validate byte units" {
    const text = "A一B";
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 12 } },
        .{ .byte_range = .{ .start = 1, .len = 3 }, .style = .{ .font_size = 16, .script = .han } },
        .{ .byte_range = .{ .start = 4, .len = 1 }, .style = .{ .font_size = 12 } },
    };
    const attributed = AttributedText{ .text = text, .spans = &spans };

    try attributed.validate();
    try std.testing.expectEqual(@as(usize, 4), spans[1].byte_range.end());
    try std.testing.expectEqual(@as(f32, 16), attributed.styleAtByte(2).?.font_size);
    try std.testing.expect(attributed.styleAtByte(text.len) == null);

    const bad = AttributedText{
        .text = text,
        .spans = &.{.{ .byte_range = .{ .start = 2, .len = 1 }, .style = .{} }},
    };
    try std.testing.expectError(error.InvalidUtf8Boundary, bad.validate());
}

test "attributed text splits style runs by byte range boundaries" {
    const allocator = std.testing.allocator;
    const text = "abcde";
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{ .font_size = 12 } },
        .{ .byte_range = .{ .start = 2, .len = 2 }, .style = .{ .font_size = 16 } },
        .{ .byte_range = .{ .start = 3, .len = 2 }, .style = .{ .font_size = 20 } },
    };
    const attributed = AttributedText{ .text = text, .spans = &spans };
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 4), runs.len);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_range.start);
    try std.testing.expectEqual(@as(usize, 2), runs[0].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 12), runs[0].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 2), runs[1].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[1].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), runs[1].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 3), runs[2].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[2].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), runs[2].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 4), runs[3].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[3].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), runs[3].style.font_size, 0.001);

    const default_runs = try (AttributedText{ .text = "ab", .spans = &.{} }).runs(allocator);
    defer allocator.free(default_runs);
    try std.testing.expectEqual(@as(usize, 1), default_runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), default_runs[0].style.font_size, 0.001);
}

test "core identifiers locale and glyph cluster helpers" {
    const font_id = FontId{ .index = 3 };
    try std.testing.expect(font_id.isValid());
    try std.testing.expect(!FontId.invalid.isValid());

    const language = Language{ .tag = "zh" };
    try std.testing.expect(language.isValid());
    const bad_language = Language{ .tag = "bad tag" };
    try std.testing.expect(!bad_language.isValid());

    const locale = Locale{ .tag = "zh-Hans-CN" };
    try std.testing.expect(locale.isValid());
    try std.testing.expectEqualStrings("zh", locale.language().tag);
    const parts = try locale.parse();
    try std.testing.expectEqualStrings("zh", parts.language);
    try std.testing.expectEqualStrings("Hans", parts.script.?);
    try std.testing.expectEqualStrings("CN", parts.region.?);

    const variant_locale = Locale{ .tag = "sl-rozaj-biske" };
    const variant_parts = try variant_locale.parse();
    try std.testing.expectEqualStrings("sl", variant_parts.language);
    try std.testing.expect(variant_parts.script == null);
    try std.testing.expect(variant_parts.region == null);
    try std.testing.expectEqual(@as(usize, 2), variant_parts.variantSlice().len);
    try std.testing.expectEqualStrings("rozaj", variant_parts.variantSlice()[0]);
    const bad_locale = Locale{ .tag = "bad tag" };
    try std.testing.expect(!bad_locale.isValid());

    const mixed = Locale{ .tag = "ZH_hANS_cn_ROZAJ" };
    const canonical = try mixed.canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(canonical);
    try std.testing.expectEqualStrings("zh-Hans-CN-rozaj", canonical);

    const hebrew_alias = try (Locale{ .tag = "IW-il" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(hebrew_alias);
    try std.testing.expectEqualStrings("he-IL", hebrew_alias);
    const indonesian_alias = try (Locale{ .tag = "in-ID" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(indonesian_alias);
    try std.testing.expectEqualStrings("id-ID", indonesian_alias);
    const yiddish_alias = try (Locale{ .tag = "ji" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(yiddish_alias);
    try std.testing.expectEqualStrings("yi", yiddish_alias);

    const cluster = GlyphCluster{
        .text_range = .{ .start = 1, .len = 3 },
        .glyph_range = .{ .start = 4, .len = 2 },
    };
    try std.testing.expect(cluster.containsByte(2));
    try std.testing.expect(!cluster.containsByte(4));
    try std.testing.expectEqual(@as(usize, 6), cluster.glyph_range.end());
}

test "paragraph style converts to paragraph options" {
    const style = ParagraphStyle{
        .direction = .rtl,
        .text_align = .center,
        .line_height = 24,
        .max_lines = 2,
        .overflow_mode = .ellipsis,
        .tab_width = 2,
        .first_line_indent = 10,
        .paragraph_spacing = 4,
    };
    const options = style.paragraphOptions(80);

    try std.testing.expectEqual(layout.TextDirection.rtl, options.direction);
    try std.testing.expectEqual(layout.TextAlign.center, options.alignment);
    try std.testing.expectApproxEqAbs(@as(f32, 24), options.line_height.?, 0.001);
    try std.testing.expectEqual(@as(usize, 2), options.max_lines.?);
    try std.testing.expect(options.ellipsis);
    try std.testing.expectEqual(@as(usize, 2), options.tab_width);
    try std.testing.expectApproxEqAbs(@as(f32, 10), options.first_line_indent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), options.paragraph_spacing, 0.001);
}

test "measures attributed text with primary style" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try @import("font.zig").Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const @import("font.zig").Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{ .font_size = 20, .letter_spacing = 2, .line_height = 24 } },
    };
    const attributed = AttributedText{
        .text = "AA",
        .spans = &spans,
        .paragraph_style = .{ .text_align = .left },
    };
    const metrics = try measureAttributedTextUtf8(cascade, &layout_buffer, attributed, 100);

    try std.testing.expectApproxEqAbs(@as(f32, 34.0), metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), metrics.baseline, 0.001);
}

test "measures attributed runs with per span style" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try @import("font.zig").Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const @import("font.zig").Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    const metrics = try measureAttributedRunsUtf8(allocator, cascade, attributed);

    try std.testing.expectApproxEqAbs(@as(f32, 48.0), metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), metrics.baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), metrics.ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), metrics.descent, 0.001);
}

test "layouts attributed runs with x offsets and metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try @import("font.zig").Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const @import("font.zig").Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    var positioned = try layoutAttributedRunsUtf8(allocator, cascade, attributed);
    defer positioned.deinit();

    try std.testing.expectEqual(@as(usize, 2), positioned.runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), positioned.runs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), positioned.runs[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), positioned.runs[0].metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), positioned.runs[1].metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), positioned.metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), positioned.metrics.height, 0.001);
}

test "layouts attributed glyph runs for rendering" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try @import("font.zig").Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const @import("font.zig").Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    var glyph_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, attributed);
    defer glyph_runs.deinit();

    try std.testing.expectEqual(@as(usize, 2), glyph_runs.runs.len);
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs[0].glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs[1].glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), glyph_runs.runs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), glyph_runs.runs[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), glyph_runs.runs[0].glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), glyph_runs.runs[1].glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), glyph_runs.metrics.width, 0.001);
}
