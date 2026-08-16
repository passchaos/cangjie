//! ContextSubst format-1/2 class accelerator construction.

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
) (Error || std.mem.Allocator.Error)![]model.ContextClassSubtable {
    const subtables =
        try allocator.alloc(model.ContextClassSubtable, subtable_count);
    @memset(subtables, .{});
    var built_count: usize = 0;
    errdefer {
        ownership.deinitContextClassSubtableContents(
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
            5,
        );
        subtable.* = try buildSubtable(view, offset, allocator) orelse {
            // Allocate the successful empty result before releasing partial
            // state. If allocation fails, the outer errdefer still owns and
            // releases that state exactly once.
            const empty =
                try allocator.alloc(model.ContextClassSubtable, 0);
            ownership.deinitContextClassSubtableContents(
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
) (Error || std.mem.Allocator.Error)!?model.ContextClassSubtable {
    return switch (try view.readU16(subtable_offset)) {
        1 => try buildGlyphRules(view, subtable_offset, allocator),
        2 => try buildClassRules(view, subtable_offset, allocator),
        else => null,
    };
}

fn buildGlyphRules(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ContextClassSubtable {
    const coverage_offset = try requiredCoverage(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    // Coverage format 2 may legally overlap, in which case the first matching
    // range selects the RuleSet. Keep that uncommon topology on the generic
    // parser instead of collapsing authored coverage indexes by glyph.
    if (try view.readU16(coverage_offset) != 1) return null;
    const set_count = try view.readU16(subtable_offset + 4);

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
            try view.readU16(subtable_offset + 6 + set_index * 2);
        if (set_relative == 0) continue;
        const set_offset = subtable_offset + set_relative;
        const rule_count = try view.readU16(set_offset);
        for (0..rule_count) |rule_index| {
            const rule_offset = set_offset +
                try view.readU16(set_offset + 2 + rule_index * 2);
            const input_count = try view.readU16(rule_offset);
            if (input_count == 0 or
                input_count > shared.max_region_glyphs)
            {
                return null;
            }
            const subst_count = try view.readU16(rule_offset + 2);
            const classes_start = classes.items.len;
            var hash = opentype_class_context.sequenceHashEmpty();
            for (1..input_count) |input_index| {
                const glyph = try view.readU16(
                    rule_offset + 4 + (input_index - 1) * 2,
                );
                try classes.append(allocator, glyph);
                hash = opentype_class_context.sequenceHashAppend(hash, glyph);
            }
            try rules.append(allocator, .{
                .class_set = @intCast(set_index),
                .input_count = input_count,
                .lookahead_count = 0,
                .hash = hash,
                .order = order,
                .lookup_index = 0,
                .classes_start = @intCast(classes_start),
                .subst_count = subst_count,
                .records_offset = @intCast(
                    rule_offset + 4 + (@as(usize, input_count) - 1) * 2,
                ),
            });
            order += 1;
        }
    }
    if (rules.items.len == 0) return null;

    try shared.finishRuleGroups(&rules, &groups, allocator);
    const first_index_start = try first_index.appendGlyphIndex(
        view,
        coverage_offset,
        groups.items,
        &classes,
        allocator,
    );
    const rules_slice = try rules.toOwnedSlice(allocator);
    errdefer allocator.free(rules_slice);
    const classes_slice = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(classes_slice);
    const groups_slice = try groups.toOwnedSlice(allocator);
    success = true;

    return .{
        .subtable_offset = subtable_offset,
        .first_index_start = first_index_start,
        .class_def = table.class_def.empty_offset,
        .rules = rules_slice,
        .classes = classes_slice,
        .groups = groups_slice,
    };
}

fn buildClassRules(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ContextClassSubtable {
    const coverage_offset = try requiredCoverage(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 4),
    );
    const set_count = try view.readU16(subtable_offset + 6);

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
            try view.readU16(subtable_offset + 8 + set_index * 2);
        if (set_relative == 0) continue;
        const set_offset = subtable_offset + set_relative;
        const rule_count = try view.readU16(set_offset);
        for (0..rule_count) |rule_index| {
            const rule_offset = set_offset +
                try view.readU16(set_offset + 2 + rule_index * 2);
            const input_count = try view.readU16(rule_offset);
            if (input_count == 0 or
                input_count > shared.max_region_glyphs)
            {
                return null;
            }
            const subst_count = try view.readU16(rule_offset + 2);
            const classes_start = classes.items.len;
            var hash = opentype_class_context.sequenceHashEmpty();
            for (1..input_count) |input_index| {
                const class = try view.readU16(
                    rule_offset + 4 + (input_index - 1) * 2,
                );
                try classes.append(allocator, class);
                hash = opentype_class_context.sequenceHashAppend(hash, class);
            }
            try rules.append(allocator, .{
                .class_set = @intCast(set_index),
                .input_count = input_count,
                .lookahead_count = 0,
                .hash = hash,
                .order = order,
                .lookup_index = 0,
                .classes_start = @intCast(classes_start),
                .subst_count = subst_count,
                .records_offset = @intCast(
                    rule_offset + 4 + (@as(usize, input_count) - 1) * 2,
                ),
            });
            order += 1;
        }
    }
    if (rules.items.len == 0) return null;

    try shared.finishRuleGroups(&rules, &groups, allocator);
    const first_index_start = try first_index.appendClassIndex(
        view,
        coverage_offset,
        class_def,
        groups.items,
        &classes,
        allocator,
    );
    const rules_slice = try rules.toOwnedSlice(allocator);
    errdefer allocator.free(rules_slice);
    const classes_slice = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(classes_slice);
    const groups_slice = try groups.toOwnedSlice(allocator);
    success = true;

    return .{
        .subtable_offset = subtable_offset,
        .first_index_start = first_index_start,
        .class_def = class_def,
        .rules = rules_slice,
        .classes = classes_slice,
        .groups = groups_slice,
    };
}

fn requiredCoverage(
    view: View,
    base: usize,
    relative: u16,
) Error!usize {
    return table.offset.required16(view, base, relative);
}
