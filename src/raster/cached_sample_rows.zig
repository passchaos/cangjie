//! Fixed-storage sample intersections for the repeated direct-outline cache.
//!
//! Unlike prepared glyph coverage, this cache retains geometry only. Every
//! draw still rebuilds horizontal spans, applies the fill rule, accumulates
//! coverage, and blends the target. The fixed limits make construction
//! infallible and let unusual outlines fall back to prepared-edge scanning.
const std = @import("std");
const RowAccumulator = @import("row_accumulator.zig").RowAccumulator;
const scanline = @import("scanline.zig");

const sample_offsets_4 = [_]f32{ 0.125, 0.375, 0.625, 0.875 };
const max_pixel_rows = 128;
const max_sample_rows = max_pixel_rows * sample_offsets_4.len;
const max_intersections = 2048;

const Row = struct {
    start: u16,
    len: u16,
};

pub const Cache = struct {
    valid: bool = false,
    min_y: i32 = 0,
    row_count: usize = 0,
    intersection_count: usize = 0,
    rows: [max_sample_rows]Row = undefined,
    intersections: [max_intersections]scanline.WindingIntersection = undefined,

    /// Build sorted intersections for the default four vertical sample lanes.
    /// Capacity overflow simply disables this optional layer; the caller still
    /// retains its sorted prepared edges and can scan those normally.
    pub fn build(
        self: *Cache,
        prepared_lines: []const scanline.PreparedFillLine,
        bounds: ?scanline.Bounds,
    ) void {
        self.valid = false;
        const clipped = bounds orelse return;
        if (prepared_lines.len < 2 or prepared_lines.len > 128) return;
        const pixel_row_count_i64 = @as(i64, clipped.max_y) - clipped.min_y + 1;
        if (pixel_row_count_i64 <= 0 or pixel_row_count_i64 > max_pixel_rows) return;
        const pixel_row_count: usize = @intCast(pixel_row_count_i64);

        var active: [128]scanline.PreparedFillLine = undefined;
        var row_intersections: [128]scanline.WindingIntersection = undefined;
        var next_line: usize = 0;
        var active_count: usize = 0;
        var output_count: usize = 0;
        for (0..pixel_row_count) |row_index| {
            const y = clipped.min_y + @as(i32, @intCast(row_index));
            const row_lines = scanline.updateActiveFillLines(
                &active,
                &active_count,
                prepared_lines,
                &next_line,
                y,
            );
            inline for (sample_offsets_4, 0..) |offset, sample_index| {
                const py = @as(f32, @floatFromInt(y)) + offset;
                var count: usize = 0;
                for (row_lines) |line| {
                    if (py < line.y_min or py >= line.y_max) continue;
                    row_intersections[count] = .{
                        .x = @mulAdd(
                            f32,
                            line.slope,
                            py - line.y_min,
                            line.x_at_y_min,
                        ),
                        .delta = line.delta,
                    };
                    count += 1;
                }
                if (output_count + count > self.intersections.len) return;
                scanline.sortWindingIntersections(
                    row_intersections[0..count],
                );
                self.rows[row_index * 4 + sample_index] = .{
                    .start = @intCast(output_count),
                    .len = @intCast(count),
                };
                @memcpy(
                    self.intersections[output_count..][0..count],
                    row_intersections[0..count],
                );
                output_count += count;
            }
        }
        self.min_y = clipped.min_y;
        self.row_count = pixel_row_count * 4;
        self.intersection_count = output_count;
        self.valid = true;
    }

    /// Fill from immutable sorted intersections. Returns false when this
    /// optional cache declined construction, allowing prepared-edge fallback.
    pub fn fill(
        self: *const Cache,
        allocator: std.mem.Allocator,
        target: scanline.Target,
        bounds: ?scanline.Bounds,
        fill_rule: scanline.FillRule,
    ) !bool {
        if (!self.valid) return false;
        const clipped = bounds orelse return true;
        std.debug.assert(clipped.min_y == self.min_y);
        std.debug.assert(
            self.row_count ==
                @as(usize, @intCast(clipped.max_y - clipped.min_y + 1)) * 4,
        );

        const row_width_i32 = clipped.max_x - clipped.min_x + 1;
        if (row_width_i32 <= 0) return true;
        const row_width: usize = @intCast(row_width_i32);
        var inline_counts: [512]u8 = undefined;
        var inline_differences: [129]i16 = undefined;
        var accumulator = try RowAccumulator.init(
            allocator,
            row_width,
            true,
            &inline_counts,
            &inline_differences,
        );
        defer accumulator.deinit(allocator);
        const coverage_lut = scanline.coverageLutForSampleCount(16).?;

        var y = clipped.min_y;
        while (y <= clipped.max_y) : (y += 1) {
            const row_index: usize = @intCast(y - self.min_y);
            var row_has_coverage = false;
            var row_min_x = clipped.max_x;
            var row_max_x = clipped.min_x;
            inline for (0..4) |sample_index| {
                const row = self.rows[row_index * 4 + sample_index];
                const start: usize = row.start;
                coverIntersections(
                    self.intersections[start .. start + row.len],
                    fill_rule,
                    clipped.min_x,
                    clipped.max_x,
                    &accumulator,
                    &row_has_coverage,
                    &row_min_x,
                    &row_max_x,
                );
            }
            if (row_has_coverage) {
                accumulator.blendAndClear(
                    target,
                    clipped.min_x,
                    y,
                    row_min_x,
                    row_max_x,
                    coverage_lut,
                );
            }
        }
        return true;
    }
};

test "cached sample rows match prepared-edge scan" {
    const source = [_]scanline.Line{
        .{ .a = .{ .x = 1.25, .y = 1.25 }, .b = .{ .x = 7.75, .y = 1.25 } },
        .{ .a = .{ .x = 7.75, .y = 1.25 }, .b = .{ .x = 7.75, .y = 7.75 } },
        .{ .a = .{ .x = 7.75, .y = 7.75 }, .b = .{ .x = 1.25, .y = 7.75 } },
        .{ .a = .{ .x = 1.25, .y = 7.75 }, .b = .{ .x = 1.25, .y = 1.25 } },
        .{ .a = .{ .x = 3.0, .y = 3.0 }, .b = .{ .x = 3.0, .y = 6.0 } },
        .{ .a = .{ .x = 3.0, .y = 6.0 }, .b = .{ .x = 6.0, .y = 6.0 } },
        .{ .a = .{ .x = 6.0, .y = 6.0 }, .b = .{ .x = 6.0, .y = 3.0 } },
        .{ .a = .{ .x = 6.0, .y = 3.0 }, .b = .{ .x = 3.0, .y = 3.0 } },
    };
    var prepared_storage: [source.len]scanline.PreparedFillLine = undefined;
    const prepared = scanline.prepareFillLines(&prepared_storage, &source);
    scanline.sortPreparedFillLinesByYMin(prepared);
    const target_template = scanline.Target{
        .width = 10,
        .height = 10,
        .pixels = undefined,
    };
    const bounds = scanline.boundsForTarget(target_template, &source);
    var cache = Cache{};
    cache.build(prepared, bounds);
    try std.testing.expect(cache.valid);

    inline for (.{ scanline.FillRule.non_zero, scanline.FillRule.even_odd }) |fill_rule| {
        var expected = [_]u8{0} ** 100;
        var actual = [_]u8{0} ** 100;
        var expected_target = target_template;
        expected_target.pixels = &expected;
        var actual_target = target_template;
        actual_target.pixels = &actual;
        try scanline.fillPreparedSorted(
            std.testing.allocator,
            expected_target,
            prepared,
            bounds,
            fill_rule,
            4,
        );
        try std.testing.expect(try cache.fill(
            std.testing.allocator,
            actual_target,
            bounds,
            fill_rule,
        ));
        try std.testing.expectEqualSlices(u8, &expected, &actual);
    }
}

inline fn coverIntersections(
    intersections: []const scanline.WindingIntersection,
    fill_rule: scanline.FillRule,
    min_x: i32,
    max_x: i32,
    accumulator: *RowAccumulator,
    row_has_coverage: *bool,
    row_min_x: *i32,
    row_max_x: *i32,
) void {
    if (intersections.len < 2) return;
    if (intersections.len == 2 and
        intersections[1].x - intersections[0].x > 0.000001)
    {
        if (fill_rule == .even_odd or intersections[0].delta != 0) {
            coverSpan(
                accumulator,
                min_x,
                max_x,
                intersections[0].x,
                intersections[1].x,
                row_has_coverage,
                row_min_x,
                row_max_x,
            );
        }
        return;
    }

    switch (fill_rule) {
        .non_zero => {
            if (intersections.len == 4 and
                intersections[1].x - intersections[0].x > 0.000001 and
                intersections[2].x - intersections[1].x > 0.000001 and
                intersections[3].x - intersections[2].x > 0.000001)
            {
                coverSpan(
                    accumulator,
                    min_x,
                    max_x,
                    intersections[0].x,
                    intersections[1].x,
                    row_has_coverage,
                    row_min_x,
                    row_max_x,
                );
                if (intersections[0].delta == intersections[1].delta) {
                    coverSpan(
                        accumulator,
                        min_x,
                        max_x,
                        intersections[1].x,
                        intersections[2].x,
                        row_has_coverage,
                        row_min_x,
                        row_max_x,
                    );
                }
                coverSpan(
                    accumulator,
                    min_x,
                    max_x,
                    intersections[2].x,
                    intersections[3].x,
                    row_has_coverage,
                    row_min_x,
                    row_max_x,
                );
                return;
            }
            var winding: i32 = 0;
            var previous_x: ?f32 = null;
            var index: usize = 0;
            while (index < intersections.len) {
                const current_x = intersections[index].x;
                if (previous_x) |start_x| {
                    if (winding != 0) {
                        coverSpan(
                            accumulator,
                            min_x,
                            max_x,
                            start_x,
                            current_x,
                            row_has_coverage,
                            row_min_x,
                            row_max_x,
                        );
                    }
                }
                var delta_sum: i32 = 0;
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
                coverSpan(
                    accumulator,
                    min_x,
                    max_x,
                    intersections[pair].x,
                    intersections[pair + 1].x,
                    row_has_coverage,
                    row_min_x,
                    row_max_x,
                );
            }
        },
    }
}

inline fn coverSpan(
    accumulator: *RowAccumulator,
    min_x: i32,
    max_x: i32,
    start_x: f32,
    end_x: f32,
    row_has_coverage: *bool,
    row_min_x: *i32,
    row_max_x: *i32,
) void {
    if (accumulator.cover(
        min_x,
        max_x,
        &sample_offsets_4,
        start_x,
        end_x,
    )) |span| {
        row_has_coverage.* = true;
        row_min_x.* = @min(row_min_x.*, span.min_x);
        row_max_x.* = @max(row_max_x.*, span.max_x);
    }
}
