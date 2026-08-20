//! Extension-wrapped ReverseChainSingleSubst accelerator assembly.

const std = @import("std");
const chaining_coverage = @import("../chaining_coverage/root.zig");
const chaining_index = @import("../../index/chaining.zig");
const extension = @import("extension.zig");
const model = @import("../../model.zig");
const reverse = @import("../reverse.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Lookup = model.Lookup;
pub const View = table.View;

pub fn build(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    base_lookup: Lookup,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Lookup {
    const subtables =
        try allocator.alloc(model.ReverseChainingSingleSubtable, subtable_count);
    errdefer allocator.free(subtables);
    @memset(subtables, .{});
    var pairs = std.ArrayList(model.ChainingPair).empty;
    errdefer pairs.deinit(allocator);
    var exact_contexts =
        std.ArrayList(model.ReverseChainingContextEntry).empty;
    errdefer exact_contexts.deinit(allocator);
    var saw_coverage = false;

    for (subtables, 0..) |*subtable, subtable_index| {
        const wrapper = try requiredSubtable(
            view,
            lookup_offset,
            subtable_index,
        );
        const payload = try extension.payload(view, wrapper, 8);
        subtable.* = try reverse.parse(view, payload);
        try chaining_coverage.appendCoveragePairs(
            view,
            subtable.coverage_offset,
            @intCast(subtable_index),
            &pairs,
            allocator,
        );
        try reverse.appendExact(
            view,
            subtable.*,
            @intCast(subtable_index),
            &exact_contexts,
            allocator,
        );
        saw_coverage = true;
    }
    if (!saw_coverage or pairs.items.len == 0) {
        pairs.deinit(allocator);
        exact_contexts.deinit(allocator);
        allocator.free(subtables);
        return base_lookup;
    }

    const groups = try chaining_index.buildGroups(pairs.items, allocator);
    pairs.deinit(allocator);
    // Later exact-context allocation can still fail. Clear the list after
    // transferring its contents so its errdefer remains safe on that path.
    pairs = .empty;
    errdefer deinitGroups(allocator, groups);
    const exact_slice = if (exact_contexts.items.len == subtable_count)
        try reverse.finish(exact_contexts.items, allocator)
    else
        try allocator.alloc(model.ReverseChainingContextEntry, 0);
    exact_contexts.deinit(allocator);
    exact_contexts = .empty;

    var result = base_lookup;
    result.reverse_chaining_subtables = subtables;
    result.reverse_chaining_groups = groups;
    result.reverse_chaining_exact_contexts = exact_slice;
    return result;
}

fn requiredSubtable(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_offset,
        try view.readU16(lookup_offset + 6 + subtable_index * 2),
    );
}

fn deinitGroups(
    allocator: std.mem.Allocator,
    groups: []const model.ChainingGroup,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
    allocator.free(groups);
}
