const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const no_variation_index: u16 = 0xffff;

pub const ValueRecord = struct {
    value_tag: [4]u8,
    delta_set_outer_index: u16,
    delta_set_inner_index: u16,

    /// OpenType 1.8.4 allows both delta-set indexes to be 0xffff to say that
    /// a known MVAR tag has no associated variation data.  Keep the raw fields
    /// available for fontations-style inspection while giving callers a simple
    /// predicate for the sentinel case.
    pub fn hasVariationData(self: ValueRecord) bool {
        return !(self.delta_set_outer_index == no_variation_index and self.delta_set_inner_index == no_variation_index);
    }
};

pub const Info = struct {
    version: u32,
    value_record_size: u16,
    item_variation_store_offset: ?usize,
    value_records: []ValueRecord,
};

pub const Header = struct {
    version: u32,
    value_record_size: usize,
    value_record_count: usize,
    item_variation_store_offset: ?usize,
    records_end: usize,
};

pub fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 12) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    if (try bin.readU16At(data, offset + 4) != 0) return error.BadSfnt;

    const value_record_size_u16 = try bin.readU16At(data, offset + 6);
    const value_record_size: usize = @intCast(value_record_size_u16);
    if (value_record_size < 8) return error.BadSfnt;

    const value_record_count: usize = @intCast(try bin.readU16At(data, offset + 8));
    if (value_record_count > (length - 12) / value_record_size) return error.BadSfnt;
    const records_end = 12 + value_record_count * value_record_size;

    const store_offset_raw: usize = @intCast(try bin.readU16At(data, offset + 10));
    const store_offset: ?usize = if (value_record_count == 0) blk: {
        // The OpenType MVAR header uses a nullable Offset16.  Enforcing zero
        // for empty record arrays prevents stale offsets from being mistaken as
        // live variation data by metadata-only callers.
        if (store_offset_raw != 0) return error.BadSfnt;
        break :blk null;
    } else blk: {
        if (store_offset_raw == 0 or store_offset_raw < records_end or store_offset_raw > length) return error.BadSfnt;
        // Full ItemVariationStore validation is shared with HVAR/VVAR in
        // font.zig because it depends on fvar axis count, but the MVAR parser
        // can still reject offsets that cannot even hold the fixed store header.
        if (length - store_offset_raw < 8) return error.BadSfnt;
        break :blk store_offset_raw;
    };

    return .{
        .version = (@as(u32, major) << 16) | @as(u32, minor),
        .value_record_size = value_record_size,
        .value_record_count = value_record_count,
        .item_variation_store_offset = store_offset,
        .records_end = records_end,
    };
}

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    try validateValueRecords(data, offset, h);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    const h = try header(data, offset, length);
    try validateValueRecords(data, offset, h);

    const records = try allocator.alloc(ValueRecord, h.value_record_count);
    errdefer allocator.free(records);
    for (records, 0..) |*record, index| record.* = try valueRecordAt(data, offset, h, index);
    return .{
        .version = h.version,
        .value_record_size = @intCast(h.value_record_size),
        .item_variation_store_offset = h.item_variation_store_offset,
        .value_records = records,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    allocator.free(value.value_records);
}

pub fn validateValueRecords(data: []const u8, table_offset: usize, h: Header) Error!void {
    var previous_tag: ?[4]u8 = null;
    for (0..h.value_record_count) |index| {
        const record = try valueRecordAt(data, table_offset, h, index);
        if (previous_tag) |previous| {
            if (std.mem.order(u8, &previous, &record.value_tag) != .lt) return error.BadSfnt;
        }
        previous_tag = record.value_tag;

        const outer_is_sentinel = record.delta_set_outer_index == no_variation_index;
        const inner_is_sentinel = record.delta_set_inner_index == no_variation_index;
        if (outer_is_sentinel != inner_is_sentinel) return error.BadSfnt;
    }
}

pub fn valueRecordAt(data: []const u8, table_offset: usize, h: Header, index: usize) Error!ValueRecord {
    if (index >= h.value_record_count) return error.BadSfnt;
    const record_relative = 12 + index * h.value_record_size;
    if (record_relative + 8 > h.records_end) return error.BadSfnt;
    if (record_relative > std.math.maxInt(usize) - table_offset) return error.BadSfnt;
    const record = table_offset + record_relative;
    return .{
        .value_tag = try bin.readTagAt(data, record),
        .delta_set_outer_index = try bin.readU16At(data, record + 4),
        .delta_set_inner_index = try bin.readU16At(data, record + 6),
    };
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeTagTest(bytes: []u8, offset: usize, comptime tag: []const u8) void {
    if (tag.len != 4) @compileError("tags in MVAR tests must be four bytes");
    @memcpy(bytes[offset .. offset + 4], tag);
}

test "MVAR value records are ordered and can omit variation data" {
    var bytes: [36]u8 = .{0} ** 36;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 6, 8);
    writeU16Test(&bytes, 8, 2);
    writeU16Test(&bytes, 10, 28);
    writeTagTest(&bytes, 12, "hasc");
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 0);
    writeTagTest(&bytes, 20, "hdsc");
    writeU16Test(&bytes, 24, no_variation_index);
    writeU16Test(&bytes, 26, no_variation_index);

    try validate(&bytes, 0, bytes.len);
    const h = try header(&bytes, 0, bytes.len);
    const first = try valueRecordAt(&bytes, 0, h, 0);
    const second = try valueRecordAt(&bytes, 0, h, 1);
    try std.testing.expect(first.hasVariationData());
    try std.testing.expect(!second.hasVariationData());

    var unsorted = bytes;
    writeTagTest(&unsorted, 20, "haaa");
    try std.testing.expectError(error.BadSfnt, validate(&unsorted, 0, unsorted.len));

    var half_sentinel = bytes;
    writeU16Test(&half_sentinel, 26, 0);
    try std.testing.expectError(error.BadSfnt, validate(&half_sentinel, 0, half_sentinel.len));
}

test "empty MVAR tables use a null item variation store offset" {
    var bytes: [12]u8 = .{0} ** 12;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 6, 8);

    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 0), parsed.value_records.len);
    try std.testing.expect(parsed.item_variation_store_offset == null);

    var stale_offset = bytes;
    writeU16Test(&stale_offset, 10, 12);
    try std.testing.expectError(error.BadSfnt, validate(&stale_offset, 0, stale_offset.len));
}
