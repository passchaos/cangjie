//! Exact LigatureSet lookup with a compact hash threshold.

const std = @import("std");
const model = @import("../../model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const min_sets_for_hash = 8;

pub fn build(
    sets: []const model.LigatureSet,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u16 {
    if (sets.len < min_sets_for_hash or sets.len > std.math.maxInt(u16)) {
        return allocator.alloc(u16, 0);
    }
    // At most 50% load bounds both hit and miss probing without allocating by
    // sparse glyph-id span.
    const slot_count =
        std.math.ceilPowerOfTwo(usize, sets.len * 2) catch
            return error.OutOfMemory;
    const slots = try allocator.alloc(u16, slot_count);
    @memset(slots, 0);
    for (sets, 0..) |set, set_index| {
        var slot = hash(set.glyph) & (slots.len - 1);
        while (slots[slot] != 0) {
            slot = (slot + 1) & (slots.len - 1);
        }
        slots[slot] = @intCast(set_index + 1);
    }
    return slots;
}

pub fn find(
    sets: []const model.LigatureSet,
    slots: []const u16,
    glyph: GlyphId,
) ?model.LigatureSet {
    if (slots.len != 0) {
        var slot = hash(glyph) & (slots.len - 1);
        while (slots[slot] != 0) : (slot = (slot + 1) & (slots.len - 1)) {
            const set = sets[slots[slot] - 1];
            if (set.glyph == glyph) return set;
        }
        return null;
    }

    var low: usize = 0;
    var high: usize = sets.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate = sets[middle].glyph;
        if (glyph < candidate) {
            high = middle;
        } else if (glyph > candidate) {
            low = middle + 1;
        } else {
            return sets[middle];
        }
    }
    return null;
}

fn hash(glyph: GlyphId) usize {
    return @as(usize, glyph) *% 0x9e37;
}
