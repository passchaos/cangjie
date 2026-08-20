//! Chaining-context accelerator construction.

const std = @import("std");
const class_context = @import("../../../opentype/class_context.zig");
const model = @import("../model.zig");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");
const owned_coverage = @import("../coverage.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

const max_region_glyphs = 64;

pub fn coverageSubtable(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ChainingCoverageSubtable {
    const parsed =
        try positioning.lookup.contextual.parseChainingCoverage(
            view,
            subtable_offset,
        ) orelse return null;
    var subtable = model.ChainingCoverageSubtable{
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
    errdefer model.deinitChainingCoverageSubtableContents(
        subtable,
        allocator,
    );
    subtable.backtrack_coverages = try owned_coverage.Owned.buildSequence(
        view,
        subtable_offset,
        subtable.backtrack_offsets_pos,
        subtable.backtrack_count,
        allocator,
    );
    subtable.input_coverages = try owned_coverage.Owned.buildSequence(
        view,
        subtable_offset,
        subtable.input_offsets_pos,
        subtable.input_count,
        allocator,
    );
    subtable.lookahead_coverages = try owned_coverage.Owned.buildSequence(
        view,
        subtable_offset,
        subtable.lookahead_offsets_pos,
        subtable.lookahead_count,
        allocator,
    );
    try fillFastSingleRecords(view, &subtable);
    if (subtable.input_count > 1) {
        const second = try parsed.input_coverages.coverageOffset(view, 1);
        subtable.second_input_digest =
            try table.coverage.digest(view, second);
    }
    return subtable;
}

pub fn deinitCoverageSubtables(
    allocator: std.mem.Allocator,
    subtables: []const model.ChainingCoverageSubtable,
) void {
    model.deinitChainingCoverageSubtables(subtables, allocator);
}

pub fn deinitCoverageSubtableContents(
    allocator: std.mem.Allocator,
    subtable: model.ChainingCoverageSubtable,
) void {
    model.deinitChainingCoverageSubtableContents(subtable, allocator);
}

pub fn extensionClassSubtables(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]model.ChainingClassSubtable {
    if (lookup_type != 9) {
        return allocator.alloc(model.ChainingClassSubtable, 0);
    }
    if ((try positioning.lookup.dispatch.commonExtensionType(
        view,
        lookup_offset,
        subtable_count,
    )) != 8) {
        return allocator.alloc(model.ChainingClassSubtable, 0);
    }

    const subtables =
        try allocator.alloc(model.ChainingClassSubtable, subtable_count);
    @memset(subtables, .{});
    var built_count: usize = 0;
    errdefer {
        model.deinitChainingClassSubtableContents(
            subtables[0..built_count],
            allocator,
        );
        allocator.free(subtables);
    }
    for (0..subtable_count) |subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        const payload =
            try positioning.lookup.dispatch.extensionPayload(view, wrapper, 8);
        const parsed = try classSubtable(
            view,
            payload,
            allocator,
        ) orelse {
            model.deinitChainingClassSubtableContents(
                subtables[0..built_count],
                allocator,
            );
            allocator.free(subtables);
            return allocator.alloc(model.ChainingClassSubtable, 0);
        };
        subtables[subtable_index] = parsed;
        built_count += 1;
    }
    return subtables;
}

pub fn coverageOnly(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
) Error!bool {
    for (0..subtable_count) |subtable_index| {
        const subtable = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        if (try view.readU16(subtable) != 3) return false;
    }
    return true;
}

fn fillFastSingleRecords(
    view: View,
    subtable: *model.ChainingCoverageSubtable,
) Error!void {
    if (subtable.pos_count == 0 or
        subtable.pos_count > model.ChainingCoverageSubtable.max_fast_records)
    {
        return;
    }
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    var records =
        [_]model.FastSinglePositionRecord{.{}} **
        model.ChainingCoverageSubtable.max_fast_records;
    for (0..subtable.pos_count) |record_index| {
        const record = subtable.records_pos + record_index * 4;
        const sequence_index = try view.readU16(record);
        if (sequence_index >= subtable.input_count) return;
        const lookup_index = try view.readU16(record + 2);
        if (lookup_index >= lookup_count) return;
        const lookup = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
        if (try view.readU16(lookup) != 1) return;
        const lookup_flag = try view.readU16(lookup + 2);
        if ((lookup_flag & 0x0010) != 0) return;
        if (try view.readU16(lookup + 4) == 0) return;
        records[record_index] = .{
            .sequence_index = sequence_index,
            .lookup_index = lookup_index,
            .lookup_flag = lookup_flag,
        };
    }
    subtable.fast_record_count = subtable.pos_count;
    subtable.fast_records = records;
}

fn classSubtable(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ChainingClassSubtable {
    const parsed =
        try positioning.lookup.contextual.parseChaining(view, subtable_offset);
    const class_table = switch (parsed) {
        .class => |value| value,
        else => return null,
    };
    // This specialized sidecar intentionally supports only rules without
    // backtrack and with one lookup applied at input sequence index zero.
    var rules = std.ArrayList(class_context.Rule).empty;
    var classes = std.ArrayList(u16).empty;
    var groups = std.ArrayList(class_context.RuleGroup).empty;
    var success = false;
    defer if (!success) {
        rules.deinit(allocator);
        classes.deinit(allocator);
        groups.deinit(allocator);
    };

    var order: u32 = 0;
    for (0..class_table.sets.count) |set_index| {
        const set_offset =
            try class_table.sets.resolve(view, set_index) orelse continue;
        const set = try positioning.lookup.contextual.parseRuleSet(
            view,
            set_offset,
        );
        for (0..set.rule_count) |rule_index| {
            const rule =
                try positioning.lookup.contextual.parseChainingRule(
                    view,
                    try set.ruleOffset(view, rule_index),
                );
            if (rule.backtrack_count != 0 or
                rule.input_count == 0 or
                rule.input_count > max_region_glyphs or
                rule.lookahead_count > max_region_glyphs or
                rule.records.count != 1)
            {
                return null;
            }
            const position_record = try rule.records.record(view, 0);
            if (position_record.sequence_index != 0) return null;
            const classes_start = classes.items.len;
            var hash = class_context.sequenceHashEmpty();
            for (1..rule.input_count) |input_index| {
                const class = try view.readU16(
                    rule.input_values_pos + (input_index - 1) * 2,
                );
                try classes.append(allocator, class);
                hash = class_context.sequenceHashAppend(hash, class);
            }
            for (0..rule.lookahead_count) |lookahead_index| {
                const class = try view.readU16(
                    rule.lookahead_values_pos + lookahead_index * 2,
                );
                try classes.append(allocator, class);
                hash = class_context.sequenceHashAppend(hash, class);
            }
            try rules.append(allocator, .{
                .class_set = @intCast(set_index),
                .input_count = rule.input_count,
                .lookahead_count = rule.lookahead_count,
                .hash = hash,
                .order = order,
                .lookup_index = position_record.lookup_index,
                .classes_start = @intCast(classes_start),
            });
            order += 1;
        }
    }
    if (rules.items.len == 0) return null;

    std.sort.heap(
        class_context.Rule,
        rules.items,
        {},
        class_context.ruleLessThan,
    );
    var group_start: usize = 0;
    while (group_start < rules.items.len) {
        const class_set = rules.items[group_start].class_set;
        var group_end = group_start;
        var max_input_count: u16 = 0;
        var max_lookahead_count: u16 = 0;
        while (group_end < rules.items.len and
            rules.items[group_end].class_set == class_set) : (group_end += 1)
        {
            max_input_count =
                @max(max_input_count, rules.items[group_end].input_count);
            max_lookahead_count = @max(
                max_lookahead_count,
                rules.items[group_end].lookahead_count,
            );
        }
        try groups.append(allocator, .{
            .class_set = class_set,
            .start = group_start,
            .len = group_end - group_start,
            .max_input_count = max_input_count,
            .max_lookahead_count = max_lookahead_count,
        });
        group_start = group_end;
    }

    const rule_slice = try rules.toOwnedSlice(allocator);
    errdefer allocator.free(rule_slice);
    const class_slice = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(class_slice);
    const group_slice = try groups.toOwnedSlice(allocator);
    success = true;
    return .{
        .subtable_offset = subtable_offset,
        .coverage_offset = class_table.coverage_offset,
        .input_class_def = class_table.input_class_def,
        .lookahead_class_def = class_table.lookahead_class_def,
        .uniform_input_count = if (group_slice.len == 1)
            group_slice[0].max_input_count
        else
            0,
        .rules = rule_slice,
        .classes = class_slice,
        .groups = group_slice,
    };
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try view.readU16(8));
}
