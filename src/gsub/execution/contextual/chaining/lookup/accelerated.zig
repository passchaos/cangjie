//! Indexed position-major ChainContextSubst lookup execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const chaining_coverage = @import("../coverage/root.zig");
const extension_payload =
    @import("../../../../accelerator/build/lookup/extension.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const options = @import("../../../../runtime/options.zig");
const table = @import("../../../../table/root.zig");
const target = @import("target.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const Error = target.Error;
pub const Lookup = accelerator.Lookup;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    sidecar: *const Lookup,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;

        const current = glyphs.items[position];
        // The union digest is a permissive first-input proof. Exact group and
        // pair indexes below preserve authored subtable order.
        if (!sidecar.chaining_input_digest.mayHave(current)) continue;
        if (!filtering.sourceFeatureAllowsGlyph(run, position)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, current)) continue;

        const group = accelerator.index.chaining.find(
            sidecar.chaining_groups,
            sidecar.chaining_group_slots,
            current,
        ) orelse continue;
        const second_index = if (sidecar.chaining_needs_second_input)
            traversal.nextIndex(
                glyphs.items,
                position + 1,
                lookup_flag,
                run,
                false,
                position,
            )
        else
            null;
        const second = if (second_index) |index| glyphs.items[index] else null;
        if (!group.has_no_second_input and
            !group.second_input_digest.isEmpty())
        {
            const glyph = second orelse continue;
            if (!group.second_input_digest.mayHave(glyph)) continue;
        }

        const candidates =
            if (sidecar.chaining_pair_index_complete and
            !group.has_no_second_input) pair: {
                const glyph = second orelse continue;
                break :pair accelerator.index.chaining.findPairIndices(
                    sidecar.chaining_pair_groups,
                    sidecar.chaining_pair_group_slots,
                    current,
                    glyph,
                ) orelse continue;
            } else group.subtable_indices;
        const first_backtrack = if (sidecar.chaining_needs_backtrack)
            traversal.previousGlyph(
                glyphs.items,
                position,
                lookup_flag,
                run,
                true,
                position,
            )
        else
            null;
        const single_input_lookahead =
            if (sidecar.chaining_needs_single_input_lookahead)
                traversal.nextGlyph(
                    glyphs.items,
                    position + 1,
                    lookup_flag,
                    run,
                    true,
                    position,
                )
            else
                null;

        var third_index: ?usize = null;
        var third_resolved = false;
        for (candidates) |subtable_index| {
            const parsed =
                if (subtable_index < sidecar.chaining_subtables.len and
                sidecar.chaining_subtables[subtable_index]
                    .input_count != 0)
                    sidecar.chaining_subtables[subtable_index]
                else
                    null;
            if (parsed) |subtable| {
                if (subtable.input_count > 1) {
                    const glyph = second orelse continue;
                    if (!subtable.second_input_digest.mayHave(glyph)) continue;
                }
                if (subtable.input_count > 2) {
                    if (!third_resolved) {
                        third_index = if (second_index) |index|
                            traversal.nextIndex(
                                glyphs.items,
                                index + 1,
                                lookup_flag,
                                run,
                                false,
                                position,
                            )
                        else
                            null;
                        third_resolved = true;
                    }
                    const index = third_index orelse continue;
                    if (!subtable.third_input_digest.mayHave(
                        glyphs.items[index],
                    )) continue;
                }
                if (subtable.backtrack_count != 0) {
                    const glyph = first_backtrack orelse continue;
                    if (!subtable.first_backtrack_digest.mayHave(glyph)) {
                        continue;
                    }
                }
                if (subtable.input_count == 1 and
                    subtable.lookahead_count != 0)
                {
                    const glyph = single_input_lookahead orelse continue;
                    if (!subtable.first_lookahead_digest.mayHave(glyph)) {
                        continue;
                    }
                }
                const result =
                    if (subtable.backtrack_count == 0 and
                    subtable.lookahead_count == 0 and
                    subtable.input_count <= 3)
                        try chaining_coverage.acceleratedNoContextAt(
                            Executor,
                            view,
                            subtable,
                            glyphs,
                            position,
                            second_index,
                            third_index,
                            allocator,
                            run,
                        )
                    else
                        try chaining_coverage.acceleratedAt(
                            Executor,
                            view,
                            subtable,
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
                continue;
            }

            const wrapper_or_subtable =
                lookup_offset + try view.readU16(
                    lookup_offset + 6 +
                        @as(usize, subtable_index) * 2,
                );
            const subtable_offset =
                if (sidecar.extension_lookup_type == 6)
                    try extension_payload.payload(
                        view,
                        wrapper_or_subtable,
                        6,
                    )
                else
                    wrapper_or_subtable;
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
