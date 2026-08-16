//! GPOS positioning-result value contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");

test "Adjustment exposes source-level attachment relationships" {
    const ordinary = positioning.Adjustment{ .index = 3 };
    try std.testing.expect(!ordinary.markAttachment());
    try std.testing.expectEqual(
        @as(?usize, null),
        ordinary.attachmentParentIndex(),
    );

    const mark = positioning.Adjustment{
        .index = 4,
        .attachment_type = .mark,
        .attachment_parent_index = 2,
        .attachment_cross_offset = 70_000,
    };
    try std.testing.expect(mark.markAttachment());
    try std.testing.expectEqual(
        @as(?usize, 2),
        mark.attachmentParentIndex(),
    );
    try std.testing.expectEqual(@as(i32, 70_000), mark.attachment_cross_offset);
}
