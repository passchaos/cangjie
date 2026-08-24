//! Metadata decoding for validated kern tables.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{EndOfStream} || std.mem.Allocator.Error;

pub fn info(
    allocator: std.mem.Allocator,
    data: []const u8,
    kern: sfnt.Record,
) Error!types.Info {
    try sfnt.requireLength(kern, 4);
    const version = try bin.readU32At(data, kern.offset);
    if (version == 0x00010000) {
        return try appleInfo(allocator, data, kern);
    }
    if ((version >> 16) != 0) {
        return .{
            .dialect = .unsupported,
            .version = version,
            .subtables = try allocator.alloc(types.Subtable, 0),
        };
    }
    return try legacyInfo(allocator, data, kern);
}

fn legacyInfo(
    allocator: std.mem.Allocator,
    data: []const u8,
    kern: sfnt.Record,
) Error!types.Info {
    const table_count = try bin.readU16At(data, kern.offset + 2);
    const subtables = try allocator.alloc(types.Subtable, table_count);
    errdefer allocator.free(subtables);

    var subtable_offset = kern.offset + 4;
    for (subtables, 0..) |*subtable_info, subtable_index| {
        if (subtable_offset > kern.offset + kern.length or
            kern.offset + kern.length - subtable_offset < 6)
        {
            return error.BadSfnt;
        }
        var length: usize = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        const format = coverage >> 8;
        if (format == 0 and subtable_index + 1 == subtables.len) {
            if (kern.offset + kern.length - subtable_offset < 14) {
                return error.BadSfnt;
            }
            const pair_count = try bin.readU16At(data, subtable_offset + 6);
            const required_length = 14 + @as(usize, pair_count) * 6;
            if (required_length <= kern.offset + kern.length - subtable_offset) {
                length = @max(length, required_length);
            }
        }
        subtable_info.* = .{
            .offset = subtable_offset,
            .length = length,
            .format = format,
            .coverage = coverage,
            .horizontal = (coverage & 0x0001) != 0,
            .minimum = (coverage & 0x0002) != 0,
            .cross_stream = (coverage & 0x0004) != 0,
            .override = (coverage & 0x0008) != 0,
            .pair_count = if (format == 0 and length >= 14) try bin.readU16At(data, subtable_offset + 6) else null,
        };
        subtable_offset += length;
    }
    return .{ .dialect = .legacy, .version = try bin.readU16At(data, kern.offset), .subtables = subtables };
}

fn appleInfo(
    allocator: std.mem.Allocator,
    data: []const u8,
    kern: sfnt.Record,
) Error!types.Info {
    const table_count: usize = @intCast(try bin.readU32At(data, kern.offset + 4));
    const subtables = try allocator.alloc(types.Subtable, table_count);
    errdefer allocator.free(subtables);

    var subtable_offset = kern.offset + 8;
    for (subtables) |*subtable_info| {
        const length: usize = @intCast(try bin.readU32At(data, subtable_offset));
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        const format = coverage & 0x00ff;
        subtable_info.* = .{
            .offset = subtable_offset,
            .length = length,
            .format = format,
            .coverage = coverage,
            .horizontal = (coverage & 0x8000) == 0,
            .minimum = false,
            .cross_stream = (coverage & 0x4000) != 0,
            .variation = (coverage & 0x2000) != 0,
            .tuple_index = try bin.readU16At(data, subtable_offset + 6),
            .pair_count = if (format == 0 and length >= 16) try bin.readU16At(data, subtable_offset + 8) else null,
        };
        subtable_offset += length;
    }
    return .{ .dialect = .apple, .version = try bin.readU32At(data, kern.offset), .subtables = subtables };
}
