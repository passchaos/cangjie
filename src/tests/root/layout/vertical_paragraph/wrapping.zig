//! Vertical UAX #14 and grapheme-safe emergency wrapping.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

fn layout(
    font: *const Font,
    buffer: *LayoutBuffer,
    text: []const u8,
    max_inline_size: f32,
    writing_mode: support.WritingMode,
) !support.ParagraphLayout {
    return TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{font}),
        buffer,
        text,
        20,
        .{
            .max_width = max_inline_size,
            .writing_mode = writing_mode,
            .text_orientation = .upright,
        },
    );
}

test "vertical word wrapping selects UAX 14 spaces" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "A A", 100, .vertical_lr);
    const one = natural.glyphs[0].y_advance;
    const space = natural.glyphs[1].y_advance;
    const wrapped = try layout(
        &font,
        &buffer,
        "A A",
        one + space + 0.1,
        .vertical_lr,
    );
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), wrapped.lines[0].glyph_start);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[1].byte_start);
    try std.testing.expectApproxEqAbs(one, wrapped.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(one, wrapped.lines[1].height, 0.001);

    var geometry = try paragraph.buildGeometry(
        allocator,
        "A A",
        wrapped,
        .{},
    );
    defer geometry.deinit();
    const upstream = geometry.caret(.{
        .byte_offset = 2,
        .affinity = .upstream,
    }).?;
    const downstream = geometry.caret(.{
        .byte_offset = 2,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 0), upstream.line_index);
    try std.testing.expectEqual(@as(usize, 1), downstream.line_index);
}

test "vertical CJK wraps at character opportunities before emergency fallback" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "你好你", 100, .vertical_rl);
    const one = natural.glyphs[0].y_advance;
    const wrapped = try layout(
        &font,
        &buffer,
        "你好你",
        one * 2 + 0.1,
        .vertical_rl,
    );
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[1].glyph_len);
    try std.testing.expect(wrapped.lines[0].x > wrapped.lines[1].x);

    const no_wrap = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "你好你",
        20,
        .{
            .max_width = one,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), no_wrap.lines.len);
    try std.testing.expect(no_wrap.lines[0].height > one);
}

test "vertical emergency wrapping uses safe grapheme boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "AAAA", 100, .vertical_lr);
    const one = natural.glyphs[0].y_advance;
    const wrapped = try layout(
        &font,
        &buffer,
        "AAAA",
        one * 2 + 0.1,
        .vertical_lr,
    );
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[1].glyph_len);

    const combining = try layout(
        &font,
        &buffer,
        "A\u{0301}A",
        one + 0.1,
        .vertical_lr,
    );
    try std.testing.expectEqual(@as(usize, 2), combining.lines.len);
    // The base and combining mark share one grapheme and must stay together
    // even when their combined shaped extent exceeds the requested measure.
    try std.testing.expect(combining.lines[0].glyph_len >= 2);
    try std.testing.expectEqual(@as(usize, 3), combining.lines[0].byte_len);
}

test "retained vertical paragraphs reflow between wrapped and unwrapped columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "A A A",
        20,
        .{
            .max_width = 100,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const one = shaped.glyphs[0].y_advance;
    const intrinsic = try shaped.contentWidths(.{
        .max_width = 100,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(one, intrinsic.min, 0.001);
    try std.testing.expect(intrinsic.max > intrinsic.min);

    const wrapped = try shaped.layout(&reflow, .{
        .max_width = one + 0.1,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), wrapped.lines.len);
    const natural = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), natural.lines.len);
    try std.testing.expectApproxEqAbs(
        one,
        shaped.glyphs[0].y_advance,
        0.001,
    );
}

test "vertical soft wrapping composes with explicit hard breaks" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "AA\nAA", 100, .vertical_lr);
    const one = natural.glyphs[0].y_advance;
    const wrapped = try layout(
        &font,
        &buffer,
        "AA\nAA",
        one + 0.1,
        .vertical_lr,
    );
    try std.testing.expectEqual(@as(usize, 4), wrapped.lines.len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[2].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), wrapped.lines[3].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), wrapped.lines[1].byteEnd());
    try std.testing.expectEqual(@as(usize, 3), wrapped.lines[2].byte_start);
}
