const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const SequenceKind = enum {
    /// The variation selector requests the base glyph from the ordinary Unicode cmap.
    default,
    /// The variation selector has an explicit non-default glyph mapping.
    non_default,
};

const Header = struct {
    table_end: usize,
    record_count: usize,
    records_end: usize,
};

const SelectorRecord = struct {
    selector: u21,
    default_offset: u32,
    non_default_offset: u32,
};

const PayloadKind = enum { default, non_default };

const PayloadRange = struct {
    start: usize,
    end: usize,
};

/// Enumerate variation selectors advertised by a cmap format-14 subtable.
///
/// Returned values are sorted by the table's validated VariationSelectorRecord
/// order. The caller owns the returned slice.
pub fn selectors(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error![]u21 {
    const header = try validate(data, offset, length);
    const out = try allocator.alloc(u21, header.record_count);
    errdefer allocator.free(out);
    for (out, 0..) |*selector, index| {
        selector.* = (try selectorRecord(data, offset, index)).selector;
    }
    return out;
}

/// Enumerate selectors that define either a default or non-default sequence for
/// `codepoint` in a format-14 subtable. The caller owns the returned slice.
pub fn selectorsForCodepoint(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, codepoint: u21) Error![]u21 {
    const header = try validate(data, offset, length);
    var out = std.ArrayList(u21).empty;
    errdefer out.deinit(allocator);

    for (0..header.record_count) |index| {
        const record = try selectorRecord(data, offset, index);
        if (try sequenceKindForRecord(data, offset, header, record, codepoint)) |_| {
            try out.append(allocator, record.selector);
        }
    }
    return try out.toOwnedSlice(allocator);
}

/// Enumerate base codepoints that are defined for `selector` in a format-14
/// subtable. Default and non-default UVS records are both included.
pub fn codepointsForSelector(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, selector: u21) Error![]u21 {
    const header = try validate(data, offset, length);
    const record = (try findSelectorRecord(data, offset, header.record_count, selector)) orelse return try allocator.alloc(u21, 0);

    var out = std.ArrayList(u21).empty;
    errdefer out.deinit(allocator);

    if (record.default_offset != 0) {
        const payload = offset + try validatePayloadOffset(record.default_offset, header.records_end, length);
        try appendDefaultCodepoints(allocator, &out, data, payload, header.table_end);
    }
    if (record.non_default_offset != 0) {
        const payload = offset + try validatePayloadOffset(record.non_default_offset, header.records_end, length);
        try appendNonDefaultCodepoints(allocator, &out, data, payload, header.table_end);
    }

    const values = try out.toOwnedSlice(allocator);
    return try sortUniqueOwned(allocator, values);
}

/// Return whether a specific Unicode variation sequence is default,
/// non-default, or absent from a format-14 subtable.
pub fn sequenceKind(data: []const u8, offset: usize, length: usize, codepoint: u21, selector: u21) Error!?SequenceKind {
    const header = try validate(data, offset, length);
    const record = (try findSelectorRecord(data, offset, header.record_count, selector)) orelse return null;
    return try sequenceKindForRecord(data, offset, header, record, codepoint);
}

fn sequenceKindForRecord(data: []const u8, offset: usize, header: Header, record: SelectorRecord, codepoint: u21) Error!?SequenceKind {
    if (record.non_default_offset != 0) {
        const payload = offset + try validatePayloadOffset(record.non_default_offset, header.records_end, header.table_end - offset);
        if (try nonDefaultContains(data, payload, header.table_end, codepoint)) return .non_default;
    }
    if (record.default_offset != 0) {
        const payload = offset + try validatePayloadOffset(record.default_offset, header.records_end, header.table_end - offset);
        if (try defaultContains(data, payload, header.table_end, codepoint)) return .default;
    }
    return null;
}

fn validate(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 10) return error.BadSfnt;
    if (try bin.readU16At(data, offset) != 14) return error.BadSfnt;

    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const records_end = try recordsEnd(length, record_count);
    const table_end = offset + length;

    var previous_selector: ?u32 = null;
    for (0..record_count) |index| {
        const record = try selectorRecord(data, offset, index);
        if (previous_selector) |last_selector| {
            if (record.selector <= last_selector) return error.BadSfnt;
        }
        previous_selector = record.selector;

        const default_range = if (record.default_offset != 0) blk: {
            const payload = offset + try validatePayloadOffset(record.default_offset, records_end, length);
            try validateDefaultPayload(data, payload, table_end);
            break :blk try payloadRange(data, payload, table_end, .default);
        } else null;
        const non_default_range = if (record.non_default_offset != 0) blk: {
            const payload = offset + try validatePayloadOffset(record.non_default_offset, records_end, length);
            try validateNonDefaultPayload(data, payload, table_end);
            break :blk try payloadRange(data, payload, table_end, .non_default);
        } else null;

        if (default_range) |range| try validatePayloadRangeDoesNotAliasPrevious(data, offset, table_end, index, range);
        if (non_default_range) |range| try validatePayloadRangeDoesNotAliasPrevious(data, offset, table_end, index, range);
        if (default_range != null and non_default_range != null) {
            if (rangesOverlap(default_range.?, non_default_range.?)) return error.BadSfnt;
            const default_payload = offset + @as(usize, record.default_offset);
            const non_default_payload = offset + @as(usize, record.non_default_offset);
            try validateSetsDisjoint(data, default_payload, non_default_payload, table_end);
        }
    }

    return .{ .table_end = table_end, .record_count = record_count, .records_end = records_end };
}

fn findSelectorRecord(data: []const u8, offset: usize, record_count: usize, selector: u21) Error!?SelectorRecord {
    const target: u32 = selector;
    for (0..record_count) |index| {
        const record = try selectorRecord(data, offset, index);
        if (target < record.selector) return null;
        if (target == record.selector) return record;
    }
    return null;
}

fn selectorRecord(data: []const u8, offset: usize, index: usize) Error!SelectorRecord {
    const record = offset + 10 + index * 11;
    const selector = try readU24(data, record);
    if (!isVariationSelector(selector)) return error.BadSfnt;
    return .{
        .selector = @intCast(selector),
        .default_offset = try bin.readU32At(data, record + 3),
        .non_default_offset = try bin.readU32At(data, record + 7),
    };
}

fn recordsEnd(length: usize, record_count: usize) Error!usize {
    if (record_count > (length - 10) / 11) return error.BadSfnt;
    return 10 + record_count * 11;
}

fn validatePayloadOffset(payload_offset: u32, records_end: usize, length: usize) Error!usize {
    const offset: usize = @intCast(payload_offset);
    if (offset < records_end or offset >= length) return error.BadSfnt;
    return offset;
}

fn payloadRange(data: []const u8, offset: usize, table_end: usize, kind: PayloadKind) Error!PayloadRange {
    if (offset + 4 > table_end) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU32At(data, offset));
    const stride: usize = switch (kind) {
        .default => 4,
        .non_default => 5,
    };
    if (count > (table_end - (offset + 4)) / stride) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + count * stride };
}

fn rangesOverlap(a: PayloadRange, b: PayloadRange) bool {
    return a.start < b.end and b.start < a.end;
}

fn validatePayloadRangeDoesNotAliasPrevious(data: []const u8, cmap_offset: usize, table_end: usize, current_record_index: usize, candidate: PayloadRange) Error!void {
    for (0..current_record_index) |previous_index| {
        const record = try selectorRecord(data, cmap_offset, previous_index);
        if (record.default_offset != 0) {
            const previous = try payloadRange(data, cmap_offset + @as(usize, record.default_offset), table_end, .default);
            if (rangesOverlap(candidate, previous)) return error.BadSfnt;
        }
        if (record.non_default_offset != 0) {
            const previous = try payloadRange(data, cmap_offset + @as(usize, record.non_default_offset), table_end, .non_default);
            if (rangesOverlap(candidate, previous)) return error.BadSfnt;
        }
    }
}

fn validateDefaultPayload(data: []const u8, offset: usize, table_end: usize) Error!void {
    const count: usize = @intCast(try bin.readU32At(data, offset));
    if (count > (table_end - (offset + 4)) / 4) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..count) |index| {
        const range = offset + 4 + index * 4;
        const start = try readU24(data, range);
        if (!isUnicodeScalar(start)) return error.BadSfnt;
        const end_u64 = @as(u64, start) + data[range + 3];
        if (end_u64 > 0x10ffff) return error.BadSfnt;
        const end: u32 = @intCast(end_u64);
        if (!isUnicodeScalar(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}

fn validateNonDefaultPayload(data: []const u8, offset: usize, table_end: usize) Error!void {
    const count: usize = @intCast(try bin.readU32At(data, offset));
    if (count > (table_end - (offset + 4)) / 5) return error.BadSfnt;

    var previous: ?u32 = null;
    for (0..count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try readU24(data, mapping);
        if (!isUnicodeScalar(unicode_value)) return error.BadSfnt;
        if (previous) |last| {
            if (unicode_value <= last) return error.BadSfnt;
        }
        previous = unicode_value;
    }
}

fn validateSetsDisjoint(data: []const u8, default_offset: usize, non_default_offset: usize, table_end: usize) Error!void {
    const default_count: usize = @intCast(try bin.readU32At(data, default_offset));
    const non_default_count: usize = @intCast(try bin.readU32At(data, non_default_offset));
    if (default_count > (table_end - (default_offset + 4)) / 4) return error.BadSfnt;
    if (non_default_count > (table_end - (non_default_offset + 4)) / 5) return error.BadSfnt;

    var default_index: usize = 0;
    for (0..non_default_count) |mapping_index| {
        const mapping = non_default_offset + 4 + mapping_index * 5;
        const unicode_value = try readU24(data, mapping);

        while (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try readU24(data, range);
            const end = start + data[range + 3];
            if (end >= unicode_value) break;
            default_index += 1;
        }
        if (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try readU24(data, range);
            const end = start + data[range + 3];
            if (unicode_value >= start and unicode_value <= end) return error.BadSfnt;
        }
    }
}

fn defaultContains(data: []const u8, offset: usize, table_end: usize, codepoint: u21) Error!bool {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count: usize = @intCast(try bin.readU32At(data, offset));
    if (range_count > (table_end - (offset + 4)) / 4) return error.BadSfnt;
    const cp: u32 = codepoint;
    for (0..range_count) |index| {
        const range = offset + 4 + index * 4;
        const start = try readU24(data, range);
        const end = start + data[range + 3];
        if (cp < start) return false;
        if (cp <= end) return true;
    }
    return false;
}

fn nonDefaultContains(data: []const u8, offset: usize, table_end: usize, codepoint: u21) Error!bool {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count: usize = @intCast(try bin.readU32At(data, offset));
    if (mapping_count > (table_end - (offset + 4)) / 5) return error.BadSfnt;
    const cp: u32 = codepoint;
    for (0..mapping_count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try readU24(data, mapping);
        if (cp < unicode_value) return false;
        if (cp == unicode_value) return true;
    }
    return false;
}

fn appendDefaultCodepoints(allocator: std.mem.Allocator, out: *std.ArrayList(u21), data: []const u8, offset: usize, table_end: usize) Error!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU32At(data, offset));
    if (count > (table_end - (offset + 4)) / 4) return error.BadSfnt;
    for (0..count) |index| {
        const range = offset + 4 + index * 4;
        const start = try readU24(data, range);
        const additional = data[range + 3];
        for (0..@as(usize, additional) + 1) |delta| {
            try out.append(allocator, @intCast(start + @as(u32, @intCast(delta))));
        }
    }
}

fn appendNonDefaultCodepoints(allocator: std.mem.Allocator, out: *std.ArrayList(u21), data: []const u8, offset: usize, table_end: usize) Error!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU32At(data, offset));
    if (count > (table_end - (offset + 4)) / 5) return error.BadSfnt;
    for (0..count) |index| {
        const mapping = offset + 4 + index * 5;
        try out.append(allocator, @intCast(try readU24(data, mapping)));
    }
}

fn sortUniqueOwned(allocator: std.mem.Allocator, values: []u21) Error![]u21 {
    std.mem.sort(u21, values, {}, u21LessThan);
    var out_len: usize = 0;
    for (values) |value| {
        if (out_len == 0 or values[out_len - 1] != value) {
            values[out_len] = value;
            out_len += 1;
        }
    }
    return try allocator.realloc(values, out_len);
}

fn u21LessThan(_: void, lhs: u21, rhs: u21) bool {
    return lhs < rhs;
}

fn readU24(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 3) return error.BadSfnt;
    return (@as(u32, data[offset]) << 16) | (@as(u32, data[offset + 1]) << 8) | data[offset + 2];
}

fn isUnicodeScalar(value: u32) bool {
    return value <= 0x10ffff and !(value >= 0xd800 and value <= 0xdfff);
}

fn isVariationSelector(value: u32) bool {
    return (value >= 0xfe00 and value <= 0xfe0f) or (value >= 0xe0100 and value <= 0xe01ef);
}
