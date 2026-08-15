//! COLR v1 variation runtime and semantic validation.

const bin = @import("../../../../../../binary.zig");
const variation_common =
    @import("../../../../../../opentype/variation/root.zig");
const ownership = @import("ownership.zig");
const references = @import("references.zig");
const runtime = @import("runtime.zig");
const types = @import("../types.zig");

const delta_map = variation_common.delta_set_index_map;
const item_store = variation_common.item_store;

pub const Context = runtime.Context;
pub const no_index = runtime.no_index;
pub const read = runtime.read;
pub const delta = runtime.delta;

pub fn validate(
    data: []const u8,
    table: types.Table,
    axis_count: ?usize,
    glyph_count: u16,
) types.Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset or
        table.length < 2)
    {
        return error.BadSfnt;
    }
    if (try bin.readU16At(data, table.offset) != 1) return;
    if (table.length < 34) return error.BadSfnt;

    const map_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 26));
    const store_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 30));
    if (map_offset != 0 and store_offset == 0) return error.BadSfnt;

    var context_storage: runtime.Context = undefined;
    const context: ?*const runtime.Context = if (store_offset != 0) blk: {
        const store = try item_store.validate(
            data,
            .{ .offset = table.offset, .length = table.length },
            store_offset,
            axis_count orelse return error.BadSfnt,
            34,
        );
        try ownership.validate(
            data,
            table,
            .{ .start = store_offset, .end = store.end_offset },
        );

        const map = if (map_offset != 0) blk_map: {
            const parsed = try delta_map.read(
                data,
                .{ .offset = table.offset, .length = table.length },
                map_offset,
                34,
            );
            for (0..parsed.map_count) |index| {
                const mapped = try delta_map.entry(data, parsed, index);
                if (mapped.outer == 0xffff and mapped.inner == 0xffff) {
                    continue;
                }
                try validateReference(data, table, store, store_offset, mapped);
            }
            if (map_offset < store.end_offset and
                store_offset < parsed.end_offset)
            {
                return error.BadSfnt;
            }
            try ownership.validate(
                data,
                table,
                .{ .start = parsed.offset, .end = parsed.end_offset },
            );
            break :blk_map parsed;
        } else null;

        context_storage = .{
            .store_offset = store_offset,
            .item_data_count = store.item_data_count,
            .map = map,
        };
        break :blk &context_storage;
    } else null;

    try references.validate(data, table, glyph_count, context);
}

fn validateReference(
    data: []const u8,
    table: types.Table,
    store: item_store.Info,
    store_offset: usize,
    mapped: delta_map.Index,
) types.Error!void {
    if (mapped.outer >= store.item_data_count) return error.BadSfnt;
    if (mapped.inner >= try item_store.itemCount(
        data,
        .{ .offset = table.offset, .length = table.length },
        store_offset,
        mapped.outer,
    )) {
        return error.BadSfnt;
    }
}
