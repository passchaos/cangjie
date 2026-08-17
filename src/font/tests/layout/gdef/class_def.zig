//! Focused GDEF ClassDef contracts.

const std = @import("std");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const sfnt_fixture = @import("../../fixtures/sfnt.zig");

const GlyphClass = gdef.GlyphClass;

test "GDEF ClassDef format 1 validates upper glyph boundary without overflow" {
    var bytes: [14]u8 = .{0} ** 14;
    sfnt_fixture.writeU16(&bytes, 0, 1); // ClassDef format 1.
    sfnt_fixture.writeU16(&bytes, 2, 0xffff); // startGlyphID at the u16 boundary.
    sfnt_fixture.writeU16(&bytes, 4, 1); // Only one class value follows.
    sfnt_fixture.writeU16(&bytes, 6, @intFromEnum(GlyphClass.mark));

    try std.testing.expectEqual(@as(u16, @intFromEnum(GlyphClass.mark)), try gdef.classValue(&bytes, 0, 0xffff));

    // The declared ClassDef span can exceed the physical table when widened.
    // This must report malformed GDEF/SFNT data, not wrap `startGlyphID +
    // glyphCount` and silently treat the boundary glyph as unclassified.
    sfnt_fixture.writeU16(&bytes, 4, 5);
    try std.testing.expectError(error.BadSfnt, gdef.classValue(&bytes, 0, 0xffff));
}

test "GDEF ClassDef format 2 rejects overlapping and reversed ranges" {
    var bytes: [22]u8 = .{0} ** 22;
    sfnt_fixture.writeU16(&bytes, 0, 2); // ClassDef format 2.
    sfnt_fixture.writeU16(&bytes, 2, 3); // Three ClassRangeRecords.
    sfnt_fixture.writeU16(&bytes, 4, 10);
    sfnt_fixture.writeU16(&bytes, 6, 12);
    sfnt_fixture.writeU16(&bytes, 8, @intFromEnum(GlyphClass.base));
    sfnt_fixture.writeU16(&bytes, 10, 12); // Overlaps the previous inclusive range.
    sfnt_fixture.writeU16(&bytes, 12, 14);
    sfnt_fixture.writeU16(&bytes, 14, @intFromEnum(GlyphClass.mark));
    sfnt_fixture.writeU16(&bytes, 16, 20);
    sfnt_fixture.writeU16(&bytes, 18, 18); // Reversed range.
    sfnt_fixture.writeU16(&bytes, 20, @intFromEnum(GlyphClass.component));

    try std.testing.expectError(error.BadSfnt, gdef.classValue(&bytes, 0, 12));

    sfnt_fixture.writeU16(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadSfnt, gdef.classValue(&bytes, 0, 18));
}

test "GDEF dense ClassDef reader fills glyph-indexed metadata" {
    var format1: [12]u8 = .{0} ** 12;
    sfnt_fixture.writeU16(&format1, 0, 1); // ClassDef format 1.
    sfnt_fixture.writeU16(&format1, 2, 2); // startGlyphID.
    sfnt_fixture.writeU16(&format1, 4, 3); // glyphCount.
    sfnt_fixture.writeU16(&format1, 6, @intFromEnum(GlyphClass.base));
    sfnt_fixture.writeU16(&format1, 8, @intFromEnum(GlyphClass.mark));
    sfnt_fixture.writeU16(&format1, 10, @intFromEnum(GlyphClass.component));

    var dense1: [8]u16 = undefined;
    try gdef.readClassDefDense(&format1, 0, @intCast(dense1.len), dense1[0..], true);
    try std.testing.expectEqualSlices(u16, &.{
        0,
        0,
        @intFromEnum(GlyphClass.base),
        @intFromEnum(GlyphClass.mark),
        @intFromEnum(GlyphClass.component),
        0,
        0,
        0,
    }, &dense1);

    var format2: [16]u8 = .{0} ** 16;
    sfnt_fixture.writeU16(&format2, 0, 2); // ClassDef format 2.
    sfnt_fixture.writeU16(&format2, 2, 2); // Two ranges.
    sfnt_fixture.writeU16(&format2, 4, 1);
    sfnt_fixture.writeU16(&format2, 6, 3);
    sfnt_fixture.writeU16(&format2, 8, @intFromEnum(GlyphClass.ligature));
    sfnt_fixture.writeU16(&format2, 10, 5);
    sfnt_fixture.writeU16(&format2, 12, 5);
    sfnt_fixture.writeU16(&format2, 14, 7); // MarkAttachClassDef values are font-defined, not GlyphClass enum values.

    var dense2: [8]u16 = undefined;
    try gdef.readClassDefDense(&format2, 0, @intCast(dense2.len), dense2[0..], false);
    try std.testing.expectEqualSlices(u16, &.{ 0, 2, 2, 2, 0, 7, 0, 0 }, &dense2);

    try std.testing.expectError(error.BadSfnt, gdef.readClassDefDense(&format2, 0, @intCast(dense2.len), dense2[0..], true));
}

test "GDEF coverage indexes canonical format 1 and format 2 tables" {
    var format1: [12]u8 = .{0} ** 12;
    sfnt_fixture.writeU16(&format1, 0, 1);
    sfnt_fixture.writeU16(&format1, 2, 4);
    sfnt_fixture.writeU16(&format1, 4, 2);
    sfnt_fixture.writeU16(&format1, 6, 5);
    sfnt_fixture.writeU16(&format1, 8, 9);
    sfnt_fixture.writeU16(&format1, 10, 12);
    try std.testing.expectEqual(
        @as(?usize, 2),
        try gdef.coverageIndex(&format1, 0, 9),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try gdef.coverageIndex(&format1, 0, 8),
    );

    var format2: [16]u8 = .{0} ** 16;
    sfnt_fixture.writeU16(&format2, 0, 2);
    sfnt_fixture.writeU16(&format2, 2, 2);
    sfnt_fixture.writeU16(&format2, 4, 3);
    sfnt_fixture.writeU16(&format2, 6, 4);
    sfnt_fixture.writeU16(&format2, 8, 0);
    sfnt_fixture.writeU16(&format2, 10, 8);
    sfnt_fixture.writeU16(&format2, 12, 9);
    sfnt_fixture.writeU16(&format2, 14, 2);
    try std.testing.expectEqual(
        @as(?usize, 3),
        try gdef.coverageIndex(&format2, 0, 9),
    );

    sfnt_fixture.writeU16(&format2, 10, 4);
    try std.testing.expectError(
        error.BadSfnt,
        gdef.coverageIndex(&format2, 0, 9),
    );
}
