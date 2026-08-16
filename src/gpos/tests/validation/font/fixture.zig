//! Compact builders shared by complete-table validation tests.

const std = @import("std");
pub const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn writeSinglePositionLookup(
    bytes: []u8,
    lookup_offset: usize,
    glyph: GlyphId,
    lookup_flag: u16,
    x_placement: i16,
) void {
    writeU16(bytes, lookup_offset, 1);
    writeU16(bytes, lookup_offset + 2, lookup_flag);
    writeU16(bytes, lookup_offset + 4, 1);
    writeU16(bytes, lookup_offset + 6, 8);

    const subtable = lookup_offset + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 8);
    writeU16(bytes, subtable + 4, 0x0001);
    writeI16(bytes, subtable + 6, x_placement);
    writeCoverage1(bytes, subtable + 8, glyph);
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

pub fn writeFeatureRecord(
    bytes: []u8,
    offset: usize,
    tag_value: u32,
    feature_offset: u16,
) void {
    writeU32(bytes, offset, tag_value);
    writeU16(bytes, offset + 4, feature_offset);
}

pub fn writeFeature(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, lookup_index);
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
