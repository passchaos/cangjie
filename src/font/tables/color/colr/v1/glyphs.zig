//! COLR v1 glyph-reference validation across Paint and clip graphs.

const std = @import("std");

const bin = @import("../../../../../binary.zig");
const bases = @import("bases.zig");
const clip = @import("clip.zig");
const glyph = @import("../../../../../glyph.zig");
const layers = @import("layers.zig");
const paint = @import("paint/root.zig");
const types = @import("types.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
) types.Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 34 or
        try bin.readU16At(data, table.offset) != 1)
    {
        return error.BadSfnt;
    }
    _ = try clip.validate(data, table, glyph_count);

    const base_list = try bases.read(data, table);
    if (base_list) |list| {
        for (0..list.record_count) |index| {
            const record = try bases.recordAt(data, table, list, index);
            try validateGlyphId(record.glyph_id, glyph_count);
            var guard = paint.Guard{};
            try validateGraph(
                data,
                table,
                glyph_count,
                base_list,
                record.paint_offset,
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
                glyph_count,
                base_list,
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

fn validateGraph(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
    base_list: ?bases.List,
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
                    glyph_count,
                    base_list,
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
        .glyph => {
            try validateGlyphId(
                try bin.readU16At(data, offset + 4),
                glyph_count,
            );
            try validateGraph(
                data,
                table,
                glyph_count,
                base_list,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    1,
                ),
                guard,
            );
        },
        .colr_glyph => {
            const referenced_glyph = try bin.readU16At(data, offset + 1);
            try validateGlyphId(referenced_glyph, glyph_count);
            const list = base_list orelse return error.BadSfnt;
            _ = (try bases.paintOffsetForGlyph(
                data,
                table,
                list,
                referenced_glyph,
            )) orelse return error.BadSfnt;
            // Cross-glyph recursion is a traversal concern: rejecting a cycle
            // while parsing would make unrelated valid color glyphs unusable.
            // The renderer's lazy traversal owns that glyph stack. Here we
            // prove only that the referenced BaseGlyphPaintRecord exists.
        },
        .single_child => try validateGraph(
            data,
            table,
            glyph_count,
            base_list,
            try paint.childOffset(
                data,
                paint_table,
                offset,
                info.min_size,
                1,
            ),
            guard,
        ),
        .composite => {
            try validateGraph(
                data,
                table,
                glyph_count,
                base_list,
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
                glyph_count,
                base_list,
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
        .solid, .color_line, .terminal => return,
    }
}

fn validateGlyphId(
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

test "glyph validation covers PaintGlyph and declared PaintColrGlyph targets" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 2);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 16);
    writeU16(&bytes, 44, 2);
    writeU32(&bytes, 46, 25);

    bytes[50] = 10;
    writeU24(&bytes, 51, 6);
    writeU16(&bytes, 54, 3);
    bytes[56] = 11;
    writeU16(&bytes, 57, 2);
    bytes[59] = 2;
    writeI16(&bytes, 62, 0x4000);

    const table = types.Table{ .offset = 0, .length = bytes.len };
    try validate(&bytes, table, 4);

    writeU16(&bytes, 54, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 54, 3);

    writeU16(&bytes, 57, 3);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 57, 1);
    // A self-edge remains structurally valid; lazy traversal rejects it only
    // when that glyph is actually rendered.
    try validate(&bytes, table, 4);
}

test "glyph validation covers LayerList Paints and ClipList ranges" {
    var bytes: [80]u8 = .{0} ** 80;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 18, 34);
    writeU32(&bytes, 22, 53);

    writeU32(&bytes, 34, 1);
    writeU32(&bytes, 38, 8);
    bytes[42] = 10;
    writeU24(&bytes, 43, 6);
    writeU16(&bytes, 46, 1);
    bytes[48] = 2;
    writeI16(&bytes, 51, 0x4000);

    bytes[53] = 1;
    writeU32(&bytes, 54, 1);
    writeU16(&bytes, 58, 2);
    writeU16(&bytes, 60, 3);
    writeU24(&bytes, 62, 12);
    bytes[65] = 1;
    writeI16(&bytes, 66, 0);
    writeI16(&bytes, 68, 0);
    writeI16(&bytes, 70, 10);
    writeI16(&bytes, 72, 10);

    const table = types.Table{ .offset = 0, .length = 74 };
    try validate(&bytes, table, 4);

    writeU16(&bytes, 46, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 46, 1);

    writeU16(&bytes, 60, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
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
