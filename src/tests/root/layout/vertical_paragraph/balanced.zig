//! Whole-segment balanced wrapping for vertical paragraph columns.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

test "vertical balanced wrapping lowers raggedness without adding columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAA AA AA A";

    const greedy = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), greedy.lines.len);
    try expectGlyphCounts(greedy, &.{ 3, 5, 1 });

    const balanced = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(greedy.lines.len, balanced.lines.len);
    try expectGlyphCounts(balanced, &.{ 3, 2, 4 });
    try std.testing.expectEqual(@as(usize, 0), balanced.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), balanced.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 4), balanced.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 3), balanced.lines[1].byte_len);
    try std.testing.expectEqual(@as(usize, 7), balanced.lines[2].byte_start);
    try std.testing.expectEqual(text.len - 7, balanced.lines[2].byte_len);
}

test "vertical balanced wrapping keeps hard segments independent" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAA AA AA A\nAAA AA AA A";

    const result = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 6), result.lines.len);
    try expectGlyphCounts(result, &.{ 3, 2, 4, 3, 2, 4 });
    try std.testing.expectEqual(
        @as(usize, "AAA AA AA A\n".len),
        result.lines[3].byte_start,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 6),
        result.lines[2].x -
            (result.lines[3].x + result.lines[3].width),
        0.001,
    );
}

test "vertical balanced wrapping reserves first-column inline indent" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAAA", .{
        .max_width = 60,
        .first_line_indent = 20,
        .line_break_strategy = .balanced,
        .word_break = .break_all,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectGlyphCounts(result, &.{ 2, 3 });
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        result.lines[0].indent,
        0.001,
    );
    try std.testing.expect(result.lines[0].height <= 40.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.lines[1].indent,
        0.001,
    );
    try std.testing.expect(result.lines[1].height <= 60.001);
}

test "vertical balanced is inert for no-wrap and unbounded columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const no_wrap = try layout(&font, &buffer, "AAA AA", .{
        .max_width = 1,
        .wrap_mode = .no_wrap,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), no_wrap.lines.len);

    const unbounded = try layout(&font, &buffer, "AAA AA", .{
        .max_width = std.math.inf(f32),
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), unbounded.lines.len);
}

fn expectGlyphCounts(
    result: support.ParagraphLayout,
    expected: []const usize,
) !void {
    try std.testing.expectEqual(expected.len, result.lines.len);
    for (result.lines, expected) |line, glyph_count| {
        try std.testing.expectEqual(glyph_count, line.glyph_len);
    }
}
