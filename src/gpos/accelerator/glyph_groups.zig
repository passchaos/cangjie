//! Exact first-glyph index for GPOS lookup subtable candidates.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const owned_coverage = @import("coverage.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub const Group = struct {
    glyph: GlyphId,
    subtable_indices: []const u16,
};

pub const Pair = struct {
    glyph: GlyphId,
    subtable_index: u16,
};

pub const min_groups_for_hash = 8;
pub const max_direct_glyphs = 4096;

/// Append `(covered glyph, subtable index)` pairs from an indexed Coverage.
pub fn appendCoveragePairs(
    view: View,
    coverage_offset: usize,
    subtable_index: u16,
    pairs: *std.ArrayList(Pair),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    const format = try view.readU16(coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try view.readU16(coverage_offset + 2);
            if (!view.assume_validated) {
                try table.coverage.validateFormat1Order(
                    view,
                    coverage_offset,
                    glyph_count,
                    .indexed,
                );
            }
            try pairs.ensureUnusedCapacity(allocator, glyph_count);
            for (0..glyph_count) |glyph_index| {
                pairs.appendAssumeCapacity(.{
                    .glyph = try view.readU16(
                        coverage_offset + 4 + glyph_index * 2,
                    ),
                    .subtable_index = subtable_index,
                });
            }
        },
        2 => {
            const range_count = try view.readU16(coverage_offset + 2);
            if (!view.assume_validated) {
                try table.coverage.validateFormat2Ranges(
                    view,
                    coverage_offset,
                    range_count,
                );
            }
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                const start = try view.readU16(range);
                const end = try view.readU16(range + 2);
                const span = @as(usize, end) - @as(usize, start) + 1;
                try pairs.ensureUnusedCapacity(allocator, span);
                for (@as(usize, start)..@as(usize, end) + 1) |glyph| {
                    pairs.appendAssumeCapacity(.{
                        .glyph = @intCast(glyph),
                        .subtable_index = subtable_index,
                    });
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

/// Append membership pairs from a Coverage already decoded by the owning
/// sidecar. This avoids reparsing the font while building secondary indexes.
pub fn appendOwnedCoveragePairs(
    coverage: owned_coverage.Owned,
    subtable_index: u16,
    pairs: *std.ArrayList(Pair),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    try pairs.ensureUnusedCapacity(allocator, coverage.glyphCount());
    switch (coverage) {
        .glyphs => |glyphs| for (glyphs) |glyph| {
            pairs.appendAssumeCapacity(.{
                .glyph = glyph,
                .subtable_index = subtable_index,
            });
        },
        .ranges => |ranges| for (ranges) |range| {
            var glyph: usize = range.start;
            while (glyph <= range.end) : (glyph += 1) {
                pairs.appendAssumeCapacity(.{
                    .glyph = @intCast(glyph),
                    .subtable_index = subtable_index,
                });
            }
        },
        .direct => |indexes| for (indexes, 0..) |one_based, glyph| {
            if (one_based == 0) continue;
            pairs.appendAssumeCapacity(.{
                .glyph = @intCast(glyph),
                .subtable_index = subtable_index,
            });
        },
    }
}

/// Collapse sorted pairs into exact per-glyph candidate slices.
pub fn buildGroups(
    pairs: []Pair,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]Group {
    if (pairs.len == 0) return try allocator.alloc(Group, 0);
    std.sort.heap(Pair, pairs, {}, pairLessThan);

    var group_count: usize = 1;
    var previous_glyph = pairs[0].glyph;
    for (pairs[1..]) |pair| {
        if (pair.glyph == previous_glyph) continue;
        group_count += 1;
        previous_glyph = pair.glyph;
    }

    const groups = try allocator.alloc(Group, group_count);
    var built_count: usize = 0;
    errdefer {
        deinitGroupContents(groups[0..built_count], allocator);
        allocator.free(groups);
    }
    var pair_index: usize = 0;
    for (groups) |*group| {
        const glyph = pairs[pair_index].glyph;
        const start = pair_index;
        while (pair_index < pairs.len and pairs[pair_index].glyph == glyph) {
            pair_index += 1;
        }
        const indices = try allocator.alloc(u16, pair_index - start);
        for (indices, 0..) |*index, candidate_index| {
            index.* = pairs[start + candidate_index].subtable_index;
        }
        group.* = .{ .glyph = glyph, .subtable_indices = indices };
        built_count += 1;
    }
    return groups;
}

pub fn deinitGroups(
    groups: []const Group,
    allocator: std.mem.Allocator,
) void {
    deinitGroupContents(groups, allocator);
    allocator.free(groups);
}

fn deinitGroupContents(
    groups: []const Group,
    allocator: std.mem.Allocator,
) void {
    for (groups) |group| allocator.free(group.subtable_indices);
}

/// Build a bounded open-addressed side index for larger group arrays.
pub fn buildSlots(
    groups: []const Group,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    if (groups.len < min_groups_for_hash or
        groups.len > std.math.maxInt(u16))
    {
        return try allocator.alloc(u16, 0);
    }
    // An empty zero slot and at most 50% load keep successful and negative
    // probes bounded; stored indexes are one-based so zero remains the sentinel.
    const slot_count = std.math.ceilPowerOfTwo(
        usize,
        groups.len * 2,
    ) catch return error.OutOfMemory;
    const slots = try allocator.alloc(u16, slot_count);
    @memset(slots, 0);
    for (groups, 0..) |group, group_index| {
        var slot = hash(group.glyph) & (slots.len - 1);
        while (slots[slot] != 0) slot = (slot + 1) & (slots.len - 1);
        slots[slot] = @intCast(group_index + 1);
    }
    return slots;
}

pub fn buildDirect(
    groups: []const Group,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    // A dense 8 KiB ceiling is small beside the parsed font and replaces a
    // hash probe for the common BMP-sized Latin/Indic glyph spaces. Large or
    // sparse CJK/CID ids retain the existing bounded hash/binary indexes.
    if (groups.len == 0 or groups.len > std.math.maxInt(u16)) {
        return try allocator.alloc(u16, 0);
    }
    const last_glyph: usize = groups[groups.len - 1].glyph;
    if (last_glyph >= max_direct_glyphs) return try allocator.alloc(u16, 0);
    const direct = try allocator.alloc(u16, last_glyph + 1);
    @memset(direct, 0);
    for (groups, 0..) |group, group_index| {
        direct[group.glyph] = @intCast(group_index + 1);
    }
    return direct;
}

pub fn find(
    groups: []const Group,
    slots: []const u16,
    glyph: GlyphId,
) ?[]const u16 {
    return findDirect(groups, slots, &.{}, glyph);
}

pub fn findDirect(
    groups: []const Group,
    slots: []const u16,
    direct: []const u16,
    glyph: GlyphId,
) ?[]const u16 {
    if (direct.len != 0) {
        if (glyph >= direct.len) return null;
        const group_index = direct[glyph];
        return if (group_index == 0)
            null
        else
            groups[group_index - 1].subtable_indices;
    }
    if (slots.len != 0) {
        var slot = hash(glyph) & (slots.len - 1);
        while (slots[slot] != 0) : (slot = (slot + 1) & (slots.len - 1)) {
            const group = groups[slots[slot] - 1];
            if (group.glyph == glyph) return group.subtable_indices;
        }
        return null;
    }

    var low: usize = 0;
    var high = groups.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate = groups[middle].glyph;
        if (glyph < candidate) {
            high = middle;
        } else if (glyph > candidate) {
            low = middle + 1;
        } else {
            return groups[middle].subtable_indices;
        }
    }
    return null;
}

fn pairLessThan(_: void, lhs: Pair, rhs: Pair) bool {
    if (lhs.glyph != rhs.glyph) return lhs.glyph < rhs.glyph;
    return lhs.subtable_index < rhs.subtable_index;
}

fn hash(glyph: GlyphId) usize {
    return @as(usize, glyph) *% 0x9e37;
}
