const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const ValueRecord = struct {
    value: i16,
    device_offset: u16,
};

pub const Constants = struct {
    script_percent_scale_down: i16,
    script_script_percent_scale_down: i16,
    delimited_sub_formula_min_height: u16,
    display_operator_min_height: u16,
    value_records: []ValueRecord,
    radical_degree_bottom_raise_percent: i16,
};

pub const GlyphInfo = struct {
    italics_correction_info_offset: ?usize,
    top_accent_attachment_offset: ?usize,
    extended_shape_coverage_offset: ?usize,
    math_kern_info_offset: ?usize,
    extended_shape_glyphs: []u16,
};

pub const Info = struct {
    version: u32,
    constants_offset: usize,
    glyph_info_offset: usize,
    variants_offset: usize,
    constants: Constants,
    glyph_info: GlyphInfo,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    try validateConstants(data, offset, length, h.constants_offset);
    try validateGlyphInfo(data, offset, length, h.glyph_info_offset);
    try validateChildOffset(h.variants_offset, length, 10);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    const constants = try readConstants(allocator, data, offset, h.constants_offset);
    errdefer freeConstants(allocator, constants);
    const glyph_info = try readGlyphInfo(allocator, data, offset, length, h.glyph_info_offset);
    errdefer freeGlyphInfo(allocator, glyph_info);
    return .{
        .version = h.version,
        .constants_offset = h.constants_offset,
        .glyph_info_offset = h.glyph_info_offset,
        .variants_offset = h.variants_offset,
        .constants = constants,
        .glyph_info = glyph_info,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeConstants(allocator, value.constants);
    freeGlyphInfo(allocator, value.glyph_info);
}

fn freeGlyphInfo(allocator: std.mem.Allocator, value: GlyphInfo) void {
    allocator.free(value.extended_shape_glyphs);
}

fn freeConstants(allocator: std.mem.Allocator, value: Constants) void {
    allocator.free(value.value_records);
}

const Header = struct {
    version: u32,
    constants_offset: usize,
    glyph_info_offset: usize,
    variants_offset: usize,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 10) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const constants_offset: usize = @intCast(try bin.readU16At(data, offset + 4));
    const glyph_info_offset: usize = @intCast(try bin.readU16At(data, offset + 6));
    const variants_offset: usize = @intCast(try bin.readU16At(data, offset + 8));
    try validateChildOffset(constants_offset, length, 214);
    return .{
        .version = (@as(u32, major) << 16) | minor,
        .constants_offset = constants_offset,
        .glyph_info_offset = glyph_info_offset,
        .variants_offset = variants_offset,
    };
}

fn validateChildOffset(child_offset: usize, table_length: usize, min_len: usize) Error!void {
    if (child_offset == 0 or child_offset > table_length or min_len > table_length - child_offset) return error.BadSfnt;
}

fn validateConstants(data: []const u8, table_offset: usize, table_length: usize, constants_offset: usize) Error!void {
    try validateChildOffset(constants_offset, table_length, 214);
    const constants = table_offset + constants_offset;
    for (0..51) |index| {
        const record_offset = constants + 8 + index * 4;
        const device_offset = try bin.readU16At(data, record_offset + 2);
        if (device_offset != 0) try validateDeviceTable(data, table_offset, table_length, constants_offset, device_offset);
    }
}

fn validateGlyphInfo(data: []const u8, table_offset: usize, table_length: usize, glyph_info_offset: usize) Error!void {
    try validateChildOffset(glyph_info_offset, table_length, 8);
    const start = table_offset + glyph_info_offset;
    const italic_offset = try bin.readU16At(data, start);
    const accent_offset = try bin.readU16At(data, start + 2);
    const extended_offset = try bin.readU16At(data, start + 4);
    const kern_offset = try bin.readU16At(data, start + 6);
    if (italic_offset != 0) try validateChildWithinParent(italic_offset, table_length, glyph_info_offset, 4);
    if (accent_offset != 0) try validateChildWithinParent(accent_offset, table_length, glyph_info_offset, 4);
    if (extended_offset != 0) _ = try coverageGlyphCount(data, table_offset, table_length, glyph_info_offset + @as(usize, extended_offset));
    if (kern_offset != 0) try validateChildWithinParent(kern_offset, table_length, glyph_info_offset, 2);
}

fn validateChildWithinParent(child_offset: u16, table_length: usize, parent_offset: usize, min_len: usize) Error!void {
    const relative = parent_offset + @as(usize, child_offset);
    if (relative > table_length or min_len > table_length - relative) return error.BadSfnt;
}

fn validateDeviceTable(data: []const u8, table_offset: usize, table_length: usize, parent_offset: usize, device_offset: u16) Error!void {
    const absolute_relative = parent_offset + @as(usize, device_offset);
    if (absolute_relative > table_length or table_length - absolute_relative < 6) return error.BadSfnt;
    const start = table_offset + absolute_relative;
    const start_size = try bin.readU16At(data, start);
    const end_size = try bin.readU16At(data, start + 2);
    const delta_format = try bin.readU16At(data, start + 4);
    if (start_size > end_size) return error.BadSfnt;
    const bits_per_delta: usize = switch (delta_format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.BadSfnt,
    };
    const value_count = @as(usize, end_size - start_size) + 1;
    const word_count = (value_count * bits_per_delta + 15) / 16;
    if (word_count * 2 > table_length - absolute_relative - 6) return error.BadSfnt;
}

fn readGlyphInfo(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, glyph_info_offset: usize) Error!GlyphInfo {
    try validateGlyphInfo(data, table_offset, table_length, glyph_info_offset);
    const start = table_offset + glyph_info_offset;
    const italic_offset = try bin.readU16At(data, start);
    const accent_offset = try bin.readU16At(data, start + 2);
    const extended_offset = try bin.readU16At(data, start + 4);
    const kern_offset = try bin.readU16At(data, start + 6);
    const extended_shape_glyphs = if (extended_offset != 0)
        try coverageGlyphs(allocator, data, table_offset, table_length, glyph_info_offset + @as(usize, extended_offset))
    else
        try allocator.alloc(u16, 0);
    errdefer allocator.free(extended_shape_glyphs);
    return .{
        .italics_correction_info_offset = nullableOffset(italic_offset),
        .top_accent_attachment_offset = nullableOffset(accent_offset),
        .extended_shape_coverage_offset = nullableOffset(extended_offset),
        .math_kern_info_offset = nullableOffset(kern_offset),
        .extended_shape_glyphs = extended_shape_glyphs,
    };
}

fn nullableOffset(value: u16) ?usize {
    return if (value == 0) null else @intCast(value);
}

fn coverageGlyphCount(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize) Error!usize {
    try validateChildOffset(coverage_offset, table_length, 4);
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    return switch (format) {
        1 => count: {
            const count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (count > (table_length - coverage_offset - 4) / 2) return error.BadSfnt;
            var previous: ?u16 = null;
            for (0..count) |index| {
                const glyph = try bin.readU16At(data, start + 4 + index * 2);
                if (previous) |last| if (glyph <= last) return error.BadSfnt;
                previous = glyph;
            }
            break :count count;
        },
        2 => count: {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (range_count > (table_length - coverage_offset - 4) / 6) return error.BadSfnt;
            var total: usize = 0;
            var previous_end: ?u16 = null;
            for (0..range_count) |index| {
                const record = start + 4 + index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                const start_coverage_index = try bin.readU16At(data, record + 4);
                if (first > last or start_coverage_index != total) return error.BadSfnt;
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

fn coverageGlyphs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize) Error![]u16 {
    const count = try coverageGlyphCount(data, table_offset, table_length, coverage_offset);
    const glyphs = try allocator.alloc(u16, count);
    errdefer allocator.free(glyphs);
    const start = table_offset + coverage_offset;
    switch (try bin.readU16At(data, start)) {
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

fn readConstants(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, constants_offset: usize) Error!Constants {
    const start = table_offset + constants_offset;
    const value_records = try allocator.alloc(ValueRecord, 51);
    errdefer allocator.free(value_records);
    for (value_records, 0..) |*record, index| {
        const record_offset = start + 8 + index * 4;
        record.* = .{
            .value = try bin.readI16At(data, record_offset),
            .device_offset = try bin.readU16At(data, record_offset + 2),
        };
    }
    return .{
        .script_percent_scale_down = try bin.readI16At(data, start),
        .script_script_percent_scale_down = try bin.readI16At(data, start + 2),
        .delimited_sub_formula_min_height = try bin.readU16At(data, start + 4),
        .display_operator_min_height = try bin.readU16At(data, start + 6),
        .value_records = value_records,
        .radical_degree_bottom_raise_percent = try bin.readI16At(data, start + 212),
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

test "MATH constants expose scalar and value-record metadata" {
    var bytes: [248]u8 = .{0} ** 248;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 224);
    writeU16(&bytes, 8, 238);
    writeI16(&bytes, 10, 80);
    writeI16(&bytes, 12, 60);
    writeU16(&bytes, 14, 1000);
    writeU16(&bytes, 16, 1200);
    writeI16(&bytes, 18, 11);
    writeI16(&bytes, 222, 55);
    writeU16(&bytes, 228, 8);
    writeU16(&bytes, 232, 1);
    writeU16(&bytes, 234, 1);
    writeU16(&bytes, 236, 3);

    try validate(&bytes, 0, bytes.len);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u32, 0x00010000), parsed.version);
    try std.testing.expectEqual(@as(i16, 80), parsed.constants.script_percent_scale_down);
    try std.testing.expectEqual(@as(u16, 1200), parsed.constants.display_operator_min_height);
    try std.testing.expectEqual(@as(i16, 11), parsed.constants.value_records[0].value);
    try std.testing.expectEqual(@as(i16, 55), parsed.constants.radical_degree_bottom_raise_percent);
    try std.testing.expectEqual(@as(?usize, 8), parsed.glyph_info.extended_shape_coverage_offset);
    try std.testing.expectEqualSlices(u16, &.{3}, parsed.glyph_info.extended_shape_glyphs);
}

test "MATH rejects malformed constants offsets" {
    var bytes: [20]u8 = .{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 0);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));
}
