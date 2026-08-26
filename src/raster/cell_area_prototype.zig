//! Experimental analytic cell-area rasterizer.
//!
//! This is deliberately isolated from the production dispatch.  It models
//! FreeType's two per-cell integrals (`cover` and `area`) so that the output
//! semantics can be compared with Cangjie's 4x4 point sampler before any hot
//! path is replaced.
const std = @import("std");
const scanline = @import("scanline.zig");

const Cell = struct {
    cover: f64 = 0,
    area: f64 = 0,
};

pub fn fill(
    allocator: std.mem.Allocator,
    target: scanline.Target,
    lines: []const scanline.Line,
    fill_rule: scanline.FillRule,
) !void {
    if (target.width == 0 or target.height == 0 or lines.len == 0) return;

    const bounds = scanline.boundsForTarget(target, lines) orelse return;
    // One sentinel cell to the left carries winding into a clipped row, just
    // like `ftgrays` clamps all cells left of its band to `min_ex - 1`.
    const min_x = bounds.min_x - 1;
    const max_x = bounds.max_x;
    const min_y = bounds.min_y;
    const max_y = bounds.max_y;
    const width_i64 = @as(i64, max_x) - min_x + 1;
    const height_i64 = @as(i64, max_y) - min_y + 1;
    // This prototype uses a dense grid to keep the integral itself obvious.
    // Production code would need sparse cells and bounded banding.
    if (width_i64 <= 0 or width_i64 > 16 * 1024 or height_i64 <= 0)
        return error.OutOfMemory;
    const grid_width: usize = @intCast(width_i64);
    const grid_height: usize = @intCast(height_i64);
    const cell_count = try std.math.mul(usize, grid_width, grid_height);
    const cells = try allocator.alloc(Cell, cell_count);
    defer allocator.free(cells);
    @memset(cells, .{});

    for (lines) |line| {
        try accumulateLine(cells, grid_width, min_x, min_y, grid_height, line);
    }
    sweep(target, cells, grid_width, min_x, min_y, fill_rule);
}

fn accumulateLine(
    cells: []Cell,
    grid_width: usize,
    origin_x: i32,
    origin_y: i32,
    height: usize,
    line: scanline.Line,
) !void {
    if (!pointFinite(line.a) or !pointFinite(line.b)) return;
    const dy = @as(f64, line.b.y) - line.a.y;
    if (dy == 0 or !std.math.isFinite(dy)) return;

    const low_y = @max(
        @as(f64, @floatFromInt(origin_y)),
        @min(@as(f64, line.a.y), line.b.y),
    );
    const high_y = @min(
        @as(f64, @floatFromInt(origin_y)) +
            @as(f64, @floatFromInt(height)),
        @max(@as(f64, line.a.y), line.b.y),
    );
    if (low_y >= high_y) return;
    var row = floorI32FromF64(low_y) orelse return;
    const last_row = (ceilI32FromF64(high_y) orelse return) - 1;
    while (row <= last_row) : (row += 1) {
        if (row < origin_y or row - origin_y >= height) continue;
        const strip_low = @max(low_y, @as(f64, @floatFromInt(row)));
        const strip_high = @min(high_y, @as(f64, @floatFromInt(row + 1)));
        if (strip_low >= strip_high) continue;
        const low_t = (strip_low - line.a.y) / dy;
        const high_t = (strip_high - line.a.y) / dy;
        const x_low = lerp(line.a.x, line.b.x, low_t);
        const x_high = lerp(line.a.x, line.b.x, high_t);
        const row_index: usize = @intCast(row - origin_y);
        const row_cells = cells[row_index * grid_width ..][0..grid_width];
        if (dy > 0) {
            try accumulateStrip(row_cells, origin_x, x_low, x_high, strip_high - strip_low);
        } else {
            try accumulateStrip(row_cells, origin_x, x_high, x_low, strip_low - strip_high);
        }
    }
}

fn accumulateStrip(
    row: []Cell,
    origin_x: i32,
    start_x: f64,
    end_x: f64,
    signed_dy: f64,
) !void {
    const dx = end_x - start_x;
    if (dx == 0) {
        const cell_x = floorI32FromF64(start_x) orelse return;
        addCell(row, origin_x, cell_x, signed_dy, start_x - @as(f64, @floatFromInt(cell_x)), start_x - @as(f64, @floatFromInt(cell_x)));
        return;
    }

    var t: f64 = 0;
    var iterations: usize = 0;
    while (t < 1) {
        // Probe into the open interval so an endpoint exactly on an integer
        // boundary is assigned to the cell the segment actually traverses.
        const probe_t = @min(1.0, t + 1.0e-12);
        const probe_x = start_x + dx * probe_t;
        const cell_x = floorI32FromF64(probe_x) orelse return;
        const boundary = if (dx > 0)
            @as(f64, @floatFromInt(cell_x + 1))
        else
            @as(f64, @floatFromInt(cell_x));
        var next_t = (boundary - start_x) / dx;
        // Rounding can leave `t` microscopically before a boundary while the
        // recomputed quotient lands on the same value.  Advancing by an ulp
        // (rather than an arbitrary geometric epsilon) guarantees progress
        // without skipping a representable crossing.
        if (next_t <= t) next_t = @min(1.0, std.math.nextAfter(f64, t, 1.0));
        next_t = @min(1.0, next_t);
        const piece_start_x = start_x + dx * t;
        const piece_end_x = start_x + dx * next_t;
        const base_x: f64 = @floatFromInt(cell_x);
        addCell(
            row,
            origin_x,
            cell_x,
            signed_dy * (next_t - t),
            std.math.clamp(piece_start_x - base_x, 0.0, 1.0),
            std.math.clamp(piece_end_x - base_x, 0.0, 1.0),
        );
        t = next_t;
        iterations += 1;
        if (iterations > row.len + 2) return error.InvalidOutline;
    }
}

inline fn addCell(
    row: []Cell,
    origin_x: i32,
    cell_x: i32,
    dy: f64,
    x0: f64,
    x1: f64,
) void {
    const index = @as(i64, cell_x) - origin_x;
    if (index < 0 or index >= row.len) return;
    const cell = &row[@intCast(index)];
    cell.cover += dy;
    cell.area += dy * (x0 + x1);
}

fn sweep(
    target: scanline.Target,
    cells: []const Cell,
    grid_width: usize,
    origin_x: i32,
    origin_y: i32,
    fill_rule: scanline.FillRule,
) void {
    const grid_height = cells.len / grid_width;
    for (0..grid_height) |grid_y| {
        const row = cells[grid_y * grid_width ..][0..grid_width];
        const y = origin_y + @as(i32, @intCast(grid_y));
        var cover: f64 = 0;
        for (row, 0..) |cell, grid_x| {
            cover += cell.cover;
            const x = origin_x + @as(i32, @intCast(grid_x));
            if (x < 0 or x >= target.width) continue;
            var coverage = @abs(cover - cell.area * 0.5);
            if (fill_rule == .even_odd) {
                coverage = @mod(coverage, 2.0);
                if (coverage > 1.0) coverage = 2.0 - coverage;
            } else {
                coverage = @min(1.0, coverage);
            }
            const alpha: u8 = @intFromFloat(@floor(coverage * 255.0));
            const target_index = @as(usize, @intCast(y)) * target.width +
                @as(usize, @intCast(x));
            target.pixels[target_index] = @max(target.pixels[target_index], alpha);
        }
    }
}

inline fn pointFinite(point: scanline.Point) bool {
    return std.math.isFinite(point.x) and std.math.isFinite(point.y);
}

inline fn lerp(a: f32, b: f32, t: f64) f64 {
    return @as(f64, a) + (@as(f64, b) - a) * t;
}

fn floorI32FromF64(value: f64) ?i32 {
    if (!std.math.isFinite(value) or value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intFromFloat(@floor(value));
}

fn ceilI32FromF64(value: f64) ?i32 {
    if (!std.math.isFinite(value) or value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intFromFloat(@ceil(value));
}

test "cell-area prototype matches 4x4 sampling for pixel-aligned rectangle" {
    const lines = [_]scanline.Line{
        .{ .a = .{ .x = 1, .y = 1 }, .b = .{ .x = 4, .y = 1 } },
        .{ .a = .{ .x = 4, .y = 1 }, .b = .{ .x = 4, .y = 4 } },
        .{ .a = .{ .x = 4, .y = 4 }, .b = .{ .x = 1, .y = 4 } },
        .{ .a = .{ .x = 1, .y = 4 }, .b = .{ .x = 1, .y = 1 } },
    };
    var sampled_pixels = [_]u8{0} ** 36;
    var analytic_pixels = [_]u8{0} ** 36;
    try scanline.fill(std.testing.allocator, .{ .width = 6, .height = 6, .pixels = &sampled_pixels }, &lines, .non_zero, 4);
    try fill(std.testing.allocator, .{ .width = 6, .height = 6, .pixels = &analytic_pixels }, &lines, .non_zero);
    try std.testing.expectEqualSlices(u8, &sampled_pixels, &analytic_pixels);
}

test "cell-area prototype integrates fractional rectangle coverage" {
    const lines = [_]scanline.Line{
        .{ .a = .{ .x = 1.25, .y = 1.25 }, .b = .{ .x = 3.75, .y = 1.25 } },
        .{ .a = .{ .x = 3.75, .y = 1.25 }, .b = .{ .x = 3.75, .y = 3.75 } },
        .{ .a = .{ .x = 3.75, .y = 3.75 }, .b = .{ .x = 1.25, .y = 3.75 } },
        .{ .a = .{ .x = 1.25, .y = 3.75 }, .b = .{ .x = 1.25, .y = 1.25 } },
    };
    var pixels = [_]u8{0} ** 25;
    try fill(
        std.testing.allocator,
        .{ .width = 5, .height = 5, .pixels = &pixels },
        &lines,
        .non_zero,
    );
    const expected = [_]u8{
        0, 0,   0,   0,   0,
        0, 143, 191, 143, 0,
        0, 191, 255, 191, 0,
        0, 143, 191, 143, 0,
        0, 0,   0,   0,   0,
    };
    try std.testing.expectEqualSlices(u8, &expected, &pixels);

    // Quarter-pixel rectangle boundaries are exactly representable by the
    // existing four sample lanes, so this is a true differential case rather
    // than merely an analytic oracle.
    var sampled = [_]u8{0} ** 25;
    try scanline.fill(
        std.testing.allocator,
        .{ .width = 5, .height = 5, .pixels = &sampled },
        &lines,
        .non_zero,
        4,
    );
    try std.testing.expectEqualSlices(u8, &sampled, &pixels);
}

test "cell-area prototype preserves orientation and non-zero holes" {
    const lines = [_]scanline.Line{
        // Clockwise outer rectangle.
        .{ .a = .{ .x = 0.5, .y = 0.5 }, .b = .{ .x = 4.5, .y = 0.5 } },
        .{ .a = .{ .x = 4.5, .y = 0.5 }, .b = .{ .x = 4.5, .y = 4.5 } },
        .{ .a = .{ .x = 4.5, .y = 4.5 }, .b = .{ .x = 0.5, .y = 4.5 } },
        .{ .a = .{ .x = 0.5, .y = 4.5 }, .b = .{ .x = 0.5, .y = 0.5 } },
        // Counter-clockwise inner rectangle cancels the winding.
        .{ .a = .{ .x = 1.5, .y = 1.5 }, .b = .{ .x = 1.5, .y = 3.5 } },
        .{ .a = .{ .x = 1.5, .y = 3.5 }, .b = .{ .x = 3.5, .y = 3.5 } },
        .{ .a = .{ .x = 3.5, .y = 3.5 }, .b = .{ .x = 3.5, .y = 1.5 } },
        .{ .a = .{ .x = 3.5, .y = 1.5 }, .b = .{ .x = 1.5, .y = 1.5 } },
    };
    var pixels = [_]u8{0} ** 25;
    try fill(
        std.testing.allocator,
        .{ .width = 5, .height = 5, .pixels = &pixels },
        &lines,
        .non_zero,
    );
    try std.testing.expectEqual(@as(u8, 0), pixels[2 * 5 + 2]);
    try std.testing.expectEqual(@as(u8, 127), pixels[1 * 5 + 2]);
    try std.testing.expectEqual(@as(u8, 127), pixels[2 * 5 + 1]);
}
