//! GPOS recursive lookup preflight contracts.

const std = @import("std");
const table = @import("../../table/root.zig");
const validation = @import("../../validation/root.zig");

test "validation rejects truncated contextual records atomically" {
    var bytes = [_]u8{0} ** 36;
    writeU16(&bytes, 8, 12);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 4);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 8);
    // Context rule declares two records but only one fits.
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 0);
    writeU16(&bytes, 30, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = 32,
    };
    try std.testing.expectError(
        error.BadGpos,
        validation.lookup.records(view, 28, 2, 1),
    );
}

test "validation rejects recursive lookup graphs at bounded depth" {
    try std.testing.expectEqual(@as(usize, 16), validation.lookup.max_context_depth);
}

test "validation checks nested mark filtering set indexes" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 8, 12);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 4);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 0x0010);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 10);
    writeU16(&bytes, 24, 2);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectError(
        error.BadGpos,
        validation.lookup.recordMarkFilteringSets(
            view,
            28,
            1,
            .{ .mark_filtering_sets = &.{&.{5}} },
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
