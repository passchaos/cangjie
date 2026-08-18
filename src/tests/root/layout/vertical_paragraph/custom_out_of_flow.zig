//! Concrete placement and resolver replay for vertical custom objects.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const marker = paragraph.object_replacement_utf8;

test "retained and styled vertical custom placement remains zero occupancy" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const text = "A" ++ marker ++ "A";
    const object = paragraph.InlineObject{
        .id = 8,
        .kind = .custom_out_of_flow,
        .byte_index = 1,
        .width = 10,
        .height = 10,
    };
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
            .inline_objects = &.{object},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const placement = paragraph.OutOfFlowPlacement{
        .byte_index = 1,
        .geometry = .{
            .x = 50,
            .y = 60,
            .width = 70,
            .height = 80,
        },
    };
    const retained = try shaped.layout(&reflow, .{
        .max_width = 100,
        .inline_objects = &.{object},
        .out_of_flow_placements = &.{placement},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 20), retained.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), retained.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), retained.inline_objects[0].x, 0.001);

    const widths = try shaped.contentWidths(.{
        .max_width = 100,
        .inline_objects = &.{object},
        .out_of_flow_placements = &.{placement},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), widths.max, 0.001);

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 6,
        .font_size = 20,
    }};
    const styled_result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .inline_objects = &.{object},
            .out_of_flow_placements = &.{placement},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(
        styled_result.glyphs.len,
        styled.glyphMetadata().len,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        styled_result.inline_objects[0].y,
        0.001,
    );

    var draw_list = try support.buildGlyphDrawList(
        allocator,
        styled_result,
        .{ .origin_x = 3, .origin_y = 4 },
    );
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 53),
        draw_list.inline_objects[0].x,
        0.001,
    );
}

test "vertical resolver supports placement-only replay" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const object = paragraph.InlineObject{
        .id = 12,
        .kind = .custom_out_of_flow,
        .byte_index = 1,
        .width = 10,
        .height = 10,
    };
    const text = "A" ++ marker ++ "A";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(.{
        .max_width = 100,
        .inline_objects = &.{object},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });

    const first_pass = try resolver.pass();
    const first = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        first_pass.options,
    );
    const request = switch (try resolver.next(first_pass, first)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try std.testing.expectApproxEqAbs(
        first.inline_objects[0].anchor_y,
        request.anchor_y,
        0.001,
    );
    try resolver.submit(request, .{
        .geometry = .{
            .x = request.anchor_x + 5,
            .y = request.anchor_y + 7,
            .width = 24,
            .height = 26,
        },
    });
    const final_pass = try resolver.pass();
    const final = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        final_pass.options,
    );
    try std.testing.expectEqual(
        paragraph.OutOfFlowStep.complete,
        try resolver.next(final_pass, final),
    );
    try std.testing.expectApproxEqAbs(
        request.anchor_x + 5,
        final.inline_objects[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        request.anchor_y + 7,
        final.inline_objects[0].y,
        0.001,
    );
}

test "vertical resolver exclusions remain outside the direct-placement slice" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const object = paragraph.InlineObject{
        .id = 13,
        .kind = .custom_out_of_flow,
        .byte_index = 0,
        .width = 10,
        .height = 10,
    };
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(.{
        .max_width = 100,
        .inline_objects = &.{object},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const first_pass = try resolver.pass();
    const first = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        marker,
        20,
        first_pass.options,
    );
    const request = switch (try resolver.next(first_pass, first)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try resolver.submit(request, .{
        .geometry = .{ .x = 1, .y = 2, .width = 10, .height = 10 },
        .exclusion = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
    });
    const replay = try resolver.pass();
    try std.testing.expectError(
        error.UnsupportedVerticalParagraphOptions,
        TextShaper.layoutParagraphUtf8(
            FontCascade.init(&.{&font}),
            &buffer,
            marker,
            20,
            replay.options,
        ),
    );
}

test "vertical max-lines hides custom objects and their placements" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AA" ++ marker;
    const object = paragraph.InlineObject{
        .id = 2,
        .kind = .custom_out_of_flow,
        .byte_index = 2,
        .width = 10,
        .height = 10,
    };
    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 20.1,
            .max_lines = 1,
            .inline_objects = &.{object},
            .out_of_flow_placements = &.{.{
                .byte_index = 2,
                .geometry = .{ .x = 40, .y = 50, .width = 10, .height = 10 },
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 0), result.inline_objects.len);

    var resolver = paragraph.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(.{
        .max_width = 20.1,
        .max_lines = 1,
        .inline_objects = &.{object},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const pass_value = try resolver.pass();
    const unresolved = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        pass_value.options,
    );
    try std.testing.expectEqual(
        paragraph.OutOfFlowStep.complete,
        try resolver.next(pass_value, unresolved),
    );
}
