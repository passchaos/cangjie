//! Allocation-free fast path for contextual records targeting SingleSubst.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const direct_single = @import("../../direct/single/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || limits.Error;
const Single = accelerator.model.SingleSubstitution;
const View = table.View;

pub const max_records = 64;

pub fn apply(
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    records_offset: usize,
    record_count: usize,
    input_indices: []const usize,
    run: Options,
) Error!bool {
    if (record_count == 0) return true;
    if (record_count > max_records) return false;
    if (try applyAccelerated(
        view,
        glyphs,
        records_offset,
        record_count,
        input_indices,
        run,
    )) return true;
    return applyParsed(
        view,
        glyphs,
        records_offset,
        record_count,
        input_indices,
        run,
    );
}

// Keep generic lookup-header and subtable scratch out of the overwhelmingly
// common accelerator-backed record path. Large Arabic contextual programs
// invoke this helper many thousands of times per corpus.
noinline fn applyParsed(
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    records_offset: usize,
    record_count: usize,
    input_indices: []const usize,
    run: Options,
) Error!bool {
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    var targets: [max_records]usize = undefined;
    var lookup_offsets: [max_records]usize = undefined;
    var lookup_flags: [max_records]u16 = undefined;
    var subtable_counts: [max_records]u16 = undefined;
    var lookup_indices: [max_records]u16 = undefined;
    var singles: [max_records]Single = undefined;

    for (0..record_count) |record_index| {
        const record = records_offset + record_index * 4;
        const sequence_index = try view.readU16(record);
        const lookup_index = try view.readU16(record + 2);
        if (sequence_index >= input_indices.len) return false;
        if (lookup_index >= lookup_count) return error.BadGsub;
        // Fall back to the generic record executor so disabled nested lookups
        // retain authored record ordering without duplicating its map logic.
        if (lookup_order.contains(run.disabled_lookups, lookup_index)) {
            return false;
        }

        var single = Single{};
        var lookup_offset: usize = 0;
        var lookup_flag: u16 = 0;
        var subtable_count: u16 = 0;
        var resolved = false;
        if (run.lookup_accelerators) |lookups| {
            if (lookup_index < lookups.len and
                lookups[lookup_index].single_subst.enabled)
            {
                single = lookups[lookup_index].single_subst;
                resolved = true;
            }
        }
        for (lookup_indices[0..record_index], 0..) |prior, prior_index| {
            if (prior != lookup_index) continue;
            lookup_offset = lookup_offsets[prior_index];
            lookup_flag = lookup_flags[prior_index];
            subtable_count = subtable_counts[prior_index];
            single = singles[prior_index];
            resolved = true;
            break;
        }
        if (!resolved or !single.enabled) {
            lookup_offset = try requiredLookup(
                view,
                lookup_list,
                lookup_index,
            );
            if (try view.readU16(lookup_offset) != 1) return false;
            lookup_flag = try view.readU16(lookup_offset + 2);
            subtable_count = try view.readU16(lookup_offset + 4);
        }

        lookup_indices[record_index] = lookup_index;
        targets[record_index] = input_indices[sequence_index];
        lookup_offsets[record_index] = lookup_offset;
        lookup_flags[record_index] = lookup_flag;
        subtable_counts[record_index] = subtable_count;
        singles[record_index] = single;
    }

    for (0..record_count) |record_index| {
        const target = targets[record_index];
        if (target >= glyphs.items.len) continue;
        try limits.consumeNested(run);
        if (singles[record_index].enabled) {
            _ = try direct_single.acceleratedAt(
                view,
                singles[record_index],
                glyphs,
                target,
                run,
            );
            continue;
        }
        var nested_run = run;
        if ((lookup_flags[record_index] & 0x0010) != 0) {
            nested_run.active_mark_filtering_set = try view.readU16(
                lookup_offsets[record_index] + 6 +
                    @as(usize, subtable_counts[record_index]) * 2,
            );
            try filtering.validateMarkFilteringSetIndex(nested_run);
        }
        for (0..subtable_counts[record_index]) |subtable_index| {
            const subtable_offset = lookup_offsets[record_index] +
                try view.readU16(
                    lookup_offsets[record_index] + 6 + subtable_index * 2,
                );
            if (try direct_single.at(
                view,
                subtable_offset,
                glyphs,
                target,
                lookup_flags[record_index],
                nested_run,
            )) break;
        }
    }
    return true;
}

fn applyAccelerated(
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    records_offset: usize,
    record_count: usize,
    input_indices: []const usize,
    run: Options,
) Error!bool {
    const lookups = run.lookup_accelerators orelse return false;
    var targets: [max_records]usize = undefined;
    var singles: [max_records]*const Single = undefined;

    for (0..record_count) |record_index| {
        const record = records_offset + record_index * 4;
        const sequence_index = try view.readU16(record);
        const lookup_index = try view.readU16(record + 2);
        if (sequence_index >= input_indices.len) return false;
        if (lookup_index >= lookups.len) return error.BadGsub;
        if (lookup_order.contains(run.disabled_lookups, lookup_index)) {
            return false;
        }
        const single = &lookups[lookup_index].single_subst;
        if (!single.enabled) return false;
        targets[record_index] = input_indices[sequence_index];
        singles[record_index] = single;
    }

    for (0..record_count) |record_index| {
        if (targets[record_index] >= glyphs.items.len) continue;
        try limits.consumeNested(run);
        _ = try direct_single.acceleratedAt(
            view,
            singles[record_index].*,
            glyphs,
            targets[record_index],
            run,
        );
    }
    return true;
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try view.readU16(8));
}

fn requiredLookup(
    view: View,
    lookup_list: usize,
    lookup_index: usize,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_list,
        try view.readU16(lookup_list + 2 + lookup_index * 2),
    );
}
