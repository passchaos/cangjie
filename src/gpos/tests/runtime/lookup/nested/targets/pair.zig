//! Nested pair target integration contracts.

const std = @import("std");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS context nested lookup can apply pair positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

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
    fixture.writeU16(&bytes, rule + 4, 2);
    // PosLookupRecord sequenceIndex=0 intentionally invokes PairPos on the
    // first glyph of the matched input. The nested lookup must still inspect
    // the following glyph in the real run and produce both pair adjustments.
    fixture.writeU16(&bytes, rule + 6, 0);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 1);

    fixture.writeU16(&bytes, 52, 2);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);
    const pair = 60;
    fixture.writeU16(&bytes, pair + 0, 1);
    fixture.writeU16(&bytes, pair + 2, 22);
    fixture.writeU16(&bytes, pair + 4, 0x0004);
    fixture.writeU16(&bytes, pair + 6, 0x0001);
    fixture.writeU16(&bytes, pair + 8, 1);
    fixture.writeU16(&bytes, pair + 10, 28);
    fixture.writeCoverage1(&bytes, pair + 22, 1);
    const pair_set = pair + 28;
    fixture.writeU16(&bytes, pair_set + 0, 1);
    fixture.writeU16(&bytes, pair_set + 2, 2);
    fixture.writeI16(&bytes, pair_set + 4, -50);
    fixture.writeI16(&bytes, pair_set + 6, 20);

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[1].x_placement);
}
test "GPOS nested chaining context can recurse into PairPos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 220;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 4);
    fixture.writeU16(&bytes, 12, 10); // Lookup 0: outer ChainContextPos.
    fixture.writeU16(&bytes, 14, 50); // Lookup 1: ExtensionPos(ChainContextPos).
    fixture.writeU16(&bytes, 16, 110); // Lookup 2: ChainContextPos.
    fixture.writeU16(&bytes, 18, 160); // Lookup 3: PairPos.

    fixture.writeU16(&bytes, 20, 8);
    fixture.writeU16(&bytes, 22, 0);
    fixture.writeU16(&bytes, 24, 1);
    fixture.writeU16(&bytes, 26, 8);
    const outer = 28;
    fixture.writeU16(&bytes, outer + 0, 3);
    fixture.writeU16(&bytes, outer + 2, 0); // BacktrackCount.
    fixture.writeU16(&bytes, outer + 4, 1); // InputGlyphCount.
    fixture.writeU16(&bytes, outer + 6, 18);
    fixture.writeU16(&bytes, outer + 8, 0); // LookAheadCount.
    fixture.writeU16(&bytes, outer + 10, 1); // PosCount.
    fixture.writeU16(&bytes, outer + 12, 0); // SequenceIndex 0.
    fixture.writeU16(&bytes, outer + 14, 1); // Lookup 1.
    fixture.writeCoverage1(&bytes, outer + 18, 10);

    fixture.writeU16(&bytes, 60, 9);
    fixture.writeU16(&bytes, 62, 0);
    fixture.writeU16(&bytes, 64, 1);
    fixture.writeU16(&bytes, 66, 8);
    const extension = 68;
    fixture.writeU16(&bytes, extension + 0, 1);
    fixture.writeU16(&bytes, extension + 2, 8);
    fixture.writeU32(&bytes, extension + 4, 8);
    const middle = extension + 8;
    fixture.writeU16(&bytes, middle + 0, 3);
    fixture.writeU16(&bytes, middle + 2, 0);
    fixture.writeU16(&bytes, middle + 4, 2);
    fixture.writeU16(&bytes, middle + 6, 22);
    fixture.writeU16(&bytes, middle + 8, 28);
    fixture.writeU16(&bytes, middle + 10, 0);
    fixture.writeU16(&bytes, middle + 12, 1);
    fixture.writeU16(&bytes, middle + 14, 0);
    fixture.writeU16(&bytes, middle + 16, 2);
    fixture.writeCoverage1(&bytes, middle + 22, 10);
    fixture.writeCoverage1(&bytes, middle + 28, 11);

    fixture.writeU16(&bytes, 120, 8);
    fixture.writeU16(&bytes, 122, 0);
    fixture.writeU16(&bytes, 124, 1);
    fixture.writeU16(&bytes, 126, 8);
    const inner = 128;
    fixture.writeU16(&bytes, inner + 0, 3);
    fixture.writeU16(&bytes, inner + 2, 0);
    fixture.writeU16(&bytes, inner + 4, 1);
    fixture.writeU16(&bytes, inner + 6, 18);
    fixture.writeU16(&bytes, inner + 8, 1);
    fixture.writeU16(&bytes, inner + 10, 24);
    fixture.writeU16(&bytes, inner + 12, 1);
    fixture.writeU16(&bytes, inner + 14, 0);
    fixture.writeU16(&bytes, inner + 16, 3);
    fixture.writeCoverage1(&bytes, inner + 18, 10);
    fixture.writeCoverage1(&bytes, inner + 24, 11);

    fixture.writeU16(&bytes, 170, 2);
    fixture.writeU16(&bytes, 172, 0);
    fixture.writeU16(&bytes, 174, 1);
    fixture.writeU16(&bytes, 176, 8);
    const pair = 178;
    fixture.writeU16(&bytes, pair + 0, 1);
    fixture.writeU16(&bytes, pair + 2, 22);
    fixture.writeU16(&bytes, pair + 4, 0);
    fixture.writeU16(&bytes, pair + 6, 0x0004);
    fixture.writeU16(&bytes, pair + 8, 1);
    fixture.writeU16(&bytes, pair + 10, 28);
    fixture.writeCoverage1(&bytes, pair + 22, 10);
    const pair_set = pair + 28;
    fixture.writeU16(&bytes, pair_set + 0, 1);
    fixture.writeU16(&bytes, pair_set + 2, 11);
    fixture.writeI16(&bytes, pair_set + 4, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -70), adjustments.items[1].x_advance);
}
