const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Info = struct {
    version: u32,
    coverage_offset: usize,
    multi_var_store_offset: ?usize,
    condition_list_offset: ?usize,
    axis_indices_list_offset: ?usize,
    var_composite_glyphs_offset: usize,
    glyphs: []u16,
};

const Header = struct {
    version: u32,
    coverage_offset: usize,
    multi_var_store_offset: ?usize,
    condition_list_offset: ?usize,
    axis_indices_list_offset: ?usize,
    var_composite_glyphs_offset: usize,
};

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    _ = try coverageGlyphCount(data, offset, length, h.coverage_offset, glyph_count);
    if (h.multi_var_store_offset) |store| try validateMultiItemVariationStoreHeader(data, offset, length, store);
    if (h.condition_list_offset) |conditions| try validateConditionListHeader(data, offset, length, conditions);
    if (h.axis_indices_list_offset) |axis_indices| try validateIndex2Header(data, offset, length, axis_indices);
    try validateIndex2Header(data, offset, length, h.var_composite_glyphs_offset);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    try validate(data, offset, length, glyph_count);
    const glyphs = try coverageGlyphs(allocator, data, offset, length, h.coverage_offset, glyph_count);
    errdefer allocator.free(glyphs);
    return .{
        .version = h.version,
        .coverage_offset = h.coverage_offset,
        .multi_var_store_offset = h.multi_var_store_offset,
        .condition_list_offset = h.condition_list_offset,
        .axis_indices_list_offset = h.axis_indices_list_offset,
        .var_composite_glyphs_offset = h.var_composite_glyphs_offset,
        .glyphs = glyphs,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    allocator.free(value.glyphs);
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 24) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const coverage_offset: usize = @intCast(try bin.readU32At(data, offset + 4));
    const multi_var_store_offset = nullableOffset(try bin.readU32At(data, offset + 8));
    const condition_list_offset = nullableOffset(try bin.readU32At(data, offset + 12));
    const axis_indices_list_offset = nullableOffset(try bin.readU32At(data, offset + 16));
    const var_composite_glyphs_offset: usize = @intCast(try bin.readU32At(data, offset + 20));
    try validateRequiredOffset(coverage_offset, length, 24, 4);
    try validateRequiredOffset(var_composite_glyphs_offset, length, 24, 4);
    if (multi_var_store_offset) |value| try validateOptionalOffset(value, length, 24, 2);
    if (condition_list_offset) |value| try validateOptionalOffset(value, length, 24, 4);
    if (axis_indices_list_offset) |value| try validateOptionalOffset(value, length, 24, 4);
    return .{
        .version = (@as(u32, major) << 16) | minor,
        .coverage_offset = coverage_offset,
        .multi_var_store_offset = multi_var_store_offset,
        .condition_list_offset = condition_list_offset,
        .axis_indices_list_offset = axis_indices_list_offset,
        .var_composite_glyphs_offset = var_composite_glyphs_offset,
    };
}

fn nullableOffset(value: u32) ?usize {
    return if (value == 0) null else @intCast(value);
}

fn validateRequiredOffset(value: usize, length: usize, minimum: usize, min_len: usize) Error!void {
    if (value == 0) return error.BadSfnt;
    try validateOptionalOffset(value, length, minimum, min_len);
}

fn validateOptionalOffset(value: usize, length: usize, minimum: usize, min_len: usize) Error!void {
    if (value < minimum or value > length or min_len > length - value) return error.BadSfnt;
}

fn coverageGlyphCount(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_count: usize) Error!usize {
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    return switch (format) {
        1 => count: {
            if (table_length - coverage_offset < 4) return error.BadSfnt;
            const count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (count > (table_length - coverage_offset - 4) / 2) return error.BadSfnt;
            var previous: ?u16 = null;
            for (0..count) |index| {
                const glyph = try bin.readU16At(data, start + 4 + index * 2);
                if (glyph >= glyph_count) return error.BadSfnt;
                if (previous) |last| if (glyph <= last) return error.BadSfnt;
                previous = glyph;
            }
            break :count count;
        },
        2 => count: {
            if (table_length - coverage_offset < 4) return error.BadSfnt;
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (range_count > (table_length - coverage_offset - 4) / 6) return error.BadSfnt;
            var total: usize = 0;
            var previous_end: ?u16 = null;
            for (0..range_count) |index| {
                const record = start + 4 + index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                const start_coverage_index = try bin.readU16At(data, record + 4);
                if (first > last or last >= glyph_count) return error.BadSfnt;
                if (start_coverage_index != total) return error.BadSfnt;
                if (previous_end) |prev| if (first <= prev) return error.BadSfnt;
                previous_end = last;
                total += @as(usize, last - first) + 1;
                if (total > std.math.maxInt(u16)) return error.BadSfnt;
            }
            break :count total;
        },
        else => error.BadSfnt,
    };
}

fn coverageGlyphs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_count: usize) Error![]u16 {
    const count = try coverageGlyphCount(data, table_offset, table_length, coverage_offset, glyph_count);
    const glyphs = try allocator.alloc(u16, count);
    errdefer allocator.free(glyphs);
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    switch (format) {
        1 => {
            for (glyphs, 0..) |*glyph, index| glyph.* = try bin.readU16At(data, start + 4 + index * 2);
        },
        2 => {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            var out_index: usize = 0;
            for (0..range_count) |range_index| {
                const record = start + 4 + range_index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                var glyph = first;
                while (glyph <= last) : (glyph += 1) {
                    glyphs[out_index] = glyph;
                    out_index += 1;
                }
            }
        },
        else => return error.BadSfnt,
    }
    return glyphs;
}

fn validateIndex2Header(data: []const u8, table_offset: usize, table_length: usize, index_offset: usize) Error!void {
    if (table_length - index_offset < 4) return error.BadSfnt;
    const start = table_offset + index_offset;
    const count: usize = @intCast(try bin.readU16At(data, start));
    const off_size = data[start + 2];
    if (data[start + 3] != 0) return error.BadSfnt;
    if (off_size < 1 or off_size > 4) return error.BadSfnt;
    const offset_array_bytes = (count + 1) * @as(usize, off_size);
    if (offset_array_bytes > table_length - index_offset - 4) return error.BadSfnt;
    var previous: usize = 1;
    for (0..count + 1) |index| {
        const value = try readOffset(data, start + 4 + index * @as(usize, off_size), off_size);
        if (value < previous) return error.BadSfnt;
        if (value - 1 > table_length - index_offset - 4 - offset_array_bytes) return error.BadSfnt;
        previous = value;
    }
}

fn readOffset(data: []const u8, offset: usize, size: usize) Error!usize {
    var value: usize = 0;
    for (0..size) |index| value = (value << 8) | data[offset + index];
    return value;
}

fn validateConditionListHeader(data: []const u8, table_offset: usize, table_length: usize, list_offset: usize) Error!void {
    if (table_length - list_offset < 4) return error.BadSfnt;
    const start = table_offset + list_offset;
    const count: usize = @intCast(try bin.readU32At(data, start));
    if (count > (table_length - list_offset - 4) / 4) return error.BadSfnt;
    for (0..count) |index| {
        const cond_offset: usize = @intCast(try bin.readU32At(data, start + 4 + index * 4));
        if (cond_offset == 0 or cond_offset > table_length - list_offset or table_length - list_offset - cond_offset < 2) return error.BadSfnt;
    }
}

fn validateMultiItemVariationStoreHeader(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize) Error!void {
    if (table_length - store_offset < 8) return error.BadSfnt;
    const start = table_offset + store_offset;
    if (try bin.readU16At(data, start) != 1) return error.BadSfnt;
    const region_list_offset: usize = @intCast(try bin.readU32At(data, start + 2));
    const data_count: usize = @intCast(try bin.readU16At(data, start + 6));
    const offsets_end = 8 + data_count * 4;
    if (offsets_end > table_length - store_offset) return error.BadSfnt;
    if (region_list_offset < offsets_end or region_list_offset > table_length - store_offset or table_length - store_offset - region_list_offset < 2) return error.BadSfnt;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

test "VARC exposes top-level offsets and coverage glyphs" {
    var bytes: [42]u8 = .{0} ** 42;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU32(&bytes, 4, 24);
    writeU32(&bytes, 20, 32);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 1);
    writeU16(&bytes, 30, 3);
    writeU16(&bytes, 32, 1); // Index2 count.
    bytes[34] = 1; // offSize.
    bytes[36] = 1;
    bytes[37] = 5;
    bytes[38] = 0xaa;
    bytes[39] = 0xbb;
    bytes[40] = 0xcc;
    bytes[41] = 0xdd;

    try validate(&bytes, 0, bytes.len, 4);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 4);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u32, 0x00010000), parsed.version);
    try std.testing.expectEqual(@as(usize, 24), parsed.coverage_offset);
    try std.testing.expectEqual(@as(?usize, null), parsed.multi_var_store_offset);
    try std.testing.expectEqual(@as(usize, 32), parsed.var_composite_glyphs_offset);
    try std.testing.expectEqualSlices(u16, &.{ 1, 3 }, parsed.glyphs);
}

test "VARC coverage glyphs must stay sorted and in maxp bounds" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 4, 24);
    writeU32(&bytes, 20, 32);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 3);
    writeU16(&bytes, 30, 1);
    writeU16(&bytes, 32, 0);
    bytes[34] = 1;
    bytes[36] = 1;
    bytes[37] = 3;
    bytes[38] = 0;
    bytes[39] = 0;

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 4));
}
