//! Binary fixture writers for borrowed COLR/CPAL lifecycle tests.

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

pub fn writeUtf16NameRecord(
    bytes: []u8,
    offset: usize,
    name_id: u16,
    length: u16,
    storage_offset: u16,
) void {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, 0x0409);
    writeU16(bytes, offset + 6, name_id);
    writeU16(bytes, offset + 8, length);
    writeU16(bytes, offset + 10, storage_offset);
}

pub fn writeSingleEntryCpal(bytes: []u8, offset: usize) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 1);
    writeU32(bytes, offset + 8, 14);
    writeU16(bytes, offset + 12, 0);
    bytes[offset + 14] = 10;
    bytes[offset + 15] = 20;
    bytes[offset + 16] = 30;
    bytes[offset + 17] = 255;
}
