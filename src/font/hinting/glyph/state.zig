//! Allocation-free TrueType point-zone and per-program graphics state.

const fixed = @import("fixed.zig");
const outline = @import("../outline.zig");
const types = @import("../types.zig");

pub const Vector = fixed.Vector;

/// State reset at the beginning of every font, control-value, or glyph
/// program. None of these values persist in the PPEM instance.
pub const GraphicsState = struct {
    projection: Vector = .{},
    dual_projection: Vector = .{},
    freedom: Vector = .{},
    rp0: usize = 0,
    rp1: usize = 0,
    rp2: usize = 0,
    zp0: u8 = 1,
    zp1: u8 = 1,
    zp2: u8 = 1,
    loop: usize = 1,
    round_mode: types.RoundMode = .grid,
    super_round_period: i32 = 64,
    super_round_phase: i32 = 0,
    super_round_threshold: i32 = 32,

    pub fn round(self: GraphicsState, value: i32) i32 {
        return switch (self.round_mode) {
            .off => value,
            // TrueType distance rounding is symmetric around zero. Applying
            // the positive bit-mask formula directly to negative values
            // rounds ties toward negative infinity; FreeType instead rounds
            // the magnitude and restores the sign. This is observable in
            // compound programs that ROUND a negative inter-component span.
            .grid => roundSigned(value, 64, 32, 0),
            .half_grid => roundSigned(value, 64, 0, 32),
            .double_grid => roundSigned(value, 32, 16, 0),
            // TrueType's RDTG/RUTG round the magnitude and restore the sign;
            // they are not mathematical floor/ceil for negative distances.
            .down_to_grid => if (value >= 0)
                types.floor26Dot6(value)
            else
                0 -| types.floor26Dot6(0 -| value),
            .up_to_grid => if (value >= 0)
                types.ceil26Dot6(value)
            else
                0 -| types.ceil26Dot6(0 -| value),
            .super, .super_45 => blk: {
                const period = self.super_round_period;
                if (period <= 0) break :blk value;
                break :blk fixed.clampI64(
                    @as(i64, @divFloor(
                        value - self.super_round_phase +
                            self.super_round_threshold,
                        period,
                    )) * period + self.super_round_phase,
                );
            },
        };
    }
};

fn roundSigned(value: i32, period: i32, threshold: i32, phase: i32) i32 {
    const magnitude: i64 = if (value < 0)
        -@as(i64, value)
    else
        value;
    const rounded = @divTrunc(
        magnitude + @as(i64, threshold),
        @as(i64, period),
    ) * period + phase;
    return fixed.clampI64(if (value < 0) -rounded else rounded);
}

test "grid rounding is symmetric for negative distances" {
    const std = @import("std");

    var state = GraphicsState{};
    try std.testing.expectEqual(@as(i32, 64), state.round(63));
    try std.testing.expectEqual(@as(i32, -64), state.round(-63));
    try std.testing.expectEqual(@as(i32, 128), state.round(96));
    try std.testing.expectEqual(@as(i32, -128), state.round(-96));

    state.round_mode = .double_grid;
    try std.testing.expectEqual(@as(i32, 32), state.round(16));
    try std.testing.expectEqual(@as(i32, -32), state.round(-16));
}

pub const Zone = struct {
    current: []outline.Point,
    original: []outline.Point,
    unscaled: []outline.Point,
    flags: []outline.PointFlag,
    contours: []const u16 = &.{},
    real_point_count: usize,

    pub fn validate(self: Zone) types.Error!void {
        if (self.current.len != self.original.len or
            self.current.len != self.unscaled.len or
            self.current.len != self.flags.len or
            self.real_point_count > self.current.len)
        {
            return error.InvalidHintOperand;
        }
    }
};
