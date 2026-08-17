//! Single-subtable execution for ChainContextPos format 3.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const lookup_order = @import("../../../../../../opentype/lookup_order.zig");
const contextual_matching = @import("../../matching.zig");
const matching = @import("matching.zig");
const model = @import("../../model.zig");
const output = @import("../../../../output/root.zig");
const positioning = @import("../../../../../positioning/root.zig");
const run_matching = @import("../../../../matching.zig");
const single = @import("../../../single.zig");
const table = @import("../../../../../table/root.zig");

const Adjustment = model.Adjustment;
const ApplyRecordsFn = model.ApplyRecordsFn;
const Error = model.Error;
const Options = model.Options;
const Result = model.Result;
const View = model.View;

pub const Subtable = accelerator.model.ChainingCoverageSubtable;

pub fn parse(view: View, subtable_offset: usize) Error!?Subtable {
    const parsed =
        try positioning.lookup.contextual.parseChainingCoverage(
            view,
            subtable_offset,
        ) orelse return null;
    return fromParsed(parsed);
}

pub fn fromParsed(
    parsed: positioning.lookup.contextual.ChainingCoverage,
) Subtable {
    return .{
        .subtable_offset = parsed.subtable_offset,
        .backtrack_offsets_pos = parsed.backtrack_coverages.offsets_pos,
        .backtrack_count = parsed.backtrack_coverages.count,
        .input_offsets_pos = parsed.input_coverages.offsets_pos,
        .input_count = parsed.input_coverages.count,
        .lookahead_offsets_pos = parsed.lookahead_coverages.offsets_pos,
        .lookahead_count = parsed.lookahead_coverages.count,
        .records_pos = parsed.records.records_pos,
        .pos_count = parsed.records.count,
    };
}

pub fn collect(
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: model.ApplyNestedFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        const result = try collectAt(
            false,
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
            applyNested,
        );
        position = if (result.matched)
            @max(position + 1, result.next_pos)
        else
            position + 1;
    }
}

/// Execute one format-3 subtable at a candidate input position.
///
/// `first_coverage_proven` is true only after exact accelerator group lookup;
/// it skips the already-proven first input Coverage without weakening direct
/// or nested generic execution.
pub fn collectAt(
    comptime first_coverage_proven: bool,
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: model.ApplyNestedFn,
) Error!Result {
    if (position >= glyphs.len or subtable.input_count == 0) return .{};
    if (run_matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[position],
    )) return .{};
    if (view.assume_validated and
        subtable.input_count == 1 and
        subtable.backtrack_count == 0 and
        subtable.lookahead_count == 1 and
        subtable.pos_count == 1)
    {
        return collectSimpleAt(
            first_coverage_proven,
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyNested,
        );
    }

    var input_buffer: [64]usize = undefined;
    if (subtable.input_count > input_buffer.len) {
        return error.UnsupportedGpos;
    }
    const input = input_buffer[0..subtable.input_count];
    if (!contextual_matching.forward(
        glyphs,
        position,
        lookup_flag,
        run,
        input,
    )) return .{};
    if (first_coverage_proven and input[0] != position) return .{};
    if (!try matching.indices(
        view,
        subtable.subtable_offset,
        glyphs,
        input,
        subtable.input_offsets_pos,
        subtable.input_coverages,
        if (first_coverage_proven) 1 else 0,
    )) return .{};

    var backtrack_buffer: [64]usize = undefined;
    if (subtable.backtrack_count > backtrack_buffer.len) {
        return error.UnsupportedGpos;
    }
    const backtrack = backtrack_buffer[0..subtable.backtrack_count];
    if (!contextual_matching.backtrack(
        glyphs,
        position,
        lookup_flag,
        run,
        backtrack,
    )) return .{};

    var lookahead_buffer: [64]usize = undefined;
    if (subtable.lookahead_count > lookahead_buffer.len) {
        return error.UnsupportedGpos;
    }
    const lookahead = lookahead_buffer[0..subtable.lookahead_count];
    if (!contextual_matching.forward(
        glyphs,
        input[subtable.input_count - 1] + 1,
        lookup_flag,
        run,
        lookahead,
    )) return .{};
    if (!try matching.indices(
        view,
        subtable.subtable_offset,
        glyphs,
        backtrack,
        subtable.backtrack_offsets_pos,
        subtable.backtrack_coverages,
        0,
    )) return .{};
    if (!try matching.indices(
        view,
        subtable.subtable_offset,
        glyphs,
        lookahead,
        subtable.lookahead_offsets_pos,
        subtable.lookahead_coverages,
        0,
    )) return .{};

    try output.safety.markChainingContext(
        allocator,
        &run,
        backtrack,
        input,
        lookahead,
    );
    if (!try applyFastSingleRecords(
        view,
        subtable,
        glyphs,
        input,
        adjustments,
        allocator,
        run,
    )) {
        try applyRecords(
            view,
            subtable.records_pos,
            subtable.pos_count,
            input,
            glyphs,
            adjustments,
            allocator,
            run,
        );
    }
    return .{
        .matched = true,
        .next_pos = input[subtable.input_count - 1] + 1,
    };
}

fn applyFastSingleRecords(
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    input_indices: []const usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) Error!bool {
    if (subtable.fast_record_count == 0) return false;
    const accelerators = run.lookup_accelerators orelse return false;
    for (subtable.fast_records[0..subtable.fast_record_count]) |record| {
        if (record.sequence_index >= input_indices.len or
            record.lookup_index >= accelerators.len)
        {
            return false;
        }
        // Defer disabled records to the generic nested executor, which skips
        // them while retaining the authored ordering of any remaining records.
        if (lookup_order.contains(
            run.disabled_lookups,
            record.lookup_index,
        )) return false;
        const target_index = input_indices[record.sequence_index];
        if (target_index >= glyphs.len) continue;
        const nested = accelerators[record.lookup_index];
        if (nested.single_pos_subtables.len == 0) return false;
        var nested_run = run;
        nested_run.context_depth = run.context_depth + 1;
        _ = try single.collectAtAccelerated(
            view,
            nested.single_pos_subtables,
            glyphs[target_index],
            target_index,
            adjustments,
            allocator,
            record.lookup_flag,
            nested_run,
        );
    }
    return true;
}

fn collectSimpleAt(
    comptime first_coverage_proven: bool,
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyNested: model.ApplyNestedFn,
) Error!Result {
    if (!first_coverage_proven) {
        if (subtable.input_coverages.len != 0) {
            if (subtable.input_coverages[0].index(glyphs[position]) == null) {
                return .{};
            }
        } else {
            const coverage_offset = try table.offset.required16(
                view,
                subtable.subtable_offset,
                try view.readU16(subtable.input_offsets_pos),
            );
            if (!try table.coverage.contains(
                view,
                coverage_offset,
                glyphs[position],
                .membership,
            )) return .{};
        }
    }

    const lookahead_index = contextual_matching.next(
        glyphs,
        position + 1,
        lookup_flag,
        run,
    ) orelse return .{};
    if (subtable.lookahead_coverages.len != 0) {
        if (subtable.lookahead_coverages[0].index(
            glyphs[lookahead_index],
        ) == null) return .{};
    } else {
        const coverage_offset = try table.offset.required16(
            view,
            subtable.subtable_offset,
            try view.readU16(subtable.lookahead_offsets_pos),
        );
        if (!try table.coverage.contains(
            view,
            coverage_offset,
            glyphs[lookahead_index],
            .membership,
        )) return .{};
    }
    if (try view.readU16(subtable.records_pos) != 0) return .{};
    try applyNested(
        view,
        glyphs,
        position,
        try view.readU16(subtable.records_pos + 2),
        adjustments,
        allocator,
        run,
    );
    return .{ .matched = true, .next_pos = lookahead_index };
}
