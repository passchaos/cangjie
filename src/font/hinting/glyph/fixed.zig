//! Fixed-point vector math shared by TrueType point-zone operations.

const std = @import("std");

const compatibility = @import("compatibility.zig");
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
    if (vector.y == 0 and
        (vector.x == 0x4000 or vector.x == -0x4000))
    {
        return .{
            .x = if (vector.x > 0) distance else 0 -| distance,
            .y = 0,
        };
    }
    if (vector.x == 0 and
        (vector.y == 0x4000 or vector.y == -0x4000))
    {
        return .{
            .x = 0,
            .y = if (vector.y > 0) distance else 0 -| distance,
        };
    }
    return .{
        .x = mulShift14(distance, vector.x),
        .y = mulShift14(distance, vector.y),
    };
}

pub fn projectPoint(point: outline.Point, vector: Vector) i32 {
    if (vector.y == 0) {
        if (vector.x == 0x4000) return point.x;
        if (vector.x == -0x4000) return 0 -| point.x;
    }
    if (vector.x == 0) {
        if (vector.y == 0x4000) return point.y;
        if (vector.y == -0x4000) return 0 -| point.y;
    }
    return dot26Dot6(point.x, point.y, vector);
}

pub fn projectDifference(
    first: outline.Point,
    second: outline.Point,
    vector: Vector,
) i32 {
    if (vector.y == 0) {
        if (vector.x == 0x4000) return first.x -| second.x;
        if (vector.x == -0x4000) return second.x -| first.x;
    }
    if (vector.x == 0) {
        if (vector.y == 0x4000) return first.y -| second.y;
        if (vector.y == -0x4000) return second.y -| first.y;
    }
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

/// Convert projected distance into an XY move along the freedom vector.
///
/// The TrueType interpreter first quantizes `freedom / dot(projection,
/// freedom)` to a signed 16.16 move vector, then multiplies the requested
/// 26.6 distance by that vector. Combining those operations into one rational
/// multiply changes non-axis-aligned moves by a 26.6 unit.
pub fn movementAlongFreedom(
    distance: i32,
    freedom: Vector,
    projection: Vector,
) outline.Point {
    const dot_product =
        @as(i64, projection.x) * freedom.x +
        @as(i64, projection.y) * freedom.y;
    // FreeType's Compute_Funcs uses this exact positive rounding phase.
    const dot = clampI64((dot_product + 0x2000) >> 14);
    const move_x, const move_y = if (dot >= 0x3ffe)
        .{
            clampI64(@as(i64, freedom.x) * 4),
            clampI64(@as(i64, freedom.y) * 4),
        }
    else if (dot > -0x400 and dot < 0x400)
        .{ @as(i32, 0), @as(i32, 0) }
    else
        .{
            clampI64(@divTrunc(
                @as(i64, freedom.x) * 0x10000,
                @as(i64, dot),
            )),
            clampI64(@divTrunc(
                @as(i64, freedom.y) * 0x10000,
                @as(i64, dot),
            )),
        };
    return .{
        .x = mulFix16Clamped(distance, move_x),
        .y = mulFix16Clamped(distance, move_y),
    };
}

pub fn compatibleMovement(
    distance: i32,
    freedom: Vector,
    projection: Vector,
    policy: compatibility.State,
) outline.Point {
    // The vast majority of TrueType moves use one of the four signed axis
    // pairs selected by SVTCA/SPVTCA/SFVTCA. Preserve the generic staged
    // 16.16 calculation for diagonal vectors, but avoid it when projection
    // and freedom already make the result exact.
    if (freedom.y == 0 and projection.y == 0 and
        (freedom.x == 0x4000 or freedom.x == -0x4000) and
        (projection.x == 0x4000 or projection.x == -0x4000))
    {
        return .{
            .x = if (policy.active())
                0
            else if (freedom.x == projection.x)
                distance
            else
                0 -| distance,
            .y = 0,
        };
    }
    if (freedom.x == 0 and projection.x == 0 and
        (freedom.y == 0x4000 or freedom.y == -0x4000) and
        (projection.y == 0x4000 or projection.y == -0x4000))
    {
        return .{
            .x = 0,
            .y = if (policy.postIup())
                0
            else if (freedom.y == projection.y)
                distance
            else
                0 -| distance,
        };
    }
    var result = movementAlongFreedom(distance, freedom, projection);
    const axes = policy.directAxes(freedom);
    if (!axes.x) result.x = 0;
    if (!axes.y) result.y = 0;
    return result;
}

pub fn mulDivClamped(a: i32, b: i32, denominator: i32) i32 {
    if (denominator == 0) return 0;
    const product = @as(i64, a) * b;
    const divisor: i64 = denominator;
    const product_magnitude: u64 =
        @intCast(if (product < 0) -product else product);
    const divisor_magnitude: u64 =
        @intCast(if (divisor < 0) -divisor else divisor);
    const quotient: i64 = @intCast(
        (product_magnitude + (divisor_magnitude >> 1)) /
            divisor_magnitude,
    );
    return clampI64(
        if ((product < 0) != (divisor < 0))
            -quotient
        else
            quotient,
    );
}

/// Divide into a signed 16.16 ratio with FreeType/TrueType nearest rounding.
///
/// IUP intentionally computes its scale first and then multiplies by that
/// quantized scale. Collapsing the two operations into one rational multiply
/// changes deployed outlines by one 26.6 unit.
pub fn divFix16Clamped(numerator: i32, denominator: i32) i32 {
    return mulDivClamped(numerator, 0x10000, denominator);
}

pub fn mulFix16Clamped(value: i32, factor: i32) i32 {
    return mulDivClamped(value, factor, 0x10000);
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

test "fixed multiply divide rounds signed results to nearest" {
    try std.testing.expectEqual(@as(i32, 2), mulDivClamped(1, 3, 2));
    try std.testing.expectEqual(@as(i32, -2), mulDivClamped(-1, 3, 2));
    try std.testing.expectEqual(
        @as(i32, 0x18000),
        divFix16Clamped(3, 2),
    );
    try std.testing.expectEqual(
        @as(i32, -2),
        mulFix16Clamped(-3, 0x8000),
    );
}

test "projected movement preserves staged 16.16 vector quantization" {
    const moved = movementAlongFreedom(
        -193,
        .{ .x = 13421, .y = 9397 },
        .{ .x = -16322, .y = 1428 },
    );
    try std.testing.expectEqual(
        outline.Point{ .x = 206, .y = 144 },
        moved,
    );
}
