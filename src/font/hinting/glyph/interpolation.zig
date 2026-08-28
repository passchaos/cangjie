//! TrueType IUP contour interpolation.
//!
//! IUP works in one coordinate dimension at a time and excludes phantom
//! points.  Keeping the wrap-around contour algorithm separate avoids mixing
//! topological interpolation with general projection and movement mechanics.

const std = @import("std");

const fixed = @import("fixed.zig");
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
    coordinates_are_scaled: bool,
) types.Error!void {
    if (current.len != original.len or
        current.len != unscaled.len or
        current.len != flags.len or
        real_point_count > current.len)
    {
        return error.InvalidHintOperand;
    }
    if (contours.len == 0) return;
    return if (x_axis)
        untouchedAxis(current, original, unscaled, flags, contours, real_point_count, true, coordinates_are_scaled)
    else
        untouchedAxis(current, original, unscaled, flags, contours, real_point_count, false, coordinates_are_scaled);
}

fn untouchedAxis(
    current: []outline.Point,
    original: []const outline.Point,
    unscaled: []const outline.Point,
    flags: []const outline.PointFlag,
    contours: []const u16,
    real_point_count: usize,
    comptime x_axis: bool,
    coordinates_are_scaled: bool,
) types.Error!void {
    var contour_start: usize = 0;
    for (contours) |end_value| {
        const contour_end: usize = end_value;
        if (contour_end < contour_start or
            contour_end >= real_point_count)
        {
            return error.InvalidHintOperand;
        }
        interpolateContour(
            current,
            original,
            unscaled,
            flags,
            contour_start,
            contour_end,
            x_axis,
            coordinates_are_scaled,
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
    comptime x_axis: bool,
    coordinates_are_scaled: bool,
) void {
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
        interpolateRange(
            current,
            original,
            unscaled,
            previous + 1,
            index - 1,
            previous,
            index,
            x_axis,
            coordinates_are_scaled,
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
    interpolateRange(
        current,
        original,
        unscaled,
        previous + 1,
        end,
        previous,
        first,
        x_axis,
        coordinates_are_scaled,
    );
    if (first > start) {
        interpolateRange(
            current,
            original,
            unscaled,
            start,
            first - 1,
            previous,
            first,
            x_axis,
            coordinates_are_scaled,
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
    comptime x_axis: bool,
    coordinates_are_scaled: bool,
) void {
    if (start > end) return;
    // `untouchedAxis` obtains both references from a contour that it has
    // already bounded against `real_point_count`, which is no greater than the
    // three coordinate slice lengths. Keep that proof outside this hot loop.
    std.debug.assert(first_ref < current.len and second_ref < current.len);
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
    // Compound programs execute after child hinting with unity projection
    // scaling. FreeType's parent zone copies the placed device coordinates
    // into both `org` and `orus`, so use `original` for its ratio domain.
    // Simple programs retain design-space `orus` coordinates instead.
    const low_ratio = if (coordinates_are_scaled) low_original else low_unscaled;
    const high_ratio = if (coordinates_are_scaled) high_original else high_unscaled;
    const scale = if (low_ratio == high_ratio)
        0
    else
        fixed.divFix16Clamped(
            high_current -| low_current,
            high_ratio -| low_ratio,
        );

    for (start..end + 1) |point| {
        const original_value = coordinate(original[point], x_axis);
        const result = if (original_value <= low_original)
            original_value +| low_delta
        else if (original_value >= high_original)
            original_value +| high_delta
        else if (low_ratio == high_ratio or low_current == high_current)
            low_current
        else
            low_current +| fixed.mulFix16Clamped(
                coordinate(
                    if (coordinates_are_scaled)
                        original[point]
                    else
                        unscaled[point],
                    x_axis,
                ) -| low_ratio,
                scale,
            );
        setCoordinate(&current[point], x_axis, result);
    }
}

fn isTouched(flag: outline.PointFlag, comptime x_axis: bool) bool {
    return if (x_axis) flag.touched_x else flag.touched_y;
}

fn coordinate(point: outline.Point, comptime x_axis: bool) i32 {
    return if (x_axis) point.x else point.y;
}

fn setCoordinate(
    point: *outline.Point,
    comptime x_axis: bool,
    value: i32,
) void {
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
        false,
    );
    try std.testing.expectEqual(@as(i32, 164), current[1].x);
}

test "compound IUP interpolates in original scaled coordinates" {
    var current = [_]outline.Point{
        .{ .x = 64, .y = 0 },
        .{ .x = 190, .y = 0 },
        .{ .x = 320, .y = 0 },
    };
    const original = [_]outline.Point{
        .{ .x = 64, .y = 0 },
        .{ .x = 190, .y = 0 },
        .{ .x = 256, .y = 0 },
    };
    const unscaled = [_]outline.Point{
        .{ .x = -817, .y = 0 },
        .{ .x = -418, .y = 0 },
        .{ .x = -207, .y = 0 },
    };
    const flags = [_]outline.PointFlag{
        .{ .touched_x = true },
        .{},
        .{ .touched_x = true },
    };
    try untouched(
        &current,
        &original,
        &unscaled,
        &flags,
        &.{2},
        3,
        true,
        true,
    );
    try std.testing.expectEqual(@as(i32, 232), current[1].x);
}
