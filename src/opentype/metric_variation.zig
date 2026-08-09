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

pub fn hvarAdvanceWidthDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!i32 {
    return try advanceDelta(data, offset, length, 20, 8, glyph_id, normalized_coords);
}

pub fn hvarLeftSideBearingDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    return try optionalMappedDelta(data, offset, length, 20, 12, glyph_id, normalized_coords);
}

pub fn hvarRightSideBearingDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    return try optionalMappedDelta(data, offset, length, 20, 16, glyph_id, normalized_coords);
}

pub fn vvarAdvanceHeightDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!i32 {
    return try advanceDelta(data, offset, length, 24, 8, glyph_id, normalized_coords);
}

pub fn vvarTopSideBearingDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    return try optionalMappedDelta(data, offset, length, 24, 12, glyph_id, normalized_coords);
}

pub fn vvarBottomSideBearingDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    return try optionalMappedDelta(data, offset, length, 24, 16, glyph_id, normalized_coords);
}

pub fn vvarVerticalOriginDelta(data: []const u8, offset: usize, length: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    return try optionalMappedDelta(data, offset, length, 24, 20, glyph_id, normalized_coords);
}

fn advanceDelta(data: []const u8, offset: usize, length: usize, minimum_length: usize, map_field_offset: usize, glyph_id: usize, normalized_coords: []const f32) Error!i32 {
    if (normalized_coords.len == 0) return 0;
    const h = try header(data, offset, length, minimum_length);
    const map_offset: usize = @intCast(try bin.readU32At(data, offset + map_field_offset));
    const index = if (map_offset == 0)
        DeltaSetIndex{ .outer = glyph_id >> 16, .inner = glyph_id & 0xffff }
    else
        try deltaSetIndexForMappedItem(data, offset, length, map_offset, minimum_length, glyph_id);
    return try itemVariationDelta(data, offset, length, h.item_variation_store_offset, index, normalized_coords);
}

fn optionalMappedDelta(data: []const u8, offset: usize, length: usize, minimum_length: usize, map_field_offset: usize, glyph_id: usize, normalized_coords: []const f32) Error!?i32 {
    if (normalized_coords.len == 0) return 0;
    const h = try header(data, offset, length, minimum_length);
    const map_offset: usize = @intCast(try bin.readU32At(data, offset + map_field_offset));
    if (map_offset == 0) return null;
    const index = try deltaSetIndexForMappedItem(data, offset, length, map_offset, minimum_length, glyph_id);
    return try itemVariationDelta(data, offset, length, h.item_variation_store_offset, index, normalized_coords);
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

pub const DeltaSetIndex = struct {
    outer: usize,
    inner: usize,
};

fn deltaSetIndexForMappedItem(data: []const u8, table_offset: usize, table_length: usize, map_offset: usize, minimum_map_offset: usize, item_index: usize) Error!DeltaSetIndex {
    if (map_offset < minimum_map_offset or map_offset > table_length or table_length - map_offset < 4) return error.BadSfnt;
    const map_start = table_offset + map_offset;
    const format = data[map_start];
    const entry_format = data[map_start + 1];
    if ((entry_format & 0xc0) != 0) return error.BadSfnt;

    const entry_size = @as(usize, ((entry_format & 0x30) >> 4)) + 1;
    const inner_bit_count = @as(usize, entry_format & 0x0f) + 1;
    if (inner_bit_count > entry_size * 8) return error.BadSfnt;

    const map_count, const map_data_start = switch (format) {
        0 => .{ @as(usize, @intCast(try bin.readU16At(data, map_start + 2))), map_start + 4 },
        1 => blk: {
            if (table_length - map_offset < 6) return error.BadSfnt;
            break :blk .{ @as(usize, @intCast(try bin.readU32At(data, map_start + 2))), map_start + 6 };
        },
        else => return error.BadSfnt,
    };
    if (map_count == 0) return .{ .outer = item_index >> 16, .inner = item_index & 0xffff };
    if (map_count > (table_offset + table_length - map_data_start) / entry_size) return error.BadSfnt;

    // The OpenType variation-common format deliberately reuses the final map
    // entry when an item id is beyond mapCount. This is required for production
    // HVAR tables with truncated advance maps and matches fontations/HarfBuzz.
    const mapped_index = @min(item_index, map_count - 1);
    const entry_offset = map_data_start + mapped_index * entry_size;
    var value: u32 = 0;
    for (0..entry_size) |byte_index| {
        value = (value << 8) | data[entry_offset + byte_index];
    }
    const inner_shift: u5 = @intCast(inner_bit_count);
    const inner_mask = (@as(u32, 1) << inner_shift) - 1;
    return .{
        .outer = @intCast(value >> inner_shift),
        .inner = @intCast(value & inner_mask),
    };
}

fn itemVariationDelta(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize, index: DeltaSetIndex, normalized_coords: []const f32) Error!i32 {
    return roundF64ToI32(try itemVariationDeltaF64(data, table_offset, table_length, store_offset, index, normalized_coords));
}

/// Evaluate an ItemVariationStore row without metric rounding.
///
/// COLR v1 applies these deltas to several non-integer target types (Fixed and
/// F2Dot14 as well as FWORD), so its runtime resolver must retain the fractional
/// result. HVAR/VVAR call the same decoder and round only at their integer API
/// boundary, keeping the packed-row and region-scalar semantics in one place.
pub fn itemVariationDeltaF64(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize, index: DeltaSetIndex, normalized_coords: []const f32) Error!f64 {
    if (normalized_coords.len == 0 or (index.outer == 0xffff and index.inner == 0xffff)) return 0;
    if (store_offset > table_length or table_length - store_offset < 8) return error.BadSfnt;
    const store = table_offset + store_offset;
    const format = try bin.readU16At(data, store);
    if (format != 1) return error.BadSfnt;
    const region_list_offset: usize = @intCast(try bin.readU32At(data, store + 2));
    const item_data_count: usize = @intCast(try bin.readU16At(data, store + 6));
    if (index.outer >= item_data_count) return 0;
    const offsets_array_end = 8 + item_data_count * 4;
    if (offsets_array_end > table_length - store_offset) return error.BadSfnt;

    const region_list = try variationRegionListRef(data, table_offset, table_length, store_offset, region_list_offset, offsets_array_end);
    const item_data_offset: usize = @intCast(try bin.readU32At(data, store + 8 + index.outer * 4));
    const item_data = try itemVariationDataRef(data, table_offset, table_length, store_offset, item_data_offset, region_list.region_count);
    if (index.inner >= item_data.item_count) return 0;

    var accum: f64 = 0;
    for (0..item_data.region_index_count) |region_delta_index| {
        const region_index = try bin.readU16At(data, item_data.region_indexes_offset + region_delta_index * 2);
        const scalar = try variationRegionScalar(data, region_list, region_index, normalized_coords);
        const delta = try itemVariationDeltaValue(data, item_data, index.inner, region_delta_index);
        accum += @as(f64, @floatFromInt(delta)) * scalar;
    }
    return accum;
}

const VariationRegionListRef = struct {
    offset: usize,
    axis_count: usize,
    region_count: usize,
};

fn variationRegionListRef(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize, region_list_offset: usize, minimum_region_offset: usize) Error!VariationRegionListRef {
    if (region_list_offset < minimum_region_offset or region_list_offset > table_length - store_offset or table_length - store_offset - region_list_offset < 4) return error.BadSfnt;
    const region_list = table_offset + store_offset + region_list_offset;
    const axis_count: usize = @intCast(try bin.readU16At(data, region_list));
    const region_count: usize = @intCast(try bin.readU16At(data, region_list + 2));
    const region_bytes = region_count * axis_count * 6;
    if (region_bytes > table_length - store_offset - region_list_offset - 4) return error.BadSfnt;
    return .{
        .offset = region_list,
        .axis_count = axis_count,
        .region_count = region_count,
    };
}

const ItemVariationDataRef = struct {
    offset: usize,
    item_count: usize,
    word_delta_count: usize,
    long_words: bool,
    region_index_count: usize,
    region_indexes_offset: usize,
    delta_rows_offset: usize,
    row_size: usize,
};

fn itemVariationDataRef(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize, item_data_offset: usize, region_count: usize) Error!ItemVariationDataRef {
    if (item_data_offset > table_length - store_offset or table_length - store_offset - item_data_offset < 6) return error.BadSfnt;
    const item_data = table_offset + store_offset + item_data_offset;
    const item_count: usize = @intCast(try bin.readU16At(data, item_data));
    const raw_word_delta_count = try bin.readU16At(data, item_data + 2);
    const region_index_count: usize = @intCast(try bin.readU16At(data, item_data + 4));
    const word_delta_count: usize = @intCast(raw_word_delta_count & 0x7fff);
    const long_words = (raw_word_delta_count & 0x8000) != 0;
    if (word_delta_count > region_index_count or region_index_count > region_count) return error.BadSfnt;

    const region_indexes_offset = item_data + 6;
    const region_indexes_bytes = region_index_count * 2;
    if (region_indexes_bytes > table_length - store_offset - item_data_offset - 6) return error.BadSfnt;
    for (0..region_index_count) |region_index_offset| {
        const region_index = try bin.readU16At(data, region_indexes_offset + region_index_offset * 2);
        if (region_index >= region_count) return error.BadSfnt;
    }

    const remaining = table_length - store_offset - item_data_offset - 6 - region_indexes_bytes;
    const narrow_delta_count = region_index_count - word_delta_count;
    const row_size = if (long_words)
        word_delta_count * 4 + narrow_delta_count * 2
    else
        word_delta_count * 2 + narrow_delta_count;
    if (row_size != 0 and item_count > remaining / row_size) return error.BadSfnt;
    return .{
        .offset = item_data,
        .item_count = item_count,
        .word_delta_count = word_delta_count,
        .long_words = long_words,
        .region_index_count = region_index_count,
        .region_indexes_offset = region_indexes_offset,
        .delta_rows_offset = region_indexes_offset + region_indexes_bytes,
        .row_size = row_size,
    };
}

fn itemVariationDeltaValue(data: []const u8, item_data: ItemVariationDataRef, item_index: usize, region_delta_index: usize) Error!i32 {
    if (item_index >= item_data.item_count or region_delta_index >= item_data.region_index_count) return error.BadSfnt;
    const row = item_data.delta_rows_offset + item_index * item_data.row_size;
    if (region_delta_index < item_data.word_delta_count) {
        const value_offset = row + if (item_data.long_words) region_delta_index * 4 else region_delta_index * 2;
        return if (item_data.long_words)
            try bin.readI32At(data, value_offset)
        else
            try bin.readI16At(data, value_offset);
    }

    const narrow_index = region_delta_index - item_data.word_delta_count;
    const narrow_start = row + if (item_data.long_words) item_data.word_delta_count * 4 else item_data.word_delta_count * 2;
    return if (item_data.long_words)
        try bin.readI16At(data, narrow_start + narrow_index * 2)
    else
        @as(i8, @bitCast(data[narrow_start + narrow_index]));
}

fn variationRegionScalar(data: []const u8, region_list: VariationRegionListRef, region_index: usize, normalized_coords: []const f32) Error!f64 {
    if (region_index >= region_list.region_count) return error.BadSfnt;
    const region_record_size = region_list.axis_count * 6;
    const region_start = region_list.offset + 4 + region_index * region_record_size;
    var scalar: f32 = 1.0;
    for (0..region_list.axis_count) |axis_index| {
        const axis_offset = region_start + axis_index * 6;
        const start = try bin.readI16At(data, axis_offset);
        const peak = try bin.readI16At(data, axis_offset + 2);
        const end = try bin.readI16At(data, axis_offset + 4);
        // A zero peak makes this axis inactive for the region. In particular,
        // do not divide through a [0, 0, end] tent: OpenType defines it as
        // contributing a scalar of one on this axis.
        if (peak == 0) continue;
        if (start > peak or peak > end or (start < 0 and end > 0)) continue;
        const coord = try normalizedF2Dot14Bits(if (axis_index < normalized_coords.len) normalized_coords[axis_index] else 0);
        if (coord < start or coord > end) return 0;
        if (coord == peak) continue;
        if (coord < peak) {
            scalar = (scalar * @as(f32, @floatFromInt(@as(i32, coord) - start))) /
                @as(f32, @floatFromInt(@as(i32, peak) - start));
        } else {
            scalar = (scalar * @as(f32, @floatFromInt(@as(i32, end) - coord))) /
                @as(f32, @floatFromInt(@as(i32, end) - peak));
        }
    }
    return scalar;
}

fn normalizedF2Dot14Bits(value: f32) Error!i16 {
    if (!std.math.isFinite(value) or value < -1 or value > 1) return error.BadSfnt;
    // Public variation APIs carry f32, while ItemVariationStore regions and
    // Fontations/Skrifa locations are F2Dot14. Quantize before support tests so
    // values such as 0.4 resolve to 0.4000244140625 rather than crossing a tent
    // boundary or losing the small fractional delta observable in COLR.
    const bias: f32 = if (std.math.signbit(value)) -0.5 else 0.5;
    return @intFromFloat(value * 16384.0 + bias);
}

fn roundF64ToI32(value: f64) i32 {
    const rounded = @floor(value + 0.5);
    if (rounded <= @as(f64, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    if (rounded >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(rounded);
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

test "HVAR advance deltas apply item variation store scalars" {
    var bytes: [72]u8 = .{0} ** 72;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 36);
    writeU32Test(&bytes, 8, 20);
    writeMapWithTwoEntries(&bytes, 20);
    writeItemVariationStoreWithItemsTest(&bytes, 36, 2);

    try std.testing.expectEqual(@as(i32, 0), try hvarAdvanceWidthDelta(&bytes, 0, bytes.len, 1, &.{}));
    try std.testing.expectEqual(@as(i32, 4), try hvarAdvanceWidthDelta(&bytes, 0, bytes.len, 1, &.{0.5}));
    try std.testing.expectEqual(@as(i32, 7), try hvarAdvanceWidthDelta(&bytes, 0, bytes.len, 99, &.{1.0}));
    try std.testing.expectError(error.BadSfnt, hvarAdvanceWidthDelta(&bytes, 0, bytes.len, 1, &.{std.math.inf(f32)}));
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

fn writeItemVariationStoreWithItemsTest(bytes: []u8, offset: usize, item_count: u16) void {
    writeU16Test(bytes, offset + 0, 1); // format.
    writeU32Test(bytes, offset + 2, 12); // VariationRegionList offset.
    writeU16Test(bytes, offset + 6, 1); // itemVariationDataCount.
    writeU32Test(bytes, offset + 8, 24); // ItemVariationData offset.

    writeU16Test(bytes, offset + 12, 1); // axisCount.
    writeU16Test(bytes, offset + 14, 1); // regionCount.
    writeF2Dot14Test(bytes, offset + 16, 0.0);
    writeF2Dot14Test(bytes, offset + 18, 1.0);
    writeF2Dot14Test(bytes, offset + 20, 1.0);

    writeU16Test(bytes, offset + 24, item_count);
    writeU16Test(bytes, offset + 26, 1); // wordDeltaCount.
    writeU16Test(bytes, offset + 28, 1); // regionIndexCount.
    writeU16Test(bytes, offset + 30, 0); // regionIndexes[0].
    for (0..item_count) |index| {
        writeU16Test(bytes, offset + 32 + index * 2, 7);
    }
}

fn writeF2Dot14Test(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i16 = @intFromFloat(value * 16384.0);
    std.mem.writeInt(i16, bytes[offset..][0..2], fixed, .big);
}
