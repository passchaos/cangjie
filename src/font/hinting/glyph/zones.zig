//! TrueType glyph-zone geometry and transient graphics state.
//!
//! This module deliberately owns no allocations.  The glyph executor builds
//! private working copies of the twilight and glyph zones, then presents them
//! here as slices.  Keeping all movement and interpolation behind this
//! boundary makes the interpreter's commit-on-success contract auditable.

const std = @import("std");

const compatibility = @import("compatibility.zig");
const fixed = @import("fixed.zig");
const interpolation = @import("interpolation.zig");
const shifts = @import("shifts.zig");
const state = @import("state.zig");
const outline = @import("../outline.zig");
const types = @import("../types.zig");

pub const Vector = fixed.Vector;
pub const GraphicsState = state.GraphicsState;
pub const Zone = state.Zone;

pub const Context = struct {
    // The VM owns these descriptors. Borrow them rather than copying all six
    // slices every time an opcode asks for point-zone access.
    twilight: *Zone,
    glyph: *Zone,
    state: *GraphicsState,
    compatibility: *compatibility.State,
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
        // Stem-control programs commonly derive perfectly horizontal or
        // vertical vectors from points. Their normalized 2.14 values are
        // exact, so avoid floating-point sqrt/division on this hot path.
        if (y == 0) return .{
            .x = if (x > 0) 0x4000 else -0x4000,
            .y = 0,
        };
        if (x == 0) return .{
            .x = 0,
            .y = if (y > 0) 0x4000 else -0x4000,
        };
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
        return fixed.projectPoint(
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
            return fixed.projectDifference(
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
            const established = fixed.pointAlongVector(cvt_value, self.state.freedom);
            zone.original[point] = established;
            zone.unscaled[point] = established;
            zone.current[point] = established;
        }
        const current = try self.projectedCurrent(zone_index, point);
        var target = cvt_value;
        if (do_round) {
            if (zone_index != 0 and
                fixed.absDistance(target, current) >
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
            const offset = fixed.pointAlongVector(target, self.state.freedom);
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
                fixed.absDistance(target, original_distance) >
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

    pub fn moveStackIndirectRelative(
        self: *Context,
        point: usize,
        distance: i32,
        set_rp0: bool,
    ) types.Error!void {
        const old_rp0 = self.state.rp0;
        if (self.state.zp1 == 0) {
            const reference = try self.originalPoint(
                self.state.zp0,
                old_rp0,
            );
            const offset = fixed.pointAlongVector(distance, self.state.freedom);
            const established = outline.Point{
                .x = reference.x +| offset.x,
                .y = reference.y +| offset.y,
            };
            const twilight = try self.zoneAt(0);
            if (point >= twilight.current.len) {
                return error.InvalidHintOperand;
            }
            twilight.original[point] = established;
            twilight.unscaled[point] = established;
            twilight.current[point] = established;
        }
        const current = try self.currentDistance(
            self.state.zp1,
            point,
            self.state.zp0,
            old_rp0,
        );
        try self.move(self.state.zp1, point, distance -| current);
        self.state.rp1 = old_rp0;
        self.state.rp2 = point;
        if (set_rp0) self.state.rp0 = point;
    }

    pub fn interpolatePoint(self: *Context, point: usize) types.Error!void {
        const rp1_current = try self.currentPoint(
            self.state.zp0,
            self.state.rp1,
        );
        // IP uses unscaled outline coordinates whenever all three zone
        // pointers address the glyph zone. Scaling both distances first is
        // mathematically equivalent over reals, but not after 26.6 rounding:
        // deployed fonts can differ by one unit. If any pointer addresses
        // twilight, the interpreter instead uses the original 26.6 arrays.
        const use_unscaled =
            self.state.zp0 != 0 and
            self.state.zp1 != 0 and
            self.state.zp2 != 0;
        const old_range = self.interpolationOriginalDistance(
            self.state.zp1,
            self.state.rp2,
            self.state.zp0,
            self.state.rp1,
            use_unscaled,
        ) catch 0;
        const current_range = self.currentDistance(
            self.state.zp1,
            self.state.rp2,
            self.state.zp0,
            self.state.rp1,
        ) catch 0;
        const original_distance = try self.interpolationOriginalDistance(
            self.state.zp2,
            point,
            self.state.zp0,
            self.state.rp1,
            use_unscaled,
        );
        const current_distance = fixed.projectDifference(
            try self.currentPoint(self.state.zp2, point),
            rp1_current,
            self.state.projection,
        );
        const target = if (original_distance == 0)
            0
        else if (old_range == 0)
            original_distance
        else
            fixed.mulDivClamped(
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
        const delta = fixed.pointAlongVector(distance, self.state.freedom);
        const allowed = self.compatibility.allowShiftPixel(
            self.state.*,
            zone.flags[point].touched_y,
        );
        if (allowed) {
            // v40 compatibility always suppresses SHPIX's X component.
            if (!self.compatibility.active()) {
                zone.current[point].x +|= delta.x;
            }
            if (self.compatibility.directAxes(self.state.freedom).y) {
                zone.current[point].y +|= delta.y;
            }
            touch(&zone.flags[point], self.state.freedom);
        }
    }

    pub fn shiftPointsByReference(
        self: *Context,
        use_rp1: bool,
        points: []const usize,
    ) types.Error!void {
        return shifts.pointsByReference(
            self.twilight,
            self.glyph,
            self.state,
            self.compatibility.*,
            use_rp1,
            points,
        );
    }

    pub fn shiftContourByReference(
        self: *Context,
        use_rp1: bool,
        contour: usize,
    ) types.Error!void {
        return shifts.contourByReference(
            self.twilight,
            self.glyph,
            self.state,
            self.compatibility.*,
            use_rp1,
            contour,
        );
    }

    pub fn shiftZoneByReference(
        self: *Context,
        use_rp1: bool,
        zone_index: u8,
    ) types.Error!void {
        return shifts.zoneByReference(
            self.twilight,
            self.glyph,
            self.state,
            self.compatibility.*,
            use_rp1,
            zone_index,
        );
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
        if (point >= self.glyph.flags.len) return error.InvalidHintOperand;
        self.glyph.flags[point].on_curve =
            !self.glyph.flags[point].on_curve;
    }

    pub fn setCurveRange(
        self: *Context,
        first: usize,
        last: usize,
        on_curve: bool,
    ) types.Error!void {
        if (first > last or last >= self.glyph.flags.len) {
            return error.InvalidHintOperand;
        }
        for (self.glyph.flags[first .. last + 1]) |*flag| {
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
        const zone = self.glyph;
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
        return fixed.projectPoint(value, self.state.projection);
    }

    fn currentDistance(
        self: *Context,
        first_zone: u8,
        first: usize,
        second_zone: u8,
        second: usize,
    ) types.Error!i32 {
        return fixed.projectDifference(
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
            return fixed.projectDifference(
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
        return fixed.projectDifference(
            try self.originalPoint(first_zone, first),
            try self.originalPoint(second_zone, second),
            self.state.dual_projection,
        );
    }

    fn interpolationOriginalDistance(
        self: *Context,
        first_zone: u8,
        first: usize,
        second_zone: u8,
        second: usize,
        use_unscaled: bool,
    ) types.Error!i32 {
        if (use_unscaled) {
            std.debug.assert(first_zone == 1 and second_zone == 1);
            return fixed.projectDifference(
                try self.unscaledPoint(first),
                try self.unscaledPoint(second),
                self.state.dual_projection,
            );
        }
        return fixed.projectDifference(
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
        const delta = fixed.compatibleMovement(
            projected_distance,
            self.state.freedom,
            self.state.projection,
            self.compatibility.*,
        );
        zone.current[point].x +|= delta.x;
        zone.current[point].y +|= delta.y;
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
            0 => self.twilight,
            1 => self.glyph,
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
    if (fixed.absDistance(distance, signed_width) <
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

fn touch(flag: *outline.PointFlag, freedom: Vector) void {
    if (freedom.x != 0) flag.touched_x = true;
    if (freedom.y != 0) flag.touched_y = true;
}

test "IP derives glyph-zone ratios from unscaled coordinates" {
    var current = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = 5, .y = 0 },
    };
    var original = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = 2, .y = 0 },
    };
    var unscaled = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 0 },
        .{ .x = 3, .y = 0 },
    };
    var flags = [_]outline.PointFlag{.{}} ** 3;
    var twilight_points = [_]outline.Point{};
    var twilight_flags = [_]outline.PointFlag{};
    var graphics = GraphicsState{
        .rp1 = 0,
        .rp2 = 2,
    };
    var compatibility_state = compatibility.State{};
    var twilight = Zone{
        .current = &twilight_points,
        .original = &twilight_points,
        .unscaled = &twilight_points,
        .flags = &twilight_flags,
        .real_point_count = twilight_points.len,
    };
    var glyph = Zone{
        .current = &current,
        .original = &original,
        .unscaled = &unscaled,
        .flags = &flags,
        .contours = &.{2},
        .real_point_count = current.len,
    };
    var context = Context{
        .twilight = &twilight,
        .glyph = &glyph,
        .state = &graphics,
        .compatibility = &compatibility_state,
        .scale_16_16 = 0x10000,
    };

    // Unscaled interpolation yields round(1 * 5 / 3) = 2. Reusing the
    // independently rounded original 26.6 coordinates would yield 3.
    try context.interpolatePoint(1);
    try std.testing.expectEqual(@as(i32, 2), current[1].x);
}
