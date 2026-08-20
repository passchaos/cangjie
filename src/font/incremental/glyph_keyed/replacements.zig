//! First-wins merge of glyph replacement data across a patch group.

const std = @import("std");
const payload = @import("payload.zig");

pub fn collect(
    allocator: std.mem.Allocator,
    patches: []const payload.View,
    tag: [4]u8,
    glyph_count: usize,
) ![]?[]const u8 {
    const result = try allocator.alloc(?[]const u8, glyph_count);
    errdefer allocator.free(result);
    @memset(result, null);

    for (patches) |view| {
        const table_index = findTable(view, tag) orelse continue;
        for (0..view.glyph_count) |glyph_index| {
            const glyph_id: usize = try view.glyphId(glyph_index);
            if (glyph_id >= glyph_count) return error.BadSfnt;
            // The IFT specification permits any application order within a
            // glyph-keyed patch group. Matching Fontations, the caller's first
            // patch wins when two supplied patches replace the same key.
            if (result[glyph_id] == null) {
                result[glyph_id] = try view.glyphData(table_index, glyph_index);
            }
        }
    }
    return result;
}

fn findTable(view: payload.View, tag: [4]u8) ?usize {
    for (0..view.table_count) |index| {
        const candidate = view.tableTag(index) catch return null;
        if (std.mem.eql(u8, &candidate, &tag)) return index;
    }
    return null;
}
