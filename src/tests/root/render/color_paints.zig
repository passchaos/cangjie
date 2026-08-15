//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const Font = support.Font;
const ColorPaint = support.ColorPaint;
const ColorAffine = support.ColorAffine;
const GlyphId = support.GlyphId;
const ColorRenderTarget = support.ColorRenderTarget;
const Rgba = support.Rgba;
const Rasterizer = support.Rasterizer;
const testing = support.testing;
const colorRenderTargetPixelDifference = support.colorRenderTargetPixelDifference;

test "reads COLR layers and CPAL palette colors" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const palettes = try font.colorPalettes(allocator);
    defer allocator.free(palettes);
    try std.testing.expectEqual(@as(usize, 1), palettes.len);
    try std.testing.expectEqual(@as(u16, 0), palettes[0].first_color_index);
    try std.testing.expectEqual(@as(u16, 2), palettes[0].color_count);
    try std.testing.expectEqual(@as(u32, 0), palettes[0].palette_type);
    try std.testing.expectEqual(@as(?u16, null), palettes[0].label_name_id);

    const entry_labels = try font.paletteEntryLabels(allocator);
    defer allocator.free(entry_labels);
    try std.testing.expectEqual(@as(usize, 2), entry_labels.len);
    try std.testing.expectEqual(@as(?u16, null), entry_labels[0]);
    try std.testing.expectEqual(@as(?u16, null), entry_labels[1]);

    const layers = try font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 2), layers.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 0), layers[0].palette_index);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[1].glyph_id);
    try std.testing.expectEqual(@as(u16, 1), layers[1].palette_index);

    const palette_colors = try font.paletteColors(allocator, 0);
    defer allocator.free(palette_colors);
    try std.testing.expectEqual(@as(usize, 2), palette_colors.len);
    try std.testing.expectEqual(@as(u8, 255), palette_colors[0].red);
    try std.testing.expectEqual(@as(u8, 0), palette_colors[0].green);
    try std.testing.expectEqual(@as(u8, 0), palette_colors[0].blue);
    try std.testing.expectEqual(@as(u8, 255), palette_colors[1].blue);
    const missing_palette_colors = try font.paletteColors(allocator, 1);
    defer allocator.free(missing_palette_colors);
    try std.testing.expectEqual(@as(usize, 0), missing_palette_colors.len);

    const red = (try font.paletteColor(0, layers[0].palette_index)).?;
    try std.testing.expectEqual(@as(u8, 255), red.red);
    try std.testing.expectEqual(@as(u8, 0), red.green);
    try std.testing.expectEqual(@as(u8, 0), red.blue);
    try std.testing.expectEqual(@as(u8, 255), red.alpha);

    const blue = (try font.paletteColor(0, layers[1].palette_index)).?;
    try std.testing.expectEqual(@as(u8, 0), blue.red);
    try std.testing.expectEqual(@as(u8, 0), blue.green);
    try std.testing.expectEqual(@as(u8, 255), blue.blue);
    try std.testing.expectEqual(@as(u8, 255), blue.alpha);
    try std.testing.expect(try font.paletteColor(1, 0) == null);

    const missing_layers = try font.colorLayers(allocator, 2);
    defer allocator.free(missing_layers);
    try std.testing.expectEqual(@as(usize, 0), missing_layers.len);
}

test "reads COLR v1 PaintSolid metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .solid => |solid| {
            try std.testing.expectEqual(@as(u16, 0), solid.palette_index);
            try std.testing.expectApproxEqAbs(@as(f32, 0.5), solid.alpha, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(try font.colorPaint(0) == null);
}

test "renders COLR v1 PaintSolid glyph into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    var translucent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.a < 255) translucent_pixels += 1;
    }

    try std.testing.expect(red_pixels > 10);
    try std.testing.expect(translucent_pixels > 0);
}

test "reads and renders COLR v1 PaintGlyph with nested PaintSolid" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1GlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| {
            try std.testing.expectEqual(@as(GlyphId, 1), glyph_paint.glyph_id);
            switch (glyph_paint.brush) {
                .solid => |solid| {
                    try std.testing.expectEqual(@as(u16, 0), solid.palette_index);
                    try std.testing.expectApproxEqAbs(@as(f32, 1.0), solid.alpha, 0.001);
                },
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
    }
    try std.testing.expect(red_pixels > 10);
}

test "reads and renders COLR v1 PaintColrLayers" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1LayersTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .layers => |layers| {
            try std.testing.expectEqual(@as(u8, 2), layers.layer_count);
            try std.testing.expectEqual(@as(u32, 0), layers.first_layer_index);
        },
        else => return error.TestUnexpectedResult,
    }
    const first_layer = (try font.colorPaintLayer(0)).?;
    switch (first_layer) {
        .glyph => |glyph_paint| {
            try std.testing.expectEqual(@as(GlyphId, 1), glyph_paint.glyph_id);
            switch (glyph_paint.brush) {
                .solid => |solid| try std.testing.expectEqual(@as(u16, 0), solid.palette_index),
                else => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

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

test "reads and renders COLR v1 PaintLinearGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1LinearGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    const clip = (try font.colorClipBox(1)).?;
    try std.testing.expectEqual(@as(f32, 0), clip.x_min);
    try std.testing.expectEqual(@as(f32, 0), clip.y_min);
    try std.testing.expectEqual(@as(f32, 700), clip.x_max);
    try std.testing.expectEqual(@as(f32, 125), clip.y_max);
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .linear_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 0), gradient.p0.x);
                try std.testing.expectEqual(@as(f32, 700), gradient.p1.x);
                try std.testing.expectEqual(ColorPaint.Extend.pad, gradient.color_line.extend);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
                const first = gradient.color_line.stop(0).?;
                const last = gradient.color_line.stop(1).?;
                try std.testing.expectEqual(@as(u16, 0), first.palette_index);
                try std.testing.expectEqual(@as(f32, 0), first.offset);
                try std.testing.expectEqual(@as(u16, 1), last.palette_index);
                try std.testing.expectEqual(@as(f32, 1), last.offset);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_dominant: usize = 0;
    var blue_dominant: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > pixel.b) red_dominant += 1;
        if (pixel.b > pixel.r) blue_dominant += 1;
    }
    try std.testing.expect(red_dominant > 0);
    try std.testing.expect(blue_dominant > 0);
    // Font-space y=125 maps to pixel y=29 at this size/baseline. The upper
    // half of the triangle would be covered without the COLR ClipBox.
    try std.testing.expectEqual(@as(u8, 0), target.at(20, 27).a);
    try std.testing.expect(target.at(16, 31).a > 0);
}

test "COLR v1 variable ClipBox resolves and clips at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1VariableClipTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_clip = (try font.colorClipBox(1)).?;
    try std.testing.expectEqual(@as(f32, 100), default_clip.x_min);
    try std.testing.expectEqual(@as(f32, 100), default_clip.y_min);
    try std.testing.expectEqual(@as(f32, 900), default_clip.x_max);
    try std.testing.expectEqual(@as(f32, 900), default_clip.y_max);

    // Logical indexes 1/2 map to a +500 row, while indexes 3/4 map
    // to -500 and exercise DeltaSetIndexMap's required final-entry reuse.
    const varied_clip = (try font.colorClipBoxAtCoords(1, &.{0.4})).?;
    // 0.4 is quantized to the F2Dot14 location 0.4000244140625 before
    // ItemVariationStore evaluation, matching Fontations/Skrifa.
    try std.testing.expectApproxEqAbs(@as(f32, 300.0122), varied_clip.x_min, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 300.0122), varied_clip.y_min, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 699.9878), varied_clip.x_max, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 699.9878), varied_clip.y_max, 0.0001);
    try std.testing.expectError(error.BadSfnt, font.colorClipBoxAtCoords(1, &.{1.01}));

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.4});

    var default_opaque: usize = 0;
    var varied_opaque: usize = 0;
    for (default_target.pixels, varied_target.pixels) |default_pixel, varied_pixel| {
        if (default_pixel.a != 0) default_opaque += 1;
        if (varied_pixel.a != 0) varied_opaque += 1;
    }
    try std.testing.expect(default_opaque > 0);
    try std.testing.expect(varied_opaque < default_opaque);
}

test "COLR v1 variable paints resolve and render at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1VariablePaintTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_paint = (try font.colorPaint(1)).?;
    const varied_paint = (try font.colorPaintAtCoords(1, &.{0.5})).?;
    const default_alpha = switch (default_paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .solid => |solid| solid.alpha,
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    };
    const varied_alpha = switch (varied_paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .solid => |solid| solid.alpha,
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(f32, 1), default_alpha);
    try std.testing.expectEqual(@as(f32, 0.5), varied_alpha);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.5});

    var default_max_alpha: u8 = 0;
    var varied_max_alpha: u8 = 0;
    for (default_target.pixels, varied_target.pixels) |default_pixel, varied_pixel| {
        default_max_alpha = @max(default_max_alpha, default_pixel.a);
        varied_max_alpha = @max(varied_max_alpha, varied_pixel.a);
    }
    try std.testing.expect(default_max_alpha > 0);
    try std.testing.expect(varied_max_alpha > 0);
    try std.testing.expect(varied_max_alpha < default_max_alpha);
}

test "COLR v1 variable gradients resolve geometry and stops" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const linear_bytes = try test_font.buildColorV1VariableLinearGradientTtf(allocator);
    defer allocator.free(linear_bytes);
    var linear_font = try Font.parse(allocator, linear_bytes);
    defer linear_font.deinit();
    const linear = (try linear_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.linear_gradient;
    try std.testing.expectEqual(@as(f32, 100), linear.p0.x);
    try std.testing.expectEqual(@as(f32, 600), linear.p1.x);
    const linear_stops = try linear_font.colorStopsAtCoords(allocator, linear.color_line, &.{0.5});
    defer allocator.free(linear_stops);
    try std.testing.expectEqual(@as(usize, 2), linear_stops.len);
    try std.testing.expectEqual(@as(f32, 0.25), linear_stops[0].offset);
    try std.testing.expectEqual(@as(u16, 1), linear_stops[0].palette_index);
    try std.testing.expectEqual(@as(f32, 0.75), linear_stops[1].offset);
    try std.testing.expectEqual(@as(u16, 0), linear_stops[1].palette_index);
    try std.testing.expectEqual(@as(f32, 0.5), linear_stops[1].alpha);

    const radial_bytes = try test_font.buildColorV1VariableRadialGradientTtf(allocator);
    defer allocator.free(radial_bytes);
    var radial_font = try Font.parse(allocator, radial_bytes);
    defer radial_font.deinit();
    const radial = (try radial_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.radial_gradient;
    try std.testing.expectEqual(@as(f32, 100), radial.r0);
    try std.testing.expectEqual(@as(f32, 250), radial.r1);

    const sweep_bytes = try test_font.buildColorV1VariableSweepGradientTtf(allocator);
    defer allocator.free(sweep_bytes);
    var sweep_font = try Font.parse(allocator, sweep_bytes);
    defer sweep_font.deinit();
    const sweep = (try sweep_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.sweep_gradient;
    try std.testing.expectEqual(@as(f32, 450), sweep.center.x);
    try std.testing.expectEqual(@as(f32, 0), sweep.center.y);
    try std.testing.expectEqual(@as(f32, 45), sweep.start_angle);
    try std.testing.expectEqual(@as(f32, 315), sweep.end_angle);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &linear_font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &linear_font, 1, 24, 8, 32, 0, &.{0.5});
    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "COLR v1 variable transforms affect geometry and brush space" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1VariableTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_transform = (try font.colorPaint(1)).?.transform.affine;
    const varied_transform = (try font.colorPaintAtCoords(1, &.{0.5})).?.transform.affine;
    try std.testing.expectEqual(ColorAffine.identity, default_transform);
    try std.testing.expectEqual(@as(f32, 100), varied_transform.dx);
    try std.testing.expectEqual(@as(f32, 50), varied_transform.dy);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.5});
    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "COLR v1 nested PaintGlyph transforms match live Skrifa matrices" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const first = (try font.colorPaint(207)).?.clip_glyph;
    try std.testing.expectEqual(@as(GlyphId, 7), first.glyph_id);
    const outer = (try font.colorPaintChildAtCoords(first.child, &.{})).transform;
    try std.testing.expectEqual(ColorAffine.identity, outer.affine);
    const second = (try font.colorPaintChildAtCoords(outer.child, &.{})).clip_glyph;
    try std.testing.expectEqual(@as(GlyphId, 6), second.glyph_id);
    const rotation = (try font.colorPaintChildAtCoords(second.child, &.{})).transform.affine;

    // Skrifa's current source resolves the same nested PaintRotate to this
    // matrix before its fill_glyph optimization.
    try std.testing.expectApproxEqAbs(@as(f32, 0.9848152), rotation.xx, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.17360622), rotation.yx, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.17360622), rotation.xy, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9848152), rotation.yy, 0.000001);

    var identity_target = try ColorRenderTarget.init(allocator, 256, 256);
    defer identity_target.deinit();
    var rotated_target = try ColorRenderTarget.init(allocator, 256, 256);
    defer rotated_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&identity_target, &font, 205, 200, 20, 220, 0);
    try rasterizer.renderColorGlyph(&rotated_target, &font, 207, 200, 20, 220, 0);
    try std.testing.expect(colorRenderTargetPixelDifference(&identity_target, &rotated_target) > 0);
}

test "COLR v1 foreground palette sentinel renders current color" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1ForegroundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var white_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a != 0 and pixel.r == pixel.g and pixel.g == pixel.b and pixel.r > 0) white_pixels += 1;
    }
    try std.testing.expect(white_pixels > 10);
}

test "reads and renders COLR v1 PaintRadialGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1RadialGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .radial_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 350), gradient.c0.x);
                try std.testing.expectEqual(@as(f32, 0), gradient.r0);
                try std.testing.expectEqual(@as(f32, 350), gradient.r1);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    const center = target.at(16, 30);
    const edge = target.at(9, 31);
    try std.testing.expect(center.r > center.b);
    try std.testing.expect(edge.b > edge.r);
}

test "reads and renders COLR v1 PaintSweepGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1SweepGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .sweep_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 350), gradient.center.x);
                try std.testing.expectEqual(@as(f32, 0), gradient.start_angle);
                try std.testing.expectEqual(@as(f32, 360), gradient.end_angle);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    const upper = target.at(17, 29);
    const lower = target.at(17, 30);
    try std.testing.expect(upper.r > upper.b);
    try std.testing.expect(lower.b > lower.r);
}

test "rejects COLR v1 ClipList offsets that alias records" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1InvalidClipListTtf(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "accepts COLR v1 exact shared paint payloads" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1RecursivePaintAliasTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
}

test "accepts fonts containing isolated COLR v1 PaintColrGlyph cycles" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildColorV1IndirectPaintColrGlyphCycleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    try std.testing.expectEqual(@as(GlyphId, 2), paint.colr_glyph.glyph_id);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try std.testing.expectError(error.BadSfnt, rasterizer.renderColorGlyph(&target, &font, 1, 20, 4, 24, 0));
}

test "COLR v1 PaintColrGlyph traverses referenced paints and clips" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildColorV1PaintColrGlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(0)).?;
    try std.testing.expectEqual(@as(GlyphId, 1), paint.colr_glyph.glyph_id);

    var referenced = try ColorRenderTarget.init(allocator, 48, 48);
    defer referenced.deinit();
    var caller = try ColorRenderTarget.init(allocator, 48, 48);
    defer caller.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&referenced, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyph(&caller, &font, 0, 24, 8, 32, 0);

    try std.testing.expectEqualSlices(Rgba, referenced.pixels, caller.pixels);
    // The referenced glyph's ClipBox starts at y=350 font units, so the lower
    // triangle tip is removed in both direct and PaintColrGlyph traversal.
    try std.testing.expectEqual(@as(u8, 0), caller.at(16, 31).a);
}

test "COLR v1 PaintColrGlyph matches live Skrifa referenced clip traversal" {
    const allocator = std.testing.allocator;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(166)).?;
    try std.testing.expectEqual(@as(GlyphId, 95), paint.colr_glyph.glyph_id);
    const referenced_clip = (try font.colorClipBox(95)).?;
    try std.testing.expectEqual(@as(f32, 0), referenced_clip.x_min);
    try std.testing.expectEqual(@as(f32, 0), referenced_clip.y_min);
    try std.testing.expectEqual(@as(f32, 1000), referenced_clip.x_max);
    try std.testing.expectEqual(@as(f32, 1000), referenced_clip.y_max);

    var referenced = try ColorRenderTarget.init(allocator, 256, 256);
    defer referenced.deinit();
    var caller = try ColorRenderTarget.init(allocator, 256, 256);
    defer caller.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&referenced, &font, 95, 200, 20, 220, 0);
    try rasterizer.renderColorGlyph(&caller, &font, 166, 200, 20, 220, 0);
    // Skrifa traversal first applies glyph 166's inset clip, then glyph 95's
    // own 0..1000 clip around the referenced radial paint.
    try std.testing.expect(colorRenderTargetPixelDifference(&referenced, &caller) > 0);
}

test "COLR v1 PaintComposite renders all current modes" {
    const allocator = std.testing.allocator;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const expected_overlap = [_]Rgba{
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 255, .b = 233, .a = 255 },
        .{ .r = 255, .g = 247, .b = 232, .a = 255 },
        .{ .r = 255, .g = 240, .b = 2, .a = 255 },
        .{ .r = 104, .g = 199, .b = 1, .a = 255 },
        .{ .r = 255, .g = 220, .b = 232, .a = 255 },
        .{ .r = 255, .g = 255, .b = 11, .a = 255 },
        .{ .r = 255, .g = 210, .b = 0, .a = 255 },
        .{ .r = 208, .g = 240, .b = 209, .a = 255 },
        .{ .r = 255, .g = 229, .b = 3, .a = 255 },
        .{ .r = 151, .g = 21, .b = 231, .a = 255 },
        .{ .r = 151, .g = 76, .b = 231, .a = 255 },
        .{ .r = 104, .g = 172, .b = 1, .a = 255 },
        .{ .r = 145, .g = 227, .b = 255, .a = 255 },
        .{ .r = 230, .g = 213, .b = 102, .a = 255 },
        .{ .r = 145, .g = 227, .b = 255, .a = 255 },
        .{ .r = 217, .g = 187, .b = 0, .a = 255 },
    };

    for (expected_overlap, 0..) |expected, raw_mode| {
        const glyph_id: GlyphId = @intCast(120 + raw_mode);
        var target = try ColorRenderTarget.init(allocator, 256, 256);
        defer target.deinit();
        var rasterizer = Rasterizer.init(allocator);
        try rasterizer.renderColorGlyph(&target, &font, glyph_id, 200, 20, 220, 0);
        try std.testing.expectEqual(expected, target.at(120, 120));
    }
}
