//! Cursive attachment-chain output contracts.

const std = @import("std");
const cursive = @import("../../../../runtime/lookup/cursive.zig");
const output = @import("../../../../runtime/output/root.zig");

test "cursive joins preserve placement across overlapping links" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 120, .y = 35 },
        .{ .x = 120, .y = 185 },
        0,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        1,
        2,
        .{ .x = 268, .y = 139 },
        .{ .x = 0, .y = 0 },
        0,
        .ltr,
    );

    const middle = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 148), middle.x_advance);
    try std.testing.expectEqual(@as(i16, -120), middle.x_placement);
    try std.testing.expect(middle.x_advance_absolute);
}

test "cursive joins reverse existing attachment chains" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 120, .y = 44 },
        .{ .x = 120, .y = 152 },
        0,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        2,
        1,
        .{ .x = 376, .y = 79 },
        .{ .x = 239, .y = 152 },
        0,
        .ltr,
    );

    const old_parent = output.adjustments.find(adjustments.items, 0).?;
    const middle = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(?usize, 1), old_parent.attachment_parent_index);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        old_parent.attachment_type,
    );
    try std.testing.expectEqual(@as(i16, 108), old_parent.y_placement);
    try std.testing.expectEqual(@as(?usize, 2), middle.attachment_parent_index);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        middle.attachment_type,
    );
    try std.testing.expectEqual(@as(i16, -73), middle.y_placement);
}

test "later cursive direction replaces a reciprocal attachment" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 218, .y = 40 },
        .{ .x = 82, .y = 184 },
        0x0001,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 218, .y = 40 },
        .{ .x = 82, .y = 184 },
        0,
        .ltr,
    );

    const first = output.adjustments.find(adjustments.items, 0).?;
    const second = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.none,
        first.attachment_type,
    );
    try std.testing.expectEqual(@as(?usize, null), first.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 0), first.y_placement);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        second.attachment_type,
    );
    try std.testing.expectEqual(@as(?usize, 0), second.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, -144), second.y_placement);
}
