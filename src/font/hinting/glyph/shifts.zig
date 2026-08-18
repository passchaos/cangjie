//! Bulk SHP/SHC/SHZ point displacement over TrueType zones.

const std = @import("std");

const compatibility = @import("compatibility.zig");
const fixed = @import("fixed.zig");
const outline = @import("../outline.zig");
const state = @import("state.zig");
const types = @import("../types.zig");

pub fn pointsByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    policy: compatibility.State,
    use_rp1: bool,
    points: []const usize,
) types.Error!void {
    const reference = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
        policy,
        use_rp1,
    );
    const target = try zoneAt(twilight, glyph, graphics.zp2);
    for (points) |point| {
        if (point >= target.current.len) continue;
        shiftPoint(
            &target.current[point],
            &target.flags[point],
            reference.delta,
            graphics.freedom,
        );
    }
}

pub fn contourByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    policy: compatibility.State,
    use_rp1: bool,
    contour: usize,
) types.Error!void {
    const reference = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
        policy,
        use_rp1,
    );
    const target = try zoneAt(twilight, glyph, graphics.zp2);
    const start, const end = if (graphics.zp2 == 0) blk: {
        if (contour != 0) return error.InvalidHintOperand;
        break :blk .{ @as(usize, 0), target.real_point_count };
    } else blk: {
        if (contour >= target.contours.len) {
            return error.InvalidHintOperand;
        }
        const first = if (contour == 0)
            0
        else
            @as(usize, target.contours[contour - 1]) + 1;
        break :blk .{
            first,
            @as(usize, target.contours[contour]) + 1,
        };
    };
    for (start..end) |point| {
        // FreeType excludes the reference itself when it belongs to the
        // contour being shifted. Moving it would make a subsequent SHC/SHZ
        // observe displacement that did not exist in the source program.
        if (reference.zone == graphics.zp2 and
            reference.point == point)
        {
            continue;
        }
        shiftPoint(
            &target.current[point],
            &target.flags[point],
            reference.delta,
            graphics.freedom,
        );
    }
}

pub fn zoneByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    policy: compatibility.State,
    use_rp1: bool,
    zone_index: u8,
) types.Error!void {
    if (zone_index > 1) return error.InvalidHintOperand;
    const reference = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
        policy,
        use_rp1,
    );
    const target = try zoneAt(twilight, glyph, zone_index);
    const limit = @min(target.real_point_count, target.current.len);
    for (target.current[0..limit], 0..) |*point, point_index| {
        if (reference.zone == zone_index and
            reference.point == point_index)
        {
            continue;
        }
        if (graphics.freedom.x != 0) point.x +|= reference.delta.x;
        if (graphics.freedom.y != 0) point.y +|= reference.delta.y;
    }
}

const ReferenceDisplacement = struct {
    delta: outline.Point,
    zone: u8,
    point: usize,
};

fn referenceDisplacement(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    policy: compatibility.State,
    use_rp1: bool,
) types.Error!ReferenceDisplacement {
    const zone_index = if (use_rp1) graphics.zp0 else graphics.zp1;
    const point_index = if (use_rp1) graphics.rp1 else graphics.rp2;
    const target = try zoneAt(twilight, glyph, zone_index);
    if (point_index >= target.current.len) {
        return error.InvalidHintOperand;
    }
    const projected = fixed.projectDifference(
        target.current[point_index],
        target.original[point_index],
        graphics.projection,
    );
    return .{
        .delta = fixed.compatibleMovement(
            projected,
            graphics.freedom,
            graphics.projection,
            policy,
        ),
        .zone = zone_index,
        .point = point_index,
    };
}

fn zoneAt(
    twilight: *state.Zone,
    glyph: *state.Zone,
    index: u8,
) types.Error!*state.Zone {
    return switch (index) {
        0 => twilight,
        1 => glyph,
        else => error.InvalidHintOperand,
    };
}

fn shiftPoint(
    point: *outline.Point,
    flag: *outline.PointFlag,
    displacement: outline.Point,
    freedom: state.Vector,
) void {
    if (freedom.x != 0) {
        point.x +|= displacement.x;
        flag.touched_x = true;
    }
    if (freedom.y != 0) {
        point.y +|= displacement.y;
        flag.touched_y = true;
    }
}

test "SHC and SHZ leave an in-zone reference point unmoved" {
    var twilight_points = [_]outline.Point{.{ .x = 0, .y = 0 }};
    var twilight_flags = [_]outline.PointFlag{.{}};
    var current = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 64, .y = 0 },
        .{ .x = 100, .y = 0 },
    };
    var original = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
    };
    var unscaled = original;
    var flags = [_]outline.PointFlag{.{}} ** current.len;
    var twilight = state.Zone{
        .current = &twilight_points,
        .original = &twilight_points,
        .unscaled = &twilight_points,
        .flags = &twilight_flags,
        .real_point_count = twilight_points.len,
    };
    var glyph = state.Zone{
        .current = &current,
        .original = &original,
        .unscaled = &unscaled,
        .flags = &flags,
        .contours = &.{2},
        .real_point_count = current.len,
    };
    const graphics = state.GraphicsState{
        .rp2 = 1,
    };
    const policy = compatibility.State{};

    try contourByReference(&twilight, &glyph, &graphics, policy, false, 0);
    try std.testing.expectEqual(@as(i32, 64), current[0].x);
    try std.testing.expectEqual(@as(i32, 64), current[1].x);
    try std.testing.expectEqual(@as(i32, 164), current[2].x);

    current = .{
        .{ .x = 0, .y = 0 },
        .{ .x = 64, .y = 0 },
        .{ .x = 100, .y = 0 },
    };
    try zoneByReference(&twilight, &glyph, &graphics, policy, false, 1);
    try std.testing.expectEqual(@as(i32, 64), current[0].x);
    try std.testing.expectEqual(@as(i32, 64), current[1].x);
    try std.testing.expectEqual(@as(i32, 164), current[2].x);
}
