//! Inline-axis start/center/end alignment for vertical columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical logical and physical alignments use the y axis" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    for ([_]struct {
        alignment: paragraph.Align,
        expected_y: f32,
    }{
        .{ .alignment = .start, .expected_y = 0 },
        .{ .alignment = .center, .expected_y = 40 },
        .{ .alignment = .end, .expected_y = 80 },
    }) |case| {
        const result = try layout(&font, &buffer, "A", .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .alignment = case.alignment,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        });
        try std.testing.expectApproxEqAbs(
            case.expected_y,
            result.lines[0].y,
            0.001,
        );
        try std.testing.expectEqual(
            @as(?paragraph.Align, case.alignment),
            result.lines[0].resolved_alignment,
        );
        try std.testing.expectApproxEqAbs(
            case.expected_y + 20,
            result.height,
            0.001,
        );
    }
}

test "vertical physical alignment translates a complete multi-column set" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const right = try layout(&font, &buffer, "AAA", .{
        .max_width = 40,
        .alignment = .right,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .max_block_size = 100,
    });
    try std.testing.expectEqual(@as(usize, 2), right.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 80), right.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), right.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), right.width, 0.001);

    const left = try layout(&font, &buffer, "AAA", .{
        .max_width = 40,
        .alignment = .left,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .max_block_size = 100,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), left.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), left.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), left.width, 0.001);

    const intrinsic = try layout(&font, &buffer, "A", .{
        .max_width = 40,
        .wrap_mode = .no_wrap,
        .alignment = .right,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), intrinsic.lines[0].x, 0.001);

    const overfull = try layout(&font, &buffer, "AAA", .{
        .max_width = 40,
        .alignment = .right,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .max_block_size = 30,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), overfull.lines[0].x, 0.001);
}

test "vertical physical alignment preserves explicit block geometry" {
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
        .wrap_mode = .no_wrap,
        .alignment = .right,
        .line_regions = &.{.{ .x = 17, .y = 5, .width = 40 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .max_block_size = 100,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 17), result.lines[0].x, 0.001);
}

test "vertical physical left and right align the column set" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    for ([_]struct {
        alignment: paragraph.Align,
        expected_x: f32,
    }{
        .{ .alignment = .left, .expected_x = 0 },
        .{ .alignment = .right, .expected_x = 80 },
    }) |case| {
        inline for ([_]support.TextDirection{ .ltr, .rtl }) |direction| {
            const result = try layout(&font, &buffer, "A", .{
                .max_width = 100,
                .wrap_mode = .no_wrap,
                .alignment = case.alignment,
                .direction = direction,
                .writing_mode = .vertical_lr,
                .text_orientation = .upright,
                .max_block_size = 100,
            });
            try std.testing.expectApproxEqAbs(
                case.expected_x,
                result.lines[0].x,
                0.001,
            );
            // Block-axis physical alignment never changes inline direction or
            // its top/bottom logical-start placement.
            try std.testing.expectApproxEqAbs(
                if (direction == .ltr) @as(f32, 0) else 80,
                result.lines[0].y,
                0.001,
            );
            try std.testing.expectEqual(
                @as(?paragraph.Align, case.alignment),
                result.lines[0].resolved_alignment,
            );
        }
    }
}

test "vertical alignment uses the post-indent column region" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const centered = try layout(&font, &buffer, "A", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .alignment = .center,
        .first_line_indent = 10,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    // The available region is [10, 100], so 20 units of content start at 45.
    try std.testing.expectApproxEqAbs(@as(f32, 45), centered.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        centered.lines[0].indent,
        0.001,
    );

    const ended = try layout(&font, &buffer, "A", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .alignment = .end,
        .first_line_indent = 10,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 80), ended.lines[0].y, 0.001);
}

test "vertical soft columns align independently after first indent" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAA", .{
        .max_width = 50,
        .alignment = .center,
        .first_line_indent = 10,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), result.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15), result.lines[1].y, 0.001);
}

test "vertical hard segments reset indent before alignment" {
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
        .alignment = .center,
        .first_line_indent = 10,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 45), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 45), result.lines[1].y, 0.001);

    const trailing = try layout(&font, &buffer, "A\n", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .alignment = .end,
        .first_line_indent = 10,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), trailing.lines.len);
    try std.testing.expectEqual(@as(usize, 0), trailing.lines[1].glyph_len);
    // An empty hard segment has zero content size and aligns at the end of its
    // own [indent, max_width] region.
    try std.testing.expectApproxEqAbs(
        @as(f32, 100),
        trailing.lines[1].y,
        0.001,
    );
}

test "vertical alignment never shifts overfull or unbounded columns backward" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const overfull = try layout(&font, &buffer, "AAA", .{
        .max_width = 40,
        .wrap_mode = .no_wrap,
        .alignment = .end,
        .first_line_indent = 10,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        overfull.lines[0].y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 70), overfull.height, 0.001);

    const unbounded = try layout(&font, &buffer, "A", .{
        .max_width = std.math.inf(f32),
        .wrap_mode = .no_wrap,
        .alignment = .center,
        .first_line_indent = 10,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        unbounded.lines[0].y,
        0.001,
    );
}
