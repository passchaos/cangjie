//! Atomic TrueType glyph-program execution.
//!
//! A glyph program can write every point zone plus CVT and storage.  This
//! executor clones all of those mutable surfaces before entering the VM and
//! publishes them only after successful completion.  The PPEM `Instance`
//! therefore remains reusable after malformed or unsupported glyph bytecode.

const std = @import("std");

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
) types.Error!void {
    try state.twilight.validate();
    if (transaction.face_identity != state.source.face_identity or
        transaction.scale_16_16 != state.graphics.scale_16_16 or
        transaction.target != state.graphics.target)
    {
        return error.StaleHintingInstance;
    }
    try validateTransaction(transaction);

    // Phantom metrics are grid-fitted before bytecode, including when prep
    // disabled glyph instructions or the glyph program is empty.
    if ((state.graphics.instruct_control & 1) != 0) {
        roundPhantomPoints(transaction.points, transaction.real_point_count);
        return;
    }

    const glyph_points = try allocator.dupe(
        outline.Point,
        transaction.points,
    );
    defer allocator.free(glyph_points);
    const glyph_original = try allocator.dupe(
        outline.Point,
        transaction.original,
    );
    defer allocator.free(glyph_original);
    const glyph_unscaled = try allocator.dupe(
        outline.Point,
        transaction.unscaled,
    );
    defer allocator.free(glyph_unscaled);
    const glyph_flags = try allocator.dupe(
        outline.PointFlag,
        transaction.flags,
    );
    defer allocator.free(glyph_flags);

    const twilight_points = try allocator.dupe(
        outline.Point,
        state.twilight.points,
    );
    defer allocator.free(twilight_points);
    const twilight_original = try allocator.dupe(
        outline.Point,
        state.twilight.original,
    );
    defer allocator.free(twilight_original);
    const twilight_unscaled = try allocator.dupe(
        outline.Point,
        state.twilight.unscaled,
    );
    defer allocator.free(twilight_unscaled);
    const twilight_flags = try allocator.dupe(
        outline.PointFlag,
        state.twilight.flags,
    );
    defer allocator.free(twilight_flags);

    const cvt = try allocator.dupe(i32, state.cvt);
    defer allocator.free(cvt);
    const storage = try allocator.dupe(i32, state.storage);
    defer allocator.free(storage);
    var retained = state.graphics;

    roundPhantomPoints(glyph_points, transaction.real_point_count);
    var source = state.source;
    source.glyph_program = transaction.instructions;
    var interpreter = vm_mod.Vm.init(
        source,
        state.definitions,
        state.stack,
        cvt,
        storage,
        &retained,
    );
    try interpreter.attachZones(
        zone(
            twilight_points,
            twilight_original,
            twilight_unscaled,
            twilight_flags,
            &.{},
            twilight_points.len,
        ),
        zone(
            glyph_points,
            glyph_original,
            glyph_unscaled,
            glyph_flags,
            transaction.contours,
            transaction.real_point_count,
        ),
    );
    try interpreter.run(.glyph);

    @memcpy(transaction.points, glyph_points);
    @memcpy(transaction.original, glyph_original);
    @memcpy(transaction.unscaled, glyph_unscaled);
    @memcpy(transaction.flags, glyph_flags);
    @memcpy(state.twilight.points, twilight_points);
    @memcpy(state.twilight.original, twilight_original);
    @memcpy(state.twilight.unscaled, twilight_unscaled);
    @memcpy(state.twilight.flags, twilight_flags);
    @memcpy(state.cvt, cvt);
    @memcpy(state.storage, storage);
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
