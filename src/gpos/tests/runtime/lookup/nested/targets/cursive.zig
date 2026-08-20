//! Nested cursive target integration contracts.

const std = @import("std");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS context nested lookup can apply cursive positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 124;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 2);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 42);

    fixture.writeU16(&bytes, 16, 7);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 8);

    const context = 24;
    fixture.writeU16(&bytes, context + 0, 1);
    fixture.writeU16(&bytes, context + 2, 22);
    fixture.writeU16(&bytes, context + 4, 1);
    fixture.writeU16(&bytes, context + 6, 8);

    const set = context + 8;
    fixture.writeU16(&bytes, set + 0, 1);
    fixture.writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    fixture.writeU16(&bytes, rule + 0, 2);
    fixture.writeU16(&bytes, rule + 2, 1);
    fixture.writeU16(&bytes, rule + 4, 22);
    // The PosLookupRecord targets sequenceIndex 1. A nested CursivePos must
    // use glyph 20 as the previous cursive glyph, while leaving the unrelated
    // earlier 10-12 join untouched.
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 20);

    fixture.writeU16(&bytes, 52, 3);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);
    const cursive = 60;
    fixture.writeU16(&bytes, cursive + 0, 1);
    fixture.writeU16(&bytes, cursive + 2, 22);
    fixture.writeU16(&bytes, cursive + 4, 4);
    fixture.writeU16(&bytes, cursive + 6, 0);
    fixture.writeU16(&bytes, cursive + 8, 34);
    fixture.writeU16(&bytes, cursive + 10, 40);
    fixture.writeU16(&bytes, cursive + 12, 0);
    fixture.writeU16(&bytes, cursive + 14, 0);
    fixture.writeU16(&bytes, cursive + 16, 46);
    fixture.writeU16(&bytes, cursive + 18, 52);
    fixture.writeU16(&bytes, cursive + 20, 0);
    fixture.writeCoverage1List(&bytes, cursive + 22, &.{ 10, 12, 20, 22 });
    fixture.writeAnchor1(&bytes, cursive + 34, 100, 30);
    fixture.writeAnchor1(&bytes, cursive + 40, 20, 5);
    fixture.writeAnchor1(&bytes, cursive + 46, 200, 70);
    fixture.writeAnchor1(&bytes, cursive + 52, 50, 10);

    const glyphs = [_]GlyphId{ 10, 12, 20, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 200), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
    try std.testing.expectEqual(@as(usize, 3), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 60), adjustments.items[1].y_placement);
}
