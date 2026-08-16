//! OpenType variation rounding contracts.

const std = @import("std");
const numeric = @import("../../outline/root.zig").numeric;

test "OpenType variation rounding sends half-unit ties toward positive infinity" {
    try std.testing.expectEqual(
        @as(f32, -103),
        numeric.roundOpenType(-102.5001),
    );
    try std.testing.expectEqual(
        @as(f32, -101),
        numeric.roundOpenType(-101.5),
    );
    try std.testing.expectEqual(
        @as(f32, 101),
        numeric.roundOpenType(100.5),
    );
    try std.testing.expectEqual(
        @as(f32, 101),
        numeric.roundOpenType(100.5001),
    );
}
