//! Compact first-glyph to contextual RuleGroup index.
//!
//! Small indexes use sorted glyph/group pairs; larger indexes use a 50%-load
//! open-addressed table encoded in the same `[]u16` ownership sidecar.

const std = @import("std");
const class_context = @import("../../../opentype/class_context.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub const Entry = struct {
    glyph: GlyphId,
    group_index: u16,
};

pub const min_entries_for_hash = 8;
const empty_group_index = std.math.maxInt(u16);
pub const sorted_encoding: u16 = 0;
pub const hash_encoding: u16 = 1;

pub fn appendClassIndex(
    view: View,
    coverage_offset: usize,
    input_class_def: usize,
    groups: []const class_context.RuleGroup,
    classes: *std.ArrayList(u16),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!usize {
    const coverage_count =
        try table.coverage.glyphCount(view, coverage_offset);
    var entries = try std.ArrayList(Entry).initCapacity(
        allocator,
        coverage_count,
    );
    defer entries.deinit(allocator);

    for (0..coverage_count) |coverage_index| {
        const glyph = (try table.coverage.glyphAt(
            view,
            coverage_offset,
            coverage_index,
        )) orelse return error.BadGsub;
        const class_set =
            try table.class_def.value(view, input_class_def, glyph);
        const group_index = class_context.groupIndexForClass(
            groups,
            class_set,
        ) orelse continue;
        try entries.append(allocator, .{
            .glyph = glyph,
            .group_index = @intCast(group_index),
        });
    }
    std.sort.heap(Entry, entries.items, {}, lessEntry);

    // Overlapping Coverage format-2 ranges are accepted. The RuleGroup depends
    // only on glyph/class, so repeated glyphs collapse to one exact answer.
    var write: usize = 0;
    for (entries.items) |entry| {
        if (write != 0 and entries.items[write - 1].glyph == entry.glyph) {
            continue;
        }
        entries.items[write] = entry;
        write += 1;
    }
    entries.shrinkRetainingCapacity(write);
    return appendPrepared(entries.items, classes, allocator);
}

pub fn appendGlyphIndex(
    view: View,
    coverage_offset: usize,
    groups: []const class_context.RuleGroup,
    classes: *std.ArrayList(u16),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!usize {
    const coverage_count =
        try table.coverage.glyphCount(view, coverage_offset);
    var entries = try std.ArrayList(Entry).initCapacity(
        allocator,
        coverage_count,
    );
    defer entries.deinit(allocator);
    for (0..coverage_count) |coverage_index| {
        const group_index = class_context.groupIndexForClass(
            groups,
            @intCast(coverage_index),
        ) orelse continue;
        try entries.append(allocator, .{
            .glyph = (try table.coverage.glyphAt(
                view,
                coverage_offset,
                coverage_index,
            )) orelse return error.BadGsub,
            .group_index = @intCast(group_index),
        });
    }
    return appendPrepared(entries.items, classes, allocator);
}

pub fn appendPrepared(
    entries: []const Entry,
    classes: *std.ArrayList(u16),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!usize {
    const start = classes.items.len;
    if (entries.len < min_entries_for_hash) {
        try classes.ensureUnusedCapacity(allocator, 1 + entries.len * 2);
        classes.appendAssumeCapacity(sorted_encoding);
        for (entries) |entry| {
            classes.appendAssumeCapacity(entry.glyph);
            classes.appendAssumeCapacity(entry.group_index);
        }
    } else {
        try appendHash(entries, classes, allocator);
    }
    return start;
}

pub fn find(
    classes: []const u16,
    index_start: usize,
    groups: []const class_context.RuleGroup,
    glyph: GlyphId,
) ?class_context.RuleGroup {
    if (index_start >= classes.len) return null;
    const index = classes[index_start..];
    if (index.len == 0 or (index.len - 1) % 2 != 0) return null;
    const group_index = switch (index[0]) {
        hash_encoding => group: {
            const slot_count = (index.len - 1) / 2;
            if (slot_count == 0 or !std.math.isPowerOfTwo(slot_count)) {
                return null;
            }
            var slot = hashGlyph(glyph) & (slot_count - 1);
            while (index[2 + slot * 2] != empty_group_index) : (slot = (slot + 1) & (slot_count - 1)) {
                if (index[1 + slot * 2] == glyph) {
                    break :group index[2 + slot * 2];
                }
            }
            return null;
        },
        sorted_encoding => group: {
            const count = (index.len - 1) / 2;
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const middle = low + (high - low) / 2;
                const candidate = index[1 + middle * 2];
                if (glyph < candidate) {
                    high = middle;
                } else if (glyph > candidate) {
                    low = middle + 1;
                } else {
                    break :group index[2 + middle * 2];
                }
            }
            return null;
        },
        else => return null,
    };
    if (group_index >= groups.len) return null;
    return groups[group_index];
}

pub fn hashGlyph(glyph: GlyphId) usize {
    return @as(usize, glyph) *% 0x9e37;
}

fn appendHash(
    entries: []const Entry,
    classes: *std.ArrayList(u16),
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    const slot_count =
        std.math.ceilPowerOfTwo(usize, entries.len * 2) catch
            return error.OutOfMemory;
    try classes.ensureUnusedCapacity(allocator, 1 + slot_count * 2);
    classes.appendAssumeCapacity(hash_encoding);
    const slots = classes.addManyAsSliceAssumeCapacity(slot_count * 2);
    @memset(slots, 0);
    for (0..slot_count) |slot| {
        slots[slot * 2 + 1] = empty_group_index;
    }
    for (entries) |entry| {
        var slot = hashGlyph(entry.glyph) & (slot_count - 1);
        while (slots[slot * 2 + 1] != empty_group_index) {
            slot = (slot + 1) & (slot_count - 1);
        }
        slots[slot * 2] = entry.glyph;
        slots[slot * 2 + 1] = entry.group_index;
    }
}

fn lessEntry(_: void, lhs: Entry, rhs: Entry) bool {
    return lhs.glyph < rhs.glyph;
}
