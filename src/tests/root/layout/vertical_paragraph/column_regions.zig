//! Caller-selected physical origins and inline measures for vertical columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

test "vertical column regions control wrapping origin and alignment" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const regions = [_]paragraph.LineRegion{
        .{ .x = 100, .y = 10, .width = 30 },
        .{ .x = 60, .y = 20, .width = 50 },
        .{ .x = 20, .y = 30, .width = 40 },
    };

    const result = try layout(&font, &buffer, "AAAAA", .{
        .max_width = 200,
        .first_line_indent = 80,
        .line_regions = &regions,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    for (result.lines, regions, &[_]usize{ 1, 2, 2 }) |line, region, count| {
        try std.testing.expectEqual(count, line.glyph_len);
        try std.testing.expectApproxEqAbs(region.x, line.x, 0.001);
        try std.testing.expectApproxEqAbs(region.x, line.region_x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.y, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.region_inline_start, 0.001);
        try std.testing.expectApproxEqAbs(region.width, line.region_inline_size, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 0), line.indent, 0.001);
        try std.testing.expect(line.height <= region.width + 0.001);
    }

    const centered = try layout(&font, &buffer, "A", .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .alignment = .center,
        .line_regions = regions[0..1],
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 15), centered.lines[0].y, 0.001);
}

test "vertical balanced wrapping uses each explicit column measure" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const regions = [_]paragraph.LineRegion{
        .{ .x = 80, .y = 0, .width = 30 },
        .{ .x = 40, .y = 10, .width = 50 },
        .{ .x = 0, .y = 20, .width = 40 },
    };

    const result = try layout(&font, &buffer, "AAAAA", .{
        .max_width = 200,
        .line_break_strategy = .balanced,
        .line_regions = &regions,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    for (result.lines, regions) |line, region| {
        try std.testing.expectApproxEqAbs(region.x, line.x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.region_inline_start, 0.001);
        try std.testing.expectApproxEqAbs(region.width, line.region_inline_size, 0.001);
        try std.testing.expect(line.height <= region.width + 0.001);
    }
}
