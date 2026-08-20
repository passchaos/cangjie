//! GPOS adjustment accumulation contracts.

const std = @import("std");
const output = @import("../../../runtime/output/root.zig");

const Adjustment = output.adjustments.Adjustment;

test "output keeps semantic zero records and replaces absolute advances" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try output.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        2,
        .{ .index = 2, .x_advance = 0 },
        .{ .x_advance_absolute = true },
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);

    try output.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        2,
        .{ .index = 2, .x_advance = 120 },
        .{ .x_advance_absolute = true },
    );
    try output.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        2,
        .{ .index = 2, .x_advance = 240 },
        .{ .x_advance_absolute = true },
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 240), adjustments.items[0].x_advance);
}

test "output distinguishes additive deltas mark replacement and pair metadata" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    // A numerically empty ordinary result disappears, while PairPos retains
    // the record because it suppresses legacy kern for the matched pair.
    try output.adjustments.append(
        &adjustments,
        allocator,
        1,
        .{ .index = 1 },
        false,
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    try output.adjustments.append(
        &adjustments,
        allocator,
        1,
        .{ .index = 1 },
        true,
    );
    try std.testing.expect(adjustments.items[0].pair_positioned);

    try output.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        1,
        .{ .index = 1, .x_placement = 10, .y_placement = 20 },
        .{},
    );
    try output.adjustments.appendWithFlags(
        &adjustments,
        allocator,
        1,
        .{
            .index = 1,
            .x_placement = 30,
            .y_placement = 40,
            .attachment_cross_offset = 90,
        },
        .{ .attachment_type = .mark, .attachment_parent_index = 0 },
    );
    const merged = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 30), merged.x_placement);
    try std.testing.expectEqual(@as(i16, 40), merged.y_placement);
    try std.testing.expectEqual(@as(i32, 90), merged.attachment_cross_offset);
    try std.testing.expectEqual(output.adjustments.AttachmentType.mark, merged.attachment_type);
    try std.testing.expectEqual(@as(?usize, 0), merged.attachment_parent_index);

    const placement =
        output.adjustments.currentPlacement(adjustments.items, 1);
    try std.testing.expectEqual(@as(i16, 30), placement.x);
    try std.testing.expectEqual(@as(i16, 40), placement.y);
    output.adjustments.findMutable(adjustments.items, 1).?.y_placement = 55;
    try std.testing.expectEqual(
        @as(i16, 55),
        output.adjustments.find(adjustments.items, 1).?.y_placement,
    );
}
