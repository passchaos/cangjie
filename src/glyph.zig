const std = @import("std");

pub const GlyphId = u16;

pub const Point = struct {
    x: f32,
    y: f32,
};

pub const Bounds = struct {
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

pub const PathCommand = union(enum) {
    move_to: Point,
    line_to: Point,
    quad_to: struct { control: Point, end: Point },
    cubic_to: struct { c0: Point, c1: Point, end: Point },
    close,
};

pub const GlyphOutline = struct {
    allocator: std.mem.Allocator,
    glyph_id: GlyphId,
    bounds: Bounds,
    advance_width: u16,
    left_side_bearing: i16,
    commands: std.ArrayList(PathCommand) = .empty,

    pub fn init(allocator: std.mem.Allocator, glyph_id: GlyphId, bounds: Bounds, advance_width: u16, left_side_bearing: i16) GlyphOutline {
        return .{
            .allocator = allocator,
            .glyph_id = glyph_id,
            .bounds = bounds,
            .advance_width = advance_width,
            .left_side_bearing = left_side_bearing,
        };
    }

    pub fn deinit(self: *GlyphOutline) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const OutlineBuilder = struct {
    outline: *GlyphOutline,

    pub fn moveTo(self: *OutlineBuilder, point: Point) !void {
        try self.outline.commands.append(self.outline.allocator, .{ .move_to = point });
    }

    pub fn lineTo(self: *OutlineBuilder, point: Point) !void {
        try self.outline.commands.append(self.outline.allocator, .{ .line_to = point });
    }

    pub fn quadTo(self: *OutlineBuilder, control: Point, end: Point) !void {
        try self.outline.commands.append(self.outline.allocator, .{ .quad_to = .{ .control = control, .end = end } });
    }

    pub fn cubicTo(self: *OutlineBuilder, c0: Point, c1: Point, end: Point) !void {
        try self.outline.commands.append(self.outline.allocator, .{ .cubic_to = .{ .c0 = c0, .c1 = c1, .end = end } });
    }

    pub fn close(self: *OutlineBuilder) !void {
        try self.outline.commands.append(self.outline.allocator, .close);
    }
};

pub fn midpoint(a: Point, b: Point) Point {
    return .{ .x = (a.x + b.x) * 0.5, .y = (a.y + b.y) * 0.5 };
}
