//! Runtime decoding for COLR v1 transform Paint formats.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const model = @import("../../../model.zig");
const paint = @import("../paint/root.zig");
const table_types = @import("../types.zig");
const variation = @import("../variation/root.zig");
const Context = @import("types.zig").Context;

pub const Error = variation.Error;

pub fn transform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint.TransformPaint {
    const format = data[offset];
    const info = paint.formatInfo(format) orelse return error.BadSfnt;
    const paint_table = paint.Table{
        .offset = table.offset,
        .length = table.length,
    };
    const child = try paint.childOffset(
        data,
        paint_table,
        offset,
        info.min_size,
        1,
    );
    const affine = switch (format) {
        12, 13 => try affineTransform(data, table, offset, info, context),
        14, 15 => try translateTransform(data, table, offset, format, context),
        16...23 => try scaleTransform(data, table, offset, format, context),
        24...27 => try rotateTransform(data, table, offset, format, context),
        28...31 => try skewTransform(data, table, offset, format, context),
        else => return error.BadSfnt,
    };
    return .{ .affine = affine, .child = .{ .offset = child } };
}

fn affineTransform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    info: paint.FormatInfo,
    context: Context,
) Error!model.Affine {
    const matrix = try paint.transformPayloadRange(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        info.min_size,
    );
    const base = matrix.start;
    const var_index = if (data[offset] == 13)
        try bin.readU32At(data, base + 24)
    else
        variation.no_index;
    var values: [6]f32 = undefined;
    for (&values, 0..) |*value, index| {
        value.* = fixed16_16(try bin.readI32At(data, base + index * 4)) +
            @as(f32, @floatCast((try delta(
                data,
                table,
                context,
                var_index,
                index,
            )) / 65536.0));
    }
    return .{
        .xx = values[0],
        .yx = values[1],
        .xy = values[2],
        .yy = values[3],
        .dx = values[4],
        .dy = values[5],
    };
}

fn translateTransform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    format: u8,
    context: Context,
) Error!model.Affine {
    const base = if (format == 15)
        try bin.readU32At(data, offset + 8)
    else
        variation.no_index;
    return .{
        .dx = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 4))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                0,
            ))),
        .dy = @as(f32, @floatFromInt(try bin.readI16At(data, offset + 6))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                1,
            ))),
    };
}

fn scaleTransform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    format: u8,
    context: Context,
) Error!model.Affine {
    const variable = (format & 1) != 0;
    const around_center =
        format == 18 or format == 19 or format == 22 or format == 23;
    const uniform = format >= 20;
    const base = if (variable)
        try bin.readU32At(data, offset + paint.formatInfo(format).?.min_size - 4)
    else
        variation.no_index;
    const scale_x = f2dot14(try bin.readI16At(data, offset + 4)) +
        @as(f32, @floatCast((try delta(
            data,
            table,
            context,
            base,
            0,
        )) / 16384.0));
    const scale_y = if (uniform)
        scale_x
    else
        f2dot14(try bin.readI16At(data, offset + 6)) +
            @as(f32, @floatCast((try delta(
                data,
                table,
                context,
                base,
                1,
            )) / 16384.0));
    const center_delta: usize = if (uniform) 1 else 2;
    const center_offset: usize = if (uniform) 6 else 8;
    const center_x = if (around_center)
        @as(f32, @floatFromInt(try bin.readI16At(data, offset + center_offset))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                center_delta,
            )))
    else
        0;
    const center_y = if (around_center)
        @as(
            f32,
            @floatFromInt(try bin.readI16At(data, offset + center_offset + 2)),
        ) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                center_delta + 1,
            )))
    else
        0;
    return .{
        .xx = scale_x,
        .yy = scale_y,
        .dx = center_x - scale_x * center_x,
        .dy = center_y - scale_y * center_y,
    };
}

fn rotateTransform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    format: u8,
    context: Context,
) Error!model.Affine {
    const variable = (format & 1) != 0;
    const around_center = format >= 26;
    const base = if (variable)
        try bin.readU32At(data, offset + paint.formatInfo(format).?.min_size - 4)
    else
        variation.no_index;
    const angle = f2dot14(try bin.readI16At(data, offset + 4)) +
        @as(f32, @floatCast((try delta(
            data,
            table,
            context,
            base,
            0,
        )) / 16384.0));
    const center_x = if (around_center)
        @as(f32, @floatFromInt(try bin.readI16At(data, offset + 6))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                1,
            )))
    else
        0;
    const center_y = if (around_center)
        @as(f32, @floatFromInt(try bin.readI16At(data, offset + 8))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                2,
            )))
    else
        0;
    const radians = angle * std.math.pi;
    const sine = @sin(radians);
    const cosine = @cos(radians);
    return .{
        .xx = cosine,
        .yx = sine,
        .xy = -sine,
        .yy = cosine,
        .dx = sine * center_y + (1.0 - cosine) * center_x,
        .dy = -sine * center_x + (1.0 - cosine) * center_y,
    };
}

fn skewTransform(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    format: u8,
    context: Context,
) Error!model.Affine {
    const variable = (format & 1) != 0;
    const around_center = format >= 30;
    const base = if (variable)
        try bin.readU32At(data, offset + paint.formatInfo(format).?.min_size - 4)
    else
        variation.no_index;
    const x_angle = f2dot14(try bin.readI16At(data, offset + 4)) +
        @as(f32, @floatCast((try delta(
            data,
            table,
            context,
            base,
            0,
        )) / 16384.0));
    const y_angle = f2dot14(try bin.readI16At(data, offset + 6)) +
        @as(f32, @floatCast((try delta(
            data,
            table,
            context,
            base,
            1,
        )) / 16384.0));
    const center_x = if (around_center)
        @as(f32, @floatFromInt(try bin.readI16At(data, offset + 8))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                2,
            )))
    else
        0;
    const center_y = if (around_center)
        @as(f32, @floatFromInt(try bin.readI16At(data, offset + 10))) +
            @as(f32, @floatCast(try delta(
                data,
                table,
                context,
                base,
                3,
            )))
    else
        0;
    const tan_x = @tan(x_angle * std.math.pi);
    const tan_y = @tan(y_angle * std.math.pi);
    return .{
        .xy = -tan_x,
        .yx = tan_y,
        .dx = tan_x * center_y,
        .dy = -tan_y * center_x,
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

fn fixed16_16(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}

test "static translate decodes as an affine transform" {
    var bytes: [16]u8 = .{0} ** 16;
    bytes[0] = 14;
    writeU24(&bytes, 1, 8);
    writeI16(&bytes, 4, 40);
    writeI16(&bytes, 6, -20);
    bytes[8] = 2;
    writeI16(&bytes, 11, 0x4000);

    const result = try transform(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        0,
        .{ .normalized_coords = &.{}, .variation = null },
    );
    try std.testing.expectEqual(@as(usize, 8), result.child.offset);
    try std.testing.expectEqual(@as(f32, 40), result.affine.dx);
    try std.testing.expectEqual(@as(f32, -20), result.affine.dy);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}
