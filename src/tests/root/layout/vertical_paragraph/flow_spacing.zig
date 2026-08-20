//! Flow-axis indentation and paragraph spacing for vertical columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical first-line indent narrows and offsets only the first soft column" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAA", .{
        .max_width = 45,
        .first_line_indent = 10,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        result.lines[0].indent,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.lines[1].indent,
        0.001,
    );

    var geometry = try paragraph.buildGeometry(
        allocator,
        "AAA",
        result,
        .{},
    );
    defer geometry.deinit();
    const start = geometry.caret(.{
        .byte_offset = 0,
        .affinity = .downstream,
    }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 10), start.rect.y, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        draw_list.glyphs[0].baseline_y,
        0.001,
    );
}

test "vertical hard segments reset indent and receive block spacing" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\nA";

    const rl = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), rl.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), rl.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), rl.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26), rl.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rl.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 46), rl.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), rl.height, 0.001);

    const lr = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), lr.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26), lr.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 46), lr.width, 0.001);

    const trailing = try layout(&font, &buffer, "A\n", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), trailing.lines.len);
    try std.testing.expectEqual(@as(usize, 0), trailing.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 26),
        trailing.lines[1].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        trailing.lines[1].y,
        0.001,
    );
}

test "vertical paragraph spacing does not separate soft columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAA", .{
        .max_width = 20.1,
        .paragraph_spacing = 7,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    try std.testing.expectApproxEqAbs(
        result.lines[0].width,
        result.lines[0].x - result.lines[1].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.lines[1].width,
        result.lines[1].x - result.lines[2].x,
        0.001,
    );
}

test "vertical flow spacing preserves signed public option semantics" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "A\nA", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = -10,
        .paragraph_spacing = -5,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[1].y, 0.001);
    // Negative block spacing overlaps adjacent hard-break columns.
    try std.testing.expectApproxEqAbs(@as(f32, 15), result.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 35), result.width, 0.001);
}

test "vertical indent resets after hard breaks that also soft-wrap" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AA\nAA", .{
        .max_width = 30,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 4), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[2].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[3].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 6),
        result.lines[2].x -
            (result.lines[1].x + result.lines[1].width),
        0.001,
    );
}

test "retained vertical flow spacing leaves intrinsic widths unchanged" {
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
        "A\nA",
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

    const baseline_widths = try shaped.contentWidths(.{
        .max_width = 100,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const spaced_widths = try shaped.contentWidths(.{
        .max_width = 100,
        .first_line_indent = 10,
        .paragraph_spacing = 99,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(baseline_widths, spaced_widths);

    const spaced = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 10), spaced.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26), spaced.lines[1].x, 0.001);

    const plain = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), plain.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), plain.lines[0].x, 0.001);
}

test "styled vertical flow spacing preserves metadata" {
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
    const text = "A\nA";
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 2,
            .byte_len = 1,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .first_line_indent = 10,
            .paragraph_spacing = 6,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26), result.lines[0].x, 0.001);
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
}
