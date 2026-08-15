//! Runtime decoding and variation resolution for COLR v1 ColorLines.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const model = @import("../../../model.zig");
const paint = @import("../paint/root.zig");
const table_types = @import("../types.zig");
const variation = @import("../variation/root.zig");
const Context = @import("types.zig").Context;

pub const Error = variation.Error;

pub fn read(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    variable: bool,
) Error!model.Paint.ColorLine {
    if (offset < table.offset or
        offset > table.offset + table.length or
        table.offset + table.length - offset < 3)
    {
        return error.BadSfnt;
    }
    const extend =
        std.enums.fromInt(model.Paint.Extend, data[offset]) orelse
        return error.BadSfnt;
    const stop_count = try bin.readU16At(data, offset + 1);
    if (stop_count == 0) return error.BadSfnt;
    const stops_data = data[offset + 3 .. table.offset + table.length];
    const stop_size = paint.colorStopSize(variable);
    if (stop_count > stops_data.len / stop_size) return error.BadSfnt;
    return .{
        .extend = extend,
        .stops_data = stops_data[0 .. @as(usize, stop_count) * stop_size],
        .stop_count = stop_count,
        .variable = variable,
    };
}

pub fn stop(
    data: []const u8,
    table: table_types.Table,
    color_line: model.Paint.ColorLine,
    index: usize,
    context: Context,
) Error!?model.Paint.ColorStop {
    var result = color_line.stop(index) orelse return null;
    if (!color_line.variable or context.normalized_coords.len == 0) {
        return result;
    }

    // ColorLine stores a bounded borrowed slice, so callers do not need the
    // original absolute ColorLine offset here. The VarColorStop-local index is
    // enough to resolve its two consecutive deltas through the table context.
    const stop_size = paint.colorStopSize(true);
    if (index > std.math.maxInt(usize) / stop_size) return error.BadSfnt;
    const start = index * stop_size;
    if (start > color_line.stops_data.len or
        stop_size > color_line.stops_data.len - start)
    {
        return error.BadSfnt;
    }
    const var_index_base =
        std.mem.readInt(u32, color_line.stops_data[start + 6 ..][0..4], .big);
    result.offset += @floatCast((try delta(
        data,
        table,
        context,
        var_index_base,
        0,
    )) / 16384.0);
    result.alpha += @floatCast((try delta(
        data,
        table,
        context,
        var_index_base,
        1,
    )) / 16384.0);
    return result;
}

pub fn stops(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: table_types.Table,
    color_line: model.Paint.ColorLine,
    context: Context,
) (Error || std.mem.Allocator.Error)![]model.Paint.ColorStop {
    const result = try allocator.alloc(
        model.Paint.ColorStop,
        color_line.stop_count,
    );
    errdefer allocator.free(result);
    for (result, 0..) |*resolved, index| {
        resolved.* = (try stop(
            data,
            table,
            color_line,
            index,
            context,
        )) orelse return error.BadSfnt;
    }

    // Variation deltas may reorder offsets even though the encoded base stops
    // are sorted. Keep equal-offset stops stable so palette transition order is
    // deterministic and matches the source ColorLine.
    for (1..result.len) |index| {
        const current = result[index];
        var destination = index;
        while (destination > 0 and
            current.offset < result[destination - 1].offset)
        {
            result[destination] = result[destination - 1];
            destination -= 1;
        }
        result[destination] = current;
    }
    return result;
}

fn delta(
    data: []const u8,
    table: table_types.Table,
    context: Context,
    var_index_base: u32,
    sequence_index: usize,
) Error!f64 {
    const variation_context = context.variation orelse return 0;
    return try variation.delta(
        data,
        table,
        variation_context,
        var_index_base,
        sequence_index,
        context.normalized_coords,
    );
}

test "ColorLine decodes bounded stop bytes" {
    var bytes: [32]u8 = .{0} ** 32;
    bytes[4] = 2;
    writeU16(&bytes, 5, 1);
    writeI16(&bytes, 7, 0x2000);
    writeU16(&bytes, 9, 7);
    writeI16(&bytes, 11, 0x4000);

    const line = try read(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        4,
        false,
    );
    try std.testing.expectEqual(model.Paint.Extend.reflect, line.extend);
    try std.testing.expectEqual(@as(u16, 1), line.stop_count);
    try std.testing.expectEqual(@as(usize, 6), line.stops_data.len);
    try std.testing.expectEqual(@as(u16, 7), line.stop(0).?.palette_index);
}

test "stop readers resolve variations and stably sort offsets" {
    var bytes: [128]u8 = .{0} ** 128;
    const color_line = model.Paint.ColorLine{
        .extend = .pad,
        .stop_count = 2,
        .stops_data = bytes[0..20],
        .variable = true,
    };
    writeI16(&bytes, 0, 0);
    writeU16(&bytes, 2, 1);
    writeI16(&bytes, 4, 0x4000);
    writeU32(&bytes, 6, 0);
    writeI16(&bytes, 10, 0x2000);
    writeU16(&bytes, 12, 2);
    writeI16(&bytes, 14, 0x2000);
    writeU32(&bytes, 16, 2);
    writeItemVariationStore(&bytes, 64, &.{ 12288, 0, -8192, 4096 });

    const table = table_types.Table{ .offset = 0, .length = bytes.len };
    const context = Context{
        .normalized_coords = &.{1},
        .variation = .{
            .store_offset = 64,
            .item_data_count = 1,
            .map = null,
        },
    };
    try std.testing.expect(
        (try stop(&bytes, table, color_line, 2, context)) == null,
    );
    const resolved = try stops(
        std.testing.allocator,
        &bytes,
        table,
        color_line,
        context,
    );
    defer std.testing.allocator.free(resolved);
    try std.testing.expectEqual(@as(usize, 2), resolved.len);
    try std.testing.expectEqual(@as(f32, 0), resolved[0].offset);
    try std.testing.expectEqual(@as(u16, 2), resolved[0].palette_index);
    try std.testing.expectEqual(@as(f32, 0.75), resolved[0].alpha);
    try std.testing.expectEqual(@as(f32, 0.75), resolved[1].offset);
    try std.testing.expectEqual(@as(u16, 1), resolved[1].palette_index);
    try std.testing.expectEqual(@as(f32, 1), resolved[1].alpha);
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
