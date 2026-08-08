const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

const ItemVariationDataRef = struct {
    data_start: usize,
    region_list_start: usize,
    axis_count: u16,
    region_count: u16,
    item_region_count: u16,
};

pub fn regionCount(table: []const u8, vstore_offset: usize, vs_index: u16) Error!usize {
    return (try itemVariationDataRef(table, vstore_offset, vs_index)).item_region_count;
}

pub fn defaultScalar(table: []const u8, vstore_offset: usize, vs_index: u16, item_region_index: usize) Error!f32 {
    const ref = try itemVariationDataRef(table, vstore_offset, vs_index);
    if (item_region_index >= ref.item_region_count) return error.BadSfnt;
    const region_index_offset = ref.data_start + 6 + item_region_index * 2;
    if (region_index_offset > table.len or table.len - region_index_offset < 2) return error.BadSfnt;
    const region_index = std.mem.readInt(u16, table[region_index_offset..][0..2], .big);
    if (region_index >= ref.region_count) return error.BadSfnt;
    return try variationRegionDefaultScalar(table, ref.region_list_start, ref.axis_count, region_index);
}

fn itemVariationDataRef(table: []const u8, vstore_offset: usize, vs_index: u16) Error!ItemVariationDataRef {
    // CFF2's Top DICT vstore operand points at a CFF2 VariationStore: a
    // USHORT length followed by a standard OpenType ItemVariationStore.
    if (vstore_offset > table.len or table.len - vstore_offset < 10) return error.BadSfnt;
    const vstore_length = std.mem.readInt(u16, table[vstore_offset..][0..2], .big);
    if (vstore_length < 10 or vstore_length > table.len - vstore_offset) return error.BadSfnt;
    const store = vstore_offset + 2;
    if (table.len - store < 8) return error.BadSfnt;
    const format = std.mem.readInt(u16, table[store..][0..2], .big);
    if (format != 1) return error.BadSfnt;
    const region_list_offset = std.mem.readInt(u32, table[store + 2 ..][0..4], .big);
    if (region_list_offset == 0) return error.BadSfnt;
    const region_list_start = store + @as(usize, @intCast(region_list_offset));
    if (region_list_start > table.len or table.len - region_list_start < 4) return error.BadSfnt;
    const axis_count = std.mem.readInt(u16, table[region_list_start..][0..2], .big);
    const region_count = std.mem.readInt(u16, table[region_list_start + 2 ..][0..2], .big);
    const region_record_size = @as(usize, axis_count) * 6;
    if (region_record_size != 0 and @as(usize, region_count) > (table.len - region_list_start - 4) / region_record_size) return error.BadSfnt;
    const data_count = std.mem.readInt(u16, table[store + 6 ..][0..2], .big);
    if (vs_index >= data_count) return error.BadSfnt;
    const offset_pos = store + 8 + @as(usize, vs_index) * 4;
    if (offset_pos > table.len or table.len - offset_pos < 4) return error.BadSfnt;
    const data_offset = std.mem.readInt(u32, table[offset_pos..][0..4], .big);
    if (data_offset == 0) return error.BadSfnt;
    const data_start = store + @as(usize, @intCast(data_offset));
    if (data_start > table.len or table.len - data_start < 6) return error.BadSfnt;
    const item_region_count = std.mem.readInt(u16, table[data_start + 4 ..][0..2], .big);
    if (item_region_count > region_count) return error.BadSfnt;
    if (@as(usize, item_region_count) > (table.len - data_start - 6) / 2) return error.BadSfnt;
    return .{
        .data_start = data_start,
        .region_list_start = region_list_start,
        .axis_count = axis_count,
        .region_count = region_count,
        .item_region_count = item_region_count,
    };
}

fn variationRegionDefaultScalar(table: []const u8, region_list_start: usize, axis_count: u16, region_index: u16) Error!f32 {
    const region_record_size = @as(usize, axis_count) * 6;
    const region_start = region_list_start + 4 + @as(usize, region_index) * region_record_size;
    if (region_start > table.len or region_record_size > table.len - region_start) return error.BadSfnt;
    var scalar: f32 = 1.0;
    for (0..axis_count) |axis| {
        const axis_offset = region_start + axis * 6;
        const start = f2dot14ToF32(std.mem.readInt(i16, table[axis_offset..][0..2], .big));
        const peak = f2dot14ToF32(std.mem.readInt(i16, table[axis_offset + 2 ..][0..2], .big));
        const end = f2dot14ToF32(std.mem.readInt(i16, table[axis_offset + 4 ..][0..2], .big));
        if (peak == 0) continue;
        if (start > peak or peak > end or (start < 0 and end > 0)) continue;
        const coord: f32 = 0;
        if (coord < start or coord > end) return 0;
        if (coord == peak) continue;
        if (coord < peak) {
            scalar = (scalar * (coord - start)) / (peak - start);
        } else {
            scalar = (scalar * (end - coord)) / (end - peak);
        }
    }
    return scalar;
}

fn f2dot14ToF32(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

test "CFF2 VariationStore default scalars" {
    const bytes = [_]u8{
        0, 40, // CFF2 VariationStore length, including this length field.
        0, 1, // ItemVariationStore format.
        0, 0, 0, 22, // VariationRegionList offset from ItemVariationStore start.
        0, 1, // One ItemVariationData subtable.
        0, 0, 0, 12, // Offset to ItemVariationData from ItemVariationStore start.
        0, 1, // itemCount.
        0, 0, // wordDeltaCount.
        0, 2, // regionIndexCount.
        0, 0, 0, 1, // Region indexes used by this ItemVariationData.
        0, 1, // axisCount.
        0, 2, // regionCount.
        0xc0, 0x00, 0, 0, 0x40, 0x00, // Region 0: scalar at coord 0 is 1.
        0, 0, 0, 0, 0, 0, // Region 1: peak 0 is ignored, scalar stays 1.
    };
    try std.testing.expectEqual(@as(usize, 2), try regionCount(&bytes, 0, 0));
    try std.testing.expectEqual(@as(f32, 1), try defaultScalar(&bytes, 0, 0, 0));
    try std.testing.expectEqual(@as(f32, 1), try defaultScalar(&bytes, 0, 0, 1));
    try std.testing.expectError(error.BadSfnt, regionCount(&bytes, 0, 1));
}
