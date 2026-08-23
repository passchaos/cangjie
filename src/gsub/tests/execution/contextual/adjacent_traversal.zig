//! Physical-adjacency traversal contracts for prevalidated source runs.

const std = @import("std");
const traversal = @import("../../../execution/support/context_traversal.zig");

test "adjacent traversal stops at the source syllable boundary" {
    const glyphs = [_]u16{ 10, 11, 12, 13, 14 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4 });
    const syllables = [_]u8{ 1, 1, 1, 2, 2 };
    var indices: [5]usize = undefined;

    const count = traversal.collectForwardPrefix(
        &glyphs,
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &syllables,
            .match_source_syllable = true,
            .run_has_default_ignorables = false,
        },
        &indices,
        false,
        0,
    );
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, indices[0..count]);
}

test "adjacent traversal preserves the no-syllable whole-run prefix" {
    const glyphs = [_]u16{ 10, 11, 12 };
    var indices: [4]usize = undefined;
    const count = traversal.collectForwardPrefix(
        &glyphs,
        1,
        0,
        .{ .run_has_default_ignorables = false },
        &indices,
        false,
        1,
    );
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, indices[0..count]);
}
