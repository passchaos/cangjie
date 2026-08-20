//! Dense, target-independent prepared coverage storage.

const std = @import("std");
const scanline = @import("../scanline.zig");

pub const Cache = struct {
    pixels: []u8 = &.{},
    rows: []Row = &.{},
    min_x: i32 = 0,
    min_y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        if (self.pixels.len != 0) {
            allocator.free(self.pixels);
            allocator.free(self.rows);
        }
        self.* = undefined;
    }
};

pub const Row = struct {
    /// Inclusive x indexes relative to `Cache.min_x`. Empty rows use start > end.
    start: u32 = 1,
    end: u32 = 0,
};

pub fn build(allocator: std.mem.Allocator, bounds: ?scanline.Bounds, rows: anytype, points: []const scanline.WindingIntersection, min_sample_y: i32) !Cache {
    const geometry = bounds orelse return .{};
    if (rows.len == 0) return .{};
    const width_i64 = @as(i64, geometry.max_x) - geometry.min_x + 1;
    const height_i64 = @as(i64, geometry.max_y) - geometry.min_y + 1;
    if (width_i64 <= 0 or height_i64 <= 0 or width_i64 > 65_536 or height_i64 > 65_536) return .{};
    const width: usize = @intCast(width_i64);
    const height: usize = @intCast(height_i64);
    if (width > std.math.maxInt(usize) / height or width * height > 16 * 1024 * 1024) return .{};
    const pixels = try allocator.alloc(u8, width * height);
    errdefer allocator.free(pixels);
    @memset(pixels, 0);
    const cached_rows = try allocator.alloc(Row, height);
    errdefer allocator.free(cached_rows);
    const differences = try allocator.alloc(i16, width + 1);
    defer allocator.free(differences);
    @memset(differences, 0);
    for (0..height) |row_index| {
        const y = geometry.min_y + @as(i32, @intCast(row_index));
        var dirty_min = geometry.max_x;
        var dirty_max = geometry.min_x;
        var dirty = false;
        for (0..4) |sample_index| {
            const record_index_i64 = (@as(i64, y) - min_sample_y) * 4 + @as(i64, @intCast(sample_index));
            if (record_index_i64 < 0 or record_index_i64 >= rows.len) continue;
            const record = rows[@intCast(record_index_i64)];
            const start: usize = record.start;
            const intersections = points[start .. start + record.len];
            var winding: i32 = 0;
            var previous: ?f32 = null;
            var index: usize = 0;
            while (index < intersections.len) {
                const current = intersections[index].x;
                if (previous) |span_start| {
                    if (winding != 0) if (addSpan(differences, geometry.min_x, geometry.max_x, span_start, current)) |span| {
                        dirty = true;
                        dirty_min = @min(dirty_min, span[0]);
                        dirty_max = @max(dirty_max, span[1]);
                    };
                }
                var delta: i32 = 0;
                while (index < intersections.len and @abs(intersections[index].x - current) <= 0.000001) : (index += 1) delta += intersections[index].delta;
                winding += delta;
                previous = current;
            }
        }
        if (!dirty) {
            cached_rows[row_index] = .{};
            continue;
        }
        var running: i16 = 0;
        var x = dirty_min;
        while (x <= dirty_max) : (x += 1) {
            running += differences[@intCast(x - geometry.min_x)];
            std.debug.assert(running >= 0 and running <= 16);
            pixels[row_index * width + @as(usize, @intCast(x - geometry.min_x))] = @intCast(running);
        }
        const first: usize = @intCast(dirty_min - geometry.min_x);
        const after: usize = @intCast(dirty_max - geometry.min_x + 1);
        @memset(differences[first .. after + 1], 0);
        cached_rows[row_index] = .{
            .start = @intCast(dirty_min - geometry.min_x),
            .end = @intCast(dirty_max - geometry.min_x),
        };
    }
    return .{
        .pixels = pixels,
        .rows = cached_rows,
        .min_x = geometry.min_x,
        .min_y = geometry.min_y,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

fn addSpan(differences: []i16, min_x: i32, max_x: i32, start_f: f32, end_f: f32) ?[2]i32 {
    if (end_f <= start_f or end_f <= @as(f32, @floatFromInt(min_x)) or start_f >= @as(f32, @floatFromInt(max_x)) + 1.0) return null;
    const clipped_start = @max(start_f, @as(f32, @floatFromInt(min_x)));
    const clipped_end = @min(end_f, @as(f32, @floatFromInt(max_x)) + 1.0);
    const x_start: i32 = @intFromFloat(@floor(clipped_start));
    const x_end: i32 = @min(max_x, @as(i32, @intFromFloat(@ceil(clipped_end))));
    const full_start: i32 = @intFromFloat(@ceil(clipped_start));
    const full_end = @as(i32, @intFromFloat(@floor(clipped_end))) - 1;
    var x = x_start;
    if (full_start <= full_end) {
        while (x < full_start) : (x += 1) addPartial(differences, min_x, start_f, end_f, x);
        addDifference(differences, min_x, full_start, full_end, 4);
        x = full_end + 1;
    }
    while (x <= x_end) : (x += 1) addPartial(differences, min_x, start_f, end_f, x);
    return .{ x_start, x_end };
}

fn addPartial(differences: []i16, min_x: i32, start: f32, end: f32, x: i32) void {
    const base: f32 = @floatFromInt(x);
    var count: i16 = 0;
    count += @intFromBool(base + 0.125 >= start and base + 0.125 < end);
    count += @intFromBool(base + 0.375 >= start and base + 0.375 < end);
    count += @intFromBool(base + 0.625 >= start and base + 0.625 < end);
    count += @intFromBool(base + 0.875 >= start and base + 0.875 < end);
    if (count != 0) addDifference(differences, min_x, x, x, count);
}

fn addDifference(differences: []i16, min_x: i32, start: i32, end: i32, count: i16) void {
    const first: usize = @intCast(start - min_x);
    const after: usize = @intCast(end - min_x + 1);
    differences[first] += count;
    differences[after] -= count;
}

test "coverage cache declines pathological bounds" {
    var cache = try build(
        std.testing.allocator,
        .{
            .min_x = std.math.minInt(i32),
            .min_y = 0,
            .max_x = std.math.maxInt(i32),
            .max_y = 1,
        },
        &[_]struct { start: u32, len: u32 }{.{ .start = 0, .len = 0 }},
        &.{},
        0,
    );
    defer cache.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), cache.pixels.len);
}
