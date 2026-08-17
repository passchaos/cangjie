//! Shared OpenType LookupList index ordering helpers.
//!
//! GSUB, GPOS, and JSTF all identify lookups by their `LookupList` index.
//! JSTF modification lists are validated as sorted sets, while ordinary
//! feature selection may be supplied by either a parser or a caller-side
//! cache. Keep membership and canonical union semantics in one place so every
//! execution path agrees on the order in which modified plans run.

const std = @import("std");

/// Test membership in an ascending, duplicate-free lookup-index set.
pub fn contains(sorted: []const u16, needle: u16) bool {
    var low: usize = 0;
    var high = sorted.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (sorted[middle] < needle) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low < sorted.len and sorted[low] == needle;
}

/// Own the canonical union of an active plan and JSTF-enabled lookups.
///
/// The active input normally already follows LookupList order, but sorting the
/// rare modified plan here also makes low-level preselected inputs safe. The
/// returned slice is always ascending and duplicate-free, as required before
/// reapplying a JSTF suggestion to an unmodified glyph string.
pub fn mergeEnabled(
    allocator: std.mem.Allocator,
    active: []const u16,
    enabled: []const u16,
) std.mem.Allocator.Error![]u16 {
    const merged = try allocator.alloc(u16, active.len + enabled.len);
    errdefer allocator.free(merged);
    @memcpy(merged[0..active.len], active);
    @memcpy(merged[active.len..], enabled);
    std.mem.sort(u16, merged, {}, lessThan);

    var write: usize = 0;
    for (merged) |lookup| {
        if (write != 0 and merged[write - 1] == lookup) continue;
        merged[write] = lookup;
        write += 1;
    }
    return try allocator.realloc(merged, write);
}

fn lessThan(_: void, lhs: u16, rhs: u16) bool {
    return lhs < rhs;
}

test "JSTF lookup unions follow LookupList order" {
    const merged = try mergeEnabled(
        std.testing.allocator,
        &.{ 1, 3, 5 },
        &.{ 0, 3, 4 },
    );
    defer std.testing.allocator.free(merged);

    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 3, 4, 5 }, merged);
    try std.testing.expect(contains(merged, 4));
    try std.testing.expect(!contains(merged, 2));
}
