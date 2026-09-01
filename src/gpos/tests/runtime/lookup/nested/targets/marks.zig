//! Nested marks target integration contracts.

const std = @import("std");
const fixture = @import("../fixture.zig");
const GlyphId = fixture.GlyphId;
const dispatcher = @import("../../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../../positioning/root.zig");

const Adjustment = positioning.Adjustment;
const collectLookup = dispatcher.collect;

test "GPOS context nested lookup can apply MarkBasePos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

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
    fixture.writeU16(&bytes, rule + 4, 12);
    // PosLookupRecord sequenceIndex=1 invokes MarkBasePos on the matched mark.
    // The nested lookup still needs the full run so it can locate glyph 10 as
    // the previous base, but it must not position marks outside this record.
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 10);

    fixture.writeU16(&bytes, 52, 4);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);

    const mark_base = 60;
    fixture.writeU16(&bytes, mark_base + 0, 1);
    fixture.writeU16(&bytes, mark_base + 2, 12);
    fixture.writeU16(&bytes, mark_base + 4, 18);
    fixture.writeU16(&bytes, mark_base + 6, 1);
    fixture.writeU16(&bytes, mark_base + 8, 24);
    fixture.writeU16(&bytes, mark_base + 10, 36);

    fixture.writeCoverage1(&bytes, mark_base + 12, 12);
    fixture.writeCoverage1(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    fixture.writeU16(&bytes, mark_array + 0, 1);
    fixture.writeU16(&bytes, mark_array + 2, 0);
    fixture.writeU16(&bytes, mark_array + 4, 6);
    fixture.writeAnchor1(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    fixture.writeU16(&bytes, base_array + 0, 1);
    fixture.writeU16(&bytes, base_array + 2, 4);
    fixture.writeAnchor1(&bytes, base_array + 4, 80, 120);

    const glyphs = [_]GlyphId{ 10, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}
test "GPOS context nested lookup applies MarkLigPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

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
    fixture.writeU16(&bytes, rule + 4, 22);
    // The context matches only [20, 22], but the nested MarkLigPos subtable
    // also covers the later [21, 22] cluster. PosLookupRecord sequenceIndex=1
    // must therefore attach just the matched mark while still using the full
    // run to find glyph 20 as its preceding ligature.
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 20);

    fixture.writeU16(&bytes, 52, 5);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);

    const mark_lig = 60;
    fixture.writeU16(&bytes, mark_lig + 0, 1);
    fixture.writeU16(&bytes, mark_lig + 2, 12);
    fixture.writeU16(&bytes, mark_lig + 4, 18);
    fixture.writeU16(&bytes, mark_lig + 6, 1);
    fixture.writeU16(&bytes, mark_lig + 8, 26);
    fixture.writeU16(&bytes, mark_lig + 10, 38);

    fixture.writeCoverage1(&bytes, mark_lig + 12, 22);
    fixture.writeCoverage1List(&bytes, mark_lig + 18, &.{ 20, 21 });

    const mark_array = mark_lig + 26;
    fixture.writeU16(&bytes, mark_array + 0, 1);
    fixture.writeU16(&bytes, mark_array + 2, 0);
    fixture.writeU16(&bytes, mark_array + 4, 6);
    fixture.writeAnchor1(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 38;
    fixture.writeU16(&bytes, ligature_array + 0, 2);
    fixture.writeU16(&bytes, ligature_array + 2, 6);
    fixture.writeU16(&bytes, ligature_array + 4, 16);

    const first_ligature_attach = ligature_array + 6;
    fixture.writeU16(&bytes, first_ligature_attach + 0, 1);
    fixture.writeU16(&bytes, first_ligature_attach + 2, 4);
    fixture.writeAnchor1(&bytes, first_ligature_attach + 4, 100, 120);

    const second_ligature_attach = ligature_array + 16;
    fixture.writeU16(&bytes, second_ligature_attach + 0, 1);
    fixture.writeU16(&bytes, second_ligature_attach + 2, 4);
    fixture.writeAnchor1(&bytes, second_ligature_attach + 4, 200, 220);

    const glyphs = [_]GlyphId{ 20, 22, 21, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS context nested lookup uses exact MarkLigPos sidecar" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 132;

    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 128);
    fixture.writeU16(&bytes, 6, 130);
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
    fixture.writeU16(&bytes, rule + 4, 22);
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 20);

    fixture.writeU16(&bytes, 52, 5);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);
    const mark_lig = 60;
    fixture.writeU16(&bytes, mark_lig + 0, 1);
    fixture.writeU16(&bytes, mark_lig + 2, 12);
    fixture.writeU16(&bytes, mark_lig + 4, 18);
    fixture.writeU16(&bytes, mark_lig + 6, 1);
    fixture.writeU16(&bytes, mark_lig + 8, 26);
    fixture.writeU16(&bytes, mark_lig + 10, 38);
    fixture.writeCoverage1(&bytes, mark_lig + 12, 22);
    fixture.writeCoverage1List(&bytes, mark_lig + 18, &.{ 20, 21 });
    fixture.writeU16(&bytes, mark_lig + 26, 1);
    fixture.writeU16(&bytes, mark_lig + 28, 0);
    fixture.writeU16(&bytes, mark_lig + 30, 6);
    fixture.writeAnchor1(&bytes, mark_lig + 32, 10, 15);
    fixture.writeU16(&bytes, mark_lig + 38, 2);
    fixture.writeU16(&bytes, mark_lig + 40, 6);
    fixture.writeU16(&bytes, mark_lig + 42, 16);
    fixture.writeU16(&bytes, mark_lig + 44, 1);
    fixture.writeU16(&bytes, mark_lig + 46, 4);
    fixture.writeAnchor1(&bytes, mark_lig + 48, 100, 120);
    fixture.writeU16(&bytes, mark_lig + 54, 1);
    fixture.writeU16(&bytes, mark_lig + 56, 4);
    fixture.writeAnchor1(&bytes, mark_lig + 58, 200, 220);
    fixture.writeU16(&bytes, 128, 0);
    fixture.writeU16(&bytes, 130, 0);

    const accelerators = try @import("../../../../../accelerator/root.zig")
        .build.lookup.all(&bytes, 0, bytes.len, allocator);
    defer @import("../../../../../accelerator/root.zig")
        .build.lookup.deinit(allocator, accelerators);
    // Poison only borrowed coverage glyph ids after the immutable sidecar has
    // captured them. The contextual target must use lookup 1's exact sidecar.
    fixture.writeU16(&bytes, mark_lig + 16, 99);
    fixture.writeU16(&bytes, mark_lig + 22, 99);

    const glyphs = [_]GlyphId{ 20, 22, 21, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try collectLookup(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 16, &glyphs, &adjustments, allocator, .{
        .lookup_accelerators = accelerators,
        .assume_validated = true,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
}

test "GPOS context nested lookup applies MarkToMarkPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 116;

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
    fixture.writeU16(&bytes, rule + 4, 12);
    // The matched input is [10, 12], and sequenceIndex=1 targets only that
    // second glyph. A later [13, 12] mark pair is covered by MarkToMarkPos too,
    // so a nested implementation that rescans the entire run would incorrectly
    // attach the final glyph as well.
    fixture.writeU16(&bytes, rule + 6, 1);
    fixture.writeU16(&bytes, rule + 8, 1);
    fixture.writeCoverage1(&bytes, context + 22, 10);

    fixture.writeU16(&bytes, 52, 6);
    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 8);

    const mark_mark = 60;
    fixture.writeU16(&bytes, mark_mark + 0, 1);
    fixture.writeU16(&bytes, mark_mark + 2, 12);
    fixture.writeU16(&bytes, mark_mark + 4, 18);
    fixture.writeU16(&bytes, mark_mark + 6, 1);
    fixture.writeU16(&bytes, mark_mark + 8, 26);
    fixture.writeU16(&bytes, mark_mark + 10, 38);

    fixture.writeCoverage1(&bytes, mark_mark + 12, 12);
    fixture.writeCoverage1List(&bytes, mark_mark + 18, &.{ 10, 13 });

    const mark_1_array = mark_mark + 26;
    fixture.writeU16(&bytes, mark_1_array + 0, 1);
    fixture.writeU16(&bytes, mark_1_array + 2, 0);
    fixture.writeU16(&bytes, mark_1_array + 4, 6);
    fixture.writeAnchor1(&bytes, mark_1_array + 6, 10, 15);

    const mark_2_array = mark_mark + 38;
    fixture.writeU16(&bytes, mark_2_array + 0, 2);
    fixture.writeU16(&bytes, mark_2_array + 2, 6);
    fixture.writeU16(&bytes, mark_2_array + 4, 12);
    fixture.writeAnchor1(&bytes, mark_2_array + 6, 80, 120);
    fixture.writeAnchor1(&bytes, mark_2_array + 12, 200, 220);

    const glyphs = [_]GlyphId{ 10, 12, 13, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}
