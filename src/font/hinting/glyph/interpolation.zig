//! TrueType IUP contour interpolation.
//!
//! IUP works in one coordinate dimension at a time and excludes phantom
//! points.  Keeping the wrap-around contour algorithm separate avoids mixing
//! topological interpolation with general projection and movement mechanics.

const std = @import("std");

const outline = @import("../outline.zig");
const types = @import("../types.zig");

pub fn untouched(
    current: []outline.Point,
    original: []const outline.Point,
    unscaled: []const outline.Point,
    flags: []const outline.PointFlag,
    contours: []const u16,
    real_point_count: usize,
    x_axis: bool,
) types.Error!void {
    if (current.len != original.len or
        current.len != unscaled.len or
        current.len != flags.len or
        real_point_count > current.len)
    {
        return error.InvalidHintOperand;
    }
    if (contours.len == 0) return;
    var contour_start: usize = 0;
    for (contours) |end_value| {
        const contour_end: usize = end_value;
        if (contour_end < contour_start or
            contour_end >= real_point_count)
        {
            return error.InvalidHintOperand;
        }
        try interpolateContour(
            current,
            original,
            unscaled,
            flags,
            contour_start,
            contour_end,
            x_axis,
        );
        contour_start = contour_end + 1;
    }
    if (contour_start != real_point_count) {
        return error.InvalidHintOperand;
    }
}

fn interpolateContour(
    current: []outline.Point,
    original: []const outline.Point,
    unscaled: []const outline.Point,
    flags: []const outline.PointFlag,
    start: usize,
    end: usize,
    x_axis: bool,
) types.Error!void {
    var first_touched: ?usize = null;
    var index = start;
    while (index <= end) : (index += 1) {
        if (isTouched(flags[index], x_axis)) {
            first_touched = index;
            break;
        }
    }
    const first = first_touched orelse return;
    var previous = first;
    index = first + 1;
    while (index <= end) : (index += 1) {
        if (!isTouched(flags[index], x_axis)) continue;
        try interpolateRange(
            current,
            original,
            unscaled,
            previous + 1,
            index - 1,
            previous,
            index,
            x_axis,
        );
        previous = index;
    }
    if (previous == first) {
        const delta = coordinate(current[first], x_axis) -|
            coordinate(original[first], x_axis);
        for (start..end + 1) |point| {
            if (point == first) continue;
            setCoordinate(
                &current[point],
                x_axis,
                coordinate(original[point], x_axis) +| delta,
            );
        }
        return;
    }
    try interpolateRange(
        current,
        original,
        unscaled,
        previous + 1,
        end,
        previous,
        first,
        x_axis,
    );
    if (first > start) {
        try interpolateRange(
            current,
            original,
            unscaled,
            start,
            first - 1,
            previous,
            first,
            x_axis,
        );
    }
}

fn interpolateRange(
    current: []outline.Point,
    original: []const outline.Point,
    unscaled: []const outline.Point,
    start: usize,
    end: usize,
    first_ref: usize,
    second_ref: usize,
    x_axis: bool,
) types.Error!void {
    if (start > end) return;
    if (first_ref >= current.len or second_ref >= current.len) {
        return error.InvalidHintOperand;
    }
    var low_ref = first_ref;
    var high_ref = second_ref;
    var low_unscaled = coordinate(unscaled[low_ref], x_axis);
    var high_unscaled = coordinate(unscaled[high_ref], x_axis);
    if (low_unscaled > high_unscaled) {
        std.mem.swap(usize, &low_ref, &high_ref);
        std.mem.swap(i32, &low_unscaled, &high_unscaled);
    }
    const low_original = coordinate(original[low_ref], x_axis);
    const high_original = coordinate(original[high_ref], x_axis);
    const low_current = coordinate(current[low_ref], x_axis);
    const high_current = coordinate(current[high_ref], x_axis);
    const low_delta = low_current -| low_original;
    const high_delta = high_current -| high_original;

    for (start..end + 1) |point| {
        const original_value = coordinate(original[point], x_axis);
        const result = if (original_value <= low_original)
            original_value +| low_delta
        else if (original_value >= high_original)
            original_value +| high_delta
        else if (low_unscaled == high_unscaled or low_current == high_current)
            low_current
        else
            low_current +| mulDivClamped(
                coordinate(unscaled[point], x_axis) -| low_unscaled,
                high_current -| low_current,
                high_unscaled -| low_unscaled,
            );
        setCoordinate(&current[point], x_axis, result);
    }
}

fn mulDivClamped(a: i32, b: i32, denominator: i32) i32 {
    if (denominator == 0) return 0;
    return clampI64(@divTrunc(
        @as(i64, a) * b,
        @as(i64, denominator),
    ));
}

fn clampI64(value: i64) i32 {
    if (value <= std.math.minInt(i32)) return std.math.minInt(i32);
    if (value >= std.math.maxInt(i32)) return std.math.maxInt(i32);
    return @intCast(value);
}

fn isTouched(flag: outline.PointFlag, x_axis: bool) bool {
    return if (x_axis) flag.touched_x else flag.touched_y;
}

fn coordinate(point: outline.Point, x_axis: bool) i32 {
    return if (x_axis) point.x else point.y;
}

fn setCoordinate(point: *outline.Point, x_axis: bool, value: i32) void {
    if (x_axis) {
        point.x = value;
    } else {
        point.y = value;
    }
}

test "IUP shifts and interpolates untouched contour points" {
    var current = [_]outline.Point{
        .{ .x = 64, .y = 0 },
        .{ .x = 100, .y = 0 },
        .{ .x = 264, .y = 0 },
    };
    const original = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
        .{ .x = 200, .y = 0 },
    };
    const flags = [_]outline.PointFlag{
        .{ .touched_x = true },
        .{},
        .{ .touched_x = true },
    };
    try untouched(
        &current,
        &original,
        &original,
        &flags,
        &.{2},
        3,
        true,
    );
    try std.testing.expectEqual(@as(i32, 164), current[1].x);
}
