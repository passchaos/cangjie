//! Retained and subsystem integration for vertical inline alignment.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical alignment composes with tabs and in-flow objects" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const tabbed = try layout(&font, &buffer, "A\tA", .{
        .max_width = 120,
        .wrap_mode = .no_wrap,
        .alignment = .center,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // Absolute tab rulers pin their column to logical inline start, matching
    // horizontal tab-ruler lines rather than translating the ruler itself.
    try std.testing.expectApproxEqAbs(@as(f32, 0), tabbed.lines[0].y, 0.001);
    try std.testing.expectEqual(
        @as(?paragraph.Align, .start),
        tabbed.lines[0].resolved_alignment,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        tabbed.glyphs[1].y_advance,
        0.001,
    );

    const text = "A" ++ paragraph.object_replacement_utf8;
    const object = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 120,
            .wrap_mode = .no_wrap,
            .alignment = .end,
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
    try std.testing.expectApproxEqAbs(@as(f32, 60), object.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 80),
        object.inline_objects[0].y,
        0.001,
    );
}

test "retained and styled vertical alignment preserve intrinsic content" {
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
        "A",
        20,
        .{
            .max_width = 100,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const start_widths = try shaped.contentWidths(.{
        .max_width = 100,
        .alignment = .start,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const end_widths = try shaped.contentWidths(.{
        .max_width = 100,
        .alignment = .end,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(start_widths, end_widths);

    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const centered = try shaped.layout(&reflow, .{
        .max_width = 100,
        .alignment = .center,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), centered.lines[0].y, 0.001);

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = 1,
        .style_index = 7,
        .font_size = 20,
    }};
    const styled_result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "A",
        20,
        &spans,
        .{
            .max_width = 100,
            .alignment = .end,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 80),
        styled_result.lines[0].y,
        0.001,
    );
    try std.testing.expectEqual(
        styled_result.glyphs.len,
        styled.glyphMetadata().len,
    );
}

test "vertical alignment is reflected by geometry and draw output" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const result = try layout(&font, &buffer, "A", .{
        .max_width = 100,
        .alignment = .center,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    var geometry = try paragraph.buildGeometry(allocator, "A", result, .{});
    defer geometry.deinit();
    const caret = geometry.caret(.{
        .byte_offset = 0,
        .affinity = .downstream,
    }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 40), caret.rect.y, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        draw_list.glyphs[0].baseline_y,
        0.001,
    );
}

test "vertical alignment rejects block-axis and justification requests" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    for ([_]paragraph.Align{ .left, .right, .justify }) |alignment| {
        try std.testing.expectError(
            error.UnsupportedVerticalParagraphOptions,
            layout(&font, &buffer, "A", .{
                .max_width = 100,
                .alignment = alignment,
                .writing_mode = .vertical_rl,
                .text_orientation = .upright,
            }),
        );
    }
}
