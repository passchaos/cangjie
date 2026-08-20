//! Shared scanline value types used by direct and prepared accumulation.

const std = @import("std");
const glyph_mod = @import("../glyph.zig");

pub const Point = glyph_mod.Point;

pub const Target = struct {
    width: u32,
    height: u32,
    pixels: []u8,
};

pub const CoveredSpan = struct {
    min_x: i32,
    max_x: i32,
};

pub inline fn blendUnchecked(target: Target, x: i32, y: i32, coverage: u8) void {
    const index = @as(usize, @intCast(y)) * target.width +
        @as(usize, @intCast(x));
    if (coverage == 255) {
        target.pixels[index] = 255;
        return;
    }
    target.pixels[index] = @max(target.pixels[index], coverage);
}

pub fn coverSpanFinite(coverage_counts: []u8, min_x: i32, max_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32) ?CoveredSpan {
    std.debug.assert(std.math.isFinite(start_f) and std.math.isFinite(end_f));
    const start64: f64 = start_f;
    const end64: f64 = end_f;
    const min64: f64 = @floatFromInt(min_x);
    const max64: f64 = @floatFromInt(max_x);
    if (end64 <= start64 or end64 <= min64 or start64 >= max64 + 1.0) return null;
    const x_start = if (start64 <= min64) min_x else @as(i32, @intFromFloat(@floor(start64)));
    // Pixel samples lie strictly inside [x, x + 1), so ceil(end) is empty.
    const x_end = if (end64 >= max64 + 1.0) max_x else @as(i32, @intFromFloat(@ceil(end64))) - 1;
    const full_start = if (start64 <= min64) min_x else @as(i32, @intFromFloat(@ceil(start64)));
    const full_end = if (end64 >= max64 + 1.0) max_x else @as(i32, @intFromFloat(@floor(end64))) - 1;
    const full_coverage: u8 = @intCast(sample_offsets.len);
    var x = x_start;
    if (full_start <= full_end) {
        while (x < full_start) : (x += 1) coverPartialPixelDispatch(coverage_counts, min_x, sample_offsets, start_f, end_f, x);
        while (x <= full_end) : (x += 1) coverage_counts[@intCast(x - min_x)] += full_coverage;
    }
    while (x <= x_end) : (x += 1) coverPartialPixelDispatch(coverage_counts, min_x, sample_offsets, start_f, end_f, x);
    return .{ .min_x = x_start, .max_x = x_end };
}

inline fn coverPartialPixelDispatch(coverage_counts: []u8, min_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32, x: i32) void {
    if (sample_offsets.len == 4) return coverPartialPixel4(coverage_counts, min_x, start_f, end_f, x);
    coverPartialPixel(coverage_counts, min_x, sample_offsets, start_f, end_f, x);
}

pub inline fn coverPartialPixel4(coverage_counts: []u8, min_x: i32, start_f: f32, end_f: f32, x: i32) void {
    const base: f32 = @floatFromInt(x);
    var count: u8 = 0;
    count += @intFromBool(base + 0.125 >= start_f and base + 0.125 < end_f);
    count += @intFromBool(base + 0.375 >= start_f and base + 0.375 < end_f);
    count += @intFromBool(base + 0.625 >= start_f and base + 0.625 < end_f);
    count += @intFromBool(base + 0.875 >= start_f and base + 0.875 < end_f);
    coverage_counts[@intCast(x - min_x)] += count;
}

pub fn coverPartialPixel(coverage_counts: []u8, min_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32, x: i32) void {
    for (sample_offsets) |sample_offset| {
        const px = @as(f32, @floatFromInt(x)) + sample_offset;
        if (px >= start_f and px < end_f) coverage_counts[@intCast(x - min_x)] += 1;
    }
}
