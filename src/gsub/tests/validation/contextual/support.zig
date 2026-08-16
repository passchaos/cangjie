//! Shared nested-lookup proof and binary writers for contextual validation.

const std = @import("std");
const table = @import("../../../table/root.zig");

pub const Validator = struct {
    pub fn validateNested(table_view: table.View, lookup_offset: usize) !void {
        // Tests construct one minimal lookup at the exact resolved offset.
        if (try table_view.readU16(lookup_offset) == 0) return error.BadGsub;
    }
};

pub fn installLookupList(
    bytes: []u8,
    lookup_list: usize,
    lookup: usize,
) void {
    writeU16(bytes, 8, @intCast(lookup_list));
    writeU16(bytes, lookup_list, 1);
    writeU16(bytes, lookup_list + 2, @intCast(lookup - lookup_list));
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 0);
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

pub fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: u16,
    classes: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, @intCast(classes.len));
    for (classes, 0..) |class, index| {
        writeU16(bytes, offset + 6 + index * 2, class);
    }
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

pub fn validatedView(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}
