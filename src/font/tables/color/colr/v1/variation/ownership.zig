//! Ownership separation between COLR variation tables and Paint payloads.

const bin = @import("../../../../../../binary.zig");
const bases = @import("../bases.zig");
const clip = @import("../clip.zig");
const directories = @import("../directories.zig");
const layers = @import("../layers.zig");
const paint = @import("../paint/root.zig");
const types = @import("../types.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    if (try bases.read(data, table)) |base_list| {
        if (directories.overlaps(
            variation_range,
            bases.range(table, base_list),
        )) {
            return error.BadSfnt;
        }
    }

    const layer_list_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 18));
    if (layer_list_offset != 0) {
        const structural_range = try directories.layerListRange(
            data,
            table,
            layer_list_offset,
        );
        if (directories.overlaps(variation_range, structural_range)) {
            return error.BadSfnt;
        }
    }

    const clip_list_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 22));
    if (clip_list_offset != 0) {
        const structural_range = try directories.clipListRange(
            data,
            table,
            clip_list_offset,
        );
        if (directories.overlaps(variation_range, structural_range)) {
            return error.BadSfnt;
        }
    }

    try validateClipBoxes(data, table, variation_range);
    try validatePaintPayloads(data, table, variation_range);
}

fn validateClipBoxes(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    const list = (try clip.directory(data, table)) orelse return;
    for (0..list.count) |index| {
        const clip_box_range =
            (try clip.boxAtIndex(data, table, list, index)).range;
        if (directories.overlaps(variation_range, clip_box_range)) {
            return error.BadSfnt;
        }
    }
}

fn validatePaintPayloads(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    const forbidden = paint.Range{
        .start = table.offset + variation_range.start,
        .end = table.offset + variation_range.end,
    };
    if (try bases.read(data, table)) |base_list| {
        for (0..base_list.record_count) |index| {
            var guard = paint.Guard{ .forbidden_range = forbidden };
            try validateGraph(
                data,
                table,
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
            var guard = paint.Guard{ .forbidden_range = forbidden };
            try validateGraph(
                data,
                table,
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
        .glyph, .single_child => try validateGraph(
            data,
            table,
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
        .solid, .color_line, .colr_glyph, .terminal => return,
    }
}
