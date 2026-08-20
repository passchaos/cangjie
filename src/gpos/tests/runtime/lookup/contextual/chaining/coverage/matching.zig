//! Coverage sequence matching contracts.

const std = @import("std");
const matching =
    @import("../../../../../../runtime/lookup/contextual/chaining/coverage/matching.zig");
const table = @import("../../../../../../table/root.zig");

test "coverage matching checks every unproven input slot" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 4);
    writeU16(&bytes, 2, 10);
    writeCoverage(&bytes, 4, 3);
    writeCoverage(&bytes, 10, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expect(try matching.indices(
        view,
        0,
        &.{ 9, 5 },
        &.{ 0, 1 },
        0,
        &.{},
        1,
    ));
    try std.testing.expect(!try matching.indices(
        view,
        0,
        &.{ 3, 7 },
        &.{ 0, 1 },
        0,
        &.{},
        0,
    ));
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
