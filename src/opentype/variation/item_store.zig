//! ItemVariationStore structure and child-payload ownership validation.

const std = @import("std");

const bin = @import("../../binary.zig");
const delta_map = @import("delta_set_index_map.zig");

pub const Error = error{BadSfnt} || error{EndOfStream};
pub const Table = delta_map.Table;

pub const Info = struct {
    item_data_count: usize,
    end_offset: usize,
};

pub const Range = struct {
    start: usize,
    end: usize,
};

const RegionList = struct {
    region_count: usize,
    range: Range,
};

const ItemData = struct {
    item_count: usize,
    range: Range,
};

pub fn validate(
    data: []const u8,
    table: Table,
    store_offset: usize,
    axis_count: usize,
    minimum_store_offset: usize,
) Error!Info {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (store_offset < minimum_store_offset or
        store_offset > table.length or
        table.length - store_offset < 8)
    {
        return error.BadSfnt;
    }
    const store = table.offset + store_offset;
    if (try bin.readU16At(data, store) != 1) return error.BadSfnt;
    const region_list_offset: usize =
        @intCast(try bin.readU32At(data, store + 2));
    const item_data_count: usize =
        @intCast(try bin.readU16At(data, store + 6));
    if (item_data_count > (table.length - store_offset - 8) / 4) {
        return error.BadSfnt;
    }
    const offsets_array_end = 8 + item_data_count * 4;

    const regions = try validateRegionList(
        data,
        table,
        store_offset,
        region_list_offset,
        axis_count,
        offsets_array_end,
    );
    var end_offset = @max(offsets_array_end, regions.range.end);
    for (0..item_data_count) |index| {
        const item_data_offset: usize =
            @intCast(try bin.readU32At(data, store + 8 + index * 4));
        if (item_data_offset < offsets_array_end) return error.BadSfnt;
        const item_data = try validateItemData(
            data,
            table,
            store_offset,
            item_data_offset,
            regions.region_count,
        );
        try validateItemDataOwnership(
            data,
            table,
            store_offset,
            store,
            index,
            regions,
            item_data,
            offsets_array_end,
        );
        end_offset = @max(end_offset, item_data.range.end);
    }
    return .{
        .item_data_count = item_data_count,
        .end_offset = store_offset + end_offset,
    };
}

pub fn itemCount(
    data: []const u8,
    table: Table,
    store_offset: usize,
    outer_index: usize,
) Error!usize {
    if (table.offset > data.len or table.length > data.len - table.offset or
        store_offset > table.length or table.length - store_offset < 8)
    {
        return error.BadSfnt;
    }
    const store = table.offset + store_offset;
    const item_data_count: usize =
        @intCast(try bin.readU16At(data, store + 6));
    if (outer_index >= item_data_count or
        item_data_count > (table.length - store_offset - 8) / 4)
    {
        return error.BadSfnt;
    }
    const item_data_offset: usize =
        @intCast(try bin.readU32At(data, store + 8 + outer_index * 4));
    if (item_data_offset > table.length - store_offset or
        table.length - store_offset - item_data_offset < 2)
    {
        return error.BadSfnt;
    }
    return try bin.readU16At(
        data,
        table.offset + store_offset + item_data_offset,
    );
}

pub fn rangesOverlap(lhs: Range, rhs: Range) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

pub fn rangesEqual(lhs: Range, rhs: Range) bool {
    return lhs.start == rhs.start and lhs.end == rhs.end;
}

fn validateRegionList(
    data: []const u8,
    table: Table,
    store_offset: usize,
    region_list_offset: usize,
    expected_axis_count: usize,
    minimum_region_offset: usize,
) Error!RegionList {
    if (region_list_offset < minimum_region_offset or
        region_list_offset > table.length - store_offset or
        table.length - store_offset - region_list_offset < 4)
    {
        return error.BadSfnt;
    }
    const region_list = table.offset + store_offset + region_list_offset;
    const axis_count: usize =
        @intCast(try bin.readU16At(data, region_list));
    const region_count: usize =
        @intCast(try bin.readU16At(data, region_list + 2));
    if (axis_count != expected_axis_count) return error.BadSfnt;
    const available = table.length - store_offset - region_list_offset - 4;
    if (axis_count != 0 and region_count > available / axis_count / 6) {
        return error.BadSfnt;
    }
    const region_bytes = region_count * axis_count * 6;

    for (0..region_count) |region_index| {
        for (0..axis_count) |axis_index| {
            const axis =
                region_list + 4 + (region_index * axis_count + axis_index) * 6;
            const start = try readNormalizedCoordinate(data, axis);
            const peak = try readNormalizedCoordinate(data, axis + 2);
            const end = try readNormalizedCoordinate(data, axis + 4);
            // VariationRegion coordinates form a normalized F2DOT14 tent.
            if (start > peak or peak > end) return error.BadSfnt;
        }
    }

    return .{
        .region_count = region_count,
        .range = .{
            .start = region_list_offset,
            .end = region_list_offset + 4 + region_bytes,
        },
    };
}

fn validateItemData(
    data: []const u8,
    table: Table,
    store_offset: usize,
    item_data_offset: usize,
    region_count: usize,
) Error!ItemData {
    if (item_data_offset > table.length - store_offset or
        table.length - store_offset - item_data_offset < 6)
    {
        return error.BadSfnt;
    }
    const item_data = table.offset + store_offset + item_data_offset;
    const item_count: usize =
        @intCast(try bin.readU16At(data, item_data));
    const raw_word_delta_count = try bin.readU16At(data, item_data + 2);
    const region_index_count: usize =
        @intCast(try bin.readU16At(data, item_data + 4));
    const word_delta_count: usize =
        @intCast(raw_word_delta_count & 0x7fff);
    const long_words = (raw_word_delta_count & 0x8000) != 0;
    if (word_delta_count > region_index_count or
        region_index_count > region_count)
    {
        return error.BadSfnt;
    }

    const region_indexes_offset = item_data + 6;
    const remaining_header =
        table.length - store_offset - item_data_offset - 6;
    if (region_index_count > remaining_header / 2) return error.BadSfnt;
    const region_indexes_bytes = region_index_count * 2;
    for (0..region_index_count) |index| {
        const region_index =
            try bin.readU16At(data, region_indexes_offset + index * 2);
        if (region_index >= region_count) return error.BadSfnt;
    }

    const remaining = remaining_header - region_indexes_bytes;
    const narrow_delta_count = region_index_count - word_delta_count;
    const row_size = if (long_words)
        word_delta_count * 4 + narrow_delta_count * 2
    else
        word_delta_count * 2 + narrow_delta_count;
    if (row_size != 0 and item_count > remaining / row_size) {
        return error.BadSfnt;
    }
    return .{
        .item_count = item_count,
        .range = .{
            .start = item_data_offset,
            .end = item_data_offset +
                6 +
                region_indexes_bytes +
                item_count * row_size,
        },
    };
}

fn readNormalizedCoordinate(data: []const u8, offset: usize) Error!i16 {
    const value = try bin.readI16At(data, offset);
    if (value < -0x4000 or value > 0x4000) return error.BadSfnt;
    return value;
}

fn validateItemDataOwnership(
    data: []const u8,
    table: Table,
    store_offset: usize,
    store: usize,
    current_index: usize,
    regions: RegionList,
    item_data: ItemData,
    offsets_array_end: usize,
) Error!void {
    if (rangesOverlap(
        item_data.range,
        .{ .start = 0, .end = offsets_array_end },
    ) or rangesOverlap(item_data.range, regions.range)) {
        return error.BadSfnt;
    }

    for (0..current_index) |previous_index| {
        const previous_offset: usize =
            @intCast(try bin.readU32At(data, store + 8 + previous_index * 4));
        const previous = try validateItemData(
            data,
            table,
            store_offset,
            previous_offset,
            regions.region_count,
        );
        if (rangesOverlap(item_data.range, previous.range)) {
            return error.BadSfnt;
        }
    }
}

test "ItemVariationStore validates tents and child ownership" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 2, 16);
    writeU16(&bytes, 6, 2);
    writeU32(&bytes, 8, 28);
    writeU32(&bytes, 12, 38);

    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 1);
    writeI16(&bytes, 20, -0x4000);
    writeI16(&bytes, 22, 0);
    writeI16(&bytes, 24, 0x4000);

    writeItemData(&bytes, 28, 1, 7);
    writeItemData(&bytes, 38, 0, 0);

    const table = Table{ .offset = 0, .length = 48 };
    const info = try validate(&bytes, table, 0, 1, 0);
    try std.testing.expectEqual(@as(usize, 2), info.item_data_count);
    try std.testing.expectEqual(@as(usize, 1), try itemCount(
        &bytes,
        table,
        0,
        0,
    ));

    var alias = bytes;
    writeU32(&alias, 12, 28);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&alias, table, 0, 1, 0),
    );

    var reversed = bytes;
    writeI16(&reversed, 20, 0x2000);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&reversed, table, 0, 1, 0),
    );
}

test "ItemVariationStore permits zero-width rows" {
    var bytes: [22]u8 = .{0} ** 22;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 2, 12);
    writeU16(&bytes, 6, 1);
    writeU32(&bytes, 8, 16);
    writeU16(&bytes, 12, 0);
    writeU16(&bytes, 14, 0);
    writeU16(&bytes, 16, 3);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 0);
    _ = try validate(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        0,
        0,
        0,
    );
}

fn writeItemData(
    bytes: []u8,
    offset: usize,
    item_count: u16,
    delta: i16,
) void {
    writeU16(bytes, offset, item_count);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 0);
    if (item_count != 0) writeI16(bytes, offset + 8, delta);
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
