//! Affine geometry used while materializing nested font outlines.

const glyph = @import("../../glyph.zig");
const varc = @import("../../opentype/varc.zig");

pub const Transform = struct {
    xx: f32,
    yx: f32,
    xy: f32,
    yy: f32,
    dx: f32,
    dy: f32,

    pub fn identity() Transform {
        return .{ .xx = 1, .yx = 0, .xy = 0, .yy = 1, .dx = 0, .dy = 0 };
    }

    pub fn apply(self: Transform, point: glyph.Point) glyph.Point {
        return .{
            .x = point.x * self.xx + point.y * self.xy + self.dx,
            .y = point.x * self.yx + point.y * self.yy + self.dy,
        };
    }

    /// Compose `b` inside `a`, matching the recursive component order used by
    /// TrueType compound glyphs and OpenType VARC components.
    pub fn mul(a: Transform, b: Transform) Transform {
        return .{
            .xx = a.xx * b.xx + a.xy * b.yx,
            .yx = a.yx * b.xx + a.yy * b.yx,
            .xy = a.xx * b.xy + a.xy * b.yy,
            .yy = a.yx * b.xy + a.yy * b.yy,
            .dx = a.xx * b.dx + a.xy * b.dy + a.dx,
            .dy = a.yx * b.dx + a.yy * b.dy + a.dy,
        };
    }
};

pub fn fromVarc(value: varc.StaticTransform) Transform {
    return .{
        .xx = value.xx,
        .yx = value.yx,
        .xy = value.xy,
        .yy = value.yy,
        .dx = value.dx,
        .dy = value.dy,
    };
}

pub fn transformPathCommands(
    commands: []glyph.PathCommand,
    transform: Transform,
) void {
    for (commands) |*command| {
        switch (command.*) {
            .move_to => |*point| point.* = transform.apply(point.*),
            .line_to => |*point| point.* = transform.apply(point.*),
            .quad_to => |*curve| {
                curve.control = transform.apply(curve.control);
                curve.end = transform.apply(curve.end);
            },
            .cubic_to => |*curve| {
                curve.c0 = transform.apply(curve.c0);
                curve.c1 = transform.apply(curve.c1);
                curve.end = transform.apply(curve.end);
            },
            .close => {},
        }
    }
}
