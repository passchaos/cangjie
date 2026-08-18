//! Owning raw TrueType point transaction for one simple glyph.
//!
//! The transaction retains every datum consumed by the point-zone VM: source
//! and original-scaled coordinates, mutable scaled coordinates, contour ends,
//! on-curve/touched flags, glyph bytecode, and the four metric phantom points.
//! Public path commands are rebuilt only after point execution completes.

const std = @import("std");

const bin = @import("../../binary.zig");
const glyph = @import("../../glyph.zig");
const glyf = @import("../tables/truetype/glyf/root.zig");
const types = @import("types.zig");

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const PointFlag = packed struct(u8) {
    on_curve: bool = false,
    touched_x: bool = false,
    touched_y: bool = false,
    overlap: bool = false,
    reserved: u4 = 0,
};

pub const PixelOutline = struct {
    allocator: std.mem.Allocator,
    glyph_id: glyph.GlyphId,
    commands: std.ArrayList(glyph.PathCommand) = .empty,
    advance_width: f32,
    left_side_bearing: f32,

    pub fn deinit(self: *PixelOutline) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const Transaction = struct {
    allocator: std.mem.Allocator,
    /// Stable identity of the face whose validated `glyf` bytes are borrowed.
    face_identity: usize,
    target: types.Target,
    glyph_id: glyph.GlyphId,
    real_point_count: usize,
    points: []Point,
    original: []Point,
    unscaled: []Point,
    flags: []PointFlag,
    contours: []u16,
    instructions: []const u8,
    scale_16_16: i32,

    pub fn deinit(self: *Transaction) void {
        self.allocator.free(self.contours);
        self.allocator.free(self.flags);
        self.allocator.free(self.unscaled);
        self.allocator.free(self.original);
        self.allocator.free(self.points);
        self.* = undefined;
    }

    pub fn phantomPoints(self: *const Transaction) *const [4]Point {
        return @ptrCast(self.points[self.real_point_count..].ptr);
    }

    pub fn mutablePhantomPoints(self: *Transaction) *[4]Point {
        return @ptrCast(self.points[self.real_point_count..].ptr);
    }

    /// Rebuild a pixel-space quadratic path after hinting.
    pub fn toPixelOutline(self: *const Transaction) types.Error!PixelOutline {
        const origin_shift = self.points[self.real_point_count].x;
        var result = PixelOutline{
            .allocator = self.allocator,
            .glyph_id = self.glyph_id,
            .advance_width = @as(f32, @floatFromInt(
                self.points[self.real_point_count + 1].x -
                    self.points[self.real_point_count].x,
            )) / 64.0,
            .left_side_bearing = leftBearing: {
                if (self.real_point_count == 0) break :leftBearing 0;
                var x_min = self.points[0].x;
                for (self.points[1..self.real_point_count]) |point| {
                    x_min = @min(x_min, point.x);
                }
                break :leftBearing @as(f32, @floatFromInt(
                    x_min - self.points[self.real_point_count].x,
                )) / 64.0;
            },
        };
        errdefer result.deinit();
        try result.commands.ensureTotalCapacity(
            self.allocator,
            self.real_point_count + self.contours.len,
        );
        var start: usize = 0;
        for (self.contours) |end_value| {
            const end: usize = end_value;
            if (end < start or end >= self.real_point_count) {
                return error.BadSfnt;
            }
            try appendContour(
                &result,
                self.points[start .. end + 1],
                self.flags[start .. end + 1],
                origin_shift,
            );
            start = end + 1;
        }
        if (start != self.real_point_count) return error.BadSfnt;
        return result;
    }
};

pub const Metrics = struct {
    bounds: glyph.Bounds,
    advance_width: i32,
    left_side_bearing: i32,
    vertical_advance: i32,
    top_side_bearing: i32,
};

pub fn decodeSimple(
    allocator: std.mem.Allocator,
    face_identity: usize,
    target: types.Target,
    glyph_id: glyph.GlyphId,
    data: []const u8,
    contour_count: u16,
    metrics: Metrics,
    scale_16_16: i32,
) types.Error!Transaction {
    var reader = bin.Reader.init(data);
    _ = reader.readI16() catch return error.BadSfnt;
    reader.skip(8) catch return error.BadSfnt;
    const contours = try allocator.alloc(u16, contour_count);
    errdefer allocator.free(contours);
    var real_point_count: usize = 0;
    var previous: ?u16 = null;
    for (contours) |*end| {
        end.* = reader.readU16() catch return error.BadSfnt;
        if (previous) |prior| if (end.* <= prior) return error.BadSfnt;
        previous = end.*;
        real_point_count = @as(usize, end.*) + 1;
    }
    const instruction_len = reader.readU16() catch return error.BadSfnt;
    if (instruction_len > data.len - reader.offset) return error.BadSfnt;
    const instructions =
        data[reader.offset .. reader.offset + instruction_len];
    reader.skip(instruction_len) catch return error.BadSfnt;

    const point_count = real_point_count + 4;
    const unscaled = try allocator.alloc(Point, point_count);
    errdefer allocator.free(unscaled);
    const original = try allocator.alloc(Point, point_count);
    errdefer allocator.free(original);
    const points = try allocator.alloc(Point, point_count);
    errdefer allocator.free(points);
    const flags = try allocator.alloc(PointFlag, point_count);
    errdefer allocator.free(flags);
    @memset(flags, .{});

    var point_index: usize = 0;
    while (point_index < real_point_count) : (point_index += 1) {
        const raw = reader.readU8() catch return error.BadSfnt;
        glyf.validateSimpleFlag(raw, point_index) catch return error.BadSfnt;
        flags[point_index] = .{
            .on_curve = (raw & 0x01) != 0,
            .overlap = point_index == 0 and (raw & 0x40) != 0,
        };
        unscaled[point_index].x = raw; // Temporary compressed flag storage.
        if ((raw & 0x08) != 0) {
            const repeat = reader.readU8() catch return error.BadSfnt;
            for (0..repeat) |_| {
                point_index += 1;
                if (point_index >= real_point_count) return error.BadSfnt;
                unscaled[point_index].x = raw;
                flags[point_index] = flags[point_index - 1];
            }
        }
    }

    var x: i32 = 0;
    for (unscaled[0..real_point_count]) |*point| {
        const raw: u8 = @intCast(point.x);
        const delta: i32 = if ((raw & 0x02) != 0)
            if ((raw & 0x10) != 0)
                reader.readU8() catch return error.BadSfnt
            else
                -@as(i32, reader.readU8() catch return error.BadSfnt)
        else if ((raw & 0x10) != 0)
            0
        else
            reader.readI16() catch return error.BadSfnt;
        x += delta;
        point.x = x;
    }
    // Re-decode flags to preserve the independent Y stream shape. This second
    // bounded scan is cheaper than retaining another point-sized allocation.
    var flag_reader = bin.Reader.init(data);
    _ = flag_reader.readI16() catch return error.BadSfnt;
    flag_reader.skip(8 + contour_count * 2) catch return error.BadSfnt;
    const instruction_bytes = flag_reader.readU16() catch return error.BadSfnt;
    flag_reader.skip(instruction_bytes) catch return error.BadSfnt;
    var flag_index: usize = 0;
    while (flag_index < real_point_count) : (flag_index += 1) {
        const raw = flag_reader.readU8() catch return error.BadSfnt;
        unscaled[flag_index].y = raw;
        if ((raw & 0x08) != 0) {
            const repeat = flag_reader.readU8() catch return error.BadSfnt;
            for (0..repeat) |_| {
                flag_index += 1;
                if (flag_index >= real_point_count) return error.BadSfnt;
                unscaled[flag_index].y = raw;
            }
        }
    }
    // Skip the X stream already consumed by `reader`; Y begins at its current
    // position and uses the re-expanded raw flags stored in `unscaled.y`.
    var y: i32 = 0;
    for (unscaled[0..real_point_count]) |*point| {
        const raw: u8 = @intCast(point.y);
        const delta: i32 = if ((raw & 0x04) != 0)
            if ((raw & 0x20) != 0)
                reader.readU8() catch return error.BadSfnt
            else
                -@as(i32, reader.readU8() catch return error.BadSfnt)
        else if ((raw & 0x20) != 0)
            0
        else
            reader.readI16() catch return error.BadSfnt;
        y += delta;
        point.y = y;
    }

    const left = metrics.bounds.x_min - metrics.left_side_bearing;
    unscaled[real_point_count] = .{ .x = left, .y = 0 };
    unscaled[real_point_count + 1] = .{
        .x = left + metrics.advance_width,
        .y = 0,
    };
    unscaled[real_point_count + 2] = .{
        .x = 0,
        .y = metrics.bounds.y_max + metrics.top_side_bearing,
    };
    unscaled[real_point_count + 3] = .{
        .x = 0,
        .y = metrics.bounds.y_max + metrics.top_side_bearing -
            metrics.vertical_advance,
    };
    for (unscaled, original, points) |raw, *origin, *point| {
        origin.* = .{
            .x = types.scaleFUnits(raw.x, scale_16_16),
            .y = types.scaleFUnits(raw.y, scale_16_16),
        };
        point.* = origin.*;
    }
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = target,
        .glyph_id = glyph_id,
        .real_point_count = real_point_count,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .instructions = instructions,
        .scale_16_16 = scale_16_16,
    };
}

fn appendContour(
    outline: *PixelOutline,
    points: []const Point,
    flags: []const PointFlag,
    origin_shift: i32,
) types.Error!void {
    if (points.len == 0 or points.len != flags.len) return error.BadSfnt;
    const first = points[0];
    const last = points[points.len - 1];
    var current: Point = undefined;
    var index: usize = 0;
    if (flags[0].on_curve) {
        current = first;
        index = 1;
    } else if (flags[flags.len - 1].on_curve) {
        current = last;
    } else {
        current = midpoint(last, first);
    }
    try outline.commands.append(
        outline.allocator,
        .{ .move_to = pixelPoint(current, origin_shift) },
    );
    while (index < points.len) {
        const point = points[index];
        if (flags[index].on_curve) {
            current = point;
            try outline.commands.append(
                outline.allocator,
                .{ .line_to = pixelPoint(current, origin_shift) },
            );
            index += 1;
        } else {
            const next_index = if (index + 1 < points.len) index + 1 else 0;
            const end = if (flags[next_index].on_curve)
                points[next_index]
            else
                midpoint(point, points[next_index]);
            try outline.commands.append(outline.allocator, .{
                .quad_to = .{
                    .control = pixelPoint(point, origin_shift),
                    .end = pixelPoint(end, origin_shift),
                },
            });
            current = end;
            index += if (flags[next_index].on_curve and next_index != 0)
                2
            else
                1;
        }
    }
    try outline.commands.append(outline.allocator, .close);
}

fn midpoint(a: Point, b: Point) Point {
    return .{
        .x = @divTrunc(a.x + b.x, 2),
        .y = @divTrunc(a.y + b.y, 2),
    };
}

fn pixelPoint(point: Point, origin_shift: i32) glyph.Point {
    return .{
        .x = @as(f32, @floatFromInt(point.x - origin_shift)) / 64.0,
        .y = @as(f32, @floatFromInt(point.y)) / 64.0,
    };
}
