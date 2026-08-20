//! Fontless atoms, fallback runs, and ellipsis under vertical UAX #9.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "vertical bidi keeps an inline object as a fontless visual atom" {
    const allocator = std.testing.allocator;
    const marker = paragraph.object_replacement_utf8;
    const text = "א" ++ marker ++ "ב";
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
            .inline_objects = &.{.{
                .id = 9,
                .byte_index = 2,
                .width = 12,
                .height = 12,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 5, 2, 0 });
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        result.inline_objects[0].y,
        0.001,
    );
    var font_owned: usize = 0;
    for (result.runs) |run| font_owned += run.glyph_len;
    try std.testing.expectEqual(@as(usize, 2), font_owned);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.inline_objects.len);
}

test "vertical bidi preserves logical tab field geometry after permutation" {
    const allocator = std.testing.allocator;
    const text = "A\tאבB";
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
            .tab_stops = &.{.{ .position = 60 }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 0, 1, 4, 2, 6 });
    try std.testing.expect(result.glyphs[1].isTab());
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        result.glyphs[1].y_advance,
        0.001,
    );
    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 4), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
}

test "vertical bidi rebuilds fallback font runs in visual order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const primary_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{ 'A', 'B' },
    );
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{ 0x05d0, 0x05d1 },
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
        "AאבB",
        20,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 0, 3, 1, 5 });
    try std.testing.expectEqual(@as(usize, 3), result.runs.len);
    try std.testing.expectEqual(@as(usize, 0), result.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), result.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), result.runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 2), result.runs[1].glyph_len);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 3), draw_list.runs.len);
    try std.testing.expect(draw_list.runs[0].font != draw_list.runs[1].font);
    try std.testing.expect(draw_list.runs[0].font == draw_list.runs[2].font);

    var overlays = try support.buildDebugOverlays(allocator, result, .{});
    defer overlays.deinit();
    var fallback_regions: [3]paragraph.Rect = undefined;
    var fallback_count: usize = 0;
    for (overlays.items) |item| {
        if (item.kind != .fallback_font_region) continue;
        if (fallback_count >= fallback_regions.len) {
            return error.TestUnexpectedFallbackRegion;
        }
        fallback_regions[fallback_count] = item.rect;
        fallback_count += 1;
    }
    try std.testing.expectEqual(fallback_regions.len, fallback_count);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        fallback_regions[0].y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        fallback_regions[1].y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        fallback_regions[1].height,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        fallback_regions[2].y,
        0.001,
    );
}

test "vertical bidi keeps ellipsis at visual inline end" {
    const allocator = std.testing.allocator;
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
        "Aאבגדה",
        20,
        .{
            .max_width = 80.1,
            .max_lines = 1,
            .ellipsis = true,
            .word_break = .break_all,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    const line = result.lines[0];
    const visible =
        result.glyphs[line.glyph_start .. line.glyph_start + line.glyph_len];
    try std.testing.expect(visible.len >= 3);
    for (visible[visible.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
    try std.testing.expect(line.height <= 80.1);
}

fn expectClusters(glyphs: []const support.GlyphPosition, expected: []const usize) !void {
    try std.testing.expectEqual(expected.len, glyphs.len);
    for (glyphs, expected) |glyph, cluster| {
        try std.testing.expectEqual(cluster, glyph.cluster);
    }
}
