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

    /// Publish a compound decoded into the retained arena. The next load
    /// resets the arena and decodes fresh data while preserving capacity.
    pub fn publishFallback(
        self: *Buffer,
        transaction: outline.Transaction,
    ) *outline.Transaction {
        self.transaction = transaction;
        self.has_transaction = true;
        return &self.transaction;
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
