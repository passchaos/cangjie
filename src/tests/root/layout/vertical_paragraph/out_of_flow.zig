//! Source-anchor fallback for ordinary vertical out-of-flow objects.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const marker = paragraph.object_replacement_utf8;

test "vertical out-of-flow object anchors without layout occupancy" {
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
            .max_width = 100,
            .inline_objects = &.{.{
                .id = 7,
                .kind = .out_of_flow,
                .byte_index = 1,
                .width = 80,
                .height = 90,
                .baseline = 30,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.glyphs[1].y_advance,
        0.001,
    );
    // Only the two A glyphs occupy the column. Object paint bounds do not
    // enlarge paragraph metrics or the containing column.
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), result.height, 0.001);
    const positioned = result.inline_objects[0];
    try std.testing.expectEqual(
        paragraph.InlineObjectKind.out_of_flow,
        positioned.kind,
    );
    try std.testing.expectApproxEqAbs(@as(f32, -30), positioned.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), positioned.y, 0.001);
    try std.testing.expectApproxEqAbs(positioned.x, positioned.anchor_x, 0.001);
    try std.testing.expectApproxEqAbs(positioned.y, positioned.anchor_y, 0.001);

    const hit = result.hitTest(positioned.x + 1, positioned.y + 1);
    try std.testing.expect(hit.cluster != 1);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.selectionRectForBytes(1, 4).height,
        0.001,
    );

    const centered = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .alignment = .center,
            .inline_objects = &.{.{
                .id = 8,
                .kind = .out_of_flow,
                .byte_index = 1,
                .width = 10,
                .height = 10,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    // The zero-advance marker follows the final aligned y pen rather than its
    // pre-alignment source position.
    try std.testing.expectApproxEqAbs(
        centered.lines[0].y + 20,
        centered.inline_objects[0].anchor_y,
        0.001,
    );
}

test "vertical out-of-flow object-only paragraph has no font or inline extent" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        marker,
        20,
        .{
            .max_width = 100,
            .inline_objects = &.{.{
                .id = 5,
                .kind = .out_of_flow,
                .byte_index = 0,
                .width = 40,
                .height = 50,
            }},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), result.runs.len);
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.height, 0.001);
    try std.testing.expect(result.width < 40);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
}
