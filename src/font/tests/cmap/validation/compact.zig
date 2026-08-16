//! Focused cmap validation contracts.

const std = @import("std");
const cmap_mod = @import("../../../tables/cmap/root.zig");
const glyph = @import("../../../../glyph.zig");
const sfnt = @import("../../../sfnt/root.zig");
const font_mod = @import("../../../../font.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;
const TableRecord = sfnt.Record;

test "cmap format 2 validates subheader and glyph-array bounds" {
    var valid: [12 + 536]u8 = .{0} ** (12 + 536);
    fixture.writeU16(&valid, 2, 1);
    fixture.writeU16(&valid, 4, 3);
    fixture.writeU16(&valid, 6, 2);
    fixture.writeU32(&valid, 8, 12);
    const subtable = 12;
    fixture.writeU16(&valid, subtable, 2);
    fixture.writeU16(&valid, subtable + 2, 536);
    fixture.writeU16(&valid, subtable + 6 + 0x12 * 2, 8); // High byte 0x12 uses SubHeader[1].
    fixture.writeU16(&valid, subtable + 518, 0);
    fixture.writeU16(&valid, subtable + 520, 0);
    fixture.writeU16(&valid, subtable + 526, 0x34);
    fixture.writeU16(&valid, subtable + 528, 1);
    fixture.writeI16(&valid, subtable + 530, 0);
    fixture.writeU16(&valid, subtable + 532, 2);
    fixture.writeU16(&valid, subtable + 534, 77);

    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = valid.len,
    };
    const subtables = try cmap_mod.parse(std.testing.allocator, &valid, cmap, 128);
    defer std.testing.allocator.free(subtables);
    try std.testing.expectEqual(@as(glyph.GlyphId, 77), try cmap_mod.glyph(&valid, .{ .platform_id = 3, .encoding_id = 2, .offset = subtable, .length = 536, .format = 2 }, 0x1234));

    var unaligned_key = valid;
    fixture.writeU16(&unaligned_key, subtable + 6 + 0x12 * 2, 10);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(std.testing.allocator, &unaligned_key, cmap, 128));

    var backwards_range = valid;
    fixture.writeU16(&backwards_range, subtable + 532, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(std.testing.allocator, &backwards_range, cmap, 128));
}

test "Unicode cmap format 2 rejects surrogate character ranges" {
    var surrogate: [12 + 536]u8 = .{0} ** (12 + 536);
    fixture.writeU16(&surrogate, 2, 1); // One EncodingRecord.
    fixture.writeU16(&surrogate, 4, 0); // Unicode platform.
    fixture.writeU16(&surrogate, 6, 2); // Deprecated but Unicode scalar cmap_mod.
    fixture.writeU32(&surrogate, 8, 12);
    const subtable = 12;
    fixture.writeU16(&surrogate, subtable, 2);
    fixture.writeU16(&surrogate, subtable + 2, 536);
    fixture.writeU16(&surrogate, subtable + 6 + 0xd8 * 2, 8); // High byte 0xd8 uses SubHeader[1].
    fixture.writeU16(&surrogate, subtable + 526, 0); // Low byte 0 starts at U+d800.
    fixture.writeU16(&surrogate, subtable + 528, 1);
    fixture.writeI16(&surrogate, subtable + 530, 0);
    fixture.writeU16(&surrogate, subtable + 532, 2);
    fixture.writeU16(&surrogate, subtable + 534, 1);

    const unicode_cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = surrogate.len,
    };
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(std.testing.allocator, &surrogate, unicode_cmap, 128));

    // Legacy Windows code-page format-2 subtables are byte-code maps rather
    // than Unicode scalar maps. Keep accepting the same byte range there so the
    // surrogate check does not reject non-Unicode East Asian production fonts.
    fixture.writeU16(&surrogate, 4, 3);
    fixture.writeU16(&surrogate, 6, 2);
    const legacy_subtables = try cmap_mod.parse(std.testing.allocator, &surrogate, unicode_cmap, 128);
    defer std.testing.allocator.free(legacy_subtables);
}

test "cmap format 6 and 10 validate declared array size and Unicode range" {
    var format6: [12]u8 = .{0} ** 12;
    fixture.writeU16(&format6, 0, 6);
    fixture.writeU16(&format6, 2, format6.len);
    fixture.writeU16(&format6, 6, 'A');
    fixture.writeU16(&format6, 8, 1);
    fixture.writeU16(&format6, 10, 5);
    try cmap_mod.validateNumericFormat(
        &format6,
        0,
        format6.len,
        6,
        true,
    );
    try std.testing.expectEqual(@as(glyph.GlyphId, 5), try cmap_mod.glyph(&format6, .{ .platform_id = 0, .encoding_id = 3, .offset = 0, .length = format6.len, .format = 6 }, 'A'));

    var truncated_format6 = format6;
    fixture.writeU16(&truncated_format6, 2, 10);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &truncated_format6,
            0,
            10,
            6,
            true,
        ),
    );

    var overflowing_format6: [14]u8 = .{0} ** 14;
    fixture.writeU16(&overflowing_format6, 0, 6);
    fixture.writeU16(&overflowing_format6, 2, overflowing_format6.len);
    fixture.writeU16(&overflowing_format6, 6, 0xffff);
    fixture.writeU16(&overflowing_format6, 8, 2);
    fixture.writeU16(&overflowing_format6, 10, 1);
    fixture.writeU16(&overflowing_format6, 12, 2);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &overflowing_format6,
            0,
            overflowing_format6.len,
            6,
            true,
        ),
    );

    var format10: [22]u8 = .{0} ** 22;
    fixture.writeU16(&format10, 0, 10);
    fixture.writeU32(&format10, 4, format10.len);
    fixture.writeU32(&format10, 12, 0x10ffff);
    fixture.writeU32(&format10, 16, 1);
    fixture.writeU16(&format10, 20, 9);
    try cmap_mod.validateNumericFormat(
        &format10,
        0,
        format10.len,
        10,
        true,
    );
    try std.testing.expectEqual(@as(glyph.GlyphId, 9), try cmap_mod.glyph(&format10, .{ .platform_id = 0, .encoding_id = 4, .offset = 0, .length = format10.len, .format = 10 }, 0x10ffff));

    var overflowing_format10 = format10;
    fixture.writeU32(&overflowing_format10, 12, 0x110000);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &overflowing_format10,
            0,
            overflowing_format10.len,
            10,
            true,
        ),
    );

    var surrogate_format10 = format10;
    fixture.writeU32(&surrogate_format10, 12, 0xd800);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &surrogate_format10,
            0,
            surrogate_format10.len,
            10,
            true,
        ),
    );

    var surrogate_spanning_format10: [24]u8 = .{0} ** 24;
    fixture.writeU16(&surrogate_spanning_format10, 0, 10);
    fixture.writeU32(&surrogate_spanning_format10, 4, surrogate_spanning_format10.len);
    fixture.writeU32(&surrogate_spanning_format10, 12, 0xd7ff);
    fixture.writeU32(&surrogate_spanning_format10, 16, 2);
    fixture.writeU16(&surrogate_spanning_format10, 20, 9);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &surrogate_spanning_format10,
            0,
            surrogate_spanning_format10.len,
            10,
            true,
        ),
    );

    var extra_bytes_format10: [24]u8 = .{0} ** 24;
    fixture.writeU16(&extra_bytes_format10, 0, 10);
    fixture.writeU32(&extra_bytes_format10, 4, extra_bytes_format10.len);
    fixture.writeU32(&extra_bytes_format10, 12, 'A');
    fixture.writeU32(&extra_bytes_format10, 16, 1);
    fixture.writeU16(&extra_bytes_format10, 20, 9);
    try std.testing.expectError(
        error.BadSfnt,
        cmap_mod.validateNumericFormat(
            &extra_bytes_format10,
            0,
            extra_bytes_format10.len,
            10,
            true,
        ),
    );
}
