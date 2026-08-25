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

/// HarfBuzz-compatible glyph extents in font units.
///
/// `x_bearing`/`y_bearing` identify the top-left ink corner in the OpenType
/// coordinate system; width grows right and height grows down, so ordinary
/// upright outlines have a negative height.
pub const Extents = struct {
    x_bearing: i32,
    y_bearing: i32,
    width: i32,
    height: i32,
};

pub fn extentsForBounds(bounds: Bounds) Extents {
    return .{
        .x_bearing = bounds.x_min,
        .y_bearing = bounds.y_max,
        .width = @as(i32, bounds.x_max) - @as(i32, bounds.x_min),
        .height = @as(i32, bounds.y_min) - @as(i32, bounds.y_max),
    };
}

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

/// Caller-owned storage for repeated outline materialization.
///
/// `GlyphOutline` remains the owning, one-result API. This buffer is the
/// explicit alternative for atlas builders and other loops that decode many
/// outlines from one immutable parsed face: its command allocation and the
/// raw point storage needed by compound `glyf` placement survive between
/// calls. A borrowed outline returned by `GlyphSession.outlineInto` remains
/// valid until a different/failed decode on this buffer or `deinit`; repeating
/// the same glyph id returns the retained decoded outline.
pub const GlyphOutlineBuffer = struct {
    // These fields are implementation storage shared with the font decoder.
    // Public users should consume `current`; their layout is not a stable API.
    outline_storage: GlyphOutline,
    compound_points: std.ArrayList(Point) = .empty,
    cached_glyph_id: ?GlyphId = null,

    pub fn init(allocator: std.mem.Allocator) GlyphOutlineBuffer {
        return .{
            .outline_storage = GlyphOutline.init(
                allocator,
                0,
                .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 },
                0,
                0,
            ),
        };
    }

    pub fn deinit(self: *GlyphOutlineBuffer) void {
        const allocator = self.outline_storage.allocator;
        self.outline_storage.deinit();
        self.compound_points.deinit(allocator);
        self.* = undefined;
    }

    /// Return the most recently materialized outline.
    ///
    /// Before the first successful decode (and after a failed decode), this
    /// returns an empty outline with glyph id and metrics set to zero. The
    /// pointer is invalidated by a different or failed decode into this buffer
    /// even when its address does not change.
    pub fn current(self: *const GlyphOutlineBuffer) *const GlyphOutline {
        return &self.outline_storage;
    }
};

/// Reset reusable storage before a trusted outline decode.
///
/// This is an internal cross-module boundary rather than part of the exported
/// `cangjie.font` namespace. Keeping it here lets the storage owner preserve
/// all capacity while the table decoder supplies fresh result metadata.
pub fn resetOutlineBuffer(buffer: *GlyphOutlineBuffer) void {
    buffer.cached_glyph_id = null;
    buffer.outline_storage.commands.clearRetainingCapacity();
    buffer.compound_points.clearRetainingCapacity();
    configureOutline(
        &buffer.outline_storage,
        0,
        .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 },
        0,
        0,
    );
}

pub fn cachedOutline(
    buffer: *GlyphOutlineBuffer,
    glyph_id: GlyphId,
) ?*const GlyphOutline {
    if (buffer.cached_glyph_id == glyph_id) return buffer.current();
    return null;
}

pub fn publishOutlineBuffer(
    buffer: *GlyphOutlineBuffer,
    glyph_id: GlyphId,
) *const GlyphOutline {
    buffer.cached_glyph_id = glyph_id;
    return buffer.current();
}

pub fn configureOutline(
    outline: *GlyphOutline,
    glyph_id: GlyphId,
    bounds: Bounds,
    advance_width: u16,
    left_side_bearing: i16,
) void {
    outline.glyph_id = glyph_id;
    outline.bounds = bounds;
    outline.advance_width = advance_width;
    outline.left_side_bearing = left_side_bearing;
}

pub fn boundsForCommands(commands: []const PathCommand) Bounds {
    var acc = PathBoundsAccumulator{};
    for (commands) |command| {
        switch (command) {
            .move_to => |point| acc.include(point),
            .line_to => |point| acc.include(point),
            .quad_to => |curve| {
                acc.include(curve.control);
                acc.include(curve.end);
            },
            .cubic_to => |curve| {
                acc.include(curve.c0);
                acc.include(curve.c1);
                acc.include(curve.end);
            },
            .close => {},
        }
    }
    return acc.finish();
}

const PathBoundsAccumulator = struct {
    has_point: bool = false,
    x_min: f32 = 0,
    y_min: f32 = 0,
    x_max: f32 = 0,
    y_max: f32 = 0,

    fn include(self: *PathBoundsAccumulator, point: Point) void {
        if (!self.has_point) {
            self.* = .{
                .has_point = true,
                .x_min = point.x,
                .y_min = point.y,
                .x_max = point.x,
                .y_max = point.y,
            };
            return;
        }
        self.x_min = @min(self.x_min, point.x);
        self.y_min = @min(self.y_min, point.y);
        self.x_max = @max(self.x_max, point.x);
        self.y_max = @max(self.y_max, point.y);
    }

    fn finish(self: PathBoundsAccumulator) Bounds {
        if (!self.has_point) return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        return .{
            .x_min = clampF32ToI16(@floor(self.x_min)),
            .y_min = clampF32ToI16(@floor(self.y_min)),
            .x_max = clampF32ToI16(@ceil(self.x_max)),
            .y_max = clampF32ToI16(@ceil(self.y_max)),
        };
    }
};

fn clampF32ToI16(value: f32) i16 {
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i16)))) return std.math.minInt(i16);
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i16)))) return std.math.maxInt(i16);
    return @intFromFloat(value);
}

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
