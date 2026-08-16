//! Ownership release for decoded GSUB accelerator sidecars.
//!
//! Builders may stop after any successfully completed lookup or contextual
//! subtable. `deinit*Contents` therefore releases nested allocations without
//! assuming ownership of the outer slice, while `deinit*` additionally frees
//! that slice. All ownership remains expressed through concrete model types.

const std = @import("std");
const feature_index = @import("feature_index.zig");
const model = @import("model.zig");

pub fn deinit(allocator: std.mem.Allocator, lookups: []model.Lookup) void {
    deinitContents(allocator, lookups);
    allocator.free(lookups);
}

pub fn deinitContents(
    allocator: std.mem.Allocator,
    lookups: []const model.Lookup,
) void {
    for (lookups, 0..) |lookup, lookup_index| {
        // Feature indexing is table-wide and is intentionally stored only on
        // lookup zero. Do not inspect copied non-zero entries for ownership.
        if (lookup_index == 0) {
            if (lookup.feature_index) |index| {
                feature_index.destroy(index, allocator);
            }
        }
        allocator.free(lookup.single_subst_entries);
        allocator.free(lookup.multiple_subst.entries);
        allocator.free(lookup.ligature_subst.sets);
        allocator.free(lookup.ligature_subst.set_slots);
        allocator.free(lookup.ligature_subst.definitions);
        allocator.free(lookup.ligature_subst.components);
        deinitContextClassSubtables(allocator, lookup.context_class_subtables);
        allocator.free(lookup.context_coverage_subtables);
        allocator.free(lookup.context_coverage_offsets);
        deinitGroups(allocator, lookup.context_groups);
        allocator.free(lookup.context_group_slots);
        allocator.free(lookup.chaining_subtable_digests);
        allocator.free(lookup.chaining_subtables);
        deinitGroups(allocator, lookup.chaining_groups);
        allocator.free(lookup.chaining_group_slots);
        deinitPairGroups(allocator, lookup.chaining_pair_groups);
        allocator.free(lookup.chaining_pair_group_slots);
        deinitChainingClassSubtables(
            allocator,
            lookup.chaining_class_subtables,
        );
        allocator.free(lookup.reverse_chaining_subtables);
        allocator.free(lookup.reverse_chaining_exact_contexts);
        deinitGroups(allocator, lookup.reverse_chaining_groups);
    }
}

pub fn deinitContextClassSubtables(
    allocator: std.mem.Allocator,
    subtables: []const model.ContextClassSubtable,
) void {
    deinitContextClassSubtableContents(allocator, subtables);
    allocator.free(subtables);
}

pub fn deinitContextClassSubtableContents(
    allocator: std.mem.Allocator,
    subtables: []const model.ContextClassSubtable,
) void {
    for (subtables) |subtable| {
        allocator.free(subtable.rules);
        allocator.free(subtable.classes);
        allocator.free(subtable.groups);
    }
}

pub fn deinitChainingClassSubtables(
    allocator: std.mem.Allocator,
    subtables: []const model.ChainingClassSubtable,
) void {
    deinitChainingClassSubtableContents(allocator, subtables);
    allocator.free(subtables);
}

pub fn deinitChainingClassSubtableContents(
    allocator: std.mem.Allocator,
    subtables: []const model.ChainingClassSubtable,
) void {
    for (subtables) |subtable| {
        allocator.free(subtable.rules);
        allocator.free(subtable.classes);
        allocator.free(subtable.groups);
    }
}

fn deinitGroups(
    allocator: std.mem.Allocator,
    groups: []const model.ChainingGroup,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
    allocator.free(groups);
}

fn deinitPairGroups(
    allocator: std.mem.Allocator,
    groups: []const model.ChainingPairGroup,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
    allocator.free(groups);
}
