//! Reusable grayscale target storage and renderer pixel records.

const std = @import("std");

pub const RenderTarget = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
    ) !RenderTarget {
        const pixels = try allocator.alloc(u8, @as(usize, width) * height);
        @memset(pixels, 0);
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .pixels = pixels,
        };
    }

    pub fn deinit(self: *RenderTarget) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn clear(self: *RenderTarget, value: u8) void {
        @memset(self.pixels, value);
    }

    pub fn at(self: *const RenderTarget, x: u32, y: u32) u8 {
        return self.pixels[@as(usize, y) * self.width + x];
    }
};

/// Blend one coverage sample into a grayscale target.
///
/// This is a module operation rather than part of the public target method set:
/// raster algorithms need it, while renderer-facing callers only need target
/// allocation, clearing, and pixel inspection.
pub fn blendCoverage(
    target: *RenderTarget,
    x: i32,
    y: i32,
    coverage: u8,
) void {
    if (x < 0 or y < 0) return;
    const ux: u32 = @intCast(x);
    const uy: u32 = @intCast(y);
    if (ux >= target.width or uy >= target.height) return;
    const index = @as(usize, uy) * target.width + ux;
    target.pixels[index] = @max(target.pixels[index], coverage);
}

pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};
