//! Binary fixture writers shared by focused cmap validation tests.

const std = @import("std");
const fixture = @import("../../fixtures/sfnt.zig");

pub fn writeFormat8Header(
    bytes: []u8,
    length: u32,
    groups: u32,
) void {
    fixture.writeU16(bytes, 0, 0);
    fixture.writeU16(bytes, 2, 1);
    fixture.writeU16(bytes, 4, 0);
    fixture.writeU16(bytes, 6, 4);
    fixture.writeU32(bytes, 8, 12);
    fixture.writeU16(bytes, 12, 8);
    fixture.writeU32(bytes, 16, length);
    fixture.writeU32(bytes, 8216, groups);
}

pub fn setFormat8Is32(bytes: []u8, word: u16, value: bool) void {
    const byte_offset = 24 + @as(usize, word) / 8;
    const mask: u8 = @as(u8, 0x80) >> @intCast(word & 7);
    if (value) {
        bytes[byte_offset] |= mask;
    } else {
        bytes[byte_offset] &= ~mask;
    }
}

pub fn writeFormat12Header(
    bytes: []u8,
    length: u32,
    groups: u32,
) void {
    fixture.writeU16(bytes, 0, 0);
    fixture.writeU16(bytes, 2, 1);
    fixture.writeU16(bytes, 4, 3);
    fixture.writeU16(bytes, 6, 10);
    fixture.writeU32(bytes, 8, 12);
    fixture.writeU16(bytes, 12, 12);
    fixture.writeU32(bytes, 16, length);
    fixture.writeU32(bytes, 24, groups);
}

pub fn writeFormat14Header(
    bytes: []u8,
    length: u32,
    records: u32,
) void {
    fixture.writeU16(bytes, 0, 0);
    fixture.writeU16(bytes, 2, 1);
    fixture.writeU16(bytes, 4, 0);
    fixture.writeU16(bytes, 6, 5);
    fixture.writeU32(bytes, 8, 12);
    fixture.writeU16(bytes, 12, 14);
    fixture.writeU32(bytes, 14, length);
    fixture.writeU32(bytes, 18, records);
}

pub fn writeFormat4Header(bytes: []u8, length: u16) void {
    fixture.writeU16(bytes, 0, 0);
    fixture.writeU16(bytes, 2, 1);
    fixture.writeU16(bytes, 4, 3);
    fixture.writeU16(bytes, 6, 1);
    fixture.writeU32(bytes, 8, 12);
    fixture.writeU16(bytes, 12, 4);
    fixture.writeU16(bytes, 14, length);
    fixture.writeU16(bytes, 18, 4);
    fixture.writeU16(bytes, 20, 4);
    fixture.writeU16(bytes, 22, 1);
}

pub fn writeFormat4Segment(
    bytes: []u8,
    segment_index: usize,
    start: u16,
    end: u16,
    delta: i16,
    range_offset: u16,
) void {
    const subtable = 12;
    fixture.writeU16(bytes, subtable + 14 + segment_index * 2, end);
    fixture.writeU16(bytes, subtable + 20 + segment_index * 2, start);
    fixture.writeI16(bytes, subtable + 24 + segment_index * 2, delta);
    fixture.writeU16(
        bytes,
        subtable + 28 + segment_index * 2,
        range_offset,
    );
}

pub fn writeGroup(
    bytes: []u8,
    offset: usize,
    start: u32,
    end: u32,
    glyph_id: u32,
) void {
    fixture.writeU32(bytes, offset, start);
    fixture.writeU32(bytes, offset + 4, end);
    fixture.writeU32(bytes, offset + 8, glyph_id);
}

pub fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    std.debug.assert(value <= 0x00ff_ffff);
    bytes[offset] = @intCast(value >> 16);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}
