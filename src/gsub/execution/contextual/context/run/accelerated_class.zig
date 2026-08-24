//! Accelerator-backed ContextSubst class lookup dispatch.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const accelerated = @import("../class/accelerated.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Lookup = accelerator.Lookup;
const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    lookup_accelerator: *const Lookup,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;
        const first = glyphs.items[position];
        var subtable_index: usize = 0;
        while (subtable_index < subtable_count and
            subtable_index <
                lookup_accelerator.context_class_subtables.len) : (subtable_index += 1)
        {
            const accelerated_subtable =
                lookup_accelerator.context_class_subtables[subtable_index];
            if (accelerated_subtable.rules.len == 0) continue;
            // The selected group is also the matcher's first operation. Probe
            // once here and lend the result across that API boundary.
            const group = accelerator.index.class_first.findPrepared(
                accelerated_subtable.classes,
                accelerated_subtable.first_index_start,
                accelerated_subtable.groups,
                first,
            ) orelse continue;
            // Most glyphs are absent from the exact first-glyph index. Probe
            // it before the more expensive source-scope and LookupFlag tests.
            if (!filtering.lookupCursorAllowsGlyph(run, position) or
                filtering.lookupIgnoresGlyph(lookup_flag, run, first))
            {
                break;
            }
            const result = try accelerated.applyGroup(
                Executor,
                view,
                accelerated_subtable,
                group,
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
