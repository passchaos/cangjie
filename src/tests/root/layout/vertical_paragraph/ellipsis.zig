//! Positive-down ellipsis fitting for limited vertical columns.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical ellipsis fits an upright synthetic tail along y" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAAAA", .{
        .max_width = 100.1,
        .max_lines = 1,
        .ellipsis = true,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 5), result.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 100),
        result.lines[0].height,
        0.001,
    );
    try std.testing.expect(result.lines[0].height <= 100.1);
    try std.testing.expectEqual(@as(usize, 1), result.runs.len);
    try std.testing.expectEqual(result.glyphs.len, result.runs[0].glyph_len);
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
        try std.testing.expectEqual(
            support.GlyphOrientation.upright,
            glyph.orientation,
        );
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
    }

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(result.glyphs.len, draw_list.glyphs.len);
    for (draw_list.glyphs[draw_list.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(
            support.GlyphOrientation.upright,
            glyph.orientation,
        );
    }
}

test "vertical mixed ellipsis rotates periods and realigns column" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "AAAAAAAA", .{
        .max_width = 120.1,
        .max_lines = 1,
        .ellipsis = true,
        .alignment = .center,
        .writing_mode = .vertical_lr,
        .text_orientation = .mixed,
    });
    const line = result.lines[0];
    try std.testing.expectApproxEqAbs(@as(f32, 110), line.height, 0.001);
    try std.testing.expectApproxEqAbs(
        (120.1 - line.height) / 2,
        line.y,
        0.001,
    );
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(
            support.GlyphOrientation.sideways,
            glyph.orientation,
        );
        // The fixture's .notdef horizontal advance is half its one-em
        // vertical advance, proving that synthetic dots use orientation-aware
        // metrics rather than copying an arbitrary source glyph.
        try std.testing.expectApproxEqAbs(@as(f32, 10), glyph.y_advance, 0.001);
    }
}

test "vertical ellipsis reuses a retained fallback face that maps period" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const primary_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{'A'},
    );
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{ '.', 'B' },
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{ &primary, &fallback }),
        &buffer,
        "ABAAAA",
        20,
        .{
            .max_width = 100.1,
            .max_lines = 1,
            .ellipsis = true,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(result.runs.len >= 2);
    const terminal_run = result.runs[result.runs.len - 1];
    try std.testing.expectEqual(@as(usize, 1), terminal_run.font_index);
    const period_glyph = try fallback.glyphIndex('.');
    try std.testing.expect(period_glyph != 0);
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(period_glyph, glyph.glyph_id);
    }
}

test "vertical ellipsis is inert without omitted visible columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const exact = try layout(&font, &buffer, "AA", .{
        .max_width = 100,
        .max_lines = 1,
        .ellipsis = true,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), exact.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), exact.glyphs[1].codepoint);

    const hidden = try layout(&font, &buffer, "AAAA", .{
        .max_width = 20.1,
        .max_lines = 0,
        .ellipsis = true,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 0), hidden.lines.len);
    try std.testing.expectEqual(@as(usize, 0), hidden.glyphs.len);
}

test "vertical ellipsis recomputes an aligned terminal tab field" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, "A\tAA AA AA", .{
        .max_width = 120.1,
        .max_lines = 1,
        .ellipsis = true,
        .tab_stops = &.{.{
            .position = 110,
            .alignment = .end,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(result.glyphs[1].isTab());
    try std.testing.expect(result.lines[0].height <= 120.1);
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}

test "vertical ellipsis removes trimmed in-flow object block occupancy" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const marker = @import("../../../../api/paragraph/root.zig")
        .object_replacement_utf8;
    const text = "AAAA" ++ marker ++ "A";

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 100.1,
            .max_lines = 1,
            .ellipsis = true,
            .inline_objects = &.{.{
                .id = 18,
                .byte_index = 4,
                .width = 80,
                .height = 20,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), result.inline_objects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.width, 0.001);
    try std.testing.expectEqual(@as(usize, 5), result.glyphs.len);
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}

test "vertical object-only column can materialize ellipsis without a source run" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const marker = @import("../../../../api/paragraph/root.zig")
        .object_replacement_utf8;
    const text = marker ++ marker;

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 20.1,
            .max_lines = 1,
            .ellipsis = true,
            .inline_objects = &.{
                .{ .id = 31, .byte_index = 0, .width = 20, .height = 20 },
                .{ .id = 32, .byte_index = 3, .width = 20, .height = 20 },
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .mixed,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.runs.len);
    try std.testing.expectEqual(@as(usize, 3), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), result.inline_objects.len);
    for (result.glyphs) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}
