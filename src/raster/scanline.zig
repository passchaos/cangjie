const std = @import("std");
const RowAccumulator = @import("row_accumulator.zig").RowAccumulator;
const scanline_types = @import("scanline_types.zig");

pub const Point = scanline_types.Point;

pub const Line = struct {
    a: Point,
    b: Point,
};

pub const Target = scanline_types.Target;

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

pub const WindingIntersection = struct {
    x: f32,
    delta: i8,
};

pub const PreparedFillLine = struct {
    x_at_y_min: f32,
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
    var inline_prepared_lines: [128]PreparedFillLine = undefined;
    const prepared_storage = if (lines.len <= inline_prepared_lines.len)
        inline_prepared_lines[0..lines.len]
    else
        try allocator.alloc(PreparedFillLine, lines.len);
    defer if (lines.len > inline_prepared_lines.len) allocator.free(prepared_storage);
    const prepared = prepareFillLinesAndBounds(target, prepared_storage, lines);
    const prepared_lines = prepared.lines;
    if (prepared_lines.len < 2) return;
    const bounds = prepared.bounds orelse return;
    const min_x = bounds.min_x;
    const min_y = bounds.min_y;
    const max_x = bounds.max_x;
    const max_y = bounds.max_y;
    const row_width_i32 = max_x - min_x + 1;
    if (row_width_i32 <= 0) return;
    const row_width: usize = @intCast(row_width_i32);
    var inline_coverage_counts: [512]u8 = undefined;
    // Text glyph rows are normally well below this width. Keeping only the
    // common case inline cuts the direct fill's stack frame substantially;
    // unusually wide targets retain the allocator-backed fallback.
    var inline_coverage_differences: [129]i16 = undefined;
    var row_accumulator = try RowAccumulator.init(
        allocator,
        row_width,
        sample_axis == 4,
        &inline_coverage_counts,
        &inline_coverage_differences,
    );
    defer row_accumulator.deinit(allocator);
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

    if (prepared_lines.len < 32) {
        sortPreparedFillLinesByYMin(prepared_lines);
        var next_line: usize = 0;
        var active_count: usize = 0;
        var y = min_y;
        while (y <= max_y) : (y += 1) {
            const row_lines = updateActiveFillLines(active_storage, &active_count, prepared_lines, &next_line, y);
            fillPreparedRow(target, row_lines, intersection_storage, min_x, max_x, y, fill_rule, sample_offsets, coverage_lut, &row_accumulator);
        }
        return;
    }

    // Direct rendering rebuilds edge state for every draw. Bucket sufficiently
    // complex outlines by the first pixel row each edge can cross instead of
    // comparison-sorting complete 24-byte records by y_min. Order within one
    // row is irrelevant because intersections are sorted by x before winding
    // is evaluated. Small outlines retain insertion sorting because the fixed
    // bucket setup costs more than the comparisons it replaces.
    var inline_next_lines: [128]usize = undefined;
    const next_lines = if (prepared_lines.len <= inline_next_lines.len)
        inline_next_lines[0..prepared_lines.len]
    else
        try allocator.alloc(usize, prepared_lines.len);
    defer if (prepared_lines.len > inline_next_lines.len) allocator.free(next_lines);
    const row_count: usize = @intCast(max_y - min_y + 1);
    var inline_row_heads: [512]usize = undefined;
    const row_heads = if (row_count <= inline_row_heads.len)
        inline_row_heads[0..row_count]
    else
        try allocator.alloc(usize, row_count);
    defer if (row_count > inline_row_heads.len) allocator.free(row_heads);
    bucketFillLinesByFirstRow(prepared_lines, min_y, max_y, next_lines, row_heads);

    var active_count: usize = 0;
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        const row_lines = updateBucketedActiveFillLines(
            active_storage,
            &active_count,
            prepared_lines,
            next_lines,
            row_heads[@intCast(y - min_y)],
            y,
        );
        fillPreparedRow(
            target,
            row_lines,
            intersection_storage,
            min_x,
            max_x,
            y,
            fill_rule,
            sample_offsets,
            coverage_lut,
            &row_accumulator,
        );
    }
}

inline fn fillPreparedRow(
    target: Target,
    row_lines: []const PreparedFillLine,
    intersection_storage: []WindingIntersection,
    min_x: i32,
    max_x: i32,
    y: i32,
    fill_rule: FillRule,
    sample_offsets: []const f32,
    coverage_lut: []const u8,
    row_accumulator: *RowAccumulator,
) void {
    if (row_lines.len < 2) return;
    var row_has_coverage = false;
    var row_min_x = max_x;
    var row_max_x = min_x;
    if (row_lines.len == 2) {
        const first = row_lines[0];
        const second = row_lines[1];
        for (sample_offsets) |sample_offset| {
            const py = @as(f32, @floatFromInt(y)) + sample_offset;
            if (py < first.y_min or py >= first.y_max or
                py < second.y_min or py >= second.y_max) continue;
            const first_x = @mulAdd(
                f32,
                first.slope,
                py - first.y_min,
                first.x_at_y_min,
            );
            const second_x = @mulAdd(
                f32,
                second.slope,
                py - second.y_min,
                second.x_at_y_min,
            );
            if (@abs(second_x - first_x) <= 0.000001) continue;
            const start_f, const end_f, const left_delta = if (first_x < second_x)
                .{ first_x, second_x, first.delta }
            else
                .{ second_x, first_x, second.delta };
            if (fill_rule == .even_odd or left_delta != 0) {
                if (row_accumulator.cover(min_x, max_x, sample_offsets, start_f, end_f)) |span| {
                    row_has_coverage = true;
                    row_min_x = @min(row_min_x, span.min_x);
                    row_max_x = @max(row_max_x, span.max_x);
                }
            }
        }
        if (row_has_coverage) {
            row_accumulator.blendAndClear(target, min_x, y, row_min_x, row_max_x, coverage_lut);
        }
        return;
    }
    for (sample_offsets) |sample_offset| {
        const py = @as(f32, @floatFromInt(y)) + sample_offset;
        var intersection_count: usize = 0;
        for (row_lines) |line| {
            if (py < line.y_min or py >= line.y_max) continue;
            const x_intersect = @mulAdd(
                f32,
                line.slope,
                py - line.y_min,
                line.x_at_y_min,
            );
            intersection_storage[intersection_count] = .{
                .x = x_intersect,
                .delta = line.delta,
            };
            intersection_count += 1;
        }
        const intersections = intersection_storage[0..intersection_count];
        if (intersections.len < 2) continue;
        if (intersections.len == 4 and row_lines.len >= 5) {
            insertionSortIntersections(intersections);
        } else {
            sortWindingIntersections(intersections);
        }

        if (intersections.len == 2 and
            intersections[1].x - intersections[0].x > 0.000001)
        {
            if (fill_rule == .even_odd or intersections[0].delta != 0) {
                if (row_accumulator.cover(min_x, max_x, sample_offsets, intersections[0].x, intersections[1].x)) |span| {
                    row_has_coverage = true;
                    row_min_x = @min(row_min_x, span.min_x);
                    row_max_x = @max(row_max_x, span.max_x);
                }
            }
            continue;
        }

        switch (fill_rule) {
            .non_zero => {
                if (intersections.len == 4 and
                    intersections[1].x - intersections[0].x > 0.000001 and
                    intersections[2].x - intersections[1].x > 0.000001 and
                    intersections[3].x - intersections[2].x > 0.000001)
                {
                    // Each edge contributes ±1. The winding after one or three
                    // crossings is therefore odd and cannot be zero; only the
                    // middle span needs a runtime winding test. Because these
                    // spans are already ordered, retain their first and last
                    // covered pixels and merge row bounds only once.
                    var sample_has_coverage = false;
                    var sample_min_x: i32 = undefined;
                    var sample_max_x: i32 = undefined;
                    if (row_accumulator.cover(
                        min_x,
                        max_x,
                        sample_offsets,
                        intersections[0].x,
                        intersections[1].x,
                    )) |span| {
                        sample_has_coverage = true;
                        sample_min_x = span.min_x;
                        sample_max_x = span.max_x;
                    }
                    if (intersections[0].delta == intersections[1].delta) {
                        if (row_accumulator.cover(
                            min_x,
                            max_x,
                            sample_offsets,
                            intersections[1].x,
                            intersections[2].x,
                        )) |span| {
                            if (!sample_has_coverage) sample_min_x = span.min_x;
                            sample_has_coverage = true;
                            sample_max_x = span.max_x;
                        }
                    }
                    if (row_accumulator.cover(
                        min_x,
                        max_x,
                        sample_offsets,
                        intersections[2].x,
                        intersections[3].x,
                    )) |span| {
                        if (!sample_has_coverage) sample_min_x = span.min_x;
                        sample_has_coverage = true;
                        sample_max_x = span.max_x;
                    }
                    if (sample_has_coverage) {
                        row_has_coverage = true;
                        row_min_x = @min(row_min_x, sample_min_x);
                        row_max_x = @max(row_max_x, sample_max_x);
                    }
                    continue;
                }
                var winding: i32 = 0;
                var previous_x: ?f32 = null;
                var index: usize = 0;
                while (index < intersections.len) {
                    const current_x = intersections[index].x;
                    if (previous_x) |start_f| {
                        if (winding != 0) {
                            if (row_accumulator.cover(min_x, max_x, sample_offsets, start_f, current_x)) |span| {
                                row_has_coverage = true;
                                row_min_x = @min(row_min_x, span.min_x);
                                row_max_x = @max(row_max_x, span.max_x);
                            }
                        }
                    }
                    var delta_sum: i32 = 0;
                    // Sorting and finite preparation guarantee a non-negative
                    // difference, so absolute value would duplicate work in
                    // this innermost winding loop.
                    while (index < intersections.len and
                        intersections[index].x - current_x <= 0.000001) : (index += 1)
                    {
                        delta_sum += intersections[index].delta;
                    }
                    winding += delta_sum;
                    previous_x = current_x;
                }
            },
            .even_odd => {
                var pair: usize = 0;
                while (pair + 1 < intersections.len) : (pair += 2) {
                    if (row_accumulator.cover(min_x, max_x, sample_offsets, intersections[pair].x, intersections[pair + 1].x)) |span| {
                        row_has_coverage = true;
                        row_min_x = @min(row_min_x, span.min_x);
                        row_max_x = @max(row_max_x, span.max_x);
                    }
                }
            },
        }
    }
    if (row_has_coverage) {
        row_accumulator.blendAndClear(target, min_x, y, row_min_x, row_max_x, coverage_lut);
    }
}

test "four distinct non-zero crossings preserve nested and disjoint spans" {
    const target = Target{ .width = 8, .height = 1, .pixels = undefined };
    const offsets = [_]f32{ 0.125, 0.375, 0.625, 0.875 };
    const lut = coverageLutForSampleCount(16).?;
    const cases = [_]struct { deltas: [4]i8, disjoint: bool }{
        // Two disjoint contours and one nested, same-direction contour.
        .{ .deltas = .{ 1, -1, 1, -1 }, .disjoint = true },
        .{ .deltas = .{ 1, 1, -1, -1 }, .disjoint = false },
        // Reversed contour direction must produce the same occupied spans.
        .{ .deltas = .{ -1, -1, 1, 1 }, .disjoint = false },
    };
    for (cases) |case| {
        var pixels = [_]u8{0} ** 8;
        var mutable_target = target;
        mutable_target.pixels = &pixels;
        var counts: [512]u8 = undefined;
        var differences: [513]i16 = undefined;
        var accumulator = try RowAccumulator.init(
            std.testing.allocator,
            pixels.len,
            true,
            &counts,
            &differences,
        );
        defer accumulator.deinit(std.testing.allocator);
        var storage: [4]WindingIntersection = undefined;
        const lines = [_]PreparedFillLine{
            .{ .x_at_y_min = 1, .y_min = 0, .y_max = 1, .slope = 0, .delta = case.deltas[0] },
            .{ .x_at_y_min = 2, .y_min = 0, .y_max = 1, .slope = 0, .delta = case.deltas[1] },
            .{ .x_at_y_min = 4, .y_min = 0, .y_max = 1, .slope = 0, .delta = case.deltas[2] },
            .{ .x_at_y_min = 5, .y_min = 0, .y_max = 1, .slope = 0, .delta = case.deltas[3] },
        };
        fillPreparedRow(
            mutable_target,
            &lines,
            &storage,
            0,
            7,
            0,
            .non_zero,
            &offsets,
            lut,
            &accumulator,
        );
        const expected = if (case.disjoint)
            [_]u8{ 0, 255, 0, 0, 255, 0, 0, 0 }
        else
            [_]u8{ 0, 255, 255, 255, 255, 0, 0, 0 };
        try std.testing.expectEqualSlices(u8, &expected, &pixels);
    }
}

pub fn boundsForTarget(target: Target, lines: []const Line) ?Bounds {
    const target_max_x = targetMaxPixelIndex(target.width) orelse return null;
    const target_max_y = targetMaxPixelIndex(target.height) orelse return null;
    // All finite coordinates remain in floating point during the fused edge
    // walk. Convert only the four final extrema; saturating every endpoint
    // duplicated classification and floor/ceil work for no additional safety.
    var raw_min_x = std.math.inf(f32);
    var raw_min_y = std.math.inf(f32);
    var raw_max_x = -std.math.inf(f32);
    var raw_max_y = -std.math.inf(f32);
    var saw_finite_line = false;
    for (lines) |line| {
        if (!lineFinite(line)) continue;
        saw_finite_line = true;
        raw_min_x = @min(raw_min_x, @min(line.a.x, line.b.x));
        raw_min_y = @min(raw_min_y, @min(line.a.y, line.b.y));
        raw_max_x = @max(raw_max_x, @max(line.a.x, line.b.x));
        raw_max_y = @max(raw_max_y, @max(line.a.y, line.b.y));
    }
    if (!saw_finite_line) return null;

    const min_x = @max(0, saturatingSubOne(floorI32Saturating(raw_min_x)));
    const min_y = @max(0, saturatingSubOne(floorI32Saturating(raw_min_y)));
    const max_x = @min(target_max_x, saturatingAddOne(ceilI32Saturating(raw_max_x)));
    const max_y = @min(target_max_y, saturatingAddOne(ceilI32Saturating(raw_max_y)));
    if (max_x < min_x or max_y < min_y) return null;
    return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
}

pub const blendUnchecked = scanline_types.blendUnchecked;

const PreparedLinesAndBounds = struct {
    lines: []PreparedFillLine,
    bounds: ?Bounds,
};

fn prepareFillLinesAndBounds(
    target: Target,
    out: []PreparedFillLine,
    lines: []const Line,
) PreparedLinesAndBounds {
    std.debug.assert(out.len >= lines.len);
    const target_max_x = targetMaxPixelIndex(target.width) orelse
        return .{ .lines = out[0..0], .bounds = null };
    const target_max_y = targetMaxPixelIndex(target.height) orelse
        return .{ .lines = out[0..0], .bounds = null };
    var raw_min_x = std.math.inf(f32);
    var raw_min_y = std.math.inf(f32);
    var raw_max_x = -std.math.inf(f32);
    var raw_max_y = -std.math.inf(f32);
    var count: usize = 0;
    var saw_finite_line = false;
    for (lines) |line| {
        if (!lineFinite(line)) continue;
        saw_finite_line = true;
        raw_min_x = @min(raw_min_x, @min(line.a.x, line.b.x));
        raw_min_y = @min(raw_min_y, @min(line.a.y, line.b.y));
        raw_max_x = @max(raw_max_x, @max(line.a.x, line.b.x));
        raw_max_y = @max(raw_max_y, @max(line.a.y, line.b.y));

        const dy = line.b.y - line.a.y;
        if (dy == 0.0 or !std.math.isFinite(dy)) continue;
        const slope = (line.b.x - line.a.x) / dy;
        // Every evaluated sample lies inside the edge's half-open y range.
        // Finite endpoints, delta-y, and slope therefore guarantee a finite
        // interpolated x; reject extreme arithmetic here once rather than
        // rechecking the result for every edge at every subpixel row.
        if (!std.math.isFinite(slope)) continue;
        out[count] = .{
            .x_at_y_min = if (dy > 0.0) line.a.x else line.b.x,
            .y_min = @min(line.a.y, line.b.y),
            .y_max = @max(line.a.y, line.b.y),
            .slope = slope,
            .delta = if (dy > 0.0) 1 else -1,
        };
        count += 1;
    }
    if (!saw_finite_line) return .{ .lines = out[0..count], .bounds = null };

    const min_x = @max(0, saturatingSubOne(floorI32Saturating(raw_min_x)));
    const min_y = @max(0, saturatingSubOne(floorI32Saturating(raw_min_y)));
    const max_x = @min(target_max_x, saturatingAddOne(ceilI32Saturating(raw_max_x)));
    const max_y = @min(target_max_y, saturatingAddOne(ceilI32Saturating(raw_max_y)));
    const bounds: ?Bounds = if (max_x < min_x or max_y < min_y) null else .{
        .min_x = min_x,
        .min_y = min_y,
        .max_x = max_x,
        .max_y = max_y,
    };
    return .{ .lines = out[0..count], .bounds = bounds };
}

test "combined line preparation preserves public bounds and edges" {
    const target = Target{ .width = 12, .height = 10, .pixels = &.{} };
    const source = [_]Line{
        .{ .a = .{ .x = -2.5, .y = 1.25 }, .b = .{ .x = 4.75, .y = 1.25 } },
        .{ .a = .{ .x = 4.75, .y = 1.25 }, .b = .{ .x = 8.5, .y = 7.75 } },
        .{ .a = .{ .x = std.math.nan(f32), .y = 2 }, .b = .{ .x = 3, .y = 4 } },
        .{ .a = .{ .x = 8.5, .y = 7.75 }, .b = .{ .x = -2.5, .y = 1.25 } },
    };
    var combined_storage: [source.len]PreparedFillLine = undefined;
    var reference_storage: [source.len]PreparedFillLine = undefined;
    const combined = prepareFillLinesAndBounds(target, &combined_storage, &source);
    const reference_lines = prepareFillLines(&reference_storage, &source);

    try std.testing.expectEqual(boundsForTarget(target, &source), combined.bounds);
    try std.testing.expectEqualSlices(PreparedFillLine, reference_lines, combined.lines);
}

test "line preparation rejects non-finite slopes once" {
    const source = [_]Line{.{
        .a = .{ .x = -std.math.floatMax(f32), .y = 0 },
        .b = .{ .x = std.math.floatMax(f32), .y = 1 },
    }};
    var storage: [source.len]PreparedFillLine = undefined;
    try std.testing.expectEqual(
        @as(usize, 0),
        prepareFillLines(&storage, &source).len,
    );
}

test "prepared edge anchors intersections at its lower endpoint" {
    const source = [_]Line{
        .{ .a = .{ .x = 7, .y = 5 }, .b = .{ .x = 3, .y = 1 } },
        .{ .a = .{ .x = 2, .y = 1 }, .b = .{ .x = 6, .y = 5 } },
    };
    var storage: [source.len]PreparedFillLine = undefined;
    const prepared = prepareFillLines(&storage, &source);
    try std.testing.expectEqual(@as(usize, 2), prepared.len);
    try std.testing.expectEqual(@as(f32, 3), prepared[0].x_at_y_min);
    try std.testing.expectEqual(@as(f32, 1), prepared[0].y_min);
    try std.testing.expectEqual(@as(f32, 2), prepared[1].x_at_y_min);
    try std.testing.expectEqual(@as(f32, 1), prepared[1].y_min);
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(PreparedFillLine));
}

pub fn prepareFillLines(out: []PreparedFillLine, lines: []const Line) []PreparedFillLine {
    std.debug.assert(out.len >= lines.len);
    var count: usize = 0;
    for (lines) |line| {
        if (!lineFinite(line)) continue;
        const dy = line.b.y - line.a.y;
        // Horizontal edges never cross the half-open scanline test used by the
        // rasterizer. Dropping them here keeps the hot sample loop focused on
        // candidate edges while preserving the exact winding rule for all rows.
        if (dy == 0.0 or !std.math.isFinite(dy)) continue;
        const slope = (line.b.x - line.a.x) / dy;
        if (!std.math.isFinite(slope)) continue;
        out[count] = .{
            .x_at_y_min = if (dy > 0.0) line.a.x else line.b.x,
            .y_min = @min(line.a.y, line.b.y),
            .y_max = @max(line.a.y, line.b.y),
            .slope = slope,
            .delta = if (dy > 0.0) 1 else -1,
        };
        count += 1;
    }
    return out[0..count];
}

fn lessThanPreparedFillLineYMin(_: void, lhs: PreparedFillLine, rhs: PreparedFillLine) bool {
    return lhs.y_min < rhs.y_min;
}

pub fn sortPreparedFillLinesByYMin(lines: []PreparedFillLine) void {
    if (lines.len <= 128) {
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

const no_fill_line = std.math.maxInt(usize);

fn bucketFillLinesByFirstRow(
    lines: []const PreparedFillLine,
    min_y: i32,
    max_y: i32,
    next_lines: []usize,
    row_heads: []usize,
) void {
    std.debug.assert(next_lines.len >= lines.len);
    std.debug.assert(row_heads.len == @as(usize, @intCast(max_y - min_y + 1)));
    @memset(row_heads, no_fill_line);
    const min_y_f: f32 = @floatFromInt(min_y);
    const max_y_f = @as(f32, @floatFromInt(max_y)) + 1.0;
    for (lines, 0..) |line, line_index| {
        if (line.y_max <= min_y_f or line.y_min >= max_y_f) continue;
        const first_y = std.math.clamp(
            floorI32Saturating(line.y_min),
            min_y,
            max_y,
        );
        const row_index: usize = @intCast(first_y - min_y);
        next_lines[line_index] = row_heads[row_index];
        row_heads[row_index] = line_index;
    }
}

fn updateBucketedActiveFillLines(
    active_storage: []PreparedFillLine,
    active_count: *usize,
    lines: []const PreparedFillLine,
    next_lines: []const usize,
    first_line: usize,
    y: i32,
) []PreparedFillLine {
    std.debug.assert(active_storage.len >= lines.len);
    const row_min_y: f32 = @floatFromInt(y);
    var kept: usize = 0;
    for (active_storage[0..active_count.*]) |line| {
        if (line.y_max <= row_min_y) continue;
        active_storage[kept] = line;
        kept += 1;
    }

    var line_index = first_line;
    while (line_index != no_fill_line) : (line_index = next_lines[line_index]) {
        const line = lines[line_index];
        if (line.y_max <= row_min_y) continue;
        active_storage[kept] = line;
        kept += 1;
    }
    active_count.* = kept;
    return active_storage[0..kept];
}

test "bucketed active edges match sorted active sets" {
    const lines = [_]PreparedFillLine{
        .{ .x_at_y_min = 0, .y_min = -2.5, .y_max = 0.25, .slope = 1, .delta = 1 },
        .{ .x_at_y_min = 1, .y_min = -0.1, .y_max = 2.75, .slope = -1, .delta = -1 },
        .{ .x_at_y_min = 2, .y_min = 0.0, .y_max = 4.0, .slope = 0, .delta = 1 },
        .{ .x_at_y_min = 3, .y_min = 1.9, .y_max = 3.1, .slope = 2, .delta = -1 },
        .{ .x_at_y_min = 4, .y_min = 3.0, .y_max = 8.0, .slope = 0, .delta = 1 },
    };
    const min_y: i32 = 0;
    const max_y: i32 = 3;
    var next_lines: [lines.len]usize = undefined;
    var row_heads: [max_y - min_y + 1]usize = undefined;
    bucketFillLinesByFirstRow(&lines, min_y, max_y, &next_lines, &row_heads);

    var active: [lines.len]PreparedFillLine = undefined;
    var active_count: usize = 0;
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        const active_lines = updateBucketedActiveFillLines(
            &active,
            &active_count,
            &lines,
            &next_lines,
            row_heads[@intCast(y - min_y)],
            y,
        );
        var seen = [_]bool{false} ** lines.len;
        for (active_lines) |active_line| {
            for (lines, 0..) |line, index| {
                if (active_line.x_at_y_min == line.x_at_y_min) seen[index] = true;
            }
        }
        for (lines, 0..) |line, index| {
            const row_min_y: f32 = @floatFromInt(y);
            const expected = line.y_min < row_min_y + 1.0 and line.y_max > row_min_y;
            try std.testing.expectEqual(expected, seen[index]);
        }
    }
}

pub fn updateActiveFillLines(active_storage: []PreparedFillLine, active_count: *usize, sorted_lines: []const PreparedFillLine, next_line: *usize, y: i32) []PreparedFillLine {
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

pub fn sampleOffsetsForAxis(sample_axis: i32) ?[]const f32 {
    return switch (sample_axis) {
        1 => &sample_offsets_1,
        2 => &sample_offsets_2,
        4 => &sample_offsets_4,
        else => null,
    };
}

pub fn coverageLutForSampleCount(sample_count: i32) ?[]const u8 {
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

pub fn fillCoverageLut(lut: *[256]u8, sample_count: i32) void {
    for (lut, 0..) |*coverage, count| {
        const clamped_count = @min(@as(i32, @intCast(count)), sample_count);
        coverage.* = @intCast(@divTrunc(clamped_count * @as(i32, 255), sample_count));
    }
}

fn lessThanWindingIntersection(_: void, lhs: WindingIntersection, rhs: WindingIntersection) bool {
    return lhs.x < rhs.x;
}

pub inline fn sortWindingIntersections(intersections: []WindingIntersection) void {
    switch (intersections.len) {
        0, 1 => return,
        2 => {
            compareSwapIntersections(&intersections[0], &intersections[1]);
            return;
        },
        3 => {
            compareSwapIntersections(&intersections[0], &intersections[1]);
            compareSwapIntersections(&intersections[1], &intersections[2]);
            compareSwapIntersections(&intersections[0], &intersections[1]);
            return;
        },
        4 => {
            compareSwapIntersections(&intersections[0], &intersections[2]);
            compareSwapIntersections(&intersections[1], &intersections[3]);
            compareSwapIntersections(&intersections[0], &intersections[1]);
            compareSwapIntersections(&intersections[2], &intersections[3]);
            compareSwapIntersections(&intersections[1], &intersections[2]);
            return;
        },
        else => {},
    }
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

inline fn insertionSortIntersections(intersections: []WindingIntersection) void {
    var index: usize = 1;
    while (index < intersections.len) : (index += 1) {
        const value = intersections[index];
        var cursor = index;
        while (cursor > 0 and intersections[cursor - 1].x > value.x) : (cursor -= 1) {
            intersections[cursor] = intersections[cursor - 1];
        }
        intersections[cursor] = value;
    }
}

inline fn compareSwapIntersections(a: *WindingIntersection, b: *WindingIntersection) void {
    if (a.x > b.x) {
        const temporary = a.*;
        a.* = b.*;
        b.* = temporary;
    }
}

test "small winding sorting networks preserve ascending intersections" {
    const values = [_]f32{ 4, 1, 3, 2 };
    for (2..values.len + 1) |len| {
        var intersections: [4]WindingIntersection = undefined;
        for (values, 0..) |value, index| {
            intersections[index] = .{ .x = value, .delta = @intCast(index) };
        }
        sortWindingIntersections(intersections[0..len]);
        for (intersections[1..len], intersections[0 .. len - 1]) |current, previous| {
            try std.testing.expect(previous.x <= current.x);
        }
    }

    var coincident = [_]WindingIntersection{
        .{ .x = 3.0, .delta = 1 },
        .{ .x = 1.0, .delta = -1 },
        .{ .x = 1.0 + 0.0000005, .delta = 1 },
        .{ .x = 2.0, .delta = -1 },
    };
    sortWindingIntersections(&coincident);
    try std.testing.expect(coincident[1].x - coincident[0].x <= 0.000001);
}

pub const CoveredSpan = scanline_types.CoveredSpan;

fn coverSpan(coverage_counts: []u8, min_x: i32, max_x: i32, sample_offsets: []const f32, start_f: f32, end_f: f32) ?CoveredSpan {
    if (!std.math.isFinite(start_f) or !std.math.isFinite(end_f)) return null;
    return coverSpanFinite(coverage_counts, min_x, max_x, sample_offsets, start_f, end_f);
}

pub const coverSpanFinite = scanline_types.coverSpanFinite;
const coverPartialPixel4 = scanline_types.coverPartialPixel4;
const coverPartialPixel = scanline_types.coverPartialPixel;

test "four-sample partial coverage matches the generic loop at boundaries" {
    const boundaries = [_]f32{
        -1.0, -0.875, -0.625, -0.375, -0.125,
        0.0,  0.125,  0.375,  0.625,  0.875,
        1.0,  1.125,  1.375,  1.625,  1.875,
        2.0,
    };
    for (boundaries) |start| {
        for (boundaries) |end| {
            if (end < start) continue;
            var generic = [_]u8{0} ** 3;
            var specialized = [_]u8{0} ** 3;
            for (0..generic.len) |index| {
                const x: i32 = @intCast(index);
                coverPartialPixel(&generic, 0, &sample_offsets_4, start, end, x);
                coverPartialPixel4(&specialized, 0, start, end, x);
            }
            try std.testing.expectEqual(generic, specialized);
        }
    }
}

test "finite cover span fast path matches defensive clipping" {
    const boundaries = [_]f32{
        -1.0e30, -2.0,  -0.125, 0.0,   0.125, 0.875,
        1.0,     1.125, 2.0,    2.875, 3.0,   1.0e30,
    };
    for (boundaries) |start| {
        for (boundaries) |end| {
            var defensive = [_]u8{0} ** 3;
            var fast = [_]u8{0} ** 3;
            const defensive_span = coverSpan(&defensive, 0, 2, &sample_offsets_4, start, end);
            const fast_span = coverSpanFinite(&fast, 0, 2, &sample_offsets_4, start, end);
            try std.testing.expectEqual(defensive_span, fast_span);
            try std.testing.expectEqual(defensive, fast);
        }
    }
}

test "covered span excludes the guaranteed-empty end pixel" {
    var counts = [_]u8{0} ** 4;
    try std.testing.expectEqual(
        CoveredSpan{ .min_x = 0, .max_x = 1 },
        coverSpanFinite(&counts, 0, 3, &sample_offsets_4, 0.25, 1.75).?,
    );
    try std.testing.expectEqualSlices(u8, &.{ 3, 3, 0, 0 }, &counts);
}

test "difference accumulation clears the complete dirty span while blending" {
    var pixels = [_]u8{0} ** 4;
    var counts: [512]u8 = undefined;
    var differences: [513]i16 = undefined;
    var accumulator = try RowAccumulator.init(
        std.testing.allocator,
        pixels.len,
        true,
        &counts,
        &differences,
    );
    defer accumulator.deinit(std.testing.allocator);
    _ = accumulator.cover(0, 3, &sample_offsets_4, 0.25, 2.75);
    accumulator.blendAndClear(
        .{ .width = pixels.len, .height = 1, .pixels = &pixels },
        0,
        0,
        0,
        2,
        &coverage_lut_16,
    );
    try std.testing.expectEqualSlices(
        i16,
        &.{ 0, 0, 0, 0, 0 },
        accumulator.differences,
    );
    const first = pixels;

    // Raster compositing is max coverage, so a pre-existing stronger pixel
    // must survive while the parallel target-row traversal is active.
    pixels[1] = 180;
    _ = accumulator.cover(0, 3, &sample_offsets_4, 0.25, 2.75);
    accumulator.blendAndClear(
        .{ .width = pixels.len, .height = 1, .pixels = &pixels },
        0,
        0,
        0,
        2,
        &coverage_lut_16,
    );
    try std.testing.expectEqual(@as(u8, 180), pixels[1]);
    try std.testing.expectEqualSlices(
        i16,
        &.{ 0, 0, 0, 0, 0 },
        accumulator.differences,
    );

    @memset(&pixels, 0);
    _ = accumulator.cover(0, 3, &sample_offsets_4, 0.25, 2.75);
    accumulator.blendAndClear(
        .{ .width = pixels.len, .height = 1, .pixels = &pixels },
        0,
        0,
        0,
        2,
        &coverage_lut_16,
    );
    try std.testing.expectEqual(first, pixels);
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
