const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Info = struct {
    major_version: u8,
    minor_version: u8,
    header_size: u8,
    top_dict_length: u16,
    top_dict_data: []const u8,
    trailing_data: []const u8,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    _ = try infoView(data, offset, length);
}

pub fn info(data: []const u8, offset: usize, length: usize) Error!Info {
    return try infoView(data, offset, length);
}

fn infoView(data: []const u8, offset: usize, length: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 5) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const major = table[0];
    const minor = table[1];
    const header_size = table[2];
    if (major != 2 or minor != 0) return error.BadSfnt;
    if (header_size < 5 or header_size > table.len) return error.BadSfnt;
    const top_dict_length = std.mem.readInt(u16, table[3..5], .big);
    if (@as(usize, top_dict_length) > table.len - header_size) return error.BadSfnt;
    const top_start: usize = header_size;
    const top_end = top_start + @as(usize, top_dict_length);
    return .{
        .major_version = major,
        .minor_version = minor,
        .header_size = header_size,
        .top_dict_length = top_dict_length,
        .top_dict_data = table[top_start..top_end],
        .trailing_data = table[top_end..],
    };
}

test "CFF2 header exposes top dict and trailing data" {
    const bytes = [_]u8{ 2, 0, 6, 0, 2, 0xff, 0x11, 0x22, 0x33 };
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(u8, 2), parsed.major_version);
    try std.testing.expectEqual(@as(u8, 6), parsed.header_size);
    try std.testing.expectEqual(@as(u16, 2), parsed.top_dict_length);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22 }, parsed.top_dict_data);
    try std.testing.expectEqualSlices(u8, &.{0x33}, parsed.trailing_data);
}

test "CFF2 rejects bad versions and oversized top dicts" {
    try std.testing.expectError(error.BadSfnt, validate(&.{ 1, 0, 5, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 4, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 5, 0, 1 }, 0, 5));
}
