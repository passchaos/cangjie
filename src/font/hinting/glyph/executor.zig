//! Atomic TrueType glyph-program execution.
//!
//! A glyph program can write every point zone plus CVT and storage.  This
//! executor clones all of those mutable surfaces before entering the VM and
//! publishes them only after successful completion.  The PPEM `Instance`
//! therefore remains reusable after malformed or unsupported glyph bytecode.

const std = @import("std");

const bin = @import("../../../binary.zig");
const compound = @import("../compound.zig");
const outline = @import("../outline.zig");
const program = @import("../program.zig");
const types = @import("../types.zig");
const vm_mod = @import("../vm.zig");
const zones = @import("zones.zig");

pub const Twilight = struct {
    points: []outline.Point,
    original: []outline.Point,
    unscaled: []outline.Point,
    flags: []outline.PointFlag,

    fn validate(self: Twilight) types.Error!void {
        if (self.points.len != self.original.len or
            self.points.len != self.unscaled.len or
            self.points.len != self.flags.len)
        {
            return error.InvalidHintOperand;
        }
    }
};

pub const InstanceState = struct {
    source: types.Source,
    definitions: program.Definitions,
    stack: []i32,
    cvt: []i32,
    storage: []i32,
    graphics: types.RetainedGraphicsState,
    twilight: Twilight,
};

pub fn execute(
    allocator: std.mem.Allocator,
    state: InstanceState,
    transaction: *outline.Transaction,
    component_resolver: ?compound.Resolver,
) types.Error!void {
    try state.twilight.validate();
    if (transaction.face_identity != state.source.face_identity or
        transaction.scale_16_16 != state.graphics.scale_16_16 or
        transaction.target != state.graphics.target or
        !locationsEqual(
            transaction.normalized_coords,
            state.source.normalized_coords,
        ))
    {
        return error.StaleHintingInstance;
    }
    try validateTransaction(transaction);

    var work = try Work.init(allocator, state, component_resolver);
    defer work.deinit();
    var glyph = try OwnedGlyph.clone(allocator, transaction);
    defer glyph.deinit();

    try work.executeGlyph(&glyph.transaction);

    @memcpy(transaction.points, glyph.transaction.points);
    @memcpy(transaction.original, glyph.transaction.original);
    @memcpy(transaction.unscaled, glyph.transaction.unscaled);
    @memcpy(transaction.flags, glyph.transaction.flags);
    work.commit(state);
}

const Work = struct {
    allocator: std.mem.Allocator,
    state: InstanceState,
    resolver: ?compound.Resolver,
    cvt: []i32,
    storage: []i32,
    twilight_points: []outline.Point,
    twilight_original: []outline.Point,
    twilight_unscaled: []outline.Point,
    twilight_flags: []outline.PointFlag,
    retained: types.RetainedGraphicsState,
    depth: usize = 0,

    fn init(
        allocator: std.mem.Allocator,
        state: InstanceState,
        resolver: ?compound.Resolver,
    ) types.Error!Work {
        const cvt = try allocator.dupe(i32, state.cvt);
        errdefer allocator.free(cvt);
        const storage = try allocator.dupe(i32, state.storage);
        errdefer allocator.free(storage);
        const twilight_points = try allocator.dupe(
            outline.Point,
            state.twilight.points,
        );
        errdefer allocator.free(twilight_points);
        const twilight_original = try allocator.dupe(
            outline.Point,
            state.twilight.original,
        );
        errdefer allocator.free(twilight_original);
        const twilight_unscaled = try allocator.dupe(
            outline.Point,
            state.twilight.unscaled,
        );
        errdefer allocator.free(twilight_unscaled);
        const twilight_flags = try allocator.dupe(
            outline.PointFlag,
            state.twilight.flags,
        );
        errdefer allocator.free(twilight_flags);
        return .{
            .allocator = allocator,
            .state = state,
            .resolver = resolver,
            .cvt = cvt,
            .storage = storage,
            .twilight_points = twilight_points,
            .twilight_original = twilight_original,
            .twilight_unscaled = twilight_unscaled,
            .twilight_flags = twilight_flags,
            .retained = state.graphics,
        };
    }

    fn deinit(self: *Work) void {
        self.allocator.free(self.twilight_flags);
        self.allocator.free(self.twilight_unscaled);
        self.allocator.free(self.twilight_original);
        self.allocator.free(self.twilight_points);
        self.allocator.free(self.storage);
        self.allocator.free(self.cvt);
        self.* = undefined;
    }

    fn commit(self: *const Work, state: InstanceState) void {
        @memcpy(state.twilight.points, self.twilight_points);
        @memcpy(state.twilight.original, self.twilight_original);
        @memcpy(state.twilight.unscaled, self.twilight_unscaled);
        @memcpy(state.twilight.flags, self.twilight_flags);
        @memcpy(state.cvt, self.cvt);
        @memcpy(state.storage, self.storage);
    }

    fn executeGlyph(
        self: *Work,
        transaction: *outline.Transaction,
    ) types.Error!void {
        if (self.depth > self.state.source.limits.max_component_depth) {
            return error.UnsupportedHintGlyph;
        }
        self.depth += 1;
        defer self.depth -= 1;
        if (transaction.is_compound) {
            return self.executeCompound(transaction);
        }
        roundPhantomPoints(
            transaction.points,
            transaction.real_point_count,
        );
        if ((self.retained.instruct_control & 1) != 0 or
            transaction.instructions.len == 0)
        {
            return;
        }
        return self.runProgram(transaction, transaction.scale_16_16);
    }

    fn executeCompound(
        self: *Work,
        transaction: *outline.Transaction,
    ) types.Error!void {
        const resolver = self.resolver orelse
            return error.UnsupportedHintGlyph;
        for (transaction.components) |component_record| {
            const source = try resolver.resolve(component_record.glyph_id);
            var child = try OwnedGlyph.decode(
                self.allocator,
                transaction,
                source,
                @intCast(self.state.source.limits.max_component_depth),
                resolver,
            );
            defer child.deinit();
            if (child.transaction.real_point_count != component_record.point_len) {
                return error.BadSfnt;
            }
            try self.executeGlyph(&child.transaction);
            try placeComponent(
                transaction,
                component_record,
                &child.transaction,
            );
            if (component_record.use_my_metrics) {
                @memcpy(
                    transaction.points[transaction.real_point_count..],
                    child.transaction.points[child.transaction.real_point_count..],
                );
            }
        }

        if ((self.retained.instruct_control & 1) != 0 or
            transaction.instructions.len == 0)
        {
            return;
        }
        // Parent bytecode observes already-hinted, placed component points.
        // FreeType resets touched flags and treats this device-space geometry
        // as both original and unscaled, so projection scaling is identity.
        @memcpy(transaction.original, transaction.points);
        @memcpy(transaction.unscaled, transaction.points);
        for (transaction.flags[0..transaction.real_point_count]) |*flag| {
            flag.touched_x = false;
            flag.touched_y = false;
        }
        roundPhantomPoints(
            transaction.points,
            transaction.real_point_count,
        );
        return self.runProgram(transaction, 0x10000);
    }

    fn runProgram(
        self: *Work,
        transaction: *outline.Transaction,
        point_scale_16_16: i32,
    ) types.Error!void {
        // Every glyph program starts from the retained prep graphics state.
        // CVT, storage, and twilight are shared through the compound load, but
        // transient/program graphics changes from one child must not seed the
        // next child or its parent.
        self.retained = self.state.graphics;
        var source = self.state.source;
        source.glyph_program = transaction.instructions;
        var interpreter = vm_mod.Vm.init(
            source,
            self.state.definitions,
            self.state.stack,
            self.cvt,
            self.storage,
            &self.retained,
        );
        try interpreter.attachZones(
            zone(
                self.twilight_points,
                self.twilight_original,
                self.twilight_unscaled,
                self.twilight_flags,
                &.{},
                self.twilight_points.len,
            ),
            zone(
                transaction.points,
                transaction.original,
                transaction.unscaled,
                transaction.flags,
                transaction.contours,
                transaction.real_point_count,
            ),
            point_scale_16_16,
        );
        return interpreter.run(.glyph);
    }
};

const OwnedGlyph = struct {
    transaction: outline.Transaction,

    fn clone(
        allocator: std.mem.Allocator,
        source: *const outline.Transaction,
    ) types.Error!OwnedGlyph {
        const points = try allocator.dupe(outline.Point, source.points);
        errdefer allocator.free(points);
        const original = try allocator.dupe(outline.Point, source.original);
        errdefer allocator.free(original);
        const unscaled = try allocator.dupe(outline.Point, source.unscaled);
        errdefer allocator.free(unscaled);
        const flags = try allocator.dupe(outline.PointFlag, source.flags);
        errdefer allocator.free(flags);
        const contours = try allocator.dupe(u16, source.contours);
        errdefer allocator.free(contours);
        const components: []outline.ComponentRecord =
            if (source.components.len == 0)
                @constCast(&.{})
            else
                try allocator.dupe(
                    outline.ComponentRecord,
                    source.components,
                );
        errdefer if (components.len != 0) allocator.free(components);
        const normalized_coords: []f32 =
            if (source.normalized_coords.len == 0)
                @constCast(&.{})
            else
                try allocator.dupe(f32, source.normalized_coords);
        errdefer if (normalized_coords.len != 0)
            allocator.free(normalized_coords);
        return .{ .transaction = .{
            .allocator = allocator,
            .face_identity = source.face_identity,
            .target = source.target,
            .glyph_id = source.glyph_id,
            .real_point_count = source.real_point_count,
            .points = points,
            .original = original,
            .unscaled = unscaled,
            .flags = flags,
            .contours = contours,
            .components = components,
            .instructions = source.instructions,
            .scale_16_16 = source.scale_16_16,
            .normalized_coords = normalized_coords,
            .is_compound = source.is_compound,
        } };
    }

    fn decode(
        allocator: std.mem.Allocator,
        parent: *const outline.Transaction,
        source: compound.Source,
        max_component_depth: u16,
        resolver: compound.Resolver,
    ) types.Error!OwnedGlyph {
        if (source.data.len == 0) {
            return .{ .transaction = try emptyTransaction(
                allocator,
                parent,
                source,
            ) };
        }
        const contour_count = bin.readI16At(source.data, 0) catch
            return error.BadSfnt;
        const transaction = if (contour_count >= 0)
            try outline.decodeSimple(
                allocator,
                parent.face_identity,
                parent.target,
                source.glyph_id,
                source.data,
                @intCast(contour_count),
                source.metrics,
                parent.scale_16_16,
                null,
            )
        else
            try compound.decode(
                allocator,
                parent.face_identity,
                parent.target,
                source,
                parent.scale_16_16,
                max_component_depth,
                resolver,
            );
        return .{ .transaction = transaction };
    }

    fn deinit(self: *OwnedGlyph) void {
        self.transaction.deinit();
        self.* = undefined;
    }
};

fn emptyTransaction(
    allocator: std.mem.Allocator,
    parent: *const outline.Transaction,
    source: compound.Source,
) types.Error!outline.Transaction {
    const points = try allocator.alloc(outline.Point, 4);
    errdefer allocator.free(points);
    const original = try allocator.alloc(outline.Point, 4);
    errdefer allocator.free(original);
    const unscaled = try allocator.alloc(outline.Point, 4);
    errdefer allocator.free(unscaled);
    const flags = try allocator.alloc(outline.PointFlag, 4);
    errdefer allocator.free(flags);
    @memset(flags, .{});
    const left =
        source.metrics.bounds.x_min - source.metrics.left_side_bearing;
    unscaled[0] = .{ .x = left, .y = 0 };
    unscaled[1] = .{
        .x = left + source.metrics.advance_width,
        .y = 0,
    };
    unscaled[2] = .{
        .x = 0,
        .y = source.metrics.bounds.y_max +
            source.metrics.top_side_bearing,
    };
    unscaled[3] = .{
        .x = 0,
        .y = source.metrics.bounds.y_max +
            source.metrics.top_side_bearing -
            source.metrics.vertical_advance,
    };
    for (unscaled, original, points) |raw, *origin, *point| {
        origin.* = .{
            .x = types.scaleFUnits(raw.x, parent.scale_16_16),
            .y = types.scaleFUnits(raw.y, parent.scale_16_16),
        };
        point.* = origin.*;
    }
    const normalized_coords: []f32 =
        if (parent.normalized_coords.len == 0)
            @constCast(&.{})
        else
            try allocator.dupe(f32, parent.normalized_coords);
    errdefer if (normalized_coords.len != 0)
        allocator.free(normalized_coords);
    return .{
        .allocator = allocator,
        .face_identity = parent.face_identity,
        .target = parent.target,
        .glyph_id = source.glyph_id,
        .real_point_count = 0,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = &.{},
        .components = &.{},
        .instructions = &.{},
        .scale_16_16 = parent.scale_16_16,
        .normalized_coords = normalized_coords,
    };
}

fn locationsEqual(first: []const f32, second: []const f32) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| {
        if (@as(u32, @bitCast(a)) != @as(u32, @bitCast(b))) return false;
    }
    return true;
}

const ComponentOffsets = struct {
    scaled: outline.Point,
    unscaled: outline.Point,
};

fn placeComponent(
    parent: *outline.Transaction,
    record: outline.ComponentRecord,
    child: *const outline.Transaction,
) types.Error!void {
    const point_end = record.point_start + record.point_len;
    if (point_end > parent.real_point_count or
        record.contour_start + record.contour_len > parent.contours.len)
    {
        return error.BadSfnt;
    }
    const transform = compound.FixedTransform{
        .xx = record.transform.xx,
        .yx = record.transform.yx,
        .xy = record.transform.xy,
        .yy = record.transform.yy,
    };
    for (
        parent.points[record.point_start..point_end],
        child.points[0..child.real_point_count],
    ) |*destination, point| {
        destination.* = compound.applyTransform(point, transform);
    }
    for (
        parent.original[record.point_start..point_end],
        child.original[0..child.real_point_count],
    ) |*destination, point| {
        destination.* = compound.applyTransform(point, transform);
    }
    for (
        parent.unscaled[record.point_start..point_end],
        child.unscaled[0..child.real_point_count],
    ) |*destination, point| {
        destination.* = compound.applyTransform(point, transform);
    }
    @memcpy(
        parent.flags[record.point_start..point_end],
        child.flags[0..child.real_point_count],
    );

    const offsets = switch (record.placement) {
        .offset => |raw| blk: {
            var unscaled = outline.Point{ .x = raw.x, .y = raw.y };
            if ((record.flags & 0x0800) != 0) {
                unscaled = compound.scaleComponentOffset(
                    unscaled,
                    transform,
                );
            }
            var scaled = outline.Point{
                .x = types.scaleFUnits(
                    unscaled.x,
                    parent.scale_16_16,
                ),
                .y = types.scaleFUnits(
                    unscaled.y,
                    parent.scale_16_16,
                ),
            };
            if ((record.flags & 0x0004) != 0) {
                scaled.x = compound.roundGrid(scaled.x);
                scaled.y = compound.roundGrid(scaled.y);
            }
            break :blk ComponentOffsets{
                .scaled = scaled,
                .unscaled = unscaled,
            };
        },
        .points => |match| blk: {
            const parent_index = @as(usize, match.parent_point);
            const child_index =
                record.point_start + @as(usize, match.child_point);
            if (parent_index >= record.point_start or
                child_index >= point_end)
            {
                return error.BadSfnt;
            }
            break :blk ComponentOffsets{
                .scaled = outline.Point{
                    .x = parent.points[parent_index].x -|
                        parent.points[child_index].x,
                    .y = parent.points[parent_index].y -|
                        parent.points[child_index].y,
                },
                .unscaled = outline.Point{
                    .x = parent.unscaled[parent_index].x -|
                        parent.unscaled[child_index].x,
                    .y = parent.unscaled[parent_index].y -|
                        parent.unscaled[child_index].y,
                },
            };
        },
    };
    for (parent.points[record.point_start..point_end]) |*point| {
        point.x +|= offsets.scaled.x;
        point.y +|= offsets.scaled.y;
    }
    for (parent.original[record.point_start..point_end]) |*point| {
        point.x +|= offsets.scaled.x;
        point.y +|= offsets.scaled.y;
    }
    for (parent.unscaled[record.point_start..point_end]) |*point| {
        point.x +|= offsets.unscaled.x;
        point.y +|= offsets.unscaled.y;
    }
}

fn validateTransaction(transaction: *const outline.Transaction) types.Error!void {
    if (transaction.points.len != transaction.original.len or
        transaction.points.len != transaction.unscaled.len or
        transaction.points.len != transaction.flags.len or
        transaction.real_point_count + 4 != transaction.points.len)
    {
        return error.InvalidHintOperand;
    }
}

fn zone(
    current: []outline.Point,
    original: []outline.Point,
    unscaled: []outline.Point,
    flags: []outline.PointFlag,
    contours: []const u16,
    real_point_count: usize,
) zones.Zone {
    return .{
        .current = current,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .real_point_count = real_point_count,
    };
}

fn roundPhantomPoints(points: []outline.Point, real_point_count: usize) void {
    std.debug.assert(real_point_count + 4 == points.len);
    points[real_point_count].x =
        (points[real_point_count].x +| 32) & ~@as(i32, 63);
    points[real_point_count + 1].x =
        (points[real_point_count + 1].x +| 32) & ~@as(i32, 63);
    points[real_point_count + 2].y =
        (points[real_point_count + 2].y +| 32) & ~@as(i32, 63);
    points[real_point_count + 3].y =
        (points[real_point_count + 3].y +| 32) & ~@as(i32, 63);
}
