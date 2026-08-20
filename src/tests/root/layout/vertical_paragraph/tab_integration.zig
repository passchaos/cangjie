//! Retained, styled, and owned geometry integration for vertical tabs.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "retained vertical tabs change rulers without reshaping" {
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
        "A\tA",
        20,
        .{
            .max_width = 200,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine = shaped.glyphs[1].y_advance;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const first = try shaped.layout(&reflow, .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        first.glyphs[1].y_advance,
        0.001,
    );
    const second = try shaped.layout(&reflow, .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 90 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 70),
        second.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        pristine,
        shaped.glyphs[1].y_advance,
        0.001,
    );

    const widths = try shaped.contentWidths(.{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 80), widths.max, 0.001);
}

test "styled vertical tabs preserve metadata and geometry" {
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
    const text = "A\tA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 51,
        .font_size = 20,
        .word_spacing = 9,
    }};

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 200,
            .word_spacing = 11,
            .tab_stops = &.{.{ .position = 60 }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        result.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        geometry.graphemes[1].inline_size,
        0.001,
    );

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
}
