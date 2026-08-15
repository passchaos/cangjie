//! Validation of COLR v1 varIndex sequences throughout the Paint graph.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const variation_common =
    @import("../../../../../../opentype/variation/root.zig");
const delta_map = variation_common.delta_set_index_map;
const item_store = variation_common.item_store;
const clip = @import("../clip.zig");
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
    var visitor = Visitor{ .context = context };
    try paint.walkAll(data, table, &visitor);
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

const Visitor = struct {
    context: ?*const runtime.Context,

    pub fn visit(
        self: *const Visitor,
        data: []const u8,
        table: types.Table,
        offset: usize,
        info: paint.FormatInfo,
    ) types.Error!void {
        switch (info.kind) {
            .solid => if (data[offset] == 3) {
                try validateSequence(
                    data,
                    table,
                    self.context,
                    try bin.readU32At(data, offset + 5),
                    1,
                );
            },
            .single_child => try validateTransform(
                data,
                table,
                offset,
                info,
                self.context,
            ),
            .color_line => try validateGradient(
                data,
                table,
                offset,
                info,
                self.context,
            ),
            .terminal,
            .colr_layers,
            .glyph,
            .colr_glyph,
            .composite,
            => {},
        }
    }
};

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
