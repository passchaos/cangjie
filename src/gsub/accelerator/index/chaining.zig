//! Chaining-context first-glyph and first-pair indexes.

const std = @import("std");
const GlyphDigest = @import("../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const model = @import("../model.zig");

pub const min_groups_for_hash = 8;

pub fn buildGroups(
    pairs: []model.ChainingPair,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]model.ChainingGroup {
    if (pairs.len == 0) return allocator.alloc(model.ChainingGroup, 0);
    std.sort.heap(model.ChainingPair, pairs, {}, lessPair);

    var group_count: usize = 1;
    var previous = pairs[0].glyph;
    for (pairs[1..]) |pair| {
        if (pair.glyph == previous) continue;
        group_count += 1;
        previous = pair.glyph;
    }
    const groups = try allocator.alloc(model.ChainingGroup, group_count);
    var built: usize = 0;
    errdefer {
        for (groups[0..built]) |group| allocator.free(group.subtable_indices);
        allocator.free(groups);
    }
    var pair_index: usize = 0;
    for (groups) |*group| {
        const glyph = pairs[pair_index].glyph;
        const start = pair_index;
        while (pair_index < pairs.len and
            pairs[pair_index].glyph == glyph) : (pair_index += 1)
        {}
        const indices = try allocator.alloc(u16, pair_index - start);
        for (indices, 0..) |*index, offset| {
            index.* = pairs[start + offset].subtable_index;
        }
        group.* = .{ .glyph = glyph, .subtable_indices = indices };
        built += 1;
    }
    return groups;
}

pub fn buildPairGroups(
    pairs: []model.ChainingPairEntry,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]model.ChainingPairGroup {
    if (pairs.len == 0) return allocator.alloc(model.ChainingPairGroup, 0);
    std.sort.heap(model.ChainingPairEntry, pairs, {}, lessPairEntry);

    var group_count: usize = 1;
    var previous_first = pairs[0].first;
    var previous_second = pairs[0].second;
    for (pairs[1..]) |pair| {
        if (pair.first == previous_first and pair.second == previous_second) {
            continue;
        }
        group_count += 1;
        previous_first = pair.first;
        previous_second = pair.second;
    }
    const groups = try allocator.alloc(model.ChainingPairGroup, group_count);
    var built: usize = 0;
    errdefer {
        for (groups[0..built]) |group| allocator.free(group.subtable_indices);
        allocator.free(groups);
    }
    var pair_index: usize = 0;
    for (groups) |*group| {
        const first = pairs[pair_index].first;
        const second = pairs[pair_index].second;
        const start = pair_index;
        while (pair_index < pairs.len and
            pairs[pair_index].first == first and
            pairs[pair_index].second == second) : (pair_index += 1)
        {}
        const indices = try allocator.alloc(u16, pair_index - start);
        for (indices, 0..) |*index, offset| {
            index.* = pairs[start + offset].subtable_index;
        }
        group.* = .{
            .first = first,
            .second = second,
            .subtable_indices = indices,
        };
        built += 1;
    }
    return groups;
}

pub fn fillSecondInputMetadata(
    groups: []model.ChainingGroup,
    subtables: []const model.ChainingCoverageSubtable,
) void {
    for (groups) |*group| {
        var digest = GlyphDigest.empty();
        var has_second = false;
        var has_no_second = false;
        for (group.subtable_indices) |subtable_index| {
            if (subtable_index >= subtables.len or
                subtables[subtable_index].input_count <= 1)
            {
                has_no_second = true;
                continue;
            }
            has_second = true;
            digest.unionWith(subtables[subtable_index].second_input_digest);
        }
        group.has_no_second_input = has_no_second;
        if (has_second) group.second_input_digest = digest;
    }
}

pub fn buildSlots(
    groups: []const model.ChainingGroup,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    if (groups.len < min_groups_for_hash or
        groups.len > std.math.maxInt(u16))
    {
        return allocator.alloc(u16, 0);
    }
    const slots = try allocSlots(groups.len, allocator);
    for (groups, 0..) |group, group_index| {
        var slot = hashGlyph(group.glyph) & (slots.len - 1);
        while (slots[slot] != 0) slot = (slot + 1) & (slots.len - 1);
        slots[slot] = @intCast(group_index + 1);
    }
    return slots;
}

pub fn buildPairSlots(
    groups: []const model.ChainingPairGroup,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    if (groups.len < min_groups_for_hash or
        groups.len > std.math.maxInt(u16))
    {
        return allocator.alloc(u16, 0);
    }
    const slots = try allocSlots(groups.len, allocator);
    for (groups, 0..) |group, group_index| {
        var slot = hashPair(group.first, group.second) & (slots.len - 1);
        while (slots[slot] != 0) slot = (slot + 1) & (slots.len - 1);
        slots[slot] = @intCast(group_index + 1);
    }
    return slots;
}

pub fn find(
    groups: []const model.ChainingGroup,
    slots: []const u16,
    glyph: GlyphId,
) ?*const model.ChainingGroup {
    if (slots.len != 0) {
        var slot = hashGlyph(glyph) & (slots.len - 1);
        while (slots[slot] != 0) : (slot = (slot + 1) & (slots.len - 1)) {
            const group = &groups[slots[slot] - 1];
            if (group.glyph == glyph) return group;
        }
        return null;
    }
    var low: usize = 0;
    var high: usize = groups.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (glyph < groups[middle].glyph) {
            high = middle;
        } else if (glyph > groups[middle].glyph) {
            low = middle + 1;
        } else {
            return &groups[middle];
        }
    }
    return null;
}

pub fn findIndices(
    groups: []const model.ChainingGroup,
    slots: []const u16,
    glyph: GlyphId,
) ?[]const u16 {
    return (find(groups, slots, glyph) orelse return null).subtable_indices;
}

pub fn findPairIndices(
    groups: []const model.ChainingPairGroup,
    slots: []const u16,
    first: GlyphId,
    second: GlyphId,
) ?[]const u16 {
    if (slots.len != 0) {
        var slot = hashPair(first, second) & (slots.len - 1);
        while (slots[slot] != 0) : (slot = (slot + 1) & (slots.len - 1)) {
            const group = groups[slots[slot] - 1];
            if (group.first == first and group.second == second) {
                return group.subtable_indices;
            }
        }
        return null;
    }
    var low: usize = 0;
    var high: usize = groups.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const group = groups[middle];
        if (first < group.first or
            (first == group.first and second < group.second))
        {
            high = middle;
        } else if (first > group.first or
            (first == group.first and second > group.second))
        {
            low = middle + 1;
        } else {
            return group.subtable_indices;
        }
    }
    return null;
}

fn allocSlots(
    group_count: usize,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    const count = std.math.ceilPowerOfTwo(usize, group_count * 2) catch
        return error.OutOfMemory;
    const slots = try allocator.alloc(u16, count);
    @memset(slots, 0);
    return slots;
}

fn hashGlyph(glyph: GlyphId) usize {
    return @as(usize, glyph) *% 0x9e37;
}

fn hashPair(first: GlyphId, second: GlyphId) usize {
    var mixed = @as(usize, first) *% 0x9e37;
    mixed ^= @as(usize, second) *% 0x85eb;
    return mixed ^ (mixed >> 7);
}

fn lessPair(_: void, lhs: model.ChainingPair, rhs: model.ChainingPair) bool {
    if (lhs.glyph != rhs.glyph) return lhs.glyph < rhs.glyph;
    return lhs.subtable_index < rhs.subtable_index;
}

fn lessPairEntry(
    _: void,
    lhs: model.ChainingPairEntry,
    rhs: model.ChainingPairEntry,
) bool {
    if (lhs.first != rhs.first) return lhs.first < rhs.first;
    if (lhs.second != rhs.second) return lhs.second < rhs.second;
    return lhs.subtable_index < rhs.subtable_index;
}
