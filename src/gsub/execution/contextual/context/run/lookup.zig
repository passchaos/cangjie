//! Position-major direct and ExtensionSubst ContextSubst lookup dispatch.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;

const Kind = enum { direct, extension };

pub fn apply(
    comptime Dispatcher: type,
    comptime Executor: type,
    comptime kind: Kind,
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
        if (!filtering.lookupCursorAllowsGlyph(run, position) or
            filtering.lookupIgnoresGlyph(
                lookup_flag,
                run,
                glyphs.items[position],
            ))
        {
            continue;
        }
        for (0..subtable_count) |subtable_index| {
            const child = lookup_offset + try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            );
            const subtable_offset = switch (kind) {
                .direct => child,
                .extension => try accelerator.build.lookup.extension.payload(
                    view,
                    child,
                    5,
                ),
            };
            const result = try Dispatcher.at(
                Executor,
                view,
                subtable_offset,
                glyphs,
                position,
                allocator,
                lookup_flag,
                run,
            );
            if (!result.matched) continue;
            next_position = @max(next_position, result.next_pos);
            break;
        }
    }
}
