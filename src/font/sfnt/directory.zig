//! SFNT offset-table and table-directory structural validation.

const std = @import("std");

const record_mod = @import("record.zig");
const Error = record_mod.Error;
const Range = record_mod.Range;
const Record = record_mod.Record;

pub fn validateSearchParameters(
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
) Error!void {
    if (num_tables == 0) return error.BadSfnt;

    var max_power_of_two: usize = 1;
    var expected_entry_selector: u16 = 0;
    while (max_power_of_two * 2 <= num_tables) {
        max_power_of_two *= 2;
        expected_entry_selector += 1;
    }

    const expected_search_range = max_power_of_two * 16;
    const table_record_bytes = @as(usize, num_tables) * 16;
    if (expected_search_range > std.math.maxInt(u16) or
        table_record_bytes > std.math.maxInt(u16))
    {
        return error.BadSfnt;
    }
    // Legacy AAT fonts with stale rangeShift are admitted by Font only when
    // they actually carry mort/morx. The common fields remain strict here.
    _ = range_shift;
    if (search_range != expected_search_range or
        entry_selector != expected_entry_selector)
    {
        return error.BadSfnt;
    }
}

pub fn expectedRangeShift(num_tables: u16) Error!u16 {
    var max_power_of_two: usize = 1;
    while (max_power_of_two * 2 <= num_tables) {
        max_power_of_two *= 2;
    }
    const expected_search_range = max_power_of_two * 16;
    const table_record_bytes = @as(usize, num_tables) * 16;
    if (expected_search_range > std.math.maxInt(u16) or
        table_record_bytes > std.math.maxInt(u16))
    {
        return error.BadSfnt;
    }
    return @intCast(table_record_bytes - expected_search_range);
}

pub fn end(data_len: usize, start: usize, num_tables: u16) Error!usize {
    const record_bytes = @as(usize, num_tables) * 16;
    if (start > data_len or data_len - start < 12) return error.BadSfnt;
    if (record_bytes > data_len - start - 12) return error.BadSfnt;
    return start + 12 + record_bytes;
}

pub fn validate(records: []const Record) Error!void {
    var previous_tag: ?[4]u8 = null;
    for (records) |record| {
        try record_mod.validateTag(record.tag);
        if (previous_tag) |previous| {
            // Strict lexical order simultaneously rejects duplicate tags and
            // makes all table lookup independent of malformed source order.
            if (std.mem.order(u8, &previous, &record.tag) != .lt) {
                return error.BadSfnt;
            }
        }
        previous_tag = record.tag;
    }
}

pub fn validateRanges(
    records: []const Record,
    reserved_prefix_end: usize,
    directory: Range,
) Error!void {
    for (records, 0..) |record, index| {
        if (record.length == 0) continue;
        // Payload starts are long-aligned, while directory lengths exclude
        // their trailing zero padding.
        if ((record.offset & 3) != 0) return error.BadSfnt;
        const record_range = try rangeForRecord(record);
        if (record.offset < reserved_prefix_end) return error.BadSfnt;
        if (record_mod.overlaps(record_range, directory)) {
            return error.BadSfnt;
        }
        for (records[index + 1 ..]) |other| {
            if (other.length == 0) continue;
            if (record_mod.overlaps(
                record_range,
                try rangeForRecord(other),
            )) {
                return error.BadSfnt;
            }
        }
    }
}

pub fn validatePadding(data: []const u8, records: []const Record) Error!void {
    for (records) |record| {
        const record_range = try boundedRange(data.len, record);
        const padding_len = (4 - (record.length & 3)) & 3;
        if (padding_len == 0 or record_range.end == data.len) continue;

        // Checksums model missing alignment bytes as zero. Reject non-zero
        // physical padding so it cannot hide data between table payloads.
        const present_padding_len =
            @min(padding_len, data.len - record_range.end);
        for (data[record_range.end .. record_range.end + present_padding_len]) |byte| {
            if (byte != 0) return error.BadSfnt;
        }
    }
}

pub fn validateDisjoint(
    records: []const Record,
    reserved: Range,
) Error!void {
    for (records) |record| {
        if (record.length == 0) continue;
        if (record_mod.overlaps(try rangeForRecord(record), reserved)) {
            return error.BadSfnt;
        }
    }
}

fn rangeForRecord(record: Record) Error!Range {
    const end_offset = std.math.add(
        usize,
        record.offset,
        record.length,
    ) catch return error.BadSfnt;
    return .{ .start = record.offset, .end = end_offset };
}

fn boundedRange(data_len: usize, record: Record) Error!Range {
    if (record.offset > data_len or record.length > data_len - record.offset) {
        return error.BadSfnt;
    }
    return .{
        .start = record.offset,
        .end = record.offset + record.length,
    };
}
