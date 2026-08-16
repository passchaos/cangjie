//! Lookup profiling counter, hash, and diff contracts.

const std = @import("std");
const profile = @import("../../../execution/lookup/profile.zig");

test "GSUB lookup profile classifies concrete lookup kinds" {
    var counters = profile.Profile{};
    for ([_]u16{ 1, 2, 3, 4, 5, 6, 7, 99 }) |lookup_type| {
        profile.recordKind(&counters, lookup_type);
    }

    try std.testing.expectEqual(@as(usize, 8), counters.gsub_lookup_count);
    try std.testing.expectEqual(
        @as(usize, 1),
        counters.gsub_single_lookup_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        counters.gsub_multiple_lookup_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        counters.gsub_alternate_lookup_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        counters.gsub_ligature_lookup_count,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        counters.gsub_context_lookup_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        counters.gsub_extension_lookup_count,
    );
}

test "GSUB lookup profile finds the first changed glyph and run hash" {
    try std.testing.expectEqual(
        @as(usize, 2),
        profile.firstDifferentGlyphIndex(&.{ 1, 2, 3 }, &.{ 1, 2, 4 }),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        profile.firstDifferentGlyphIndex(&.{ 1, 2 }, &.{ 1, 2, 3 }),
    );
    try std.testing.expectEqual(
        profile.glyphRunHash(&.{ 1, 2, 3 }),
        profile.glyphRunHash(&.{ 1, 2, 3 }),
    );
    try std.testing.expect(
        profile.glyphRunHash(&.{ 1, 2, 3 }) !=
            profile.glyphRunHash(&.{ 1, 2, 4 }),
    );
}
