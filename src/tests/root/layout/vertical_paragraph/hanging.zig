//! Optical line-end punctuation hanging in vertical columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

const wrapping_text = "一丁。丂";
const terminal_text = "一丁丂。";

test "vertical punctuation hanging expands fit without changing advances" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, wrapping_text, .{
        .max_width = 50,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // UAX #14 prohibits a break before U+3002, so without hanging the latest
    // fitting authored edge is after the first ideograph.
    try std.testing.expectEqual(@as(usize, 1), natural.lines[0].glyph_len);

    const hanging = try layout(&font, &buffer, wrapping_text, .{
        .max_width = 50,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), hanging.lines[0].glyph_len);
    const first = hanging.lines[0];
    const glyphs = first.glyphs(hanging);
    const punctuation_advance = glyphs[glyphs.len - 1].y_advance;
    try std.testing.expectEqual(@as(u21, 0x3002), glyphs[glyphs.len - 1].codepoint);
    try std.testing.expectApproxEqAbs(
        punctuation_advance / 2,
        first.hang_end,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), first.hang_start, 0.001);
    try std.testing.expectApproxEqAbs(
        inlineAdvance(glyphs) - first.hang_end,
        first.height,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 50),
        first.height,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        first.y + first.height,
        hanging.height,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 0), first.byte_start);
    try std.testing.expectEqual(@as(usize, "一丁。".len), first.byte_len);
    try std.testing.expectEqual(first.byteEnd(), hanging.lines[1].byte_start);

    // Caret and selection geometry retain the complete glyph advances rather
    // than collapsing the protruding punctuation's source extent.
    const trailing = hanging.caretRect(.{
        .glyph_index = first.glyph_start + first.glyph_len - 1,
        .cluster = "一丁。".len,
        .trailing = true,
    });
    try std.testing.expectApproxEqAbs(
        first.y + inlineAdvance(glyphs),
        trailing.y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        inlineAdvance(glyphs),
        hanging.selectionRectForBytes(0, "一丁。".len).height,
        0.001,
    );
}

test "vertical punctuation compression remains explicitly unsupported" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    try std.testing.expectError(
        error.UnsupportedVerticalParagraphOptions,
        layout(&font, &buffer, wrapping_text, .{
            .max_width = 50,
            .punctuation = .{
                .max_compression_fraction = 1,
                .end_hanging_fraction = 0.5,
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        }),
    );
}

test "vertical balanced wrapping and alignment use occupied hanging height" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    for ([_]paragraph.Align{ .start, .center, .end }) |alignment| {
        const result = try layout(&font, &buffer, terminal_text, .{
            .max_width = 100,
            .line_break_strategy = .balanced,
            .alignment = alignment,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        });
        try std.testing.expectEqual(@as(usize, 1), result.lines.len);
        const line = result.lines[0];
        try std.testing.expectApproxEqAbs(@as(f32, 10), line.hang_end, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 70), line.height, 0.001);
        const expected_y: f32 = switch (alignment) {
            .start => 0,
            .center => 15,
            .end => 30,
            else => unreachable,
        };
        try std.testing.expectApproxEqAbs(expected_y, line.y, 0.001);
        try std.testing.expectApproxEqAbs(
            expected_y + 80,
            result.caretRect(.{
                .glyph_index = line.glyph_start + line.glyph_len - 1,
                .cluster = terminal_text.len,
                .trailing = true,
            }).y,
            0.001,
        );
    }
}

test "vertical hanging uses final bidi visual bottom edge" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{ 'A', 'B', 0x05d0, 0x05d1, 0x3002 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const bidi_text = "AאבB。";

    const result = try layout(&font, &buffer, bidi_text, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    const line = result.lines[0];
    const glyphs = line.glyphs(result);
    try std.testing.expectEqual(@as(u21, 0x3002), glyphs[glyphs.len - 1].codepoint);
    try std.testing.expect(line.hang_end > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), line.hang_start, 0.001);
}

test "vertical tab-ruler column remains start pinned while punctuation hangs" {
    const allocator = std.testing.allocator;
    const bytes = try hangingFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "一\t丁。", .{
        .max_width = 120,
        .wrap_mode = .no_wrap,
        .alignment = .end,
        .tab_stops = &.{.{ .position = 80, .alignment = .end }},
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[0].y, 0.001);
    try std.testing.expect(result.lines[0].hang_end > 0);
    try std.testing.expectEqual(
        paragraph.Align.start,
        result.lines[0].resolved_alignment.?,
    );
}

fn inlineAdvance(glyphs: []const support.GlyphPosition) f32 {
    var result: f32 = 0;
    for (glyphs) |glyph| result += glyph.y_advance;
    return result;
}

fn hangingFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
}
