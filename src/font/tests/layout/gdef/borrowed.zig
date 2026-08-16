//! Font-owned GDEF borrowed-byte lifecycle contracts.

const std = @import("std");
const font_mod = @import("../../../../font.zig");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");

const Font = font_mod.Font;
const GlyphClass = font_mod.GlyphClass;

test "public glyph class aliases the concrete GDEF module type" {
    try std.testing.expect(font_mod.GlyphClass == gdef.GlyphClass);
}

test "ignores mark glyph filtering offset field before GDEF 1.2" {
    var bytes: [32]u8 = .{0} ** 32;
    fixture.writeU16(&bytes, 0, 1); // major
    fixture.writeU16(&bytes, 2, 0); // GDEF 1.0: no MarkGlyphSetsDef field.
    fixture.writeU16(&bytes, 4, 14); // GlyphClassDef offset.
    fixture.writeU16(&bytes, 12, 1); // First bytes of the class def, not a mark-set offset.
    fixture.writeU16(&bytes, 14, 1); // ClassDef format 1.
    fixture.writeU16(&bytes, 16, 3); // startGlyphID
    fixture.writeU16(&bytes, 18, 1); // glyphCount
    fixture.writeU16(&bytes, 20, 3); // class value: mark

    const font = gdefOnlyFont(&bytes);
    try std.testing.expectEqual(GlyphClass.mark, try font.glyphClass(3));
    var metadata = try font_mod.shaping.gdefLookupMetadataForShaping(
        &font,
        std.testing.allocator,
    );
    defer metadata.deinit(std.testing.allocator);
    try std.testing.expect(metadata.mark_filtering_sets == null);
}

test "GDEF lazy glyph class rejects mutated class values outside enum" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const gdef_offset: usize = try fixture.tableOffset(bytes, "GDEF");
    try std.testing.expectEqual(GlyphClass.base, try font.glyphClass(1));

    // The parsed Font keeps a borrowed GDEF table. Rechecking the class value
    // before enum conversion prevents post-parse mutations from manufacturing
    // undeclared glyph classes while preserving arbitrary MarkAttachClassDef
    // group numbers.
    fixture.writeU16(bytes, gdef_offset + 20, 5);
    try std.testing.expectError(error.BadSfnt, font.glyphClass(1));

    fixture.writeU16(bytes, gdef_offset + 20, @intFromEnum(GlyphClass.base));
    try fixture.updateTableChecksum(bytes, "GDEF");
    try std.testing.expectEqual(@as(u16, 7), try font.markAttachClass(3));
}

test "GDEF lazy class APIs revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(GlyphClass.base, try font.glyphClass(1));

    const gdef_offset: usize = try fixture.tableOffset(bytes, "GDEF");
    // Keep the ClassDef value inside the valid GDEF enum while changing the
    // borrowed table after parse. The lazy public API must reject the table
    // because it no longer matches the SFNT checksum that Font.parse accepted.
    fixture.writeU16(bytes, gdef_offset + 20, @intFromEnum(GlyphClass.ligature));
    try std.testing.expectError(error.BadSfnt, font.glyphClass(1));
}

test "GDEF lazy class APIs revalidate child offsets after borrowed bytes mutate" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildGdefClassTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const gdef_offset: usize = try fixture.tableOffset(bytes, "GDEF");
        fixture.writeU16(bytes, gdef_offset + 4, 6); // GlyphClassDef now points into the GDEF header.
        fixture.writeU16(bytes, gdef_offset + 6, 1); // Malicious header bytes decode as ClassDef format 1.
        fixture.writeU16(bytes, gdef_offset + 8, 0); // startGlyphID.
        fixture.writeU16(bytes, gdef_offset + 10, 1); // glyphCount.
        fixture.writeU16(bytes, gdef_offset + 12, @intFromEnum(GlyphClass.mark));

        try std.testing.expectError(error.BadSfnt, font.glyphClass(0));
    }

    {
        const bytes = try test_font.buildGdefClassTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const gdef_offset: usize = try fixture.tableOffset(bytes, "GDEF");
        fixture.writeU16(bytes, gdef_offset + 10, 4); // MarkAttachClassDef now aliases the GDEF header.
        fixture.writeU16(bytes, gdef_offset + 4, 1); // Header bytes at offset 4 form ClassDef format 1.
        fixture.writeU16(bytes, gdef_offset + 6, 3); // startGlyphID.
        fixture.writeU16(bytes, gdef_offset + 8, 1); // glyphCount.

        try std.testing.expectError(error.BadSfnt, font.markAttachClass(3));
    }
}

test "GDEF lazy mark filtering sets revalidate glyph ids after borrowed bytes mutate" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const gdef_offset: usize = try fixture.tableOffset(bytes, "GDEF");
    fixture.writeU16(bytes, gdef_offset + 2, 2); // Enable MarkGlyphSetsDef in the lazy GDEF reader.
    fixture.writeU16(bytes, gdef_offset + 12, 14); // Reuse the original class payload as a mark-set table.
    fixture.writeU16(bytes, gdef_offset + 14, 1); // MarkGlyphSetsDef format 1.
    fixture.writeU16(bytes, gdef_offset + 16, 1);
    fixture.writeU32(bytes, gdef_offset + 18, 10); // Coverage follows the one Offset32 entry.
    fixture.writeU16(bytes, gdef_offset + 24, 1); // Coverage format 1.
    fixture.writeU16(bytes, gdef_offset + 26, 1);
    fixture.writeU16(bytes, gdef_offset + 28, 5); // maxp.numGlyphs is still 5, so glyph id 5 is invalid.

    try std.testing.expectError(
        error.BadSfnt,
        font_mod.shaping.gdefLookupMetadataForShaping(&font, allocator),
    );
}

fn gdefOnlyFont(data: []const u8) Font {
    const table_only = @import("../../fixtures/table_only.zig");
    var font = table_only.init(Font, data, 64, 1);
    font.gdef = table_only.record(
        data,
        .{ 'G', 'D', 'E', 'F' },
        0,
        data.len,
    );
    return font;
}
