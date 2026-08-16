//! Shared mark-attachment output contracts.

const std = @import("std");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const output_state = @import("../../../../runtime/output/root.zig");

const Adjustment = positioning.Adjustment;

test "mark attachment snapshots only the parent cross-axis offset" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try output_state.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        0,
        .{
            .index = 0,
            .x_placement = 40,
            .y_placement = -22,
        },
        .{},
    );
    try marks.output.append(
        &adjustments,
        allocator,
        1,
        0,
        -160,
        -274,
        false,
    );

    const mark = output_state.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, -160), mark.x_placement);
    try std.testing.expectEqual(@as(i16, -274), mark.y_placement);
    try std.testing.expectEqual(@as(i32, -22), mark.attachment_cross_offset);
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
}

test "mark attachment resolves a cursive cross-axis chain" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try output_state.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        0,
        .{ .index = 0, .y_placement = 30 },
        .{},
    );
    try output_state.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        1,
        .{ .index = 1, .y_placement = -12 },
        .{
            .attachment_type = .cursive,
            .attachment_parent_index = 0,
        },
    );
    try marks.output.append(
        &adjustments,
        allocator,
        2,
        1,
        5,
        7,
        false,
    );

    const mark = output_state.adjustments.find(adjustments.items, 2).?;
    try std.testing.expectEqual(@as(i32, 18), mark.attachment_cross_offset);
}

test "vertical mark attachment snapshots parent x placement" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try output_state.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        0,
        .{
            .index = 0,
            .x_placement = 27,
            .y_placement = -40,
        },
        .{},
    );
    try marks.output.append(
        &adjustments,
        allocator,
        1,
        0,
        8,
        9,
        true,
    );

    const mark = output_state.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i32, 27), mark.attachment_cross_offset);
}
