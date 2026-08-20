//! Retained, styled, geometry, and renderer integration for vertical exclusions.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "retained vertical exclusions change geometry without reshaping" {
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
        "AAAA",
        20,
        .{ .max_width = 100, .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    defer shaped.deinit();
    const pristine = shaped.glyphs[0];
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const excluded = try shaped.layout(&reflow, .{
        .max_width = 100,
        .exclusions = &.{.{ .x = 0, .y = 0, .width = 20, .height = 30 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), excluded.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30), excluded.lines[0].y, 0.001);

    const plain = try shaped.layout(&reflow, .{
        .max_width = 100,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), plain.lines.len);
    try std.testing.expectEqual(pristine, shaped.glyphs[0]);
}

test "styled vertical exclusion reaches geometry and renderer" {
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
    const text = "AAAA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 9,
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
            .max_width = 100,
            .exclusions = &.{.{ .x = 0, .y = 0, .width = 20, .height = 30 }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    var geometry = try paragraph.buildStyledGeometry(allocator, text, result, &spans, .{});
    defer geometry.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 30), geometry.lines[0].bounds.y, 0.001);
    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 30), draw_list.glyphs[0].baseline_y, 0.001);
}

test "retained vertical-rl exclusions preserve reverse block progression" {
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
        "AAAA",
        20,
        .{ .max_width = 100, .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const result = try shaped.layout(&reflow, .{
        .max_width = 100,
        .exclusions = &.{.{ .x = -20, .y = 0, .width = 20, .height = 30 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expect(result.lines[0].x > result.lines[1].x);
    try std.testing.expectApproxEqAbs(@as(f32, 30), result.lines[0].y, 0.001);

    var geometry = try paragraph.buildGeometry(allocator, "AAAA", result, .{});
    defer geometry.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 30), geometry.lines[0].bounds.y, 0.001);
    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, 30), draw_list.glyphs[0].baseline_y, 0.001);
}
