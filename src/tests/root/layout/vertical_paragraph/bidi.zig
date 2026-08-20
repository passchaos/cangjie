//! UAX #9 visual order along positive-down vertical paragraph columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "vertical mixed bidi maps visual order onto the y pen" {
    const allocator = std.testing.allocator;
    const text = "AאבB";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 0, 3, 1, 5 });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 80), result.height, 0.001);
    try std.testing.expectEqual(@as(usize, 1), result.hitTest(10, 25).glyph_index);
    try std.testing.expectEqual(@as(usize, 3), result.hitTest(10, 25).cluster);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        result,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[1].direction,
    );
    const rtl = geometry.spans[1].graphemes(geometry.graphemes);
    try std.testing.expectEqual(@as(usize, 1), rtl[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), rtl[1].byte_start);
    try std.testing.expectApproxEqAbs(@as(f32, 20), rtl[0].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rtl[1].inline_position, 0.001);
    const rtl_start = geometry.caret(.{
        .byte_offset = 1,
        .affinity = .downstream,
    }).?;
    const rtl_end = geometry.caret(.{
        .byte_offset = 5,
        .affinity = .upstream,
    }).?;
    try std.testing.expect(rtl_start.rect.y > rtl_end.rect.y);
    const fragments = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = 3 },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 2), fragments.len);
    try std.testing.expect(fragments[0].rect.y < fragments[1].rect.y);

    const stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 5), stops.len);
    for (stops[1..], stops[0 .. stops.len - 1]) |current, previous| {
        try std.testing.expect(
            current.inline_position >= previous.inline_position,
        );
    }

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 4), draw_list.glyphs.len);
    for (draw_list.glyphs, 0..) |glyph, index| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatFromInt(index * 20)),
            glyph.baseline_y,
            0.001,
        );
    }
}

test "vertical UAX bidi resolves each soft column independently" {
    const allocator = std.testing.allocator;
    const text = "AאבגBדהוC";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 80.1,
            .word_break = .break_all,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    try expectLineClusters(result, 0, &.{ 0, 5, 3, 1 });
    try expectLineClusters(result, 1, &.{ 7, 12, 10, 8 });
    try expectLineClusters(result, 2, &.{14});
    try std.testing.expect(result.lines[0].x > result.lines[1].x);
    try std.testing.expect(result.lines[1].x > result.lines[2].x);
}

test "vertical bidi resets visual ordering at explicit hard columns" {
    const allocator = std.testing.allocator;
    const text = "Aאב\nBגד";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try expectLineClusters(result, 0, &.{ 0, 3, 1 });
    try expectLineClusters(result, 1, &.{ 6, 9, 7 });
    // The hard-break source atom remains a zero-advance metadata suffix rather
    // than entering either visible column.
    try std.testing.expectEqual(@as(usize, 5), result.glyphs[6].cluster);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        result.glyphs[6].y_advance,
        0.001,
    );
}

test "vertical explicit override reorders and mirrors without strong RTL text" {
    const allocator = std.testing.allocator;
    const text = "\u{202e}(AB)\u{202c}";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    var visible: [4]u21 = undefined;
    var count: usize = 0;
    for (result.glyphs) |glyph| {
        if (glyph.codepoint > 0x7f) continue;
        if (count >= visible.len) return error.TestUnexpectedVisibleGlyph;
        visible[count] = glyph.codepoint;
        count += 1;
    }
    try std.testing.expectEqual(visible.len, count);
    try std.testing.expectEqualSlices(u21, &.{ '(', 'B', 'A', ')' }, &visible);
}

test "vertical bidi isolates reorder their contents without escaping" {
    const allocator = std.testing.allocator;
    const text = "A\u{2067}אב\u{2069}B";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    var visible: [4]u21 = undefined;
    var count: usize = 0;
    for (result.glyphs) |glyph| {
        if (glyph.codepoint == 0x2067 or glyph.codepoint == 0x2069) continue;
        if (count >= visible.len) return error.TestUnexpectedVisibleGlyph;
        visible[count] = glyph.codepoint;
        count += 1;
    }
    try std.testing.expectEqual(visible.len, count);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 'ב', 'א', 'B' }, &visible);
}

test "vertical Arabic bidi class uses the same line-local order" {
    const allocator = std.testing.allocator;
    const text = "AابB";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 0, 3, 1, 5 });
}

fn expectLineClusters(
    result: support.ParagraphLayout,
    line_index: usize,
    expected: []const usize,
) !void {
    const line = result.lines[line_index];
    try expectClusters(
        result.glyphs[line.glyph_start .. line.glyph_start + line.glyph_len],
        expected,
    );
}

fn expectClusters(glyphs: []const support.GlyphPosition, expected: []const usize) !void {
    try std.testing.expectEqual(expected.len, glyphs.len);
    for (glyphs, expected) |glyph, cluster| {
        try std.testing.expectEqual(cluster, glyph.cluster);
    }
}
