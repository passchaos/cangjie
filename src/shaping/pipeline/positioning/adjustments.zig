//! Sparse GPOS adjustment ordering and linear cursor lookup.

const gpos = @import("../../../gpos.zig");

pub fn lessThan(
    _: void,
    lhs: gpos.Adjustment,
    rhs: gpos.Adjustment,
) bool {
    return lhs.index < rhs.index;
}

/// Find the adjustment for `index` while monotonically advancing `cursor`.
///
/// GPOS emits only changed glyphs. The final output loop visits every glyph,
/// so returning an identity record avoids materializing a second dense array.
pub fn find(
    adjustments: []const gpos.Adjustment,
    index: usize,
    cursor: *usize,
) gpos.Adjustment {
    while (cursor.* < adjustments.len and
        adjustments[cursor.*].index < index)
    {
        cursor.* += 1;
    }
    if (cursor.* < adjustments.len and
        adjustments[cursor.*].index == index)
    {
        return adjustments[cursor.*];
    }
    return .{ .index = index };
}

test "sorted cursor finds sparse GPOS entries in linear order" {
    const std = @import("std");
    const adjustments = [_]gpos.Adjustment{
        .{ .index = 1, .x_advance = 10 },
        .{ .index = 3, .x_placement = -4, .pair_positioned = true },
    };
    var cursor: usize = 0;

    const missing_0 = find(&adjustments, 0, &cursor);
    try std.testing.expectEqual(@as(usize, 0), missing_0.index);
    try std.testing.expectEqual(@as(i16, 0), missing_0.x_advance);
    try std.testing.expectEqual(@as(usize, 0), cursor);

    const found_1 = find(&adjustments, 1, &cursor);
    try std.testing.expectEqual(@as(i16, 10), found_1.x_advance);
    try std.testing.expectEqual(@as(usize, 0), cursor);

    const missing_2 = find(&adjustments, 2, &cursor);
    try std.testing.expectEqual(@as(usize, 2), missing_2.index);
    try std.testing.expectEqual(@as(usize, 1), cursor);

    const found_3 = find(&adjustments, 3, &cursor);
    try std.testing.expectEqual(@as(i16, -4), found_3.x_placement);
    try std.testing.expectEqual(@as(usize, 1), cursor);
}
