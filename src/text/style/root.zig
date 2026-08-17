//! Portable text ranges, locale identifiers, and presentation styles.

const std = @import("std");
const paragraph_options = @import("../../layout/paragraph/options.zig");
const paragraph_reflow = @import("../../layout/line_break/reflow/root.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const raster = @import("../../raster.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const segmentation = @import("../segmentation/root.zig");
const unicode = @import("../../unicode.zig");

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
    /// Normalized variation-space coordinates in fvar axis order after avar
    /// mapping. Higher-level attributed text forwards this to layout shaping so
    /// HVAR/VVAR advances and bearings participate in measurement and wrapping.
    normalized_variation_coords: []const f32 = &.{},
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

pub const WrapMode = paragraph_types.WrapMode;

pub const OverflowMode = enum {
    clip,
    visible,
    ellipsis,
};

pub const ParagraphStyle = struct {
    direction: pipeline_types.TextDirection = .ltr,
    text_align: paragraph_types.TextAlign = .start,
    vertical_align: VerticalAlign = .baseline,
    line_height: ?f32 = null,
    max_lines: ?usize = null,
    ellipsis: bool = false,
    wrap_mode: WrapMode = .word,
    overflow_mode: OverflowMode = .clip,
    tab_width: usize = 4,
    first_line_indent: f32 = 0,
    paragraph_spacing: f32 = 0,
    /// Optional segmentation for Thai, Lao, Khmer, or Myanmar text.
    ///
    /// The dictionary is borrowed and must outlive layout or any retained
    /// paragraph created from these options.
    word_break_dictionary: ?*const segmentation.WordBreakDictionary = null,
    /// Optional automatic-hyphenation data and line-level policy.
    hyphenation: paragraph_options.Hyphenation = .{},

    pub fn paragraphOptions(self: ParagraphStyle, max_width: f32) paragraph_options.Options {
        return .{
            .max_width = max_width,
            .wrap_mode = self.wrap_mode,
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
            .word_break_dictionary = self.word_break_dictionary,
            .hyphenation = self.hyphenation,
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

pub const TextMetrics = paragraph_types.TextMetrics;
pub const CoreBaselineMetrics = paragraph_reflow.BaselineMetrics;

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

test {
    _ = @import("tests.zig");
}
