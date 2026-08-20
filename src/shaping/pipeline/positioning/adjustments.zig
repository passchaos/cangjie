//! Sparse GPOS adjustment ordering and linear cursor lookup.

const std = @import("std");
const gpos = @import("../../../gpos.zig");
const shaping_sections = @import("../../../shaping_sections.zig");

pub fn lessThan(
    _: void,
    lhs: gpos.Adjustment,
    rhs: gpos.Adjustment,
) bool {
    return lhs.index < rhs.index;
}

/// Preserve the common monotone GPOS stream without paying for a heap sort.
/// Keep this decision out of the segment hot frame: changing the helper must
/// not perturb unrelated GSUB/positioning code layout.
pub noinline fn sortIfNeeded(
    adjustments: []gpos.Adjustment,
) linksection(shaping_sections.isolated_hotpaths) void {
    if (adjustments.len < 2) return;
    for (
        adjustments[1..],
        adjustments[0 .. adjustments.len - 1],
    ) |current, previous| {
        if (previous.index <= current.index) continue;
        std.sort.heap(gpos.Adjustment, adjustments, {}, lessThan);
        return;
    }
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

test "GPOS adjustment ordering skips monotone input and repairs inversion" {
    var monotone = [_]gpos.Adjustment{
        .{ .index = 1 },
        .{ .index = 3 },
        .{ .index = 3 },
    };
    sortIfNeeded(&monotone);
    try std.testing.expectEqual(@as(usize, 1), monotone[0].index);
    try std.testing.expectEqual(@as(usize, 3), monotone[2].index);

    var inverted = [_]gpos.Adjustment{
        .{ .index = 4 },
        .{ .index = 1 },
        .{ .index = 3 },
    };
    sortIfNeeded(&inverted);
    try std.testing.expectEqual(@as(usize, 1), inverted[0].index);
    try std.testing.expectEqual(@as(usize, 3), inverted[1].index);
    try std.testing.expectEqual(@as(usize, 4), inverted[2].index);
}
