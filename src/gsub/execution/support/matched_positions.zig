//! Stack-first storage for positions already consumed by one lookup.

const std = @import("std");

pub const stack_capacity = 128;

pub const Scratch = struct {
    items: []bool,
    heap: ?[]bool = null,

    pub fn init(
        allocator: std.mem.Allocator,
        len: usize,
        stack: *[stack_capacity]bool,
    ) std.mem.Allocator.Error!Scratch {
        const result: Scratch = if (len <= stack.len)
            .{ .items = stack[0..len] }
        else blk: {
            const heap = try allocator.alloc(bool, len);
            break :blk .{ .items = heap, .heap = heap };
        };
        @memset(result.items, false);
        return result;
    }

    pub fn deinit(self: Scratch, allocator: std.mem.Allocator) void {
        if (self.heap) |heap| allocator.free(heap);
    }
};
