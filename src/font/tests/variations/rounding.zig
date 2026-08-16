//! OpenType variation rounding contracts.

const std = @import("std");

test "OpenType variation rounding sends half-unit ties toward positive infinity" {
    try std.testing.expectEqual(@as(f32, -103), otRound(-102.5001));
    try std.testing.expectEqual(@as(f32, -101), otRound(-101.5));
    try std.testing.expectEqual(@as(f32, 101), otRound(100.5));
    try std.testing.expectEqual(@as(f32, 101), otRound(100.5001));
}

fn otRound(value: f32) f32 {
    return @floor(value + 0.5);
}
