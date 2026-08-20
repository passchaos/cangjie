//! Nested ExtensionPos precedence contracts.

const std = @import("std");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS chaining coverage nested ExtensionPos SinglePos respects alternatives" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 2);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 70);

    fixture.writeU16(&bytes, 16, 8);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 8);

    const chaining = 24;
    fixture.writeU16(&bytes, chaining + 0, 3);
    fixture.writeU16(&bytes, chaining + 2, 1);
    fixture.writeU16(&bytes, chaining + 4, 24);
    fixture.writeU16(&bytes, chaining + 6, 2);
    fixture.writeU16(&bytes, chaining + 8, 30);
    fixture.writeU16(&bytes, chaining + 10, 36);
    fixture.writeU16(&bytes, chaining + 12, 1);
    fixture.writeU16(&bytes, chaining + 14, 42);
    fixture.writeU16(&bytes, chaining + 16, 1);
    // Match [10, 11] only when preceded by 7 and followed by 12, then apply
    // lookup 1 to input sequenceIndex 1. The nested lookup contains two
    // ExtensionPos(SinglePos) subtables for glyph 11; the first matching
    // wrapper must win instead of cascading both SinglePos adjustments.
    fixture.writeU16(&bytes, chaining + 18, 1);
    fixture.writeU16(&bytes, chaining + 20, 1);
    fixture.writeCoverage1(&bytes, chaining + 24, 7);
    fixture.writeCoverage1(&bytes, chaining + 30, 10);
    fixture.writeCoverage1(&bytes, chaining + 36, 11);
    fixture.writeCoverage1(&bytes, chaining + 42, 12);

    fixture.writeU16(&bytes, 80, 9);
    fixture.writeU16(&bytes, 84, 2);
    fixture.writeU16(&bytes, 86, 10);
    fixture.writeU16(&bytes, 88, 32);

    const first_extension = 90;
    fixture.writeU16(&bytes, first_extension + 0, 1);
    fixture.writeU16(&bytes, first_extension + 2, 1);
    fixture.writeU32(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    fixture.writeU16(&bytes, first_single + 0, 1);
    fixture.writeU16(&bytes, first_single + 2, 8);
    fixture.writeU16(&bytes, first_single + 4, 0x0004);
    fixture.writeI16(&bytes, first_single + 6, 40);
    fixture.writeCoverage1(&bytes, first_single + 8, 11);

    const second_extension = 112;
    fixture.writeU16(&bytes, second_extension + 0, 1);
    fixture.writeU16(&bytes, second_extension + 2, 1);
    fixture.writeU32(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    fixture.writeU16(&bytes, second_single + 0, 1);
    fixture.writeU16(&bytes, second_single + 2, 8);
    fixture.writeU16(&bytes, second_single + 4, 0x0004);
    fixture.writeI16(&bytes, second_single + 6, 90);
    fixture.writeCoverage1(&bytes, second_single + 8, 11);

    const glyphs = [_]GlyphId{ 7, 10, 11, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 40), adjustments.items[0].x_advance);
}
test "GPOS context nested ExtensionPos PairPos respects alternatives with mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 170;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 2);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 54);

    fixture.writeU16(&bytes, 16, 7);
    fixture.writeU16(&bytes, 18, 0x0010);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 10);
    fixture.writeU16(&bytes, 24, 0);

    const context = 26;
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
    fixture.writeU16(&bytes, rule + 4, 11);
    fixture.writeU16(&bytes, rule + 6, 0);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 10);

    fixture.writeU16(&bytes, 64, 9);
    fixture.writeU16(&bytes, 66, 0x0010);
    fixture.writeU16(&bytes, 68, 2);
    fixture.writeU16(&bytes, 70, 12);
    fixture.writeU16(&bytes, 72, 56);
    fixture.writeU16(&bytes, 74, 0);

    const first_extension = 76;
    fixture.writeU16(&bytes, first_extension + 0, 1);
    fixture.writeU16(&bytes, first_extension + 2, 2);
    fixture.writeU32(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    fixture.writeU16(&bytes, first_pair + 0, 1);
    fixture.writeU16(&bytes, first_pair + 2, 22);
    fixture.writeU16(&bytes, first_pair + 4, 0x0004);
    fixture.writeU16(&bytes, first_pair + 6, 0);
    fixture.writeU16(&bytes, first_pair + 8, 1);
    fixture.writeU16(&bytes, first_pair + 10, 28);
    fixture.writeCoverage1(&bytes, first_pair + 22, 10);
    fixture.writeU16(&bytes, first_pair + 28, 1);
    fixture.writeU16(&bytes, first_pair + 30, 11);
    fixture.writeI16(&bytes, first_pair + 32, -30);

    const second_extension = 120;
    fixture.writeU16(&bytes, second_extension + 0, 1);
    fixture.writeU16(&bytes, second_extension + 2, 2);
    fixture.writeU32(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    fixture.writeU16(&bytes, second_pair + 0, 1);
    fixture.writeU16(&bytes, second_pair + 2, 22);
    fixture.writeU16(&bytes, second_pair + 4, 0x0004);
    fixture.writeU16(&bytes, second_pair + 6, 0);
    fixture.writeU16(&bytes, second_pair + 8, 1);
    fixture.writeU16(&bytes, second_pair + 10, 28);
    fixture.writeCoverage1(&bytes, second_pair + 22, 10);
    fixture.writeU16(&bytes, second_pair + 28, 1);
    fixture.writeU16(&bytes, second_pair + 30, 11);
    fixture.writeI16(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The unselected mark is transparent for both the outer ContextPos match
    // and the wrapped PairPos lookup. Once the first ExtensionPos(PairPos)
    // subtable matches that filtered pair, the second wrapper in the same
    // lookup must remain an alternative rather than adding another adjustment.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}
