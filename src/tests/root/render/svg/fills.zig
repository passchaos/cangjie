//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const ColorRenderTarget = support.ColorRenderTarget;
const Rasterizer = support.Rasterizer;
const testing = support.testing;

test "reads OpenType SVG glyph document metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const document = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqual(@as(GlyphId, 1), document.start_glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), document.end_glyph_id);
    try std.testing.expect(std.mem.startsWith(u8, document.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, document.data, "<path") != null);

    try std.testing.expect(try font.svgGlyphDocument(0) == null);
}

test "renders OpenType SVG glyph document into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    var non_red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) {
            red_pixels += 1;
        } else {
            non_red_pixels += 1;
        }
    }
    try std.testing.expect(red_pixels > 20);
    try std.testing.expectEqual(@as(usize, 0), non_red_pixels);
}

test "resolves and renders gzip OpenType SVG documents" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildGzipSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const raw = (try font.svgGlyphDocument(1)) orelse return error.MissingSvgGlyph;
    try std.testing.expectEqualSlices(u8, &.{ 0x1f, 0x8b, 0x08 }, raw.data[0..3]);

    var resolved = (try font.resolvedSvgGlyphDocument(allocator, 1)) orelse return error.MissingSvgGlyph;
    defer resolved.deinit();
    try std.testing.expect(resolved.allocator != null);
    try std.testing.expect(std.mem.startsWith(u8, resolved.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, resolved.data, "<rect") != null);

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0 and pixel.a > 0) red_pixels += 1;
    }
    try std.testing.expect(red_pixels > 50);
}

test "resolves real HarfBuzz gzip SVG fixture" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/harfbuzz/test/shape/data/text-rendering-tests/fonts/TestSVGgzip.otf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x1f600);
    try std.testing.expectEqual(@as(GlyphId, 3), glyph_id);

    var resolved = (try font.resolvedSvgGlyphDocument(allocator, glyph_id)) orelse return error.MissingSvgGlyph;
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 3166), resolved.data.len);
    try std.testing.expect(std.mem.startsWith(u8, resolved.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, resolved.data, "<linearGradient") != null);

    var target = try ColorRenderTarget.init(allocator, 160, 160);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 128, 16, 144, 0);
    var painted_pixels: usize = 0;
    var colored_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        painted_pixels += 1;
        if (pixel.r != pixel.g or pixel.g != pixel.b) colored_pixels += 1;
    }
    try std.testing.expect(painted_pixels > 400);
    try std.testing.expect(colored_pixels > 400);
}

test "renders OpenType SVG glyph with multiple curved paths" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgCurveTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 64, 64);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 40, 12, 52, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
    }
    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);
    try std.testing.expect(green_pixels > 20);
}

test "renders OpenType SVG rect circle and opacity paints" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgShapeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var green_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
        if (pixel.a < 255) translucent_pixels += 1;
    }
    try std.testing.expect(green_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_pixels > 20);
}

test "renders OpenType SVG transformed shapes at transformed positions" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(47, 17);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);

    const blue_sample = target.at(29, 46);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);

    const untransformed_red_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_red_origin.a);
}

test "renders OpenType SVG rotate transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgRotateTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const rotated_red = target.at(46, 36);
    try std.testing.expect(rotated_red.r > 0);
    try std.testing.expectEqual(@as(u8, 0), rotated_red.g);
    try std.testing.expectEqual(@as(u8, 0), rotated_red.b);

    const original_red_position = target.at(36, 22);
    try std.testing.expectEqual(@as(u8, 0), original_red_position.a);

    var blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
    }
    try std.testing.expect(blue_pixels > 10);
}

test "renders OpenType SVG skew transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgSkewTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const skewed_red = target.at(32, 26);
    try std.testing.expect(skewed_red.r > 0);
    try std.testing.expectEqual(@as(u8, 0), skewed_red.g);
    try std.testing.expectEqual(@as(u8, 0), skewed_red.b);

    const unskewed_red_top_right = target.at(18, 22);
    try std.testing.expectEqual(@as(u8, 0), unskewed_red_top_right.a);

    const skewed_blue = target.at(43, 52);
    try std.testing.expect(skewed_blue.b > 0);
    try std.testing.expectEqual(@as(u8, 0), skewed_blue.r);
    try std.testing.expectEqual(@as(u8, 0), skewed_blue.g);
}

test "renders OpenType SVG grouped inherited paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgGroupTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(31, 26);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(50, 24);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < 255);

    const untransformed_group_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_group_origin.a);
}

test "renders OpenType SVG nested grouped inherited paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgNestedGroupTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(27, 30);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(48, 28);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < 255);

    const untransformed_nested_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_nested_origin.a);
}

test "renders OpenType SVG style attributes for paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");

    const bytes = try test_font.buildSvgStyleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(31, 26);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(50, 24);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < red_sample.a);

    const untransformed_style_origin = target.at(20, 20);
    try std.testing.expectEqual(@as(u8, 0), untransformed_style_origin.a);

    const hidden_class = target.at(16, 51);
    try std.testing.expectEqual(@as(u8, 0), hidden_class.a);

    const id_style = target.at(44, 52);
    try std.testing.expect(id_style.g > 0);
    try std.testing.expectEqual(@as(u8, 0), id_style.r);
    try std.testing.expect(id_style.a > 0 and id_style.a < 255);

    const element_style = target.at(24, 54);
    try std.testing.expect(element_style.b > 0);
    try std.testing.expectEqual(@as(u8, 0), element_style.r);
    try std.testing.expect(element_style.a > 0 and element_style.a < 255);

    const current_color_fill = target.at(53, 53);
    try std.testing.expect(current_color_fill.b > 0);
    try std.testing.expectEqual(@as(u8, 0), current_color_fill.r);
    try std.testing.expect(current_color_fill.a > 0 and current_color_fill.a < 255);

    const current_color_stroke = target.at(53, 57);
    try std.testing.expect(current_color_stroke.b > 0);
    try std.testing.expectEqual(@as(u8, 0), current_color_stroke.r);
    try std.testing.expect(current_color_stroke.a > 0 and current_color_stroke.a < 255);

    const cyan_keyword = target.at(14, 14);
    try std.testing.expect(cyan_keyword.g > 0);
    try std.testing.expect(cyan_keyword.b > 0);
    try std.testing.expectEqual(@as(u8, 0), cyan_keyword.r);

    const yellow_keyword = target.at(18, 14);
    try std.testing.expect(yellow_keyword.r > 0);
    try std.testing.expect(yellow_keyword.g > 0);
    try std.testing.expectEqual(@as(u8, 0), yellow_keyword.b);

    const magenta_keyword = target.at(23, 14);
    try std.testing.expect(magenta_keyword.r > 0);
    try std.testing.expect(magenta_keyword.b > 0);
    try std.testing.expectEqual(@as(u8, 0), magenta_keyword.g);

    const transparent_keyword = target.at(28, 14);
    try std.testing.expectEqual(@as(u8, 0), transparent_keyword.a);
}
