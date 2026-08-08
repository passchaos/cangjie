const std = @import("std");
const glyph_mod = @import("../glyph.zig");

pub const Point = glyph_mod.Point;

pub const Line = struct {
    a: Point,
    b: Point,
};

pub const Target = struct {
    width: u32,
    height: u32,
    pixels: []u8,
};

pub const Bounds = struct {
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,
};

pub const FillRule = enum {
    non_zero,
    even_odd,
};

const WindingIntersection = struct {
    x: f32,
    delta: i8,
};

const PreparedFillLine = struct {
    ax: f32,
    ay: f32,
    y_min: f32,
    y_max: f32,
    slope: f32,
    delta: i8,
};

/// Fill flattened outline edges into an 8-bit alpha target.
///
/// The target is intentionally structural rather than tied to raster.zig's
/// RenderTarget type. That keeps this scanline module independent from the
/// high-level raster API while still documenting the required data layout:
/// `width` and `height` are pixel dimensions and `pixels` is a row-major
/// `[]u8` buffer of at least `width * height` bytes.
pub fn fill(allocator: std.mem.Allocator, target: Target, lines: []const Line, fill_rule: FillRule, samples_per_axis: u8) !void {
    if (lines.len == 0) return;
    const bounds = boundsForTarget(target, lines) orelse return;
    const min_x = bounds.min_x;
    const min_y = bounds.min_y;
    const max_x = bounds.max_x;
    const max_y = bounds.max_y;

    const sample_axis: i32 = @max(1, @as(i32, samples_per_axis));
    const sample_count = sample_axis * sample_axis;
    var dynamic_coverage_lut: [256]u8 = undefined;
    const coverage_lut = coverageLutForSampleCount(sample_count) orelse blk: {
        fillCoverageLut(&dynamic_coverage_lut, sample_count);
        break :blk dynamic_coverage_lut[0..];
    };
    const sample_axis_usize: usize = @intCast(sample_axis);
    var dynamic_sample_offsets: []f32 = &.{};
    const sample_offsets: []const f32 = sampleOffsetsForAxis(sample_axis) orelse blk: {
        dynamic_sample_offsets = try allocator.alloc(f32, sample_axis_usize);
        for (dynamic_sample_offsets, 0..) |*offset, sample_index| {
            offset.* = (@as(f32, @floatFromInt(sample_index)) + 0.5) / @as(f32, @floatFromInt(sample_axis));
        }
        break :blk dynamic_sample_offsets;
    };
    defer if (dynamic_sample_offsets.len != 0) allocator.free(dynamic_sample_offsets);
    const row_width_i32 = max_x - min_x + 1;
    if (row_width_i32 <= 0) return;
    const row_width: usize = @intCast(row_width_i32);
    var inline_coverage_counts: [512]u8 = undefined;
    const coverage_counts = if (row_width <= inline_coverage_counts.len)
        inline_coverage_counts[0..row_width]
    else
        try allocator.alloc(u8, row_width);
    defer if (row_width > inline_coverage_counts.len) allocator.free(coverage_counts);
    @memset(coverage_counts, 0);
    var inline_prepared_lines: [128]PreparedFillLine = undefined;
    const prepared_storage = if (lines.len <= inline_prepared_lines.len)
        inline_prepared_lines[0..lines.len]
    else
        try allocator.alloc(PreparedFillLine, lines.len);
    defer if (lines.len > inline_prepared_lines.len) allocator.free(prepared_storage);
    const prepared_lines = prepareFillLines(prepared_storage, lines);
    if (prepared_lines.len < 2) return;
    sortPreparedFillLinesByYMin(prepared_lines);
    var inline_intersections: [128]WindingIntersection = undefined;
    const intersection_storage = if (prepared_lines.len <= inline_intersections.len)
        inline_intersections[0..prepared_lines.len]
    else
        try allocator.alloc(WindingIntersection, prepared_lines.len);
    defer if (prepared_lines.len > inline_intersections.len) allocator.free(intersection_storage);
    var inline_active_lines: [128]PreparedFillLine = undefined;
    const active_storage = if (prepared_lines.len <= inline_active_lines.len)
        inline_active_lines[0..prepared_lines.len]
    else
        try allocator.alloc(PreparedFillLine, prepared_lines.len);
    defer if (prepared_lines.len > inline_active_lines.len) allocator.free(active_storage);

    var next_line: usize = 0;
    var active_count: usize = 0;
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        const row_lines = updateActiveFillLines(active_storage, &active_count, prepared_lines, &next_line, y);
        if (row_lines.len < 2) continue;
        var row_has_coverage = false;
        var row_min_x = max_x;
        var row_max_x = min_x;
        for (sample_offsets) |sample_offset| {
            const py = @as(f32, @floatFromInt(y)) + sample_offset;
            if (row_lines.len == 2) {
                const first = row_lines[0];
                const second = row_lines[1];
                if (py < first.y_min or py >= first.y_max or py < second.y_min or py >= second.y_max) continue;
                const first_x = first.slope * (py - first.ay) + first.ax;
                const second_x = second.slope * (py - second.ay) + second.ax;
                if (!std.math.isFinite(first_x) or !std.math.isFinite(second_x)) continue;
                if (@abs(second_x - first_x) <= 0.000001) continue;
                const start_f, const end_f, const left_delta = if (first_x < second_x)
                    .{ first_x, second_x, first.delta }
                else
                    .{ second_x, first_x, second.delta };
                if (fill_rule == .even_odd or left_delta != 0) {
                    if (coverSpan(coverage_counts, min_x, max_x, sample_offsets, start_f, end_f)) |span| {
                        row_has_coverage = true;
                        row_min_x = @min(row_min_x, span.min_x);
                        row_max_x = @max(row_max_x, span.max_x);
                    }
                }
                continue;
            }

            var intersection_count: usize = 0;
            for (row_lines) |line| {
                if (py < line.y_min or py >= line.y_max) continue;
                const x_intersect = line.slope * (py - line.ay) + line.ax;
                if (!std.math.isFinite(x_intersect)) continue;
                intersection_storage[intersection_count] = .{
                    .x = x_intersect,
                    .delta = line.delta,
                };
                intersection_count += 1;
            }
            const intersections = intersection_storage[0..intersection_count];
            if (intersections.len < 2) continue;
            sortWindingIntersections(intersections);

            if (intersections.len == 2 and @abs(intersections[1].x - intersections[0].x) > 0.000001) {
                if (fill_rule == .even_odd or intersections[0].delta != 0) {
                    if (coverSpan(coverage_counts, min_x, max_x, sample_offsets, intersections[0].x, intersections[1].x)) |span| {
                        row_has_coverage = true;
                        row_min_x = @min(row_min_x, span.min_x);
                        row_max_x = @max(row_max_x, span.max_x);
                    }
                }
                continue;
            }

            switch (fill_rule) {
                .non_zero => {
                    var winding: i32 = 0;
                    var previous_x: ?f32 = null;
                    var index: usize = 0;
                    while (index < intersections.len) {
                        const current_x = intersections[index].x;
                        if (previous_x) |start_f| {
                            const end_f = current_x;
                            if (winding != 0) {
                                if (coverSpan(coverage_counts, min_x, max_x, sample_offsets, start_f, end_f)) |span| {
                                    row_has_coverage = true;
                                    row_min_x = @min(row_min_x, span.min_x);
                                    row_max_x = @max(row_max_x, span.max_x);
                                }
                            }
                        }

                        var delta_sum: i32 = 0;
                        while (index < intersections.len and @abs(intersections[index].x - current_x) <= 0.000001) : (index += 1) {
                            delta_sum += intersections[index].delta;
                        }
                        winding += delta_sum;
                        previous_x = current_x;
                    }
                },
                .even_odd => {
                    var pair: usize = 0;
                    while (pair + 1 < intersections.len) : (pair += 2) {
                        if (coverSpan(coverage_counts, min_x, max_x, sample_offsets, intersections[pair].x, intersections[pair + 1].x)) |span| {
                            row_has_coverage = true;
                            row_min_x = @min(row_min_x, span.min_x);
                            row_max_x = @max(row_max_x, span.max_x);
                        }
                    }
                },
            }
        }
        if (!row_has_coverage) continue;
        var x = row_min_x;
        while (x <= row_max_x) : (x += 1) {
            const inside = coverage_counts[@intCast(x - min_x)];
            if (inside == 0) continue;
            blendUnchecked(target, x, y, coverage_lut[inside]);
        }
        const clear_start: usize = @intCast(row_min_x - min_x);
        const clear_end: usize = @intCast(row_max_x - min_x + 1);
        @memset(coverage_counts[clear_start..clear_end], 0);
    }
}

pub fn boundsForTarget(target: Target, lines: []const Line) ?Bounds {
    const target_max_x = targetMaxPixelIndex(target.width) orelse return null;
    const target_max_y = targetMaxPixelIndex(target.height) orelse return null;
    var raw_min_x: i32 = std.math.maxInt(i32);
    var raw_min_y: i32 = std.math.maxInt(i32);
    var raw_max_x: i32 = std.math.minInt(i32);
    var raw_max_y: i32 = std.math.minInt(i32);
    var saw_finite_line = false;
    for (lines) |line| {
        if (!lineFinite(line)) continue;
        saw_finite_line = true;
        raw_min_x = @min(raw_min_x, floorI32Saturating(@min(line.a.x, line.b.x)));
        raw_min_y = @min(raw_min_y, floorI32Saturating(@min(line.a.y, line.b.y)));
        raw_max_x = @max(raw_max_x, ceilI32Saturating(@max(line.a.x, line.b.x)));
        raw_max_y = @max(raw_max_y, ceilI32Saturating(@max(line.a.y, line.b.y)));
    }
    if (!saw_finite_line) return null;

    const min_x = @max(0, saturatingSubOne(raw_min_x));
    const min_y = @max(0, saturatingSubOne(raw_min_y));
    const max_x = @min(target_max_x, saturatingAddOne(raw_max_x));
    const max_y = @min(target_max_y, saturatingAddOne(raw_max_y));
    if (max_x < min_x or max_y < min_y) return null;
    return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
}

fn blendUnchecked(target: Target, x: i32, y: i32, coverage: u8) void {
    const idx = @as(usize, @intCast(y)) * target.width + @as(usize, @intCast(x));
    if (coverage == 255) {
        target.pixels[idx] = 255;
        return;
    }
    target.pixels[idx] = @max(target.pixels[idx], coverage);
}

fn prepareFillLines(out: []PreparedFillLine, lines: []const Line) []PreparedFillLine {
    std.debug.assert(out.len >= lines.len);
    var count: usize = 0;
    for (lines) |line| {
        if (!lineFinite(line)) continue;
        const dy = line.b.y - line.a.y;
        // Horizontal edges never cross the half-open scanline test used by the
        // rasterizer. Dropping them here keeps the hot sample loop focused on
        // candidate edges while preserving the exact winding rule for all rows.
        if (dy == 0.0) continue;
        out[count] = .{
            .ax = line.a.x,
            .ay = line.a.y,
            .y_min = @min(line.a.y, line.b.y),
            .y_max = @max(line.a.y, line.b.y),
            .slope = (line.b.x - line.a.x) / dy,
            .delta = if (dy > 0.0) 1 else -1,
        };
        count += 1;
    }
    return out[0..count];
}

fn lessThanPreparedFillLineYMin(_: void, lhs: PreparedFillLine, rhs: PreparedFillLine) bool {
    return lhs.y_min < rhs.y_min;
}

fn sortPreparedFillLinesByYMin(lines: []PreparedFillLine) void {
    if (lines.len <= 32) {
        var index: usize = 1;
        while (index < lines.len) : (index += 1) {
            const value = lines[index];
            var cursor = index;
            while (cursor > 0 and lines[cursor - 1].y_min > value.y_min) : (cursor -= 1) {
                lines[cursor] = lines[cursor - 1];
            }
            lines[cursor] = value;
        }
        return;
    }
    std.sort.heap(PreparedFillLine, lines, {}, lessThanPreparedFillLineYMin);
}

fn updateActiveFillLines(active_storage: []PreparedFillLine, active_count: *usize, sorted_lines: []const PreparedFillLine, next_line: *usize, y: i32) []PreparedFillLine {
    std.debug.assert(active_storage.len >= sorted_lines.len);
    const row_min_y: f32 = @floatFromInt(y);
    const row_max_y = row_min_y + 1.0;

    var kept: usize = 0;
    for (active_storage[0..active_count.*]) |line| {
        // Each sample row is half-open: an edge contributes when
        // y_min <= sample_y < y_max. Keeping only edges that may cross the
        // current pixel row preserves the exact per-sample boundary test while
        // avoiding a full edge-list scan on every row.
        if (line.y_max <= row_min_y) continue;
        active_storage[kept] = line;
        kept += 1;
    }
    active_count.* = kept;

    while (next_line.* < sorted_lines.len and sorted_lines[next_line.*].y_min < row_max_y) : (next_line.* += 1) {
        const line = sorted_lines[next_line.*];
        if (line.y_max <= row_min_y) continue;
        active_storage[active_count.*] = line;
        active_count.* += 1;
    }

    return active_storage[0..active_count.*];
}

const sample_offsets_1 = [_]f32{0.5};
const sample_offsets_2 = [_]f32{ 0.25, 0.75 };
const sample_offsets_4 = [_]f32{ 0.125, 0.375, 0.625, 0.875 };
const coverage_lut_1 = makeCoverageLut(1);
const coverage_lut_4 = makeCoverageLut(4);
const coverage_lut_16 = makeCoverageLut(16);

fn sampleOffsetsForAxis(sample_axis: i32) ?[]const f32 {
    return switch (sample_axis) {
        1 => &sample_offsets_1,
        2 => &sample_offsets_2,
        4 => &sample_offsets_4,
        else => null,
    };
}

fn coverageLutForSampleCount(sample_count: i32) ?[]const u8 {
    return switch (sample_count) {
        1 => &coverage_lut_1,
        4 => &coverage_lut_4,
        16 => &coverage_lut_16,
        else => null,
    };
}

fn makeCoverageLut(comptime sample_count: i32) [256]u8 {
    var lut: [256]u8 = undefined;
    fillCoverageLut(&lut, sample_count);
    return lut;
}

fn fillCoverageLut(lut: *[256]u8, sample_count: i32) void {
    for (lut, 0..) |*coverage, count| {
        const clamped_count = @min(@as(i32, @intCast(count)), sample_count);
        coverage.* = @intCast(@divTrunc(clamped_count * @as(i32, 255), sample_count));
    }
}

fn lessThanWindingIntersection(_: void, lhs: WindingIntersection, rhs: WindingIntersection) bool {
    return lhs.x < rhs.x;
}

fn sortWindingIntersections(intersections: []WindingIntersection) void {
    if (intersections.len <= 16) {
        var index: usize = 1;
        while (index < intersections.len) : (index += 1) {
            const value = intersections[index];
            var cursor = index;
            while (cursor > 0 and intersections[cursor - 1].x > value.x) : (cursor -= 1) {
                intersections[cursor] = intersections[cursor - 1];
            }
            intersections[cursor] = value;
        }
        return;
    }
    std.sort.heap(WindingIntersection, intersections, {}, lessThanWindingIntersection);
}

const CoveredSpan = struct {
    min_x: i32,
    max_x: i32,
};

fn coverSpan(coverage_counts: []u8, min_x: i32, max_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32) ?CoveredSpan {
    if (!std.math.isFinite(start_f) or !std.math.isFinite(end_f)) return null;
    if (@as(f64, end_f) <= @as(f64, start_f)) return null;
    if (@as(f64, end_f) <= @as(f64, @floatFromInt(min_x)) or
        @as(f64, start_f) >= @as(f64, @floatFromInt(max_x)) + 1.0) return null;
    const x_start = @max(min_x, floorI32Saturating(start_f));
    const x_end = @min(max_x, ceilI32Saturating(end_f));
    const full_start = @max(x_start, ceilI32Saturating(start_f));
    const full_end = @min(x_end, floorI32Saturating(end_f) - 1);
    const full_coverage: u8 = @intCast(sample_offsets.len);

    var x = x_start;
    if (full_start <= full_end) {
        while (x < full_start) : (x += 1) {
            coverPartialPixel(coverage_counts, min_x, sample_offsets, start_f, end_f, x);
        }
        while (x <= full_end) : (x += 1) {
            coverage_counts[@intCast(x - min_x)] += full_coverage;
        }
    }
    while (x <= x_end) : (x += 1) {
        coverPartialPixel(coverage_counts, min_x, sample_offsets, start_f, end_f, x);
    }
    return .{ .min_x = x_start, .max_x = x_end };
}

fn coverPartialPixel(coverage_counts: []u8, min_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32, x: i32) void {
    for (sample_offsets) |sample_offset| {
        const px = @as(f32, @floatFromInt(x)) + sample_offset;
        if (px >= start_f and px < end_f) {
            coverage_counts[@intCast(x - min_x)] += 1;
        }
    }
}

fn targetMaxPixelIndex(limit: u32) ?i32 {
    if (limit == 0) return null;
    const max_i32_u32: u32 = @intCast(std.math.maxInt(i32));
    return @intCast(@min(limit - 1, max_i32_u32));
}

fn lineFinite(line: Line) bool {
    return pointFinite(line.a) and pointFinite(line.b);
}

fn pointFinite(point: Point) bool {
    return std.math.isFinite(point.x) and std.math.isFinite(point.y);
}

fn floorI32Saturating(value: f32) i32 {
    if (!std.math.isFinite(value)) return if (value > 0.0) std.math.maxInt(i32) else std.math.minInt(i32);
    const value64: f64 = value;
    if (value64 <= @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    if (value64 >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(@floor(value64));
}

fn ceilI32Saturating(value: f32) i32 {
    if (!std.math.isFinite(value)) return if (value > 0.0) std.math.maxInt(i32) else std.math.minInt(i32);
    const value64: f64 = value;
    if (value64 <= @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    if (value64 >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(@ceil(value64));
}

fn saturatingSubOne(value: i32) i32 {
    return if (value == std.math.minInt(i32)) value else value - 1;
}

fn saturatingAddOne(value: i32) i32 {
    return if (value == std.math.maxInt(i32)) value else value + 1;
}
