const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
    InvalidName,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const Record = struct {
    offset: usize,
    tag: []const u8,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    var previous_end: usize = h.records_end;
    for (0..h.count) |index| {
        const record = try recordAt(data, offset, length, index);
        try validateLanguageTagSyntax(record.tag);
        if (record.offset < h.records_end) return error.BadSfnt;
        if (record.offset < previous_end) return error.BadSfnt;
        previous_end = record.offset + record.tag.len;
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

const Header = struct {
    count: usize,
    records_end: usize,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 12) return error.BadSfnt;
    if (try bin.readU32At(data, offset) != 1) return error.BadSfnt;
    if (try bin.readU32At(data, offset + 4) != 0) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU32At(data, offset + 8));
    if (count > (length - 12) / 4) return error.BadSfnt;
    return .{ .count = count, .records_end = 12 + count * 4 };
}

fn recordAt(data: []const u8, offset: usize, length: usize, index: usize) Error!Record {
    const record = offset + 12 + index * 4;
    const tag_offset: usize = @intCast(try bin.readU16At(data, record));
    const tag_len: usize = @intCast(try bin.readU16At(data, record + 2));
    if (tag_len == 0) return error.InvalidName;
    if (tag_offset > length or tag_len > length - tag_offset) return error.BadSfnt;
    return .{ .offset = tag_offset, .tag = data[offset + tag_offset .. offset + tag_offset + tag_len] };
}

fn validateLanguageTagSyntax(tag: []const u8) Error!void {
    var subtag_len: usize = 0;
    var subtag_index: usize = 0;
    var first_subtag_alpha = true;
    var first_subtag_first: u8 = 0;
    for (tag) |byte| {
        if (byte == '-') {
            if (subtag_len == 0 or subtag_len > 8) return error.InvalidName;
            if (subtag_index == 0 and !isValidPrimaryLanguageSubtag(first_subtag_first, subtag_len, first_subtag_alpha, true)) return error.InvalidName;
            subtag_index += 1;
            subtag_len = 0;
            continue;
        }
        if (!std.ascii.isAlphanumeric(byte)) return error.InvalidName;
        if (subtag_index == 0) {
            if (subtag_len == 0) first_subtag_first = std.ascii.toLower(byte);
            first_subtag_alpha = first_subtag_alpha and std.ascii.isAlphabetic(byte);
        }
        subtag_len += 1;
    }
    if (subtag_len == 0 or subtag_len > 8) return error.InvalidName;
    if (subtag_index == 0 and !isValidPrimaryLanguageSubtag(first_subtag_first, subtag_len, first_subtag_alpha, false)) return error.InvalidName;
}

fn isValidPrimaryLanguageSubtag(first: u8, len: usize, all_alpha: bool, has_following_subtag: bool) bool {
    if (!all_alpha) return false;
    if (len == 1) return has_following_subtag and (first == 'i' or first == 'x');
    return len >= 2 and len <= 8;
}
