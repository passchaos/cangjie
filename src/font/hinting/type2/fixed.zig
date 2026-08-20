//! FreeType-compatible signed 16.16 arithmetic used by the Type2 hint map.
//!
//! CFF hint placement is sensitive to the intermediate rounding performed by
//! FreeType's fixed-point helpers. Keeping these operations here prevents the
//! map from accidentally depending on host floating-point contraction rules.

const std = @import("std");

pub const Fixed = struct {
    bits: i32 = 0,

    pub const zero: Fixed = .{};
    pub const one: Fixed = .{ .bits = 1 << 16 };
    pub const min: Fixed = .{ .bits = std.math.minInt(i32) };
    pub const max: Fixed = .{ .bits = std.math.maxInt(i32) };

    pub fn fromBits(bits: i32) Fixed {
        return .{ .bits = bits };
    }

    pub fn fromInt(value: i32) Fixed {
        return .{ .bits = value *% (1 << 16) };
    }

    pub fn fromF32(value: f32) Fixed {
        if (std.math.isNan(value)) return .zero;
        if (value >= 32768.0) return .max;
        if (value <= -32768.0) return .min;
        const scaled = @as(f64, value) * 65536.0;
        return .{ .bits = @intFromFloat(@round(scaled)) };
    }

    pub fn toF32(self: Fixed) f32 {
        return @as(f32, @floatFromInt(self.bits)) / 65536.0;
    }

    pub fn add(self: Fixed, other: Fixed) Fixed {
        return .{ .bits = self.bits +% other.bits };
    }

    pub fn sub(self: Fixed, other: Fixed) Fixed {
        return .{ .bits = self.bits -% other.bits };
    }

    pub fn neg(self: Fixed) Fixed {
        return .{ .bits = -%self.bits };
    }

    pub fn abs(self: Fixed) Fixed {
        return .{ .bits = if (self.bits < 0) -%self.bits else self.bits };
    }

    pub fn mul(self: Fixed, other: Fixed) Fixed {
        const product = @as(i64, self.bits) * @as(i64, other.bits);
        const correction: i64 = 0x8000 - @as(i64, @intFromBool(product < 0));
        return .{ .bits = @truncate((product + correction) >> 16) };
    }

    pub fn div(self: Fixed, other: Fixed) Fixed {
        const negative = (self.bits < 0) != (other.bits < 0);
        const numerator: u64 = @abs(@as(i64, self.bits));
        const denominator: u64 = @abs(@as(i64, other.bits));
        const quotient: u64 = if (denominator == 0)
            std.math.maxInt(i32)
        else
            ((numerator << 16) + (denominator >> 1)) / denominator;
        const bits: i32 = @bitCast(@as(u32, @truncate(quotient)));
        return .{ .bits = if (negative) -%bits else bits };
    }

    pub fn mulDiv(self: Fixed, numerator: Fixed, denominator: Fixed) Fixed {
        var negative = false;
        var a: u64 = @bitCast(@as(i64, self.bits));
        var b: u64 = @bitCast(@as(i64, numerator.bits));
        var c: u64 = @bitCast(@as(i64, denominator.bits));
        if (self.bits < 0) {
            a = 0 -% a;
            negative = !negative;
        }
        if (numerator.bits < 0) {
            b = 0 -% b;
            negative = !negative;
        }
        if (denominator.bits < 0) {
            c = 0 -% c;
            negative = !negative;
        }
        const quotient: u64 = if (c == 0)
            std.math.maxInt(i32)
        else
            (a *% b +% (c >> 1)) / c;
        const bits: i32 = @bitCast(@as(u32, @truncate(quotient)));
        return .{ .bits = if (negative) -%bits else bits };
    }

    pub fn round(self: Fixed) Fixed {
        return .{ .bits = (self.bits +% 0x8000) & ~@as(i32, 0xffff) };
    }

    pub fn fract(self: Fixed) Fixed {
        return .{ .bits = self.bits -% (self.bits & ~@as(i32, 0xffff)) };
    }

    pub fn lessThan(self: Fixed, other: Fixed) bool {
        return self.bits < other.bits;
    }

    pub fn lessOrEqual(self: Fixed, other: Fixed) bool {
        return self.bits <= other.bits;
    }

    pub fn minValue(self: Fixed, other: Fixed) Fixed {
        return if (self.bits < other.bits) self else other;
    }

    pub fn maxValue(self: Fixed, other: Fixed) Fixed {
        return if (self.bits > other.bits) self else other;
    }
};

test "Type2 fixed arithmetic matches 16.16 rounding contracts" {
    try std.testing.expectEqual(@as(i32, 0x8000), Fixed.fromF32(0.5).bits);
    try std.testing.expectEqual(@as(i32, -0x8000), Fixed.fromF32(-0.5).bits);
    try std.testing.expectEqual(@as(i32, 0x10000), Fixed.fromF32(0.5).mul(Fixed.fromInt(2)).bits);
    try std.testing.expectEqual(@as(i32, 0x8000), Fixed.fromInt(1).div(Fixed.fromInt(2)).bits);
}
