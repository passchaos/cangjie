//! Shared mark-attachment output updates.

const std = @import("std");
const positioning = @import("../../../positioning/root.zig");
const output = @import("../../output/root.zig");

pub const Adjustment = positioning.Adjustment;

const max_attachment_nesting = 64;

pub fn append(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    mark_index: usize,
    parent_index: usize,
    x_placement: i16,
    y_placement: i16,
    vertical: bool,
) std.mem.Allocator.Error!void {
    const placement = Adjustment{
        .index = mark_index,
        .x_placement = x_placement,
        .y_placement = y_placement,
        // HarfBuzz snapshots the parent's cross-axis cursive displacement at
        // lookup application time. Main-axis attachment remains deferred.
        .attachment_cross_offset = resolveCursiveCrossOffset(
            adjustments.items,
            parent_index,
            vertical,
        ),
    };
    try output.adjustments.appendWithFlags(
        adjustments,
        allocator,
        mark_index,
        placement,
        .{
            .attachment_type = .mark,
            .attachment_parent_index = parent_index,
        },
    );
}

pub fn resolveCursiveCrossOffset(
    adjustments: []const Adjustment,
    start_index: usize,
    vertical: bool,
) i32 {
    var index = start_index;
    var offset: i32 = 0;
    var depth: usize = 0;
    while (depth < max_attachment_nesting) : (depth += 1) {
        const adjustment =
            output.adjustments.find(adjustments, index) orelse break;
        offset += @as(
            i32,
            if (vertical)
                adjustment.x_placement
            else
                adjustment.y_placement,
        ) + adjustment.attachment_cross_offset;
        if (adjustment.attachment_type != .cursive) break;
        index = adjustment.attachment_parent_index orelse break;
    }
    return offset;
}
