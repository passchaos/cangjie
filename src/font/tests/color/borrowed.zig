//! Public color APIs revalidate caller-owned COLR, CPAL, and name bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const table_only = @import("../fixtures/table_only.zig");
const support = @import("support.zig");

const Font = font_mod.Font;

fn cpalFixture(data: []const u8) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.cpal = table_only.record(data, .{ 'C', 'P', 'A', 'L' }, 0, data.len);
    return font;
}

fn colorFixture(data: []const u8, colr_length: usize) Font {
    var font = table_only.init(Font, data, 16, 2);
    font.colr = table_only.record(data, .{ 'C', 'O', 'L', 'R' }, 0, colr_length);
    font.cpal = table_only.record(
        data,
        .{ 'C', 'P', 'A', 'L' },
        colr_length,
        data.len - colr_length,
    );
    return font;
}

test "CPAL palette lookup revalidates borrowed label name IDs" {
    var bytes: [54]u8 = .{0} ** 54;
    support.writeU16(&bytes, 0, 1); // CPAL version 1 includes optional label arrays.
    support.writeU16(&bytes, 2, 1); // numPaletteEntries.
    support.writeU16(&bytes, 4, 1); // numPalettes.
    support.writeU16(&bytes, 6, 1); // numColorRecords.
    support.writeU32(&bytes, 8, 30); // ColorRecordsArray follows both label arrays.
    support.writeU16(&bytes, 12, 0); // First color index for palette 0.
    support.writeU32(&bytes, 14, 0); // no palette type array.
    support.writeU32(&bytes, 18, 26); // one palette label NameID.
    support.writeU32(&bytes, 22, 28); // one palette-entry label NameID.
    support.writeU16(&bytes, 26, 256);
    support.writeU16(&bytes, 28, 0xffff);
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const name_offset = 34;
    support.writeU16(&bytes, name_offset + 0, 0);
    support.writeU16(&bytes, name_offset + 2, 1);
    support.writeU16(&bytes, name_offset + 4, 18);
    support.writeUtf16NameRecord(&bytes, name_offset + 6, 256, 2, 0);
    bytes[name_offset + 19] = 'P';

    var font = cpalFixture(&bytes);
    font.cpal = table_only.record(&bytes, .{ 'C', 'P', 'A', 'L' }, 0, name_offset);
    font.name = table_only.record(
        &bytes,
        .{ 'n', 'a', 'm', 'e' },
        name_offset,
        bytes.len - name_offset,
    );

    const color = (try font.paletteColor(0, 0)).?;
    try std.testing.expectEqual(@as(u8, 30), color.red);
    try std.testing.expectEqual(@as(u8, 20), color.green);
    try std.testing.expectEqual(@as(u8, 10), color.blue);
    try std.testing.expectEqual(@as(u8, 40), color.alpha);

    // Font deliberately borrows caller-owned SFNT bytes. Mutating only the
    // borrowed name table keeps CPAL's checksum valid while making its v1 label
    // reference dangle; the lazy color API must still observe that metadata
    // failure.
    support.writeU16(&bytes, name_offset + 12, 257);
    try std.testing.expectError(error.InvalidName, font.paletteColor(0, 0));
}

test "CPAL palette entry labels public API revalidates borrowed names" {
    const allocator = std.testing.allocator;

    var bytes: [54]u8 = .{0} ** 54;
    support.writeU16(&bytes, 0, 1);
    support.writeU16(&bytes, 2, 1);
    support.writeU16(&bytes, 4, 1);
    support.writeU16(&bytes, 6, 1);
    support.writeU32(&bytes, 8, 30);
    support.writeU16(&bytes, 12, 0);
    support.writeU32(&bytes, 14, 0);
    support.writeU32(&bytes, 18, 0);
    support.writeU32(&bytes, 22, 28);
    support.writeU16(&bytes, 28, 256);
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const name_offset = 34;
    support.writeU16(&bytes, name_offset + 0, 0);
    support.writeU16(&bytes, name_offset + 2, 1);
    support.writeU16(&bytes, name_offset + 4, 18);
    support.writeUtf16NameRecord(&bytes, name_offset + 6, 256, 2, 0);
    bytes[name_offset + 19] = 'E';

    var font = cpalFixture(&bytes);
    font.cpal = table_only.record(&bytes, .{ 'C', 'P', 'A', 'L' }, 0, name_offset);
    font.name = table_only.record(
        &bytes,
        .{ 'n', 'a', 'm', 'e' },
        name_offset,
        bytes.len - name_offset,
    );

    const labels = try font.paletteEntryLabels(allocator);
    defer allocator.free(labels);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    try std.testing.expectEqual(@as(?u16, 256), labels[0]);

    support.writeU16(&bytes, name_offset + 12, 257);
    try std.testing.expectError(error.InvalidName, font.paletteEntryLabels(allocator));
}

test "COLR public APIs revalidate borrowed glyph references" {
    const allocator = std.testing.allocator;

    var colr_v0_with_cpal: [42]u8 = .{0} ** 42;
    support.writeU16(&colr_v0_with_cpal, 0, 0); // COLR version 0.
    support.writeU16(&colr_v0_with_cpal, 2, 1); // one BaseGlyphRecord.
    support.writeU32(&colr_v0_with_cpal, 4, 14);
    support.writeU32(&colr_v0_with_cpal, 8, 20);
    support.writeU16(&colr_v0_with_cpal, 12, 1);
    support.writeU16(&colr_v0_with_cpal, 14, 1); // base glyph.
    support.writeU16(&colr_v0_with_cpal, 16, 0);
    support.writeU16(&colr_v0_with_cpal, 18, 1);
    support.writeU16(&colr_v0_with_cpal, 20, 1); // layer glyph.
    support.writeU16(&colr_v0_with_cpal, 22, 0);
    support.writeSingleEntryCpal(&colr_v0_with_cpal, 24);

    const colr_v0_font = colorFixture(&colr_v0_with_cpal, 24);
    const layers = try colr_v0_font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 1), layers.len);
    try std.testing.expectEqual(@as(u16, 1), layers[0].glyph_id);

    // The Font caches only the COLR TableRecord; a caller can still mutate the
    // borrowed layer glyph bytes after construction. The lazy API must reject
    // that cross-table violation before returning a ColorLayer.
    support.writeU16(&colr_v0_with_cpal, 20, 16);
    try std.testing.expectError(error.BadSfnt, colr_v0_font.colorLayers(allocator, 1));

    var colr_v1_with_cpal: [92]u8 = .{0} ** 92;
    support.writeU16(&colr_v1_with_cpal, 0, 1); // COLR version 1.
    support.writeU32(&colr_v1_with_cpal, 14, 34); // BaseGlyphListOffset.
    support.writeU32(&colr_v1_with_cpal, 18, 55); // LayerListOffset.
    support.writeU32(&colr_v1_with_cpal, 34, 1); // one BaseGlyphPaintRecord.
    support.writeU16(&colr_v1_with_cpal, 38, 1); // base glyph.
    support.writeU32(&colr_v1_with_cpal, 40, 10); // PaintGlyph at byte 44.
    colr_v1_with_cpal[44] = 10; // PaintGlyph.
    support.writeU24(&colr_v1_with_cpal, 45, 6); // Child PaintSolid follows PaintGlyph.
    support.writeU16(&colr_v1_with_cpal, 48, 1); // PaintGlyph glyph id.
    colr_v1_with_cpal[50] = 2; // PaintSolid.
    support.writeU16(&colr_v1_with_cpal, 51, 0);
    support.writeF2Dot14(&colr_v1_with_cpal, 53, 1.0);
    support.writeU32(&colr_v1_with_cpal, 55, 1); // one LayerList paint.
    support.writeU32(&colr_v1_with_cpal, 59, 8); // LayerList-relative PaintSolid at byte 63.
    colr_v1_with_cpal[63] = 2;
    support.writeU16(&colr_v1_with_cpal, 64, 0);
    support.writeF2Dot14(&colr_v1_with_cpal, 66, 1.0);
    support.writeSingleEntryCpal(&colr_v1_with_cpal, 74);

    const colr_v1_font = colorFixture(&colr_v1_with_cpal, 74);
    const paint = try colr_v1_font.colorPaint(1);
    try std.testing.expect(paint != null);
    try std.testing.expect((try colr_v1_font.colorPaintLayer(0)) != null);

    // PaintGlyph carries a glyph ID independently of the selected base glyph.
    // Mutating it past maxp.numGlyphs must be caught by colorPaint().
    support.writeU16(&colr_v1_with_cpal, 48, 16);
    try std.testing.expectError(error.BadSfnt, colr_v1_font.colorPaint(1));
    support.writeU16(&colr_v1_with_cpal, 48, 1);

    // LayerList is a separate lazy public entry point into the COLR v1 graph.
    // Mutating a layer paint to name an invalid glyph must be rejected there
    // even though the requested layer index itself is in range.
    colr_v1_with_cpal[63] = 10; // PaintGlyph inside the layer graph.
    support.writeU24(&colr_v1_with_cpal, 64, 6);
    support.writeU16(&colr_v1_with_cpal, 67, 16);
    colr_v1_with_cpal[69] = 2;
    support.writeU16(&colr_v1_with_cpal, 70, 0);
    support.writeF2Dot14(&colr_v1_with_cpal, 72, 1.0);
    try std.testing.expectError(error.BadSfnt, colr_v1_font.colorPaintLayer(0));
}

test "COLR public APIs revalidate borrowed palette references" {
    const allocator = std.testing.allocator;

    var colr_v0_with_cpal: [52]u8 = .{0} ** 52;
    support.writeU16(&colr_v0_with_cpal, 0, 0); // COLR version 0.
    support.writeU16(&colr_v0_with_cpal, 2, 2); // two BaseGlyphRecords.
    support.writeU32(&colr_v0_with_cpal, 4, 14);
    support.writeU32(&colr_v0_with_cpal, 8, 26);
    support.writeU16(&colr_v0_with_cpal, 12, 2);
    support.writeU16(&colr_v0_with_cpal, 14, 1); // selected base glyph.
    support.writeU16(&colr_v0_with_cpal, 16, 0);
    support.writeU16(&colr_v0_with_cpal, 18, 1);
    support.writeU16(&colr_v0_with_cpal, 20, 2); // unrequested base glyph.
    support.writeU16(&colr_v0_with_cpal, 22, 1);
    support.writeU16(&colr_v0_with_cpal, 24, 1);
    support.writeU16(&colr_v0_with_cpal, 26, 1);
    support.writeU16(&colr_v0_with_cpal, 28, 0);
    support.writeU16(&colr_v0_with_cpal, 30, 2);
    support.writeU16(&colr_v0_with_cpal, 32, 0);
    support.writeSingleEntryCpal(&colr_v0_with_cpal, 34);

    const colr_v0_font = colorFixture(&colr_v0_with_cpal, 34);
    const layers = try colr_v0_font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 1), layers.len);

    // The selected glyph's layer still uses palette index 0. Mutating only an
    // unrequested layer past CPAL must still be rejected because COLR's layer
    // array is global borrowed metadata accepted as a whole at parse time.
    support.writeU16(&colr_v0_with_cpal, 32, 1);
    try std.testing.expectError(error.BadSfnt, colr_v0_font.colorLayers(allocator, 1));

    var colr_v1_base_with_cpal: [78]u8 = .{0} ** 78;
    support.writeU16(&colr_v1_base_with_cpal, 0, 1); // COLR version 1.
    support.writeU32(&colr_v1_base_with_cpal, 14, 34); // BaseGlyphListOffset.
    support.writeU32(&colr_v1_base_with_cpal, 34, 2);
    support.writeU16(&colr_v1_base_with_cpal, 38, 1);
    support.writeU32(&colr_v1_base_with_cpal, 40, 16); // selected PaintSolid at byte 50.
    support.writeU16(&colr_v1_base_with_cpal, 44, 2);
    support.writeU32(&colr_v1_base_with_cpal, 46, 21); // unrequested PaintSolid at byte 55.
    colr_v1_base_with_cpal[50] = 2;
    support.writeU16(&colr_v1_base_with_cpal, 51, 0);
    support.writeF2Dot14(&colr_v1_base_with_cpal, 53, 1.0);
    colr_v1_base_with_cpal[55] = 2;
    support.writeU16(&colr_v1_base_with_cpal, 56, 0);
    support.writeF2Dot14(&colr_v1_base_with_cpal, 58, 1.0);
    support.writeSingleEntryCpal(&colr_v1_base_with_cpal, 60);

    const colr_v1_base_font = colorFixture(&colr_v1_base_with_cpal, 60);
    try std.testing.expect((try colr_v1_base_font.colorPaint(1)) != null);

    // `colorPaint(1)` reads only the first base glyph, but the borrowed COLR v1
    // base paint list must remain globally consistent with CPAL.
    support.writeU16(&colr_v1_base_with_cpal, 56, 1);
    try std.testing.expectError(error.BadSfnt, colr_v1_base_font.colorPaint(1));

    var colr_v1_layers_with_cpal: [74]u8 = .{0} ** 74;
    support.writeU16(&colr_v1_layers_with_cpal, 0, 1); // COLR version 1.
    support.writeU32(&colr_v1_layers_with_cpal, 18, 34); // LayerListOffset.
    support.writeU32(&colr_v1_layers_with_cpal, 34, 2);
    support.writeU32(&colr_v1_layers_with_cpal, 38, 12); // selected layer PaintSolid at byte 46.
    support.writeU32(&colr_v1_layers_with_cpal, 42, 17); // sibling layer PaintSolid at byte 51.
    colr_v1_layers_with_cpal[46] = 2;
    support.writeU16(&colr_v1_layers_with_cpal, 47, 0);
    support.writeF2Dot14(&colr_v1_layers_with_cpal, 49, 1.0);
    colr_v1_layers_with_cpal[51] = 2;
    support.writeU16(&colr_v1_layers_with_cpal, 52, 0);
    support.writeF2Dot14(&colr_v1_layers_with_cpal, 54, 1.0);
    support.writeSingleEntryCpal(&colr_v1_layers_with_cpal, 56);

    const colr_v1_layers_font = colorFixture(&colr_v1_layers_with_cpal, 56);
    try std.testing.expect((try colr_v1_layers_font.colorPaintLayer(0)) != null);

    // LayerList is a global paint array; a malformed sibling layer should not
    // be hidden merely because the requested layer still names a valid color.
    support.writeU16(&colr_v1_layers_with_cpal, 52, 1);
    try std.testing.expectError(error.BadSfnt, colr_v1_layers_font.colorPaintLayer(0));
}
