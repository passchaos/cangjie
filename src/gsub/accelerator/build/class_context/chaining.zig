//! ChainContextSubst format-2 class accelerator construction.

const std = @import("std");
const first_index = @import("../../index/class_first.zig");
const model = @import("../../model.zig");
const ownership = @import("../../ownership.zig");
const opentype_class_context =
    @import("../../../../opentype/class_context.zig");
const shared = @import("shared.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Source = shared.Source;
pub const View = table.View;

pub fn build(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    source: Source,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]model.ChainingClassSubtable {
    const subtables =
        try allocator.alloc(model.ChainingClassSubtable, subtable_count);
    @memset(subtables, .{});
    var built_count: usize = 0;
    errdefer {
        ownership.deinitChainingClassSubtableContents(
            allocator,
            subtables[0..built_count],
        );
        allocator.free(subtables);
    }

    for (subtables, 0..) |*subtable, subtable_index| {
        const offset = try shared.resolveSubtable(
            view,
            lookup_offset,
            subtable_index,
            source,
            6,
        );
        subtable.* = try buildSubtable(view, offset, allocator) orelse {
            // Preserve single ownership when allocation of the empty fallback
            // itself fails: the outer errdefer still owns partial state until
            // this allocation succeeds.
            const empty =
                try allocator.alloc(model.ChainingClassSubtable, 0);
            ownership.deinitChainingClassSubtableContents(
                allocator,
                subtables[0..built_count],
            );
            allocator.free(subtables);
            return empty;
        };
        built_count += 1;
    }
    return subtables;
}

fn buildSubtable(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ChainingClassSubtable {
    if (try view.readU16(subtable_offset) != 2) return null;
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const backtrack_class_def = (try table.offset.optional16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 4),
    )) orelse table.class_def.empty_offset;
    const input_class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 6),
    );
    const lookahead_class_def = (try table.offset.optional16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 8),
    )) orelse table.class_def.empty_offset;
    const set_count = try view.readU16(subtable_offset + 10);

    var rules = std.ArrayList(opentype_class_context.Rule).empty;
    var classes = std.ArrayList(u16).empty;
    var groups = std.ArrayList(opentype_class_context.RuleGroup).empty;
    var success = false;
    defer if (!success) {
        rules.deinit(allocator);
        classes.deinit(allocator);
        groups.deinit(allocator);
    };

    var order: u32 = 0;
    for (0..set_count) |set_index| {
        const set_relative =
            try view.readU16(subtable_offset + 12 + set_index * 2);
        if (set_relative == 0) continue;
        const set_offset = subtable_offset + set_relative;
        const rule_count = try view.readU16(set_offset);
        for (0..rule_count) |rule_index| {
            const rule_offset = set_offset +
                try view.readU16(set_offset + 2 + rule_index * 2);
            var cursor = rule_offset;

            const backtrack_count = try view.readU16(cursor);
            cursor += 2;
            if (backtrack_count > shared.max_region_glyphs) return null;
            const classes_start = classes.items.len;
            var hash = opentype_class_context.sequenceHashEmpty();
            for (0..backtrack_count) |backtrack_index| {
                const class =
                    try view.readU16(cursor + backtrack_index * 2);
                try classes.append(allocator, class);
                hash = opentype_class_context.sequenceHashAppend(hash, class);
            }
            cursor += @as(usize, backtrack_count) * 2;

            const input_count = try view.readU16(cursor);
            cursor += 2;
            if (input_count == 0 or
                input_count > shared.max_region_glyphs)
            {
                return null;
            }
            for (1..input_count) |input_index| {
                const class =
                    try view.readU16(cursor + (input_index - 1) * 2);
                try classes.append(allocator, class);
                hash = opentype_class_context.sequenceHashAppend(hash, class);
            }
            cursor += (@as(usize, input_count) - 1) * 2;

            const lookahead_count = try view.readU16(cursor);
            cursor += 2;
            if (lookahead_count > shared.max_region_glyphs) return null;
            for (0..lookahead_count) |lookahead_index| {
                const class =
                    try view.readU16(cursor + lookahead_index * 2);
                try classes.append(allocator, class);
                hash = opentype_class_context.sequenceHashAppend(hash, class);
            }
            cursor += @as(usize, lookahead_count) * 2;

            const subst_count = try view.readU16(cursor);
            cursor += 2;
            const records_offset = cursor;
            const compact_nested = subst_count == 1 and
                try view.readU16(cursor) == 0;
            const nested_lookup_index = if (compact_nested)
                try view.readU16(cursor + 2)
            else
                0;

            try rules.append(allocator, .{
                .class_set = @intCast(set_index),
                .input_count = input_count,
                .lookahead_count = lookahead_count,
                .hash = hash,
                .order = order,
                .lookup_index = nested_lookup_index,
                .classes_start = @intCast(classes_start),
                .subst_count = subst_count,
                .backtrack_count = backtrack_count,
                .record_list = !compact_nested,
                .records_offset = if (compact_nested)
                    0
                else
                    @intCast(records_offset),
            });
            order += 1;
        }
    }
    if (rules.items.len == 0) return null;

    try shared.finishChainingRuleGroups(&rules, &groups, allocator);
    fillSecondInputClassDigests(rules.items, classes.items, groups.items);
    const first_index_start = try first_index.appendClassIndex(
        view,
        coverage_offset,
        input_class_def,
        groups.items,
        &classes,
        allocator,
    );
    const rules_slice = try rules.toOwnedSlice(allocator);
    errdefer allocator.free(rules_slice);
    const classes_slice = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(classes_slice);
    const groups_slice = try groups.toOwnedSlice(allocator);
    errdefer allocator.free(groups_slice);
    const backtrack_class_values = try shared.denseClassValues(
        view,
        backtrack_class_def,
        allocator,
    );
    errdefer allocator.free(backtrack_class_values);
    const input_class_values = try shared.denseClassValues(
        view,
        input_class_def,
        allocator,
    );
    errdefer allocator.free(input_class_values);
    const lookahead_class_values = try shared.denseClassValues(
        view,
        lookahead_class_def,
        allocator,
    );
    success = true;

    return .{
        .first_index_start = first_index_start,
        .backtrack_class_def = backtrack_class_def,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .backtrack_class_values = backtrack_class_values,
        .input_class_values = input_class_values,
        .lookahead_class_values = lookahead_class_values,
        .rules = rules_slice,
        .classes = classes_slice,
        .groups = groups_slice,
    };
}

fn fillSecondInputClassDigests(
    rules: []const opentype_class_context.Rule,
    classes: []const u16,
    groups: []opentype_class_context.RuleGroup,
) void {
    for (groups) |*group| {
        // A digest lookup is useful only on the indexed path. More
        // importantly, a one-input alternative has no second-class
        // requirement, so rejecting on any second class would be unsound.
        if (!group.hash_sorted or group.min_input_count < 2) continue;

        var digest: u8 = 0;
        for (rules[group.start .. group.start + group.len]) |rule| {
            // Chaining rules store backtrack classes first, followed by
            // input[1..] and lookahead. Therefore the first class after the
            // backtrack prefix is always the rule's second input class.
            const second_class =
                classes[rule.classes_start + rule.backtrack_count];
            const bit: u3 = @truncate(second_class);
            digest |= @as(u8, 1) << bit;
        }
        group.second_input_class_digest = digest;
    }
}
