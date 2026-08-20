//! ContextSubst format-3 coverage accelerator construction.

const std = @import("std");
const chaining_index = @import("../index/chaining.zig");
const model = @import("../model.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub const Data = struct {
    subtables: []model.ContextCoverageSubtable,
    coverage_offsets: []usize,
    groups: []model.ChainingGroup,
    group_slots: []u16,

    pub fn deinit(self: *Data, allocator: std.mem.Allocator) void {
        allocator.free(self.group_slots);
        for (self.groups) |group| allocator.free(group.subtable_indices);
        allocator.free(self.groups);
        allocator.free(self.coverage_offsets);
        allocator.free(self.subtables);
        self.* = .{
            .subtables = &.{},
            .coverage_offsets = &.{},
            .groups = &.{},
            .group_slots = &.{},
        };
    }
};

/// Direct slots store `group_index + 1`; zero remains the miss sentinel.
/// Cap each compact glyph space at 8 KiB.
pub const max_direct_group_slots = 4096;

pub fn build(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Data {
    for (0..subtable_count) |subtable_index| {
        const subtable = try requiredSubtable(
            view,
            lookup_offset,
            subtable_index,
        );
        if (try view.readU16(subtable) != 3) return empty(allocator);
    }

    const subtables =
        try allocator.alloc(model.ContextCoverageSubtable, subtable_count);
    errdefer allocator.free(subtables);
    @memset(subtables, .{});
    var coverage_offsets = std.ArrayList(usize).empty;
    errdefer coverage_offsets.deinit(allocator);
    var pairs = std.ArrayList(model.ChainingPair).empty;
    errdefer pairs.deinit(allocator);

    for (subtables, 0..) |*subtable, subtable_index| {
        const offset = try requiredSubtable(
            view,
            lookup_offset,
            subtable_index,
        );
        const glyph_count = try view.readU16(offset + 2);
        if (glyph_count == 0 or glyph_count > 64) {
            return error.UnsupportedGsub;
        }
        const coverage_start = coverage_offsets.items.len;
        try coverage_offsets.ensureUnusedCapacity(allocator, glyph_count);
        for (0..glyph_count) |coverage_index| {
            const coverage = try table.offset.required16(
                view,
                offset,
                try view.readU16(offset + 6 + coverage_index * 2),
            );
            coverage_offsets.appendAssumeCapacity(coverage);
            if (coverage_index == 0) {
                try appendCoveragePairs(
                    view,
                    coverage,
                    @intCast(subtable_index),
                    &pairs,
                    allocator,
                );
            }
        }
        subtable.* = .{
            .glyph_count = glyph_count,
            .coverage_start = coverage_start,
            .subst_count = try view.readU16(offset + 4),
            .records_pos = offset + 6 + @as(usize, glyph_count) * 2,
        };
    }

    const groups = try chaining_index.buildGroups(pairs.items, allocator);
    pairs.deinit(allocator);
    errdefer {
        for (groups) |group| allocator.free(group.subtable_indices);
        allocator.free(groups);
    }
    const slots = try buildDirectSlots(groups, allocator);
    errdefer allocator.free(slots);
    return .{
        .subtables = subtables,
        .coverage_offsets = try coverage_offsets.toOwnedSlice(allocator),
        .groups = groups,
        .group_slots = slots,
    };
}

pub fn buildDirectSlots(
    groups: []const model.ChainingGroup,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    if (groups.len == 0 or
        groups[groups.len - 1].glyph >= max_direct_group_slots or
        groups.len > std.math.maxInt(u16))
    {
        return allocator.alloc(u16, 0);
    }
    const slots =
        try allocator.alloc(u16, @as(usize, groups[groups.len - 1].glyph) + 1);
    @memset(slots, 0);
    for (groups, 0..) |group, group_index| {
        slots[group.glyph] = @intCast(group_index + 1);
    }
    return slots;
}

fn appendCoveragePairs(
    view: View,
    coverage_offset: usize,
    subtable_index: u16,
    pairs: *std.ArrayList(model.ChainingPair),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    const count = try table.coverage.glyphCount(view, coverage_offset);
    try pairs.ensureUnusedCapacity(allocator, count);
    for (0..count) |coverage_index| {
        pairs.appendAssumeCapacity(.{
            .glyph = (try table.coverage.glyphAt(
                view,
                coverage_offset,
                coverage_index,
            )) orelse return error.BadGsub,
            .subtable_index = subtable_index,
        });
    }
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

fn empty(allocator: std.mem.Allocator) std.mem.Allocator.Error!Data {
    return .{
        .subtables = try allocator.alloc(model.ContextCoverageSubtable, 0),
        .coverage_offsets = try allocator.alloc(usize, 0),
        .groups = try allocator.alloc(model.ChainingGroup, 0),
        .group_slots = try allocator.alloc(u16, 0),
    };
}
