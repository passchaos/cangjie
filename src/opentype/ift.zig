const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Info = struct {
    format: u8,
    field_flags: u8,
    compatibility_id: [16]u8,
    default_patch_format: u8,
    entry_count: u32,
    entries_offset: usize,
    entry_id_string_data_offset: ?usize,
    url_template: []const u8,
    cff_charstrings_offset: ?u32,
    cff2_charstrings_offset: ?u32,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    _ = try info(data, offset, length);
}

pub fn info(data: []const u8, offset: usize, length: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 34) return error.BadSfnt;
    const table = data[offset .. offset + length];
    if (table[0] != 2) return error.BadSfnt;
    if (table[1] != 0 or table[2] != 0 or table[3] != 0) return error.BadSfnt;
    const field_flags = table[4];
    if ((field_flags & ~@as(u8, 0x03)) != 0) return error.BadSfnt;
    var compatibility_id: [16]u8 = undefined;
    @memcpy(&compatibility_id, table[5..21]);
    const default_patch_format = table[21];
    const entry_count = readU24(table, 22);
    const entries_offset: usize = @intCast(try bin.readU32At(table, 25));
    const id_offset_raw: usize = @intCast(try bin.readU32At(table, 29));
    const entry_id_string_data_offset: ?usize = if (id_offset_raw == 0) null else id_offset_raw;
    const url_template_len: usize = @intCast(try bin.readU16At(table, 33));
    if (url_template_len > table.len - 35) return error.BadSfnt;
    const optional_start = 35 + url_template_len;
    var cursor = optional_start;

    const cff_charstrings_offset: ?u32 = if ((field_flags & 0x01) != 0) blk: {
        if (cursor > table.len or table.len - cursor < 4) return error.BadSfnt;
        const value = try bin.readU32At(table, cursor);
        cursor += 4;
        break :blk value;
    } else null;
    const cff2_charstrings_offset: ?u32 = if ((field_flags & 0x02) != 0) blk: {
        if (cursor > table.len or table.len - cursor < 4) return error.BadSfnt;
        const value = try bin.readU32At(table, cursor);
        cursor += 4;
        break :blk value;
    } else null;

    if (entries_offset < cursor or entries_offset > table.len) return error.BadSfnt;
    if (entry_count != 0 and entries_offset == table.len) return error.BadSfnt;
    if (entry_id_string_data_offset) |id_offset| {
        if (id_offset < cursor or id_offset > table.len) return error.BadSfnt;
    }

    return .{
        .format = table[0],
        .field_flags = field_flags,
        .compatibility_id = compatibility_id,
        .default_patch_format = default_patch_format,
        .entry_count = entry_count,
        .entries_offset = entries_offset,
        .entry_id_string_data_offset = entry_id_string_data_offset,
        .url_template = table[35..optional_start],
        .cff_charstrings_offset = cff_charstrings_offset,
        .cff2_charstrings_offset = cff2_charstrings_offset,
    };
}

fn readU24(data: []const u8, offset: usize) u32 {
    return (@as(u32, data[offset]) << 16) | (@as(u32, data[offset + 1]) << 8) | data[offset + 2];
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

test "IFT patch map exposes header and URL template metadata" {
    const template = "https://example.test/{id}";
    var bytes: [73]u8 = .{0} ** 73;
    bytes[0] = 2;
    bytes[4] = 0x03;
    for (0..16) |index| bytes[5 + index] = @intCast(index);
    bytes[21] = 1;
    bytes[24] = 1;
    writeU32(&bytes, 25, 71);
    writeU16(&bytes, 33, template.len);
    @memcpy(bytes[35..][0..template.len], template);
    writeU32(&bytes, 35 + template.len, 12);
    writeU32(&bytes, 39 + template.len, 16);
    bytes[71] = 0xaa;
    bytes[72] = 0xbb;

    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(u8, 2), parsed.format);
    try std.testing.expectEqual(@as(u8, 0x03), parsed.field_flags);
    try std.testing.expectEqual(@as(u8, 15), parsed.compatibility_id[15]);
    try std.testing.expectEqual(@as(u32, 1), parsed.entry_count);
    try std.testing.expectEqual(@as(usize, 71), parsed.entries_offset);
    try std.testing.expectEqualStrings(template, parsed.url_template);
    try std.testing.expectEqual(@as(?u32, 12), parsed.cff_charstrings_offset);
    try std.testing.expectEqual(@as(?u32, 16), parsed.cff2_charstrings_offset);
}

test "IFT patch map rejects reserved flags and bad entry offsets" {
    var bytes: [35]u8 = .{0} ** 35;
    bytes[0] = 2;
    bytes[4] = 0x80;
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));

    bytes[4] = 0;
    bytes[24] = 1;
    writeU32(&bytes, 25, 35);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));
}

pub const TableKeyedPatchInfo = struct {
    format: [4]u8,
    compatibility_id: [16]u8,
    patch_offsets: []u32,
};

pub const GlyphKeyedPatchInfo = struct {
    format: [4]u8,
    flags: u8,
    compatibility_id: [16]u8,
    max_uncompressed_length: u32,
    brotli_stream: []const u8,
};

pub fn tableKeyedPatchInfo(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!TableKeyedPatchInfo {
    if (offset > data.len or length > data.len - offset or length < 30) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const format = readTag(table, 0);
    if (!std.mem.eql(u8, &format, "IFTB")) return error.BadSfnt;
    if (try bin.readU32At(table, 4) != 0) return error.BadSfnt;
    var compatibility_id: [16]u8 = undefined;
    @memcpy(&compatibility_id, table[8..24]);
    const patch_count: usize = @intCast(try bin.readU16At(table, 24));
    if (patch_count > (table.len - 26) / 4 - 1) return error.BadSfnt;
    const offsets = try allocator.alloc(u32, patch_count + 1);
    errdefer allocator.free(offsets);
    var previous: u32 = 0;
    for (offsets, 0..) |*value, index| {
        value.* = try bin.readU32At(table, 26 + index * 4);
        if (index == 0) {
            if (value.* != 0) return error.BadSfnt;
        } else if (value.* < previous) return error.BadSfnt;
        if (@as(usize, value.*) > table.len - 26 - offsets.len * 4) return error.BadSfnt;
        previous = value.*;
    }
    return .{ .format = format, .compatibility_id = compatibility_id, .patch_offsets = offsets };
}

pub fn freeTableKeyedPatchInfo(allocator: std.mem.Allocator, value: TableKeyedPatchInfo) void {
    allocator.free(value.patch_offsets);
}

pub fn glyphKeyedPatchInfo(data: []const u8, offset: usize, length: usize) Error!GlyphKeyedPatchInfo {
    if (offset > data.len or length > data.len - offset or length < 29) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const format = readTag(table, 0);
    if (!std.mem.eql(u8, &format, "IFTG")) return error.BadSfnt;
    if (try bin.readU32At(table, 4) != 0) return error.BadSfnt;
    const flags = table[8];
    if ((flags & ~@as(u8, 0x01)) != 0) return error.BadSfnt;
    var compatibility_id: [16]u8 = undefined;
    @memcpy(&compatibility_id, table[9..25]);
    const max_uncompressed_length = try bin.readU32At(table, 25);
    return .{
        .format = format,
        .flags = flags,
        .compatibility_id = compatibility_id,
        .max_uncompressed_length = max_uncompressed_length,
        .brotli_stream = table[29..],
    };
}

fn readTag(data: []const u8, offset: usize) [4]u8 {
    return .{ data[offset], data[offset + 1], data[offset + 2], data[offset + 3] };
}

test "IFT table keyed patch exposes patch offsets" {
    var bytes: [38]u8 = .{0} ** 38;
    @memcpy(bytes[0..4], "IFTB");
    for (0..16) |index| bytes[8 + index] = @intCast(index);
    writeU16(&bytes, 24, 1);
    writeU32(&bytes, 26, 0);
    writeU32(&bytes, 30, 4);
    @memcpy(bytes[34..38], "abcd");

    const parsed = try tableKeyedPatchInfo(std.testing.allocator, &bytes, 0, bytes.len);
    defer freeTableKeyedPatchInfo(std.testing.allocator, parsed);
    try std.testing.expectEqualStrings("IFTB", &parsed.format);
    try std.testing.expectEqual(@as(u8, 15), parsed.compatibility_id[15]);
    try std.testing.expectEqualSlices(u32, &.{ 0, 4 }, parsed.patch_offsets);
}

test "IFT glyph keyed patch exposes stream metadata" {
    var bytes: [35]u8 = .{0} ** 35;
    @memcpy(bytes[0..4], "IFTG");
    bytes[8] = 1;
    for (0..16) |index| bytes[9 + index] = @intCast(15 - index);
    writeU32(&bytes, 25, 1024);
    bytes[29] = 0xaa;
    bytes[30] = 0xbb;

    const parsed = try glyphKeyedPatchInfo(&bytes, 0, bytes.len);
    try std.testing.expectEqualStrings("IFTG", &parsed.format);
    try std.testing.expectEqual(@as(u8, 1), parsed.flags);
    try std.testing.expectEqual(@as(u8, 0), parsed.compatibility_id[15]);
    try std.testing.expectEqual(@as(u32, 1024), parsed.max_uncompressed_length);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb, 0, 0, 0, 0 }, parsed.brotli_stream);
}

test "IFT patch payloads reject reserved fields" {
    var table_keyed: [30]u8 = .{0} ** 30;
    @memcpy(table_keyed[0..4], "IFTB");
    writeU32(&table_keyed, 4, 1);
    try std.testing.expectError(error.BadSfnt, tableKeyedPatchInfo(std.testing.allocator, &table_keyed, 0, table_keyed.len));

    var glyph_keyed: [33]u8 = .{0} ** 33;
    @memcpy(glyph_keyed[0..4], "IFTG");
    glyph_keyed[8] = 0x80;
    try std.testing.expectError(error.BadSfnt, glyphKeyedPatchInfo(&glyph_keyed, 0, glyph_keyed.len));
}
