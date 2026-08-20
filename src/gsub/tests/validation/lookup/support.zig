//! Shared binary fixtures for GSUB Lookup validation.

const std = @import("std");
const table = @import("../../../table/root.zig");

pub const Validator = struct {
    pub fn validateNested(table_view: table.View, lookup_offset: usize) !void {
        if (try table_view.readU16(lookup_offset) == 0) return error.BadGsub;
    }
};

pub fn writeLookup(
    bytes: []u8,
    lookup_type: u16,
    lookup_flag: u16,
    children: []const u16,
) void {
    writeU16(bytes, 0, lookup_type);
    writeU16(bytes, 2, lookup_flag);
    writeU16(bytes, 4, @intCast(children.len));
    for (children, 0..) |child, index| {
        writeU16(bytes, 6 + index * 2, child);
    }
}

pub fn writeSingle(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeU16(bytes, offset + 4, @bitCast(delta));
    writeCoverage1(bytes, offset + 6, &.{glyph});
}

pub fn writeCoverage1(
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

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

pub fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}
