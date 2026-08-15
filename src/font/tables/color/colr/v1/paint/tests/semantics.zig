//! Semantic edge cases for COLR v1 Paint records and graphs.

const std = @import("std");

const paint = @import("../root.zig");
const types = @import("../../types.zig");

test "ColorLine rejects reserved extend modes and empty stop arrays" {
    var bytes: [25]u8 = .{0} ** 25;
    bytes[0] = 4;
    writeU24(&bytes, 1, 16);
    bytes[16] = 3;
    writeU16(&bytes, 17, 1);
    writeI16(&bytes, 19, 0);
    writeU16(&bytes, 21, 0);
    writeI16(&bytes, 23, 0x4000);
    const table = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadSfnt,
        paint.validateRecord(&bytes, table, 0),
    );

    bytes[16] = 0;
    _ = try paint.validateRecord(&bytes, table, 0);

    writeU16(&bytes, 17, 0);
    try std.testing.expectError(
        error.BadSfnt,
        paint.validateRecord(&bytes, table, 0),
    );

    writeU16(&bytes, 17, 1);
    writeI16(&bytes, 23, 0x4001);
    try std.testing.expectError(
        error.BadSfnt,
        paint.validateRecord(&bytes, table, 0),
    );
}

test "PaintComposite rejects reserved modes and accepts mode 27" {
    var bytes: [18]u8 = .{0} ** 18;
    bytes[0] = 32;
    writeU24(&bytes, 1, 8);
    bytes[4] = 28;
    writeU24(&bytes, 5, 13);
    bytes[8] = 2;
    writeI16(&bytes, 11, 0x4000);
    bytes[13] = 2;
    writeI16(&bytes, 16, 0x4000);
    const table = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadSfnt,
        paint.validateRecord(&bytes, table, 0),
    );

    bytes[4] = 27;
    _ = try paint.validateRecord(&bytes, table, 0);
}

test "PaintTransform requires a complete Affine2x3 payload" {
    var bytes: [30]u8 = .{0} ** 30;
    bytes[0] = 12;
    writeU24(&bytes, 1, 7);
    writeU24(&bytes, 4, 7);
    const table = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadSfnt,
        paint.validateRecord(&bytes, table, 0),
    );
}

test "PaintColrLayers rejects a LayerList self-cycle" {
    var bytes: [66]u8 = .{0} ** 66;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 18, 44);
    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 26);
    writeU32(&bytes, 44, 1);
    writeU32(&bytes, 48, 16);
    bytes[60] = 1;
    bytes[61] = 1;
    writeU32(&bytes, 62, 0);

    try std.testing.expectError(
        error.BadSfnt,
        paint.validateGraph(
            &bytes,
            .{ .offset = 0, .length = bytes.len },
            60,
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
