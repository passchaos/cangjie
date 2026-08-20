//! Contextual PosLookupRecord validation and atomicity contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const lookup_dispatcher = @import("../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../positioning/root.zig");
const table_core = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

const Adjustment = positioning.Adjustment;
const Table = table_core.View;
const collectLookup = lookup_dispatcher.collect;
const validateGlyphBounds = validation.font.glyphBounds;
const writeCoverage1Test = fixture.writeCoverage1;
const writeSinglePositionLookup = fixture.writeSinglePositionLookup;
const writeU16Test = fixture.writeU16;
const writeU32Test = fixture.writeU32;

test "GPOS contextual record truncation is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 14);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 28);

    writeSinglePositionLookup(&bytes, 24, 1, 0, 40);

    const context = 44;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    // The second declared PosLookupRecord is beyond table.length below.

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    const table = Table{ .data = &bytes, .offset = 0, .length = rule + 8 };
    try std.testing.expectError(error.BadGpos, collectLookup(table, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
test "GPOS contextual lookup records reject dangling lookup indexes atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 94;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SinglePos.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2); // Dangling: LookupList has only 0 and 1.

    writeSinglePositionLookup(&bytes, 64, 1, 0, 45);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 20));
    try std.testing.expectError(error.BadGpos, collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With every PosLookupRecord targeting an existing lookup, the context
    // preflight succeeds and both nested SinglePos adjustments are visible.
    writeU16Test(&bytes, rule + 10, 1);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
}
test "GPOS contextual lookup records reject sequence indexes outside matched input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 88;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SinglePos.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1); // One input glyph is matched.
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 1); // Invalid: only sequence index 0 exists.
    writeU16Test(&bytes, rule + 6, 1);

    writeSinglePositionLookup(&bytes, 64, 1, 0, 45);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 20));
    try std.testing.expectError(error.BadGpos, collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With a valid SequenceIndex, the same context applies its nested SinglePos
    // and appends a real adjustment for the matched glyph.
    writeU16Test(&bytes, rule + 4, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 45), adjustments.items[0].x_placement);
}
