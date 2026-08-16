//! Numeric contracts shared by outline materialization and varied metrics.

const std = @import("std");

/// OpenType variation arithmetic rounds half-unit ties toward positive
/// infinity. Zig's `@round` instead rounds ties away from zero, which differs
/// for negative coordinates and metric deltas.
pub fn roundOpenType(value: f32) f32 {
    return @floor(value + 0.5);
}

pub fn clampF32ToU16(value: f32) u16 {
    if (value <= 0) return 0;
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(u16)))) {
        return std.math.maxInt(u16);
    }
    return @intFromFloat(value);
}

pub fn clampF32ToI16(value: f32) i16 {
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i16)))) {
        return std.math.minInt(i16);
    }
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i16)))) {
        return std.math.maxInt(i16);
    }
    return @intFromFloat(value);
}

pub fn clampI32ToU16(value: i32) u16 {
    if (value <= 0) return 0;
    if (value >= std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(value);
}

pub fn clampI32ToI16(value: i32) i16 {
    if (value <= std.math.minInt(i16)) return std.math.minInt(i16);
    if (value >= std.math.maxInt(i16)) return std.math.maxInt(i16);
    return @intCast(value);
}

/// AAT outline callbacks use ordinary nearest-integer glyph positions rather
/// than OpenType variation tie handling.
pub fn roundedGlyphPosition(value: f32) i32 {
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i32)))) {
        return std.math.minInt(i32);
    }
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i32)))) {
        return std.math.maxInt(i32);
    }
    return @intFromFloat(@round(value));
}
