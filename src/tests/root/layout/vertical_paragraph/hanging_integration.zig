//! Retained, styled, TextGeometry, and renderer integration for vertical hanging.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

const text = "一丁。丂";

test "retained vertical hanging restores occupied height without mutating snapshot" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 100,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine = try allocator.dupe(@TypeOf(shaped.glyphs[0]), shaped.glyphs);
    defer allocator.free(pristine);
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const natural_widths = try shaped.contentWidths(.{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const hanging_widths = try shaped.contentWidths(.{
        .max_width = 50,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    // Intrinsic sizing reports the same occupied inline measure used by
    // wrapping, while retained glyph advances remain immutable.
    try std.testing.expectApproxEqAbs(
        natural_widths.min - shaped.glyphs[2].y_advance / 2,
        hanging_widths.min,
        0.001,
    );
    // The no-break segment ends in an ideograph, so only the min-content
    // fragment ending at U+3002 receives optical hanging in this fixture.
    try std.testing.expectApproxEqAbs(
        natural_widths.max,
        hanging_widths.max,
        0.001,
    );

    const natural = try shaped.layout(&reflow, .{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), natural.lines[0].glyph_len);

    const hanging = try shaped.layout(&reflow, .{
        .max_width = 50,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), hanging.lines[0].glyph_len);
    try std.testing.expect(hanging.lines[0].hang_end > 0);

    const restored = try shaped.layout(&reflow, .{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), restored.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), restored.lines[0].hang_end, 0.001);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );
}

test "retained vertical compression restores advances and intrinsic sizes" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const compression_text = "一。、丁";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        compression_text,
        20,
        .{
            .max_width = 100,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const natural_advance = shaped.glyphs[1].y_advance;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const natural_widths = try shaped.contentWidths(.{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const compressed_widths = try shaped.contentWidths(.{
        .max_width = 50,
        .punctuation = .{
            .convention = .jis,
            .max_compression_fraction = 1,
        },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(compressed_widths.min < natural_widths.min);
    try std.testing.expect(compressed_widths.max < natural_widths.max);

    const compressed = try shaped.layout(&reflow, .{
        .max_width = 45,
        .punctuation = .{
            .convention = .jis,
            .max_compression_fraction = 1,
        },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), compressed.lines[0].glyph_len);
    try std.testing.expect(
        compressed.lines[0].glyphs(compressed)[1].y_advance < natural_advance,
    );

    const restored = try shaped.layout(&reflow, .{
        .max_width = 45,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), restored.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(
        natural_advance,
        shaped.glyphs[1].y_advance,
        0.001,
    );
}

test "styled vertical hanging keeps metadata geometry and draw output parallel" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 4,
        .font_size = 20,
    }};

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 50,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    try std.testing.expect(result.lines[0].hang_end > 0);

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();
    const fragments = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = "一丁。".len },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 1), fragments.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        fragments[0].rect.height,
        0.001,
    );

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(result.glyphs.len, draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        result.lines[0].y + 40,
        draw_list.glyphs[2].baseline_y,
        0.001,
    );
}

test "styled vertical compression keeps metadata geometry and draw output parallel" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const compression_text = "一。、丁";
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = "一。".len,
            .style_index = 3,
            .font_size = 20,
        },
        .{
            .byte_start = "一。".len,
            .byte_len = compression_text.len - "一。".len,
            .style_index = 6,
            .font_size = 20,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        compression_text,
        20,
        &spans,
        .{
            .max_width = 45,
            .punctuation = .{
                .convention = .jis,
                .max_compression_fraction = 1,
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), result.lines[0].glyph_len);
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    try std.testing.expectEqual(@as(u32, 3), styled.glyphMetadata()[1].style_index);
    try std.testing.expectEqual(@as(u32, 6), styled.glyphMetadata()[2].style_index);
    try std.testing.expectApproxEqAbs(@as(f32, 45), result.lines[0].height, 0.001);

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        compression_text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();
    const fragments = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = "一。、".len },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 1), fragments.len);
    try std.testing.expectApproxEqAbs(@as(f32, 45), fragments[0].rect.height, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(result.glyphs.len, draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        result.lines[0].y + result.glyphs[0].y_advance,
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
}

test "vertical ellipsis clears hanging when dots replace terminal punctuation" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{ '.', 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 50,
            .max_lines = 1,
            .ellipsis = true,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].hang_end, 0.001);
    const glyphs = result.lines[0].glyphs(result);
    try std.testing.expect(glyphs.len >= 3);
    for (glyphs[glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}

fn hangingFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{ 0x3001, 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
}
