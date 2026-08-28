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
const compatibility = @import("compatibility.zig");
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
    hinting_enabled: bool,
    twilight: Twilight,
};

pub fn execute(
    allocator: std.mem.Allocator,
    state: InstanceState,
    transaction: *outline.Transaction,
    component_resolver: ?compound.Resolver,
) types.Error!void {
    try state.twilight.validate();
    try validateTransactionIdentity(state, transaction);

    var work = try Work.init(allocator, state, component_resolver);
    defer work.deinit();
    var glyph = try OwnedGlyph.clone(allocator, transaction);
    defer glyph.deinit();

    try work.executeGlyph(&glyph.transaction);

    @memcpy(transaction.points, glyph.transaction.points);
    @memcpy(transaction.original, glyph.transaction.original);
    @memcpy(transaction.unscaled, glyph.transaction.unscaled);
    @memcpy(transaction.flags, glyph.transaction.flags);
    transaction.grid_fit_metrics = glyph.transaction.grid_fit_metrics;
    transaction.metric_advance_26_6 =
        glyph.transaction.metric_advance_26_6;
    work.commit(state);
}

/// Execute directly against a parsed-face transaction.
///
/// This deliberately omits the rollback copies used by `execute`: the caller
/// has crossed whole-face validation, so malformed glyph bytecode is no longer
/// an expected recoverable input. The reusable instance remains mutable, just
/// like a FreeType size/slot pair after a successful `FT_Load_Glyph`.
pub fn executeAfterProof(
    allocator: std.mem.Allocator,
    state: InstanceState,
    transaction: *outline.Transaction,
    component_resolver: ?compound.Resolver,
) types.Error!void {
    try state.twilight.validate();
    try validateTransactionIdentity(state, transaction);
    var work = Work{
        .allocator = allocator,
        .state = state,
        .resolver = component_resolver,
        .cvt = state.cvt,
        .storage = state.storage,
        .twilight_points = state.twilight.points,
        .twilight_original = state.twilight.original,
        .twilight_unscaled = state.twilight.unscaled,
        .twilight_flags = state.twilight.flags,
        .retained = state.graphics,
        .compatibility = compatibility.State.init(
            state.source.interpreter,
            state.graphics.target,
            state.graphics.instruct_control,
            state.source.tricky,
        ),
    };
    try work.executeGlyph(transaction);
}

fn validateTransactionIdentity(
    state: InstanceState,
    transaction: *const outline.Transaction,
) types.Error!void {
    if (transaction.face_identity != state.source.face_identity or
        transaction.scale_16_16 != state.graphics.scale_16_16 or
        transaction.target != state.graphics.target or
        transaction.interpreter != state.source.interpreter or
        transaction.hinting_enabled != state.hinting_enabled or
        transaction.backward_compatibility !=
            compatibility.State.init(
                state.source.interpreter,
                state.graphics.target,
                state.graphics.instruct_control,
                state.source.tricky,
            ).active() or
        !locationsEqual(
            transaction.normalized_coords,
            state.source.normalized_coords,
        ))
    {
        return error.StaleHintingInstance;
    }
    try validateTransaction(transaction);
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
    compatibility: compatibility.State,
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
            .compatibility = compatibility.State.init(
                state.source.interpreter,
                state.graphics.target,
                state.graphics.instruct_control,
                state.source.tricky,
            ),
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
        // Clear only IUP tracking. A glyph-local INSTCTRL waiver persists
        // through sibling components and parent bytecode in this atomic
        // top-level load, then Work disposal resets it for the next glyph.
        self.compatibility.beginGlyph(transaction.is_compound);
        transaction.grid_fit_metrics = false;
        transaction.metric_advance_26_6 =
            transaction.phantomPoints()[1].x -|
            transaction.phantomPoints()[0].x;
        if (!self.state.hinting_enabled) return;
        if (transaction.is_compound) {
            try self.executeCompound(transaction);
        } else {
            const metric_phantoms = transaction.phantomPoints().*;
            roundPhantomPoints(
                transaction.points,
                transaction.real_point_count,
            );
            if (transaction.instructions.len != 0) {
                try self.runProgram(
                    transaction,
                    transaction.scale_16_16,
                    false,
                );
            }
            // v40 keeps the unrounded phantom origin/metrics owner; the
            // public accessor applies base-layer advance rounding.
            if (self.compatibility.active()) {
                transaction.mutablePhantomPoints().* = metric_phantoms;
            }
        }
        transaction.grid_fit_metrics = true;
    }

    fn executeCompound(
        self: *Work,
        transaction: *outline.Transaction,
    ) types.Error!void {
        const resolver = self.resolver orelse
            return error.UnsupportedHintGlyph;
        for (transaction.components) |*component_record| {
            var child = try OwnedGlyph.decode(
                self.allocator,
                transaction,
                .{
                    .glyph_id = component_record.glyph_id,
                    .data = component_record.data,
                    .metrics = component_record.metrics,
                },
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
                component_record.*,
                &child.transaction,
                self.compatibility,
            );
            if (component_record.use_my_metrics) {
                @memcpy(
                    transaction.points[transaction.real_point_count..],
                    child.transaction.points[child.transaction.real_point_count..],
                );
            }
        }

        if (transaction.instructions.len == 0) return;
        // Parent bytecode observes already-hinted, placed component points.
        // FreeType resets touched flags and treats this device-space geometry
        // as both original and unscaled, so projection scaling is identity.
        @memcpy(transaction.original, transaction.points);
        @memcpy(transaction.unscaled, transaction.points);
        for (transaction.flags[0..transaction.real_point_count]) |*flag| {
            flag.touched_x = false;
            flag.touched_y = false;
        }
        // USE_MY_METRICS may have selected a child's phantom owner.
        const metric_phantoms = transaction.phantomPoints().*;
        roundPhantomPoints(
            transaction.points,
            transaction.real_point_count,
        );
        try self.runProgram(transaction, 0x10000, true);
        if (self.compatibility.active()) {
            transaction.mutablePhantomPoints().* = metric_phantoms;
        }
    }

    fn runProgram(
        self: *Work,
        transaction: *outline.Transaction,
        point_scale_16_16: i32,
        is_compound: bool,
    ) types.Error!void {
        // Every glyph program starts from the retained prep graphics state.
        // CVT, storage, twilight, and the glyph-local native-ClearType waiver
        // are shared through a compound load. Other transient graphics
        // changes must not seed the next child or its parent.
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
        interpreter.compatibility = self.compatibility;
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
            is_compound,
        );
        try interpreter.run(.glyph);
        self.compatibility = interpreter.compatibility;
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
        var transaction = outline.Transaction{
            .allocator = allocator,
            .face_identity = source.face_identity,
            .target = source.target,
            .interpreter = source.interpreter,
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
            .variation = source.variation,
            .is_compound = source.is_compound,
            .hinting_enabled = source.hinting_enabled,
            .backward_compatibility = source.backward_compatibility,
            .grid_fit_metrics = source.grid_fit_metrics,
            .metric_advance_26_6 = source.metric_advance_26_6,
        };
        if (transaction.variation) |*context| {
            context.normalized_coords = normalized_coords;
        }
        return .{ .transaction = transaction };
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
                parent.interpreter,
                source.glyph_id,
                source.data,
                @intCast(contour_count),
                source.metrics,
                parent.scale_16_16,
                // A compound child must execute against the same varied
                // outline that was expanded into the parent transaction.
                // Re-decoding a simple child at the default instance would
                // silently replace its gvar-adjusted points before hinting.
                parent.variation,
            )
        else
            try compound.decode(
                allocator,
                parent.face_identity,
                parent.target,
                parent.interpreter,
                parent.hinting_enabled,
                parent.backward_compatibility,
                source,
                parent.scale_16_16,
                max_component_depth,
                resolver,
                parent.variation,
            );
        var owned = transaction;
        owned.normalized_coords = if (parent.normalized_coords.len == 0)
            @constCast(&.{})
        else
            try allocator.dupe(f32, parent.normalized_coords);
        if (owned.variation) |*context| {
            context.normalized_coords = owned.normalized_coords;
        }
        return .{ .transaction = owned };
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
        .x = outline.verticalPhantomX(
            parent.interpreter,
            parent.target,
            source.metrics.advance_width,
        ),
        .y = source.metrics.bounds.y_max +
            source.metrics.top_side_bearing,
    };
    unscaled[3] = .{
        .x = outline.verticalPhantomX(
            parent.interpreter,
            parent.target,
            source.metrics.advance_width,
        ),
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
        .interpreter = parent.interpreter,
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
        .variation = parent.variation,
        .hinting_enabled = parent.hinting_enabled,
        .backward_compatibility = parent.backward_compatibility,
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
    policy: compatibility.State,
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
                if (!policy.active()) {
                    scaled.x = compound.roundGrid(scaled.x);
                }
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

test "v40 skips component X grid rounding" {
    var parent_points = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 650, .y = 0 },
        .{ .x = 0, .y = 650 },
        .{ .x = 0, .y = -650 },
    };
    var parent_original = parent_points;
    var parent_unscaled = parent_points;
    var parent_flags = [_]outline.PointFlag{.{}} ** parent_points.len;
    var child_points = [_]outline.Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 640, .y = 0 },
        .{ .x = 0, .y = 640 },
        .{ .x = 0, .y = -640 },
    };
    var child_original = child_points;
    var child_unscaled = child_points;
    var child_flags = [_]outline.PointFlag{.{}} ** child_points.len;
    var parent = outline.Transaction{
        .allocator = std.testing.allocator,
        .face_identity = 1,
        .target = .normal,
        .interpreter = .cleartype,
        .glyph_id = 2,
        .real_point_count = 1,
        .points = &parent_points,
        .original = &parent_original,
        .unscaled = &parent_unscaled,
        .flags = &parent_flags,
        .contours = @constCast(&[_]u16{0}),
        .instructions = &.{},
        .scale_16_16 = 0x10000,
        .metric_advance_26_6 = 0,
    };
    const child = outline.Transaction{
        .allocator = std.testing.allocator,
        .face_identity = 1,
        .target = .normal,
        .interpreter = .cleartype,
        .glyph_id = 1,
        .real_point_count = 1,
        .points = &child_points,
        .original = &child_original,
        .unscaled = &child_unscaled,
        .flags = &child_flags,
        .contours = @constCast(&[_]u16{0}),
        .instructions = &.{},
        .scale_16_16 = 0x10000,
        .metric_advance_26_6 = 0,
    };
    const record = outline.ComponentRecord{
        .glyph_id = 1,
        .data = &.{},
        .metrics = .{
            .bounds = .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 },
            .advance_width = 0,
            .left_side_bearing = 0,
            .vertical_advance = 0,
            .top_side_bearing = 0,
        },
        .flags = 0x0004,
        .point_start = 0,
        .point_len = 1,
        .contour_start = 0,
        .contour_len = 1,
        .transform = .{},
        .placement = .{ .offset = .{ .x = 10, .y = 10 } },
        .use_my_metrics = false,
        .is_compound = false,
        .instructions = &.{},
    };

    try placeComponent(
        &parent,
        record,
        &child,
        compatibility.State.init(.cleartype, .normal, 0, false),
    );
    try std.testing.expectEqual(
        outline.Point{ .x = 10, .y = 0 },
        parent.points[0],
    );
}
