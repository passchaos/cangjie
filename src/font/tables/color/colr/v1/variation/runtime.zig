//! Runtime COLR v1 variation context and delta resolution.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const metric_variation = @import("../../../../../../opentype/metric_variation.zig");
const variation_common = @import("../../../../../../opentype/variation/root.zig");
const types = @import("../types.zig");

const delta_map = variation_common.delta_set_index_map;

pub const Error = metric_variation.Error;
pub const no_index = std.math.maxInt(u32);

pub const Context = struct {
    store_offset: usize,
    item_data_count: usize,
    map: ?delta_map.Map,
};

pub fn read(
    data: []const u8,
    table: types.Table,
) Error!?Context {
    if (table.offset > data.len or table.length > data.len - table.offset or
        table.length < 34)
    {
        return error.BadSfnt;
    }
    const store_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 30));
    if (store_offset == 0) return null;
    if (store_offset > table.length or table.length - store_offset < 8) {
        return error.BadSfnt;
    }
    const store = table.offset + store_offset;
    if (try bin.readU16At(data, store) != 1) return error.BadSfnt;
    const item_data_count: usize =
        @intCast(try bin.readU16At(data, store + 6));

    const map_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 26));
    return .{
        .store_offset = store_offset,
        .item_data_count = item_data_count,
        .map = if (map_offset == 0)
            null
        else
            try delta_map.read(
                data,
                .{ .offset = table.offset, .length = table.length },
                map_offset,
                34,
            ),
    };
}

pub fn delta(
    data: []const u8,
    table: types.Table,
    context: Context,
    var_index_base: u32,
    sequence_index: usize,
    normalized_coords: []const f32,
) Error!f64 {
    if (normalized_coords.len == 0 or var_index_base == no_index) return 0;
    if (@as(usize, var_index_base) >
        std.math.maxInt(u32) - sequence_index)
    {
        return error.BadSfnt;
    }
    const logical_index: u32 =
        var_index_base + @as(u32, @intCast(sequence_index));

    const mapped = if (context.map) |map|
        try delta_map.mappedIndex(data, map, logical_index)
    else blk: {
        if (logical_index > std.math.maxInt(u16)) return error.BadSfnt;
        break :blk delta_map.Index{
            .outer = 0,
            .inner = logical_index,
        };
    };
    if (mapped.outer == 0xffff and mapped.inner == 0xffff) return 0;
    return try metric_variation.itemVariationDeltaF64(
        data,
        table.offset,
        table.length,
        context.store_offset,
        .{ .outer = mapped.outer, .inner = mapped.inner },
        normalized_coords,
    );
}

test "runtime context reads optional variation map" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 26, 34);
    writeU32(&bytes, 30, 40);
    bytes[34] = 0;
    bytes[35] = 0;
    writeU16(&bytes, 36, 1);
    bytes[38] = 0;
    writeU16(&bytes, 40, 1);
    writeU16(&bytes, 46, 2);

    const context = (try read(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
    )).?;
    try std.testing.expectEqual(@as(usize, 40), context.store_offset);
    try std.testing.expectEqual(@as(usize, 2), context.item_data_count);
    try std.testing.expectEqual(@as(usize, 1), context.map.?.map_count);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
