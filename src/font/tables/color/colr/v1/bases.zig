//! COLR v1 BaseGlyphList directory, ordering, and Paint offset ownership.

const std = @import("std");

const bin = @import("../../../../../binary.zig");
const glyph = @import("../../../../../glyph.zig");
const paint = @import("paint/core.zig");
const paint_types = @import("paint/types.zig");
const types = @import("types.zig");

pub const List = struct {
    start: usize,
    record_count: usize,
    records_start: usize,
    paint_data_start: usize,
};

pub const Record = struct {
    glyph_id: glyph.GlyphId,
    paint_offset: usize,
};

pub fn directoryRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.Range {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (offset < 34 or
        offset > table.length or
        4 > table.length - offset)
    {
        return error.BadSfnt;
    }
    const start = table.offset + offset;
    const record_count: usize = @intCast(try bin.readU32At(data, start));
    const records_start = start + 4;
    if (record_count > (table.offset + table.length - records_start) / 6) {
        return error.BadSfnt;
    }
    return .{ .start = offset, .end = offset + 4 + record_count * 6 };
}

pub fn read(
    data: []const u8,
    table: types.Table,
) types.Error!?List {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 18) return error.BadSfnt;
    const relative: usize =
        @intCast(try bin.readU32At(data, table.offset + 14));
    if (relative == 0) return null;
    const directory_range = try directoryRange(data, table, relative);

    const start = table.offset + relative;
    const record_count: usize = @intCast(try bin.readU32At(data, start));
    const records_start = start + 4;
    const list = List{
        .start = start,
        .record_count = record_count,
        .records_start = records_start,
        .paint_data_start = directory_range.end - relative,
    };

    var previous_glyph: ?glyph.GlyphId = null;
    for (0..record_count) |index| {
        const current = try recordAt(data, table, list, index);
        // BaseGlyphPaintRecords are a binary-search directory. Strict ordering
        // makes duplicate and decreasing keys unambiguous for every consumer.
        if (previous_glyph) |previous| {
            if (current.glyph_id <= previous) return error.BadSfnt;
        }
        previous_glyph = current.glyph_id;
    }
    try validateHeaders(data, table, list);
    return list;
}

pub fn range(table: types.Table, list: List) types.Range {
    const start = list.start - table.offset;
    return .{ .start = start, .end = start + list.paint_data_start };
}

pub fn recordAt(
    data: []const u8,
    table: types.Table,
    list: List,
    index: usize,
) types.Error!Record {
    if (index >= list.record_count) return error.BadSfnt;
    const record = list.records_start + index * 6;
    return .{
        .glyph_id = try bin.readU16At(data, record),
        .paint_offset = try paintOffsetAt(data, table, list, index),
    };
}

pub fn paintOffsetAt(
    data: []const u8,
    table: types.Table,
    list: List,
    index: usize,
) types.Error!usize {
    if (index >= list.record_count) return error.BadSfnt;
    const record = list.records_start + index * 6;
    const relative: usize = @intCast(try bin.readU32At(data, record + 2));
    // Offsets are relative to BaseGlyphList, and the record array owns its
    // complete byte range. A Paint may be physically shared or reordered, but
    // it may not reinterpret list metadata as a Paint header.
    if (relative < list.paint_data_start) return error.BadSfnt;
    const list_offset = list.start - table.offset;
    if (relative > table.length - list_offset) return error.BadSfnt;
    return list.start + relative;
}

pub fn paintOffsetForGlyph(
    data: []const u8,
    table: types.Table,
    list: List,
    glyph_id: glyph.GlyphId,
) types.Error!?usize {
    // `read` proves strict key ordering, so consumers can use the on-disk
    // directory directly without allocating a secondary glyph index.
    var low: usize = 0;
    var high = list.record_count;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const record = list.records_start + mid * 6;
        const current = try bin.readU16At(data, record);
        if (glyph_id < current) {
            high = mid;
        } else if (glyph_id > current) {
            low = mid + 1;
        } else {
            return try paintOffsetAt(data, table, list, mid);
        }
    }
    return null;
}

fn validateHeaders(
    data: []const u8,
    table: types.Table,
    list: List,
) types.Error!void {
    for (0..list.record_count) |index| {
        const current = try headerAt(data, table, list, index);
        for (0..index) |previous_index| {
            const previous = try headerAt(data, table, list, previous_index);
            // Multiple glyphs may share a root Paint, and glyph-key order does
            // not constrain physical Paint order. Distinct root headers still
            // cannot partially alias because each is independently typed.
            if (current.start == previous.start and current.end == previous.end) {
                continue;
            }
            if (current.start < previous.end and previous.start < current.end) {
                return error.BadSfnt;
            }
        }
    }
}

fn headerAt(
    data: []const u8,
    table: types.Table,
    list: List,
    index: usize,
) types.Error!paint_types.Range {
    const absolute = try paintOffsetAt(data, table, list, index);
    return try paint.headerRange(
        data,
        .{ .offset = table.offset, .length = table.length },
        absolute,
    );
}

test "BaseGlyphList validates ordering and supports binary lookup" {
    var bytes: [68]u8 = .{0} ** 68;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 3);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 27);
    writeU16(&bytes, 44, 4);
    writeU32(&bytes, 46, 22);
    writeU16(&bytes, 50, 9);
    writeU32(&bytes, 52, 27);
    bytes[56] = 2;
    writeI16(&bytes, 59, 0x4000);
    bytes[61] = 2;
    writeI16(&bytes, 64, 0x4000);

    const table = types.Table{ .offset = 0, .length = bytes.len };
    const list = (try read(&bytes, table)).?;
    try std.testing.expectEqual(@as(usize, 3), list.record_count);
    try std.testing.expectEqual(
        @as(?usize, 61),
        try paintOffsetForGlyph(&bytes, table, list, 1),
    );
    try std.testing.expectEqual(
        @as(?usize, 56),
        try paintOffsetForGlyph(&bytes, table, list, 4),
    );
    try std.testing.expectEqual(
        @as(?usize, 61),
        try paintOffsetForGlyph(&bytes, table, list, 9),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try paintOffsetForGlyph(&bytes, table, list, 5),
    );

    writeU16(&bytes, 50, 4);
    try std.testing.expectError(error.BadSfnt, read(&bytes, table));
}

test "BaseGlyphList rejects metadata and out-of-table Paint offsets" {
    var bytes: [52]u8 = .{0} ** 52;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 2);
    writeU32(&bytes, 40, 9);
    const table = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, read(&bytes, table));

    writeU32(&bytes, 40, 19);
    try std.testing.expectError(error.BadSfnt, read(&bytes, table));
}

test "BaseGlyphList rejects partial root Paint overlap" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 2);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 16);
    writeU16(&bytes, 44, 2);
    writeU32(&bytes, 46, 17);
    bytes[50] = 2;
    bytes[51] = 2;
    writeI16(&bytes, 53, 0x4000);
    const table = types.Table{ .offset = 0, .length = bytes.len };
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
