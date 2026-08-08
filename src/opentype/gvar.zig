const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Info = struct {
    major_version: u16,
    minor_version: u16,
    axis_count: u16,
    shared_tuple_count: u16,
    shared_tuple_offset: usize,
    glyph_count: u16,
    flags: u16,
    glyph_data_offset: usize,
    offset_size: u8,
    glyph_variation_data_count: usize,
};

pub const GlyphInfo = struct {
    glyph_id: u16,
    data_offset: usize,
    data_length: usize,
    tuple_count: u16,
    uses_shared_point_numbers: bool,
    tuple_data_offset: usize,
};

pub fn validate(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize) Error!void {
    _ = try info(data, offset, length, expected_glyph_count, expected_axis_count);
}

pub fn glyphInfo(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize) Error!?GlyphInfo {
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    if (glyph_id >= parsed.glyph_count) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const glyph_data_limit = table.len - parsed.glyph_data_offset;
    const start = try glyphDataOffset(table, 20 + glyph_id * @as(usize, parsed.offset_size), parsed.offset_size, glyph_data_limit);
    const end = try glyphDataOffset(table, 20 + (glyph_id + 1) * @as(usize, parsed.offset_size), parsed.offset_size, glyph_data_limit);
    if (end < start) return error.BadSfnt;
    if (end == start) return null;
    const data_start = parsed.glyph_data_offset + start;
    const data_length = end - start;
    if (data_length < 4 or data_length > table.len - data_start) return error.BadSfnt;
    const raw_tuple_count = readU16(table, data_start);
    if ((raw_tuple_count & 0x7000) != 0) return error.BadSfnt;
    const tuple_count = raw_tuple_count & 0x0fff;
    if (tuple_count == 0) return error.BadSfnt;
    const tuple_data_offset = readU16(table, data_start + 2);
    if (tuple_data_offset < 4 or tuple_data_offset > data_length) return error.BadSfnt;
    return .{
        .glyph_id = @intCast(glyph_id),
        .data_offset = data_start,
        .data_length = data_length,
        .tuple_count = tuple_count,
        .uses_shared_point_numbers = (raw_tuple_count & 0x8000) != 0,
        .tuple_data_offset = tuple_data_offset,
    };
}

pub fn info(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 20) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const major = readU16(table, 0);
    const minor = readU16(table, 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const axis_count = readU16(table, 4);
    const shared_tuple_count = readU16(table, 6);
    const shared_tuple_offset = readU32(table, 8);
    const glyph_count = readU16(table, 12);
    const flags = readU16(table, 14);
    const glyph_data_offset = readU32(table, 16);
    if (axis_count != expected_axis_count or glyph_count != expected_glyph_count) return error.BadSfnt;
    if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;

    const offset_size: u8 = if ((flags & 0x0001) != 0) 4 else 2;
    const offsets_len = (@as(usize, glyph_count) + 1) * @as(usize, offset_size);
    if (offsets_len > table.len - 20) return error.BadSfnt;
    const minimum_glyph_data_offset = 20 + offsets_len;
    if (glyph_data_offset < minimum_glyph_data_offset or glyph_data_offset > table.len) return error.BadSfnt;

    if (shared_tuple_count != 0) {
        if (shared_tuple_offset < minimum_glyph_data_offset or shared_tuple_offset > glyph_data_offset) return error.BadSfnt;
        const tuple_bytes = @as(usize, shared_tuple_count) * @as(usize, axis_count) * 2;
        if (tuple_bytes > glyph_data_offset - shared_tuple_offset) return error.BadSfnt;
    }

    const glyph_data_limit = table.len - glyph_data_offset;
    var previous = try glyphDataOffset(table, 20, offset_size, glyph_data_limit);
    var variation_data_count: usize = 0;
    for (0..glyph_count) |glyph_index| {
        const current = try glyphDataOffset(table, 20 + (@as(usize, glyph_index) + 1) * @as(usize, offset_size), offset_size, glyph_data_limit);
        if (current < previous) return error.BadSfnt;
        if (current > previous) variation_data_count += 1;
        previous = current;
    }

    return .{
        .major_version = major,
        .minor_version = minor,
        .axis_count = axis_count,
        .shared_tuple_count = shared_tuple_count,
        .shared_tuple_offset = shared_tuple_offset,
        .glyph_count = glyph_count,
        .flags = flags,
        .glyph_data_offset = glyph_data_offset,
        .offset_size = offset_size,
        .glyph_variation_data_count = variation_data_count,
    };
}

fn glyphDataOffset(table: []const u8, offset: usize, size: u8, limit: usize) Error!usize {
    if (offset > table.len or size > table.len - offset) return error.BadSfnt;
    const raw = switch (size) {
        2 => @as(usize, readU16(table, offset)) * 2,
        4 => readU32(table, offset),
        else => return error.BadSfnt,
    };
    if (raw > limit) return error.BadSfnt;
    return raw;
}

fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) usize {
    return @intCast(std.mem.readInt(u32, data[offset..][0..4], .big));
}

test "gvar metadata parses offset arrays" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 2, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 26, // glyphVariationDataArrayOffset.
        0, 0, 0, 1, 0, 1, // offsets: 0, 2, 2.
        0, 0, // two bytes of glyph variation data for glyph 0.
    };
    const parsed = try info(&bytes, 0, bytes.len, 2, 1);
    try std.testing.expectEqual(@as(u16, 1), parsed.axis_count);
    try std.testing.expectEqual(@as(u16, 2), parsed.glyph_count);
    try std.testing.expectEqual(@as(u8, 2), parsed.offset_size);
    try std.testing.expectEqual(@as(usize, 1), parsed.glyph_variation_data_count);
}

test "gvar glyph metadata exposes tuple headers" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 2, // offsets: 0, 4.
        0, 1, 0, 4, // GlyphVariationData header: one tuple, dataOffset 4.
    };
    const parsed = (try glyphInfo(&bytes, 0, bytes.len, 1, 1, 0)).?;
    try std.testing.expectEqual(@as(u16, 0), parsed.glyph_id);
    try std.testing.expectEqual(@as(usize, 24), parsed.data_offset);
    try std.testing.expectEqual(@as(usize, 4), parsed.data_length);
    try std.testing.expectEqual(@as(u16, 1), parsed.tuple_count);
    try std.testing.expectEqual(@as(usize, 4), parsed.tuple_data_offset);
    try std.testing.expect(!parsed.uses_shared_point_numbers);
}
