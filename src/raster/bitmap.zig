//! Bounded bilinear sampling of straight-alpha RGBA bitmap glyphs.

const std = @import("std");
const composite = @import("composite.zig");
const Rgba = @import("targets.zig").Rgba;

pub fn blendScaledMask8(
    target: []Rgba,
    target_width: u32,
    target_height: u32,
    source: []const u8,
    source_width: usize,
    source_height: usize,
    left: f32,
    top: f32,
    scale: f32,
) void {
    std.debug.assert(source.len == source_width * source_height);
    std.debug.assert(target.len >= @as(usize, target_width) * target_height);
    if (source_width == 0 or source_height == 0 or scale <= 0) return;
    const right = left + @as(f32, @floatFromInt(source_width)) * scale;
    const bottom = top + @as(f32, @floatFromInt(source_height)) * scale;
    if (!std.math.isFinite(left) or !std.math.isFinite(top) or
        !std.math.isFinite(right) or !std.math.isFinite(bottom)) return;
    const start_x_f = @max(@floor(left), 0.0);
    const start_y_f = @max(@floor(top), 0.0);
    const end_x_f = @min(@ceil(right), @as(f32, @floatFromInt(target_width)));
    const end_y_f = @min(@ceil(bottom), @as(f32, @floatFromInt(target_height)));
    if (end_x_f <= start_x_f or end_y_f <= start_y_f) return;
    const start_x: usize = @intFromFloat(start_x_f);
    const start_y: usize = @intFromFloat(start_y_f);
    const end_x: usize = @intFromFloat(end_x_f);
    const end_y: usize = @intFromFloat(end_y_f);
    const inverse_scale = 1.0 / scale;
    for (start_y..end_y) |destination_y| {
        const source_y =
            ((@as(f32, @floatFromInt(destination_y)) + 0.5 - top) *
                inverse_scale) - 0.5;
        const y0_float = @floor(source_y);
        const y_fraction = source_y - y0_float;
        const y0: i32 = @intFromFloat(y0_float);
        for (start_x..end_x) |destination_x| {
            const source_x =
                ((@as(f32, @floatFromInt(destination_x)) + 0.5 - left) *
                    inverse_scale) - 0.5;
            const x0_float = @floor(source_x);
            const x_fraction = source_x - x0_float;
            const x0: i32 = @intFromFloat(x0_float);
            const top_coverage = lerpPremultipliedByte(
                mask8At(source, source_width, source_height, x0, y0),
                mask8At(source, source_width, source_height, x0 + 1, y0),
                x_fraction,
            );
            const bottom_coverage = lerpPremultipliedByte(
                mask8At(source, source_width, source_height, x0, y0 + 1),
                mask8At(source, source_width, source_height, x0 + 1, y0 + 1),
                x_fraction,
            );
            const coverage = lerpPremultipliedByte(
                top_coverage,
                bottom_coverage,
                y_fraction,
            );
            composite.blendPixel(
                &target[destination_y * target_width + destination_x],
                .{ .r = coverage, .g = coverage, .b = coverage, .a = coverage },
            );
        }
    }
}

fn mask8At(
    source: []const u8,
    width: usize,
    height: usize,
    x: i32,
    y: i32,
) u8 {
    if (x < 0 or y < 0) return 0;
    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);
    if (ux >= width or uy >= height) return 0;
    return source[uy * width + ux];
}

pub fn blendScaledRgba8(
    target: []Rgba,
    target_width: u32,
    target_height: u32,
    source: []const u8,
    source_width: usize,
    source_height: usize,
    left: f32,
    top: f32,
    scale: f32,
) void {
    std.debug.assert(source.len == source_width * source_height * 4);
    std.debug.assert(target.len >= @as(usize, target_width) * target_height);
    if (source_width == 0 or source_height == 0 or scale <= 0) return;

    const right = left + @as(f32, @floatFromInt(source_width)) * scale;
    const bottom = top + @as(f32, @floatFromInt(source_height)) * scale;
    if (!std.math.isFinite(left) or
        !std.math.isFinite(top) or
        !std.math.isFinite(right) or
        !std.math.isFinite(bottom))
    {
        return;
    }

    // Clip in floating point before integer conversion. This both avoids work
    // outside the target and prevents absurd finite placements overflowing.
    const start_x_f = @max(@floor(left), 0.0);
    const start_y_f = @max(@floor(top), 0.0);
    const end_x_f = @min(
        @ceil(right),
        @as(f32, @floatFromInt(target_width)),
    );
    const end_y_f = @min(
        @ceil(bottom),
        @as(f32, @floatFromInt(target_height)),
    );
    if (end_x_f <= start_x_f or end_y_f <= start_y_f) return;

    const start_x: usize = @intFromFloat(start_x_f);
    const start_y: usize = @intFromFloat(start_y_f);
    const end_x: usize = @intFromFloat(end_x_f);
    const end_y: usize = @intFromFloat(end_y_f);
    const inverse_scale = 1.0 / scale;

    for (start_y..end_y) |destination_y| {
        const source_y =
            ((@as(f32, @floatFromInt(destination_y)) + 0.5 - top) *
                inverse_scale) - 0.5;
        const y0_float = @floor(source_y);
        const y_fraction = source_y - y0_float;
        const y0: i32 = @intFromFloat(y0_float);

        for (start_x..end_x) |destination_x| {
            const source_x =
                ((@as(f32, @floatFromInt(destination_x)) + 0.5 - left) *
                    inverse_scale) - 0.5;
            const x0_float = @floor(source_x);
            const x_fraction = source_x - x0_float;
            const x0: i32 = @intFromFloat(x0_float);

            // Interpolate premultiplied samples. Straight-RGB interpolation
            // would pull arbitrary RGB through transparent texels and produce
            // dark or colored fringes around emoji silhouettes. An implicit
            // transparent border gives fractional placement correct coverage.
            const top_sample = lerpPremultipliedColor(
                premultipliedRgba8At(
                    source,
                    source_width,
                    source_height,
                    x0,
                    y0,
                ),
                premultipliedRgba8At(
                    source,
                    source_width,
                    source_height,
                    x0 + 1,
                    y0,
                ),
                x_fraction,
            );
            const bottom_sample = lerpPremultipliedColor(
                premultipliedRgba8At(
                    source,
                    source_width,
                    source_height,
                    x0,
                    y0 + 1,
                ),
                premultipliedRgba8At(
                    source,
                    source_width,
                    source_height,
                    x0 + 1,
                    y0 + 1,
                ),
                x_fraction,
            );
            const sample = lerpPremultipliedColor(
                top_sample,
                bottom_sample,
                y_fraction,
            );
            composite.blendPixel(
                &target[
                    destination_y * @as(usize, target_width) +
                        destination_x
                ],
                sample,
            );
        }
    }
}

fn premultipliedRgba8At(
    source: []const u8,
    width: usize,
    height: usize,
    x: i32,
    y: i32,
) Rgba {
    if (x < 0 or y < 0) return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);
    if (ux >= width or uy >= height) {
        return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    }
    const rgba = source[(uy * width + ux) * 4 ..][0..4];
    const alpha = @as(f32, @floatFromInt(rgba[3])) / 255.0;
    return .{
        .r = lerpPremultipliedByte(0, @floatFromInt(rgba[0]), alpha),
        .g = lerpPremultipliedByte(0, @floatFromInt(rgba[1]), alpha),
        .b = lerpPremultipliedByte(0, @floatFromInt(rgba[2]), alpha),
        .a = rgba[3],
    };
}

fn lerpPremultipliedColor(a: Rgba, b: Rgba, t: f32) Rgba {
    return .{
        .r = lerpPremultipliedByte(
            @floatFromInt(a.r),
            @floatFromInt(b.r),
            t,
        ),
        .g = lerpPremultipliedByte(
            @floatFromInt(a.g),
            @floatFromInt(b.g),
            t,
        ),
        .b = lerpPremultipliedByte(
            @floatFromInt(a.b),
            @floatFromInt(b.b),
            t,
        ),
        .a = lerpPremultipliedByte(
            @floatFromInt(a.a),
            @floatFromInt(b.a),
            t,
        ),
    };
}

fn lerpPremultipliedByte(a: f32, b: f32, t: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(a + (b - a) * t, 0, 255)));
}

test "fractional bitmap placement preserves premultiplied transparent edges" {
    // The transparent texel deliberately carries blue RGB. Premultiplied
    // interpolation must not leak it into the visible red silhouette.
    const source = [_]u8{
        255, 0, 0,   255,
        0,   0, 255, 0,
    };
    var target = [_]Rgba{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 8;
    blendScaledRgba8(
        &target,
        4,
        2,
        &source,
        2,
        1,
        0.5,
        0.5,
        1,
    );
    var saw_coverage = false;
    for (target) |pixel| {
        if (pixel.a == 0) continue;
        saw_coverage = true;
        try std.testing.expect(pixel.r != 0);
        try std.testing.expectEqual(@as(u8, 0), pixel.b);
    }
    try std.testing.expect(saw_coverage);
}
