//! Position-major execution for unindexed ChainContextSubst lookups.

const std = @import("std");
const options = @import("../../../../runtime/options.zig");
const table = @import("../../../../table/root.zig");
const target = @import("target.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const Error = target.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;
        for (0..subtable_count) |subtable_index| {
            const subtable_offset = lookup_offset + try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            );
            const result = try target.apply(
                Executor,
                view,
                subtable_offset,
                null,
                glyphs,
                position,
                allocator,
                lookup_flag,
                run,
            );
            if (result.matched) {
                next_position = @max(next_position, result.next_pos);
                break;
            }
        }
    }
}
