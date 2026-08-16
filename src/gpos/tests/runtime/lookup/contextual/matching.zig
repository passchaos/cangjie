//! Contextual visible-glyph window contracts.

const std = @import("std");
const matching =
    @import("../../../../runtime/lookup/contextual/matching.zig");
const Options = @import("../../../../runtime/options.zig").Options;

test "context matching windows preserve visible glyph indexes" {
    const glyphs = [_]u16{ 3, 4, 5, 6 };
    var glyph_classes = [_]u16{0} ** 7;
    glyph_classes[4] = 3;
    const run = Options{ .glyph_classes = &glyph_classes };

    try std.testing.expectEqual(
        @as(?usize, 2),
        matching.next(&glyphs, 1, 0x0008, run),
    );

    var forward: [3]usize = undefined;
    try std.testing.expect(matching.forward(
        &glyphs,
        0,
        0x0008,
        run,
        &forward,
    ));
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 3 }, &forward);

    var backtrack: [3]usize = undefined;
    try std.testing.expect(matching.backtrack(
        &glyphs,
        glyphs.len,
        0x0008,
        run,
        &backtrack,
    ));
    try std.testing.expectEqualSlices(usize, &.{ 3, 2, 0 }, &backtrack);
}
