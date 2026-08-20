//! Stack-first boolean scratch for ExtensionPos subtable precedence.

const std = @import("std");

pub const stack_capacity = 128;

pub const Bool = struct {
    items: []bool,
    heap: ?[]bool = null,

    pub fn init(
        allocator: std.mem.Allocator,
        length: usize,
        stack: *[stack_capacity]bool,
    ) std.mem.Allocator.Error!Bool {
        if (length <= stack.len) return .{ .items = stack[0..length] };
        const heap = try allocator.alloc(bool, length);
        return .{ .items = heap, .heap = heap };
    }

    pub fn deinit(self: Bool, allocator: std.mem.Allocator) void {
        if (self.heap) |heap| allocator.free(heap);
    }
};
