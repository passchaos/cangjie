//! Mutable SequenceIndex map contracts for cardinality-changing lookups.

const std = @import("std");
const model = @import("../../../../execution/contextual/model.zig");
const mapping =
    @import("../../../../execution/contextual/records/mapping.zig");

test "expansion inserts logical positions after the active sequence index" {
    var map = try mapping.Map.init(&.{ 0, 1, 2 });
    try map.applyChange(1, 1, .{ .removed_len = 1, .inserted_len = 3 });

    try std.testing.expectEqual(@as(usize, 5), map.len);
    try expectTargets(&map, &.{ 0, 1, 2, 3, 4 });
}

test "deletion invalidates consumed positions without retargeting shifted glyphs" {
    var map = try mapping.Map.init(&.{ 0, 1, 2 });
    try map.applyChange(0, 0, .{ .removed_len = 1, .inserted_len = 0 });

    try std.testing.expect(map.target(0) == null);
    try std.testing.expectEqual(@as(?usize, 0), map.target(1));
    try std.testing.expectEqual(@as(?usize, 1), map.target(2));
}

test "sparse ligature offsets compact logical positions and preserve ignored glyphs" {
    // Physical glyph one is ignored by the nested ligature's LookupFlag and
    // therefore never appears in the matched logical input map.
    var map = try mapping.Map.init(&.{ 0, 2, 3 });
    var offsets = [_]usize{0} ** model.max_components;
    offsets[1] = 2;
    try map.applyChange(0, 0, .{
        .removed_len = 2,
        .inserted_len = 1,
        .component_offsets = offsets,
        .component_count = 2,
    });

    try std.testing.expectEqual(@as(usize, 2), map.len);
    // The component at physical two is consumed. The later glyph shifts from
    // three to two, while ignored physical glyph one remains outside the map.
    try expectTargets(&map, &.{ 0, 2 });
}

test "map rejects initial and expanded position lists beyond fixed capacity" {
    const too_many = [_]usize{0} ** (mapping.capacity + 1);
    try std.testing.expectError(
        error.UnsupportedGsub,
        mapping.Map.init(&too_many),
    );

    var map = try mapping.Map.init(&([_]usize{0} ** mapping.capacity));
    try std.testing.expectError(
        error.UnsupportedGsub,
        map.applyChange(0, 0, .{ .removed_len = 1, .inserted_len = 2 }),
    );
}

fn expectTargets(map: *const mapping.Map, expected: []const usize) !void {
    for (expected, 0..) |target, index| {
        try std.testing.expectEqual(@as(?usize, target), map.target(index));
    }
}
