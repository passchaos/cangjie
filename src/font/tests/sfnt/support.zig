//! Binary fixture helpers shared by SFNT directory and collection tests.

const std = @import("std");
const test_font = @import("../../../test_font.zig");
const fixture = @import("../fixtures/sfnt.zig");

pub fn setTableOffset(
    bytes: []u8,
    comptime tag: *const [4]u8,
    offset: u32,
) error{BadSfnt}!void {
    return setTableOffsetAt(bytes, 0, tag, offset);
}

pub fn setTableOffsetAt(
    bytes: []u8,
    sfnt_offset: usize,
    comptime tag: *const [4]u8,
    offset: u32,
) error{BadSfnt}!void {
    const record = try tableRecordOffset(bytes, sfnt_offset, tag);
    fixture.writeU32(bytes, record + 8, offset);
}

pub fn setTableLengthAt(
    bytes: []u8,
    sfnt_offset: usize,
    comptime tag: *const [4]u8,
    length: u32,
) error{BadSfnt}!void {
    const record = try tableRecordOffset(bytes, sfnt_offset, tag);
    fixture.writeU32(bytes, record + 12, length);
}

pub fn buildMinimalTtcV2WithDsig(
    allocator: std.mem.Allocator,
) ![]u8 {
    const ttf = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ttf);

    const face_offset: usize = 28;
    const dsig_offset = face_offset + ttf.len;
    const bytes = try allocator.alloc(u8, dsig_offset + 4);
    @memset(bytes, 0);
    writeTag(bytes, 0, "ttcf");
    fixture.writeU32(bytes, 4, 0x00020000);
    fixture.writeU32(bytes, 8, 1);
    fixture.writeU32(bytes, 12, face_offset);
    writeTag(bytes, 16, "DSIG");
    fixture.writeU32(bytes, 20, 4);
    fixture.writeU32(bytes, 24, @intCast(dsig_offset));
    @memcpy(bytes[face_offset..][0..ttf.len], ttf);
    writeTag(bytes, dsig_offset, "SIG!");

    // Table offsets in a TTC face remain absolute from the collection start.
    const table_count = readU16(bytes, face_offset + 4);
    for (0..table_count) |index| {
        const offset_field = face_offset + 12 + index * 16 + 8;
        fixture.writeU32(
            bytes,
            offset_field,
            readU32(bytes, offset_field) + @as(u32, @intCast(face_offset)),
        );
    }
    return bytes;
}

pub fn writeTag(
    bytes: []u8,
    offset: usize,
    comptime tag: *const [4]u8,
) void {
    @memcpy(bytes[offset..][0..4], tag);
}

fn tableRecordOffset(
    bytes: []const u8,
    sfnt_offset: usize,
    comptime tag: *const [4]u8,
) error{BadSfnt}!usize {
    if (sfnt_offset > bytes.len or bytes.len - sfnt_offset < 12) {
        return error.BadSfnt;
    }
    const count = readU16(bytes, sfnt_offset + 4);
    if (count > (bytes.len - sfnt_offset - 12) / 16) {
        return error.BadSfnt;
    }
    for (0..count) |index| {
        const record = sfnt_offset + 12 + index * 16;
        if (std.mem.eql(u8, bytes[record..][0..4], tag)) return record;
    }
    return error.BadSfnt;
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
