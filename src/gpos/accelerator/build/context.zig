//! Compact accelerator construction for two-input ContextPos class rules.

const std = @import("std");
const class_context = @import("../../../opentype/class_context.zig");
const model = @import("../model.zig");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub fn classSubtables(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    extension_type: ?u16,
    subtable_count: u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]model.ContextClassSubtable {
    if (lookup_type != 7 and !(lookup_type == 9 and extension_type == 7)) {
        return allocator.alloc(model.ContextClassSubtable, 0);
    }
    const subtables = try allocator.alloc(
        model.ContextClassSubtable,
        subtable_count,
    );
    @memset(subtables, .{});
    var built_count: usize = 0;
    errdefer {
        deinitContents(subtables[0..built_count], allocator);
        allocator.free(subtables);
    }

    for (subtables, 0..) |*subtable, subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(lookup_offset + 6 + subtable_index * 2),
        );
        const payload = if (lookup_type == 9)
            try positioning.lookup.dispatch.extensionPayload(view, wrapper, 7)
        else
            wrapper;
        subtable.* = try buildSubtable(view, payload, allocator) orelse {
            const empty = try allocator.alloc(model.ContextClassSubtable, 0);
            deinitContents(subtables[0..built_count], allocator);
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
) (Error || std.mem.Allocator.Error)!?model.ContextClassSubtable {
    const parsed = switch (try positioning.lookup.contextual.parseContext(
        view,
        subtable_offset,
    )) {
        .class => |value| value,
        else => return null,
    };

    var rules = std.ArrayList(class_context.Rule).empty;
    var compact_rules = std.ArrayList(model.ContextClassRule).empty;
    var groups = std.ArrayList(class_context.RuleGroup).empty;
    var coverage: ?@import("../coverage.zig").Owned = null;
    var success = false;
    defer if (!success) {
        if (coverage) |owned| owned.deinit(allocator);
        rules.deinit(allocator);
        compact_rules.deinit(allocator);
        groups.deinit(allocator);
    };

    var order: u32 = 0;
    for (0..parsed.sets.count) |class_set| {
        const set_offset = try parsed.sets.resolve(view, class_set) orelse continue;
        const set = try positioning.lookup.contextual.parseRuleSet(
            view,
            set_offset,
        );
        for (0..set.rule_count) |rule_index| {
            const rule = try positioning.lookup.contextual.parseContextRule(
                view,
                try set.ruleOffset(view, rule_index),
            );
            // A two-glyph, one-record rule is the production hot shape. The
            // record may target either input, so keep its sequence index.
            if (rule.input_count != 2 or rule.records.count != 1) return null;
            const record = try rule.records.record(view, 0);
            const second_class = try view.readU16(rule.input_values_pos);
            try rules.append(allocator, .{
                .class_set = @intCast(class_set),
                .input_count = 2,
                .lookahead_count = 0,
                .hash = class_context.sequenceHash(&.{second_class}),
                .order = order,
                .lookup_index = record.lookup_index,
                .classes_start = second_class,
                .subst_count = record.sequence_index,
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
        var group_end = group_start + 1;
        while (group_end < rules.items.len and
            rules.items[group_end].class_set == class_set) : (group_end += 1)
        {}
        try groups.append(allocator, .{
            .class_set = class_set,
            .start = group_start,
            .len = group_end - group_start,
            .min_input_count = 2,
            .max_input_count = 2,
            .max_lookahead_count = 0,
        });
        group_start = group_end;
    }
    try compact_rules.ensureTotalCapacity(allocator, rules.items.len);
    for (rules.items) |rule| {
        compact_rules.appendAssumeCapacity(.{
            .second_class = @intCast(rule.classes_start),
            .sequence_index = rule.subst_count,
            .lookup_index = rule.lookup_index,
        });
    }

    coverage = try @import("../coverage.zig").Owned.build(
        view,
        parsed.coverage_offset,
        allocator,
    );
    const rule_slice = try compact_rules.toOwnedSlice(allocator);
    errdefer allocator.free(rule_slice);
    const group_slice = try groups.toOwnedSlice(allocator);
    rules.deinit(allocator);
    success = true;
    return .{
        .coverage = coverage,
        .class_def_offset = parsed.class_def_offset,
        .rules = rule_slice,
        .groups = group_slice,
    };
}

fn deinitContents(
    subtables: []const model.ContextClassSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        if (subtable.coverage) |owned| owned.deinit(allocator);
        allocator.free(subtable.rules);
        allocator.free(subtable.groups);
    }
}
