//! Compact ligature/multiple/single lookup writers for record integration.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

pub fn writeLookupList(bytes: []u8, offsets: []const u16) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, @intCast(offsets.len));
    for (offsets, 0..) |offset, index| {
        writeU16(bytes, 12 + index * 2, offset);
    }
}

pub fn writeLigatureLookup(
    bytes: []u8,
    lookup: usize,
    flag: u16,
    first: GlyphId,
    second: GlyphId,
    output: GlyphId,
) void {
    writeU16(bytes, lookup, 4);
    writeU16(bytes, lookup + 2, flag);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const subtable = lookup + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 18);
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, 8);
    const set = subtable + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    writeU16(bytes, set + 4, output);
    writeU16(bytes, set + 6, 2);
    writeU16(bytes, set + 8, second);
    writeCoverage1(bytes, subtable + 18, first);
}

pub fn writeMultipleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: GlyphId,
    replacements: []const GlyphId,
) void {
    writeU16(bytes, lookup, 2);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const subtable = lookup + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 12);
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, 18);
    writeCoverage1(bytes, subtable + 12, glyph);
    writeU16(bytes, subtable + 18, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, subtable + 20 + index * 2, replacement);
    }
}

pub fn writeSingleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const subtable = lookup + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 6);
    writeI16(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

pub fn writeRecord(
    bytes: []u8,
    offset: usize,
    sequence_index: u16,
    lookup_index: u16,
) void {
    writeU16(bytes, offset, sequence_index);
    writeU16(bytes, offset + 2, lookup_index);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
