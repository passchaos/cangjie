//! Runtime decoding for COLR v1 gradient geometry.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const color_lines = @import("color_line.zig");
const model = @import("../../../model.zig");
const paint = @import("../paint/root.zig");
const table_types = @import("../types.zig");
const variation = @import("../variation/root.zig");
const Context = @import("types.zig").Context;

pub const Error = variation.Error;

pub fn linearGradient(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint.LinearGradient {
    const format = data[offset];
    const info = paint.formatInfo(format) orelse return error.BadSfnt;
    const line_offset = try paint.childOffset(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        info.min_size,
        1,
    );
    const base = if (format == 5)
        try bin.readU32At(data, offset + info.min_size - 4)
    else
        variation.no_index;
    return .{
        .p0 = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 4))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    0,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 6))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    1,
                ))),
        },
        .p1 = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 8))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    2,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 10))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    3,
                ))),
        },
        .p2 = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 12))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    4,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 14))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    5,
                ))),
        },
        .color_line = try color_lines.read(
            data,
            table,
            line_offset,
            format == 5,
        ),
    };
}

pub fn radialGradient(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint.RadialGradient {
    const format = data[offset];
    const info = paint.formatInfo(format) orelse return error.BadSfnt;
    const line_offset = try paint.childOffset(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        info.min_size,
        1,
    );
    const base = if (format == 7)
        try bin.readU32At(data, offset + info.min_size - 4)
    else
        variation.no_index;
    return .{
        .c0 = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 4))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    0,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 6))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    1,
                ))),
        },
        .r0 = @as(f32, @floatFromInt(try bin.readU16At(data, offset + 8))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                2,
            ))),
        .c1 = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 10))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    3,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 12))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    4,
                ))),
        },
        .r1 = @as(f32, @floatFromInt(try bin.readU16At(data, offset + 14))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                5,
            ))),
        .color_line = try color_lines.read(
            data,
            table,
            line_offset,
            format == 7,
        ),
    };
}

pub fn sweepGradient(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint.SweepGradient {
    const format = data[offset];
    const info = paint.formatInfo(format) orelse return error.BadSfnt;
    const line_offset = try paint.childOffset(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        info.min_size,
        1,
    );
    const base = if (format == 9)
        try bin.readU32At(data, offset + info.min_size - 4)
    else
        variation.no_index;
    return .{
        .center = .{
            .x = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 4))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    0,
                ))),
            .y = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 6))) +
                @as(f32, @floatCast(try delta(
                    data,
                    table,
                    context,
                    base,
                    1,
                ))),
        },
        .start_angle = (f2dot14(try bin.readI16At(data, offset + 8)) +
            @as(f32, @floatCast((try delta(
                data,
                table,
                context,
                base,
                2,
            )) / 16384.0))) * 180.0 + 180.0,
        .end_angle = (f2dot14(try bin.readI16At(data, offset + 10)) +
            @as(f32, @floatCast((try delta(
                data,
                table,
                context,
                base,
                3,
            )) / 16384.0))) * 180.0 + 180.0,
        .color_line = try color_lines.read(
            data,
            table,
            line_offset,
            format == 9,
        ),
    };
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

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

test "sweep gradient shifts the encoded angle domain" {
    var bytes: [32]u8 = .{0} ** 32;
    bytes[0] = 8;
    writeU24(&bytes, 1, 12);
    writeI16(&bytes, 8, -0x4000);
    writeI16(&bytes, 10, 0x4000);
    bytes[12] = 0;
    writeU16(&bytes, 13, 1);
    writeI16(&bytes, 15, 0);
    writeU16(&bytes, 17, 0);
    writeI16(&bytes, 19, 0x4000);

    const result = try sweepGradient(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        0,
        .{ .normalized_coords = &.{}, .variation = null },
    );
    try std.testing.expectEqual(@as(f32, 0), result.start_angle);
    try std.testing.expectEqual(@as(f32, 360), result.end_angle);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}
