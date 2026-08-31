//! GPOS accelerator model ownership contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const class_context = @import("../../../opentype/class_context.zig");

test "lookup model releases its complete nested ownership graph" {
    const allocator = std.testing.allocator;
    const lookups = try allocator.alloc(accelerator.Lookup, 1);
    lookups[0] = .{
        .coverage_groups = try ownedGroups(allocator, 10),
        .coverage_group_slots = try allocator.dupe(u16, &.{1}),
        .coverage_group_direct = try allocator.dupe(u16, &.{1}),
        .single_pos_subtables = try allocator.alloc(
            accelerator.model.SinglePositionSubtable,
            1,
        ),
        .pair_pos_subtables = try allocator.alloc(
            accelerator.model.PairPositionSubtable,
            1,
        ),
        .pair_pos_records = try allocator.dupe(
            accelerator.model.PairPositionRecord,
            &.{.{ .first = 10, .second = 20, .x_advance = -30 }},
        ),
        .pair_pos_coverage_classes = try allocator.dupe(
            accelerator.model.PairClassEntry,
            &.{.{ .glyph = 10, .class = 1 }},
        ),
        .pair_pos_class_entries = try allocator.dupe(
            accelerator.model.PairClassEntry,
            &.{.{ .glyph = 20, .class = 2 }},
        ),
        .pair_pos_class_matrix = try allocator.dupe(i16, &.{ -30, 0 }),
        .cursive_subtables = try ownedCursiveSubtables(allocator),
        .mark_to_base_subtables = try ownedMarkToBaseSubtables(allocator),
        .mark_to_mark_subtables = try ownedMarkToMarkSubtables(allocator),
        .context_class_subtables = try ownedContextClassSubtables(allocator),
        .chaining_subtables = try ownedChainingSubtables(allocator),
        .chaining_groups = try ownedGroups(allocator, 20),
        .chaining_group_slots = try allocator.dupe(u16, &.{1}),
        .chaining_second_groups = try ownedGroups(allocator, 30),
        .chaining_second_group_slots = try allocator.dupe(u16, &.{1}),
        .chaining_class_subtables = try ownedChainingClassSubtables(allocator),
    };
    @memset(
        @constCast(lookups[0].single_pos_subtables),
        .{},
    );
    @memset(
        @constCast(lookups[0].pair_pos_subtables),
        .{},
    );

    // std.testing.allocator turns every missed nested free into a test failure.
    accelerator.model.deinitLookups(lookups, allocator);
}

fn ownedContextClassSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.ContextClassSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.ContextClassSubtable, 1);
    subtables[0] = .{
        .coverage = .{ .glyphs = try allocator.dupe(u16, &.{4}) },
        .rules = try allocator.alloc(accelerator.model.ContextClassRule, 1),
        .groups = try allocator.alloc(class_context.RuleGroup, 1),
    };
    return subtables;
}

fn ownedGroups(
    allocator: std.mem.Allocator,
    glyph: u16,
) ![]accelerator.glyph_groups.Group {
    const groups = try allocator.alloc(accelerator.glyph_groups.Group, 1);
    groups[0] = .{
        .glyph = glyph,
        .subtable_indices = try allocator.dupe(u16, &.{ 0, 2 }),
    };
    return groups;
}

fn ownedCursiveSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.CursivePositionSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.CursivePositionSubtable, 1);
    subtables[0] = .{
        .subtable_offset = 10,
        .coverage_offset = 20,
        .entry_exit_count = 1,
        .coverage = .{
            .glyphs = try allocator.dupe(u16, &.{5}),
        },
    };
    return subtables;
}

fn ownedMarkToBaseSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.MarkToBaseSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.MarkToBaseSubtable, 1);
    subtables[0] = .{
        .mark_coverage = .{
            .glyphs = try allocator.dupe(u16, &.{5}),
        },
        .base_coverage = .{
            .glyphs = try allocator.dupe(u16, &.{6}),
        },
    };
    return subtables;
}

fn ownedMarkToMarkSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.MarkToMarkSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.MarkToMarkSubtable, 1);
    subtables[0] = .{
        .mark_1_coverage = .{
            .glyphs = try allocator.dupe(u16, &.{5}),
        },
        .mark_2_coverage = .{
            .glyphs = try allocator.dupe(u16, &.{6}),
        },
    };
    return subtables;
}

fn ownedChainingSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.ChainingCoverageSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.ChainingCoverageSubtable, 1);
    subtables[0] = .{
        .backtrack_coverages = try ownedCoverageSequence(allocator, 1),
        .input_coverages = try ownedCoverageSequence(allocator, 2),
        .lookahead_coverages = try ownedCoverageSequence(allocator, 3),
    };
    return subtables;
}

fn ownedCoverageSequence(
    allocator: std.mem.Allocator,
    glyph: u16,
) ![]accelerator.coverage.Owned {
    const sequence = try allocator.alloc(accelerator.coverage.Owned, 1);
    sequence[0] = .{
        .glyphs = try allocator.dupe(u16, &.{glyph}),
    };
    return sequence;
}

fn ownedChainingClassSubtables(
    allocator: std.mem.Allocator,
) ![]accelerator.model.ChainingClassSubtable {
    const subtables =
        try allocator.alloc(accelerator.model.ChainingClassSubtable, 1);
    subtables[0] = .{
        .rules = try allocator.alloc(class_context.Rule, 1),
        .classes = try allocator.dupe(u16, &.{1}),
        .groups = try allocator.alloc(class_context.RuleGroup, 1),
    };
    return subtables;
}
