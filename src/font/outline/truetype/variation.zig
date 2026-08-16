//! Runtime gvar helpers shared by simple and compound outline materialization.

const std = @import("std");
const glyph = @import("../../../glyph.zig");
const gvar = @import("../../../opentype/gvar.zig");
const metrics = @import("../../tables/metrics/root.zig");
const numeric = @import("../numeric.zig");

pub fn deltaForPoint(
    deltas: []const gvar.ScaledPointDelta,
    point: usize,
) gvar.Point {
    if (point > std.math.maxInt(u16)) return .{ .x = 0, .y = 0 };
    const point_id: u16 = @intCast(point);
    if (point < deltas.len and deltas[point].point == point_id) {
        return .{ .x = deltas[point].x, .y = deltas[point].y };
    }
    var result = gvar.Point{ .x = 0, .y = 0 };
    for (deltas) |delta| {
        if (delta.point != point_id) continue;
        result.x += delta.x;
        result.y += delta.y;
    }
    return result;
}

pub fn applyMetricDeltas(
    outline: *glyph.GlyphOutline,
    default_bounds: glyph.Bounds,
    default_metrics: metrics.Horizontal,
    phantom: gvar.PhantomPointDeltas,
) void {
    const default_left_phantom = @as(
        f32,
        @floatFromInt(
            @as(i32, default_bounds.x_min) -
                @as(i32, default_metrics.left_side_bearing),
        ),
    );
    const varied_left_phantom = default_left_phantom + phantom.left.x;
    outline.left_side_bearing = numeric.clampF32ToI16(
        numeric.roundOpenType(
            @as(f32, @floatFromInt(outline.bounds.x_min)) -
                varied_left_phantom,
        ),
    );
    outline.advance_width = numeric.clampF32ToU16(
        numeric.roundOpenType(
            @as(f32, @floatFromInt(default_metrics.advance_width)) +
                phantom.horizontalAdvanceDelta(),
        ),
    );
}
