//! Shared recursion and typed-byte ownership guard for COLR v1 Paint DAGs.

const std = @import("std");

const core = @import("core.zig");
const types = @import("types.zig");

const max_graph_depth = 64;
const max_owned_ranges = 2048;

pub const Guard = struct {
    stack: [max_graph_depth]usize = undefined,
    owned_ranges: [max_owned_ranges]types.Range = undefined,
    forbidden_range: ?types.Range = null,
    depth: usize = 0,
    owned_range_count: usize = 0,

    pub fn enter(self: *Guard, offset: usize) types.Error!void {
        for (self.stack[0..self.depth]) |active_offset| {
            if (active_offset == offset) return error.BadSfnt;
        }
        if (self.depth == self.stack.len) return error.BadSfnt;
        self.stack[self.depth] = offset;
        self.depth += 1;
    }

    pub fn leave(self: *Guard) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    pub fn claimPaintRecord(
        self: *Guard,
        data: []const u8,
        table: types.Table,
        offset: usize,
        info: types.FormatInfo,
    ) types.Error!void {
        try self.claimRange(.{
            .start = offset,
            .end = offset + info.min_size,
        });
        switch (data[offset]) {
            12, 13 => try self.claimRange(try core.transformPayloadRange(
                data,
                table,
                offset,
                info.min_size,
            )),
            4...9 => try self.claimRange(try core.colorLineRange(
                data,
                table,
                offset,
                info.min_size,
                core.usesVariableColorLine(data[offset]),
            )),
            else => {},
        }
    }

    pub fn claimRange(
        self: *Guard,
        range: types.Range,
    ) types.Error!void {
        if (range.start >= range.end) return error.BadSfnt;
        if (self.forbidden_range) |forbidden| {
            if (core.overlaps(range, forbidden)) return error.BadSfnt;
        }
        for (self.owned_ranges[0..self.owned_range_count]) |owned| {
            // Exact DAG sharing is valid. Partial overlap would reinterpret
            // typed bytes at a second boundary and is therefore malformed.
            if (range.start == owned.start and range.end == owned.end) return;
            if (core.overlaps(range, owned)) return error.BadSfnt;
        }
        if (self.owned_range_count == self.owned_ranges.len) {
            return error.BadSfnt;
        }
        self.owned_ranges[self.owned_range_count] = range;
        self.owned_range_count += 1;
    }
};

test "guard accepts exact sharing and rejects recursion and partial overlap" {
    var guard = Guard{};
    try guard.enter(10);
    try std.testing.expectError(error.BadSfnt, guard.enter(10));
    guard.leave();

    try guard.claimRange(.{ .start = 10, .end = 20 });
    try guard.claimRange(.{ .start = 10, .end = 20 });
    try std.testing.expectError(
        error.BadSfnt,
        guard.claimRange(.{ .start = 15, .end = 25 }),
    );
}
