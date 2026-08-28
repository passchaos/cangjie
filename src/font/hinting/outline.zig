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
const gvar = @import("../../opentype/gvar.zig");
const numeric = @import("../outline/numeric.zig");
const types = @import("types.zig");

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const ComponentTransform = struct {
    xx: i16 = 0x4000,
    yx: i16 = 0,
    xy: i16 = 0,
    yy: i16 = 0x4000,
};

pub const ComponentPlacement = union(enum) {
    offset: struct { x: i32, y: i32 },
    points: struct {
        parent_point: u16,
        child_point: u16,
    },
};

pub const ComponentRecord = struct {
    glyph_id: glyph.GlyphId,
    /// Parse-proved component source retained by the top-level transaction.
    /// Execution must not resolve the same glyph and metrics a second time.
    data: []const u8,
    metrics: Metrics,
    flags: u16,
    point_start: usize,
    point_len: usize,
    contour_start: usize,
    contour_len: usize,
    transform: ComponentTransform,
    placement: ComponentPlacement,
    use_my_metrics: bool,
    is_compound: bool,
    /// Borrowed from the component glyph's validated `glyf` payload.
    instructions: []const u8,
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
    interpreter: types.Interpreter,
    glyph_id: glyph.GlyphId,
    real_point_count: usize,
    points: []Point,
    original: []Point,
    unscaled: []Point,
    flags: []PointFlag,
    contours: []u16,
    components: []ComponentRecord = &.{},
    /// One allocation backing simple-glyph points, originals, unscaled
    /// coordinates, flags, and contour ends. Compound and test transactions
    /// may leave this empty and retain the legacy independently-owned slices.
    simple_storage: []Point = &.{},
    instructions: []const u8,
    scale_16_16: i32,
    normalized_coords: []f32 = &.{},
    /// Borrowed face-wide gvar context used by recursively loaded components.
    variation: ?Variation = null,
    is_compound: bool = false,
    hinting_enabled: bool = true,
    backward_compatibility: bool = false,
    /// v40 keeps unrounded phantom origins while the base layer rounds
    /// reported advances independently.
    grid_fit_metrics: bool = false,
    /// Advance captured before glyph bytecode. In v40 compatibility mode the
    /// public metric ignores phantom writes and rounds this value instead.
    metric_advance_26_6: i32 = 0,

    pub fn deinit(self: *Transaction) void {
        if (self.normalized_coords.len != 0) {
            self.allocator.free(self.normalized_coords);
        }
        if (self.components.len != 0) {
            self.allocator.free(self.components);
        }
        if (self.simple_storage.len != 0) {
            self.allocator.free(self.simple_storage);
        } else {
            self.allocator.free(self.contours);
            self.allocator.free(self.flags);
            self.allocator.free(self.unscaled);
            self.allocator.free(self.original);
            self.allocator.free(self.points);
        }
        self.* = undefined;
    }

    pub fn phantomPoints(self: *const Transaction) *const [4]Point {
        return @ptrCast(self.points[self.real_point_count..].ptr);
    }

    pub fn mutablePhantomPoints(self: *Transaction) *[4]Point {
        return @ptrCast(self.points[self.real_point_count..].ptr);
    }

    pub fn horizontalAdvance(self: *const Transaction) i32 {
        const phantoms = self.phantomPoints();
        const value = if (self.backward_compatibility and
            self.grid_fit_metrics)
            self.metric_advance_26_6
        else
            phantoms[1].x -| phantoms[0].x;
        return if (self.grid_fit_metrics) roundGrid(value) else value;
    }

    pub fn verticalAdvance(self: *const Transaction) i32 {
        const phantoms = self.phantomPoints();
        const value = phantoms[2].y -| phantoms[3].y;
        return if (self.grid_fit_metrics) roundGrid(value) else value;
    }

    /// Rebuild a pixel-space quadratic path after hinting.
    pub fn toPixelOutline(self: *const Transaction) types.Error!PixelOutline {
        const origin_shift = self.points[self.real_point_count].x;
        var result = PixelOutline{
            .allocator = self.allocator,
            .glyph_id = self.glyph_id,
            .advance_width = @as(
                f32,
                @floatFromInt(self.horizontalAdvance()),
            ) / 64.0,
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

fn roundGrid(value: i32) i32 {
    return (value +| 32) & ~@as(i32, 63);
}

pub const Metrics = struct {
    bounds: glyph.Bounds,
    advance_width: i32,
    left_side_bearing: i32,
    vertical_advance: i32,
    top_side_bearing: i32,
};

pub const Variation = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    axis_count: usize,
    normalized_coords: []const f32,
};

pub fn decodeSimple(
    allocator: std.mem.Allocator,
    face_identity: usize,
    target: types.Target,
    interpreter: types.Interpreter,
    glyph_id: glyph.GlyphId,
    data: []const u8,
    contour_count: u16,
    metrics: Metrics,
    scale_16_16: i32,
    variation: ?Variation,
) types.Error!Transaction {
    var reader = bin.Reader.init(data);
    _ = reader.readI16() catch return error.BadSfnt;
    reader.skip(8) catch return error.BadSfnt;
    const contour_data_offset = reader.offset;
    var real_point_count: usize = 0;
    var previous: ?u16 = null;
    for (0..contour_count) |_| {
        const end = reader.readU16() catch return error.BadSfnt;
        if (previous) |prior| if (end <= prior) return error.BadSfnt;
        previous = end;
        real_point_count = @as(usize, end) + 1;
    }
    const instruction_len = reader.readU16() catch return error.BadSfnt;
    if (instruction_len > data.len - reader.offset) return error.BadSfnt;
    const instructions =
        data[reader.offset .. reader.offset + instruction_len];
    reader.skip(instruction_len) catch return error.BadSfnt;

    const point_count = std.math.add(usize, real_point_count, 4) catch
        return error.BadSfnt;
    const point_bytes = std.math.mul(
        usize,
        point_count,
        @sizeOf(Point),
    ) catch return error.BadSfnt;
    const contour_bytes = std.math.mul(
        usize,
        contour_count,
        @sizeOf(u16),
    ) catch return error.BadSfnt;
    const tail_bytes = std.math.add(usize, contour_bytes, point_count * 2) catch
        return error.BadSfnt;
    const payload_bytes = std.math.add(
        usize,
        std.math.mul(usize, point_bytes, 3) catch return error.BadSfnt,
        tail_bytes,
    ) catch return error.BadSfnt;
    const storage_len = std.math.divCeil(
        usize,
        payload_bytes,
        @sizeOf(Point),
    ) catch return error.BadSfnt;
    const simple_storage = try allocator.alloc(Point, storage_len);
    errdefer allocator.free(simple_storage);
    const points = simple_storage[0..point_count];
    const original = simple_storage[point_count .. point_count * 2];
    const unscaled = simple_storage[point_count * 2 .. point_count * 3];
    const tail = std.mem.sliceAsBytes(simple_storage[point_count * 3 ..]);
    const contours = std.mem.bytesAsSlice(
        u16,
        tail[0..contour_bytes],
    );
    for (contours, 0..) |*end, index| {
        const start = contour_data_offset + index * 2;
        end.* = std.mem.readInt(u16, data[start..][0..2], .big);
    }
    const flags: []PointFlag = @ptrCast(
        tail[contour_bytes..][0..point_count],
    );
    @memset(flags, .{});

    // Keep expanded glyf flags until both coordinate streams are decoded.
    // `PointFlag` stores only semantic bits, while the packed x/y delta bits
    // are needed a second time for Y; retaining one byte per point avoids a
    // second walk over the compressed flag stream.
    const raw_flags = tail[contour_bytes + point_count ..][0..point_count];
    var point_index: usize = 0;
    while (point_index < real_point_count) : (point_index += 1) {
        const raw = reader.readU8() catch return error.BadSfnt;
        glyf.validateSimpleFlag(raw, point_index) catch return error.BadSfnt;
        raw_flags[point_index] = raw;
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
                raw_flags[point_index] = raw;
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
    // Y begins at the reader's current position after the X stream.
    var y: i32 = 0;
    for (unscaled[0..real_point_count], raw_flags[0..real_point_count]) |*point, raw| {
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
        .x = verticalPhantomX(
            interpreter,
            target,
            metrics.advance_width,
        ),
        .y = metrics.bounds.y_max + metrics.top_side_bearing,
    };
    unscaled[real_point_count + 3] = .{
        .x = verticalPhantomX(
            interpreter,
            target,
            metrics.advance_width,
        ),
        .y = metrics.bounds.y_max + metrics.top_side_bearing -
            metrics.vertical_advance,
    };
    var scaled_from_fractional_variation = false;
    var use_variation_scaling = false;
    if (variation) |context| {
        // FreeType uses its fractional `unrounded` scaling path for every
        // glyph at a non-default instance, even when this glyph has no active
        // tuple. This can differ from scaling integer design coordinates
        // directly by one 26.6 unit.
        use_variation_scaling =
            hasNonDefaultLocation(context.normalized_coords);
        const deltas = gvar.accumulateSimpleGlyphPointDeltasWithReader(
            allocator,
            context.data,
            context.table_offset,
            context.table_length,
            context.glyph_count,
            context.axis_count,
            glyph_id,
            context.normalized_coords,
            []const Point,
            unscaled[0..real_point_count],
            real_point_count,
            readPointForVariation,
            contours,
            true,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.BadSfnt,
        };
        defer if (deltas) |owned| allocator.free(owned);
        if (deltas) |active| {
            if (active.len != point_count) return error.BadSfnt;
            for (unscaled, original, active) |*point, *origin, delta| {
                const varied_x =
                    @as(f32, @floatFromInt(point.x)) + delta.x;
                const varied_y =
                    @as(f32, @floatFromInt(point.y)) + delta.y;
                // The VM's dual projection reads integer design points, but
                // FreeType scales a separate `unrounded` varied coordinate.
                // Rounding to design units before scaling loses fractional
                // gvar precision and shifts some 26.6 points by one unit.
                point.x = roundVariationCoordinate(varied_x);
                point.y = roundVariationCoordinate(varied_y);
                origin.* = .{
                    .x = scaleVariationCoordinate(
                        varied_x,
                        scale_16_16,
                    ),
                    .y = scaleVariationCoordinate(
                        varied_y,
                        scale_16_16,
                    ),
                };
            }
            scaled_from_fractional_variation = true;
        }
    }
    for (unscaled, original, points) |raw, *origin, *point| {
        if (!scaled_from_fractional_variation) {
            origin.* = if (use_variation_scaling)
                .{
                    .x = scaleVariationCoordinate(
                        @floatFromInt(raw.x),
                        scale_16_16,
                    ),
                    .y = scaleVariationCoordinate(
                        @floatFromInt(raw.y),
                        scale_16_16,
                    ),
                }
            else
                .{
                    .x = types.scaleFUnits(raw.x, scale_16_16),
                    .y = types.scaleFUnits(raw.y, scale_16_16),
                };
        }
        point.* = origin.*;
    }
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = target,
        .interpreter = interpreter,
        .glyph_id = glyph_id,
        .real_point_count = real_point_count,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .simple_storage = simple_storage,
        .instructions = instructions,
        .scale_16_16 = scale_16_16,
        .variation = variation,
    };
}

fn readPointForVariation(points: []const Point, index: usize) gvar.Point {
    return .{
        .x = @floatFromInt(points[index].x),
        .y = @floatFromInt(points[index].y),
    };
}

fn roundVariationCoordinate(value: f32) i32 {
    const rounded = numeric.roundOpenType(value);
    if (rounded <= @as(f32, @floatFromInt(std.math.minInt(i32)))) {
        return std.math.minInt(i32);
    }
    if (rounded >= @as(f32, @floatFromInt(std.math.maxInt(i32)))) {
        return std.math.maxInt(i32);
    }
    return @intFromFloat(rounded);
}

fn hasNonDefaultLocation(normalized_coords: []const f32) bool {
    for (normalized_coords) |coordinate| {
        if (coordinate != 0) return true;
    }
    return false;
}

pub fn verticalPhantomX(
    interpreter: types.Interpreter,
    target: types.Target,
    advance_width: i32,
) i32 {
    if (interpreter == .cleartype and target.isGrayscaleClearType()) {
        return @divTrunc(advance_width, 2);
    }
    return 0;
}

fn scaleVariationCoordinate(value: f32, scale_16_16: i32) i32 {
    if (!std.math.isFinite(value)) {
        return if (value < 0) std.math.minInt(i32) else std.math.maxInt(i32);
    }
    const integral = @floor(value);
    if (integral <= @as(f32, @floatFromInt(std.math.minInt(i32))) or
        integral >= @as(f32, @floatFromInt(std.math.maxInt(i32))))
    {
        return if (value < 0) std.math.minInt(i32) else std.math.maxInt(i32);
    }
    const base: i32 = @intFromFloat(integral);
    const fraction = value - integral;
    // FreeType carries varied coordinates through an intermediate 26.6
    // `unrounded` array, then applies the size's 16.16 scale and rounds the
    // result back to 26.6. Reproduce those two fixed-point boundaries rather
    // than relying on host floating-point rounding.
    const fractional_26_6: i32 = @intFromFloat(@floor(
        fraction * 64.0 + 0.5,
    ));
    const unrounded = @as(i64, base) * 64 + fractional_26_6;
    const bounded = if (unrounded <= std.math.minInt(i32))
        std.math.minInt(i32)
    else if (unrounded >= std.math.maxInt(i32))
        std.math.maxInt(i32)
    else
        @as(i32, @intCast(unrounded));
    const scaled = types.scaleFUnits(bounded, scale_16_16);
    return @divFloor(scaled +| 32, 64);
}

test "fractional gvar coordinates survive scaling into 26.6" {
    try std.testing.expectEqual(
        @as(i32, 37),
        roundVariationCoordinate(36.5),
    );
    try std.testing.expectEqual(
        @as(i32, 18),
        scaleVariationCoordinate(36.5, 0x8000),
    );
    // A non-default variable instance retains FreeType's intermediate 26.6
    // boundary even when a glyph has no active tuple.
    try std.testing.expectEqual(
        @as(i32, -120),
        scaleVariationCoordinate(-1883, 4194),
    );
    try std.testing.expectEqual(
        @as(i32, -121),
        types.scaleFUnits(-1883, 4194),
    );
}

test "v40 grayscale targets center vertical phantom points" {
    try std.testing.expectEqual(
        @as(i32, 600),
        verticalPhantomX(.cleartype, .normal, 1200),
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        verticalPhantomX(.cleartype, .lcd, 1200),
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        verticalPhantomX(.classic, .normal, 1200),
    );
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
