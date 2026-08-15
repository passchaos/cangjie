//! Runtime resolution of validated COLR v1 ClipBox records.

const std = @import("std");

const model = @import("../../../model.zig");
const table_types = @import("../types.zig");
const variation = @import("../variation/root.zig");
const Context = @import("types.zig").Context;

pub const Error = variation.Error;

pub fn resolve(
    data: []const u8,
    table: table_types.Table,
    box: table_types.ClipBox,
    context: Context,
) Error!model.ClipBox {
    var result = model.ClipBox{
        .x_min = @floatFromInt(box.x_min),
        .y_min = @floatFromInt(box.y_min),
        .x_max = @floatFromInt(box.x_max),
        .y_max = @floatFromInt(box.y_max),
    };
    const var_index_base = box.var_index_base orelse return result;
    if (context.normalized_coords.len == 0 or
        var_index_base == variation.no_index)
    {
        return result;
    }
    const variation_context = context.variation orelse return error.BadSfnt;
    result.x_min += @floatCast(try variation.delta(
        data,
        table,
        variation_context,
        var_index_base,
        0,
        context.normalized_coords,
    ));
    result.y_min += @floatCast(try variation.delta(
        data,
        table,
        variation_context,
        var_index_base,
        1,
        context.normalized_coords,
    ));
    result.x_max += @floatCast(try variation.delta(
        data,
        table,
        variation_context,
        var_index_base,
        2,
        context.normalized_coords,
    ));
    result.y_max += @floatCast(try variation.delta(
        data,
        table,
        variation_context,
        var_index_base,
        3,
        context.normalized_coords,
    ));
    return result;
}

test "ClipBox resolution applies four consecutive deltas" {
    var bytes: [96]u8 = .{0} ** 96;
    writeItemVariationStore(&bytes, 32, &.{ 3, -4, 5, -6 });
    const resolved = try resolve(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        .{
            .format = 2,
            .x_min = 10,
            .y_min = 20,
            .x_max = 30,
            .y_max = 40,
            .var_index_base = 0,
            .range = .{ .start = 0, .end = 13 },
        },
        .{
            .normalized_coords = &.{1},
            .variation = .{
                .store_offset = 32,
                .item_data_count = 1,
                .map = null,
            },
        },
    );
    try std.testing.expectEqual(@as(f32, 13), resolved.x_min);
    try std.testing.expectEqual(@as(f32, 16), resolved.y_min);
    try std.testing.expectEqual(@as(f32, 35), resolved.x_max);
    try std.testing.expectEqual(@as(f32, 34), resolved.y_max);
}

test "static ClipBox resolution does not require variation context" {
    const resolved = try resolve(
        &.{},
        .{ .offset = 0, .length = 0 },
        .{
            .format = 1,
            .x_min = -2,
            .y_min = -3,
            .x_max = 4,
            .y_max = 5,
            .var_index_base = null,
            .range = .{ .start = 0, .end = 9 },
        },
        .{ .normalized_coords = &.{}, .variation = null },
    );
    try std.testing.expectEqual(@as(f32, -2), resolved.x_min);
    try std.testing.expectEqual(@as(f32, 5), resolved.y_max);
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

fn writeItemVariationStore(
    bytes: []u8,
    offset: usize,
    deltas: []const i16,
) void {
    writeU16(bytes, offset, 1);
    writeU32(bytes, offset + 2, 12);
    writeU16(bytes, offset + 6, 1);
    writeU32(bytes, offset + 8, 24);

    writeU16(bytes, offset + 12, 1);
    writeU16(bytes, offset + 14, 1);
    writeI16(bytes, offset + 16, 0);
    writeI16(bytes, offset + 18, 0x4000);
    writeI16(bytes, offset + 20, 0x4000);

    writeU16(bytes, offset + 24, @intCast(deltas.len));
    writeU16(bytes, offset + 26, 1);
    writeU16(bytes, offset + 28, 1);
    writeU16(bytes, offset + 30, 0);
    for (deltas, 0..) |value, index| {
        writeI16(bytes, offset + 32 + index * 2, value);
    }
}
