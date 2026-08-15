//! COLR v1 top-level typed-directory ownership.

const std = @import("std");

const bin = @import("../../../../../binary.zig");
const types = @import("types.zig");

pub fn validateTopLevel(
    data: []const u8,
    table: types.Table,
) types.Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 2) return error.BadSfnt;
    if (try bin.readU16At(data, table.offset) != 1) return;
    if (table.length < 34) return error.BadSfnt;

    var ranges: [3]types.Range = undefined;
    var count: usize = 0;
    const base_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 14));
    if (base_offset != 0) {
        ranges[count] = try baseGlyphListRange(data, table, base_offset);
        count += 1;
    }
    const layer_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 18));
    if (layer_offset != 0) {
        ranges[count] = try layerListRange(data, table, layer_offset);
        count += 1;
    }
    const clip_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 22));
    if (clip_offset != 0) {
        ranges[count] = try clipListRange(data, table, clip_offset);
        count += 1;
    }

    for (ranges[0..count], 0..) |lhs, lhs_index| {
        for (ranges[lhs_index + 1 .. count]) |rhs| {
            // These offsets name distinct typed directories. Even zero-count
            // aliases make child-offset ownership ambiguous.
            if (overlaps(lhs, rhs)) return error.BadSfnt;
        }
    }
}

pub fn baseGlyphListRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.Range {
    try validateOptionalOffset(offset, table, 4);
    const start = table.offset + offset;
    const count: usize = @intCast(try bin.readU32At(data, start));
    const records_start = start + 4;
    if (count > (table.offset + table.length - records_start) / 6) {
        return error.BadSfnt;
    }
    return .{ .start = offset, .end = offset + 4 + count * 6 };
}

pub fn layerListRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.Range {
    try validateOptionalOffset(offset, table, 4);
    const start = table.offset + offset;
    const count: usize = @intCast(try bin.readU32At(data, start));
    const offsets_start = start + 4;
    if (count > (table.offset + table.length - offsets_start) / 4) {
        return error.BadSfnt;
    }
    return .{ .start = offset, .end = offset + 4 + count * 4 };
}

pub fn clipListRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.Range {
    const list = try readClipListAt(data, table, offset);
    return .{
        .start = offset,
        .end = offset + list.data_start,
    };
}

pub fn readClipListAt(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.ClipList {
    try validateOptionalOffset(offset, table, 5);
    const start = table.offset + offset;
    if (data[start] != 1) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU32At(data, start + 1));
    const records_start = start + 5;
    if (count > (table.offset + table.length - records_start) / 7) {
        return error.BadSfnt;
    }
    return .{
        .offset = offset,
        .start = start,
        .count = count,
        .records_start = records_start,
        .data_start = 5 + count * 7,
    };
}

pub fn overlaps(lhs: types.Range, rhs: types.Range) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

fn validateOptionalOffset(
    offset: usize,
    table: types.Table,
    minimum_size: usize,
) types.Error!void {
    if (offset < 34 or
        offset > table.length or
        minimum_size > table.length - offset)
    {
        return error.BadSfnt;
    }
}

test "top-level directories cannot alias the header or each other" {
    var bytes: [50]u8 = .{0} ** 50;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 18, 38);
    writeU32(&bytes, 34, 0);
    writeU32(&bytes, 38, 0);
    const table = types.Table{ .offset = 0, .length = bytes.len };
    try validateTopLevel(&bytes, table);

    var header_alias = bytes;
    writeU32(&header_alias, 14, 30);
    try std.testing.expectError(
        error.BadSfnt,
        validateTopLevel(&header_alias, table),
    );

    var list_alias = bytes;
    writeU32(&list_alias, 18, 34);
    try std.testing.expectError(
        error.BadSfnt,
        validateTopLevel(&list_alias, table),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
