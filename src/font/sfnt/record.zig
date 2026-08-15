//! Shared SFNT table-record and byte-range primitives.

const std = @import("std");

pub const Error = error{BadSfnt};

pub const Record = struct {
    tag: [4]u8,
    checksum: u32,
    offset: usize,
    length: usize,
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub fn find(
    records: []const Record,
    comptime table_tag: []const u8,
) ?Record {
    for (records) |record| {
        if (std.mem.eql(u8, &record.tag, table_tag)) return record;
    }
    return null;
}

pub fn findTag(records: []const Record, table_tag: [4]u8) ?Record {
    for (records) |record| {
        if (std.mem.eql(u8, &record.tag, &table_tag)) return record;
    }
    return null;
}

pub fn validateTag(tag: [4]u8) Error!void {
    for (tag) |byte| {
        // OpenType tags are printable ASCII identifiers. Keeping this rule at
        // the shared SFNT boundary also covers variation/style axis tags.
        if (byte < 0x20 or byte > 0x7e) return error.BadSfnt;
    }
}

pub fn overlaps(a: Range, b: Range) bool {
    return a.start < b.end and b.start < a.end;
}

pub fn requireLength(record: Record, minimum_length: usize) Error!void {
    if (record.length < minimum_length) return error.BadSfnt;
}
