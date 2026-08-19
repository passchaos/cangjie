//! Generic inter-word and CJK expansion in vertical soft-wrapped columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

test "vertical CJK justification expands only non-terminal soft columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "一丁丂", .{
        .max_width = 50,
        .alignment = .justify,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), result.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), result.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.glyphs[2].y_advance, 0.001);
    try std.testing.expectEqual(@as(?paragraph.Align, .justify), result.lines[0].resolved_alignment);
    try std.testing.expect(result.lines[0].justification_target == null);

    const truncated = try layout(&font, &buffer, "一丁丂", .{
        .max_width = 50,
        .max_lines = 1,
        .alignment = .justify,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), truncated.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), truncated.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), truncated.glyphs[0].y_advance, 0.001);
}

test "vertical justification leaves hard terminal and tab-ruler columns natural" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const hard = try layout(&font, &buffer, "一丁\n丂", .{
        .max_width = 100,
        .alignment = .justify,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), hard.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), hard.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), hard.lines[1].height, 0.001);

    const tabbed = try layout(&font, &buffer, "一\t丁丂", .{
        .max_width = 70,
        .alignment = .justify,
        .tab_stops = &.{.{ .position = 40 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(?paragraph.Align, .start), tabbed.lines[0].resolved_alignment);
    try std.testing.expect(tabbed.lines[0].justification_target == null);
}

test "vertical balanced columns retain generic justification targets" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "一丁丂七", .{
        .max_width = 50,
        .line_break_strategy = .balanced,
        .alignment = .justify,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), result.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), result.lines[1].height, 0.001);
}
