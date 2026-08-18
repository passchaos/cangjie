//! TrueType glyph-zone geometry and transient graphics state.
//!
//! This module deliberately owns no allocations.  The glyph executor builds
//! private working copies of the twilight and glyph zones, then presents them
//! here as slices.  Keeping all movement and interpolation behind this
//! boundary makes the interpreter's commit-on-success contract auditable.

const std = @import("std");

const interpolation = @import("interpolation.zig");
const outline = @import("../outline.zig");
const types = @import("../types.zig");

pub const Vector = struct {
    x: i32 = 0x4000,
    y: i32 = 0,

    pub fn axis(y_axis: bool) Vector {
        return if (y_axis)
            .{ .x = 0, .y = 0x4000 }
        else
            .{};
    }

    /// TrueType vectors are normalized signed 2.14 values.  Stack operands
    /// are only specified by their low 16 bits, so sign extension happens
    /// before normalization.
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

/// State reset at the beginning of every font, control-value, or glyph
/// program.  None of these values are retained in the PPEM instance.
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
            .grid => (value +| 32) & ~@as(i32, 63),
            .half_grid => (value & ~@as(i32, 63)) +| 32,
            .double_grid => (value +| 16) & ~@as(i32, 31),
            .down_to_grid => types.floor26Dot6(value),
            .up_to_grid => types.ceil26Dot6(value),
            .super, .super_45 => blk: {
                const period = self.super_round_period;
                if (period <= 0) break :blk value;
                break :blk clampI64(
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

pub const Context = struct {
    twilight: Zone,
    glyph: Zone,
    state: *GraphicsState,
    scale_16_16: i32,

    pub fn validate(self: Context) types.Error!void {
        try self.twilight.validate();
        try self.glyph.validate();
    }

    /// Set the projection or freedom vector from the line joining a point in
    /// zp2 to a point in zp1.  The odd opcode variant rotates the line 90°
    /// counter-clockwise, matching SPVTL/SFVTL.
    pub fn lineVector(
        self: *Context,
        first: usize,
        second: usize,
        perpendicular: bool,
    ) types.Error!Vector {
        const first_point = try self.currentPoint(self.state.zp1, first);
        const second_point = try self.currentPoint(self.state.zp2, second);
        var x = first_point.x -| second_point.x;
        var y = first_point.y -| second_point.y;
        if (x == 0 and y == 0) return .{};
        if (perpendicular) {
            const previous_x = x;
            x = 0 -| y;
            y = previous_x;
        }
        return Vector.normalized(x, y);
    }

    pub fn getCoordinate(
        self: *Context,
        point: usize,
        original: bool,
    ) types.Error!i32 {
        const zone = try self.zoneAt(self.state.zp2);
        if (point >= zone.current.len) return error.InvalidHintOperand;
        const value = if (original) zone.original[point] else zone.current[point];
        return projectPoint(
            value,
            if (original)
                self.state.dual_projection
            else
                self.state.projection,
        );
    }

    pub fn setCoordinate(
        self: *Context,
        point: usize,
        value: i32,
    ) types.Error!void {
        const zone_index = self.state.zp2;
        const current = try self.getCoordinate(point, false);
        try self.move(zone_index, point, value -| current);
        // Microsoft-compatible twilight behavior: SCFS establishes both the
        // current and original position for subsequent interpolation.
        if (zone_index == 0) {
            const zone = try self.zoneAt(0);
            zone.original[point] = zone.current[point];
            zone.unscaled[point] = zone.current[point];
        }
    }

    pub fn measure(
        self: *Context,
        first: usize,
        second: usize,
        current: bool,
    ) types.Error!i32 {
        const first_zone = try self.zoneAt(self.state.zp0);
        const second_zone = try self.zoneAt(self.state.zp1);
        if (first >= first_zone.current.len or
            second >= second_zone.current.len)
        {
            return error.InvalidHintOperand;
        }
        if (current) {
            return projectDifference(
                first_zone.current[first],
                second_zone.current[second],
                self.state.projection,
            );
        }
        return self.originalDistance(
            self.state.zp0,
            first,
            self.state.zp1,
            second,
        );
    }

    pub fn mdap(
        self: *Context,
        point: usize,
        do_round: bool,
    ) types.Error!void {
        const zone_index = self.state.zp0;
        const current = try self.projectedCurrent(zone_index, point);
        const target = if (do_round) self.state.round(current) else current;
        try self.move(zone_index, point, target -| current);
        self.state.rp0 = point;
        self.state.rp1 = point;
    }

    pub fn miap(
        self: *Context,
        point: usize,
        cvt_value: i32,
        do_round: bool,
        retained: types.RetainedGraphicsState,
    ) types.Error!void {
        const zone_index = self.state.zp0;
        if (zone_index == 0) {
            const zone = try self.zoneAt(0);
            if (point >= zone.current.len) return error.InvalidHintOperand;
            const established = pointAlongVector(cvt_value, self.state.freedom);
            zone.original[point] = established;
            zone.unscaled[point] = established;
            zone.current[point] = established;
        }
        const current = try self.projectedCurrent(zone_index, point);
        var target = cvt_value;
        if (do_round) {
            if (zone_index != 0 and
                absDistance(target, current) >
                    retained.control_value_cutin)
            {
                target = current;
            }
            target = self.state.round(target);
        }
        try self.move(zone_index, point, target -| current);
        self.state.rp0 = point;
        self.state.rp1 = point;
    }

    pub fn mdrp(
        self: *Context,
        point: usize,
        opcode: u8,
        retained: types.RetainedGraphicsState,
    ) types.Error!void {
        const old_rp0 = self.state.rp0;
        var original_distance = try self.originalDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            old_rp0,
        );
        original_distance = applySingleWidth(original_distance, retained);
        var target = if ((opcode & 0x04) != 0)
            self.state.round(original_distance)
        else
            original_distance;
        target = applyMinimumDistance(
            target,
            original_distance,
            opcode,
            retained.min_distance,
        );
        const current = try self.currentDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            old_rp0,
        );
        try self.move(self.state.zp1, point, target -| current);
        self.finishRelativeMove(point, old_rp0, opcode);
    }

    pub fn mirp(
        self: *Context,
        point: usize,
        cvt_value: i32,
        opcode: u8,
        retained: types.RetainedGraphicsState,
    ) types.Error!void {
        const old_rp0 = self.state.rp0;
        var target = applySingleWidth(cvt_value, retained);
        if (self.state.zp1 == 0) {
            const reference = try self.originalPoint(
                self.state.zp0,
                old_rp0,
            );
            const offset = pointAlongVector(target, self.state.freedom);
            const established = outline.Point{
                .x = reference.x +| offset.x,
                .y = reference.y +| offset.y,
            };
            const zone = try self.zoneAt(0);
            if (point >= zone.current.len) return error.InvalidHintOperand;
            zone.original[point] = established;
            zone.unscaled[point] = established;
            zone.current[point] = established;
        }
        const original_distance = try self.originalDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            old_rp0,
        );
        if (retained.auto_flip and
            ((original_distance < 0) != (target < 0)))
        {
            target = 0 -| target;
        }
        if ((opcode & 0x04) != 0) {
            if (self.state.zp0 == self.state.zp1 and
                absDistance(target, original_distance) >
                    retained.control_value_cutin)
            {
                target = original_distance;
            }
            target = self.state.round(target);
        }
        target = applyMinimumDistance(
            target,
            original_distance,
            opcode,
            retained.min_distance,
        );
        const current = try self.currentDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            old_rp0,
        );
        try self.move(self.state.zp1, point, target -| current);
        self.finishRelativeMove(point, old_rp0, opcode);
    }

    pub fn alignReference(self: *Context, point: usize) types.Error!void {
        const distance = try self.currentDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            self.state.rp0,
        );
        try self.move(self.state.zp1, point, 0 -| distance);
    }

    pub fn interpolatePoint(self: *Context, point: usize) types.Error!void {
        const rp1_current = try self.currentPoint(
            self.state.zp0,
            self.state.rp1,
        );
        const old_range = self.originalDistance(
            self.state.zp1,
            self.state.rp2,
            self.state.zp0,
            self.state.rp1,
        ) catch 0;
        const current_range = self.currentDistance(
            self.state.zp1,
            self.state.rp2,
            self.state.zp0,
            self.state.rp1,
        ) catch 0;
        const original_distance = try self.originalDistance(
            self.state.zp2,
            point,
            self.state.zp0,
            self.state.rp1,
        );
        const current_distance = projectDifference(
            try self.currentPoint(self.state.zp2, point),
            rp1_current,
            self.state.projection,
        );
        const target = if (original_distance == 0)
            0
        else if (old_range == 0)
            original_distance
        else
            mulDivClamped(
                original_distance,
                current_range,
                old_range,
            );
        try self.move(
            self.state.zp2,
            point,
            target -| current_distance,
        );
    }

    pub fn shiftPixel(
        self: *Context,
        point: usize,
        distance: i32,
    ) types.Error!void {
        const zone = try self.zoneAt(self.state.zp2);
        if (point >= zone.current.len) return error.InvalidHintOperand;
        const delta = pointAlongVector(distance, self.state.freedom);
        zone.current[point].x +|= delta.x;
        zone.current[point].y +|= delta.y;
        touch(&zone.flags[point], self.state.freedom);
    }

    pub fn deltaPoint(self: *Context, point: usize, distance: i32) types.Error!void {
        try self.move(self.state.zp0, point, distance);
    }

    pub fn untouch(self: *Context, point: usize) types.Error!void {
        const zone = try self.zoneAt(self.state.zp0);
        if (point >= zone.flags.len) return error.InvalidHintOperand;
        if (self.state.freedom.x != 0) zone.flags[point].touched_x = false;
        if (self.state.freedom.y != 0) zone.flags[point].touched_y = false;
    }

    pub fn flipPoint(self: *Context, point: usize) types.Error!void {
        const zone = try self.zoneAt(self.state.zp0);
        if (point >= zone.flags.len) return error.InvalidHintOperand;
        zone.flags[point].on_curve = !zone.flags[point].on_curve;
    }

    pub fn setCurveRange(
        self: *Context,
        first: usize,
        last: usize,
        on_curve: bool,
    ) types.Error!void {
        const zone = try self.zoneAt(self.state.zp0);
        if (first > last or last >= zone.flags.len) {
            return error.InvalidHintOperand;
        }
        for (zone.flags[first .. last + 1]) |*flag| {
            flag.on_curve = on_curve;
        }
    }

    /// Interpolate every untouched real point on the requested axis.  Phantom
    /// points are intentionally excluded because they do not belong to a
    /// contour.
    pub fn interpolateUntouched(
        self: *Context,
        x_axis: bool,
    ) types.Error!void {
        const zone = &self.glyph;
        return interpolation.untouched(
            zone.current,
            zone.original,
            zone.unscaled,
            zone.flags,
            zone.contours,
            zone.real_point_count,
            x_axis,
        );
    }

    fn finishRelativeMove(
        self: *Context,
        point: usize,
        old_rp0: usize,
        opcode: u8,
    ) void {
        self.state.rp1 = old_rp0;
        self.state.rp2 = point;
        if ((opcode & 0x10) != 0) self.state.rp0 = point;
    }

    fn projectedCurrent(
        self: *Context,
        zone_index: u8,
        point: usize,
    ) types.Error!i32 {
        const value = try self.currentPoint(zone_index, point);
        return projectPoint(value, self.state.projection);
    }

    fn currentDistance(
        self: *Context,
        first_zone: u8,
        first: usize,
        second_zone: u8,
        second: usize,
    ) types.Error!i32 {
        return projectDifference(
            try self.currentPoint(first_zone, first),
            try self.currentPoint(second_zone, second),
            self.state.projection,
        );
    }

    fn originalDistance(
        self: *Context,
        first_zone: u8,
        first: usize,
        second_zone: u8,
        second: usize,
    ) types.Error!i32 {
        if (first_zone == 1 and second_zone == 1) {
            const first_value = try self.unscaledPoint(first);
            const second_value = try self.unscaledPoint(second);
            return projectDifference(
                .{
                    .x = types.scaleFUnits(
                        first_value.x -| second_value.x,
                        self.scale_16_16,
                    ),
                    .y = types.scaleFUnits(
                        first_value.y -| second_value.y,
                        self.scale_16_16,
                    ),
                },
                .{ .x = 0, .y = 0 },
                self.state.dual_projection,
            );
        }
        return projectDifference(
            try self.originalPoint(first_zone, first),
            try self.originalPoint(second_zone, second),
            self.state.dual_projection,
        );
    }

    fn move(
        self: *Context,
        zone_index: u8,
        point: usize,
        projected_distance: i32,
    ) types.Error!void {
        const zone = try self.zoneAt(zone_index);
        if (point >= zone.current.len) return error.InvalidHintOperand;
        const freedom_dot_projection = vectorDot(
            self.state.freedom,
            self.state.projection,
        );
        if (freedom_dot_projection <= -0x400 or
            freedom_dot_projection >= 0x400)
        {
            zone.current[point].x +|= mulDivClamped(
                projected_distance,
                self.state.freedom.x,
                freedom_dot_projection,
            );
            zone.current[point].y +|= mulDivClamped(
                projected_distance,
                self.state.freedom.y,
                freedom_dot_projection,
            );
        }
        touch(&zone.flags[point], self.state.freedom);
    }

    fn currentPoint(
        self: *Context,
        zone_index: u8,
        point: usize,
    ) types.Error!outline.Point {
        const target = try self.zoneAt(zone_index);
        if (point >= target.current.len) return error.InvalidHintOperand;
        return target.current[point];
    }

    fn originalPoint(
        self: *Context,
        zone_index: u8,
        point: usize,
    ) types.Error!outline.Point {
        const target = try self.zoneAt(zone_index);
        if (point >= target.original.len) return error.InvalidHintOperand;
        return target.original[point];
    }

    fn unscaledPoint(self: *Context, point: usize) types.Error!outline.Point {
        if (point >= self.glyph.unscaled.len) return error.InvalidHintOperand;
        return self.glyph.unscaled[point];
    }

    fn zoneAt(self: *Context, index: u8) types.Error!*Zone {
        return switch (index) {
            0 => &self.twilight,
            1 => &self.glyph,
            else => error.InvalidHintOperand,
        };
    }
};

fn applySingleWidth(
    distance: i32,
    retained: types.RetainedGraphicsState,
) i32 {
    if (retained.single_width_cutin <= 0) return distance;
    const signed_width = if (distance < 0)
        0 -| retained.single_width
    else
        retained.single_width;
    if (absDistance(distance, signed_width) <
        retained.single_width_cutin)
    {
        return signed_width;
    }
    return distance;
}

fn applyMinimumDistance(
    distance: i32,
    original_distance: i32,
    opcode: u8,
    minimum: i32,
) i32 {
    if ((opcode & 0x08) == 0) return distance;
    if (original_distance >= 0) return @max(distance, minimum);
    return @min(distance, 0 -| minimum);
}

fn pointAlongVector(distance: i32, vector: Vector) outline.Point {
    return .{
        .x = mulShift14(distance, vector.x),
        .y = mulShift14(distance, vector.y),
    };
}

fn projectPoint(point: outline.Point, vector: Vector) i32 {
    return dot26Dot6(point.x, point.y, vector);
}

fn projectDifference(
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

fn dot26Dot6(x: i32, y: i32, vector: Vector) i32 {
    const value = @as(i64, x) * vector.x + @as(i64, y) * vector.y;
    return roundShift14(value);
}

fn vectorDot(first: Vector, second: Vector) i32 {
    const value =
        @as(i64, first.x) * second.x + @as(i64, first.y) * second.y;
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

fn absDistance(first: i32, second: i32) i32 {
    const difference = @as(i64, first) - second;
    const magnitude = if (difference < 0) -difference else difference;
    return clampI64(magnitude);
}

fn touch(flag: *outline.PointFlag, freedom: Vector) void {
    if (freedom.x != 0) flag.touched_x = true;
    if (freedom.y != 0) flag.touched_y = true;
}
