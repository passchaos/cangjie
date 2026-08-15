//! Validation of COLR v1 varIndex sequences throughout the Paint graph.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const variation_common =
    @import("../../../../../../opentype/variation/root.zig");
const delta_map = variation_common.delta_set_index_map;
const item_store = variation_common.item_store;
const bases = @import("../bases.zig");
const clip = @import("../clip.zig");
const layers = @import("../layers.zig");
const paint = @import("../paint/root.zig");
const types = @import("../types.zig");
const runtime = @import("runtime.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
    context: ?*const runtime.Context,
) types.Error!void {
    try validateClipList(data, table, glyph_count, context);
    if (try bases.read(data, table)) |base_list| {
        for (0..base_list.record_count) |index| {
            var guard = paint.Guard{};
            try validateGraph(
                data,
                table,
                try bases.paintOffsetAt(data, table, base_list, index),
                context,
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
                try layers.paintOffset(
                    data,
                    layer_table,
                    layer_list,
                    @intCast(index),
                ),
                context,
                &guard,
            );
        }
    }
}

fn validateSequence(
    data: []const u8,
    table: types.Table,
    context: ?*const runtime.Context,
    var_index_base: u32,
    count: usize,
) types.Error!void {
    if (count == 0 or var_index_base == runtime.no_index) return;
    const ctx = context orelse return error.BadSfnt;
    if (@as(usize, var_index_base) >
        std.math.maxInt(u32) - (count - 1))
    {
        return error.BadSfnt;
    }

    for (0..count) |sequence_index| {
        const logical = @as(usize, var_index_base) + sequence_index;
        const mapped = if (ctx.map) |map|
            try delta_map.mappedIndex(data, map, logical)
        else blk: {
            if (logical > std.math.maxInt(u16)) return error.BadSfnt;
            break :blk delta_map.Index{
                .outer = 0,
                .inner = logical,
            };
        };
        if (mapped.outer == 0xffff and mapped.inner == 0xffff) continue;
        if (mapped.outer >= ctx.item_data_count) return error.BadSfnt;
        if (mapped.inner >= try item_store.itemCount(
            data,
            .{ .offset = table.offset, .length = table.length },
            ctx.store_offset,
            mapped.outer,
        )) {
            return error.BadSfnt;
        }
    }
}

fn validateClipList(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
    context: ?*const runtime.Context,
) types.Error!void {
    const list = (try clip.validate(data, table, glyph_count)) orelse return;
    for (0..list.count) |index| {
        const box = try clip.boxAtIndex(data, table, list, index);
        try validateSequence(
            data,
            table,
            context,
            box.var_index_base orelse continue,
            4,
        );
    }
}

fn validateGraph(
    data: []const u8,
    table: types.Table,
    offset: usize,
    context: ?*const runtime.Context,
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
                    try layers.paintOffset(
                        data,
                        layer_table,
                        layer_list,
                        first_layer_index + @as(u32, @intCast(layer_offset)),
                    ),
                    context,
                    guard,
                );
            }
        },
        .solid => if (data[offset] == 3) {
            try validateSequence(
                data,
                table,
                context,
                try bin.readU32At(data, offset + 5),
                1,
            );
        },
        .glyph, .single_child => {
            try validateTransform(data, table, offset, info, context);
            try validateGraph(
                data,
                table,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    1,
                ),
                context,
                guard,
            );
        },
        .composite => {
            try validateGraph(
                data,
                table,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    1,
                ),
                context,
                guard,
            );
            try validateGraph(
                data,
                table,
                try paint.childOffset(
                    data,
                    paint_table,
                    offset,
                    info.min_size,
                    5,
                ),
                context,
                guard,
            );
        },
        .color_line => try validateGradient(
            data,
            table,
            offset,
            info,
            context,
        ),
        .colr_glyph, .terminal => return,
    }
}

fn validateTransform(
    data: []const u8,
    table: types.Table,
    offset: usize,
    info: paint.FormatInfo,
    context: ?*const runtime.Context,
) types.Error!void {
    const count = transformItemCount(data[offset]) orelse return;
    const var_index_offset = if (data[offset] == 13)
        (try paint.transformPayloadRange(
            data,
            .{ .offset = table.offset, .length = table.length },
            offset,
            info.min_size,
        )).end - 4
    else
        offset + info.min_size - 4;
    try validateSequence(
        data,
        table,
        context,
        try bin.readU32At(data, var_index_offset),
        count,
    );
}

fn transformItemCount(format: u8) ?usize {
    return switch (format) {
        13 => 6,
        15, 17, 29 => 2,
        19, 31 => 4,
        21, 25 => 1,
        23, 27 => 3,
        else => null,
    };
}

fn validateGradient(
    data: []const u8,
    table: types.Table,
    offset: usize,
    info: paint.FormatInfo,
    context: ?*const runtime.Context,
) types.Error!void {
    const count: usize = switch (data[offset]) {
        5, 7 => 6,
        9 => 4,
        else => return,
    };
    try validateSequence(
        data,
        table,
        context,
        try bin.readU32At(data, offset + info.min_size - 4),
        count,
    );

    const color_line = try paint.childOffset(
        data,
        .{ .offset = table.offset, .length = table.length },
        offset,
        info.min_size,
        1,
    );
    const stop_count: usize =
        @intCast(try bin.readU16At(data, color_line + 1));
    for (0..stop_count) |index| {
        try validateSequence(
            data,
            table,
            context,
            try bin.readU32At(
                data,
                color_line + 3 + index * paint.colorStopSize(true) + 6,
            ),
            2,
        );
    }
}
