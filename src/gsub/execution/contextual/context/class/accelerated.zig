//! Accelerator-backed ContextSubst format-1/2 rule execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const class_context = @import("../../../../../opentype/class_context.zig");
const table = @import("../../../../table/root.zig");
const model = @import("../../model.zig");
const records = @import("../../records/root.zig");
const safety = @import("../../safety.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Subtable = accelerator.model.ContextClassSubtable;
const View = table.View;
const max_input_glyphs = accelerator.model.max_context_region_glyphs;

pub fn apply(
    comptime Executor: type,
    view: View,
    subtable: Subtable,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    const group = accelerator.index.class_first.findPrepared(
        subtable.classes,
        subtable.first_index_start,
        subtable.groups,
        glyphs.items[position],
    ) orelse return .{};
    return applyGroup(
        Executor,
        view,
        subtable,
        group,
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn applyGroup(
    comptime Executor: type,
    view: View,
    subtable: Subtable,
    group: *const class_context.RuleGroup,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (group.max_input_count == 0 or
        group.max_input_count > max_input_glyphs)
    {
        return error.UnsupportedGsub;
    }

    var input_indices_buffer: [max_input_glyphs]usize = undefined;
    const input_len = traversal.collectForwardPrefix(
        glyphs.items,
        position,
        lookup_flag,
        run,
        input_indices_buffer[0..group.max_input_count],
        false,
        position,
    );
    if (input_len == 0) return .{};
    const input_indices = input_indices_buffer[0..input_len];
    var input_classes: [max_input_glyphs]u16 = undefined;
    var input_hashes: [max_input_glyphs]u64 = undefined;
    input_hashes[0] = class_context.sequenceHashEmpty();
    for (1..input_len) |input_index| {
        input_classes[input_index - 1] =
            if (subtable.class_def == table.class_def.empty_offset)
                glyphs.items[input_indices[input_index]]
            else
                try table.class_def.value(
                    view,
                    subtable.class_def,
                    glyphs.items[input_indices[input_index]],
                );
        // Many production format-2 class sets contain hundreds of rules of
        // the same length. Cache each input-prefix hash once instead of
        // recomputing it independently for every candidate rule.
        input_hashes[input_index] = class_context.sequenceHashAppend(
            input_hashes[input_index - 1],
            input_classes[input_index - 1],
        );
    }

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        if (rule.input_count == 0 or rule.input_count > input_len) continue;
        const extra_count = @as(usize, rule.input_count) - 1;
        if (rule.hash != input_hashes[extra_count]) {
            continue;
        }
        const expected = subtable.classes[rule.classes_start .. rule.classes_start + extra_count];
        if (!std.mem.eql(u16, expected, input_classes[0..extra_count])) {
            continue;
        }

        const matched_indices = input_indices[0..rule.input_count];
        try safety.markInput(allocator, run, matched_indices);
        const glyph_count_before = glyphs.items.len;
        try records.apply(
            Executor,
            view,
            glyphs,
            rule.records_offset,
            rule.subst_count,
            matched_indices,
            allocator,
            run,
        );
        const original_next =
            input_indices[rule.input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = model.nextPositionAfterMutation(
                original_next,
                position,
                glyph_count_before,
                glyphs.items.len,
            ),
        };
    }
    return .{};
}
