//! COLR v1 LayerList directory and Paint offset ownership.

const std = @import("std");

const bin = @import("../../../../../binary.zig");
const paint = @import("paint/core.zig");
const paint_types = @import("paint/types.zig");
const types = @import("types.zig");

pub const Error = paint_types.Error;
pub const Table = types.Table;

pub const List = struct {
    start: usize,
    layer_count: usize,
    offsets_start: usize,
    paint_data_start: usize,
};

pub fn read(data: []const u8, table: Table) Error!?List {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 22) return error.BadSfnt;
    const relative: usize =
        @intCast(try bin.readU32At(data, table.offset + 18));
    if (relative == 0) return null;
    if (relative < 34 or
        relative > table.length or
        4 > table.length - relative)
    {
        return error.BadSfnt;
    }

    const start = table.offset + relative;
    const layer_count: usize = @intCast(try bin.readU32At(data, start));
    const offsets_start = start + 4;
    if (layer_count > (table.offset + table.length - offsets_start) / 4) {
        return error.BadSfnt;
    }
    const list = List{
        .start = start,
        .layer_count = layer_count,
        .offsets_start = offsets_start,
        .paint_data_start = 4 + layer_count * 4,
    };
    try validateHeaders(data, table, list);
    return list;
}

pub fn paintOffset(
    data: []const u8,
    table: Table,
    list: List,
    layer_index: u32,
) Error!usize {
    const index: usize = @intCast(layer_index);
    if (index >= list.layer_count) return error.BadSfnt;
    const relative: usize =
        @intCast(try bin.readU32At(data, list.offsets_start + index * 4));
    if (relative < list.paint_data_start) return error.BadSfnt;
    const list_offset = list.start - table.offset;
    if (relative > table.length - list_offset) return error.BadSfnt;
    return list.start + relative;
}

fn validateHeaders(
    data: []const u8,
    table: Table,
    list: List,
) Error!void {
    const table_end = table.offset + table.length;
    for (0..list.layer_count) |index| {
        const current = try headerAt(data, table, list, index);
        for (0..index) |previous_index| {
            const previous = try headerAt(
                data,
                table,
                list,
                previous_index,
            );
            // Physical order is independent of layer order, and exact Paint
            // sharing is valid. Distinct partially-overlapping headers are not.
            if (current.start == previous.start and current.end == previous.end) {
                continue;
            }
            if (current.start < previous.end and previous.start < current.end) {
                return error.BadSfnt;
            }
        }
        if (current.end > table_end) return error.BadSfnt;
    }
}

fn headerAt(
    data: []const u8,
    table: Table,
    list: List,
    index: usize,
) Error!paint_types.Range {
    const absolute = try paintOffset(
        data,
        table,
        list,
        @intCast(index),
    );
    return try paint.headerRange(
        data,
        .{ .offset = table.offset, .length = table.length },
        absolute,
    );
}

test "LayerList allows shared and reordered Paint headers" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 18, 34);
    writeU32(&bytes, 34, 3);
    writeU32(&bytes, 38, 21);
    writeU32(&bytes, 42, 16);
    writeU32(&bytes, 46, 21);
    bytes[50] = 2;
    writeI16(&bytes, 53, 0x4000);
    bytes[55] = 2;
    writeI16(&bytes, 58, 0x4000);

    const table = Table{ .offset = 0, .length = bytes.len };
    const list = (try read(&bytes, table)).?;
    try std.testing.expectEqual(@as(usize, 3), list.layer_count);
    try std.testing.expectEqual(
        @as(usize, 55),
        try paintOffset(&bytes, table, list, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 50),
        try paintOffset(&bytes, table, list, 1),
    );
    try std.testing.expectEqual(
        @as(usize, 55),
        try paintOffset(&bytes, table, list, 2),
    );
}

test "LayerList rejects metadata targets and partial header overlap" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 18, 34);
    writeU32(&bytes, 34, 2);
    writeU32(&bytes, 38, 12);
    writeU32(&bytes, 42, 13);
    bytes[46] = 2;
    bytes[47] = 2;
    writeI16(&bytes, 49, 0x4000);
    const table = Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, read(&bytes, table));

    writeU32(&bytes, 38, 4);
    try std.testing.expectError(error.BadSfnt, read(&bytes, table));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
