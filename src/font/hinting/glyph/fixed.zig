//! Fixed-point vector math shared by TrueType point-zone operations.

const std = @import("std");

const outline = @import("../outline.zig");

pub const Vector = struct {
    x: i32 = 0x4000,
    y: i32 = 0,

    pub fn axis(y_axis: bool) Vector {
        return if (y_axis)
            .{ .x = 0, .y = 0x4000 }
        else
            .{};
    }

    /// Normalize signed stack operands to a TrueType signed 2.14 vector.
    pub fn normalized(raw_x: i32, raw_y: i32) Vector {
        const x: i16 = @truncate(raw_x);
        const y: i16 = @truncate(raw_y);
        if (x == 0 and y == 0) return .{};
        const xf: f64 = @floatFromInt(x);
        const yf: f64 = @floatFromInt(y);
        const length = @sqrt(xf * xf + yf * yf);
        const nx: i32 = @intFromFloat(@round(xf * 16384.0 / length));
        const ny: i32 = @intFromFloat(@round(yf * 16384.0 / length));
        return .{
            .x = std.math.clamp(nx, -0x4000, 0x4000),
            .y = std.math.clamp(ny, -0x4000, 0x4000),
        };
    }
};

pub fn pointAlongVector(distance: i32, vector: Vector) outline.Point {
    return .{
        .x = mulShift14(distance, vector.x),
        .y = mulShift14(distance, vector.y),
    };
}

pub fn projectPoint(point: outline.Point, vector: Vector) i32 {
    return dot26Dot6(point.x, point.y, vector);
}

pub fn projectDifference(
    first: outline.Point,
    second: outline.Point,
    vector: Vector,
) i32 {
    return dot26Dot6(
        first.x -| second.x,
        first.y -| second.y,
        vector,
    );
}

pub fn vectorDot(first: Vector, second: Vector) i32 {
    const value =
        @as(i64, first.x) * second.x + @as(i64, first.y) * second.y;
    return roundShift14(value);
}

pub fn mulDivClamped(a: i32, b: i32, denominator: i32) i32 {
    if (denominator == 0) return 0;
    return clampI64(@divTrunc(
        @as(i64, a) * b,
        @as(i64, denominator),
    ));
}

pub fn clampI64(value: i64) i32 {
    if (value <= std.math.minInt(i32)) return std.math.minInt(i32);
    if (value >= std.math.maxInt(i32)) return std.math.maxInt(i32);
    return @intCast(value);
}

pub fn absDistance(first: i32, second: i32) i32 {
    const difference = @as(i64, first) - second;
    const magnitude = if (difference < 0) -difference else difference;
    return clampI64(magnitude);
}

fn dot26Dot6(x: i32, y: i32, vector: Vector) i32 {
    const value = @as(i64, x) * vector.x + @as(i64, y) * vector.y;
    return roundShift14(value);
}

fn mulShift14(value: i32, factor: i32) i32 {
    return roundShift14(@as(i64, value) * factor);
}

fn roundShift14(value: i64) i32 {
    const magnitude: u64 = @intCast(if (value < 0) -value else value);
    const rounded: i64 = @intCast((magnitude + 0x2000) >> 14);
    return clampI64(if (value < 0) -rounded else rounded);
}
