const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const Record = struct {
    tag: [4]u8,
    offset: usize,
    data: []const u8,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    var previous_tag: ?[4]u8 = null;
    var previous_end: usize = h.data_offset;
    for (0..h.count) |index| {
        const record = try recordAt(data, offset, length, index);
        if (previous_tag) |tag| {
            if (std.mem.order(u8, &tag, &record.tag) != .lt) return error.BadSfnt;
        }
        previous_tag = record.tag;
        if (record.offset < h.data_offset) return error.BadSfnt;
        if (record.offset < previous_end) return error.BadSfnt;
        previous_end = record.offset + record.data.len;
    }
}

pub fn records(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error![]Record {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    const out = try allocator.alloc(Record, h.count);
    errdefer allocator.free(out);
    for (out, 0..) |*record, index| record.* = try recordAt(data, offset, length, index);
    return out;
}

pub fn dataForTag(data: []const u8, offset: usize, length: usize, tag: [4]u8) Error!?[]const u8 {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    for (0..h.count) |index| {
        const record = try recordAt(data, offset, length, index);
        if (std.mem.eql(u8, &record.tag, &tag)) return record.data;
    }
    return null;
}

const Header = struct {
    data_offset: usize,
    count: usize,
    records_end: usize,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    if (try bin.readU32At(data, offset) != 1) return error.BadSfnt;
    if (try bin.readU32At(data, offset + 4) != 0) return error.BadSfnt;
    const data_offset: usize = @intCast(try bin.readU32At(data, offset + 8));
    const count: usize = @intCast(try bin.readU32At(data, offset + 12));
    if (count > (length - 16) / 12) return error.BadSfnt;
    const records_end = 16 + count * 12;
    // The OpenType 'meta' header includes an explicit dataOffset pointing just
    // past the data-map records. Some older fixtures left it zero because the
    // data maps themselves carry absolute offsets; accept that legacy shape,
    // but validate non-zero production fonts against the header contract so we
    // can parse common families such as IBM Plex without weakening data bounds.
    if (data_offset != 0 and data_offset < records_end) return error.BadSfnt;
    if (data_offset > length) return error.BadSfnt;
    return .{ .data_offset = if (data_offset == 0) records_end else data_offset, .count = count, .records_end = records_end };
}

fn recordAt(data: []const u8, offset: usize, length: usize, index: usize) Error!Record {
    const record_offset = offset + 16 + index * 12;
    const tag = try bin.readTagAt(data, record_offset);
    const data_offset: usize = @intCast(try bin.readU32At(data, record_offset + 4));
    const data_len: usize = @intCast(try bin.readU32At(data, record_offset + 8));
    if (data_offset > length or data_len > length - data_offset) return error.BadSfnt;
    return .{
        .tag = tag,
        .offset = data_offset,
        .data = data[offset + data_offset .. offset + data_offset + data_len],
    };
}

test "meta accepts explicit data offset after records" {
    const bytes = [_]u8{
        0, 0, 0, 1, // version
        0, 0, 0, 0, // flags
        0, 0, 0, 28, // dataOffset
        0,   0,   0,   1, // numDataMaps
        'd', 'l', 'n', 'g',
        0, 0, 0, 28, // dataOffset
        0,   0,   0,   4, // dataLength
        'l', 'a', 't', 'n',
    };

    try validate(&bytes, 0, bytes.len);
    const data = (try dataForTag(&bytes, 0, bytes.len, .{ 'd', 'l', 'n', 'g' })).?;
    try std.testing.expectEqualStrings("latn", data);
}

test "meta rejects explicit data offset that overlaps records" {
    const bytes = [_]u8{
        0, 0, 0, 1, // version
        0, 0, 0, 0, // flags
        0, 0, 0, 16, // dataOffset, before the only data-map record ends
        0,   0,   0,   1, // numDataMaps
        'd', 'l', 'n', 'g',
        0, 0, 0, 28, // record dataOffset
        0,   0,   0,   4, // dataLength
        'l', 'a', 't', 'n',
    };

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));
}
