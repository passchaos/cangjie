//! Mutable OpenType SequenceIndex-to-glyph-position mapping.

const std = @import("std");
const model = @import("../model.zig");

pub const capacity = 64;

pub const Map = struct {
    positions: [capacity]usize = undefined,
    live: [capacity]bool = undefined,
    len: usize = 0,

    pub fn init(input_indices: []const usize) error{UnsupportedGsub}!Map {
        if (input_indices.len > capacity) return error.UnsupportedGsub;
        var result = Map{ .len = input_indices.len };
        @memcpy(result.positions[0..result.len], input_indices);
        @memset(result.live[0..result.len], true);
        return result;
    }

    pub fn target(self: *const Map, sequence_index: usize) ?usize {
        if (sequence_index >= self.len or !self.live[sequence_index]) {
            return null;
        }
        return self.positions[sequence_index];
    }

    pub fn applyChange(
        self: *Map,
        sequence_index: usize,
        target_index: usize,
        change: model.Change,
    ) error{UnsupportedGsub}!void {
        if (change.removed_len == change.inserted_len) return;
        if (change.component_offsets) |component_offsets| {
            self.applyLigature(
                sequence_index,
                target_index,
                change,
                &component_offsets,
            );
            return;
        }
        if (change.inserted_len > change.removed_len) {
            try self.applyExpansion(sequence_index, target_index, change);
        } else {
            self.applyContraction(target_index, change);
        }
    }

    fn applyLigature(
        self: *Map,
        sequence_index: usize,
        target_index: usize,
        change: model.Change,
        component_offsets: *const [model.max_components]usize,
    ) void {
        for (self.positions[0..self.len], 0..) |*position, map_index| {
            if (!self.live[map_index] or position.* <= target_index) continue;
            const relative = position.* - target_index;
            var removed_before: usize = 0;
            var consumed = false;
            for (component_offsets[1..change.component_count]) |offset| {
                if (relative == offset) {
                    consumed = true;
                    break;
                }
                if (offset < relative) removed_before += 1;
            }
            position.* = if (consumed)
                target_index
            else
                position.* - removed_before;
        }

        // HarfBuzz removes logical positions immediately after SequenceIndex,
        // even when ignored glyphs make physical component offsets sparse.
        const remove_count = @min(
            change.removed_len - change.inserted_len,
            self.len -| (sequence_index + 1),
        );
        if (remove_count == 0) return;
        const remove_start = sequence_index + 1;
        const remove_end = remove_start + remove_count;
        std.mem.copyForwards(
            usize,
            self.positions[remove_start .. self.len - remove_count],
            self.positions[remove_end..self.len],
        );
        std.mem.copyForwards(
            bool,
            self.live[remove_start .. self.len - remove_count],
            self.live[remove_end..self.len],
        );
        self.len -= remove_count;
    }

    fn applyExpansion(
        self: *Map,
        sequence_index: usize,
        target_index: usize,
        change: model.Change,
    ) error{UnsupportedGsub}!void {
        const added = change.inserted_len - change.removed_len;
        for (self.positions[0..self.len], 0..) |*position, map_index| {
            if (!self.live[map_index] or position.* < target_index) continue;
            if (position.* < target_index + change.removed_len) {
                position.* = target_index;
            } else {
                position.* += added;
            }
        }

        if (self.len + added > capacity) return error.UnsupportedGsub;
        const insert_at = sequence_index + 1;
        std.mem.copyBackwards(
            usize,
            self.positions[insert_at + added .. self.len + added],
            self.positions[insert_at..self.len],
        );
        std.mem.copyBackwards(
            bool,
            self.live[insert_at + added .. self.len + added],
            self.live[insert_at..self.len],
        );
        for (0..added) |offset| {
            self.positions[insert_at + offset] = target_index + 1 + offset;
            self.live[insert_at + offset] = true;
        }
        self.len += added;
    }

    fn applyContraction(
        self: *Map,
        target_index: usize,
        change: model.Change,
    ) void {
        for (self.positions[0..self.len], 0..) |*position, map_index| {
            if (!self.live[map_index] or position.* < target_index) continue;
            if (position.* < target_index + change.removed_len) {
                if (change.inserted_len == 0) {
                    self.live[map_index] = false;
                } else {
                    position.* = target_index;
                }
            } else {
                position.* -= change.removed_len - change.inserted_len;
            }
        }
    }
};
