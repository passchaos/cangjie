//! Accelerator-backed ContextSubst format-3 lookup execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const matched = @import("matched.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Lookup = accelerator.Lookup;
const max_input_glyphs = accelerator.model.max_context_region_glyphs;
const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    lookup: *const Lookup,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;
        const first = glyphs.items[position];
        const candidates = if (run.match_source_syllable) scoped: {
            // Syllable-scoped Indic stages pay source metadata costs at every
            // cursor. Reject their overwhelmingly common exact-index misses
            // first, while leaving ordinary unscoped scripts on the existing
            // filtering-first layout.
            const indexed = try candidateSubtables(lookup, first) orelse
                continue;
            if (!filtering.lookupCursorAllowsGlyph(run, position) or
                filtering.lookupIgnoresGlyph(lookup_flag, run, first))
            {
                continue;
            }
            break :scoped indexed;
        } else unscoped: {
            if (!filtering.lookupCursorAllowsGlyph(run, position) or
                filtering.lookupIgnoresGlyph(lookup_flag, run, first))
            {
                continue;
            }
            break :unscoped try candidateSubtables(lookup, first) orelse
                continue;
        };
        for (candidates) |subtable_index| {
            if (subtable_index >= lookup.context_coverage_subtables.len) {
                return error.BadGsub;
            }
            const subtable =
                lookup.context_coverage_subtables[subtable_index];
            if (subtable.glyph_count == 0 or
                subtable.coverage_start >
                    lookup.context_coverage_offsets.len or
                subtable.glyph_count >
                    lookup.context_coverage_offsets.len -
                        subtable.coverage_start)
            {
                return error.BadGsub;
            }
            var input_indices: [max_input_glyphs]usize = undefined;
            if (!traversal.collectForward(
                glyphs.items,
                position,
                lookup_flag,
                run,
                input_indices[0..subtable.glyph_count],
                false,
                position,
            )) continue;
            const offsets = lookup.context_coverage_offsets[subtable.coverage_start .. subtable.coverage_start + subtable.glyph_count];
            var contexts_match = true;
            // Candidate grouping already proved the first coverage.
            for (offsets[1..], 1..) |coverage_offset, input_index| {
                if (try table.coverage.index(
                    view,
                    coverage_offset,
                    glyphs.items[input_indices[input_index]],
                ) == null) {
                    contexts_match = false;
                    break;
                }
            }
            if (!contexts_match) continue;

            const result = try matched.apply(
                Executor,
                view,
                glyphs,
                position,
                input_indices[0..subtable.glyph_count],
                subtable.records_pos,
                subtable.subst_count,
                allocator,
                run,
            );
            next_position = @max(next_position, result.next_pos);
            break;
        }
    }
}

fn candidateSubtables(
    lookup: *const Lookup,
    first: GlyphId,
) error{BadGsub}!?[]const u16 {
    if (lookup.context_group_slots.len != 0) {
        if (first >= lookup.context_group_slots.len) return null;
        const slot = lookup.context_group_slots[first];
        if (slot == 0) return null;
        const group_index = @as(usize, slot) - 1;
        if (group_index >= lookup.context_groups.len) return error.BadGsub;
        const group = lookup.context_groups[group_index];
        if (group.glyph != first) return error.BadGsub;
        return group.subtable_indices;
    }
    return accelerator.index.chaining.findIndices(
        lookup.context_groups,
        &.{},
        first,
    );
}
