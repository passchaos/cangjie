const std = @import("std");
const scanline = @import("scanline.zig");

// Prepared scan conversion intentionally lives beside, rather than inside,
// `scanline.zig`. The direct renderer relies on whole-function optimization of
// its stack-local preparation and scan; adding the retained-geometry entry
// point to that compilation unit measurably changed its inlining budget.
// Differential tests in raster.zig keep both scanners byte-identical.

pub const Point = scanline.Point;

pub const Line = scanline.Line;

pub const Target = scanline.Target;

pub const Bounds = scanline.Bounds;

pub const FillRule = scanline.FillRule;

const WindingIntersection = scanline.WindingIntersection;
const PreparedFillLine = scanline.PreparedFillLine;

/// Immutable scan-conversion geometry for repeated rendering.
///
/// Preparation removes horizontal/non-finite edges, computes intersection
/// slopes, and sorts by the first active scanline. The result owns no mutable
/// scratch and is safe to share; each fill call uses independent scratch.
pub const PreparedFill = struct {
    allocator: std.mem.Allocator,
    lines: []const PreparedFillLine,
    raw_bounds: ?Bounds,

    pub fn deinit(self: *PreparedFill) void {
        self.allocator.free(@constCast(self.lines));
        self.* = undefined;
    }

    pub fn edgeCount(self: *const PreparedFill) usize {
        return self.lines.len;
    }

    pub fn boundsForTarget(self: *const PreparedFill, target: Target) ?Bounds {
        return preparedBoundsForTarget(target, self.raw_bounds);
    }
};

pub fn prepare(allocator: std.mem.Allocator, lines: []const Line) !PreparedFill {
    const raw_bounds = rawBoundsForLines(lines);
    const storage = try allocator.alloc(PreparedFillLine, lines.len);
    errdefer allocator.free(storage);
    const lines_prepared = scanline.prepareFillLines(storage, lines);
    scanline.sortPreparedFillLinesByYMin(lines_prepared);
    const owned = try allocator.realloc(storage, lines_prepared.len);
    return .{ .allocator = allocator, .lines = owned, .raw_bounds = raw_bounds };
}

pub fn fill(allocator: std.mem.Allocator, target: Target, prepared: *const PreparedFill, fill_rule: FillRule, samples_per_axis: u8) !void {
    const bounds = preparedBoundsForTarget(target, prepared.raw_bounds) orelse return;
    const prepared_lines = prepared.lines;
    if (prepared_lines.len < 2) return;
    const min_x = bounds.min_x;
    const min_y = bounds.min_y;
    const max_x = bounds.max_x;
    const max_y = bounds.max_y;

    const sample_axis: i32 = @max(1, @as(i32, samples_per_axis));
    const sample_count = sample_axis * sample_axis;
    var dynamic_coverage_lut: [256]u8 = undefined;
    const coverage_lut = scanline.coverageLutForSampleCount(sample_count) orelse blk: {
        scanline.fillCoverageLut(&dynamic_coverage_lut, sample_count);
        break :blk dynamic_coverage_lut[0..];
    };
    const sample_axis_usize: usize = @intCast(sample_axis);
    var dynamic_sample_offsets: []f32 = &.{};
    const sample_offsets: []const f32 = scanline.sampleOffsetsForAxis(sample_axis) orelse blk: {
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
        const row_lines = scanline.updateActiveFillLines(active_storage, &active_count, prepared_lines, &next_line, y);
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
                    if (scanline.coverSpanFinite(coverage_counts, min_x, max_x, sample_offsets, start_f, end_f)) |span| {
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
            scanline.sortWindingIntersections(intersections);

            if (intersections.len == 2 and @abs(intersections[1].x - intersections[0].x) > 0.000001) {
                if (fill_rule == .even_odd or intersections[0].delta != 0) {
                    if (scanline.coverSpanFinite(coverage_counts, min_x, max_x, sample_offsets, intersections[0].x, intersections[1].x)) |span| {
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
                                if (scanline.coverSpanFinite(coverage_counts, min_x, max_x, sample_offsets, start_f, end_f)) |span| {
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
                        if (scanline.coverSpanFinite(coverage_counts, min_x, max_x, sample_offsets, intersections[pair].x, intersections[pair + 1].x)) |span| {
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
            scanline.blendUnchecked(target, x, y, coverage_lut[inside]);
        }
        const clear_start: usize = @intCast(row_min_x - min_x);
        const clear_end: usize = @intCast(row_max_x - min_x + 1);
        @memset(coverage_counts[clear_start..clear_end], 0);
    }
}

fn rawBoundsForLines(lines: []const Line) ?Bounds {
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
    return .{ .min_x = saturatingSubOne(raw_min_x), .min_y = saturatingSubOne(raw_min_y), .max_x = saturatingAddOne(raw_max_x), .max_y = saturatingAddOne(raw_max_y) };
}

fn preparedBoundsForTarget(target: Target, raw_bounds: ?Bounds) ?Bounds {
    const raw = raw_bounds orelse return null;
    const target_max_x = targetMaxPixelIndex(target.width) orelse return null;
    const target_max_y = targetMaxPixelIndex(target.height) orelse return null;
    const min_x = @max(0, raw.min_x);
    const min_y = @max(0, raw.min_y);
    const max_x = @min(target_max_x, raw.max_x);
    const max_y = @min(target_max_y, raw.max_y);
    if (max_x < min_x or max_y < min_y) return null;
    return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
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
