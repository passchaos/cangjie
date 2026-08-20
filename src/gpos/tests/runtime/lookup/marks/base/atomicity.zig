//! Whole-lookup MarkBasePos atomicity contracts.

const std = @import("std");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;
const writeAnchor1Test = writeAnchor1;
const writeCoverage1Test = writeCoverage1;
const writeU16Test = writeU16;

test "GPOS direct mark-to-base positioning preflights anchor arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 58);

    const first_mark_base = 10;
    writeU16Test(&bytes, first_mark_base + 0, 1);
    writeU16Test(&bytes, first_mark_base + 2, 12);
    writeU16Test(&bytes, first_mark_base + 4, 18);
    writeU16Test(&bytes, first_mark_base + 6, 1);
    writeU16Test(&bytes, first_mark_base + 8, 24);
    writeU16Test(&bytes, first_mark_base + 10, 36);
    writeCoverage1Test(&bytes, first_mark_base + 12, 2);
    writeCoverage1Test(&bytes, first_mark_base + 18, 1);
    const first_mark_array = first_mark_base + 24;
    writeU16Test(&bytes, first_mark_array + 0, 1);
    writeU16Test(&bytes, first_mark_array + 2, 0);
    writeU16Test(&bytes, first_mark_array + 4, 6);
    writeAnchor1Test(&bytes, first_mark_array + 6, 20, 30);
    const first_base_array = first_mark_base + 36;
    writeU16Test(&bytes, first_base_array + 0, 1);
    writeU16Test(&bytes, first_base_array + 2, 4);
    writeAnchor1Test(&bytes, first_base_array + 4, 100, 100);

    const second_mark_base = 58;
    writeU16Test(&bytes, second_mark_base + 0, 1);
    writeU16Test(&bytes, second_mark_base + 2, 12);
    writeU16Test(&bytes, second_mark_base + 4, 18);
    writeU16Test(&bytes, second_mark_base + 6, 1);
    writeU16Test(&bytes, second_mark_base + 8, 24);
    writeU16Test(&bytes, second_mark_base + 10, 30);
    writeCoverage1Test(&bytes, second_mark_base + 12, 2);
    writeCoverage1Test(&bytes, second_mark_base + 18, 1);
    const second_mark_array = second_mark_base + 24;
    writeU16Test(&bytes, second_mark_array + 0, 1);
    writeU16Test(&bytes, second_mark_array + 2, 0);
    writeU16Test(&bytes, second_mark_array + 4, 8); // Anchor starts exactly at table.length.

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
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
