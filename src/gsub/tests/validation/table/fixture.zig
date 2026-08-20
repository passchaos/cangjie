//! Shared complete-table fixtures for GSUB validation integration tests.

const std = @import("std");

pub fn writeSingleLookupTable(bytes: []u8, lookup_type: u16) usize {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);
    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);
    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);
    writeU16(bytes, 18, lookup_type);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);
    return 26;
}

pub fn writeSingleDeltaLookup(
    bytes: []u8,
    lookup: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    writeSingleDeltaSubtable(bytes, lookup + 8, glyph, delta);
}

pub fn writeSingleDeltaSubtable(
    bytes: []u8,
    subtable: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 6);
    writeI16(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeCoverage1List(bytes, offset, &.{glyph});
}

pub fn writeCoverage1List(
    bytes: []u8,
    offset: usize,
    glyphs: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
