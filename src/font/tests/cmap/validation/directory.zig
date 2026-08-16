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

test "cmap parser rejects subtable length past cmap table boundary" {
    const allocator = std.testing.allocator;
    var data: [44]u8 = .{0} ** 44;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 20,
    };

    fixture.writeU16(&data, 0, 0);
    fixture.writeU16(&data, 2, 1);
    fixture.writeU16(&data, 4, 3);
    fixture.writeU16(&data, 6, 10);
    fixture.writeU32(&data, 8, 12);
    fixture.writeU16(&data, 12, 12);
    fixture.writeU32(&data, 16, 28);
    fixture.writeU32(&data, 24, 1);
    fixture.writeU32(&data, 28, 'A');
    fixture.writeU32(&data, 32, 'A');
    fixture.writeU32(&data, 36, 9);

    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &data, cmap, 128));
}

test "cmap format 0 length is fixed at parse time" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    inline for (.{ @as(u16, 261), @as(u16, 263) }) |length| {
        const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
        defer allocator.free(bytes);
        const cmap_offset = try fixture.tableOffset(bytes, "cmap");
        // Format 0 has no variable payload: padding belongs to the enclosing
        // SFNT table, not to the cmap subtable's declared length.
        fixture.writeU16(bytes, cmap_offset + 14, length);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "cmap header version and encoding records are canonical" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 282,
    };

    var valid: [282]u8 = .{0} ** 282;
    fixture.writeU16(&valid, 0, 0);
    fixture.writeU16(&valid, 2, 2);
    fixture.writeU16(&valid, 4, 0);
    fixture.writeU16(&valid, 6, 0);
    fixture.writeU32(&valid, 8, 20);
    fixture.writeU16(&valid, 12, 0);
    fixture.writeU16(&valid, 14, 1);
    fixture.writeU32(&valid, 16, 20);
    fixture.writeU16(&valid, 20, 0);
    fixture.writeU16(&valid, 22, 262);

    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 1);
    defer allocator.free(subtables);
    try std.testing.expectEqual(@as(usize, 2), subtables.len);

    var bad_version = valid;
    fixture.writeU16(&bad_version, 0, 1);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bad_version, cmap, 1));

    var duplicate_encoding = valid;
    fixture.writeU16(&duplicate_encoding, 14, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &duplicate_encoding, cmap, 1));

    var unsorted_encoding = valid;
    fixture.writeU16(&unsorted_encoding, 6, 1);
    fixture.writeU16(&unsorted_encoding, 14, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unsorted_encoding, cmap, 1));

    var header_alias = valid;
    fixture.writeU32(&header_alias, 8, 0); // Reinterprets the cmap version/count fields as a subtable header.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &header_alias, cmap, 1));

    var record_alias = valid;
    fixture.writeU32(&record_alias, 8, 12); // Points into the second EncodingRecord rather than a child subtable.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &record_alias, cmap, 1));
}

test "cmap platform and encoding records allow only compatible formats" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 44,
        };
        var format4: [44]u8 = .{0} ** 44;
        support.writeFormat4Header(&format4, format4.len - 12);
        support.writeFormat4Segment(&format4, 0, 'A', 'A', @as(i16, 1) - @as(i16, @bitCast(@as(u16, 'A'))), 0);
        support.writeFormat4Segment(&format4, 1, 0xffff, 0xffff, 1, 0);
        const subtables = try cmap_mod.parse(allocator, &format4, cmap, 512);
        allocator.free(subtables);

        var variation_sequence_format4 = format4;
        fixture.writeU16(&variation_sequence_format4, 4, 0);
        fixture.writeU16(&variation_sequence_format4, 6, 5);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &variation_sequence_format4, cmap, 512));

        var full_repertoire_format4 = format4;
        fixture.writeU16(&full_repertoire_format4, 6, 10);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &full_repertoire_format4, cmap, 512));

        var unknown_unicode_encoding_format4 = full_repertoire_format4;
        fixture.writeU16(&unknown_unicode_encoding_format4, 4, 0);
        const unknown_unicode_encoding = try cmap_mod.parse(allocator, &unknown_unicode_encoding_format4, cmap, 512);
        allocator.free(unknown_unicode_encoding);

        // Unknown Unicode encoding IDs may carry ordinary maps, but must not
        // appropriate the registered variation-sequence or last-resort formats.
        var unknown_variation_format = unknown_unicode_encoding_format4;
        fixture.writeU16(&unknown_variation_format, 12, 14);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unknown_variation_format, cmap, 512));
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 40,
        };
        var format12: [40]u8 = .{0} ** 40;
        support.writeFormat12Header(&format12, format12.len - 12, 1);
        support.writeGroup(&format12, 28, 0x100, 0x100, 1);
        const subtables = try cmap_mod.parse(allocator, &format12, cmap, 512);
        allocator.free(subtables);

        var bmp_format12 = format12;
        fixture.writeU16(&bmp_format12, 6, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bmp_format12, cmap, 512));

        var last_resort_format12 = format12;
        fixture.writeU16(&last_resort_format12, 4, 0);
        fixture.writeU16(&last_resort_format12, 6, 6);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &last_resort_format12, cmap, 512));

        var format13 = last_resort_format12;
        fixture.writeU16(&format13, 12, 13);
        const format13_subtables = try cmap_mod.parse(allocator, &format13, cmap, 512);
        allocator.free(format13_subtables);

        var windows_format13 = format13;
        fixture.writeU16(&windows_format13, 4, 3);
        fixture.writeU16(&windows_format13, 6, 10);
        const windows_format13_subtables = try cmap_mod.parse(allocator, &windows_format13, cmap, 512);
        allocator.free(windows_format13_subtables);
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 22,
        };
        var format14: [22]u8 = .{0} ** 22;
        support.writeFormat14Header(&format14, 10, 0);
        const subtables = try cmap_mod.parse(allocator, &format14, cmap, 512);
        allocator.free(subtables);

        var non_uvs_format14 = format14;
        fixture.writeU16(&non_uvs_format14, 4, 3);
        fixture.writeU16(&non_uvs_format14, 6, 10);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &non_uvs_format14, cmap, 512));
    }
}

test "cmap language fields require zero outside Macintosh platform" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 274,
        };
        var format0: [274]u8 = .{0} ** 274;
        fixture.writeU16(&format0, 0, 0); // cmap version.
        fixture.writeU16(&format0, 2, 1);
        fixture.writeU16(&format0, 4, 0); // Unicode platform, deprecated default semantics.
        fixture.writeU16(&format0, 6, 0);
        fixture.writeU32(&format0, 8, 12);
        fixture.writeU16(&format0, 12, 0);
        fixture.writeU16(&format0, 14, 262);

        const subtables = try cmap_mod.parse(allocator, &format0, cmap, 2);
        allocator.free(subtables);

        var unicode_language = format0;
        fixture.writeU16(&unicode_language, 16, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unicode_language, cmap, 2));

        var mac_language = unicode_language;
        fixture.writeU16(&mac_language, 4, 1); // Macintosh platform is the only owner of the legacy language field.
        const mac_subtables = try cmap_mod.parse(allocator, &mac_language, cmap, 2);
        allocator.free(mac_subtables);
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 40,
        };
        var format12: [40]u8 = .{0} ** 40;
        support.writeFormat12Header(&format12, format12.len - 12, 1);
        support.writeGroup(&format12, 28, 0x100, 0x100, 1);

        const subtables = try cmap_mod.parse(allocator, &format12, cmap, 4);
        allocator.free(subtables);

        var nonzero_language = format12;
        fixture.writeU32(&nonzero_language, 20, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &nonzero_language, cmap, 4));
    }
}

test "cmap glyph ids are validated against maxp glyph count" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const cmap_offset = try fixture.tableOffset(bytes, "cmap");
        const format4_offset = cmap_offset + 12;
        // The fixture declares maxp.numGlyphs == 2, so glyph id 2 is outside
        // the usable glyph set even though the format-4 segment itself is
        // structurally well-formed.
        fixture.writeI16(bytes, format4_offset + 24, @as(i16, 2) - @as(i16, @bitCast(@as(u16, 'A'))));
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var format12: [40]u8 = .{0} ** 40;
        support.writeFormat12Header(&format12, format12.len - 12, 1);
        support.writeGroup(&format12, 28, 0x100, 0x102, 2);

        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = format12.len,
        };
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &format12, cmap, 4));
    }
}
