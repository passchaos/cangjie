//! Vertical tab rulers measured from each column's logical inline start.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

test "vertical tabs use explicit stops and repeating fallback grid" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const explicit = try layout(&font, &buffer, "A\tA", .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), explicit.glyphs.len);
    try std.testing.expect(explicit.glyphs[1].isTab());
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        explicit.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 80), explicit.height, 0.001);

    const fallback = try layout(&font, &buffer, "A\tA\tA", .{
        .max_width = 400,
        .tab_width = 2,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        fallback.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        fallback.glyphs[3].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 100), fallback.height, 0.001);
}

test "vertical tab field alignments use y advances and decimal fallback" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const center = try layout(&font, &buffer, "A\tAA", .{
        .max_width = 200,
        .tab_stops = &.{.{
            .position = 80,
            .alignment = .center,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        center.glyphs[1].y_advance,
        0.001,
    );

    const end = try layout(&font, &buffer, "A\tAA", .{
        .max_width = 200,
        .tab_stops = &.{.{
            .position = 80,
            .alignment = .end,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        end.glyphs[1].y_advance,
        0.001,
    );
    const end_tab_advance = end.glyphs[1].y_advance;

    const decimal = try layout(&font, &buffer, "A\tA.A", .{
        .max_width = 200,
        .tab_stops = &.{.{
            .position = 80,
            .alignment = .decimal,
            .decimal_point = '.',
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        decimal.glyphs[1].y_advance,
        0.001,
    );

    const missing_decimal = try layout(&font, &buffer, "A\tAA", .{
        .max_width = 200,
        .tab_stops = &.{.{
            .position = 80,
            .alignment = .decimal,
            .decimal_point = ',',
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        end_tab_advance,
        missing_decimal.glyphs[1].y_advance,
        0.001,
    );
}

test "vertical tab stops are local to indented column starts" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "A\tA", .{
        .max_width = 200,
        .first_line_indent = 10,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 10), result.lines[0].y, 0.001);
    // The ruler origin is the indented column start; A consumes 20 and the tab
    // advances another 40 to the 60-unit stop.
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        result.glyphs[1].y_advance,
        0.001,
    );
    const second = result.caretRect(.{
        .glyph_index = 2,
        .cluster = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 70), second.y, 0.001);
}

test "vertical tabs reset at hard and soft column boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const hard = try layout(&font, &buffer, "A\tA\nAA\tA", .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), hard.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        hard.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        hard.glyphs[5].y_advance,
        0.001,
    );

    const soft = try layout(&font, &buffer, "A A\tA", .{
        .max_width = 60,
        .tab_stops = &.{.{ .position = 40 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), soft.lines.len);
    // UAX #14 discards the tab marker at the selected boundary while its
    // source byte remains owned by the preceding logical line.
    try std.testing.expectEqual(@as(usize, 3), soft.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), soft.lines[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 4), soft.lines[0].byte_len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        soft.glyphs[3].y_advance,
        0.001,
    );
}

test "vertical tab alignment lookahead remains safe across soft wrapping" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "A\tAAA A", .{
        .max_width = 80,
        .tab_stops = &.{.{
            .position = 80,
            .alignment = .end,
        }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(result.lines.len > 1);
    for (result.lines) |line| {
        try std.testing.expect(line.y + line.height <= 80.001);
    }
}

test "vertical collapse turns tabs into ordinary source-visible blanks" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "A \t  A", .{
        .max_width = 200,
        .white_space_collapse = .collapse,
        .tab_stops = &.{.{ .position = 120 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(result.glyphs[2].isTab());
    try std.testing.expect(!result.glyphs[2].isActiveTab());
    try std.testing.expectEqual(@as(f32, 0), result.glyphs[2].y_advance);

    const break_spaces = try layout(&font, &buffer, "A\t\t", .{
        .max_width = 40.1,
        .tab_width = 1,
        .white_space_collapse = .break_spaces,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), break_spaces.lines.len);
    try std.testing.expectEqual(
        @as(usize, 2),
        break_spaces.lines[0].glyph_len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        break_spaces.lines[1].glyph_len,
    );
    for (break_spaces.lines) |line| {
        const tab =
            break_spaces.glyphs[line.glyph_start + line.glyph_len - 1];
        try std.testing.expect(tab.isActiveTab());
        try std.testing.expect(tab.y_advance > 0);
    }
}
