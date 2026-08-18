//! Vertical source-order column limits independent from optional ellipsis.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical max-lines keeps a source-order soft-column prefix" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAA", .{
        .max_width = 20.1,
        .max_lines = 2,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 2), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), result.runs.len);
    try std.testing.expectEqual(@as(usize, 2), result.runs[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), result.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 1), result.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), result.lines[1].byte_len);
    // Physical RL placement is recomputed after truncation, so no invisible
    // suffix columns reserve block-axis width.
    try std.testing.expectApproxEqAbs(@as(f32, 40), result.width, 0.001);

    const no_op = try layout(&font, &buffer, "AA", .{
        .max_width = 20.1,
        .max_lines = 99,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), no_op.lines.len);
    try std.testing.expectEqual(@as(usize, 2), no_op.glyphs.len);
}

test "vertical max-lines composes hard and soft columns in source order" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AA\nAA", .{
        .max_width = 20.1,
        .max_lines = 3,
        .paragraph_spacing = 6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    try std.testing.expectEqual(@as(usize, 4), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 3), result.lines[1].byteEnd());
    try std.testing.expectEqual(@as(usize, 3), result.lines[2].byte_start);
    try std.testing.expectApproxEqAbs(
        @as(f32, 6),
        result.lines[2].x -
            (result.lines[1].x + result.lines[1].width),
        0.001,
    );
}

test "vertical zero max-lines clears every visible output stream" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A" ++ paragraph.object_replacement_utf8 ++ "A";

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .max_lines = 0,
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
    try std.testing.expectEqual(@as(usize, 0), result.lines.len);
    try std.testing.expectEqual(@as(usize, 0), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), result.runs.len);
    try std.testing.expectEqual(@as(usize, 0), result.inline_objects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.height, 0.001);
}
