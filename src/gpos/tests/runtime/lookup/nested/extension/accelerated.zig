//! Accelerated nested ExtensionPos contextual contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const nested = @import("../../../../../runtime/lookup/nested.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const buildLookupAccelerators = accelerator.build.lookup.all;
const deinitLookupAccelerators = accelerator.build.lookup.deinit;

test "GPOS accelerates nested extension chaining class positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 142;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 10); // Empty ScriptList.
    fixture.writeU16(&bytes, 6, 12); // Empty FeatureList.
    fixture.writeU16(&bytes, 8, 14); // LookupList.
    fixture.writeU16(&bytes, 10, 0);
    fixture.writeU16(&bytes, 12, 0);
    fixture.writeU16(&bytes, 14, 2);
    fixture.writeU16(&bytes, 16, 6); // Lookup 0.
    fixture.writeU16(&bytes, 18, 106); // Lookup 1.

    const extension_lookup = 20;
    fixture.writeU16(&bytes, extension_lookup + 0, 9); // ExtensionPos.
    fixture.writeU16(&bytes, extension_lookup + 2, 0);
    fixture.writeU16(&bytes, extension_lookup + 4, 1);
    fixture.writeU16(&bytes, extension_lookup + 6, 8);

    const extension = 28;
    fixture.writeU16(&bytes, extension + 0, 1);
    fixture.writeU16(&bytes, extension + 2, 8); // ChainContextPos.
    fixture.writeU32(&bytes, extension + 4, 8);

    const chain = 36;
    fixture.writeU16(&bytes, chain + 0, 2); // Chaining class format.
    fixture.writeU16(&bytes, chain + 2, 50); // Coverage.
    fixture.writeU16(&bytes, chain + 4, 56); // Empty backtrack ClassDef.
    fixture.writeU16(&bytes, chain + 6, 62); // Input ClassDef.
    fixture.writeU16(&bytes, chain + 8, 70); // Lookahead ClassDef.
    fixture.writeU16(&bytes, chain + 10, 2);
    fixture.writeU16(&bytes, chain + 12, 0);
    fixture.writeU16(&bytes, chain + 14, 16); // Class 1 rule set.

    const set = chain + 16;
    fixture.writeU16(&bytes, set + 0, 2);
    fixture.writeU16(&bytes, set + 2, 6);
    fixture.writeU16(&bytes, set + 4, 20);
    const first_rule = set + 6;
    fixture.writeU16(&bytes, first_rule + 0, 0); // BacktrackCount.
    fixture.writeU16(&bytes, first_rule + 2, 1); // InputCount.
    fixture.writeU16(&bytes, first_rule + 4, 1); // LookaheadCount.
    fixture.writeU16(&bytes, first_rule + 6, 3); // Non-matching lookahead class.
    fixture.writeU16(&bytes, first_rule + 8, 1);
    fixture.writeU16(&bytes, first_rule + 10, 0);
    fixture.writeU16(&bytes, first_rule + 12, 1);
    const second_rule = set + 20;
    fixture.writeU16(&bytes, second_rule + 0, 0);
    fixture.writeU16(&bytes, second_rule + 2, 1);
    fixture.writeU16(&bytes, second_rule + 4, 1);
    fixture.writeU16(&bytes, second_rule + 6, 2); // Matching lookahead class.
    fixture.writeU16(&bytes, second_rule + 8, 1);
    fixture.writeU16(&bytes, second_rule + 10, 0);
    fixture.writeU16(&bytes, second_rule + 12, 1);

    fixture.writeCoverage1(&bytes, chain + 50, 10);
    fixture.writeU16(&bytes, chain + 56, 1); // Empty ClassDef format 1.
    fixture.writeU16(&bytes, chain + 58, 0);
    fixture.writeU16(&bytes, chain + 60, 0);
    fixture.writeClassDef1(&bytes, chain + 62, 10, 1);
    fixture.writeClassDef1(&bytes, chain + 70, 20, 2);

    fixture.writeSinglePositionLookup(&bytes, 120, 10, 0, 50);

    const glyphs = [_]GlyphId{ 10, 20 };
    const accelerators = try buildLookupAccelerators(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);
    try std.testing.expect(accelerators[0].chaining_class_subtables.len != 0);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try nested.apply(.{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true }, &glyphs, 0, 0, &adjustments, allocator, .{
        .lookup_accelerators = accelerators,
        .assume_validated = true,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 50), adjustments.items[0].x_placement);
}

test "GPOS accelerates nested extension MarkLigPos at only its target" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 86);
    fixture.writeU16(&bytes, 6, 88);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);

    const lookup = 14;
    fixture.writeU16(&bytes, lookup + 0, 9);
    fixture.writeU16(&bytes, lookup + 2, 0);
    fixture.writeU16(&bytes, lookup + 4, 1);
    fixture.writeU16(&bytes, lookup + 6, 8);
    const wrapper = 22;
    fixture.writeU16(&bytes, wrapper + 0, 1);
    fixture.writeU16(&bytes, wrapper + 2, 5);
    fixture.writeU32(&bytes, wrapper + 4, 8);

    const mark_ligature = 30;
    fixture.writeU16(&bytes, mark_ligature + 0, 1);
    fixture.writeU16(&bytes, mark_ligature + 2, 12);
    fixture.writeU16(&bytes, mark_ligature + 4, 18);
    fixture.writeU16(&bytes, mark_ligature + 6, 1);
    fixture.writeU16(&bytes, mark_ligature + 8, 24);
    fixture.writeU16(&bytes, mark_ligature + 10, 36);
    fixture.writeCoverage1(&bytes, mark_ligature + 12, 22);
    fixture.writeCoverage1(&bytes, mark_ligature + 18, 20);
    fixture.writeU16(&bytes, mark_ligature + 24, 1);
    fixture.writeU16(&bytes, mark_ligature + 26, 0);
    fixture.writeU16(&bytes, mark_ligature + 28, 6);
    fixture.writeAnchor1(&bytes, mark_ligature + 30, 10, 15);
    fixture.writeU16(&bytes, mark_ligature + 36, 1);
    fixture.writeU16(&bytes, mark_ligature + 38, 4);
    fixture.writeU16(&bytes, mark_ligature + 40, 1);
    fixture.writeU16(&bytes, mark_ligature + 42, 4);
    fixture.writeAnchor1(&bytes, mark_ligature + 44, 100, 120);
    fixture.writeU16(&bytes, 86, 0);
    fixture.writeU16(&bytes, 88, 0);

    const accelerators = try buildLookupAccelerators(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer deinitLookupAccelerators(allocator, accelerators);
    try std.testing.expectEqual(
        @as(usize, 1),
        accelerators[0].mark_to_ligature_subtables.len,
    );
    // A later covered mark proves nested execution does not accidentally run
    // the whole prepared subtable. Poisoning borrowed Coverage values proves
    // the exact ExtensionPos sidecar is the path that handles the target.
    fixture.writeU16(&bytes, mark_ligature + 16, 99);
    fixture.writeU16(&bytes, mark_ligature + 22, 99);
    const glyphs = [_]GlyphId{ 20, 22, 20, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try nested.apply(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, &glyphs, 1, 0, &adjustments, allocator, .{
        .lookup_accelerators = accelerators,
        .assume_validated = true,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
}
