//! Bulk SHP/SHC/SHZ point displacement over TrueType zones.

const fixed = @import("fixed.zig");
const outline = @import("../outline.zig");
const state = @import("state.zig");
const types = @import("../types.zig");

pub fn pointsByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    use_rp1: bool,
    points: []const usize,
) types.Error!void {
    const displacement = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
        use_rp1,
    );
    const target = try zoneAt(twilight, glyph, graphics.zp2);
    for (points) |point| {
        if (point >= target.current.len) continue;
        shiftPoint(
            &target.current[point],
            &target.flags[point],
            displacement,
            graphics.freedom,
        );
    }
}

pub fn contourByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    use_rp1: bool,
    contour: usize,
) types.Error!void {
    const displacement = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
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
        shiftPoint(
            &target.current[point],
            &target.flags[point],
            displacement,
            graphics.freedom,
        );
    }
}

pub fn zoneByReference(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    use_rp1: bool,
    zone_index: u8,
) types.Error!void {
    if (zone_index > 1) return error.InvalidHintOperand;
    const displacement = try referenceDisplacement(
        twilight,
        glyph,
        graphics,
        use_rp1,
    );
    const target = try zoneAt(twilight, glyph, zone_index);
    const limit = @min(target.real_point_count, target.current.len);
    for (target.current[0..limit]) |*point| {
        if (graphics.freedom.x != 0) point.x +|= displacement.x;
        if (graphics.freedom.y != 0) point.y +|= displacement.y;
    }
}

fn referenceDisplacement(
    twilight: *state.Zone,
    glyph: *state.Zone,
    graphics: *const state.GraphicsState,
    use_rp1: bool,
) types.Error!outline.Point {
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
    return fixed.pointAlongVector(projected, graphics.freedom);
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
