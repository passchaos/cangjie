//! ExtensionPos whole-lookup precedence contracts.

const std = @import("std");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;
const writeCoverage1Test = writeCoverage1;
const writeI16Test = writeI16;
const writeU16Test = writeU16;
const writeU32Test = writeU32;

test "GPOS ExtensionPos single positioning subtables respect mark filtering ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 36);
    writeU16Test(&bytes, 10, 0);

    const first_extension = 12;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 25);
    writeCoverage1Test(&bytes, first_single + 8, 5);

    const second_extension = 36;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 40);
    writeCoverage1Test(&bytes, second_single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{5}, &.{7} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Homogeneous ExtensionPos(SinglePos) subtables must behave like direct
    // SinglePos alternatives: the first matching wrapper wins for the original
    // mark, while the unselected mark filtering-set member remains transparent.
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[0].x_placement);
}
test "GPOS mixed ExtensionPos PairPos alternatives respect mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 58);
    writeU16Test(&bytes, 10, 82);
    writeU16Test(&bytes, 12, 0);

    const first_extension = 14;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const middle_extension = 58;
    writeU16Test(&bytes, middle_extension + 0, 1);
    writeU16Test(&bytes, middle_extension + 2, 1);
    writeU32Test(&bytes, middle_extension + 4, 8);
    const single = middle_extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 25);
    writeCoverage1Test(&bytes, single + 8, 99);

    const second_extension = 82;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    var mark_attach_classes = [_]u16{0} ** 13;
    mark_attach_classes[12] = 2;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The middle ExtensionPos(SinglePos) makes the lookup heterogeneous, so it
    // cannot use the homogeneous PairPos fast path. PairPos wrappers are still
    // ordered alternatives for glyph 10, and mark filtering keeps glyph 12
    // transparent when searching for the second glyph of the pair.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}
fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
