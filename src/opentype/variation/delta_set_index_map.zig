//! Zero-allocation DeltaSetIndexMap parsing and indexed lookup.

const std = @import("std");

const bin = @import("../../binary.zig");

pub const Error = error{BadSfnt} || error{EndOfStream};

pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const Map = struct {
    offset: usize,
    end_offset: usize,
    format: u8,
    entry_format: u8,
    entry_size: u8,
    inner_index_bit_count: u8,
    map_count: usize,
    map_data_start: usize,
};

pub const Index = struct {
    outer: usize,
    inner: usize,
};

pub fn read(
    data: []const u8,
    table: Table,
    map_offset: usize,
    minimum_map_offset: usize,
) Error!Map {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (map_offset < minimum_map_offset or
        map_offset > table.length or
        table.length - map_offset < 4)
    {
        return error.BadSfnt;
    }
    const map_start = table.offset + map_offset;
    const format = data[map_start];
    const entry_format = data[map_start + 1];
    if ((entry_format & 0xc0) != 0) return error.BadSfnt;

    const entry_size: usize =
        @as(usize, ((entry_format & 0x30) >> 4)) + 1;
    const inner_bit_count: usize =
        @as(usize, entry_format & 0x0f) + 1;
    if (inner_bit_count > entry_size * 8) return error.BadSfnt;

    const map_count, const map_data_start = switch (format) {
        0 => .{
            @as(usize, @intCast(try bin.readU16At(data, map_start + 2))),
            map_start + 4,
        },
        1 => blk: {
            if (table.length - map_offset < 6) return error.BadSfnt;
            break :blk .{
                @as(
                    usize,
                    @intCast(try bin.readU32At(data, map_start + 2)),
                ),
                map_start + 6,
            };
        },
        else => return error.BadSfnt,
    };
    if (map_count != 0 and
        map_count > (table.offset + table.length - map_data_start) / entry_size)
    {
        return error.BadSfnt;
    }

    return .{
        .offset = map_offset,
        .end_offset = map_data_start - table.offset + map_count * entry_size,
        .format = format,
        .entry_format = entry_format,
        .entry_size = @intCast(entry_size),
        .inner_index_bit_count = @intCast(inner_bit_count),
        .map_count = map_count,
        .map_data_start = map_data_start,
    };
}

pub fn entry(
    data: []const u8,
    map: Map,
    index: usize,
) Error!Index {
    if (index >= map.map_count) return error.BadSfnt;
    const entry_offset = map.map_data_start +
        index * @as(usize, map.entry_size);
    const entry_end = entry_offset + map.entry_size;
    if (entry_end > data.len) return error.BadSfnt;
    var value: u32 = 0;
    for (0..map.entry_size) |byte_index| {
        value = (value << 8) | data[entry_offset + byte_index];
    }

    const inner_shift: u5 = @intCast(map.inner_index_bit_count);
    const inner_mask = (@as(u32, 1) << inner_shift) - 1;
    return .{
        .outer = @intCast(value >> inner_shift),
        .inner = @intCast(value & inner_mask),
    };
}

pub fn mappedIndex(
    data: []const u8,
    map: Map,
    item_index: usize,
) Error!Index {
    if (map.map_count == 0) {
        return .{
            .outer = item_index >> 16,
            .inner = item_index & 0xffff,
        };
    }
    // OpenType variation-common deliberately reuses the final map entry when
    // an item id exceeds mapCount. Production HVAR and COLR tables rely on
    // this truncation rule.
    return try entry(data, map, @min(item_index, map.map_count - 1));
}

test "DeltaSetIndexMap reads formats and reuses the final entry" {
    var bytes: [32]u8 = .{0} ** 32;
    bytes[4] = 0;
    bytes[5] = 0x01; // one-byte entry, two inner bits.
    writeU16(&bytes, 6, 2);
    bytes[8] = 0b0000_0110; // outer 1, inner 2.
    bytes[9] = 0b0000_1011; // outer 2, inner 3.
    const table = Table{ .offset = 0, .length = bytes.len };
    const map = try read(&bytes, table, 4, 4);
    try std.testing.expectEqual(@as(usize, 2), map.map_count);
    try std.testing.expectEqual(
        Index{ .outer = 1, .inner = 2 },
        try mappedIndex(&bytes, map, 0),
    );
    try std.testing.expectEqual(
        Index{ .outer = 2, .inner = 3 },
        try mappedIndex(&bytes, map, 100),
    );

    bytes[12] = 1;
    bytes[13] = 0;
    writeU32(&bytes, 14, 1);
    bytes[18] = 7;
    const format_one = try read(&bytes, table, 12, 4);
    try std.testing.expectEqual(
        Index{ .outer = 3, .inner = 1 },
        try mappedIndex(&bytes, format_one, 0),
    );
}

test "empty DeltaSetIndexMap uses packed identity mapping" {
    var bytes: [8]u8 = .{0} ** 8;
    bytes[0] = 0;
    bytes[1] = 0;
    writeU16(&bytes, 2, 0);
    const map = try read(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        0,
        0,
    );
    try std.testing.expectEqual(
        Index{ .outer = 0x1234, .inner = 0xabcd },
        try mappedIndex(&bytes, map, 0x1234_abcd),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
