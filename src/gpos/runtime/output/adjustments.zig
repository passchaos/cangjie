//! Accumulation and lookup for GPOS adjustment output.
//!
//! Lookups may target one glyph repeatedly. This module centralizes the merge
//! contract so lookup executors describe whether fields are additive,
//! absolute, or attachment metadata without duplicating output-state rules.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const AttachmentType = positioning.AttachmentType;

pub const Flags = struct {
    pair_positioned: bool = false,
    attachment_type: AttachmentType = .none,
    attachment_parent_index: ?usize = null,
    x_placement_absolute: bool = false,
    y_placement_absolute: bool = false,
    x_advance_absolute: bool = false,
    y_advance_absolute: bool = false,
};

pub const Placement = struct {
    x: i16 = 0,
    y: i16 = 0,
};

pub fn append(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    index: usize,
    value: Adjustment,
    pair_positioned: bool,
) std.mem.Allocator.Error!void {
    return appendWithFlags(adjustments, allocator, index, value, .{
        .pair_positioned = pair_positioned,
    });
}

pub fn appendWithFlags(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    index: usize,
    value: Adjustment,
    flags: Flags,
) std.mem.Allocator.Error!void {
    // PairPos is also a precedence signal for higher-level shaping: when a
    // GPOS pair matches, legacy 'kern' must not be applied to that same pair
    // even when the first ValueRecord is empty and numeric deltas live on the
    // second glyph. Keep a zero-valued record when metadata carries that fact.
    const has_delta = value.x_advance != 0 or
        value.x_placement != 0 or
        value.y_placement != 0 or
        value.y_advance != 0;
    if (!has_delta and
        !flags.pair_positioned and
        flags.attachment_type == .none and
        !flags.x_advance_absolute and
        !flags.y_advance_absolute)
    {
        return;
    }

    // Search backwards because repeated positioning normally targets the most
    // recently emitted record, especially for contextual nested lookups.
    var existing_i = adjustments.items.len;
    while (existing_i > 0) {
        existing_i -= 1;
        if (adjustments.items[existing_i].index != index) continue;
        merge(&adjustments.items[existing_i], value, flags);
        return;
    }
    try adjustments.append(allocator, .{
        .index = index,
        .x_advance = value.x_advance,
        .x_placement = value.x_placement,
        .y_placement = value.y_placement,
        .y_advance = value.y_advance,
        .attachment_cross_offset = value.attachment_cross_offset,
        .pair_positioned = flags.pair_positioned,
        .attachment_type = flags.attachment_type,
        .attachment_parent_index = flags.attachment_parent_index,
        .x_advance_absolute = flags.x_advance_absolute,
        .y_advance_absolute = flags.y_advance_absolute,
    });
}

pub fn currentPlacement(
    adjustments: []const Adjustment,
    index: usize,
) Placement {
    const adjustment = find(adjustments, index) orelse return .{};
    return .{
        .x = adjustment.x_placement,
        .y = adjustment.y_placement,
    };
}

pub fn find(
    adjustments: []const Adjustment,
    index: usize,
) ?Adjustment {
    var i = adjustments.len;
    while (i > 0) {
        i -= 1;
        if (adjustments[i].index == index) return adjustments[i];
    }
    return null;
}

pub fn findMutable(
    adjustments: []Adjustment,
    index: usize,
) ?*Adjustment {
    var i = adjustments.len;
    while (i > 0) {
        i -= 1;
        if (adjustments[i].index == index) return &adjustments[i];
    }
    return null;
}

fn merge(existing: *Adjustment, value: Adjustment, flags: Flags) void {
    if (flags.x_advance_absolute) {
        existing.x_advance = value.x_advance;
    } else {
        existing.x_advance += value.x_advance;
    }
    if (flags.attachment_type == .mark or flags.x_placement_absolute) {
        existing.x_placement = value.x_placement;
    } else {
        existing.x_placement += value.x_placement;
    }
    if (flags.attachment_type == .mark or flags.y_placement_absolute) {
        existing.y_placement = value.y_placement;
    } else {
        existing.y_placement += value.y_placement;
    }
    if (flags.attachment_type == .mark) {
        existing.attachment_cross_offset = value.attachment_cross_offset;
    }
    if (flags.y_advance_absolute) {
        existing.y_advance = value.y_advance;
    } else {
        existing.y_advance += value.y_advance;
    }
    existing.pair_positioned =
        existing.pair_positioned or flags.pair_positioned;
    existing.x_advance_absolute =
        existing.x_advance_absolute or flags.x_advance_absolute;
    existing.y_advance_absolute =
        existing.y_advance_absolute or flags.y_advance_absolute;
    if (flags.attachment_type != .none) {
        existing.attachment_type = flags.attachment_type;
    }
    if (flags.attachment_parent_index) |parent_index| {
        existing.attachment_parent_index = parent_index;
    }
}
