const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Pair = struct {
    left: u16,
    right: u16,
    value: i16,
};

pub const Subtable = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    tuple_count: u32,
    format: u8,
    horizontal: bool,
    cross_stream: bool,
    variation: bool,
    backwards: bool,
    pairs: []Pair,
};

pub const Info = struct {
    version: u16,
    subtables: []Subtable,
};

const Header = struct {
    version: u16,
    table_count: usize,
};

const SubtableHeader = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    tuple_count: u32,
    format: u8,
};

const PairReadMode = enum { validate_only, allocate };

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    var subtable_offset: usize = 8;
    for (0..h.table_count) |_| {
        const subtable = try subtableHeader(data, offset, length, subtable_offset);
        try validateSubtable(data, offset, length, subtable, glyph_count);
        subtable_offset += subtable.length;
    }
    if (subtable_offset != length) return error.BadSfnt;
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    const subtables = try allocator.alloc(Subtable, h.table_count);
    var initialized: usize = 0;
    errdefer {
        freeSubtables(allocator, subtables[0..initialized]);
        allocator.free(subtables);
    }

    var subtable_offset: usize = 8;
    for (subtables) |*out| {
        const st = try subtableHeader(data, offset, length, subtable_offset);
        try validateSubtable(data, offset, length, st, glyph_count);
        const pairs = if (st.format == 0)
            try readFormat0Pairs(allocator, data, offset, st, glyph_count)
        else
            try allocator.alloc(Pair, 0);
        errdefer allocator.free(pairs);
        out.* = .{
            .offset = st.offset,
            .length = st.length,
            .coverage = st.coverage,
            .tuple_count = st.tuple_count,
            .format = st.format,
            .horizontal = (st.coverage & 0x80000000) == 0,
            .cross_stream = (st.coverage & 0x40000000) != 0,
            .variation = (st.coverage & 0x20000000) != 0,
            .backwards = (st.coverage & 0x10000000) != 0,
            .pairs = pairs,
        };
        initialized += 1;
        subtable_offset += st.length;
    }
    return .{ .version = h.version, .subtables = subtables };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeSubtables(allocator, value.subtables);
    allocator.free(value.subtables);
}

fn freeSubtables(allocator: std.mem.Allocator, subtables: []Subtable) void {
    for (subtables) |subtable| allocator.free(subtable.pairs);
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const version = try bin.readU16At(data, offset);
    if (version < 2 or version > 4) return error.BadSfnt;
    if (try bin.readU16At(data, offset + 2) != 0) return error.BadSfnt;
    const table_count: usize = @intCast(try bin.readU32At(data, offset + 4));
    return .{ .version = version, .table_count = table_count };
}

fn subtableHeader(data: []const u8, table_offset: usize, table_length: usize, offset: usize) Error!SubtableHeader {
    if (offset > table_length or table_length - offset < 12) return error.BadSfnt;
    const start = table_offset + offset;
    const length: usize = @intCast(try bin.readU32At(data, start));
    const coverage = try bin.readU32At(data, start + 4);
    if (length < 12 or length > table_length - offset) return error.BadSfnt;
    if ((coverage & 0x0fffff00) != 0) return error.BadSfnt;
    return .{
        .offset = offset,
        .length = length,
        .coverage = coverage,
        .tuple_count = try bin.readU32At(data, start + 8),
        .format = @intCast(coverage & 0xff),
    };
}

fn validateSubtable(data: []const u8, table_offset: usize, table_length: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    _ = table_length;
    switch (subtable.format) {
        0 => _ = try format0Pairs(data, table_offset, subtable, glyph_count, null, .validate_only),
        1, 2, 4, 6 => {},
        else => return error.BadSfnt,
    }
}

fn readFormat0Pairs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error![]Pair {
    const pair_count = try format0PairCount(data, table_offset, subtable);
    const pairs = try allocator.alloc(Pair, pair_count);
    errdefer allocator.free(pairs);
    _ = try format0Pairs(data, table_offset, subtable, glyph_count, pairs, .allocate);
    return pairs;
}

fn format0PairCount(data: []const u8, table_offset: usize, subtable: SubtableHeader) Error!usize {
    if (subtable.length < 28) return error.BadSfnt;
    return @intCast(try bin.readU32At(data, table_offset + subtable.offset + 12));
}

fn format0Pairs(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize, out: ?[]Pair, mode: PairReadMode) Error!usize {
    if (subtable.length < 28) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const pair_count: usize = @intCast(try bin.readU32At(data, start + 12));
    try validateFormat0Search(data, start + 16, pair_count);
    if (pair_count > (subtable.length - 28) / 6) return error.BadSfnt;
    if (mode == .allocate and (out == null or out.?.len != pair_count)) return error.BadSfnt;

    var previous: ?u32 = null;
    for (0..pair_count) |index| {
        const pair_offset = start + 28 + index * 6;
        const left = try bin.readU16At(data, pair_offset);
        const right = try bin.readU16At(data, pair_offset + 2);
        const value = try bin.readI16At(data, pair_offset + 4);
        if (left >= glyph_count or right >= glyph_count) return error.BadSfnt;
        const pair_key = (@as(u32, left) << 16) | right;
        if (previous) |last| if (pair_key <= last) return error.BadSfnt;
        previous = pair_key;
        if (out) |pairs| pairs[index] = .{ .left = left, .right = right, .value = value };
    }
    return pair_count;
}

fn validateFormat0Search(data: []const u8, offset: usize, pair_count: usize) Error!void {
    const search_range = try bin.readU32At(data, offset);
    const entry_selector = try bin.readU32At(data, offset + 4);
    const range_shift = try bin.readU32At(data, offset + 8);
    const power = floorPowerOfTwo(pair_count);
    var selector: u32 = 0;
    var tmp = power;
    while (tmp > 1) : (tmp >>= 1) selector += 1;
    const expected_search_range = power * 6;
    const expected_range_shift = pair_count * 6 - expected_search_range;
    if (expected_search_range > std.math.maxInt(u32) or expected_range_shift > std.math.maxInt(u32)) return error.BadSfnt;
    if (search_range != expected_search_range or entry_selector != selector or range_shift != expected_range_shift) return error.BadSfnt;
}

fn floorPowerOfTwo(value: usize) usize {
    if (value == 0) return 0;
    var power: usize = 1;
    while (power <= value / 2) power *= 2;
    return power;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

test "kerx format 0 exposes sorted kerning pairs" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 4);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 40);
    writeU32(&bytes, 12, 0);
    writeU32(&bytes, 16, 0);
    writeU32(&bytes, 20, 2);
    writeU32(&bytes, 24, 12);
    writeU32(&bytes, 28, 1);
    writeU32(&bytes, 32, 0);
    writeU16(&bytes, 36, 0);
    writeU16(&bytes, 38, 1);
    writeI16(&bytes, 40, -30);
    writeU16(&bytes, 42, 1);
    writeU16(&bytes, 44, 2);
    writeI16(&bytes, 46, 20);

    try validate(&bytes, 0, bytes.len, 3);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 3);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u16, 4), parsed.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.subtables.len);
    try std.testing.expect(parsed.subtables[0].horizontal);
    try std.testing.expectEqual(@as(u8, 0), parsed.subtables[0].format);
    try std.testing.expectEqual(@as(usize, 2), parsed.subtables[0].pairs.len);
    try std.testing.expectEqual(Pair{ .left = 0, .right = 1, .value = -30 }, parsed.subtables[0].pairs[0]);
    try std.testing.expectEqual(Pair{ .left = 1, .right = 2, .value = 20 }, parsed.subtables[0].pairs[1]);
}

test "kerx format 0 rejects unsorted pairs" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 4);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 40);
    writeU32(&bytes, 20, 2);
    writeU32(&bytes, 24, 12);
    writeU32(&bytes, 28, 1);
    writeU32(&bytes, 32, 0);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 2);
    writeI16(&bytes, 40, 20);
    writeU16(&bytes, 42, 0);
    writeU16(&bytes, 44, 1);
    writeI16(&bytes, 46, -30);

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 3));
}
