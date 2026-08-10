const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Feature = struct {
    feature_type: u16,
    feature_setting: u16,
    enable_flags: u32,
    disable_flags: u32,
};

pub const Subtable = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    sub_feature_flags: u32,
    format: u8,
    vertical: bool,
    backwards: bool,
    all_directions: bool,
    logical: bool,
    data: []const u8,
};

pub const Chain = struct {
    offset: usize,
    default_flags: u32,
    length: usize,
    features: []Feature,
    subtables: []Subtable,
};

pub const Info = struct {
    version: u16,
    chains: []Chain,
};

const Header = struct {
    version: u16,
    chain_count: usize,
};

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    var cursor: usize = 8;
    for (0..h.chain_count) |_| {
        const chain = try chainHeader(data, offset, length, cursor);
        try validateChain(data, offset, length, chain, h.version, glyph_count);
        cursor += chain.length;
    }
    if (cursor > length) return error.BadSfnt;
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    const chains = try allocator.alloc(Chain, h.chain_count);
    var initialized: usize = 0;
    errdefer {
        freeChains(allocator, chains[0..initialized]);
        allocator.free(chains);
    }

    var cursor: usize = 8;
    for (chains) |*out| {
        const chain = try chainHeader(data, offset, length, cursor);
        try validateChain(data, offset, length, chain, h.version, glyph_count);
        out.* = try readChain(allocator, data, offset, chain);
        initialized += 1;
        cursor += chain.length;
    }
    return .{ .version = h.version, .chains = chains };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeChains(allocator, value.chains);
    allocator.free(value.chains);
}

fn freeChains(allocator: std.mem.Allocator, chains: []Chain) void {
    for (chains) |chain| {
        allocator.free(chain.features);
        allocator.free(chain.subtables);
    }
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const version = try bin.readU16At(data, offset);
    if (version != 2 and version != 3) return error.BadSfnt;
    if (try bin.readU16At(data, offset + 2) != 0) return error.BadSfnt;
    const chain_count: usize = @intCast(try bin.readU32At(data, offset + 4));
    return .{ .version = version, .chain_count = chain_count };
}

const ChainHeader = struct {
    offset: usize,
    default_flags: u32,
    length: usize,
    feature_count: usize,
    subtable_count: usize,
};

fn chainHeader(data: []const u8, table_offset: usize, table_length: usize, offset: usize) Error!ChainHeader {
    if (offset > table_length or table_length - offset < 16) return error.BadSfnt;
    const start = table_offset + offset;
    const length: usize = @intCast(try bin.readU32At(data, start + 4));
    const feature_count: usize = @intCast(try bin.readU32At(data, start + 8));
    const subtable_count: usize = @intCast(try bin.readU32At(data, start + 12));
    if (length < 16 or (length & 3) != 0 or length > table_length - offset) return error.BadSfnt;
    if (feature_count > (length - 16) / 12) return error.BadSfnt;
    return .{
        .offset = offset,
        .default_flags = try bin.readU32At(data, start),
        .length = length,
        .feature_count = feature_count,
        .subtable_count = subtable_count,
    };
}

fn validateChain(data: []const u8, table_offset: usize, table_length: usize, chain: ChainHeader, version: u16, glyph_count: usize) Error!void {
    _ = table_length;
    const chain_start = table_offset + chain.offset;
    const chain_end = chain.offset + chain.length;
    var cursor = chain.offset + 16 + chain.feature_count * 12;
    for (0..chain.feature_count) |index| {
        _ = try readFeature(data, chain_start + 16 + index * 12);
    }

    for (0..chain.subtable_count) |_| {
        const subtable = try subtableHeader(data, table_offset, chain_end, cursor);
        cursor += subtable.length;
    }

    if (version >= 3) {
        try validateSubtableGlyphCoverage(data, table_offset, chain_end, cursor, chain.subtable_count, glyph_count);
    } else if (cursor > chain_end) {
        return error.BadSfnt;
    }
}

const SubtableHeader = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    sub_feature_flags: u32,
    format: u8,
};

fn subtableHeader(data: []const u8, table_offset: usize, chain_end: usize, offset: usize) Error!SubtableHeader {
    if (offset > chain_end or chain_end - offset < 12) return error.BadSfnt;
    const start = table_offset + offset;
    const length: usize = @intCast(try bin.readU32At(data, start));
    const coverage = try bin.readU32At(data, start + 4);
    if (length < 12 or length > chain_end - offset) return error.BadSfnt;
    if ((coverage & 0x0fffff00) != 0) return error.BadSfnt;
    const format: u8 = @intCast(coverage & 0xff);
    switch (format) {
        0, 1, 2, 4, 5 => {},
        else => return error.BadSfnt,
    }
    return .{
        .offset = offset,
        .length = length,
        .coverage = coverage,
        .sub_feature_flags = try bin.readU32At(data, start + 8),
        .format = format,
    };
}

fn validateSubtableGlyphCoverage(data: []const u8, table_offset: usize, chain_end: usize, offset: usize, subtable_count: usize, glyph_count: usize) Error!void {
    if (subtable_count == 0) {
        if (offset != chain_end) return error.BadSfnt;
        return;
    }
    const coverage_table_len = chain_end - offset;
    if (subtable_count > coverage_table_len / 4) return error.BadSfnt;
    const bitfield_len = (glyph_count + 7) / 8;
    for (0..subtable_count) |index| {
        const value = try bin.readU32At(data, table_offset + offset + index * 4);
        if (value == 0 or value == 0xffffffff) continue;
        const bitfield_offset: usize = @intCast(value);
        if (bitfield_offset < subtable_count * 4 or bitfield_offset > coverage_table_len or bitfield_len > coverage_table_len - bitfield_offset) return error.BadSfnt;
    }
}

fn readChain(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, chain: ChainHeader) Error!Chain {
    const features = try allocator.alloc(Feature, chain.feature_count);
    errdefer allocator.free(features);
    const chain_start = table_offset + chain.offset;
    for (features, 0..) |*feature, index| feature.* = try readFeature(data, chain_start + 16 + index * 12);

    const subtables = try allocator.alloc(Subtable, chain.subtable_count);
    errdefer allocator.free(subtables);
    var cursor = chain.offset + 16 + chain.feature_count * 12;
    for (subtables) |*subtable| {
        const st = try subtableHeader(data, table_offset, chain.offset + chain.length, cursor);
        subtable.* = .{
            .offset = st.offset,
            .length = st.length,
            .coverage = st.coverage,
            .sub_feature_flags = st.sub_feature_flags,
            .format = st.format,
            .vertical = (st.coverage & 0x80000000) != 0,
            .backwards = (st.coverage & 0x40000000) != 0,
            .all_directions = (st.coverage & 0x20000000) != 0,
            .logical = (st.coverage & 0x10000000) != 0,
            .data = data[table_offset + st.offset + 12 .. table_offset + st.offset + st.length],
        };
        cursor += st.length;
    }

    return .{ .offset = chain.offset, .default_flags = chain.default_flags, .length = chain.length, .features = features, .subtables = subtables };
}

fn readFeature(data: []const u8, offset: usize) Error!Feature {
    return .{
        .feature_type = try bin.readU16At(data, offset),
        .feature_setting = try bin.readU16At(data, offset + 2),
        .enable_flags = try bin.readU32At(data, offset + 4),
        .disable_flags = try bin.readU32At(data, offset + 8),
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

test "morx exposes chain feature and subtable metadata" {
    var bytes: [52]u8 = .{0} ** 52;
    writeU16(&bytes, 0, 2);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 1);
    writeU32(&bytes, 12, 44);
    writeU32(&bytes, 16, 1);
    writeU32(&bytes, 20, 1);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU32(&bytes, 28, 4);
    writeU32(&bytes, 32, 0xfffffffb);
    writeU32(&bytes, 36, 16);
    writeU32(&bytes, 40, 0x20000004);
    writeU32(&bytes, 44, 4);
    writeU32(&bytes, 48, 0x12345678);

    try validate(&bytes, 0, bytes.len, 2);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 2);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u16, 2), parsed.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.chains.len);
    try std.testing.expectEqual(@as(u32, 1), parsed.chains[0].default_flags);
    try std.testing.expectEqual(Feature{ .feature_type = 1, .feature_setting = 2, .enable_flags = 4, .disable_flags = 0xfffffffb }, parsed.chains[0].features[0]);
    try std.testing.expectEqual(@as(u8, 4), parsed.chains[0].subtables[0].format);
    try std.testing.expect(parsed.chains[0].subtables[0].all_directions);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, parsed.chains[0].subtables[0].data);
}

test "morx accepts duplicate and unsorted feature records from system fonts" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 2);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 12, 52);
    writeU32(&bytes, 16, 2);
    writeU16(&bytes, 24, 2);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 0);
    try validate(&bytes, 0, bytes.len, 2);
}
