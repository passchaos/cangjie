//! Compact table fixtures shared by GPOS plan contract tests.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const unicode = @import("../../../../unicode.zig");

pub fn writeFeatureTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 54);
    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 34, 1);
    writeU32(bytes, 36, unicode.tag("kern"));
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 3);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 0);
    writeU16(bytes, 50, 1);
    writeU16(bytes, 54, 2);
    writeU16(bytes, 56, 6);
    writeU16(bytes, 58, 30);
    writeSinglePositionLookup(bytes, 60, 5, 11);
    writeSinglePositionLookup(bytes, 84, 5, 17);
}

pub fn writeTopologyFreeTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 58);
    writeU16(bytes, 6, 60);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 2);
    writeU16(bytes, 12, 6);
    writeU16(bytes, 14, 30);
    writeSinglePositionLookup(bytes, 16, 5, 11);
    writeSinglePositionLookup(bytes, 40, 5, 17);
    writeU16(bytes, 58, 0);
    writeU16(bytes, 60, 0);
}

pub fn writePairTable(bytes: []u8, extension: bool, advance: i16) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, @intCast(bytes.len - 4));
    writeU16(bytes, 6, @intCast(bytes.len - 2));
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);
    writeU16(bytes, 14, if (extension) 9 else 2);
    writeU16(bytes, 16, 0);
    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 8);

    const pair: usize = if (extension) pair: {
        writeU16(bytes, 22, 1);
        writeU16(bytes, 24, 2);
        writeU32(bytes, 26, 8);
        break :pair 30;
    } else 22;
    writeU16(bytes, pair, 1);
    writeU16(bytes, pair + 2, 20);
    writeU16(bytes, pair + 4, 0x0004);
    writeU16(bytes, pair + 6, 0);
    writeU16(bytes, pair + 8, 1);
    writeU16(bytes, pair + 10, 12);
    writeU16(bytes, pair + 12, 1);
    writeU16(bytes, pair + 14, 7);
    writeI16(bytes, pair + 16, advance);
    writeCoverage1(bytes, pair + 20, 5);
    writeU16(bytes, bytes.len - 4, 0);
    writeU16(bytes, bytes.len - 2, 0);
}

pub fn writeMarkBaseTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 70);
    writeU16(bytes, 6, 72);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);
    writeU16(bytes, 14, 4);
    writeU16(bytes, 16, 0);
    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 8);

    const mark_base = 22;
    writeU16(bytes, mark_base, 1);
    writeU16(bytes, mark_base + 2, 12);
    writeU16(bytes, mark_base + 4, 18);
    writeU16(bytes, mark_base + 6, 1);
    writeU16(bytes, mark_base + 8, 24);
    writeU16(bytes, mark_base + 10, 36);
    writeCoverage1(bytes, mark_base + 12, 22);
    writeCoverage1(bytes, mark_base + 18, 20);
    writeU16(bytes, mark_base + 24, 1);
    writeU16(bytes, mark_base + 26, 0);
    writeU16(bytes, mark_base + 28, 6);
    writeAnchor1(bytes, mark_base + 30, 10, 15);
    writeU16(bytes, mark_base + 36, 1);
    writeU16(bytes, mark_base + 38, 4);
    writeAnchor1(bytes, mark_base + 40, 100, 120);
    writeU16(bytes, 70, 0);
    writeU16(bytes, 72, 0);
}

fn writeSinglePositionLookup(
    bytes: []u8,
    lookup_offset: usize,
    glyph: GlyphId,
    placement: i16,
) void {
    writeU16(bytes, lookup_offset, 1);
    writeU16(bytes, lookup_offset + 2, 0);
    writeU16(bytes, lookup_offset + 4, 1);
    writeU16(bytes, lookup_offset + 6, 8);
    const subtable = lookup_offset + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 8);
    writeU16(bytes, subtable + 4, 0x0001);
    writeI16(bytes, subtable + 6, placement);
    writeU16(bytes, subtable + 8, 1);
    writeU16(bytes, subtable + 10, 1);
    writeU16(bytes, subtable + 12, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
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

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
