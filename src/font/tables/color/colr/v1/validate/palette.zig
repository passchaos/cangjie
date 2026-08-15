//! COLR v1 Paint-graph validation for CPAL palette references.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const bases = @import("../bases.zig");
const layers = @import("../layers.zig");
const paint = @import("../paint/root.zig");
const types = @import("../types.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    palette_entries: ?u16,
) types.Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 34 or
        try bin.readU16At(data, table.offset) != 1)
    {
        return error.BadSfnt;
    }

    if (try bases.read(data, table)) |base_list| {
        for (0..base_list.record_count) |index| {
            var guard = paint.Guard{};
            try validateGraph(
                data,
                table,
                palette_entries,
                try bases.paintOffsetAt(data, table, base_list, index),
                &guard,
            );
        }
    }

    const layer_table = layers.Table{
        .offset = table.offset,
        .length = table.length,
    };
    if (try layers.read(data, layer_table)) |layer_list| {
        for (0..layer_list.layer_count) |index| {
            var guard = paint.Guard{};
            try validateGraph(
                data,
                table,
                palette_entries,
                try layers.paintOffset(
                    data,
                    layer_table,
                    layer_list,
                    @intCast(index),
                ),
                &guard,
            );
        }
    }
}

pub fn validateIndex(
    palette_index: u16,
    palette_entries: ?u16,
) types.Error!void {
    // 0xFFFF selects the application foreground/currentColor and therefore
    // deliberately has no corresponding CPAL color record.
    if (palette_index == 0xffff) return;
    const entries = palette_entries orelse return error.BadSfnt;
    if (palette_index >= entries) return error.BadSfnt;
}

fn validateGraph(
    data: []const u8,
    table: types.Table,
    palette_entries: ?u16,
    offset: usize,
    guard: *paint.Guard,
) types.Error!void {
    const paint_table = paint.Table{
        .offset = table.offset,
        .length = table.length,
    };
    const info = try paint.validateRecord(data, paint_table, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, paint_table, offset, info);

    switch (info.kind) {
        .colr_layers => {
            const layer_count = data[offset + 1];
            if (layer_count == 0) return;
            const first_layer_index = try bin.readU32At(data, offset + 2);
            const layer_table = layers.Table{
                .offset = table.offset,
                .length = table.length,
            };
            const layer_list =
                (try layers.read(data, layer_table)) orelse
                return error.BadSfnt;
            const first: usize = @intCast(first_layer_index);
            if (first > layer_list.layer_count or
                @as(usize, layer_count) > layer_list.layer_count - first)
            {
                return error.BadSfnt;
            }
            for (0..layer_count) |layer_offset| {
                try validateGraph(
                    data,
                    table,
                    palette_entries,
                    try layers.paintOffset(
                        data,
                        layer_table,
                        layer_list,
                        first_layer_index + @as(u32, @intCast(layer_offset)),
                    ),
                    guard,
                );
            }
        },
        .solid => try validateIndex(
            try bin.readU16At(data, offset + 1),
            palette_entries,
        ),
        .glyph, .single_child => try validateGraph(
            data,
            table,
            palette_entries,
            try paint.childOffset(
                data,
                paint_table,
                offset,
                info.min_size,
                1,
            ),
            guard,
        ),
        .color_line => try validateColorLine(
            data,
            paint_table,
            palette_entries,
            offset,
            info.min_size,
        ),
        .composite => {
            try validateGraph(
                data,
                table,
                palette_entries,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    1,
                ),
                guard,
            );
            try validateGraph(
                data,
                table,
                palette_entries,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    5,
                ),
                guard,
            );
        },
        .colr_glyph, .terminal => return,
    }
}

fn validateColorLine(
    data: []const u8,
    table: paint.Table,
    palette_entries: ?u16,
    offset: usize,
    paint_header_size: usize,
) types.Error!void {
    const variable = paint.usesVariableColorLine(data[offset]);
    const color_line = try paint.colorLineRange(
        data,
        table,
        offset,
        paint_header_size,
        variable,
    );
    const stop_count: usize =
        @intCast(try bin.readU16At(data, color_line.start + 1));
    const stops_start = color_line.start + 3;
    const stop_size = paint.colorStopSize(variable);
    for (0..stop_count) |index| {
        try validateIndex(
            try bin.readU16At(
                data,
                stops_start + index * stop_size + 2,
            ),
            palette_entries,
        );
    }
}

test "palette validation covers base and layer Paint roots" {
    var bytes: [80]u8 = .{0} ** 80;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 18, 49);

    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 10);
    bytes[44] = 2;
    writeU16(&bytes, 45, 0);
    writeI16(&bytes, 47, 0x4000);

    writeU32(&bytes, 49, 1);
    writeU32(&bytes, 53, 8);
    bytes[57] = 2;
    writeU16(&bytes, 58, 1);
    writeI16(&bytes, 60, 0x4000);

    const table = types.Table{ .offset = 0, .length = bytes.len };
    try validate(&bytes, table, 2);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 1));

    writeU16(&bytes, 58, 0xffff);
    try validate(&bytes, table, 1);
}

test "palette validation follows ColorLine and nested Paint graphs" {
    var bytes: [96]u8 = .{0} ** 96;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 10);

    bytes[44] = 10;
    writeU24(&bytes, 45, 6);
    writeU16(&bytes, 48, 1);
    bytes[50] = 5;
    writeU24(&bytes, 51, 20);
    const color_line = 70;
    bytes[color_line] = 0;
    writeU16(&bytes, color_line + 1, 2);
    writeI16(&bytes, color_line + 3, 0);
    writeU16(&bytes, color_line + 5, 0);
    writeI16(&bytes, color_line + 7, 0x4000);
    writeU32(&bytes, color_line + 9, 0);
    writeI16(&bytes, color_line + 13, 0x4000);
    writeU16(&bytes, color_line + 15, 2);
    writeI16(&bytes, color_line + 17, 0x4000);
    writeU32(&bytes, color_line + 19, 0);

    const table = types.Table{ .offset = 0, .length = bytes.len };
    try validate(&bytes, table, 3);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 2));
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

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
