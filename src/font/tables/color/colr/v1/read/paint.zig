//! Runtime decoding for COLR v1 Paint records.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const model = @import("../../../model.zig");
const paint_grammar = @import("../paint/root.zig");
const table_types = @import("../types.zig");
const gradients = @import("gradients.zig");
const transforms = @import("transforms.zig");
const Context = @import("types.zig").Context;
const variation = @import("../variation/root.zig");

pub const Error = variation.Error || error{UnsupportedGlyph};

pub fn read(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint {
    const table_end = table.offset + table.length;
    if (table.offset > data.len or
        table.length > data.len - table.offset or
        offset < table.offset or
        offset >= table_end)
    {
        return error.BadSfnt;
    }
    const info = try paint_grammar.validateRecord(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
    );
    const format = data[offset];
    return switch (format) {
        1 => .{ .layers = .{
            .layer_count = data[offset + 1],
            .first_layer_index = try bin.readU32At(data, offset + 2),
        } },
        2, 3 => .{ .solid = .{
            .palette_index = try bin.readU16At(data, offset + 1),
            .alpha = f2dot14(try bin.readI16At(data, offset + 3)) +
                @as(f32, @floatCast((try delta(
                    data,
                    table,
                    context,
                    if (format == 3)
                        try bin.readU32At(data, offset + 5)
                    else
                        variation.no_index,
                    0,
                )) / 16384.0)),
        } },
        4, 5 => .{ .linear_gradient = try gradients.linearGradient(
            data,
            table,
            offset,
            context,
        ) },
        6, 7 => .{ .radial_gradient = try gradients.radialGradient(
            data,
            table,
            offset,
            context,
        ) },
        8, 9 => .{ .sweep_gradient = try gradients.sweepGradient(
            data,
            table,
            offset,
            context,
        ) },
        10 => try glyphPaint(data, table, offset, context),
        11 => .{ .colr_glyph = .{
            .glyph_id = try bin.readU16At(data, offset + 1),
        } },
        12...31 => .{ .transform = try transforms.transform(
            data,
            table,
            offset,
            context,
        ) },
        32 => .{ .composite = .{
            .source = .{ .offset = try paint_grammar.childOffset(
                data,
                .{ .offset = table.offset, .length = table.length },
                offset,
                info.min_size,
                1,
            ) },
            .mode = std.enums.fromInt(
                model.Paint.CompositeMode,
                data[offset + 4],
            ) orelse return error.BadSfnt,
            .backdrop = .{ .offset = try paint_grammar.childOffset(
                data,
                .{ .offset = table.offset, .length = table.length },
                offset,
                info.min_size,
                5,
            ) },
        } },
        else => error.UnsupportedGlyph,
    };
}

fn glyphPaint(
    data: []const u8,
    table: table_types.Table,
    offset: usize,
    context: Context,
) Error!model.Paint {
    const child_offset = try paint_grammar.childOffset(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        6,
        1,
    );
    const glyph_id = try bin.readU16At(data, offset + 4);
    const child = try read(data, table, child_offset, context);
    return switch (child) {
        .solid => |solid| .{ .glyph = .{
            .glyph_id = glyph_id,
            .brush = .{ .solid = solid },
        } },
        .linear_gradient => |gradient| .{ .glyph = .{
            .glyph_id = glyph_id,
            .brush = .{ .linear_gradient = gradient },
        } },
        .radial_gradient => |gradient| .{ .glyph = .{
            .glyph_id = glyph_id,
            .brush = .{ .radial_gradient = gradient },
        } },
        .sweep_gradient => |gradient| .{ .glyph = .{
            .glyph_id = glyph_id,
            .brush = .{ .sweep_gradient = gradient },
        } },
        else => .{ .clip_glyph = .{
            .glyph_id = glyph_id,
            .child = .{ .offset = child_offset },
        } },
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

test "PaintGlyph promotes brush children and clips structural children" {
    var bytes: [32]u8 = .{0} ** 32;
    bytes[0] = 10;
    writeU24(&bytes, 1, 6);
    writeU16(&bytes, 4, 7);
    bytes[6] = 2;
    writeU16(&bytes, 7, 3);
    writeI16(&bytes, 9, 0x4000);

    const table = table_types.Table{ .offset = 0, .length = bytes.len };
    const brush = try read(
        &bytes,
        table,
        0,
        .{ .normalized_coords = &.{}, .variation = null },
    );
    try std.testing.expectEqual(@as(u16, 7), brush.glyph.glyph_id);
    try std.testing.expectEqual(@as(u16, 3), brush.glyph.brush.solid.palette_index);

    bytes[6] = 11;
    writeU16(&bytes, 7, 9);
    const clipped = try read(
        &bytes,
        table,
        0,
        .{ .normalized_coords = &.{}, .variation = null },
    );
    try std.testing.expectEqual(@as(u16, 7), clipped.clip_glyph.glyph_id);
    try std.testing.expectEqual(@as(usize, 6), clipped.clip_glyph.child.offset);
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
