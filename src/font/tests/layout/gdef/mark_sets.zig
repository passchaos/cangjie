//! Focused GDEF MarkGlyphSetsDef contracts.

const std = @import("std");
const face_mod = @import("../../../face/root.zig");
const font_mod = @import("../../../../font.zig");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const sfnt_fixture = @import("../../fixtures/sfnt.zig");
const table_only = @import("../../fixtures/table_only.zig");

test "reads GDEF mark glyph filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;

    sfnt_fixture.writeU16(&bytes, 0, 1);
    sfnt_fixture.writeU16(&bytes, 2, 2);
    sfnt_fixture.writeU32(&bytes, 4, 12);
    sfnt_fixture.writeU32(&bytes, 8, 22);

    sfnt_fixture.writeU16(&bytes, 12, 1);
    sfnt_fixture.writeU16(&bytes, 14, 2);
    sfnt_fixture.writeU16(&bytes, 16, 5);
    sfnt_fixture.writeU16(&bytes, 18, 9);

    sfnt_fixture.writeU16(&bytes, 22, 2);
    sfnt_fixture.writeU16(&bytes, 24, 2);
    sfnt_fixture.writeU16(&bytes, 26, 20);
    sfnt_fixture.writeU16(&bytes, 28, 21);
    sfnt_fixture.writeU16(&bytes, 30, 0);
    sfnt_fixture.writeU16(&bytes, 32, 30);
    sfnt_fixture.writeU16(&bytes, 34, 32);
    sfnt_fixture.writeU16(&bytes, 36, 2);

    const sets = try gdef.readMarkSets(allocator, &bytes, 0);
    defer gdef.freeMarkSets(allocator, sets);

    try std.testing.expectEqual(@as(usize, 2), sets.len);
    try std.testing.expectEqualSlices(u16, &.{ 5, 9 }, sets[0]);
    try std.testing.expectEqualSlices(u16, &.{ 20, 21, 30, 31, 32 }, sets[1]);
}

test "GDEF MarkGlyphSetsDef rejects coverage offsets into its header" {
    var bytes: [16]u8 = .{0} ** 16;
    sfnt_fixture.writeU16(&bytes, 0, 1); // MarkGlyphSetsDef format.
    sfnt_fixture.writeU16(&bytes, 2, 1); // One CoverageOffset entry follows.
    sfnt_fixture.writeU32(&bytes, 4, 0); // Would reinterpret the MarkGlyphSetsDef header as Coverage format 1.

    try std.testing.expectError(error.BadSfnt, gdef.readMarkSets(std.testing.allocator, &bytes, 0));
}

test "GDEF MarkGlyphSetsDef handles duplicate and unsorted coverage glyphs" {
    const allocator = std.testing.allocator;
    var bytes: [28]u8 = .{0} ** 28;
    sfnt_fixture.writeU16(&bytes, 0, 1); // MarkGlyphSetsDef format.
    sfnt_fixture.writeU16(&bytes, 2, 1);
    sfnt_fixture.writeU32(&bytes, 4, 8);

    sfnt_fixture.writeU16(&bytes, 8, 1); // Coverage format 1.
    sfnt_fixture.writeU16(&bytes, 10, 3);
    sfnt_fixture.writeU16(&bytes, 12, 5);
    sfnt_fixture.writeU16(&bytes, 14, 5); // Duplicate glyphs appear in real GDEF mark-filtering sets.
    sfnt_fixture.writeU16(&bytes, 16, 9);
    const sets = try gdef.readMarkSets(allocator, &bytes, 0);
    defer gdef.freeMarkSets(allocator, sets);
    try std.testing.expectEqualSlices(u16, &.{ 5, 9 }, sets[0]);

    sfnt_fixture.writeU16(&bytes, 12, 9);
    sfnt_fixture.writeU16(&bytes, 14, 5); // Genuinely unsorted; still reject.
    sfnt_fixture.writeU16(&bytes, 16, 10);
    try std.testing.expectError(error.BadSfnt, gdef.readMarkSets(allocator, &bytes, 0));

    sfnt_fixture.writeU16(&bytes, 8, 2); // Coverage format 2.
    sfnt_fixture.writeU16(&bytes, 10, 2);
    sfnt_fixture.writeU16(&bytes, 12, 5);
    sfnt_fixture.writeU16(&bytes, 14, 9);
    sfnt_fixture.writeU16(&bytes, 16, 0);
    sfnt_fixture.writeU16(&bytes, 18, 9); // Overlaps the previous inclusive range.
    sfnt_fixture.writeU16(&bytes, 20, 11);
    sfnt_fixture.writeU16(&bytes, 22, 5);
    try std.testing.expectError(error.BadSfnt, gdef.readMarkSets(allocator, &bytes, 0));
}

test "public GDEF mark glyph sets expose count and strict indexes" {
    const allocator = std.testing.allocator;
    var bytes: [44]u8 = .{0} ** 44;
    sfnt_fixture.writeU16(&bytes, 0, 1);
    sfnt_fixture.writeU16(&bytes, 2, 2);
    sfnt_fixture.writeU16(&bytes, 12, 14);
    sfnt_fixture.writeU16(&bytes, 14, 1);
    sfnt_fixture.writeU16(&bytes, 16, 2);
    sfnt_fixture.writeU32(&bytes, 18, 12);
    sfnt_fixture.writeU32(&bytes, 22, 20);
    sfnt_fixture.writeU16(&bytes, 26, 1);
    sfnt_fixture.writeU16(&bytes, 28, 2);
    sfnt_fixture.writeU16(&bytes, 30, 1);
    sfnt_fixture.writeU16(&bytes, 32, 3);
    sfnt_fixture.writeU16(&bytes, 34, 1);
    sfnt_fixture.writeU16(&bytes, 36, 2);
    sfnt_fixture.writeU16(&bytes, 38, 2);
    sfnt_fixture.writeU16(&bytes, 40, 4);

    var font = table_only.init(font_mod.Font, &bytes, 5, 1);
    font.gdef = table_only.record(
        &bytes,
        .{ 'G', 'D', 'E', 'F' },
        0,
        bytes.len,
    );
    defer font.deinit();
    try std.testing.expectEqual(@as(usize, 2), try font.markGlyphSetCount());

    const first = try font.markGlyphSet(allocator, 0);
    defer allocator.free(first);
    try std.testing.expectEqualSlices(u16, &.{ 1, 3 }, first);
    const second = try font.markGlyphSet(allocator, 1);
    defer allocator.free(second);
    try std.testing.expectEqualSlices(u16, &.{ 2, 4 }, second);
    try std.testing.expectError(
        error.InvalidMarkGlyphSet,
        font.markGlyphSet(allocator, 2),
    );

    const inspected =
        @import("../../../../api/font/metadata/layout/root.zig")
            .inspect(face_mod.backend.face(&font));
    try std.testing.expectEqual(
        @as(usize, 2),
        try inspected.markGlyphSetCount(),
    );
    const inspected_first = try inspected.markGlyphSet(allocator, 0);
    defer allocator.free(inspected_first);
    try std.testing.expectEqualSlices(u16, &.{ 1, 3 }, inspected_first);

    sfnt_fixture.writeU16(&bytes, 32, 5);
    try std.testing.expectError(error.BadSfnt, font.markGlyphSetCount());
}

test "missing GDEF mark set distinguishes count from invalid index" {
    const allocator = std.testing.allocator;
    const inert: [1]u8 = .{0};
    var font = table_only.init(font_mod.Font, &inert, 1, 1);
    defer font.deinit();
    try std.testing.expectEqual(@as(usize, 0), try font.markGlyphSetCount());
    try std.testing.expectError(
        error.InvalidMarkGlyphSet,
        font.markGlyphSet(allocator, 0),
    );
}
