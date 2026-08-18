//! Safe negative letter/word spacing along the vertical inline axis.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical negative letter and word spacing shrink positive advances" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "A A", .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const natural_letter = natural.glyphs[0].y_advance;
    const natural_word = natural.glyphs[1].y_advance;
    const compressed = try layout(&font, &buffer, "A A", .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .letter_spacing = -4,
        .word_spacing = -6,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        natural_letter - 4,
        compressed.glyphs[0].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        natural_word - 6,
        compressed.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        natural_letter - 4,
        compressed.glyphs[2].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        compressed.glyphs[0].y_advance +
            compressed.glyphs[1].y_advance +
            compressed.glyphs[2].y_advance,
        compressed.height,
        0.001,
    );
}

test "vertical negative spacing changes wrapping with monotone prefixes" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "AAAA", .{
        .max_width = 32.1,
        .word_break = .break_all,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 4), natural.lines.len);

    const compressed = try layout(&font, &buffer, "AAAA", .{
        .max_width = 32.1,
        .word_break = .break_all,
        .letter_spacing = -4,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), compressed.lines.len);
    for (compressed.lines) |line| {
        try std.testing.expectEqual(@as(usize, 2), line.glyph_len);
        try std.testing.expectApproxEqAbs(@as(f32, 32), line.height, 0.001);
    }
}

test "vertical spacing permits zero but rejects reverse source advances" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const zero = try layout(&font, &buffer, "AA", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .letter_spacing = -20,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), zero.height, 0.001);
    for (zero.glyphs) |glyph| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.y_advance, 0.001);
    }
    var geometry = try paragraph.buildGeometry(
        allocator,
        "AA",
        zero,
        .{},
    );
    defer geometry.deinit();
    const stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 3), stops.len);
    for (stops) |stop| {
        try std.testing.expectApproxEqAbs(
            zero.lines[0].y,
            stop.inline_position,
            0.001,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        zero.selectionRectForBytes(0, 2).height,
        0.001,
    );

    try std.testing.expectError(
        error.InvalidParagraphOptions,
        layout(&font, &buffer, "A", .{
            .max_width = 100,
            .letter_spacing = -20.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        layout(&font, &buffer, "A A", .{
            .max_width = 100,
            .word_spacing = -20.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );
}

test "vertical collapse may erase an otherwise negative space advance" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    try std.testing.expectError(
        error.InvalidParagraphOptions,
        layout(&font, &buffer, "A A", .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .word_spacing = -20.1,
            .white_space_collapse = .preserve,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        }),
    );
    const collapsed = try layout(&font, &buffer, "A A", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .word_spacing = -20.1,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        collapsed.glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 40), collapsed.height, 0.001);
}

test "vertical negative spacing keeps tabs and public interaction synchronized" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\tA";

    const result = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .letter_spacing = -4,
        .tab_stops = &.{.{ .position = 60 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 16), result.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 44), result.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16), result.glyphs[2].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 76), result.height, 0.001);
    const caret = result.caretRect(.{
        .glyph_index = 2,
        .cluster = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 60), caret.y, 0.001);
    const selection = result.selectionRectForBytes(0, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 16), selection.height, 0.001);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        result,
        .{},
    );
    defer geometry.deinit();
    const stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 4), stops.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), stops[1].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), stops[2].inline_position, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
}
