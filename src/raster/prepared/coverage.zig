//! Dense, target-independent prepared coverage storage.

const std = @import("std");
const scanline = @import("../scanline.zig");

pub const Cache = struct {
    /// Coverage bytes packed by each row's non-zero interval.
    pixels: []u8 = &.{},
    rows: []Row = &.{},
    min_x: i32 = 0,
    min_y: i32 = 0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        if (self.rows.len != 0) {
            if (self.pixels.len != 0) allocator.free(self.pixels);
            allocator.free(self.rows);
        }
        self.* = undefined;
    }
};

pub const Row = struct {
    /// Byte offset of `start` in `Cache.pixels`.
    data_start: u32 = 0,
    /// Inclusive x indexes relative to `Cache.min_x`. Empty rows use start > end.
    start: u16 = 1,
    end: u16 = 0,
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
    const cached_rows = try allocator.alloc(Row, height);
    errdefer allocator.free(cached_rows);
    const differences = try allocator.alloc(i16, width + 1);
    defer allocator.free(differences);
    @memset(differences, 0);
    var pixel_count: usize = 0;
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
                // Intersections are finite and sorted during preparation.
                while (index < intersections.len and
                    intersections[index].x - current <= 0.000001) : (index += 1)
                {
                    delta += intersections[index].delta;
                }
                winding += delta;
                previous = current;
            }
        }
        if (!dirty) {
            cached_rows[row_index] = .{};
            continue;
        }
        const data_start = pixel_count;
        var running: i16 = 0;
        var x = dirty_min;
        while (x <= dirty_max) : (x += 1) {
            const difference_index: usize = @intCast(x - geometry.min_x);
            running += differences[difference_index];
            differences[difference_index] = 0;
            std.debug.assert(running >= 0 and running <= 16);
            pixels[pixel_count] = @intCast(running);
            pixel_count += 1;
        }
        const after: usize = @intCast(dirty_max - geometry.min_x + 1);
        differences[after] = 0;
        cached_rows[row_index] = .{
            .start = @intCast(dirty_min - geometry.min_x),
            .end = @intCast(dirty_max - geometry.min_x),
            // The maximum packed size is the already-bounded dense rectangle,
            // so this cursor also fits the row's u32 offset representation.
            .data_start = @intCast(data_start),
        };
    }
    const packed_pixels = try allocator.realloc(pixels, pixel_count);
    return .{
        .pixels = packed_pixels,
        .rows = cached_rows,
        .min_x = geometry.min_x,
        .min_y = geometry.min_y,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

fn addSpan(differences: []i16, min_x: i32, max_x: i32, start_f: f32, end_f: f32) ?[2]i32 {
    // Match the direct scanner's quarter-sample representation while every
    // 1/8-pixel center is exactly representable. Raw prepared bounds can be
    // negative, so the fallback retains the defensive wide-coordinate path.
    if (min_x >= -1_048_576 and max_x <= 1_048_575) {
        return addSpanQuarterSamples(
            differences,
            min_x,
            max_x,
            start_f,
            end_f,
        );
    }
    return addSpanWide(differences, min_x, max_x, start_f, end_f);
}

fn addSpanQuarterSamples(differences: []i16, min_x: i32, max_x: i32, start_f: f32, end_f: f32) ?[2]i32 {
    const start64: f64 = start_f;
    const end64: f64 = end_f;
    const min64: f64 = @floatFromInt(min_x);
    const max64: f64 = @floatFromInt(max_x);
    if (end64 <= start64 or end64 <= min64 or start64 >= max64 + 1.0) return null;

    const min_sample = @as(i64, min_x) * 4;
    const max_sample = (@as(i64, max_x) + 1) * 4;
    const first = if (start64 <= min64)
        min_sample
    else
        @as(i64, @intFromFloat(@ceil(start64 * 4.0 - 0.5)));
    const after = if (end64 >= max64 + 1.0)
        max_sample
    else
        @as(i64, @intFromFloat(@ceil(end64 * 4.0 - 0.5)));
    if (after <= first) return null;

    const x_start: i32 = @intCast(@divFloor(first, 4));
    const x_end: i32 = @intCast(@divFloor(after - 1, 4));
    if (x_start == x_end) {
        addDifference(differences, min_x, x_start, x_start, @intCast(after - first));
        return .{ x_start, x_end };
    }

    const first_offset: i16 = @intCast(@mod(first, 4));
    const after_offset: i16 = @intCast(@mod(after, 4));
    var full_start = x_start;
    var full_end = x_end;
    if (first_offset != 0) {
        addDifference(differences, min_x, x_start, x_start, 4 - first_offset);
        full_start += 1;
    }
    if (after_offset != 0) {
        addDifference(differences, min_x, x_end, x_end, after_offset);
        full_end -= 1;
    }
    if (full_start <= full_end) {
        addDifference(differences, min_x, full_start, full_end, 4);
    }
    return .{ x_start, x_end };
}

fn addSpanWide(differences: []i16, min_x: i32, max_x: i32, start_f: f32, end_f: f32) ?[2]i32 {
    if (end_f <= start_f or end_f <= @as(f32, @floatFromInt(min_x)) or start_f >= @as(f32, @floatFromInt(max_x)) + 1.0) return null;
    const clipped_start = @max(start_f, @as(f32, @floatFromInt(min_x)));
    const clipped_end = @min(end_f, @as(f32, @floatFromInt(max_x)) + 1.0);
    const x_start: i32 = @intFromFloat(@floor(clipped_start));
    const x_end: i32 = @min(
        max_x,
        @as(i32, @intFromFloat(@ceil(clipped_end))) - 1,
    );
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

test "quarter-sample spans match scalar predicates across negative bounds" {
    const boundaries = [_]f32{
        -2.0,  -1.876, -1.875, -1.874, -1.625, -1.375, -1.125,
        -1.0,  -0.875, -0.625, -0.375, -0.125, 0.0,    0.125,
        0.375, 0.625,  0.875,  1.0,    2.0,    3.0,
    };
    for (boundaries) |start| {
        for (boundaries) |end| {
            var expected = [_]i16{0} ** 7;
            var actual = [_]i16{0} ** 7;
            const expected_span = addSpanScalar(&expected, -3, 2, start, end);
            const actual_span = addSpanQuarterSamples(&actual, -3, 2, start, end);
            try std.testing.expectEqual(expected_span, actual_span);
            try std.testing.expectEqualSlices(i16, &expected, &actual);
        }
    }
}

fn addSpanScalar(differences: []i16, min_x: i32, max_x: i32, start: f32, end: f32) ?[2]i32 {
    var first: ?i32 = null;
    var last: i32 = undefined;
    var x = min_x;
    while (x <= max_x) : (x += 1) {
        const base: f32 = @floatFromInt(x);
        var count: i16 = 0;
        inline for ([_]f32{ 0.125, 0.375, 0.625, 0.875 }) |offset| {
            count += @intFromBool(base + offset >= start and base + offset < end);
        }
        if (count == 0) continue;
        addDifference(differences, min_x, x, x, count);
        if (first == null) first = x;
        last = x;
    }
    return if (first) |value| .{ value, last } else null;
}

test "empty dense coverage keeps row metadata without pixel storage" {
    const rows = [_]struct { start: u32 = 0, len: u32 = 0 }{.{}} ** 4;
    var cache = try build(
        std.testing.allocator,
        .{ .min_x = 0, .min_y = 0, .max_x = 2, .max_y = 0 },
        &rows,
        &.{},
        0,
    );
    defer cache.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), cache.rows.len);
    try std.testing.expectEqual(@as(usize, 0), cache.pixels.len);
}

test "coverage row metadata remains eight bytes" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Row));
}
