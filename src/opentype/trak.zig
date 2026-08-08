const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const TrackValue = struct {
    size: f32,
    value: i16,
};

pub const Track = struct {
    track: f32,
    name_id: u16,
    values: []TrackValue,
};

pub const Info = struct {
    horizontal: []Track,
    vertical: []Track,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    if (h.horiz_offset) |child| try validateTrackData(data, offset, length, child);
    if (h.vert_offset) |child| try validateTrackData(data, offset, length, child);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    return .{
        .horizontal = if (h.horiz_offset) |child| try readTrackData(allocator, data, offset, length, child) else try allocator.alloc(Track, 0),
        .vertical = if (h.vert_offset) |child| try readTrackData(allocator, data, offset, length, child) else try allocator.alloc(Track, 0),
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeTracks(allocator, value.horizontal);
    freeTracks(allocator, value.vertical);
}

fn freeTracks(allocator: std.mem.Allocator, tracks: []Track) void {
    for (tracks) |track| allocator.free(track.values);
    allocator.free(tracks);
}

const Header = struct {
    horiz_offset: ?usize,
    vert_offset: ?usize,
};

const TrackHeader = struct {
    count: usize,
    size_count: usize,
    size_table_offset: usize,
    entries_start: usize,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 12) return error.BadSfnt;
    if (try bin.readU32At(data, offset) != 0x00010000) return error.BadSfnt;
    if (try bin.readU16At(data, offset + 4) != 0) return error.BadSfnt;
    const horiz: usize = @intCast(try bin.readU16At(data, offset + 6));
    const vert: usize = @intCast(try bin.readU16At(data, offset + 8));
    if (try bin.readU16At(data, offset + 10) != 0) return error.BadSfnt;
    return .{
        .horiz_offset = if (horiz == 0) null else try validateChildOffset(horiz, length, 8),
        .vert_offset = if (vert == 0) null else try validateChildOffset(vert, length, 8),
    };
}

fn validateChildOffset(offset: usize, length: usize, min_len: usize) Error!usize {
    if (offset > length or min_len > length - offset) return error.BadSfnt;
    return offset;
}

fn trackHeader(data: []const u8, table_offset: usize, table_length: usize, track_data_offset: usize) Error!TrackHeader {
    _ = try validateChildOffset(track_data_offset, table_length, 8);
    const start = table_offset + track_data_offset;
    const count: usize = @intCast(try bin.readU16At(data, start));
    const size_count: usize = @intCast(try bin.readU16At(data, start + 2));
    const size_table_offset: usize = @intCast(try bin.readU32At(data, start + 4));
    const entries_start = track_data_offset + 8;
    if (count > (table_length - entries_start) / 8) return error.BadSfnt;
    if (size_count == 0) return error.BadSfnt;
    if (size_table_offset > table_length or @as(u64, size_count) * 4 > @as(u64, table_length - size_table_offset)) return error.BadSfnt;
    return .{ .count = count, .size_count = size_count, .size_table_offset = size_table_offset, .entries_start = entries_start };
}

fn validateTrackData(data: []const u8, table_offset: usize, table_length: usize, track_data_offset: usize) Error!void {
    const h = try trackHeader(data, table_offset, table_length, track_data_offset);
    var previous_track: ?i32 = null;
    for (0..h.count) |index| {
        const entry = table_offset + h.entries_start + index * 8;
        const track = try bin.readI32At(data, entry);
        if (previous_track) |previous| {
            if (track <= previous) return error.BadSfnt;
        }
        previous_track = track;
        const value_offset: usize = @intCast(try bin.readU16At(data, entry + 6));
        if (value_offset > table_length or @as(u64, h.size_count) * 2 > @as(u64, table_length - value_offset)) return error.BadSfnt;
    }
}

fn readTrackData(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, track_data_offset: usize) Error![]Track {
    const h = try trackHeader(data, table_offset, table_length, track_data_offset);
    const tracks = try allocator.alloc(Track, h.count);
    errdefer freeTracks(allocator, tracks);
    var initialized: usize = 0;
    errdefer for (tracks[0..initialized]) |track| allocator.free(track.values);

    for (tracks, 0..) |*track, track_index| {
        const entry = table_offset + h.entries_start + track_index * 8;
        const value_offset: usize = @intCast(try bin.readU16At(data, entry + 6));
        const values = try allocator.alloc(TrackValue, h.size_count);
        errdefer allocator.free(values);
        for (values, 0..) |*value, size_index| {
            value.* = .{
                .size = fixed16_16ToF32(try bin.readI32At(data, table_offset + h.size_table_offset + size_index * 4)),
                .value = try bin.readI16At(data, table_offset + value_offset + size_index * 2),
            };
        }
        track.* = .{
            .track = fixed16_16ToF32(try bin.readI32At(data, entry)),
            .name_id = try bin.readU16At(data, entry + 4),
            .values = values,
        };
        initialized += 1;
    }
    return tracks;
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}
