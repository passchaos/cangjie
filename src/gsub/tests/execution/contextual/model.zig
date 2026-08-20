//! Contextual mutation result and resume-position contracts.

const std = @import("std");
const model = @import("../../../execution/contextual/model.zig");

test "contextual resume position follows growth and bounded contraction" {
    try std.testing.expectEqual(
        @as(usize, 8),
        model.nextPositionAfterMutation(6, 2, 5, 7),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        model.nextPositionAfterMutation(6, 2, 8, 6),
    );
    // A large contraction cannot revisit the match start.
    try std.testing.expectEqual(
        @as(usize, 3),
        model.nextPositionAfterMutation(4, 2, 8, 1),
    );
}
