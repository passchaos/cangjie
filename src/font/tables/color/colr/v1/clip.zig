//! COLR v1 ClipList validation, ownership, and glyph lookup.

const std = @import("std");

const bin = @import("../../../../../binary.zig");
const glyph = @import("../../../../../glyph.zig");
const directories = @import("directories.zig");
const types = @import("types.zig");

const max_owned_clip_boxes = 2048;

const ClipBoxOwnership = struct {
    ranges: [max_owned_clip_boxes]types.Range = undefined,
    count: usize = 0,

    fn claim(self: *ClipBoxOwnership, range: types.Range) types.Error!void {
        if (range.start >= range.end) return error.BadSfnt;
        for (self.ranges[0..self.count]) |owned| {
            if (range.start == owned.start and range.end == owned.end) return;
            if (directories.overlaps(range, owned)) return error.BadSfnt;
        }
        if (self.count == self.ranges.len) return error.BadSfnt;
        self.ranges[self.count] = range;
        self.count += 1;
    }
};

pub fn validate(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
) types.Error!?types.ClipList {
    const list = (try directory(data, table)) orelse return null;
    var previous_end_glyph: ?glyph.GlyphId = null;
    var ownership = ClipBoxOwnership{};
    for (0..list.count) |index| {
        const record = list.records_start + index * 7;
        const start_glyph = try bin.readU16At(data, record);
        const end_glyph = try bin.readU16At(data, record + 2);
        if (start_glyph > end_glyph or end_glyph >= glyph_count) {
            return error.BadSfnt;
        }
        if (previous_end_glyph) |previous| {
            if (start_glyph <= previous) return error.BadSfnt;
        }
        previous_end_glyph = end_glyph;
        try ownership.claim((try boxAtIndex(data, table, list, index)).range);
    }
    return list;
}

pub fn directory(
    data: []const u8,
    table: types.Table,
) types.Error!?types.ClipList {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 34 or
        try bin.readU16At(data, table.offset) != 1)
    {
        return error.BadSfnt;
    }
    const offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 22));
    if (offset == 0) return null;
    return try directories.readClipListAt(data, table, offset);
}

pub fn boxForGlyph(
    data: []const u8,
    table: types.Table,
    list: types.ClipList,
    glyph_id: glyph.GlyphId,
) types.Error!?types.ClipBox {
    var low: usize = 0;
    var high: usize = list.count;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const record = list.records_start + mid * 7;
        const start_glyph = try bin.readU16At(data, record);
        const end_glyph = try bin.readU16At(data, record + 2);
        if (glyph_id < start_glyph) {
            high = mid;
        } else if (glyph_id > end_glyph) {
            low = mid + 1;
        } else {
            return try readBoxAtRecord(data, table, list, record);
        }
    }
    return null;
}

pub fn boxAtIndex(
    data: []const u8,
    table: types.Table,
    list: types.ClipList,
    index: usize,
) types.Error!types.ClipBox {
    if (index >= list.count) return error.BadSfnt;
    return try readBoxAtRecord(
        data,
        table,
        list,
        list.records_start + index * 7,
    );
}

fn readBoxAtRecord(
    data: []const u8,
    table: types.Table,
    list: types.ClipList,
    record: usize,
) types.Error!types.ClipBox {
    const relative: usize = @intCast(try readU24(data, record + 4));
    if (relative < list.data_start or relative > table.length - list.offset) {
        return error.BadSfnt;
    }
    return try readBox(data, table, list.start + relative);
}

fn readBox(
    data: []const u8,
    table: types.Table,
    absolute_offset: usize,
) types.Error!types.ClipBox {
    const table_end = table.offset + table.length;
    if (absolute_offset < table.offset or absolute_offset >= table_end) {
        return error.BadSfnt;
    }
    const format = data[absolute_offset];
    const size: usize = switch (format) {
        1 => 9,
        2 => 13,
        else => return error.BadSfnt,
    };
    if (size > table_end - absolute_offset) return error.BadSfnt;

    const x_min = try bin.readI16At(data, absolute_offset + 1);
    const y_min = try bin.readI16At(data, absolute_offset + 3);
    const x_max = try bin.readI16At(data, absolute_offset + 5);
    const y_max = try bin.readI16At(data, absolute_offset + 7);
    if (x_min > x_max or y_min > y_max) return error.BadSfnt;
    return .{
        .format = format,
        .x_min = x_min,
        .y_min = y_min,
        .x_max = x_max,
        .y_max = y_max,
        .var_index_base = if (format == 2)
            try bin.readU32At(data, absolute_offset + 9)
        else
            null,
        .range = .{
            .start = absolute_offset - table.offset,
            .end = absolute_offset - table.offset + size,
        },
    };
}

fn readU24(data: []const u8, offset: usize) types.Error!u32 {
    if (offset > data.len or 3 > data.len - offset) return error.EndOfStream;
    return (@as(u32, data[offset]) << 16) |
        (@as(u32, data[offset + 1]) << 8) |
        data[offset + 2];
}

test "clip lists accept shared boxes and reject partial overlap" {
    var bytes: [92]u8 = .{0} ** 92;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 22, 34);
    const list = 34;
    bytes[list] = 1;
    writeU32(&bytes, list + 1, 2);
    writeU16(&bytes, list + 5, 0);
    writeU16(&bytes, list + 7, 0);
    writeU24(&bytes, list + 9, 19);
    writeU16(&bytes, list + 12, 1);
    writeU16(&bytes, list + 14, 1);
    writeU24(&bytes, list + 16, 28);
    const first = list + 19;
    bytes[first] = 1;
    writeI16(&bytes, first + 1, 0);
    writeI16(&bytes, first + 3, 0);
    writeI16(&bytes, first + 5, 10);
    writeI16(&bytes, first + 7, 10);
    const second = list + 28;
    bytes[second] = 1;
    writeI16(&bytes, second + 1, 20);
    writeI16(&bytes, second + 3, 20);
    writeI16(&bytes, second + 5, 30);
    writeI16(&bytes, second + 7, 30);
    const table = types.Table{ .offset = 0, .length = second + 9 };
    _ = try validate(&bytes, table, 2);

    var shared = bytes;
    writeU24(&shared, list + 16, 19);
    _ = try validate(&shared, table, 2);

    var overlap = bytes;
    writeU24(&overlap, list + 16, 23);
    overlap[list + 23] = 1;
    writeI16(&overlap, list + 24, 0);
    writeI16(&overlap, list + 26, 1);
    writeI16(&overlap, list + 28, 10);
    writeI16(&overlap, list + 30, 10);
    try std.testing.expectError(error.BadSfnt, validate(&overlap, table, 2));
}

test "validated clip list locates static and variable boxes" {
    var bytes: [68]u8 = .{0} ** 68;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 22, 34);
    bytes[34] = 1;
    writeU32(&bytes, 35, 1);
    writeU16(&bytes, 39, 1);
    writeU16(&bytes, 41, 2);
    writeU24(&bytes, 43, 12);
    bytes[46] = 2;
    writeI16(&bytes, 47, -1);
    writeI16(&bytes, 49, -2);
    writeI16(&bytes, 51, 10);
    writeI16(&bytes, 53, 20);
    writeU32(&bytes, 55, 7);
    const table = types.Table{ .offset = 0, .length = 59 };
    const list = (try validate(&bytes, table, 3)).?;
    const box = (try boxForGlyph(&bytes, table, list, 2)).?;
    try std.testing.expectEqual(@as(u8, 2), box.format);
    try std.testing.expectEqual(@as(i16, -1), box.x_min);
    try std.testing.expectEqual(@as(?u32, 7), box.var_index_base);
    try std.testing.expect((try boxForGlyph(&bytes, table, list, 0)) == null);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
