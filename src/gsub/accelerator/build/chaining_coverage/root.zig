//! ChainContextSubst format-3 lookup accelerator construction.

const std = @import("std");
const fast_single = @import("fast_single.zig");
const GlyphDigest = @import("../../../../glyph_digest.zig").GlyphDigest;
const chaining_index = @import("../../index/chaining.zig");
const model = @import("../../model.zig");
pub const coverage_pairs = @import("pairs.zig");
pub const parser = @import("parser.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;
pub fn build(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    extension_wrapped: bool,
    single_subst: model.SingleSubstitution,
    extension_lookup_type: ?u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.Lookup {
    var digest = GlyphDigest.empty();
    var group_pairs = std.ArrayList(model.ChainingPair).empty;
    errdefer group_pairs.deinit(allocator);
    var pair_pairs = std.ArrayList(model.ChainingPairEntry).empty;
    errdefer pair_pairs.deinit(allocator);
    var pair_index_complete = true;
    const subtable_digests = try allocator.alloc(GlyphDigest, subtable_count);
    errdefer allocator.free(subtable_digests);
    @memset(subtable_digests, .{});
    const subtables = try allocator.alloc(
        model.ChainingCoverageSubtable,
        subtable_count,
    );
    errdefer allocator.free(subtables);
    @memset(subtables, .{});
    var saw_input_coverage = false;
    var needs_second_input = false;
    var needs_backtrack = false;
    var needs_single_input_lookahead = false;

    for (subtables, 0..) |*subtable, subtable_index| {
        const raw = try requiredSubtable(view, lookup_offset, subtable_index);
        const offset = if (extension_wrapped)
            try extensionPayload(view, raw, 6)
        else
            raw;
        subtable.* = try parser.parse(view, offset) orelse continue;
        try fast_single.fill(view, subtable);
        const first_coverage = try requiredCoverageAt(
            view,
            offset,
            subtable.input_offsets_pos,
        );
        try coverage_pairs.appendFirst(
            view,
            first_coverage,
            @intCast(subtable_index),
            &group_pairs,
            allocator,
        );
        if (subtable.input_count > 1) {
            needs_second_input = true;
            const second_coverage = try requiredCoverageAt(
                view,
                offset,
                subtable.input_offsets_pos + 2,
            );
            subtable.second_input_coverage_offset = second_coverage;
            subtable.second_input_digest =
                try table.coverage.digest(view, second_coverage);
            if (pair_index_complete) {
                pair_index_complete = try coverage_pairs.appendPair(
                    view,
                    first_coverage,
                    second_coverage,
                    @intCast(subtable_index),
                    &pair_pairs,
                    allocator,
                );
            }
        } else {
            pair_index_complete = false;
        }
        if (subtable.input_count > 2) {
            const third_coverage = try requiredCoverageAt(
                view,
                offset,
                subtable.input_offsets_pos + 4,
            );
            subtable.third_input_coverage_offset = third_coverage;
            subtable.third_input_digest =
                try table.coverage.digest(view, third_coverage);
        }
        if (subtable.backtrack_count != 0) {
            needs_backtrack = true;
            const coverage = try requiredCoverageAt(
                view,
                offset,
                subtable.backtrack_offsets_pos,
            );
            subtable.first_backtrack_digest =
                try table.coverage.digest(view, coverage);
        }
        if (subtable.input_count == 1 and subtable.lookahead_count != 0) {
            needs_single_input_lookahead = true;
            const coverage = try requiredCoverageAt(
                view,
                offset,
                subtable.lookahead_offsets_pos,
            );
            subtable.first_lookahead_digest =
                try table.coverage.digest(view, coverage);
        }
        const subtable_digest = try table.coverage.digest(view, first_coverage);
        subtable_digests[subtable_index] = subtable_digest;
        digest.unionWith(subtable_digest);
        saw_input_coverage = true;
    }
    if (!saw_input_coverage or digest.isEmpty()) {
        group_pairs.deinit(allocator);
        allocator.free(subtable_digests);
        allocator.free(subtables);
        return .{};
    }

    const groups = try chaining_index.buildGroups(group_pairs.items, allocator);
    group_pairs.deinit(allocator);
    errdefer deinitGroups(allocator, groups);
    chaining_index.fillSecondInputMetadata(groups, subtables);
    const group_slots = try chaining_index.buildSlots(groups, allocator);
    errdefer allocator.free(group_slots);
    const pair_groups = if (pair_index_complete)
        try chaining_index.buildPairGroups(pair_pairs.items, allocator)
    else
        try allocator.alloc(model.ChainingPairGroup, 0);
    pair_pairs.deinit(allocator);
    errdefer deinitPairGroups(allocator, pair_groups);
    const pair_slots = if (pair_index_complete)
        try chaining_index.buildPairSlots(pair_groups, allocator)
    else
        try allocator.alloc(u16, 0);
    errdefer allocator.free(pair_slots);

    return .{
        .single_subst = single_subst,
        .extension_lookup_type = extension_lookup_type,
        .chaining_coverage_only = true,
        .chaining_needs_second_input = needs_second_input,
        .chaining_needs_backtrack = needs_backtrack,
        .chaining_needs_single_input_lookahead = needs_single_input_lookahead,
        .chaining_input_digest = digest,
        .chaining_subtable_digests = subtable_digests,
        .chaining_subtables = subtables,
        .chaining_groups = groups,
        .chaining_group_slots = group_slots,
        .chaining_pair_groups = pair_groups,
        .chaining_pair_group_slots = pair_slots,
        .chaining_pair_index_complete = pair_index_complete,
    };
}

pub fn lookupUsesCoverageOnly(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    extension_wrapped: bool,
) Error!bool {
    for (0..subtable_count) |subtable_index| {
        const raw = try requiredSubtable(view, lookup_offset, subtable_index);
        const offset = if (extension_wrapped)
            try extensionPayload(view, raw, 6)
        else
            raw;
        if (try view.readU16(offset) != 3) return false;
    }
    return true;
}

pub fn appendCoveragePairs(
    view: View,
    coverage: usize,
    subtable_index: u16,
    output: *std.ArrayList(model.ChainingPair),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    return coverage_pairs.appendFirst(
        view,
        coverage,
        subtable_index,
        output,
        allocator,
    );
}

fn requiredCoverageAt(
    view: View,
    subtable_offset: usize,
    offset_position: usize,
) Error!usize {
    return table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(offset_position),
    );
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

fn extensionPayload(
    view: View,
    wrapper: usize,
    expected_type: u16,
) Error!usize {
    if (try view.readU16(wrapper) != 1 or
        try view.readU16(wrapper + 2) != expected_type)
    {
        return error.UnsupportedGsub;
    }
    return table.offset.extensionPayload(
        view,
        wrapper,
        try view.readU32(wrapper + 4),
    );
}

fn deinitGroups(
    allocator: std.mem.Allocator,
    groups: []model.ChainingGroup,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
    allocator.free(groups);
}

fn deinitPairGroups(
    allocator: std.mem.Allocator,
    groups: []model.ChainingPairGroup,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
    allocator.free(groups);
}
