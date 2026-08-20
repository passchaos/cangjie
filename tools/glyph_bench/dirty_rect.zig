//! Shared dirty-rectangle accounting for symmetric glyph benchmarks.

const std = @import("std");

pub const Bounds = struct {
    min_x: u32,
    min_y: u32,
    max_x: u32,
    max_y: u32,

    pub fn pixelCount(self: Bounds) usize {
        return @as(usize, self.max_x - self.min_x + 1) *
            @as(usize, self.max_y - self.min_y + 1);
    }
};

pub fn nonZeroBounds(pixels: []const u8, width: u32) ?Bounds {
    if (width == 0) return null;
    var result = Bounds{
        .min_x = std.math.maxInt(u32),
        .min_y = std.math.maxInt(u32),
        .max_x = 0,
        .max_y = 0,
    };
    var found = false;
    for (pixels, 0..) |pixel, index| {
        if (pixel == 0) continue;
        const x: u32 = @intCast(index % width);
        const y: u32 = @intCast(index / width);
        result.min_x = @min(result.min_x, x);
        result.min_y = @min(result.min_y, y);
        result.max_x = @max(result.max_x, x);
        result.max_y = @max(result.max_y, y);
        found = true;
    }
    return if (found) result else null;
}

pub fn clear(pixels: []u8, width: u32, bounds: ?Bounds) void {
    const value = bounds orelse return;
    var y = value.min_y;
    while (y <= value.max_y) : (y += 1) {
        const start = @as(usize, y) * width + value.min_x;
        const end = @as(usize, y) * width + value.max_x + 1;
        @memset(pixels[start..end], 0);
    }
}

pub fn checksum(pixels: []const u8, width: u32, bounds: ?Bounds) u64 {
    const value = bounds orelse return 0;
    var hasher = std.hash.Wyhash.init(0);
    var y = value.min_y;
    while (y <= value.max_y) : (y += 1) {
        const start = @as(usize, y) * width + value.min_x;
        const end = @as(usize, y) * width + value.max_x + 1;
        hasher.update(pixels[start..end]);
    }
    return hasher.final();
}

test "dirty rectangle clears and hashes only its clipped rows" {
    var pixels = [_]u8{0} ** 20;
    pixels[6] = 10;
    pixels[7] = 20;
    pixels[13] = 30;
    const bounds = nonZeroBounds(&pixels, 5).?;
    try std.testing.expectEqual(Bounds{ .min_x = 1, .min_y = 1, .max_x = 3, .max_y = 2 }, bounds);
    try std.testing.expectEqual(@as(usize, 6), bounds.pixelCount());
    try std.testing.expect(checksum(&pixels, 5, bounds) != 0);
    clear(&pixels, 5, bounds);
    try std.testing.expect(nonZeroBounds(&pixels, 5) == null);
}
