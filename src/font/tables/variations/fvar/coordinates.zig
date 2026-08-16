//! Caller-supplied fvar coordinate validation and normalization helpers.

const std = @import("std");
const types = @import("types.zig");

pub const Error = error{BadSfnt};

pub fn validate(
    axes: []const types.Axis,
    coordinates: []const types.Coordinate,
) Error!void {
    for (coordinates, 0..) |coordinate, coordinate_index| {
        // Coordinate tags are a source-level caller contract, not merely table
        // data. Rejecting unknown/duplicate tags prevents first-match ordering
        // and spelling mistakes such as `WGHT` from becoming silent defaults.
        if (!std.math.isFinite(coordinate.value)) return error.BadSfnt;
        if (axisIndex(axes, coordinate.tag) == null) return error.BadSfnt;
        for (coordinates[0..coordinate_index]) |previous| {
            if (std.mem.eql(u8, &previous.tag, &coordinate.tag)) {
                return error.BadSfnt;
            }
        }
    }
}

pub fn valueForAxis(
    axis: types.Axis,
    coordinates: []const types.Coordinate,
) ?f32 {
    for (coordinates) |coordinate| {
        if (std.mem.eql(u8, &axis.tag, &coordinate.tag)) {
            return coordinate.value;
        }
    }
    return null;
}

pub fn quantizeNormalized(value: f32) f32 {
    // HarfBuzz's public design-coordinate path first rounds normalized
    // fvar/avar output to 16.16 and then to F2Dot14. A direct 14-bit rounding
    // differs at values such as 0.1 and can shift gvar phantom metrics across
    // a half-unit boundary.
    const fixed_16_16: i32 = @intFromFloat(@round(value * 65536.0));
    const fixed_2_14: i16 = @intCast((fixed_16_16 + 2) >> 2);
    return @as(f32, @floatFromInt(fixed_2_14)) / 16384.0;
}

fn axisIndex(axes: []const types.Axis, tag: [4]u8) ?usize {
    for (axes, 0..) |axis, index| {
        if (std.mem.eql(u8, &axis.tag, &tag)) return index;
    }
    return null;
}
