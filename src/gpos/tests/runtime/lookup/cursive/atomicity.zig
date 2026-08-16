//! Whole-lookup CursivePos atomicity contracts.

const std = @import("std");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;
const writeAnchor1Test = writeAnchor1;
const writeCoverage1ListTest = writeCoverage1List;
const writeU16Test = writeU16;

test "GPOS direct cursive positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 3); // CursivePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 46);

    const first_cursive = 10;
    writeU16Test(&bytes, first_cursive + 0, 1);
    writeU16Test(&bytes, first_cursive + 2, 14);
    writeU16Test(&bytes, first_cursive + 4, 2);
    writeU16Test(&bytes, first_cursive + 6, 0);
    writeU16Test(&bytes, first_cursive + 8, 22);
    writeU16Test(&bytes, first_cursive + 10, 28);
    writeU16Test(&bytes, first_cursive + 12, 0);
    writeCoverage1ListTest(&bytes, first_cursive + 14, &.{ 10, 11 });
    writeAnchor1Test(&bytes, first_cursive + 22, 100, 50);
    writeAnchor1Test(&bytes, first_cursive + 28, 20, 10);

    const second_cursive = 46;
    writeU16Test(&bytes, second_cursive + 0, 1);
    writeU16Test(&bytes, second_cursive + 2, 6);
    writeU16Test(&bytes, second_cursive + 4, 1);
    writeU16Test(&bytes, second_cursive + 6, 1); // Truncated Coverage format 1.
    writeU16Test(&bytes, second_cursive + 8, 2);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn writeCoverage1List(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| writeU16(bytes, offset + 4 + index * 2, glyph);
}

fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16(bytes, offset, 1);
    writeI16(bytes, offset + 2, x);
    writeI16(bytes, offset + 4, y);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
