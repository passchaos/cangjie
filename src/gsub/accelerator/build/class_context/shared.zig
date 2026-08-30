//! Shared policy and rule grouping for class-based contextual accelerators.

const std = @import("std");
const model = @import("../../model.zig");
const opentype_class_context = @import("../../../../opentype/class_context.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

/// Identifies whether a contextual payload is stored directly in its lookup
/// or behind an ExtensionSubst format-1 wrapper.
pub const Source = enum {
    direct,
    extension,
};

/// Runtime matchers use fixed stack windows. Larger authored rules remain on
/// the generic parser rather than turning accelerator construction into an
/// implicit allocation policy.
pub const max_region_glyphs = model.max_context_region_glyphs;
const max_dense_class_glyphs = 8192;

/// Expand a modest ClassDef into direct glyph-indexed values. Large sparse
/// definitions stay table-backed so adversarial fonts cannot multiply memory
/// use by the number of contextual subtables.
pub fn denseClassValues(
    view: View,
    class_def_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]const u16 {
    if (class_def_offset == table.class_def.empty_offset) return &.{};
    const format = try view.readU16(class_def_offset);
    const glyph_count: usize = switch (format) {
        1 => @as(usize, try view.readU16(class_def_offset + 2)) +
            @as(usize, try view.readU16(class_def_offset + 4)),
        2 => count: {
            const range_count = try view.readU16(class_def_offset + 2);
            var max_end: usize = 0;
            for (0..range_count) |range_index| {
                max_end = @max(
                    max_end,
                    try view.readU16(
                        class_def_offset + 4 + range_index * 6 + 2,
                    ),
                );
            }
            break :count if (range_count == 0) 0 else max_end + 1;
        },
        else => return &.{},
    };
    if (glyph_count == 0 or glyph_count > max_dense_class_glyphs) {
        return &.{};
    }
    const values = try allocator.alloc(u16, glyph_count);
    errdefer allocator.free(values);
    @memset(values, 0);
    switch (format) {
        1 => {
            const start = try view.readU16(class_def_offset + 2);
            const count = try view.readU16(class_def_offset + 4);
            for (0..count) |index| {
                values[@as(usize, start) + index] = try view.readU16(
                    class_def_offset + 6 + index * 2,
                );
            }
        },
        2 => {
            const range_count = try view.readU16(class_def_offset + 2);
            for (0..range_count) |range_index| {
                const record = class_def_offset + 4 + range_index * 6;
                const start = try view.readU16(record);
                const end = try view.readU16(record + 2);
                if (end < start) return error.BadGsub;
                @memset(
                    values[@as(usize, start) .. @as(usize, end) + 1],
                    try view.readU16(record + 4),
                );
            }
        },
        else => unreachable,
    }
    return values;
}

pub fn resolveSubtable(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
    source: Source,
    expected_lookup_type: u16,
) Error!usize {
    const wrapper = try table.offset.required16(
        view,
        lookup_offset,
        try view.readU16(lookup_offset + 6 + subtable_index * 2),
    );
    if (source == .direct) return wrapper;
    if (try view.readU16(wrapper) != 1 or
        try view.readU16(wrapper + 2) != expected_lookup_type)
    {
        return error.UnsupportedGsub;
    }
    return table.offset.extensionPayload(
        view,
        wrapper,
        try view.readU32(wrapper + 4),
    );
}

/// Sort rules into authored-order groups and retain each group's largest
/// bounded window. Runtime matching can then collect only as much context as
/// the candidate group can require while still trying individual rules in
/// their original order.
pub fn finishRuleGroups(
    rules: *std.ArrayList(opentype_class_context.Rule),
    groups: *std.ArrayList(opentype_class_context.RuleGroup),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    return finishRuleGroupsWithOrder(
        rules,
        groups,
        allocator,
        opentype_class_context.ruleLessThan,
    );
}

pub fn finishHashRuleGroups(
    rules: *std.ArrayList(opentype_class_context.Rule),
    groups: *std.ArrayList(opentype_class_context.RuleGroup),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    return finishRuleGroupsWithOrder(
        rules,
        groups,
        allocator,
        opentype_class_context.ruleHashLessThan,
    );
}

/// Preserve authored order for small chaining groups, but index larger groups
/// by region shape and hash. Runtime matching examines every represented shape
/// and picks the earliest exact rule, preserving OpenType first-match order.
pub fn finishChainingRuleGroups(
    rules: *std.ArrayList(opentype_class_context.Rule),
    groups: *std.ArrayList(opentype_class_context.RuleGroup),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    try finishRuleGroups(rules, groups, allocator);
    for (groups.items) |*group| {
        if (group.len < 8) continue;
        std.sort.heap(
            opentype_class_context.Rule,
            rules.items[group.start .. group.start + group.len],
            {},
            opentype_class_context.chainingRuleHashLessThan,
        );
        group.hash_sorted = true;
        var shape_start: usize = 0;
        while (shape_start < group.len) {
            const first = rules.items[group.start + shape_start];
            var shape_end = shape_start + 1;
            while (shape_end < group.len) : (shape_end += 1) {
                const candidate = rules.items[group.start + shape_end];
                if (candidate.backtrack_count != first.backtrack_count or
                    candidate.input_count != first.input_count or
                    candidate.lookahead_count != first.lookahead_count)
                {
                    break;
                }
            }
            group.max_shape_len = @max(
                group.max_shape_len,
                shape_end - shape_start,
            );
            shape_start = shape_end;
        }
        if (group.max_shape_len < 3) {
            // `hash_sorted` selects both the indexed matcher and the rule
            // ordering contract. Restore authored order when no shape bucket
            // is dense enough to justify hashing; otherwise the linear
            // fallback would observe shape/hash order and could choose a later
            // overlapping rule before an earlier authored rule.
            std.sort.heap(
                opentype_class_context.Rule,
                rules.items[group.start .. group.start + group.len],
                {},
                opentype_class_context.ruleLessThan,
            );
            group.hash_sorted = false;
        }
    }
}

fn finishRuleGroupsWithOrder(
    rules: *std.ArrayList(opentype_class_context.Rule),
    groups: *std.ArrayList(opentype_class_context.RuleGroup),
    allocator: std.mem.Allocator,
    comptime less_than: fn (void, opentype_class_context.Rule, opentype_class_context.Rule) bool,
) std.mem.Allocator.Error!void {
    std.sort.heap(
        opentype_class_context.Rule,
        rules.items,
        {},
        less_than,
    );
    var group_start: usize = 0;
    while (group_start < rules.items.len) {
        const class_set = rules.items[group_start].class_set;
        var group_end = group_start;
        var min_input_count: u16 = std.math.maxInt(u16);
        var max_input_count: u16 = 0;
        var max_lookahead_count: u16 = 0;
        while (group_end < rules.items.len and
            rules.items[group_end].class_set == class_set) : (group_end += 1)
        {
            min_input_count =
                @min(min_input_count, rules.items[group_end].input_count);
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
            .min_input_count = min_input_count,
            .max_input_count = max_input_count,
            .max_lookahead_count = max_lookahead_count,
        });
        group_start = group_end;
    }
}
