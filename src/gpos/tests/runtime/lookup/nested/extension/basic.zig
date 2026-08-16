//! Nested ExtensionPos target integration contracts.

const std = @import("std");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS context nested lookup can apply extension positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

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
    fixture.writeU16(&bytes, rule + 0, 1);
    fixture.writeU16(&bytes, rule + 2, 1);
    // PosLookupRecord invokes lookup 1, an ExtensionPos wrapping SinglePos, at
    // sequenceIndex 0. Nested extension handling must preserve the context
    // target index rather than ignoring the lookup or applying it globally.
    fixture.writeU16(&bytes, rule + 4, 0);
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeCoverage1(&bytes, context + 22, 3);

    fixture.writeU16(&bytes, 52, 9);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);
    const extension = 60;
    fixture.writeU16(&bytes, extension + 0, 1);
    fixture.writeU16(&bytes, extension + 2, 1);
    fixture.writeU32(&bytes, extension + 4, 8);
    const single = extension + 8;
    fixture.writeU16(&bytes, single + 0, 1);
    fixture.writeU16(&bytes, single + 2, 8);
    fixture.writeU16(&bytes, single + 4, 0x0004);
    fixture.writeI16(&bytes, single + 6, 70);
    fixture.writeCoverage1(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_advance);
}
