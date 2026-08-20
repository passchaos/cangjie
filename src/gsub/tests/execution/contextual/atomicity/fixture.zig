//! Shared complete-table writers for contextual atomicity integration tests.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

pub fn writeLookupList(
    bytes: []u8,
    offsets: []const u16,
) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, @intCast(offsets.len));
    for (offsets, 0..) |offset, index| {
        writeU16(bytes, 12 + index * 2, offset);
    }
}

pub fn writeSingleDeltaLookup(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 0);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 6);
    writeI16(bytes, offset + 12, delta);
    writeCoverage1(bytes, offset + 14, glyph);
}

pub fn writeCoverage1(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
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
