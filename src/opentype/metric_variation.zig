const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const IndexMapEntry = struct {
    delta_set_outer_index: u32,
    delta_set_inner_index: u32,
};

pub const IndexMap = struct {
    offset: usize,
    end_offset: usize,
    format: u8,
    entry_format: u8,
    entry_size: u8,
    inner_index_bit_count: u8,
    map_data_offset: usize,
    entries: []IndexMapEntry,
};

pub const HvarInfo = struct {
    version: u32,
    item_variation_store_offset: usize,
    advance_width_mapping: ?IndexMap = null,
    lsb_mapping: ?IndexMap = null,
    rsb_mapping: ?IndexMap = null,
};

pub const VvarInfo = struct {
    version: u32,
    item_variation_store_offset: usize,
    advance_height_mapping: ?IndexMap = null,
    tsb_mapping: ?IndexMap = null,
    bsb_mapping: ?IndexMap = null,
    v_org_mapping: ?IndexMap = null,
};

const Header = struct {
    version: u32,
    item_variation_store_offset: usize,
};

pub fn hvarInfo(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!HvarInfo {
    const h = try header(data, offset, length, 20);
    var result = HvarInfo{ .version = h.version, .item_variation_store_offset = h.item_variation_store_offset };
    errdefer freeHvar(allocator, result);

    result.advance_width_mapping = try readIndexMapAtField(allocator, data, offset, length, 8, 20);
    result.lsb_mapping = try readIndexMapAtField(allocator, data, offset, length, 12, 20);
    result.rsb_mapping = try readIndexMapAtField(allocator, data, offset, length, 16, 20);
    return result;
}

pub fn vvarInfo(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!VvarInfo {
    const h = try header(data, offset, length, 24);
    var result = VvarInfo{ .version = h.version, .item_variation_store_offset = h.item_variation_store_offset };
    errdefer freeVvar(allocator, result);

    result.advance_height_mapping = try readIndexMapAtField(allocator, data, offset, length, 8, 24);
    result.tsb_mapping = try readIndexMapAtField(allocator, data, offset, length, 12, 24);
    result.bsb_mapping = try readIndexMapAtField(allocator, data, offset, length, 16, 24);
    result.v_org_mapping = try readIndexMapAtField(allocator, data, offset, length, 20, 24);
    return result;
}

pub fn freeHvar(allocator: std.mem.Allocator, info: HvarInfo) void {
    if (info.advance_width_mapping) |map| freeIndexMap(allocator, map);
    if (info.lsb_mapping) |map| freeIndexMap(allocator, map);
    if (info.rsb_mapping) |map| freeIndexMap(allocator, map);
}

pub fn freeVvar(allocator: std.mem.Allocator, info: VvarInfo) void {
    if (info.advance_height_mapping) |map| freeIndexMap(allocator, map);
    if (info.tsb_mapping) |map| freeIndexMap(allocator, map);
    if (info.bsb_mapping) |map| freeIndexMap(allocator, map);
    if (info.v_org_mapping) |map| freeIndexMap(allocator, map);
}

fn freeIndexMap(allocator: std.mem.Allocator, map: IndexMap) void {
    allocator.free(map.entries);
}

fn header(data: []const u8, offset: usize, length: usize, minimum_length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < minimum_length) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const store_offset: usize = @intCast(try bin.readU32At(data, offset + 4));
    if (store_offset < minimum_length or store_offset > length or length - store_offset < 8) return error.BadSfnt;
    return .{
        .version = (@as(u32, major) << 16) | @as(u32, minor),
        .item_variation_store_offset = store_offset,
    };
}

fn readIndexMapAtField(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, field_offset: usize, minimum_map_offset: usize) Error!?IndexMap {
    const map_offset: usize = @intCast(try bin.readU32At(data, table_offset + field_offset));
    if (map_offset == 0) return null;
    return try readIndexMap(allocator, data, table_offset, table_length, map_offset, minimum_map_offset);
}

fn readIndexMap(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, map_offset: usize, minimum_map_offset: usize) Error!IndexMap {
    if (map_offset < minimum_map_offset or map_offset > table_length or table_length - map_offset < 4) return error.BadSfnt;
    const map_start = table_offset + map_offset;
    const format = data[map_start];
    const entry_format = data[map_start + 1];
    if ((entry_format & 0xc0) != 0) return error.BadSfnt;

    const entry_size: usize = @as(usize, ((entry_format & 0x30) >> 4)) + 1;
    const inner_bit_count: usize = @as(usize, entry_format & 0x0f) + 1;
    if (inner_bit_count > entry_size * 8) return error.BadSfnt;

    const map_count, const map_data_start = switch (format) {
        0 => .{ @as(usize, @intCast(try bin.readU16At(data, map_start + 2))), map_start + 4 },
        1 => blk: {
            if (table_length - map_offset < 6) return error.BadSfnt;
            break :blk .{ @as(usize, @intCast(try bin.readU32At(data, map_start + 2))), map_start + 6 };
        },
        else => return error.BadSfnt,
    };
    if (map_count != 0 and map_count > (table_offset + table_length - map_data_start) / entry_size) return error.BadSfnt;

    const entries = try allocator.alloc(IndexMapEntry, map_count);
    errdefer allocator.free(entries);
    const map = IndexMap{
        .offset = map_offset,
        .end_offset = map_data_start - table_offset + map_count * entry_size,
        .format = format,
        .entry_format = entry_format,
        .entry_size = @intCast(entry_size),
        .inner_index_bit_count = @intCast(inner_bit_count),
        .map_data_offset = map_data_start - table_offset,
        .entries = entries,
    };
    for (entries, 0..) |*entry, index| {
        entry.* = readIndexMapEntry(data, map_data_start, map.entry_size, map.inner_index_bit_count, index);
    }
    return map;
}

fn readIndexMapEntry(data: []const u8, map_data_start: usize, entry_size: u8, inner_index_bit_count: u8, index: usize) IndexMapEntry {
    const entry_offset = map_data_start + index * @as(usize, entry_size);
    var value: u32 = 0;
    for (0..entry_size) |byte_index| {
        value = (value << 8) | data[entry_offset + byte_index];
    }

    const inner_bit_count: u5 = @intCast(inner_index_bit_count);
    const inner_mask = (@as(u32, 1) << inner_bit_count) - 1;
    return .{
        .delta_set_outer_index = value >> inner_bit_count,
        .delta_set_inner_index = value & inner_mask,
    };
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeMapWithTwoEntries(bytes: []u8, offset: usize) void {
    bytes[offset + 0] = 0;
    bytes[offset + 1] = 0; // one-byte entries with one inner-index bit.
    writeU16Test(bytes, offset + 2, 2);
    bytes[offset + 4] = 0; // outer 0, inner 0.
    bytes[offset + 5] = 1; // outer 0, inner 1.
}

test "HVAR maps expose packed delta-set indexes" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 32);
    writeU32Test(&bytes, 8, 20);
    writeMapWithTwoEntries(&bytes, 20);

    const info = try hvarInfo(std.testing.allocator, &bytes, 0, bytes.len);
    defer freeHvar(std.testing.allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(usize, 32), info.item_variation_store_offset);
    const advance = info.advance_width_mapping.?;
    try std.testing.expectEqual(@as(usize, 2), advance.entries.len);
    try std.testing.expectEqual(IndexMapEntry{ .delta_set_outer_index = 0, .delta_set_inner_index = 0 }, advance.entries[0]);
    try std.testing.expectEqual(IndexMapEntry{ .delta_set_outer_index = 0, .delta_set_inner_index = 1 }, advance.entries[1]);
    try std.testing.expect(info.lsb_mapping == null);
}

test "VVAR reads the fourth vertical-origin map" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 40);
    writeU32Test(&bytes, 20, 24);
    writeMapWithTwoEntries(&bytes, 24);

    const info = try vvarInfo(std.testing.allocator, &bytes, 0, bytes.len);
    defer freeVvar(std.testing.allocator, info);
    try std.testing.expect(info.advance_height_mapping == null);
    const origin = info.v_org_mapping.?;
    try std.testing.expectEqual(@as(usize, 2), origin.entries.len);
}
