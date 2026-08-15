//! Binary fixtures shared by COLR v1 variation semantic tests.

const std = @import("std");

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

pub fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    std.debug.assert(value <= 0x00ff_ffff);
    bytes[offset] = @intCast(value >> 16);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

pub fn writeF2Dot14(bytes: []u8, offset: usize, value: f32) void {
    writeI16(bytes, offset, @intFromFloat(@round(value * 16384.0)));
}

pub fn writeF16Dot16(bytes: []u8, offset: usize, value: f32) void {
    std.mem.writeInt(
        i32,
        bytes[offset..][0..4],
        @intFromFloat(@round(value * 65536.0)),
        .big,
    );
}

pub fn writeItemVariationStoreWithOneItem(
    bytes: []u8,
    offset: usize,
) void {
    writeItemVariationStoreWithItems(bytes, offset, 1);
}

pub fn writeItemVariationStoreWithItems(
    bytes: []u8,
    offset: usize,
    item_count: u16,
) void {
    writeU16(bytes, offset, 1);
    writeU32(bytes, offset + 2, 12);
    writeU16(bytes, offset + 6, 1);
    writeU32(bytes, offset + 8, 24);

    writeU16(bytes, offset + 12, 1);
    writeU16(bytes, offset + 14, 1);
    writeF2Dot14(bytes, offset + 16, -1.0);
    writeF2Dot14(bytes, offset + 18, 0.0);
    writeF2Dot14(bytes, offset + 20, 1.0);

    writeU16(bytes, offset + 24, item_count);
    writeU16(bytes, offset + 26, 1);
    writeU16(bytes, offset + 28, 1);
    writeU16(bytes, offset + 30, 0);
    for (0..item_count) |index| {
        writeI16(bytes, offset + 32 + index * 2, 7);
    }
}
