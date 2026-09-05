//! Split one homogeneous shaping item into contiguous fallback-font segments.
//!
//! The segmentation policy lives here; actual shaping remains supplied by a
//! generic context's `appendSegment` method. Zig resolves that method at
//! comptime, so this boundary adds no runtime callback or type erasure.

const std = @import("std");

const cache = @import("../context/cache/root.zig");
const font_fallback = @import("font/root.zig");
const Font = @import("../../font.zig").Font;
const unicode = @import("../../unicode.zig");

pub const Pen = struct {
    x: f32 = 0,
    y: f32 = 0,
};

/// Force a generated temporary source range to remain in a specific face.
///
/// Ordinary caller text should not use this. Paragraph Kashida reshaping uses
/// it so inserted U+0640 scalars inherit the font that nominated the safe
/// boundary instead of being captured by an earlier fallback face that merely
/// happens to contain a Tatweel glyph.
pub const FontOverride = struct {
    byte_start: usize,
    byte_len: usize,
    font: *const Font,

    pub fn byteEnd(self: FontOverride) usize {
        return self.byte_start + self.byte_len;
    }
};

pub const Input = struct {
    cascade: font_fallback.Cascade,
    fallback_cache: ?*cache.FontFallbackCache = null,
    glyph_index_cache: ?*cache.GlyphIndexCache = null,
    text: []const u8,
    cluster_base: usize = 0,
    pen: Pen = .{},
    font_overrides: []const FontOverride = &.{},
};

/// Invoke `context.appendSegment(cascade, font_index, text, cluster_base, pen)`
/// once for each maximal contiguous span assigned to one fallback face.
pub fn shape(context: anytype, input: Input) !Pen {
    if (input.cascade.fonts.len == 0) return error.EmptyFontCascade;
    try input.cascade.validateLocations();

    var segment_start: usize = 0;
    var segment_font_index: ?usize = null;
    var next_pen = input.pen;

    if (input.text.len == 0) return next_pen;
    if (input.cascade.fonts.len == 1 and input.font_overrides.len == 0) {
        // A one-face cascade cannot make a fallback decision. Shape the whole
        // valid UTF-8 item directly instead of segmenting every grapheme only
        // to rediscover font index zero; this is especially material for
        // Arabic and CJK paragraph builders that use one explicit face.
        return context.appendSegment(
            input.cascade,
            0,
            input.text,
            input.cluster_base,
            next_pen,
        );
    }

    if (isAscii(input.text)) {
        // Every ASCII byte is one grapheme. Avoid Unicode iteration on the
        // dominant Latin/UI path while preserving CR/LF face selection.
        for (input.text, 0..) |codepoint, cluster_start| {
            const font_index = try selectScalar(
                input,
                codepoint,
                input.cluster_base + cluster_start,
            );
            if (segment_font_index == null) {
                segment_start = cluster_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try context.appendSegment(
                    input.cascade,
                    segment_font_index.?,
                    input.text[segment_start..cluster_start],
                    input.cluster_base + segment_start,
                    next_pen,
                );
                segment_start = cluster_start;
                segment_font_index = font_index;
            }
        }
    } else {
        var clusters = unicode.graphemeClustersAssumeValid(input.text);
        while (clusters.next()) |cluster| {
            const cluster_end = cluster.byte_start + cluster.byte_len;
            const font_index = try selectCluster(
                input,
                input.text[cluster.byte_start..cluster_end],
                input.cluster_base + cluster.byte_start,
            );
            if (segment_font_index == null) {
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try context.appendSegment(
                    input.cascade,
                    segment_font_index.?,
                    input.text[segment_start..cluster.byte_start],
                    input.cluster_base + segment_start,
                    next_pen,
                );
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            }
        }
    }

    if (segment_font_index) |font_index| {
        next_pen = try context.appendSegment(
            input.cascade,
            font_index,
            input.text[segment_start..],
            input.cluster_base + segment_start,
            next_pen,
        );
    }
    return next_pen;
}

test "single-face cascades bypass fallback segmentation unless overridden" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{ 0x0628, 0x0640 },
    );
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});

    const Context = struct {
        calls: usize = 0,
        text_len: usize = 0,

        pub fn appendSegment(
            self: *@This(),
            _: font_fallback.Cascade,
            font_index: usize,
            text: []const u8,
            _: usize,
            pen: Pen,
        ) !Pen {
            try std.testing.expectEqual(@as(usize, 0), font_index);
            self.calls += 1;
            self.text_len += text.len;
            return pen;
        }
    };

    var direct = Context{};
    _ = try shape(&direct, .{ .cascade = cascade, .text = "بـب" });
    try std.testing.expectEqual(@as(usize, 1), direct.calls);
    try std.testing.expectEqual("بـب".len, direct.text_len);

    var overridden = Context{};
    _ = try shape(&overridden, .{
        .cascade = cascade,
        .text = "بـب",
        .font_overrides = &.{.{
            .byte_start = 2,
            .byte_len = 2,
            .font = &font,
        }},
    });
    try std.testing.expectEqual(@as(usize, 1), overridden.calls);
    try std.testing.expectEqual("بـب".len, overridden.text_len);
}

pub fn isAscii(text: []const u8) bool {
    for (text) |byte| {
        if (byte >= 0x80) return false;
    }
    return true;
}

fn selectScalar(
    input: Input,
    codepoint: u21,
    byte_start: usize,
) !usize {
    if (overrideFontIndex(input, byte_start)) |font_index| {
        return font_index;
    }
    if (input.fallback_cache) |fallback_cache| {
        if (input.glyph_index_cache) |glyph_cache| {
            return try fallback_cache.selectFontWithGlyphCache(
                input.cascade,
                glyph_cache,
                codepoint,
            );
        }
        return try fallback_cache.selectFont(input.cascade, codepoint);
    }
    return try font_fallback.selectFontFrom(
        input.cascade.fonts,
        input.glyph_index_cache,
        codepoint,
    );
}

fn selectCluster(
    input: Input,
    cluster: []const u8,
    byte_start: usize,
) !usize {
    if (overrideFontIndex(input, byte_start)) |font_index| {
        return font_index;
    }
    if (input.cascade.fonts.len == 1) return 0;
    if (cluster.len == 1 and cluster[0] < 0x80) {
        return try selectScalar(input, cluster[0], byte_start);
    }
    if (input.fallback_cache) |fallback_cache| {
        return try fallback_cache.selectFontForCluster(
            input.cascade,
            input.glyph_index_cache,
            cluster,
        );
    }
    return try font_fallback.selectFontForClusterFrom(
        input.cascade.fonts,
        input.glyph_index_cache,
        cluster,
    );
}

fn overrideFontIndex(input: Input, byte_start: usize) ?usize {
    for (input.font_overrides) |override| {
        if (byte_start < override.byte_start or
            byte_start >= override.byteEnd())
        {
            continue;
        }
        for (input.cascade.fonts, 0..) |font, font_index| {
            if (font == override.font) return font_index;
        }
    }
    return null;
}

test "generated source ranges can inherit a nominated fallback font" {
    const test_font = @import("../../test_font.zig");
    const first_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{ 0x0628, 0x0640 },
    );
    defer std.testing.allocator.free(first_bytes);
    const second_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{ 0x0628, 0x0640 },
    );
    defer std.testing.allocator.free(second_bytes);
    var first = try Font.parse(std.testing.allocator, first_bytes);
    defer first.deinit();
    var second = try Font.parse(std.testing.allocator, second_bytes);
    defer second.deinit();
    const cascade = font_fallback.Cascade.init(&.{ &first, &second });
    const input = Input{
        .cascade = cascade,
        .text = "بـب",
        .font_overrides = &.{.{
            .byte_start = 2,
            .byte_len = 2,
            .font = &second,
        }},
    };

    try std.testing.expectEqual(
        @as(?usize, 1),
        overrideFontIndex(input, 2),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        try selectCluster(input, "\xd9\x80", 2),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try selectCluster(input, "\xd8\xa8", 0),
    );
}
