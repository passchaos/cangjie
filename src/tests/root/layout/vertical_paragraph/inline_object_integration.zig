//! Retained, styled, and boundary integration for vertical inline objects.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const marker = paragraph.object_replacement_utf8;

test "retained vertical object geometry updates without changing anchors" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const text = "A" ++ marker ++ "A";
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 200,
            .inline_objects = &.{.{
                .id = 1,
                .byte_index = 1,
                .width = 10,
                .height = 10,
            }},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine_y = shaped.glyphs[1].y_advance;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const result = try shaped.layout(&reflow, .{
        .max_width = 200,
        .inline_objects = &.{.{
            .id = 9,
            .byte_index = 1,
            .width = 50,
            .height = 40,
            .baseline = 20,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(u64, 9), result.inline_objects[0].id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        result.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 50),
        result.lines[0].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        pristine_y,
        shaped.glyphs[1].y_advance,
        0.001,
    );

    const widths = try shaped.contentWidths(.{
        .max_width = 200,
        .inline_objects = &.{.{
            .id = 9,
            .byte_index = 1,
            .width = 50,
            .height = 40,
        }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 80), widths.max, 0.001);
}

test "styled vertical objects preserve metadata geometry and render output" {
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
    const text = "A" ++ marker ++ "A";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 17,
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
            .max_width = 200,
            .inline_objects = &.{.{
                .id = 3,
                .byte_index = 1,
                .width = 30,
                .height = 40,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
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

    var draw_list = try support.buildGlyphDrawList(
        allocator,
        result,
        .{ .origin_x = 3, .origin_y = 5 },
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 1), draw_list.inline_objects.len);
    try std.testing.expectApproxEqAbs(
        result.inline_objects[0].x + 3,
        draw_list.inline_objects[0].x,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
}

test "vertical layout rejects every out-of-flow object kind" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    for ([_]paragraph.InlineObjectKind{
        .out_of_flow,
        .custom_out_of_flow,
    }) |kind| {
        try std.testing.expectError(
            error.UnsupportedVerticalParagraphOptions,
            TextShaper.layoutParagraphUtf8(
                FontCascade.init(&.{&font}),
                &buffer,
                marker,
                20,
                .{
                    .max_width = 100,
                    .inline_objects = &.{.{
                        .id = 1,
                        .kind = kind,
                        .byte_index = 0,
                        .width = 10,
                        .height = 10,
                    }},
                    .writing_mode = .vertical_rl,
                    .text_orientation = .upright,
                },
            ),
        );
    }
}
