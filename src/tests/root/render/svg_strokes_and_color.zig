//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const ColorRenderTarget = support.ColorRenderTarget;
const Rasterizer = support.Rasterizer;
const testing = support.testing;

test "renders OpenType SVG rect and circle strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgStrokeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(green_pixels > 10);
    try std.testing.expect(translucent_blue_pixels > 20);

    const rect_center = target.at(27, 41);
    try std.testing.expectEqual(@as(u8, 0), rect_center.a);
}

test "renders OpenType SVG stroke line caps" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgLineCapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const butt_before_start = target.at(22, 23);
    try std.testing.expectEqual(@as(u8, 0), butt_before_start.a);

    const round_before_start = target.at(22, 35);
    try std.testing.expect(round_before_start.b > 0);
    try std.testing.expectEqual(@as(u8, 0), round_before_start.r);

    const square_before_start = target.at(22, 47);
    try std.testing.expect(square_before_start.g > 0);
    try std.testing.expectEqual(@as(u8, 0), square_before_start.r);
}

test "renders OpenType SVG dashed strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgDashTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const first_dash = target.at(19, 31);
    try std.testing.expect(first_dash.r > 0);
    try std.testing.expectEqual(@as(u8, 0), first_dash.b);

    const first_gap = target.at(24, 31);
    try std.testing.expectEqual(@as(u8, 0), first_gap.a);

    const second_dash = target.at(29, 31);
    try std.testing.expect(second_dash.r > 0);

    const odd_dash_polyline = target.at(19, 44);
    try std.testing.expect(odd_dash_polyline.b > 0);

    const odd_dash_gap = target.at(24, 44);
    try std.testing.expectEqual(@as(u8, 0), odd_dash_gap.a);
}

test "renders OpenType SVG dash offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgDashOffsetTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const offset_start_gap = target.at(19, 31);
    try std.testing.expectEqual(@as(u8, 0), offset_start_gap.a);

    const offset_first_dash = target.at(25, 31);
    try std.testing.expect(offset_first_dash.r > 0);
    try std.testing.expectEqual(@as(u8, 0), offset_first_dash.b);
}

test "renders OpenType SVG round stroke joins" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgLineJoinTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const default_join_outer_corner = target.at(32, 22);
    try std.testing.expectEqual(@as(u8, 0), default_join_outer_corner.a);

    const round_join_outer_corner = target.at(51, 22);
    try std.testing.expect(round_join_outer_corner.b > 0);
    try std.testing.expectEqual(@as(u8, 0), round_join_outer_corner.r);

    const bevel_join_outer_corner = target.at(29, 44);
    try std.testing.expect(bevel_join_outer_corner.g > 0);
    try std.testing.expectEqual(@as(u8, 0), bevel_join_outer_corner.r);

    const miterlimit_bevel_outer_corner = target.at(51, 44);
    try std.testing.expect(miterlimit_bevel_outer_corner.r > 0);
    try std.testing.expectEqual(@as(u8, 0), miterlimit_bevel_outer_corner.b);
}

test "renders OpenType SVG defs and use references" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgUseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const defs_origin = target.at(13, 13);
    try std.testing.expectEqual(@as(u8, 0), defs_origin.a);

    const used_rect = target.at(25, 25);
    try std.testing.expect(used_rect.r > 0);
    try std.testing.expectEqual(@as(u8, 0), used_rect.b);

    const used_circle = target.at(44, 38);
    try std.testing.expect(used_circle.b > 0);
    try std.testing.expectEqual(@as(u8, 0), used_circle.r);
    try std.testing.expect(used_circle.a < 255);

    const used_group_rect = target.at(21, 49);
    try std.testing.expect(used_group_rect.r > 0);
    try std.testing.expectEqual(@as(u8, 0), used_group_rect.b);

    const used_group_circle = target.at(29, 48);
    try std.testing.expect(used_group_circle.g > 0);
    try std.testing.expectEqual(@as(u8, 0), used_group_circle.r);
}

test "renders OpenType SVG rect clip paths" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgClipTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const inside_clip = target.at(24, 32);
    try std.testing.expect(inside_clip.r > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_clip.b);

    const outside_clip = target.at(62, 24);
    try std.testing.expectEqual(@as(u8, 0), outside_clip.a);

    const inside_circle_clip = target.at(47, 35);
    try std.testing.expect(inside_circle_clip.b > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_circle_clip.r);

    const outside_circle_clip = target.at(59, 35);
    try std.testing.expectEqual(@as(u8, 0), outside_circle_clip.a);

    const inside_path_clip = target.at(40, 49);
    try std.testing.expect(inside_path_clip.g > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_path_clip.r);

    const outside_path_clip = target.at(36, 42);
    try std.testing.expectEqual(@as(u8, 0), outside_path_clip.a);
}

test "renders OpenType SVG alpha masks" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgMaskTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const inside_rect_mask = target.at(24, 32);
    try std.testing.expect(inside_rect_mask.r > 0);
    try std.testing.expect(inside_rect_mask.a > 0 and inside_rect_mask.a < 255);

    const outside_rect_mask = target.at(62, 24);
    try std.testing.expectEqual(@as(u8, 0), outside_rect_mask.a);

    const inside_circle_mask = target.at(47, 35);
    try std.testing.expect(inside_circle_mask.b > 0);
    try std.testing.expect(inside_circle_mask.a > 0 and inside_circle_mask.a < 255);

    const outside_circle_mask = target.at(59, 35);
    try std.testing.expectEqual(@as(u8, 0), outside_circle_mask.a);

    const inside_path_mask = target.at(40, 49);
    try std.testing.expect(inside_path_mask.g > 0);
    try std.testing.expect(inside_path_mask.a > 0 and inside_path_mask.a < 255);

    const outside_path_mask = target.at(36, 42);
    try std.testing.expectEqual(@as(u8, 0), outside_path_mask.a);

    const combo_rect_mask = target.at(20, 52);
    try std.testing.expect(combo_rect_mask.b > 0);
    try std.testing.expect(combo_rect_mask.a > 0 and combo_rect_mask.a < 255);

    const combo_circle_mask = target.at(32, 52);
    try std.testing.expect(combo_circle_mask.b > 0);
    try std.testing.expect(combo_circle_mask.a > 0 and combo_circle_mask.a < 255);

    const combo_gap_mask = target.at(27, 52);
    try std.testing.expectEqual(@as(u8, 0), combo_gap_mask.a);

    const black_masked = target.at(51, 52);
    try std.testing.expectEqual(@as(u8, 0), black_masked.a);
}

test "honors OpenType SVG display and visibility" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgVisibilityTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const visible = target.at(21, 27);
    try std.testing.expect(visible.r > 0);
    try std.testing.expectEqual(@as(u8, 0), visible.b);

    const display_none = target.at(34, 27);
    try std.testing.expectEqual(@as(u8, 0), display_none.a);

    const hidden_group = target.at(47, 27);
    try std.testing.expectEqual(@as(u8, 0), hidden_group.a);

    const style_hidden = target.at(21, 44);
    try std.testing.expectEqual(@as(u8, 0), style_hidden.a);
}

test "renders OpenType SVG path strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgPathStrokeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);

    const triangle_center = target.at(36, 48);
    try std.testing.expectEqual(@as(u8, 0), triangle_center.a);
}

test "renders OpenType SVG line polyline and polygon shapes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgPolylineTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(green_pixels > 10);
}

test "renders OpenType SVG ellipse fill and stroke" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgEllipseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);

    const stroke_center = target.at(47, 37);
    try std.testing.expectEqual(@as(u8, 0), stroke_center.a);
}

test "renders OpenType SVG linear gradient fills" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const left = target.at(20, 32);
    try std.testing.expect(left.r > left.b);
    try std.testing.expect(left.a > 0);

    const right = target.at(50, 32);
    try std.testing.expect(right.b > right.r);
    try std.testing.expect(right.a > 0);

    const middle = target.at(36, 32);
    try std.testing.expect(middle.g > middle.r);
    try std.testing.expect(middle.g > middle.b);
}

test "renders OpenType SVG radial gradient fills" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgRadialGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const center = target.at(36, 36);
    try std.testing.expect(center.r > center.b);
    try std.testing.expect(center.a > 0);

    const edge = target.at(54, 36);
    try std.testing.expect(edge.b > edge.r);
    try std.testing.expect(edge.a > 0);

    const outside = target.at(63, 36);
    try std.testing.expectEqual(@as(u8, 0), outside.a);
}

test "renders OpenType SVG gradient spread methods" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgGradientSpreadTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const repeat_second_period_start = target.at(27, 26);
    try std.testing.expect(repeat_second_period_start.r > repeat_second_period_start.b);

    const repeat_second_period_end = target.at(35, 26);
    try std.testing.expect(repeat_second_period_end.b > repeat_second_period_end.r);

    const reflect_second_period_start = target.at(27, 45);
    try std.testing.expect(reflect_second_period_start.b > reflect_second_period_start.r);

    const reflect_second_period_end = target.at(36, 45);
    try std.testing.expect(reflect_second_period_end.r > reflect_second_period_end.b);
}

test "renders OpenType SVG gradient transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSvgGradientTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const top = target.at(36, 20);
    try std.testing.expect(top.r > top.b);

    const bottom = target.at(36, 55);
    try std.testing.expect(bottom.b > bottom.r);
}

test "renders COLR glyph layers into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_channel_pixels: usize = 0;
    var blue_channel_pixels: usize = 0;
    var covered_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        covered_pixels += 1;
        if (pixel.r > 0) red_channel_pixels += 1;
        if (pixel.b > 0) blue_channel_pixels += 1;
    }

    try std.testing.expect(covered_pixels > 10);
    try std.testing.expect(red_channel_pixels > 0);
    try std.testing.expect(blue_channel_pixels > 0);
}

test "renders shaped text with COLR glyph layers into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const fonts = [_]*const Font{&font};
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A", 24);

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorShapedText(&target, shaped, 8, 32, 0);

    var red_channel_pixels: usize = 0;
    var blue_channel_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0) red_channel_pixels += 1;
        if (pixel.b > 0) blue_channel_pixels += 1;
    }
    try std.testing.expect(red_channel_pixels > 0);
    try std.testing.expect(blue_channel_pixels > 0);
}
