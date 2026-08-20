//! Compact builders shared by nested lookup integration tests.

const std = @import("std");
pub const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn writeSinglePositionLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, lookup_flag: u16, x_placement: i16) void {
    writeU16(bytes, lookup_offset, 1);
    writeU16(bytes, lookup_offset + 2, lookup_flag);
    writeU16(bytes, lookup_offset + 4, 1);
    writeU16(bytes, lookup_offset + 6, 8);
    const single = lookup_offset + 8;
    writeU16(bytes, single, 1);
    writeU16(bytes, single + 2, 8);
    writeU16(bytes, single + 4, 0x0001);
    writeI16(bytes, single + 6, x_placement);
    writeCoverage1(bytes, single + 8, glyph);
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeCoverage1List(bytes, offset, &.{glyph});
}

pub fn writeCoverage1List(bytes: []u8, offset: usize, glyphs: []const GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| writeU16(bytes, offset + 4 + index * 2, glyph);
}

pub fn writeClassDef1(bytes: []u8, offset: usize, glyph: GlyphId, class: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, glyph);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, class);
}

pub fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16(bytes, offset, 1);
    writeI16(bytes, offset + 2, x);
    writeI16(bytes, offset + 4, y);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
