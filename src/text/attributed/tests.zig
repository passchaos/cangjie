const std = @import("std");
const core = @import("../../core.zig");
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");
const layout = @import("../../layout.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

const OwnedFont = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    font: font_mod.Font,

    fn init(allocator: std.mem.Allocator, bytes: []u8) !OwnedFont {
        errdefer allocator.free(bytes);
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .font = try font_mod.Font.parse(allocator, bytes),
        };
    }

    fn deinit(self: *OwnedFont) void {
        self.font.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

test "unified attributed paragraph wraps sizes and preserves paint runs" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{
            .font_size = 20,
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
        .{ .byte_range = .{ .start = 2, .len = 3 }, .style = .{
            .font_size = 40,
            .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        .{ .text = "A A A", .spans = &spans },
        60,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expect(result.lines[1].height >= 40);
    try std.testing.expectEqual(@as(usize, 2), result.style_runs.len);
    try std.testing.expectEqual(@as(u8, 255), result.style_runs[0].style.color.r);
    try std.testing.expectEqual(@as(u8, 255), result.style_runs[1].style.color.b);
}

test "unified attributed paragraph applies feature spacing and measurement" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildScriptFeatureGsubTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const enable_sups = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("sups"), .enabled = true },
    };
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 1, .len = 2 }, .style = .{
            .font_size = 20,
            .font_features = &enable_sups,
            .letter_spacing = 3,
        } },
    };
    const attributed = core.AttributedText{ .text = "AAA", .spans = &spans };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        attributed,
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), result.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 2), result.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 23), result.glyphs[1].x_advance, 0.001);

    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const measured = try core.measureAttributedTextUtf8(
        layout.FontCascade.init(&fonts),
        &buffer,
        attributed,
        200,
    );
    try std.testing.expectApproxEqAbs(result.paragraph.width, measured.width, 0.001);
    try std.testing.expectApproxEqAbs(result.paragraph.height, measured.height, 0.001);
}

test "paint-only spans preserve ligatures and selection geometry" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalGsubTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{
            .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        .{ .text = "AA", .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.glyphs.len);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 2), result.glyphs[0].glyph_id);
    try std.testing.expect(result.paragraph.selectionRectForBytes(0, 2).width > 0);
}

test "styled bidi order carries paint fragments" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "A אב";
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{} },
        .{ .byte_range = .{ .start = 2, .len = text.len - 2 }, .style = .{
            .decoration = .{ .underline = true },
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        .{ .text = text, .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqualSlices(u21, &.{ 'A', 0x05d1, 0x05d0, ' ' }, &.{
        result.glyphs[0].codepoint,
        result.glyphs[1].codepoint,
        result.glyphs[2].codepoint,
        result.glyphs[3].codepoint,
    });
    var saw_underlined = false;
    for (result.style_runs) |run| {
        saw_underlined = saw_underlined or run.style.decoration.underline;
    }
    try std.testing.expect(saw_underlined);
}

test "styled cascade fallback keeps size and minimum line height" {
    const allocator = std.testing.allocator;
    var primary = try OwnedFont.init(
        allocator,
        try test_font.buildSingleCodepointTtf(allocator, 'A'),
    );
    defer primary.deinit();
    var fallback = try OwnedFont.init(
        allocator,
        try test_font.buildSingleCodepointTtfWithLineMetrics(
            allocator,
            'B',
            1100,
            -350,
            100,
        ),
    );
    defer fallback.deinit();
    const fonts = [_]*const font_mod.Font{ &primary.font, &fallback.font };
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{
            .font_size = 40,
            .line_height = 70,
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        .{ .text = "AB", .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.font_runs[1].font_index);
    try std.testing.expectApproxEqAbs(@as(f32, 40), result.font_runs[1].font_size, 0.001);
    try std.testing.expect(result.lines[0].height >= 70);
}

test "styled Arabic items retain joining context" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildCodepointSetTtf(
            allocator,
            &.{ 0x0627, 0x0628, 0xfe8e },
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 2, .len = 2 }, .style = .{
            .font_size = 24,
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        layout.FontCascade.init(&fonts),
        .{
            .text = "با",
            .spans = &spans,
            .paragraph_style = .{ .direction = .rtl },
        },
        200,
    );
    defer result.deinit();

    // ALEF is the second logical item but first visually. It must use the final
    // presentation-form glyph, proving the preceding style item was context.
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 3), result.glyphs[0].glyph_id);
}

test "styled ellipsis inherits terminal paint and buffer reuse clears metadata" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const cascade = layout.FontCascade.init(&fonts);
    const spans = [_]core.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{} },
        .{ .byte_range = .{ .start = 2, .len = 5 }, .style = .{
            .color = .{ .r = 0, .g = 180, .b = 0, .a = 255 },
        } },
    };
    var result = try core.layoutAttributedParagraphUtf8(
        allocator,
        cascade,
        .{
            .text = "A A A A",
            .spans = &spans,
            .paragraph_style = .{ .max_lines = 1, .ellipsis = true },
        },
        45,
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 180), result.style_runs[result.style_runs.len - 1].style.color.g);
    try std.testing.expectEqual(@as(u21, '.'), result.glyphs[result.glyphs.len - 1].codepoint);

    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = layout.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    _ = try layout.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        "AA",
        16,
        &.{.{ .byte_start = 0, .byte_len = 2, .style_index = 9, .font_size = 16 }},
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(@as(usize, 2), styled.glyphMetadata().len);
    _ = try layout.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AA",
        16,
        .{ .max_width = 100 },
    );
    // Ordinary layout owns no style state and therefore cannot mutate a
    // caller-owned sidecar. Starting another styled layout resets it.
    try std.testing.expectEqual(@as(usize, 2), styled.glyphMetadata().len);
    _ = try layout.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        "",
        16,
        &.{},
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(@as(usize, 0), styled.glyphMetadata().len);
}

test "styled paragraph rejects incomplete source partitions" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = layout.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    try std.testing.expectError(
        error.InvalidStyleSpans,
        layout.TextShaper.layoutStyledParagraphUtf8(
            layout.FontCascade.init(&fonts),
            &buffer,
            &styled,
            "AA",
            16,
            &.{.{ .byte_start = 1, .byte_len = 1, .style_index = 0, .font_size = 16 }},
            .{ .max_width = 100 },
        ),
    );
}
