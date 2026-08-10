const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const Range = struct {
    max_ppem: u16,
    behavior: u16,
};

pub const Info = struct {
    version: u16,
    ranges: []Range,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const header = try headerInfo(data, offset, length);
    var previous_max: ?u16 = null;
    for (0..header.count) |index| {
        const range = try rangeAt(data, offset, length, index);
        if (previous_max) |previous| {
            if (range.max_ppem <= previous) return error.BadSfnt;
        }
        previous_max = range.max_ppem;
    }
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    const header = try headerInfo(data, offset, length);
    try validate(data, offset, length);
    const ranges = try allocator.alloc(Range, header.count);
    errdefer allocator.free(ranges);
    for (ranges, 0..) |*range, index| {
        range.* = try rangeAt(data, offset, length, index);
    }
    return .{ .version = header.version, .ranges = ranges };
}

pub fn behavior(data: []const u8, offset: usize, length: usize, ppem: u16) Error!u16 {
    const header = try headerInfo(data, offset, length);
    try validate(data, offset, length);
    for (0..header.count) |index| {
        const range = try rangeAt(data, offset, length, index);
        if (ppem <= range.max_ppem) return behaviorForVersion(header.version, range.behavior);
    }
    return 0;
}

fn behaviorForVersion(version: u16, raw: u16) u16 {
    // FreeType accepts version-0 tables that carry version-1 bits, but masks
    // them for behavior queries. Keep raw bits visible through info() while
    // matching that query behavior for compatibility with in-the-wild fonts.
    return if (version == 0) raw & 0x0003 else raw;
}

const Header = struct {
    version: u16,
    count: usize,
};

fn headerInfo(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 4) return error.BadSfnt;
    const version = try bin.readU16At(data, offset);
    if (version > 1) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU16At(data, offset + 2));
    if (count > (length - 4) / 4) return error.BadSfnt;
    if (length != 4 + count * 4) return error.BadSfnt;
    return .{ .version = version, .count = count };
}

fn rangeAt(data: []const u8, offset: usize, length: usize, index: usize) Error!Range {
    const range_offset = offset + 4 + index * 4;
    if (range_offset < offset or range_offset + 4 > offset + length) return error.BadSfnt;
    return .{
        .max_ppem = try bin.readU16At(data, range_offset),
        .behavior = try bin.readU16At(data, range_offset + 2),
    };
}

test "gasp version 0 accepts and masks version 1 behavior bits" {
    const bytes = [_]u8{
        0, 0, // version 0.
        0,    2, // numRanges.
        0,    5,
        0,    14,
        0xff, 0xff,
        0,    15,
    };

    try validate(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(u16, 0x0002), try behavior(&bytes, 0, bytes.len, 5));
    try std.testing.expectEqual(@as(u16, 0x0003), try behavior(&bytes, 0, bytes.len, 6));

    const allocator = std.testing.allocator;
    const parsed = try info(allocator, &bytes, 0, bytes.len);
    defer allocator.free(parsed.ranges);
    try std.testing.expectEqual(@as(u16, 0), parsed.version);
    try std.testing.expectEqual(@as(u16, 0x000e), parsed.ranges[0].behavior);
    try std.testing.expectEqual(@as(u16, 0x000f), parsed.ranges[1].behavior);
}
