//! Nested lookup flag propagation contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS context nested lookup honors nested lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 74;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 2);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 42);

    fixture.writeU16(&bytes, 16, 7);
    fixture.writeU16(&bytes, 18, 0);
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
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);

    fixture.writeCoverage1(&bytes, context + 22, 1);
    fixture.writeSinglePositionLookup(&bytes, 52, 2, 0x0008, 50);

    const glyphs = [_]GlyphId{ 1, 2 };
    const glyph_classes = [_]u16{ 0, 1, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
