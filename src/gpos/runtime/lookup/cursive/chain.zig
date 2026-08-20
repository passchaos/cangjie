//! Cursive attachment-chain output updates.

const std = @import("std");
const positioning = @import("../../../positioning/root.zig");
const options = @import("../../options.zig");
const output = @import("../../output/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Anchor = positioning.anchor.Value;
pub const Direction = options.Options.Direction;

pub fn appendJoin(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    previous_position: usize,
    current_position: usize,
    exit: Anchor,
    entry: Anchor,
    lookup_flag: u16,
    direction: Direction,
) std.mem.Allocator.Error!void {
    const previous_placement = output.adjustments.currentPlacement(
        adjustments.items,
        previous_position,
    );
    const current_placement = output.adjustments.currentPlacement(
        adjustments.items,
        current_position,
    );
    const right_to_left = (lookup_flag & 0x0001) != 0;
    const child_position =
        if (right_to_left) previous_position else current_position;
    const parent_position =
        if (right_to_left) current_position else previous_position;
    try reverseAttachmentChain(
        adjustments,
        allocator,
        child_position,
        parent_position,
    );
    clearAttachmentTo(adjustments.items, parent_position, child_position);

    if (direction == .rtl) {
        const previous_x_delta = -exit.x - previous_placement.x;
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            previous_position,
            .{
                .index = previous_position,
                .x_advance = previous_x_delta,
                .x_placement = -exit.x,
            },
            .{
                .attachment_type = if (right_to_left) .cursive else .none,
                .attachment_parent_index = if (right_to_left) current_position else null,
                .x_placement_absolute = true,
            },
        );
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            current_position,
            .{
                .index = current_position,
                .x_advance = entry.x + current_placement.x,
            },
            .{ .x_advance_absolute = true },
        );
    } else {
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            previous_position,
            .{
                .index = previous_position,
                .x_advance = exit.x + previous_placement.x,
            },
            .{ .x_advance_absolute = true },
        );
        const current_x_delta = -entry.x - current_placement.x;
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            current_position,
            .{
                .index = current_position,
                .x_advance = current_x_delta,
                .x_placement = -entry.x,
            },
            .{
                .attachment_type = if (right_to_left) .none else .cursive,
                .attachment_parent_index = if (right_to_left) null else previous_position,
                .x_placement_absolute = true,
            },
        );
    }

    if (right_to_left) {
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            previous_position,
            .{
                .index = previous_position,
                .y_placement = entry.y - exit.y,
            },
            .{
                .attachment_type = .cursive,
                .attachment_parent_index = current_position,
                .y_placement_absolute = true,
            },
        );
    } else {
        try output.adjustments.appendWithFlags(
            adjustments,
            allocator,
            current_position,
            .{
                .index = current_position,
                .y_placement = exit.y - entry.y,
            },
            .{
                .attachment_type = .cursive,
                .attachment_parent_index = previous_position,
                .y_placement_absolute = true,
            },
        );
    }
}

fn clearAttachmentTo(
    adjustments: []Adjustment,
    child_index: usize,
    parent_index: usize,
) void {
    const record =
        output.adjustments.findMutable(adjustments, child_index) orelse return;
    if (record.attachment_type != .cursive) return;
    if (record.attachment_parent_index != parent_index) return;
    record.attachment_type = .none;
    record.attachment_parent_index = null;
    record.y_placement = 0;
}

fn reverseAttachmentChain(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    child_index: usize,
    new_parent_index: usize,
) std.mem.Allocator.Error!void {
    const child_record =
        output.adjustments.findMutable(
            adjustments.items,
            child_index,
        ) orelse return;
    if (child_record.attachment_type != .cursive) return;
    const old_parent_index = child_record.attachment_parent_index orelse return;
    const child_placement = output.adjustments.currentPlacement(
        adjustments.items,
        child_index,
    );
    child_record.attachment_type = .none;
    child_record.attachment_parent_index = null;
    if (old_parent_index == new_parent_index) return;

    try reverseAttachmentChain(
        adjustments,
        allocator,
        old_parent_index,
        new_parent_index,
    );
    try output.adjustments.appendWithFlags(
        adjustments,
        allocator,
        old_parent_index,
        .{
            .index = old_parent_index,
            .y_placement = -child_placement.y,
        },
        .{
            .attachment_type = .cursive,
            .attachment_parent_index = child_index,
            .y_placement_absolute = true,
        },
    );
}
