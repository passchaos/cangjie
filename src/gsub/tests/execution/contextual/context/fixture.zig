//! Compact ContextSubst fixtures shared by execution tests.

const std = @import("std");

pub fn writeLookup(bytes: []u8, lookup_type: u16, children: []const u16) void {
    writeU16(bytes, 0, lookup_type);
    writeU16(bytes, 2, 0);
    writeU16(bytes, 4, @intCast(children.len));
    for (children, 0..) |child, index| writeU16(bytes, 6 + index * 2, child);
}

pub fn writeExtensionWrapper(bytes: []u8, wrapper: usize, payload: usize) void {
    writeExtensionWrapperType(bytes, wrapper, payload, 5);
}

pub fn writeExtensionWrapperType(
    bytes: []u8,
    wrapper: usize,
    payload: usize,
    lookup_type: u16,
) void {
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, lookup_type);
    writeU32(bytes, wrapper + 4, @intCast(payload - wrapper));
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

pub fn writeClassDef1(bytes: []u8, offset: usize, start: u16, classes: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, @intCast(classes.len));
    for (classes, 0..) |class, index| writeU16(bytes, offset + 6 + index * 2, class);
}

pub fn writeRecord(bytes: []u8, offset: usize, sequence: u16, lookup: u16) void {
    writeU16(bytes, offset, sequence);
    writeU16(bytes, offset + 2, lookup);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
