//! LookupFlag, MarkAttachmentType, and MarkFilteringSet integration contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = fixture.GlyphId;
const accelerator_core = @import("../../../../accelerator/root.zig");
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const table = @import("../../../../table/root.zig");

const Adjustment = positioning.Adjustment;
const LookupAccelerator = accelerator_core.model.Lookup;
const buildLookupAccelerator = accelerator_core.build.lookup.one;
const collectLookup = dispatcher.collect;
const collectLookupWithIndex = dispatcher.collectWithIndex;
const deinitLookupAcceleratorContents =
    accelerator_core.build.lookup.deinitContents;
const Table = table.View;

test "GPOS MarkAttachmentType uses MarkAttachClassDef without glyph classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;

    fixture.writeSinglePositionLookup(&bytes, 0, 5, 0x0100, 33); // MarkAttachmentType 1.
    fixture.writeU16(&bytes, 16, 1);
    fixture.writeU16(&bytes, 18, 2);
    fixture.writeU16(&bytes, 20, 5);
    fixture.writeU16(&bytes, 22, 8);

    const glyphs = [_]GlyphId{ 5, 7, 8 };
    var mark_attach_classes = [_]u16{0} ** 9;
    mark_attach_classes[5] = 2;
    mark_attach_classes[7] = 1;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_attach_classes = &mark_attach_classes,
    });

    // Non-zero MarkAttachClassDef entries identify marks even when GlyphClassDef
    // is absent or incomplete. Glyph 5 is a mark of the wrong attachment type,
    // so the covered SinglePos adjustment must not apply to it. Glyph 8 has no
    // attachment class and still participates as an ordinary glyph.
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}
test "GPOS lookup flags honor GDEF mark filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    fixture.writeU16(&bytes, 4, 1);
    fixture.writeU16(&bytes, 6, 10);
    fixture.writeU16(&bytes, 8, 1); // MarkFilteringSet index.

    const single = 10;
    fixture.writeU16(&bytes, single + 0, 1);
    fixture.writeU16(&bytes, single + 2, 8);
    fixture.writeU16(&bytes, single + 4, 0x0001);
    fixture.writeI16(&bytes, single + 6, 33);
    fixture.writeCoverage1(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);

    // Exercise the cached dispatch path used after Font validation.
    adjustments.clearRetainingCapacity();
    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &adjustments,
        allocator,
        .{
            .mark_filtering_sets = &mark_sets,
            .lookup_accelerators = &accelerators,
            .assume_validated = true,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}
test "GPOS rejects missing GDEF mark filtering set indexes during shaping" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    fixture.writeU16(&bytes, 4, 1);
    fixture.writeU16(&bytes, 6, 10);
    fixture.writeU16(&bytes, 8, 1); // Invalid: only set 0 is supplied below.

    const single = 10;
    fixture.writeU16(&bytes, single + 0, 1);
    fixture.writeU16(&bytes, single + 2, 8);
    fixture.writeU16(&bytes, single + 4, 0x0001);
    fixture.writeI16(&bytes, single + 6, 33);
    fixture.writeCoverage1(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{5};
    const mark_sets = [_][]const GlyphId{&.{5}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    // The MarkFilteringSet field is a direct index into GDEF MarkGlyphSetsDef.
    // Once those sets are available, accepting an out-of-range index would
    // turn malformed positioning into a silent no-op or a glyph-class fallback.
    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
test "GPOS lookup flags combine mark filtering set and attachment type" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0x0210); // MarkAttachmentType 2 + UseMarkFilteringSet.
    fixture.writeU16(&bytes, 4, 1);
    fixture.writeU16(&bytes, 6, 10);
    fixture.writeU16(&bytes, 8, 0); // MarkFilteringSet index.

    const single = 10;
    fixture.writeU16(&bytes, single + 0, 1);
    fixture.writeU16(&bytes, single + 2, 8);
    fixture.writeU16(&bytes, single + 4, 0x0001);
    fixture.writeI16(&bytes, single + 6, 41);
    fixture.writeCoverage1List(&bytes, single + 8, &.{ 5, 7 });

    const glyphs = [_]GlyphId{ 5, 7 };
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var mark_attach_classes = [_]u16{0} ** 8;
    mark_attach_classes[5] = 1;
    mark_attach_classes[7] = 2;
    const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 41), adjustments.items[0].x_placement);
}
