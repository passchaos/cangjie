//! Retained caller-owned storage for repeated TrueType glyph transactions.

const std = @import("std");

const glyph = @import("../../glyph.zig");
const outline = @import("outline.zig");
const types = @import("types.zig");

/// Reusable transaction storage with the same single-loader lifecycle as
/// FreeType's `FT_GlyphLoader`. A returned transaction borrows the buffer and
/// is invalidated by the next decode or `deinit`; it must not be individually
/// deinitialized.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    simple_storage: std.ArrayList(outline.Point) = .empty,
    normalized_coords: std.ArrayList(f32) = .empty,
    fallback_arena: std.heap.ArenaAllocator,
    fallback_points: std.ArrayList(outline.Point) = .empty,
    fallback_flags: std.ArrayList(outline.PointFlag) = .empty,
    transaction: outline.Transaction,
    has_transaction: bool = false,
    fallback_active: bool = false,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{
            .allocator = allocator,
            .fallback_arena = .init(allocator),
            .transaction = emptyTransaction(allocator),
        };
    }

    pub fn deinit(self: *Buffer) void {
        self.fallback_flags.deinit(self.allocator);
        self.fallback_points.deinit(self.allocator);
        self.fallback_arena.deinit();
        self.normalized_coords.deinit(self.allocator);
        self.simple_storage.deinit(self.allocator);
        self.* = undefined;
    }

    /// Return the latest transaction, or null before a successful decode and
    /// after a failed decode attempt.
    pub fn current(self: *Buffer) ?*outline.Transaction {
        return if (self.has_transaction) &self.transaction else null;
    }

    pub fn resetRetainingCapacity(self: *Buffer) void {
        self.has_transaction = false;
        if (self.fallback_active) {
            _ = self.fallback_arena.reset(.retain_capacity);
            self.fallback_active = false;
        }
        self.fallback_points.clearRetainingCapacity();
        self.fallback_flags.clearRetainingCapacity();
        self.clearSimple();
        self.transaction = emptyTransaction(self.allocator);
    }

    pub fn decodeSimple(
        self: *Buffer,
        face_identity: usize,
        target: types.Target,
        interpreter: types.Interpreter,
        glyph_id: glyph.GlyphId,
        data: []const u8,
        contour_count: u16,
        metrics: outline.Metrics,
        scale_16_16: i32,
        variation: ?outline.Variation,
        normalized_coords: []const f32,
    ) types.Error!*outline.Transaction {
        self.resetSimpleRetainingCapacity();
        errdefer self.resetSimpleRetainingCapacity();
        var transaction = try outline.decodeSimpleIntoStorage(
            self.allocator,
            &self.simple_storage,
            face_identity,
            target,
            interpreter,
            glyph_id,
            data,
            contour_count,
            metrics,
            scale_16_16,
            variation,
        );
        try self.normalized_coords.appendSlice(
            self.allocator,
            normalized_coords,
        );
        transaction.normalized_coords = self.normalized_coords.items;
        if (transaction.variation) |*context| {
            context.normalized_coords = transaction.normalized_coords;
        }
        self.transaction = transaction;
        self.has_transaction = true;
        return &self.transaction;
    }

    /// Arena-backed fallback used until compound construction also writes
    /// directly into typed retained storage.
    pub fn fallbackAllocator(self: *Buffer) std.mem.Allocator {
        self.fallback_active = true;
        return self.fallback_arena.allocator();
    }

    /// Publish a newly decoded compound and retain its pristine mutable state.
    pub fn publishFallback(
        self: *Buffer,
        source: outline.Transaction,
    ) types.Error!*outline.Transaction {
        var transaction = source;
        const snapshot_len = std.math.mul(
            usize,
            transaction.points.len,
            3,
        ) catch return error.OutOfMemory;
        self.fallback_points.clearRetainingCapacity();
        self.fallback_flags.clearRetainingCapacity();
        try self.fallback_points.ensureTotalCapacity(
            self.allocator,
            snapshot_len,
        );
        try self.fallback_flags.ensureTotalCapacity(
            self.allocator,
            transaction.flags.len,
        );
        self.fallback_points.appendSliceAssumeCapacity(transaction.points);
        self.fallback_points.appendSliceAssumeCapacity(transaction.original);
        self.fallback_points.appendSliceAssumeCapacity(transaction.unscaled);
        self.fallback_flags.appendSliceAssumeCapacity(transaction.flags);
        // Point storage remains arena-owned, but derived PixelOutline values
        // are independent owners and must use the buffer's public allocator.
        transaction.allocator = self.allocator;
        self.transaction = transaction;
        self.has_transaction = true;
        return &self.transaction;
    }

    /// Restore a cached compound before repeated execution. Compound assembly
    /// depends only on the immutable face and the complete instance key below;
    /// CVT/storage state is consumed later by the VM and is intentionally not
    /// cached here.
    pub fn currentCompoundFor(
        self: *Buffer,
        face_identity: usize,
        glyph_id: glyph.GlyphId,
        scale_16_16: i32,
        target: types.Target,
        interpreter: types.Interpreter,
        hinting_enabled: bool,
        backward_compatibility: bool,
        normalized_coords: []const f32,
    ) ?*outline.Transaction {
        const transaction = &self.transaction;
        if (!self.fallback_active or !self.has_transaction or
            !transaction.is_compound or
            transaction.face_identity != face_identity or
            transaction.glyph_id != glyph_id or
            transaction.scale_16_16 != scale_16_16 or
            transaction.target != target or
            transaction.interpreter != interpreter or
            transaction.hinting_enabled != hinting_enabled or
            transaction.backward_compatibility != backward_compatibility or
            !locationsEqual(transaction.normalized_coords, normalized_coords))
        {
            return null;
        }
        const count = transaction.points.len;
        if (self.fallback_points.items.len != count * 3 or
            self.fallback_flags.items.len != transaction.flags.len) return null;
        @memcpy(transaction.points, self.fallback_points.items[0..count]);
        @memcpy(
            transaction.original,
            self.fallback_points.items[count .. count * 2],
        );
        @memcpy(
            transaction.unscaled,
            self.fallback_points.items[count * 2 .. count * 3],
        );
        @memcpy(transaction.flags, self.fallback_flags.items);
        transaction.grid_fit_metrics = false;
        transaction.metric_advance_26_6 = 0;
        return transaction;
    }

    fn resetSimpleRetainingCapacity(self: *Buffer) void {
        self.has_transaction = false;
        self.clearSimple();
        self.transaction = emptyTransaction(self.allocator);
    }

    fn clearSimple(self: *Buffer) void {
        self.simple_storage.clearRetainingCapacity();
        self.normalized_coords.clearRetainingCapacity();
    }
};

fn locationsEqual(first: []const f32, second: []const f32) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| {
        if (@as(u32, @bitCast(a)) != @as(u32, @bitCast(b))) return false;
    }
    return true;
}

fn emptyTransaction(allocator: std.mem.Allocator) outline.Transaction {
    return .{
        .allocator = allocator,
        .face_identity = 0,
        .target = .normal,
        .interpreter = .classic,
        .glyph_id = 0,
        .real_point_count = 0,
        .points = &.{},
        .original = &.{},
        .unscaled = &.{},
        .flags = &.{},
        .contours = &.{},
        .instructions = &.{},
        .scale_16_16 = 0,
    };
}
