//! End-to-end positioned-run geometry across grayscale and color rendering.

const std = @import("std");

const face_mod = @import("../../../font/face/root.zig");
const font_raster = @import("../../../font.zig").raster_backend;
const run_types = @import("../../../layout/types/runs.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const ColorRenderTarget = support.ColorRenderTarget;
const Font = support.Font;
const GlyphPosition = support.GlyphPosition;
const LayoutBuffer = support.LayoutBuffer;
const Rasterizer = support.Rasterizer;
const RenderTarget = support.RenderTarget;
const Rgba = support.Rgba;
const TextShaper = support.TextShaper;

test "grayscale run rendering honors two-dimensional shaping geometry" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    // The first glyph's positive y offset moves it up from the initial
    // baseline. The second starts after both advances, so it moves right and
    // down before applying its own negative offset.
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 18,
            .y_advance = 22,
            .x_offset = 3,
            .y_offset = 5,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 0,
            .x_offset = -2,
            .y_offset = -4,
        },
    };
    const run = run_types.initGlyphRun(&font, 16, &glyphs, &.{});
    var run_target = try RenderTarget.init(allocator, 72, 72);
    defer run_target.deinit();
    var reference = try RenderTarget.init(allocator, 72, 72);
    defer reference.deinit();
    var wrong_sign = try RenderTarget.init(allocator, 72, 72);
    defer wrong_sign.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;

    try rasterizer.renderRun(&run_target, run, 8, 28);
    var outline = try font_raster.glyphOutline(&font, allocator, 1);
    defer outline.deinit();
    try rasterizer.renderGlyph(
        &reference,
        &outline,
        11,
        23,
        16,
        font.units_per_em,
    );
    try rasterizer.renderGlyph(
        &reference,
        &outline,
        24,
        54,
        16,
        font.units_per_em,
    );
    try rasterizer.renderGlyph(
        &wrong_sign,
        &outline,
        11,
        33,
        16,
        font.units_per_em,
    );
    try rasterizer.renderGlyph(
        &wrong_sign,
        &outline,
        24,
        46,
        16,
        font.units_per_em,
    );

    try std.testing.expectEqualSlices(
        u8,
        reference.pixels,
        run_target.pixels,
    );
    try std.testing.expect(
        support.renderTargetPixelDifference(&run_target, &wrong_sign) > 0,
    );
}

test "vertical shaping flows through grayscale run rendering" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expect(run.glyphs[0].y_advance > 0);

    var run_target = try RenderTarget.init(allocator, 72, 88);
    defer run_target.deinit();
    var reference = try RenderTarget.init(allocator, 72, 88);
    defer reference.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderRun(&run_target, run, 12, 38);

    var pen_x: f32 = 12;
    var pen_y: f32 = 38;
    for (run.glyphs) |glyph| {
        var outline = try font_raster.glyphOutline(
            &font,
            allocator,
            glyph.glyph_id,
        );
        defer outline.deinit();
        try rasterizer.renderGlyph(
            &reference,
            &outline,
            pen_x + glyph.x_offset,
            pen_y - glyph.y_offset,
            run.font_size,
            font.units_per_em,
        );
        pen_x += glyph.x_advance;
        pen_y += glyph.y_advance;
    }
    try std.testing.expectEqualSlices(
        u8,
        reference.pixels,
        run_target.pixels,
    );
}

test "run rendering advances through two-dimensional inline objects" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 0,
            .codepoint = 0xfffc,
            .cluster = 0,
            .source_byte_len = 3,
            .x_advance = 13,
            .y_advance = 17,
            .flags = .{ .inline_object = true },
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 3,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 0,
            .x_offset = 2,
            .y_offset = 3,
        },
    };
    const run = run_types.initGlyphRun(&font, 16, &glyphs, &.{});
    var run_target = try RenderTarget.init(allocator, 64, 64);
    defer run_target.deinit();
    var reference = try RenderTarget.init(allocator, 64, 64);
    defer reference.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;

    try rasterizer.renderRun(&run_target, run, 7, 24);
    var outline = try font_raster.glyphOutline(&font, allocator, 1);
    defer outline.deinit();
    try rasterizer.renderGlyph(
        &reference,
        &outline,
        22,
        38,
        16,
        font.units_per_em,
    );
    try std.testing.expectEqualSlices(
        u8,
        reference.pixels,
        run_target.pixels,
    );
}

test "shaped text rendering applies cascade run y offsets" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyphs = [_]GlyphPosition{.{
        .glyph_id = 1,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 1,
        .x_advance = 0,
    }};
    const runs = [_]run_types.CascadeRun{.{
        .font = face_mod.backend.face(&font),
        .font_index = 0,
        .font_size = 16,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 7,
        .y_offset = 19,
    }};
    const shaped = run_types.ShapedText{
        .glyphs = &glyphs,
        .runs = &runs,
    };
    var shaped_target = try RenderTarget.init(allocator, 64, 64);
    defer shaped_target.deinit();
    var reference = try RenderTarget.init(allocator, 64, 64);
    defer reference.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;

    try rasterizer.renderShapedText(&shaped_target, shaped, 5, 20);
    var outline = try font_raster.glyphOutline(&font, allocator, 1);
    defer outline.deinit();
    try rasterizer.renderGlyph(
        &reference,
        &outline,
        12,
        39,
        16,
        font.units_per_em,
    );
    try std.testing.expectEqualSlices(
        u8,
        reference.pixels,
        shaped_target.pixels,
    );
}

test "color run rendering honors two-dimensional shaping geometry" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 17,
            .y_advance = 21,
            .x_offset = 2,
            .y_offset = 4,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 0,
            .x_offset = -1,
            .y_offset = -3,
        },
    };
    const run = run_types.initGlyphRun(&font, 16, &glyphs, &.{});
    var run_target = try ColorRenderTarget.init(allocator, 72, 72);
    defer run_target.deinit();
    var reference = try ColorRenderTarget.init(allocator, 72, 72);
    defer reference.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;

    try rasterizer.renderColorRun(&run_target, run, 8, 28, 0);
    try rasterizer.renderColorGlyph(
        &reference,
        &font,
        1,
        16,
        10,
        24,
        0,
    );
    try rasterizer.renderColorGlyph(
        &reference,
        &font,
        1,
        16,
        24,
        52,
        0,
    );
    try std.testing.expectEqualSlices(
        Rgba,
        reference.pixels,
        run_target.pixels,
    );

    // The fixture has vector outlines under its COLR layers. Ensure this gate
    // cannot pass because an accidentally unsupported color path drew nothing.
    var outline = try font_raster.glyphOutline(&font, allocator, 1);
    defer outline.deinit();
    try std.testing.expect(outline.commands.items.len != 0);
    var covered: usize = 0;
    for (run_target.pixels) |pixel| covered += @intFromBool(pixel.a != 0);
    try std.testing.expect(covered > 10);
}
