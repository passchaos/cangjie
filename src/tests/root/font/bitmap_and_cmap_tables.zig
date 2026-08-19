//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const Font = support.Font;
const CharmapMapping = support.CharmapMapping;
const KernTableDialect = support.KernTableDialect;
const BitmapStrikeSource = support.BitmapStrikeSource;
const VariationSequenceKind = support.VariationSequenceKind;
const GlyphId = support.GlyphId;
const ColorRenderTarget = support.ColorRenderTarget;
const Rgba = support.Rgba;
const Rasterizer = support.Rasterizer;
const testing = support.testing;
const writeKernFormat0SubtableTest = support.writeKernFormat0SubtableTest;
const writeU16Test = support.writeU16Test;
const writeI16Test = support.writeI16Test;
const writeU32Test = support.writeU32Test;
const writeI32Test = support.writeI32Test;
const writeU16Root = support.writeU16Root;
const writeU32Root = support.writeU32Root;

test "renders CBDT RGBA PNG at bitmap bearings with premultiplied source-over" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    // ColorRenderTarget uses premultiplied storage. A half-alpha green
    // backdrop makes this exercise both image alpha and source-over.
    target.clear(.{ .r = 0, .g = 128, .b = 0, .a = 128 });
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);

    // The fixture is a 1x1 half-alpha red PNG. CBDT bearing (2, 13) places its
    // top-left at (5 + 2, 20 - 13) = (7, 7).
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 63, .b = 0, .a = 191 }, target.at(7, 7));
    try std.testing.expectEqual(Rgba{ .r = 0, .g = 128, .b = 0, .a = 128 }, target.at(6, 7));
    try std.testing.expectEqual(Rgba{ .r = 0, .g = 128, .b = 0, .a = 128 }, target.at(7, 6));
}

test "renders CBDT format 19 with shared CBLC metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildCbdtFormat19PngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    const info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(?u16, 19), info.image_format);
    try std.testing.expectEqual(@as(i16, 4), info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 11), info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), info.width);
    try std.testing.expectEqual(@as(u32, 1), info.height);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(i16, 4), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 11), bitmap.origin_offset_y);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);
    // Format 19 has no inline metrics: CBLC index format 2 supplies the shared
    // bearing, placing this pixel at (5 + 4, 20 - 11) = (9, 9).
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 0, .b = 0, .a = 128 }, target.at(9, 9));
    try std.testing.expectEqual(@as(u8, 0), target.at(5, 20).a);
}

test "renders raw EBDT mask coverage at bitmap bearings" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildEbdtBitmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    var target = try ColorRenderTarget.init(allocator, 24, 24);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 12, 3, 12, 0);

    // Bearing (1, 9) puts the 8x1 mask at (4, 3). The authored bits are
    // 10100000 and render as white premultiplied coverage.
    try std.testing.expectEqual(Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 }, target.at(4, 3));
    try std.testing.expectEqual(@as(u8, 0), target.at(5, 3).a);
    try std.testing.expectEqual(Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 }, target.at(6, 3));
    try std.testing.expectEqual(@as(u8, 0), target.at(7, 3).a);
}

test "selects a larger CBDT strike before upscaling a smaller image when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/cbdt.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id: GlyphId = 2;

    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(12));
    try std.testing.expectEqual(@as(?u16, 64), try font.bestBitmapStrikePpem(17));
    try std.testing.expectEqual(@as(?u16, 64), try font.bestBitmapStrikePpem(60));
    try std.testing.expectEqual(@as(?u16, 128), try font.bestBitmapStrikePpem(65));
    try std.testing.expectEqual(@as(?u16, 128), try font.bestBitmapStrikePpem(200));

    const at_17 = (try font.bitmapGlyphPng(glyph_id, 17)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 64), at_17.ppem);
    try std.testing.expectEqual(@as(u32, 39), at_17.width);
    try std.testing.expectEqual(@as(u32, 52), at_17.height);

    const info = (try font.bitmapGlyphInfo(glyph_id, 17)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 64), info.ppem);
    try std.testing.expectEqual(at_17.width, info.width);
    try std.testing.expectEqual(at_17.height, info.height);
}

test "bitmap-only fonts leave missing strike glyphs transparent" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect(!font.hasOutlineData());

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    // Glyph 0 has neither a CBDT image nor an outline. Rendering it is a valid
    // no-op rather than a MissingTable failure.
    try rasterizer.renderColorGlyph(&target, &font, 0, 16, 5, 20, 0);
    for (target.pixels) |pixel| try std.testing.expectEqual(@as(u8, 0), pixel.a);
}

test "renders indexed CBDT PNG from Noto Color Emoji when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x1f600);
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 109)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap.source);

    var target = try ColorRenderTarget.init(allocator, 180, 200);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 109, 16, 160, 0);

    var colored_pixels: usize = 0;
    var nontransparent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        nontransparent_pixels += 1;
        // Decoded PNG samples are converted to the target's premultiplied
        // representation before filtering and blending.
        try std.testing.expect(pixel.r <= pixel.a);
        try std.testing.expect(pixel.g <= pixel.a);
        try std.testing.expect(pixel.b <= pixel.a);
        if (pixel.r != pixel.g or pixel.g != pixel.b) colored_pixels += 1;
    }
    try std.testing.expect(nontransparent_pixels > 1_000);
    try std.testing.expect(colored_pixels > 1_000);
}

test "renders indexed sbix PNG with bottom-left origin when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/noto_handwriting-sbix.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x270d);
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 109)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.sbix, bitmap.source);
    try std.testing.expectEqual(@as(i16, 4), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -27), bitmap.origin_offset_y);

    var target = try ColorRenderTarget.init(allocator, 180, 220);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 109, 20, 160, 0);

    // sbix is bottom-left based: x = 20 + 4 and
    // top = 160 - (128 - 27) = 59 for this known fixture.
    var nontransparent_pixels: usize = 0;
    for (target.pixels, 0..) |pixel, index| {
        if (pixel.a == 0) continue;
        nontransparent_pixels += 1;
        const px = index % target.width;
        const py = index / target.width;
        try std.testing.expect(px >= 24 and px < 152);
        try std.testing.expect(py >= 59 and py < 187);
    }
    try std.testing.expect(nontransparent_pixels > 1_000);
    try std.testing.expectEqual(@as(u8, 0), target.at(24, 58).a);
    try std.testing.expectEqual(@as(u8, 0), target.at(23, 59).a);
}

test "resolves and renders sbix dupe PNG glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildSbixDupePngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');
    try std.testing.expectEqual(@as(GlyphId, 1), glyph_id);

    const info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.sbix, info.source);
    try std.testing.expect(info.is_png);
    // Placement and bytes come from the final direct record, not from the
    // intermediate dupe header's deliberately-distinct 99/99 offsets.
    try std.testing.expectEqual(@as(i16, 3), info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -2), info.origin_offset_y);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(i16, 3), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -2), bitmap.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);
    // sbix uses bottom-left placement: left=5+3, top=20-(1-2)=21.
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 0, .b = 0, .a = 128 }, target.at(8, 21));
}

test "maps many-to-one cmap format 13 last-resort ranges" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x4e00));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x1f600));
}

test "maps trimmed cmap format 6 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildTrimmedCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex('C'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('D'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f600));
}

test "maps byte-encoding cmap format 0 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    // Macintosh platform-1, encoding-0 format 0 is a MacRoman charmap, not a
    // direct Latin-1 byte map. Byte 0xFF represents U+02C7.
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0xff));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x02c7));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x100));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f600));
}

test "maps and enumerates Macintosh Turkish Roman cmap variants" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMacintoshTurkishCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(@as(u16, 1), charmap.platform_id);
    try std.testing.expectEqual(@as(u16, 0), charmap.encoding_id);
    try std.testing.expectEqual(@as(?u32, 18), charmap.language);

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x201c));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndex(0x011e));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x0131));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x2044));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndexWithCharmap(charmap, 0x011e));

    const first = (try font.firstCharmapMapping(charmap)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x011e, .glyph_id = 2 }), first);
    const second = (try font.nextCharmapMapping(charmap, first.codepoint)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x0131, .glyph_id = 3 }), second);
    const third = (try font.nextCharmapMapping(charmap, second.codepoint)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x201c, .glyph_id = 1 }), third);
    try std.testing.expect((try font.nextCharmapMapping(charmap, third.codepoint)) == null);
}

test "maps mixed byte cmap format 2 subheaders" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedEncodingCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x0102));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x0101));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x0202));
}

test "maps trimmed 32-bit cmap format 10 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f5ff));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x1f600));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f601));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x1f602));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f603));
}

test "maps cmap format 14 variation selector records" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(?GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndexWithVariation('A', 0xfe0f));
    try std.testing.expectEqual(@as(?GlyphId, 2), try font.variationGlyphIndex('B', 0xfe0f));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndexWithVariation('B', 0xfe0f));
    try std.testing.expectEqual(@as(?GlyphId, null), try font.variationGlyphIndex('A', 0xfe0e));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithVariation('A', 0xfe0e));

    const selectors = try font.variationSelectors(allocator);
    defer allocator.free(selectors);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors);

    const selectors_for_a = try font.variationSelectorsForCodepoint(allocator, 'A');
    defer allocator.free(selectors_for_a);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors_for_a);

    const selectors_for_b = try font.variationSelectorsForCodepoint(allocator, 'B');
    defer allocator.free(selectors_for_b);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors_for_b);

    const selectors_for_c = try font.variationSelectorsForCodepoint(allocator, 'C');
    defer allocator.free(selectors_for_c);
    try std.testing.expectEqual(@as(usize, 0), selectors_for_c.len);

    const codepoints = try font.variationCodepointsForSelector(allocator, 0xfe0f);
    defer allocator.free(codepoints);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 'B' }, codepoints);

    const no_codepoints = try font.variationCodepointsForSelector(allocator, 0xfe0e);
    defer allocator.free(no_codepoints);
    try std.testing.expectEqual(@as(usize, 0), no_codepoints.len);

    try std.testing.expectEqual(VariationSequenceKind.non_default, (try font.variationSequenceKind('A', 0xfe0f)).?);
    try std.testing.expectEqual(VariationSequenceKind.default, (try font.variationSequenceKind('B', 0xfe0f)).?);
    try std.testing.expect((try font.variationSequenceKind('A', 0xfe0e)) == null);
}

test "lazy variation selector enumeration revalidates borrowed cmap bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const selectors = try font.variationSelectors(allocator);
    defer allocator.free(selectors);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cmap_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) cmap_offset = table.offset;
    }
    bytes[cmap_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.variationSelectors(allocator));
    try std.testing.expectError(error.BadSfnt, font.variationSelectorsForCodepoint(allocator, 'A'));
    try std.testing.expectError(error.BadSfnt, font.variationCodepointsForSelector(allocator, 0xfe0f));
    try std.testing.expectError(error.BadSfnt, font.variationSequenceKind('A', 0xfe0f));
}

test "enumerates cmap charmaps including variation selector subtables" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 2), charmaps.len);

    try std.testing.expectEqual(@as(u16, 0), charmaps[0].platform_id);
    try std.testing.expectEqual(@as(u16, 3), charmaps[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 6), charmaps[0].format);
    try std.testing.expectEqual(@as(?u32, 0), charmaps[0].language);

    try std.testing.expectEqual(@as(u16, 0), charmaps[1].platform_id);
    try std.testing.expectEqual(@as(u16, 5), charmaps[1].encoding_id);
    try std.testing.expectEqual(@as(u16, 14), charmaps[1].format);
    try std.testing.expectEqual(@as(?u32, null), charmaps[1].language);

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(charmaps[0], default_charmap);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithCharmap(default_charmap, 'A'));
    try std.testing.expectError(error.UnsupportedCmap, font.glyphIndexWithCharmap(charmaps[1], 'A'));
    try std.testing.expectError(error.UnsupportedCmap, font.firstCharmapMapping(charmaps[1]));
}

test "maps glyphs through explicitly selected charmaps" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 1), charmaps.len);
    try std.testing.expectEqual(@as(u16, 10), charmaps[0].format);

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithCharmap(charmaps[0], 0x1f600));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndexWithCharmap(charmaps[0], 'A'));

    var stale = charmaps[0];
    stale.encoding_id = 99;
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithCharmap(stale, 0x1f600));
    try std.testing.expectError(error.InvalidCodepoint, font.glyphIndexWithCharmap(charmaps[0], 0xd800));
}

test "iterates selected charmap mappings" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    {
        const bytes = try test_font.buildTrimmedCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const charmap = (try font.defaultCharmap()).?;
        const first = (try font.firstCharmapMapping(charmap)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'A', .glyph_id = 1 }), first);
        const second = (try font.nextCharmapMapping(charmap, first.codepoint)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'C', .glyph_id = 3 }), second);
        try std.testing.expect((try font.nextCharmapMapping(charmap, second.codepoint)) == null);
    }

    {
        const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const charmap = (try font.defaultCharmap()).?;
        const first = (try font.firstCharmapMapping(charmap)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x1f600, .glyph_id = 1 }), first);
        const second = (try font.nextCharmapMapping(charmap, first.codepoint)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x1f602, .glyph_id = 3 }), second);
        try std.testing.expect((try font.nextCharmapMapping(charmap, second.codepoint)) == null);
    }
}

test "iterates last-resort cmap ranges without entering surrogates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmap = (try font.defaultCharmap()).?;
    const first = (try font.firstCharmapMapping(charmap)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0, .glyph_id = 1 }), first);
    const after_bmp = (try font.nextCharmapMapping(charmap, 0xd7ff)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0xe000, .glyph_id = 1 }), after_bmp);
    try std.testing.expect((try font.nextCharmapMapping(charmap, 0x10ffff)) == null);
}

test "lazy charmap enumeration revalidates borrowed cmap bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(@as(u16, 4), default_charmap.format);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cmap_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) cmap_offset = table.offset;
    }
    const stale_charmap = default_charmap;
    bytes[cmap_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.defaultCharmap());
    try std.testing.expectError(error.BadSfnt, font.charmaps(allocator));
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithCharmap(stale_charmap, 'A'));
    try std.testing.expectError(error.BadSfnt, font.firstCharmapMapping(stale_charmap));
}
