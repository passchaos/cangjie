//! Static rectangular exclusions in vertical-lr block progression.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

test "vertical exclusion chooses the widest positive-down fragment" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAA", .{
        .max_width = 100,
        .exclusions = &.{.{
            .x = 0,
            .y = 0,
            .width = 20,
            .height = 30,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), result.lines[0].region_inline_start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 70), result.lines[0].region_inline_size, 0.001);
    try std.testing.expectEqual(@as(usize, 3), result.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.lines[1].x, 0.001);
}

test "fully blocked vertical band advances to exclusion right edge" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AA", .{
        .max_width = 40,
        .exclusions = &.{.{ .x = 0, .y = 0, .width = 35, .height = 40 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 35), result.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].y, 0.001);
}

test "vertical exclusions honor indent and explicit-region precedence" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const indented = try layout(&font, &buffer, "AA", .{
        .max_width = 60,
        .first_line_indent = 20,
        .exclusions = &.{.{ .x = 0, .y = 20, .width = 20, .height = 10 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 30), indented.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), indented.lines[0].region_inline_size, 0.001);

    const explicit = try layout(&font, &buffer, "A", .{
        .max_width = 60,
        .line_regions = &.{.{ .x = 5, .y = 7, .width = 30 }},
        .exclusions = &.{.{ .x = 0, .y = 0, .width = 100, .height = 100 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 5), explicit.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), explicit.lines[0].y, 0.001);
}

test "vertical-rl exclusion advances left across a fully blocked band" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const result = try layout(&font, &buffer, "AA", .{
        .max_width = 40,
        .exclusions = &.{paragraph.Exclusion{ .x = -20, .y = 0, .width = 20, .height = 40 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    // The local -40 origin is translated by the paragraph's 20-unit width.
    try std.testing.expectApproxEqAbs(@as(f32, -20), result.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].y, 0.001);
}

test "vertical-rl exclusion chooses the widest positive-down fragment" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAA", .{
        .max_width = 100,
        .exclusions = &.{paragraph.Exclusion{ .x = -20, .y = 0, .width = 20, .height = 30 }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 70), result.lines[0].region_inline_size, 0.001);
    try std.testing.expectEqual(@as(usize, 3), result.lines[0].glyph_len);
}
