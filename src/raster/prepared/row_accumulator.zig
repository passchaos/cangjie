//! Four-by-four prepared-raster row coverage accumulation.
//!
//! Full-pixel spans are stored as range differences and resolved during the
//! required blend pass. Boundary pixels retain the exact sample-center test.

const std = @import("std");
const scanline = @import("../scanline.zig");

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
        inline_counts: *[512]u8,
        inline_differences: *[513]i16,
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
        if (self.differences.len != 0) {
            var coverage: i16 = 0;
            var x = row_min_x;
            while (x <= row_max_x) : (x += 1) {
                coverage += self.differences[@intCast(x - min_x)];
                std.debug.assert(coverage >= 0 and coverage <= 16);
                if (coverage != 0) {
                    scanline.blendUnchecked(
                        target,
                        x,
                        y,
                        coverage_lut[@intCast(coverage)],
                    );
                }
            }
            // Include the sentinel after the final pixel: every interval writes
            // its negative delta there, and leaving it live would contaminate
            // a later row whose dirty range starts farther right.
            @memset(self.differences[clear_start .. clear_end + 1], 0);
            return;
        }
        var x = row_min_x;
        while (x <= row_max_x) : (x += 1) {
            const inside = self.counts[@intCast(x - min_x)];
            if (inside == 0) continue;
            scanline.blendUnchecked(target, x, y, coverage_lut[inside]);
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
    const x_end = if (end64 >= max64)
        max_x
    else
        @as(i32, @intFromFloat(@ceil(end64)));
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
            addPartialDifference4(differences, min_x, start_f, end_f, x);
        }
        addDifference(differences, min_x, full_start, full_end, 4);
        x = full_end + 1;
    }
    while (x <= x_end) : (x += 1) {
        addPartialDifference4(differences, min_x, start_f, end_f, x);
    }
    return .{ .min_x = x_start, .max_x = x_end };
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
