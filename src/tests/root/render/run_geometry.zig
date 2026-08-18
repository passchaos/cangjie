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

const CoverageBounds = struct {
    min_x: u32,
    min_y: u32,
    max_x: u32,
    max_y: u32,

    fn width(self: CoverageBounds) u32 {
        return self.max_x - self.min_x + 1;
    }

    fn height(self: CoverageBounds) u32 {
        return self.max_y - self.min_y + 1;
    }
};

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

test "grayscale run rotates only mixed vertical sideways glyphs" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 0x4e00,
            .cluster = 0,
            .source_byte_len = 3,
            .x_advance = 0,
            .y_advance = 24,
            .orientation = .upright,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 3,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 24,
            .orientation = .sideways,
        },
    };
    const run = run_types.initGlyphRun(&font, 20, &glyphs, &.{});
    var target = try RenderTarget.init(allocator, 72, 96);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderRun(&target, run, 12, 32);

    const upright = coverageBounds(&target, 0, 50) orelse
        return error.TestUnexpectedResult;
    const sideways = coverageBounds(&target, 50, target.height) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(upright.width() > upright.height());
    try std.testing.expect(sideways.height() > sideways.width());
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

test "color run rotates a sideways COLR glyph around its shaping origin" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph = [_]GlyphPosition{.{
        .glyph_id = 1,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 1,
        .x_advance = 0,
        .y_advance = 24,
        .orientation = .sideways,
    }};
    const run = run_types.initGlyphRun(&font, 20, &glyph, &.{});
    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderColorRun(&target, run, 12, 24, 0);

    const bounds = colorCoverageBounds(&target) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(bounds.height() > bounds.width());
}

fn coverageBounds(
    target: *const RenderTarget,
    min_y: u32,
    max_y: u32,
) ?CoverageBounds {
    var result: ?CoverageBounds = null;
    for (min_y..@min(max_y, target.height)) |y_value| {
        const y: u32 = @intCast(y_value);
        for (0..target.width) |x_value| {
            const x: u32 = @intCast(x_value);
            if (target.at(x, y) == 0) continue;
            includeCoverage(&result, x, y);
        }
    }
    return result;
}

fn colorCoverageBounds(
    target: *const ColorRenderTarget,
) ?CoverageBounds {
    var result: ?CoverageBounds = null;
    for (0..target.height) |y_value| {
        const y: u32 = @intCast(y_value);
        for (0..target.width) |x_value| {
            const x: u32 = @intCast(x_value);
            if (target.at(x, y).a == 0) continue;
            includeCoverage(&result, x, y);
        }
    }
    return result;
}

fn includeCoverage(result: *?CoverageBounds, x: u32, y: u32) void {
    if (result.*) |*bounds| {
        bounds.min_x = @min(bounds.min_x, x);
        bounds.min_y = @min(bounds.min_y, y);
        bounds.max_x = @max(bounds.max_x, x);
        bounds.max_y = @max(bounds.max_y, y);
    } else {
        result.* = .{
            .min_x = x,
            .min_y = y,
            .max_x = x,
            .max_y = y,
        };
    }
}
