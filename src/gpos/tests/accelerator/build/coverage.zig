//! Accelerator first-Coverage navigation contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "coverage builder resolves direct and contextual first inputs" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 0);
    writeCoverage1(&bytes, 12, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectEqual(
        @as(?usize, 12),
        try build.coverage.subtableOffset(view, 0, 1),
    );

    @memset(&bytes, 0);
    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 0);
    writeU16(&bytes, 6, 12);
    writeCoverage1(&bytes, 12, 7);
    try std.testing.expectEqual(
        @as(?usize, 12),
        try build.coverage.subtableOffset(view, 0, 7),
    );
}

test "coverage builder resolves ExtensionPos payload type" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 2);
    writeU32(&bytes, 4, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 12);
    writeCoverage1(&bytes, 20, 9);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectEqual(
        @as(?usize, 20),
        try build.coverage.subtableOffset(view, 0, 9),
    );
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
