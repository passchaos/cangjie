//! GSUB accelerator ownership-release contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const class_context = @import("../../../opentype/class_context.zig");

test "ownership releases a complete nested lookup graph" {
    const allocator = std.testing.allocator;
    const lookups = try allocator.alloc(acceleration.Lookup, 1);
    lookups[0] = .{};

    lookups[0].single_subst_entries =
        try allocator.dupe(acceleration.model.SingleEntry, &.{
            .{ .from = 1, .to = 2 },
        });
    lookups[0].multiple_subst.entries =
        try allocator.dupe(acceleration.model.MultipleEntry, &.{
            .{ .glyph = 2, .sequence_offset = 4, .glyph_count = 1 },
        });
    lookups[0].ligature_subst.sets =
        try allocator.dupe(acceleration.model.LigatureSet, &.{
            .{ .glyph = 3, .definition_start = 0, .definition_len = 1 },
        });
    lookups[0].ligature_subst.set_slots = try allocator.dupe(u16, &.{1});
    lookups[0].ligature_subst.definitions =
        try allocator.dupe(acceleration.model.LigatureDefinition, &.{
            .{ .ligature = 4, .component_start = 0, .component_count = 1 },
        });
    lookups[0].ligature_subst.components = try allocator.dupe(u16, &.{5});

    const context_subtables =
        try allocator.alloc(acceleration.model.ContextClassSubtable, 1);
    context_subtables[0] = .{
        .rules = try allocator.alloc(class_context.Rule, 1),
        .classes = try allocator.dupe(u16, &.{6}),
        .groups = try allocator.alloc(class_context.RuleGroup, 1),
    };
    lookups[0].context_class_subtables = context_subtables;
    lookups[0].context_coverage_subtables =
        try allocator.alloc(acceleration.model.ContextCoverageSubtable, 1);
    lookups[0].context_coverage_offsets = try allocator.dupe(usize, &.{7});
    lookups[0].context_groups = try ownedGroups(allocator, 8);
    lookups[0].context_group_slots = try allocator.dupe(u16, &.{1});

    lookups[0].chaining_subtable_digests =
        try allocator.alloc(@import("../../../glyph_digest.zig").GlyphDigest, 1);
    lookups[0].chaining_subtables =
        try allocator.alloc(acceleration.model.ChainingCoverageSubtable, 1);
    lookups[0].chaining_groups = try ownedGroups(allocator, 9);
    lookups[0].chaining_group_slots = try allocator.dupe(u16, &.{1});

    const pair_groups =
        try allocator.alloc(acceleration.model.ChainingPairGroup, 1);
    pair_groups[0] = .{
        .first = 10,
        .second = 11,
        .subtable_indices = try allocator.dupe(u16, &.{0}),
    };
    lookups[0].chaining_pair_groups = pair_groups;
    lookups[0].chaining_pair_group_slots = try allocator.dupe(u16, &.{1});

    const chaining_subtables =
        try allocator.alloc(acceleration.model.ChainingClassSubtable, 1);
    chaining_subtables[0] = .{
        .rules = try allocator.alloc(class_context.Rule, 1),
        .classes = try allocator.dupe(u16, &.{12}),
        .groups = try allocator.alloc(class_context.RuleGroup, 1),
    };
    lookups[0].chaining_class_subtables = chaining_subtables;
    lookups[0].reverse_chaining_subtables =
        try allocator.alloc(acceleration.model.ReverseChainingSingleSubtable, 1);
    lookups[0].reverse_chaining_exact_contexts =
        try allocator.alloc(acceleration.model.ReverseChainingContextEntry, 1);
    lookups[0].reverse_chaining_groups = try ownedGroups(allocator, 13);

    acceleration.ownership.deinit(allocator, lookups);
}

test "contents release preserves caller-owned outer lookup storage" {
    const allocator = std.testing.allocator;
    var lookups = [_]acceleration.Lookup{.{
        .single_subst_entries = try allocator.dupe(acceleration.model.SingleEntry, &.{
            .{ .from = 1, .to = 2 },
        }),
    }};

    acceleration.ownership.deinitContents(allocator, &lookups);
    // Stack storage remains valid because only nested allocations are owned.
    lookups[0] = .{};
}

fn ownedGroups(
    allocator: std.mem.Allocator,
    glyph: u16,
) ![]acceleration.model.ChainingGroup {
    const groups = try allocator.alloc(acceleration.model.ChainingGroup, 1);
    groups[0] = .{
        .glyph = glyph,
        .subtable_indices = try allocator.dupe(u16, &.{0}),
    };
    return groups;
}
