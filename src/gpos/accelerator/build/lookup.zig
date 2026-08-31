//! Assembly of the complete owned GPOS lookup-sidecar graph.

const std = @import("std");
const coverage = @import("../coverage.zig");
const glyph_groups = @import("../glyph_groups.zig");
const model = @import("../model.zig");
const pair = @import("../pair.zig");
const chaining = @import("chaining.zig");
const context = @import("context.zig");
const coverage_navigation = @import("coverage.zig");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Lookup = model.Lookup;
pub const View = table.View;

pub fn all(
    data: []const u8,
    offset: usize,
    length: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]Lookup {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGpos;
    }
    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    if (try view.readU16(0) != 1) return error.UnsupportedGpos;

    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    const lookups = try allocator.alloc(Lookup, lookup_count);
    @memset(lookups, .{});
    var built_count: usize = 0;
    errdefer {
        model.deinitLookupContents(
            lookups[0..built_count],
            allocator,
        );
        allocator.free(lookups);
    }
    for (lookups, 0..) |*lookup, lookup_index| {
        const lookup_offset = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(lookup_list + 2 + lookup_index * 2),
        );
        // Runtime dispatch trusts matching sidecar identity and header fields,
        // so construction re-proves the complete fixed lookup header.
        try positioning.lookup.dispatch.validateHeader(view, lookup_offset);
        lookup.* = try one(view, lookup_offset, allocator);
        built_count += 1;
    }
    return lookups;
}

pub fn deinit(allocator: std.mem.Allocator, lookups: []Lookup) void {
    model.deinitLookups(lookups, allocator);
}

pub fn deinitContents(
    allocator: std.mem.Allocator,
    lookups: []Lookup,
) void {
    model.deinitLookupContents(lookups, allocator);
}

pub fn one(
    view: View,
    lookup_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Lookup {
    const lookup_type = try view.readU16(lookup_offset);
    const lookup_flag = try view.readU16(lookup_offset + 2);
    const subtable_count = try view.readU16(lookup_offset + 4);
    const extension_type = if (lookup_type == 9)
        try positioning.lookup.dispatch.commonExtensionType(
            view,
            lookup_offset,
            subtable_count,
        )
    else
        null;
    const accelerates_pair = lookup_type == 2 or extension_type == 2;

    var result = Lookup{
        .lookup_offset = lookup_offset,
        .lookup_type = lookup_type,
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .lookup_offset_proved = true,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try view.readU16(
                lookup_offset + 6 + @as(usize, subtable_count) * 2,
            )
        else
            null,
        .extension_lookup_type = extension_type,
    };
    const singles = if (lookup_type == 1)
        try allocator.alloc(
            model.SinglePositionSubtable,
            subtable_count,
        )
    else
        try allocator.alloc(model.SinglePositionSubtable, 0);
    errdefer allocator.free(singles);
    @memset(singles, .{});

    const pairs = if (accelerates_pair)
        try allocator.alloc(
            model.PairPositionSubtable,
            subtable_count,
        )
    else
        try allocator.alloc(model.PairPositionSubtable, 0);
    errdefer allocator.free(pairs);
    @memset(pairs, .{});
    var pair_records = std.ArrayList(model.PairPositionRecord).empty;
    defer pair_records.deinit(allocator);
    var pair_coverage_classes =
        std.ArrayList(model.PairClassEntry).empty;
    defer pair_coverage_classes.deinit(allocator);
    var pair_classes = std.ArrayList(model.PairClassEntry).empty;
    defer pair_classes.deinit(allocator);
    var pair_matrix = std.ArrayList(i16).empty;
    defer pair_matrix.deinit(allocator);

    const mark_bases = if (lookup_type == 4)
        try allocator.alloc(
            model.MarkToBaseSubtable,
            subtable_count,
        )
    else
        try allocator.alloc(model.MarkToBaseSubtable, 0);
    errdefer model.deinitMarkToBaseSubtables(
        mark_bases,
        allocator,
    );
    @memset(mark_bases, .{});

    const mark_marks = if (lookup_type == 6)
        try allocator.alloc(model.MarkToMarkSubtable, subtable_count)
    else
        try allocator.alloc(model.MarkToMarkSubtable, 0);
    errdefer model.deinitMarkToMarkSubtables(mark_marks, allocator);
    @memset(mark_marks, .{});

    const cursive = if (lookup_type == 3)
        try allocator.alloc(
            model.CursivePositionSubtable,
            subtable_count,
        )
    else
        try allocator.alloc(model.CursivePositionSubtable, 0);
    errdefer model.deinitCursiveSubtables(cursive, allocator);
    @memset(cursive, .{
        .subtable_offset = 0,
        .coverage_offset = 0,
        .entry_exit_count = 0,
    });

    var coverage_pairs = std.ArrayList(glyph_groups.Pair).empty;
    defer coverage_pairs.deinit(allocator);
    var chaining_pairs = std.ArrayList(glyph_groups.Pair).empty;
    defer chaining_pairs.deinit(allocator);
    var chaining_second_pairs = std.ArrayList(glyph_groups.Pair).empty;
    defer chaining_second_pairs.deinit(allocator);
    var chaining_second_start: ?u16 = null;
    var chaining_second_end: u16 = 0;
    var chaining_second_closed = false;
    var chaining_second_glyph_count: usize = 0;
    const chaining_subtables =
        if (lookup_type == 8 and
        try chaining.coverageOnly(view, lookup_offset, subtable_count))
            try allocator.alloc(
                model.ChainingCoverageSubtable,
                subtable_count,
            )
        else
            try allocator.alloc(
                model.ChainingCoverageSubtable,
                0,
            );
    errdefer model.deinitChainingCoverageSubtables(
        chaining_subtables,
        allocator,
    );
    @memset(chaining_subtables, .{});

    for (0..subtable_count) |subtable_index| {
        const subtable_offset = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        const first_coverage = try coverage_navigation.subtableOffset(
            view,
            subtable_offset,
            lookup_type,
        ) orelse continue;
        result.coverage_digest.unionWith(
            try table.coverage.digest(view, first_coverage),
        );
        try glyph_groups.appendCoveragePairs(
            view,
            first_coverage,
            @intCast(subtable_index),
            &coverage_pairs,
            allocator,
        );
        if (singles.len != 0) {
            singles[subtable_index] =
                try positioning.lookup.single.parse(view, subtable_offset);
        }
        if (pairs.len != 0) {
            const pair_subtable = if (extension_type == 2)
                try positioning.lookup.dispatch.extensionPayload(
                    view,
                    subtable_offset,
                    2,
                )
            else
                subtable_offset;
            pairs[subtable_index] = try pair.append(
                view,
                pair_subtable,
                &pair_records,
                &pair_coverage_classes,
                &pair_classes,
                &pair_matrix,
                allocator,
            );
        }
        if (mark_bases.len != 0) {
            mark_bases[subtable_index] = try buildMarkBase(
                view,
                subtable_offset,
                allocator,
            );
        }
        if (mark_marks.len != 0) {
            mark_marks[subtable_index] = try buildMarkMark(
                view,
                subtable_offset,
                allocator,
            );
        }
        if (cursive.len != 0) {
            cursive[subtable_index] = try buildCursive(
                view,
                subtable_offset,
                allocator,
            );
        }
        if (chaining_subtables.len != 0) {
            chaining_subtables[subtable_index] =
                try chaining.coverageSubtable(
                    view,
                    subtable_offset,
                    allocator,
                ) orelse continue;
            try glyph_groups.appendCoveragePairs(
                view,
                first_coverage,
                @intCast(subtable_index),
                &chaining_pairs,
                allocator,
            );
            const chained = chaining_subtables[subtable_index];
            if (!chaining_second_closed) {
                if (chaining.simpleSecondEligible(view, chained)) {
                    if (chaining_second_start == null) {
                        chaining_second_start = @intCast(subtable_index);
                    }
                    chaining_second_end = @intCast(subtable_index + 1);
                    const second_coverage = chained.lookahead_coverages[0];
                    const second_glyph_count = second_coverage.glyphCount();
                    // Keep this auxiliary index bounded independently of font
                    // glyph-id spans. Large authored sets retain the existing
                    // exact Owned-Coverage fallback without construction-time
                    // memory amplification.
                    if (second_glyph_count >
                        chaining.max_second_group_pairs -
                            chaining_second_glyph_count)
                    {
                        chaining_second_closed = true;
                        chaining_second_start = null;
                        chaining_second_end = 0;
                        chaining_second_pairs.clearRetainingCapacity();
                        continue;
                    }
                    try glyph_groups.appendOwnedCoveragePairs(
                        second_coverage,
                        @intCast(subtable_index),
                        &chaining_second_pairs,
                        allocator,
                    );
                    chaining_second_glyph_count += second_glyph_count;
                } else if (chaining_second_start != null) {
                    chaining_second_closed = true;
                }
            }
        }
    }

    result.single_pos_subtables = singles;
    result.pair_pos_subtables = pairs;
    result.pair_pos_records = try pair_records.toOwnedSlice(allocator);
    errdefer allocator.free(result.pair_pos_records);
    result.pair_pos_coverage_classes =
        try pair_coverage_classes.toOwnedSlice(allocator);
    errdefer allocator.free(result.pair_pos_coverage_classes);
    result.pair_pos_class_entries = try pair_classes.toOwnedSlice(allocator);
    errdefer allocator.free(result.pair_pos_class_entries);
    result.pair_pos_class_matrix = try pair_matrix.toOwnedSlice(allocator);
    errdefer allocator.free(result.pair_pos_class_matrix);
    result.pair_pos_extension = extension_type == 2;
    result.cursive_subtables = cursive;
    result.mark_to_base_subtables = mark_bases;
    result.mark_to_mark_subtables = mark_marks;
    result.context_class_subtables = try context.classSubtables(
        view,
        lookup_offset,
        lookup_type,
        extension_type,
        subtable_count,
        allocator,
    );
    errdefer model.deinitContextClassSubtables(
        result.context_class_subtables,
        allocator,
    );

    if (coverage_pairs.items.len != 0) {
        result.coverage_groups =
            try glyph_groups.buildGroups(
                coverage_pairs.items,
                allocator,
            );
        errdefer glyph_groups.deinitGroups(
            result.coverage_groups,
            allocator,
        );
        result.coverage_group_slots =
            try glyph_groups.buildSlots(
                result.coverage_groups,
                allocator,
            );
        errdefer allocator.free(result.coverage_group_slots);
        result.coverage_group_direct =
            try glyph_groups.buildDirect(
                result.coverage_groups,
                allocator,
            );
        errdefer allocator.free(result.coverage_group_direct);
    }
    errdefer {
        glyph_groups.deinitGroups(result.coverage_groups, allocator);
        allocator.free(result.coverage_group_slots);
        allocator.free(result.coverage_group_direct);
    }

    if (chaining_subtables.len != 0 and chaining_pairs.items.len != 0) {
        result.chaining_coverage_only = true;
        result.chaining_subtables = chaining_subtables;
        result.chaining_groups = try glyph_groups.buildGroups(
            chaining_pairs.items,
            allocator,
        );
        errdefer glyph_groups.deinitGroups(
            result.chaining_groups,
            allocator,
        );
        result.chaining_group_slots =
            try glyph_groups.buildSlots(
                result.chaining_groups,
                allocator,
            );
        errdefer allocator.free(result.chaining_group_slots);
        result.chaining_second_groups = try glyph_groups.buildGroups(
            chaining_second_pairs.items,
            allocator,
        );
        errdefer glyph_groups.deinitGroups(
            result.chaining_second_groups,
            allocator,
        );
        result.chaining_second_group_slots = try glyph_groups.buildSlots(
            result.chaining_second_groups,
            allocator,
        );
        errdefer allocator.free(result.chaining_second_group_slots);
        result.chaining_second_start = chaining_second_start orelse 0;
        result.chaining_second_end = chaining_second_end;
    }
    errdefer {
        glyph_groups.deinitGroups(result.chaining_groups, allocator);
        allocator.free(result.chaining_group_slots);
        glyph_groups.deinitGroups(result.chaining_second_groups, allocator);
        allocator.free(result.chaining_second_group_slots);
    }
    result.chaining_class_subtables =
        try chaining.extensionClassSubtables(
            view,
            lookup_offset,
            lookup_type,
            subtable_count,
            allocator,
        );
    // Keep the empty homogeneous-chaining allocation live through the final
    // fallible sidecar build so its registered errdefer remains the sole owner
    // on error. Once no further error is possible, release it on the success
    // path when it was not transferred into `result`.
    if (chaining_subtables.len != 0 and chaining_pairs.items.len == 0) {
        model.deinitChainingCoverageSubtables(
            chaining_subtables,
            allocator,
        );
    }
    return result;
}

fn buildMarkBase(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.MarkToBaseSubtable {
    var parsed =
        try positioning.lookup.marks.parseMarkToBase(view, subtable_offset);
    errdefer if (parsed.mark_coverage) |owned| owned.deinit(allocator);
    parsed.mark_coverage = try coverage.Owned.build(
        view,
        parsed.mark_coverage_offset,
        allocator,
    );
    parsed.base_coverage = try coverage.Owned.build(
        view,
        parsed.base_coverage_offset,
        allocator,
    );
    return parsed;
}

fn buildMarkMark(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.MarkToMarkSubtable {
    var parsed =
        try positioning.lookup.marks.parseMarkToMark(view, subtable_offset);
    errdefer if (parsed.mark_1_coverage) |owned| owned.deinit(allocator);
    parsed.mark_1_coverage = try coverage.Owned.build(
        view,
        parsed.mark_1_coverage_offset,
        allocator,
    );
    parsed.mark_2_coverage = try coverage.Owned.build(
        view,
        parsed.mark_2_coverage_offset,
        allocator,
    );
    return parsed;
}

fn buildCursive(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.CursivePositionSubtable {
    var parsed =
        try positioning.lookup.cursive.parse(view, subtable_offset);
    errdefer if (parsed.coverage) |owned| owned.deinit(allocator);
    parsed.coverage = try coverage.Owned.build(
        view,
        parsed.coverage_offset,
        allocator,
    );
    return parsed;
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try view.readU16(8));
}
