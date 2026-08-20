//! Retained, styled, geometry, and renderer integration for vertical justification.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

const text = "一丁丂";

test "retained vertical justification restores pristine advances" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
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
    const pristine_advance = shaped.glyphs[0].y_advance;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const justified = try shaped.layout(&reflow, .{
        .max_width = 50,
        .alignment = .justify,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), justified.lines[0].height, 0.001);
    try std.testing.expect(justified.glyphs[0].y_advance > pristine_advance);

    const natural = try shaped.layout(&reflow, .{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(pristine_advance, natural.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(pristine_advance, shaped.glyphs[0].y_advance, 0.001);
}

test "styled vertical justification keeps metadata geometry and draw output parallel" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{ .byte_start = 0, .byte_len = "一".len, .style_index = 1, .font_size = 20 },
        .{ .byte_start = "一".len, .byte_len = text.len - "一".len, .style_index = 2, .font_size = 20 },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 50,
            .alignment = .justify,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    try std.testing.expectEqual(@as(u32, 1), styled.glyphMetadata()[0].style_index);
    try std.testing.expectEqual(@as(u32, 2), styled.glyphMetadata()[1].style_index);
    try std.testing.expectApproxEqAbs(@as(f32, 50), result.lines[0].height, 0.001);

    var geometry = try paragraph.buildStyledGeometry(allocator, text, result, &spans, .{});
    defer geometry.deinit();
    const fragments = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = "一丁".len },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 1), fragments.len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), fragments[0].rect.height, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        result.lines[0].y + result.glyphs[0].y_advance,
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
}
