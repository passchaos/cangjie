//! Multi-point TrueType geometry instructions.
//!
//! ISECT, ALIGNPTS, and SDPVTL combine several zones and therefore do not fit
//! the single-point movement helpers in `zones.zig`. Keeping them here makes
//! their zone-pointer and projection contracts explicit.

const fixed = @import("fixed.zig");
const outline = @import("../outline.zig");
const state = @import("state.zig");
const types = @import("../types.zig");

pub fn alignPoints(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    first: usize,
    second: usize,
) types.Error!void {
    const first_zone = try zoneAt(twilight, glyph, graphics.zp1);
    const second_zone = try zoneAt(twilight, glyph, graphics.zp0);
    if (first >= first_zone.current.len or
        second >= second_zone.current.len)
    {
        return error.InvalidHintOperand;
    }
    const distance = @divTrunc(
        fixed.projectDifference(
            second_zone.current[second],
            first_zone.current[first],
            graphics.projection,
        ),
        2,
    );
    moveProjected(
        &first_zone.current[first],
        &first_zone.flags[first],
        distance,
        graphics,
    );
    moveProjected(
        &second_zone.current[second],
        &second_zone.flags[second],
        0 -| distance,
        graphics,
    );
}

pub fn intersect(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    point: usize,
    a0: usize,
    a1: usize,
    b0: usize,
    b1: usize,
) types.Error!void {
    const a_zone = try zoneAt(twilight, glyph, graphics.zp1);
    const b_zone = try zoneAt(twilight, glyph, graphics.zp0);
    const target = try zoneAt(twilight, glyph, graphics.zp2);
    if (a0 >= a_zone.current.len or
        a1 >= a_zone.current.len or
        b0 >= b_zone.current.len or
        b1 >= b_zone.current.len or
        point >= target.current.len)
    {
        return error.InvalidHintOperand;
    }

    const av0 = a_zone.current[a0];
    const av1 = a_zone.current[a1];
    const bv0 = b_zone.current[b0];
    const bv1 = b_zone.current[b1];
    const dax = av1.x -| av0.x;
    const day = av1.y -| av0.y;
    const dbx = bv1.x -| bv0.x;
    const dby = bv1.y -| bv0.y;
    const dx = bv0.x -| av0.x;
    const dy = bv0.y -| av0.y;

    const discriminant = fixed.mulDivClamped(dax, 0 -| dby, 64) +|
        fixed.mulDivClamped(day, dbx, 64);
    const dot_product = fixed.mulDivClamped(dax, dbx, 64) +|
        fixed.mulDivClamped(day, dby, 64);
    const usable_intersection =
        @as(i64, 19) * absolute(discriminant) > absolute(dot_product);

    target.current[point] = if (usable_intersection) intersection: {
        const value = fixed.mulDivClamped(dx, 0 -| dby, 64) +|
            fixed.mulDivClamped(dy, dbx, 64);
        break :intersection .{
            .x = av0.x +| fixed.mulDivClamped(value, dax, discriminant),
            .y = av0.y +| fixed.mulDivClamped(value, day, discriminant),
        };
    } else .{
        // FreeType's grazing-line fallback is the average of both line
        // midpoints. It remains stable even for coincident or zero-length
        // segments.
        .x = fixed.clampI64(
            @divTrunc(
                @as(i64, av0.x) + av1.x + bv0.x + bv1.x,
                4,
            ),
        ),
        .y = fixed.clampI64(
            @divTrunc(
                @as(i64, av0.y) + av1.y + bv0.y + bv1.y,
                4,
            ),
        ),
    };
    target.flags[point].touched_x = true;
    target.flags[point].touched_y = true;
}

pub fn setDualProjectionLine(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *state.GraphicsState,
    first: usize,
    second: usize,
    perpendicular: bool,
) types.Error!void {
    const first_zone = try zoneAt(twilight, glyph, graphics.zp1);
    const second_zone = try zoneAt(twilight, glyph, graphics.zp2);
    if (first >= first_zone.current.len or
        second >= second_zone.current.len)
    {
        return error.InvalidHintOperand;
    }
    graphics.dual_projection = lineVector(
        first_zone.original[first],
        second_zone.original[second],
        perpendicular,
    );
    graphics.projection = lineVector(
        first_zone.current[first],
        second_zone.current[second],
        perpendicular,
    );
}

fn lineVector(
    first: outline.Point,
    second: outline.Point,
    perpendicular: bool,
) state.Vector {
    var x = first.x -| second.x;
    var y = first.y -| second.y;
    if (x == 0 and y == 0) return .{};
    if (perpendicular) {
        const old_x = x;
        x = 0 -| y;
        y = old_x;
    }
    return .normalized(x, y);
}

fn moveProjected(
    point: *outline.Point,
    flag: *outline.PointFlag,
    distance: i32,
    graphics: *const state.GraphicsState,
) void {
    const dot = fixed.vectorDot(graphics.freedom, graphics.projection);
    if (dot <= -0x400 or dot >= 0x400) {
        point.x +|= fixed.mulDivClamped(
            distance,
            graphics.freedom.x,
            dot,
        );
        point.y +|= fixed.mulDivClamped(
            distance,
            graphics.freedom.y,
            dot,
        );
    }
    if (graphics.freedom.x != 0) flag.touched_x = true;
    if (graphics.freedom.y != 0) flag.touched_y = true;
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

fn absolute(value: i32) i64 {
    const wide: i64 = value;
    return if (wide < 0) -wide else wide;
}

test "ISECT resolves crossing lines and marks both axes" {
    const std = @import("std");
    var current = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
        .{ .x = 50, .y = -100 },
        .{ .x = 50, .y = 100 },
    };
    var original = current;
    var unscaled = current;
    var flags = [_]outline.PointFlag{.{}} ** current.len;
    var zone = state.Zone{
        .current = &current,
        .original = &original,
        .unscaled = &unscaled,
        .flags = &flags,
        .real_point_count = current.len,
    };
    var empty = state.Zone{
        .current = &.{},
        .original = &.{},
        .unscaled = &.{},
        .flags = &.{},
        .real_point_count = 0,
    };
    var graphics = state.GraphicsState{};
    try intersect(&empty, &zone, &graphics, 0, 1, 2, 3, 4);
    try std.testing.expectEqual(outline.Point{ .x = 50, .y = 0 }, current[0]);
    try std.testing.expect(flags[0].touched_x);
    try std.testing.expect(flags[0].touched_y);
}

test "ALIGNPTS meets two projected points halfway" {
    const std = @import("std");
    var current = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
    };
    var original = current;
    var unscaled = current;
    var flags = [_]outline.PointFlag{.{}} ** current.len;
    var zone = state.Zone{
        .current = &current,
        .original = &original,
        .unscaled = &unscaled,
        .flags = &flags,
        .real_point_count = current.len,
    };
    var empty = state.Zone{
        .current = &.{},
        .original = &.{},
        .unscaled = &.{},
        .flags = &.{},
        .real_point_count = 0,
    };
    var graphics = state.GraphicsState{};
    try alignPoints(&empty, &zone, &graphics, 0, 1);
    try std.testing.expectEqual(@as(i32, 50), current[0].x);
    try std.testing.expectEqual(@as(i32, 50), current[1].x);
    try std.testing.expect(flags[0].touched_x);
    try std.testing.expect(flags[1].touched_x);
}

test "SDPVTL derives dual and current projection independently" {
    const std = @import("std");
    var current = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 0 },
    };
    var original = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
    };
    var unscaled = original;
    var flags = [_]outline.PointFlag{.{}} ** current.len;
    var zone = state.Zone{
        .current = &current,
        .original = &original,
        .unscaled = &unscaled,
        .flags = &flags,
        .real_point_count = current.len,
    };
    var empty = state.Zone{
        .current = &.{},
        .original = &.{},
        .unscaled = &.{},
        .flags = &.{},
        .real_point_count = 0,
    };
    var graphics = state.GraphicsState{};
    try setDualProjectionLine(&empty, &zone, &graphics, 0, 1, false);
    try std.testing.expectEqual(@as(i32, 0), graphics.dual_projection.x);
    try std.testing.expectEqual(
        @as(i32, -0x4000),
        graphics.dual_projection.y,
    );
    try std.testing.expectEqual(
        @as(i32, -0x4000),
        graphics.projection.x,
    );
    try std.testing.expectEqual(@as(i32, 0), graphics.projection.y);
}
