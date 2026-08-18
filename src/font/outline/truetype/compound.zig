//! Runtime decoding and point-anchor placement for compound `glyf` outlines.

const std = @import("std");
const bin = @import("../../../binary.zig");
const glyph = @import("../../../glyph.zig");
const glyf = @import("../../tables/truetype/glyf/root.zig");
const geometry = @import("../geometry.zig");

const Transform = geometry.Transform;

pub const Error = glyf.Error || error{EndOfStream};

pub const Placement = union(enum) {
    offset: struct { x: i16, y: i16 },
    points: glyf.PointMatch,
};

/// Exact signed 2.14 matrix retained for consumers that operate on integer
/// point zones rather than `f32` path commands.
pub const FixedTransform = struct {
    xx: i16 = 0x4000,
    yx: i16 = 0,
    xy: i16 = 0,
    yy: i16 = 0x4000,
};

pub const Component = struct {
    flags: u16,
    glyph_id: glyph.GlyphId,
    placement: Placement,
    linear_transform: Transform,
    fixed_transform: FixedTransform,

    pub fn hasMore(self: Component) bool {
        return (self.flags & 0x0020) != 0;
    }
};

pub fn readComponent(reader: *bin.Reader) Error!Component {
    const flags = try reader.readU16();
    try glyf.validateCompoundFlags(flags);
    const glyph_id = try reader.readU16();
    const placement: Placement = if ((flags & 0x0002) != 0)
        .{ .offset = if ((flags & 0x0001) != 0)
            .{ .x = try reader.readI16(), .y = try reader.readI16() }
        else
            .{ .x = try reader.readI8(), .y = try reader.readI8() } }
    else
        .{ .points = if ((flags & 0x0001) != 0)
            .{
                .parent_point = try reader.readU16(),
                .child_point = try reader.readU16(),
            }
        else
            .{
                .parent_point = try reader.readU8(),
                .child_point = try reader.readU8(),
            } };

    var fixed = FixedTransform{};
    if ((flags & 0x0008) != 0) {
        const scale = try reader.readI16();
        fixed.xx = scale;
        fixed.yy = scale;
    } else if ((flags & 0x0040) != 0) {
        fixed.xx = try reader.readI16();
        fixed.yy = try reader.readI16();
    } else if ((flags & 0x0080) != 0) {
        fixed.xx = try reader.readI16();
        fixed.yx = try reader.readI16();
        fixed.xy = try reader.readI16();
        fixed.yy = try reader.readI16();
    }
    return .{
        .flags = flags,
        .glyph_id = glyph_id,
        .placement = placement,
        .linear_transform = .{
            .xx = f2dot14(fixed.xx),
            .yx = f2dot14(fixed.yx),
            .xy = f2dot14(fixed.xy),
            .yy = f2dot14(fixed.yy),
            .dx = 0,
            .dy = 0,
        },
        .fixed_transform = fixed,
    };
}

pub fn placePointMatched(
    outline: *glyph.GlyphOutline,
    points: *std.ArrayList(glyph.Point),
    parent_point_start: usize,
    child_point_start: usize,
    child_command_start: usize,
    point_match: glyf.PointMatch,
) Error!void {
    const parent_index =
        parent_point_start + @as(usize, point_match.parent_point);
    const child_index =
        child_point_start + @as(usize, point_match.child_point);
    // Parse-time graph validation normally proves both accesses. Keep the
    // materializer defensive as well: parsed-font raster paths intentionally
    // skip repeated graph validation, and must still reject invalid indices.
    if (parent_index >= child_point_start or
        child_index >= points.items.len)
    {
        return error.InvalidGlyph;
    }

    const parent_point = points.items[parent_index];
    const child_point = points.items[child_index];
    const offset = glyph.Point{
        .x = parent_point.x - child_point.x,
        .y = parent_point.y - child_point.y,
    };
    if (offset.x == 0 and offset.y == 0) return;

    for (points.items[child_point_start..]) |*point| {
        translatePoint(point, offset);
    }
    for (outline.commands.items[child_command_start..]) |*command| {
        translateCommand(command, offset);
    }
}

fn translatePoint(point: *glyph.Point, offset: glyph.Point) void {
    point.x += offset.x;
    point.y += offset.y;
}

fn translateCommand(command: *glyph.PathCommand, offset: glyph.Point) void {
    switch (command.*) {
        .move_to => |*point| translatePoint(point, offset),
        .line_to => |*point| translatePoint(point, offset),
        .quad_to => |*curve| {
            translatePoint(&curve.control, offset);
            translatePoint(&curve.end, offset);
        },
        .cubic_to => |*curve| {
            translatePoint(&curve.c0, offset);
            translatePoint(&curve.c1, offset);
            translatePoint(&curve.end, offset);
        },
        .close => {},
    }
}

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}
