//! GPOS per-run prefilter contracts.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const prefilter = @import("../../../runtime/lookup/prefilter.zig");

test "run digest excludes lookup-flag ignored glyphs" {
    var classes = [_]u16{0} ** 8;
    classes[6] = 3;
    const digest = prefilter.runDigest(
        &.{ 5, 6, 7 },
        0x0008,
        .{ .glyph_classes = &classes },
    );
    try std.testing.expect(digest.mayHave(5));
    try std.testing.expect(!digest.mayHave(6));
    try std.testing.expect(digest.mayHave(7));
}

test "digest cache keys mark filtering state" {
    const sets = [_][]const u16{ &.{5}, &.{7} };
    var cache = prefilter.DigestCache.init();
    const first = cache.get(
        &.{ 5, 7 },
        0x0010,
        .{
            .glyph_classes = &.{ 0, 0, 0, 0, 0, 3, 0, 3 },
            .mark_filtering_sets = &sets,
            .active_mark_filtering_set = 0,
        },
    );
    const second = cache.get(
        &.{ 5, 7 },
        0x0010,
        .{
            .glyph_classes = &.{ 0, 0, 0, 0, 0, 3, 0, 3 },
            .mark_filtering_sets = &sets,
            .active_mark_filtering_set = 1,
        },
    );
    try std.testing.expect(first.mayHave(5));
    try std.testing.expect(!first.mayHave(7));
    try std.testing.expect(!second.mayHave(5));
    try std.testing.expect(second.mayHave(7));
}

test "exact coverage groups reject digest false positives" {
    const groups = [_]accelerator.glyph_groups.Group{
        .{ .glyph = 20, .subtable_indices = &.{0} },
    };
    try std.testing.expect(prefilter.groupsMayMatchRun(
        &groups,
        &.{},
        &.{20},
        0,
        .{},
    ));
    try std.testing.expect(!prefilter.groupsMayMatchRun(
        &groups,
        &.{},
        &.{21},
        0,
        .{},
    ));
}
