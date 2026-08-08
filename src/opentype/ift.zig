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
