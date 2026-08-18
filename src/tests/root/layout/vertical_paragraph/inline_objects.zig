//! In-flow inline objects in vertical paragraph columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const marker = paragraph.object_replacement_utf8;

test "vertical object height wraps inline and width expands its column" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A" ++ marker ++ "A";
    const object = paragraph.InlineObject{
        .id = 42,
        .byte_index = 1,
        .width = 50,
        .height = 30,
        .baseline = 10,
    };

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 40,
            .inline_objects = &.{object},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects[0].line_index);
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        result.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 50),
        result.lines[1].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        result.lines[1].height,
        0.001,
    );
    const positioned = result.inline_objects[0];
    try std.testing.expectApproxEqAbs(
        result.lines[1].x,
        positioned.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.lines[1].y,
        positioned.y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(positioned.x, positioned.anchor_x, 0.001);
    try std.testing.expectApproxEqAbs(positioned.y, positioned.anchor_y, 0.001);
    try std.testing.expectEqual(
        @as(usize, 1),
        result.lines[1].inlineObjects(result).len,
    );
}

test "vertical object caret selection and hit testing use object height" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A" ++ marker ++ "A";
    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .inline_objects = &.{.{
                .id = 7,
                .byte_index = 1,
                .width = 10,
                .height = 40,
            }},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    const positioned = result.inline_objects[0];
    try std.testing.expect(result.lines[0].width > positioned.width);
    try std.testing.expectApproxEqAbs(
        result.lines[0].x +
            (result.lines[0].width - positioned.width) / 2,
        positioned.x,
        0.001,
    );
    const leading = result.hitTest(
        positioned.x + positioned.width / 2,
        positioned.y + 1,
    );
    const trailing = result.hitTest(
        positioned.x + positioned.width / 2,
        positioned.y + positioned.height - 1,
    );
    try std.testing.expectEqual(@as(usize, 1), leading.cluster);
    try std.testing.expectEqual(@as(usize, 4), trailing.cluster);
    try std.testing.expect(trailing.trailing);
    const selection = result.selectionRectForBytes(1, 4);
    try std.testing.expectApproxEqAbs(
        positioned.height,
        selection.height,
        0.001,
    );

    var geometry = try paragraph.buildGeometry(allocator, text, result, .{});
    defer geometry.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        geometry.graphemes[1].inline_size,
        0.001,
    );
    const object_span = for (geometry.spans) |span| {
        if (span.byte_start == 1) break span;
    } else return error.MissingObjectGeometrySpan;
    try std.testing.expect(object_span.font_run == null);
}

test "vertical object-only paragraph wraps without font ownership" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = marker ++ marker ++ marker;

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 25,
            .inline_objects = &.{
                .{ .id = 1, .byte_index = 0, .width = 10, .height = 10 },
                .{ .id = 2, .byte_index = 3, .width = 30, .height = 10 },
                .{ .id = 3, .byte_index = 6, .width = 20, .height = 10 },
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), result.runs.len);
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 3), result.inline_objects.len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[0].inline_object_len);
    try std.testing.expectEqual(@as(usize, 1), result.lines[1].inline_object_len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        result.lines[0].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        result.lines[1].width,
        0.001,
    );
}
