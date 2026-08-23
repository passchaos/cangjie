//! Shared four-by-four scanline row coverage accumulation.
//!
//! Full-pixel spans are stored as range differences and resolved during the
//! required blend pass. Boundary pixels retain the exact sample-center test.

const std = @import("std");
const scanline = @import("scanline_types.zig");

pub const Target = scanline.Target;

pub const RowAccumulator = struct {
    counts: []u8,
    differences: []i16,
    counts_owned: bool = false,
    differences_owned: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        row_width: usize,
        use_differences: bool,
        inline_counts: []u8,
        inline_differences: []i16,
    ) !RowAccumulator {
        if (use_differences) {
            const needed = row_width + 1;
            const differences = if (needed <= inline_differences.len)
                inline_differences[0..needed]
            else
                try allocator.alloc(i16, needed);
            @memset(differences, 0);
            return .{
                .counts = &.{},
                .differences = differences,
                .differences_owned = needed > inline_differences.len,
            };
        }
        const counts = if (row_width <= inline_counts.len)
            inline_counts[0..row_width]
        else
            try allocator.alloc(u8, row_width);
        @memset(counts, 0);
        return .{
            .counts = counts,
            .differences = &.{},
            .counts_owned = row_width > inline_counts.len,
        };
    }

    pub fn deinit(self: *RowAccumulator, allocator: std.mem.Allocator) void {
        if (self.differences_owned) allocator.free(self.differences);
        if (self.counts_owned) allocator.free(self.counts);
    }

    pub inline fn cover(
        self: *RowAccumulator,
        min_x: i32,
        max_x: i32,
        sample_offsets: []const f32,
        start_f: f32,
        end_f: f32,
    ) ?scanline.CoveredSpan {
        if (self.differences.len != 0) {
            return coverSpanDifference4(
                self.differences,
                min_x,
                max_x,
                start_f,
                end_f,
            );
        }
        return scanline.coverSpanFinite(
            self.counts,
            min_x,
            max_x,
            sample_offsets,
            start_f,
            end_f,
        );
    }

    pub fn blendAndClear(
        self: *RowAccumulator,
        target: Target,
        min_x: i32,
        y: i32,
        row_min_x: i32,
        row_max_x: i32,
        coverage_lut: []const u8,
    ) void {
        const clear_start: usize = @intCast(row_min_x - min_x);
        const clear_end: usize = @intCast(row_max_x - min_x + 1);
        const target_start = @as(usize, @intCast(y)) * target.width +
            @as(usize, @intCast(row_min_x));
        const pixels = target.pixels[target_start .. target_start + clear_end - clear_start];
        if (self.differences.len != 0) {
            var coverage: i16 = 0;
            const differences = self.differences[clear_start..clear_end];
            for (differences, pixels) |*difference, *pixel| {
                coverage += difference.*;
                difference.* = 0;
                std.debug.assert(coverage >= 0 and coverage <= 16);
                if (coverage != 0) {
                    pixel.* = @max(pixel.*, coverage_lut[@intCast(coverage)]);
                }
            }
            // Include the sentinel after the final pixel: every interval writes
            // its negative delta there, and leaving it live would contaminate
            // a later row whose dirty range starts farther right.
            self.differences[clear_end] = 0;
            return;
        }
        for (self.counts[clear_start..clear_end], pixels) |inside, *pixel| {
            if (inside == 0) continue;
            pixel.* = @max(pixel.*, coverage_lut[inside]);
        }
        @memset(self.counts[clear_start..clear_end], 0);
    }
};

inline fn coverSpanDifference4(
    differences: []i16,
    min_x: i32,
    max_x: i32,
    start_f: f32,
    end_f: f32,
) ?scanline.CoveredSpan {
    std.debug.assert(std.math.isFinite(start_f) and std.math.isFinite(end_f));
    // Up to this coordinate every 1/8-pixel sample center is exactly
    // representable by f32, matching the scalar predicates below. Convert the
    // covered sample-center interval once per endpoint instead of rounding both
    // endpoints twice and testing four boundary centers.
    if (min_x >= 0 and max_x <= 1_048_575) {
        return coverSpanDifference4QuarterSamples(
            differences,
            min_x,
            max_x,
            start_f,
            end_f,
        );
    }
    return coverSpanDifference4Wide(
        differences,
        min_x,
        max_x,
        start_f,
        end_f,
    );
}

inline fn coverSpanDifference4QuarterSamples(
    differences: []i16,
    min_x: i32,
    max_x: i32,
    start_f: f32,
    end_f: f32,
) ?scanline.CoveredSpan {
    const min_f: f32 = @floatFromInt(min_x);
    const max_after_f = @as(f32, @floatFromInt(max_x)) + 1.0;
    if (end_f <= start_f or end_f <= min_f or start_f >= max_after_f) {
        return null;
    }
    const min_sample = min_x * 4;
    const max_sample = (max_x + 1) * 4;
    const first: i32 = if (start_f <= min_f)
        min_sample
    else
        @intFromFloat(@ceil(start_f * 4.0 - 0.5));
    const after: i32 = if (end_f >= max_after_f)
        max_sample
    else
        @intFromFloat(@ceil(end_f * 4.0 - 0.5));
    if (after <= first) return null;

    // The guarded target has min_x >= 0, and endpoint clipping therefore
    // guarantees both sample indexes are non-negative. Express quotient and
    // remainder in that domain so codegen uses shifts/masks rather than signed
    // division's negative-value correction sequence.
    const first_sample: u32 = @intCast(first);
    const after_sample: u32 = @intCast(after);
    const x_start: i32 = @intCast(first_sample >> 2);
    const x_end: i32 = @intCast((after_sample - 1) >> 2);
    if (x_start == x_end) {
        addDifference(
            differences,
            min_x,
            x_start,
            x_start,
            @intCast(after - first),
        );
        return .{ .min_x = x_start, .max_x = x_end };
    }

    const first_offset: i16 = @intCast(first_sample & 3);
    const after_offset: i16 = @intCast(after_sample & 3);
    var full_start = x_start;
    var full_end = x_end;
    if (first_offset != 0) {
        addDifference(
            differences,
            min_x,
            x_start,
            x_start,
            4 - first_offset,
        );
        full_start += 1;
    }
    if (after_offset != 0) {
        addDifference(
            differences,
            min_x,
            x_end,
            x_end,
            after_offset,
        );
        full_end -= 1;
    }
    if (full_start <= full_end) {
        addDifference(differences, min_x, full_start, full_end, 4);
    }
    return .{ .min_x = x_start, .max_x = x_end };
}

noinline fn coverSpanDifference4Wide(
    differences: []i16,
    min_x: i32,
    max_x: i32,
    start_f: f32,
    end_f: f32,
) ?scanline.CoveredSpan {
    const start64: f64 = start_f;
    const end64: f64 = end_f;
    const min64: f64 = @floatFromInt(min_x);
    const max64: f64 = @floatFromInt(max_x);
    if (end64 <= start64 or end64 <= min64 or start64 >= max64 + 1.0) {
        return null;
    }
    const x_start = if (start64 <= min64)
        min_x
    else
        @as(i32, @intFromFloat(@floor(start64)));
    // Sample centers are strictly below each pixel's right edge, so the pixel
    // beginning at ceil(end) can never receive coverage. This matches the
    // legacy count accumulator and avoids one empty boundary update per span.
    const x_end = if (end64 >= max64 + 1.0)
        max_x
    else
        @as(i32, @intFromFloat(@ceil(end64))) - 1;
    const full_start = if (start64 <= min64)
        min_x
    else
        @as(i32, @intFromFloat(@ceil(start64)));
    const full_end = if (end64 >= max64 + 1.0)
        max_x
    else
        @as(i32, @intFromFloat(@floor(end64))) - 1;

    var x = x_start;
    if (full_start <= full_end) {
        while (x < full_start) : (x += 1) {
            addLeftPartialDifference4(differences, min_x, start_f, x);
        }
        addDifference(differences, min_x, full_start, full_end, 4);
        x = full_end + 1;
        while (x <= x_end) : (x += 1) {
            addRightPartialDifference4(differences, min_x, end_f, x);
        }
    } else {
        // A subpixel interval with no completely covered pixel still needs
        // both endpoint predicates; this path spans at most two pixels.
        while (x <= x_end) : (x += 1) {
            addPartialDifference4(differences, min_x, start_f, end_f, x);
        }
    }
    return .{ .min_x = x_start, .max_x = x_end };
}

test "difference span excludes the guaranteed-empty end pixel" {
    var differences = [_]i16{0} ** 5;
    try std.testing.expectEqual(
        scanline.CoveredSpan{ .min_x = 0, .max_x = 1 },
        coverSpanDifference4(&differences, 0, 3, 0.25, 1.75).?,
    );
}

test "difference span matches sample-count accumulation at boundaries" {
    const boundaries = [_]f32{
        -1.0,  -0.876, -0.875, -0.874, -0.625, -0.375, -0.125,
        0.0,   0.124,  0.125,  0.126,  0.374,  0.375,  0.376,
        0.625, 0.875,  1.0,    1.125,  1.375,  1.625,  1.875,
        2.0,   3.0,    1.0e30,
    };
    const offsets = [_]f32{ 0.125, 0.375, 0.625, 0.875 };
    for (boundaries) |start| {
        for (boundaries) |end| {
            var expected = [_]u8{0} ** 3;
            var differences = [_]i16{0} ** 4;
            _ = scanline.coverSpanFinite(
                &expected,
                0,
                2,
                &offsets,
                start,
                end,
            );
            _ = coverSpanDifference4(
                &differences,
                0,
                2,
                start,
                end,
            );
            var running: i16 = 0;
            for (expected, differences[0..3]) |count, difference| {
                running += difference;
                try std.testing.expectEqual(@as(i16, count), running);
            }
        }
    }
}

inline fn addLeftPartialDifference4(
    differences: []i16,
    min_x: i32,
    start_f: f32,
    x: i32,
) void {
    const base: f32 = @floatFromInt(x);
    var count: i16 = 0;
    count += @intFromBool(base + 0.125 >= start_f);
    count += @intFromBool(base + 0.375 >= start_f);
    count += @intFromBool(base + 0.625 >= start_f);
    count += @intFromBool(base + 0.875 >= start_f);
    if (count != 0) addDifference(differences, min_x, x, x, count);
}

inline fn addRightPartialDifference4(
    differences: []i16,
    min_x: i32,
    end_f: f32,
    x: i32,
) void {
    const base: f32 = @floatFromInt(x);
    var count: i16 = 0;
    count += @intFromBool(base + 0.125 < end_f);
    count += @intFromBool(base + 0.375 < end_f);
    count += @intFromBool(base + 0.625 < end_f);
    count += @intFromBool(base + 0.875 < end_f);
    if (count != 0) addDifference(differences, min_x, x, x, count);
}

inline fn addPartialDifference4(
    differences: []i16,
    min_x: i32,
    start_f: f32,
    end_f: f32,
    x: i32,
) void {
    const base: f32 = @floatFromInt(x);
    var count: i16 = 0;
    count += @intFromBool(base + 0.125 >= start_f and base + 0.125 < end_f);
    count += @intFromBool(base + 0.375 >= start_f and base + 0.375 < end_f);
    count += @intFromBool(base + 0.625 >= start_f and base + 0.625 < end_f);
    count += @intFromBool(base + 0.875 >= start_f and base + 0.875 < end_f);
    if (count != 0) addDifference(differences, min_x, x, x, count);
}

inline fn addDifference(
    differences: []i16,
    min_x: i32,
    start: i32,
    end: i32,
    count: i16,
) void {
    const first: usize = @intCast(start - min_x);
    const after: usize = @intCast(end - min_x + 1);
    differences[first] += count;
    differences[after] -= count;
}
