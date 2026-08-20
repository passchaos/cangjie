//! CBLC/CBDT parsing and borrowed public API integration tests.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "CBLC CBDT parse validation checks every referenced bitmap payload" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    const cblc_offset = try sfnt_fixture.tableOffset(bytes, "CBLC");
    const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
    const original_data_len = std.mem.readInt(
        u32,
        bytes[cbdt_offset + 9 ..][0..4],
        .big,
    );

    // The fixture references one format-17 PNG payload. Corrupting its dataLen
    // leaves every CBLC range intact, so only a complete parse-time walk of the
    // referenced CBDT records can reject it before a glyph is requested.
    sfnt_fixture.writeU32(bytes, cbdt_offset + 9, 0xffff_ffff);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));

    // Restore CBDT, then move CBLC's image-data base beyond the declared table.
    // A glyph is valid only when the index and data tables agree on ownership.
    sfnt_fixture.writeU32(bytes, cbdt_offset + 9, original_data_len);
    sfnt_fixture.writeU32(bytes, cblc_offset + 68, 0xffff_ff00);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "CBLC public bitmap APIs revalidate borrowed CBDT payloads" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(
        @as(?u16, 16),
        try font.bestBitmapStrikePpem(16),
    );
    try std.testing.expect((try font.bitmapGlyphPng(1, 16)) != null);

    // Font borrows the caller's SFNT bytes. Every lazy bitmap entry point must
    // reject the same post-parse CBDT corruption rather than exposing stale
    // strike metadata or a partially validated payload.
    const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
    sfnt_fixture.writeU32(bytes, cbdt_offset + 9, 0xffff_ffff);
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapStrikes(allocator),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bestBitmapStrikePpem(16),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapGlyphPng(1, 16),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapGlyphInfo(1, 16),
    );
}

test "immutable Face enumerates and summarizes bitmap strikes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCbdtBgraTtf(allocator);
    defer allocator.free(bytes);
    var face = try @import("../../face/root.zig").Face.parse(allocator, bytes);
    defer face.deinit();

    const strikes = try face.color().bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(font_mod.BitmapStrikeSource.cblc_cbdt, strikes[0].source);
    try std.testing.expectEqual(@as(u16, 16), strikes[0].ppem);
    const summary = try face.color().bitmapStrikeSummary();
    try std.testing.expectEqual(@as(usize, 1), summary.strike_count);
    try std.testing.expectEqual(@as(u64, 0x41800002), summary.checksum);

    const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
    sfnt_fixture.writeU32(bytes, cbdt_offset + 9, 0xffff_ffff);
    try std.testing.expectError(
        error.BadSfnt,
        face.implementation.bitmapStrikes(allocator),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try face.color().bitmapStrikeSummary()).strike_count,
    );
}

test "CBDT embedded PNG payloads require a valid PNG datastream" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
    const png_offset = cbdt_offset + 4 + 5 + 4;
    // A loose bytes[1..4] == "PNG" check would miss this signature damage.
    bytes[png_offset] = 0;
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "CBDT non-PNG payloads validate metrics and compound glyph references" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildCbdtPngTtf(allocator);
        defer allocator.free(bytes);

        const cblc_offset = try sfnt_fixture.tableOffset(bytes, "CBLC");
        const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
        // Format 1 stores byte-aligned rows after five-byte small metrics.
        sfnt_fixture.writeU16(bytes, cblc_offset + 66, 1);
        sfnt_fixture.writeU16(bytes, cblc_offset + 74, 6);
        bytes[cbdt_offset + 4] = 2;
        bytes[cbdt_offset + 5] = 9;
        // The metrics require four bitmap bytes, but only one remains.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildCbdtPngTtf(allocator);
        defer allocator.free(bytes);

        const cblc_offset = try sfnt_fixture.tableOffset(bytes, "CBLC");
        const cbdt_offset = try sfnt_fixture.tableOffset(bytes, "CBDT");
        // Format 8 contains small metrics followed by component glyph IDs.
        sfnt_fixture.writeU16(bytes, cblc_offset + 66, 8);
        sfnt_fixture.writeU16(bytes, cblc_offset + 74, 12);
        bytes[cbdt_offset + 4] = 1;
        bytes[cbdt_offset + 5] = 1;
        bytes[cbdt_offset + 9] = 0;
        sfnt_fixture.writeU16(bytes, cbdt_offset + 10, 1);
        // maxp contains only glyph IDs 0 and 1, so component 2 is invalid.
        sfnt_fixture.writeU16(bytes, cbdt_offset + 12, 2);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}
