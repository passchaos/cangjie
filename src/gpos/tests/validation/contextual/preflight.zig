//! Whole-context lookup preflight and atomic output contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const lookup_dispatcher = @import("../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = lookup_dispatcher.collect;
const writeCoverage1Test = fixture.writeCoverage1;
const writeI16Test = fixture.writeI16;
const writeSinglePositionLookup = fixture.writeSinglePositionLookup;
const writeU16Test = fixture.writeU16;
const writeU32Test = fixture.writeU32;

test "GPOS contextual lookup preflight rejects later truncated lookup atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    // Lookup 2 is referenced only after lookup 1 would append an adjustment.
    // Its truncated SubTable offset array must be caught before collecting any
    // nested result from the contextual match.
    writeU16Test(&bytes, 90, 1);
    writeU16Test(&bytes, 94, 1);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
test "GPOS contextual lookup preflight rejects missing nested mark filtering sets atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 14, 60); // Lookup 1: valid SinglePos.
    writeU16Test(&bytes, 16, 84); // Lookup 2: SinglePos with a bad MarkFilteringSet index.

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);
    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    const bad_lookup = 94;
    writeU16Test(&bytes, bad_lookup + 0, 1);
    writeU16Test(&bytes, bad_lookup + 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, bad_lookup + 4, 1);
    writeU16Test(&bytes, bad_lookup + 6, 10);
    writeU16Test(&bytes, bad_lookup + 8, 1); // Invalid: only set 0 is supplied below.
    const single = bad_lookup + 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 1);

    const glyphs = [_]GlyphId{1};
    const mark_sets = [_][]const GlyphId{&.{1}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
test "GPOS contextual lookup preflight rejects nested extension payload atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    writeU16Test(&bytes, 90, 9);
    writeU16Test(&bytes, 94, 1);
    writeU16Test(&bytes, 96, 8);
    const extension = 98;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    // The ExtensionPos wrapper header is present, but its wrapped SinglePos
    // payload is outside this table. Reject the whole contextual match before
    // the preceding record appends its adjustment.
    writeU32Test(&bytes, extension + 4, 20);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
test "GPOS context lookup preflights later malformed subtable atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Lookup 0: ContextPos with two subtables.
    writeU16Test(&bytes, 14, 30); // Lookup 1: nested SinglePos.

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 2);
    writeU16Test(&bytes, 22, 48);
    writeU16Test(&bytes, 24, 80);
    writeSinglePositionLookup(&bytes, 40, 5, 0, 33);

    const first_context = 64;
    writeU16Test(&bytes, first_context + 0, 1);
    writeU16Test(&bytes, first_context + 2, 22);
    writeU16Test(&bytes, first_context + 4, 1);
    writeU16Test(&bytes, first_context + 6, 8);
    writeU16Test(&bytes, first_context + 8, 1);
    writeU16Test(&bytes, first_context + 10, 4);
    writeU16Test(&bytes, first_context + 12, 1);
    writeU16Test(&bytes, first_context + 14, 1);
    writeU16Test(&bytes, first_context + 16, 0);
    writeU16Test(&bytes, first_context + 18, 1);
    writeCoverage1Test(&bytes, first_context + 22, 5);

    const malformed_context = 96;
    writeU16Test(&bytes, malformed_context + 0, 1);
    writeU16Test(&bytes, malformed_context + 2, 16);
    writeU16Test(&bytes, malformed_context + 4, 1);
    writeU16Test(&bytes, malformed_context + 6, 24);
    writeCoverage1Test(&bytes, malformed_context + 16, 5);
    writeU16Test(&bytes, malformed_context + 24, 1);
    writeU16Test(&bytes, malformed_context + 26, 4);
    writeU16Test(&bytes, malformed_context + 28, 1);
    writeU16Test(&bytes, malformed_context + 30, 2);
    writeU16Test(&bytes, malformed_context + 32, 0);
    writeU16Test(&bytes, malformed_context + 34, 1);
    // The second declared PosLookupRecord begins exactly at table.length below.

    const glyphs = [_]GlyphId{5};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = 132 }, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
