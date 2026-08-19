//! Integration coverage migrated from the former package root.

const std = @import("std");
const incremental = @import("../../../api/font/metadata/incremental/root.zig");
const font_raster = @import("../../../font.zig").raster_backend;
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

test "kern metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0SubtableTest(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.kernInfo(allocator)).?;
    defer font.freeKernInfo(allocator, info);
    try std.testing.expectEqual(KernTableDialect.legacy, info.dialect);
    try std.testing.expectEqual(@as(u32, 0), info.version);
    try std.testing.expectEqual(@as(usize, 1), info.subtables.len);
    try std.testing.expectEqual(@as(u16, 0), info.subtables[0].format);
    try std.testing.expectEqual(@as(u16, 0x0001), info.subtables[0].coverage);
    try std.testing.expect(info.subtables[0].horizontal);
    try std.testing.expect(!info.subtables[0].minimum);
    try std.testing.expect(!info.subtables[0].cross_stream);
    try std.testing.expectEqual(@as(?u16, 1), info.subtables[0].pair_count);

    const missing_bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.kernInfo(allocator)) == null);
}

test "lazy kern metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0SubtableTest(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = (try font.kernInfo(allocator)).?;
    defer font.freeKernInfo(allocator, initial);
    try std.testing.expectEqual(@as(usize, 1), initial.subtables.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var kern_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "kern")) kern_offset = table.offset;
    }
    bytes[(kern_offset orelse return error.MissingTable) + 22] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.kernInfo(allocator));
}

test "PCLT metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildPcltTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.pcltInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(u32, 1234), info.font_number);
    try std.testing.expectEqual(@as(u16, 500), info.pitch);
    try std.testing.expectEqual(@as(u16, 450), info.x_height);
    try std.testing.expectEqual(@as(u16, 700), info.cap_height);
    try std.testing.expectEqual(@as(u16, 0x1234), info.symbol_set);
    try std.testing.expectEqualStrings("CangjiePCLTTest!", &info.typeface);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &info.character_complement);
    try std.testing.expectEqualStrings("CJTEST", &info.file_name);
    try std.testing.expectEqual(@as(i8, -2), info.stroke_weight);
    try std.testing.expectEqual(@as(i8, 3), info.width_type);
    try std.testing.expectEqual(@as(u8, 4), info.serif_style);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.pcltInfo()) == null);
}

test "lazy PCLT metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildPcltTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.pcltInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var pclt_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "PCLT")) pclt_offset = table.offset;
    }
    bytes[pclt_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.pcltInfo());
}

test "post metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    var post: [44]u8 = .{0} ** 44;
    writeU32Test(&post, 0, 0x00020000);
    writeI32Test(&post, 4, 0x00008000); // 0.5 degree italic angle.
    writeI16Test(&post, 8, -75);
    writeI16Test(&post, 10, 25);
    writeU32Test(&post, 12, 1);
    writeU32Test(&post, 16, 2);
    writeU32Test(&post, 20, 3);
    writeU32Test(&post, 24, 4);
    writeU32Test(&post, 28, 5);
    writeU16Test(&post, 32, 2);
    writeU16Test(&post, 34, 0);
    writeU16Test(&post, 36, 258);
    post[38] = 5;
    @memcpy(post[39..44], "A.alt");

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.postInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00020000), info.format);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), info.italic_angle, 0.001);
    try std.testing.expectEqual(@as(i16, -75), info.underline_position);
    try std.testing.expectEqual(@as(i16, 25), info.underline_thickness);
    try std.testing.expect(info.is_fixed_pitch);
    try std.testing.expectEqual(@as(u32, 2), info.min_mem_type42);
    try std.testing.expectEqual(@as(u32, 5), info.max_mem_type1);
    try std.testing.expectEqual(@as(?u16, 2), info.glyph_name_count);
}

test "post metadata handles missing and borrowed mutated tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.postInfo()) == null);

    var post: [32]u8 = .{0} ** 32;
    writeU32Test(&post, 0, 0x00030000);
    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(u32, 0x00030000), (try font.postInfo()).?.format);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var post_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "post")) post_offset = table.offset;
    }
    bytes[post_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.postInfo());
}

test "lazy glyph locations revalidate borrowed loca bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const locations = try font.glyphLocations(allocator);
    defer allocator.free(locations);
    try std.testing.expectEqual(@as(usize, 2), locations.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var loca_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "loca")) loca_offset = table.offset;
    }
    bytes[loca_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphLocations(allocator));
}

test "raw SFNT table data revalidates borrowed checksums" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const hhea_data = (try font.tableData(.{ 'h', 'h', 'e', 'a' })).?;
    try std.testing.expect(hhea_data.len >= 8);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var hhea_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hhea")) hhea_offset = table.offset;
    }
    bytes[hhea_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.tableData(.{ 'h', 'h', 'e', 'a' }));
}

test "parses sbix PNG bitmap glyphs from Apple Color Emoji when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/System/Library/Fonts/Apple Color Emoji.ttc";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return,
        error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();

    const glyph_id = try font.glyphIndex(0x1f600);
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 40)) orelse return error.MissingBitmapGlyph;
    try std.testing.expect(bitmap.data.len > 24);
    try std.testing.expect(std.mem.eql(u8, bitmap.data[1..4], "PNG"));
    try std.testing.expect(bitmap.width > 0);
    try std.testing.expect(bitmap.height > 0);
    try std.testing.expect((try font.bestBitmapStrikePpem(40)) != null);
}

test "IFT table-keyed and glyph-keyed patch metadata decode from supplied bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    var table_patch: [38]u8 = .{0} ** 38;
    @memcpy(table_patch[0..4], "IFTB");
    for (0..16) |index| table_patch[8 + index] = @intCast(index);
    writeU16Root(&table_patch, 24, 1);
    writeU32Root(&table_patch, 26, 0);
    writeU32Root(&table_patch, 30, 4);
    @memcpy(table_patch[34..38], "data");
    const table_info = try incremental.parseTablePatch(allocator, &table_patch);
    defer incremental.freeTablePatch(allocator, table_info);
    try std.testing.expectEqualStrings("IFTB", &table_info.format);
    try std.testing.expectEqualSlices(u32, &.{ 0, 4 }, table_info.patch_offsets);

    var glyph_patch: [31]u8 = .{0} ** 31;
    @memcpy(glyph_patch[0..4], "IFTG");
    glyph_patch[8] = 1;
    for (0..16) |index| glyph_patch[9 + index] = @intCast(15 - index);
    writeU32Root(&glyph_patch, 25, 256);
    glyph_patch[29] = 0xaa;
    glyph_patch[30] = 0xbb;
    const glyph_info = try incremental.parseGlyphPatch(&glyph_patch);
    try std.testing.expectEqualStrings("IFTG", &glyph_info.format);
    try std.testing.expectEqual(@as(u8, 1), glyph_info.flags);
    try std.testing.expectEqual(@as(u32, 256), glyph_info.max_uncompressed_length);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, glyph_info.brotli_stream);
}

test "IFT patch map metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.iftPatchMapInfo()).?;
    try std.testing.expectEqual(@as(u8, 2), info.format);
    try std.testing.expectEqual(@as(u8, 0x01), info.field_flags);
    try std.testing.expectEqual(@as(u8, 15), info.compatibility_id[15]);
    try std.testing.expectEqual(@as(u8, 1), info.default_patch_format);
    try std.testing.expectEqual(@as(u32, 1), info.entry_count);
    try std.testing.expectEqualStrings("https://patch.example/{id}", info.url_template);
    try std.testing.expectEqual(@as(?u32, 24), info.cff_charstrings_offset);
    try std.testing.expect(info.cff2_charstrings_offset == null);
    try std.testing.expect((try font.iftxPatchMapInfo()) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.iftPatchMapInfo()) == null);
}

test "lazy IFT patch map metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.iftPatchMapInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ift_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "IFT ")) ift_offset = table.offset;
    }
    bytes[ift_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.iftPatchMapInfo());
}

test "VARC top-level metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVarcTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.varcInfo(allocator)).?;
    defer font.freeVarcInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(usize, 24), info.coverage_offset);
    try std.testing.expectEqual(@as(?usize, null), info.multi_var_store_offset);
    try std.testing.expectEqual(@as(?usize, null), info.condition_list_offset);
    try std.testing.expectEqual(@as(usize, 32), info.var_composite_glyphs_offset);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, info.glyphs);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.varcInfo(allocator)) == null);
}

test "lazy VARC metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVarcTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.varcInfo(allocator)).?;
    defer font.freeVarcInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var varc_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "VARC")) varc_offset = table.offset;
    }
    bytes[varc_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.varcInfo(allocator));
}

test "VARC outlines recurse, filter conditions, and apply static transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVarcTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var base = try font.glyphOutline(allocator, 1);
    defer base.deinit();
    var composite = try font.glyphOutline(allocator, 0);
    defer composite.deinit();

    try std.testing.expectEqual(base.commands.items.len, composite.commands.items.len);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.x * 2 + 10), composite.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.y * 0.5 + 20), composite.commands.items[0].move_to.y);
    try std.testing.expectEqual(@as(f32, base.commands.items[1].line_to.x * 2 + 10), composite.commands.items[1].line_to.x);
    try std.testing.expectEqual(@as(f32, base.commands.items[1].line_to.y * 0.5 + 20), composite.commands.items[1].line_to.y);
    try std.testing.expectEqual(@as(i16, 10), composite.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), composite.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 1410), composite.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 145), composite.bounds.y_max);

    // At a non-default location condition 1 also matches, so the second
    // self-component contributes another untransformed copy of glyph 1.
    var varied = try font.glyphOutlineAtCoords(allocator, 0, &.{0.75});
    defer varied.deinit();
    try std.testing.expectEqual(base.commands.items.len * 2, varied.commands.items.len);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.x * 2 + 10), varied.commands.items[0].move_to.x);
    try std.testing.expectEqual(base.commands.items[0].move_to.x, varied.commands.items[base.commands.items.len].move_to.x);
    try std.testing.expectEqual(@as(i16, 0), (try font.glyphBoundsAtCoords(0, &.{0.75})).x_min);
    try std.testing.expectEqual(composite.bounds, try font.glyphBounds(0));
}

test "VARC non-default outlines apply HVAR metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVarcHvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    try std.testing.expectEqual(@as(u16, 800), default_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 0), default_outline.left_side_bearing);

    var varied = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied.deinit();
    try std.testing.expectEqual(@as(u16, 804), varied.advance_width);
    try std.testing.expectEqual(@as(i16, 4), varied.left_side_bearing);

    var raster = try font_raster.glyphOutlineAtCoords(font, allocator, 1, &.{0.5});
    defer raster.deinit();
    try std.testing.expectEqual(varied.advance_width, raster.advance_width);
    try std.testing.expectEqual(varied.left_side_bearing, raster.left_side_bearing);
}

test "parses EBDT EBLC bitmap glyph metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildEbdtBitmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(BitmapStrikeSource.eblc_ebdt, strikes[0].source);
    try std.testing.expectEqual(@as(u16, 12), strikes[0].ppem);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].start_glyph);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].end_glyph);

    const glyph_id = try font.glyphIndex('A');
    const bitmap_info = (try font.bitmapGlyphInfo(glyph_id, 12)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.eblc_ebdt, bitmap_info.source);
    try std.testing.expectEqual(@as(?u16, 1), bitmap_info.image_format);
    try std.testing.expectEqual(@as(?u8, 1), bitmap_info.bit_depth);
    try std.testing.expect(bitmap_info.row_byte_aligned);
    try std.testing.expectEqual(@as(?u16, 9), bitmap_info.advance);
    try std.testing.expectEqual(@as(i16, 1), bitmap_info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 9), bitmap_info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 8), bitmap_info.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.height);
    try std.testing.expect(!bitmap_info.is_png);
    try std.testing.expectEqual(@as(usize, 1), bitmap_info.data_length);
    try std.testing.expect((try font.bitmapGlyphPng(glyph_id, 12)) == null);
    const mask = (try font.bitmapGlyphMask(glyph_id, 12)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.eblc_ebdt, mask.source);
    try std.testing.expectEqual(@as(u8, 1), mask.bit_depth);
    try std.testing.expect(mask.row_byte_aligned);
    const coverage = try mask.decodeAlloc(allocator);
    defer allocator.free(coverage);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 255, 0, 0, 0, 0, 0 },
        coverage,
    );
    try std.testing.expectEqual(@as(?u16, 12), try font.bestBitmapStrikePpem(12));
}

test "parses CBDT CBLC PNG bitmap glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, strikes[0].source);
    try std.testing.expectEqual(@as(u16, 16), strikes[0].ppem);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].start_glyph);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].end_glyph);

    const glyph_id = try font.glyphIndex('A');
    const bitmap_info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap_info.source);
    try std.testing.expectEqual(glyph_id, bitmap_info.glyph_id);
    try std.testing.expectEqual(@as(u16, 16), bitmap_info.ppem);
    try std.testing.expectEqual(@as(i16, 2), bitmap_info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bitmap_info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.height);
    try std.testing.expectEqual(@as(?u16, 17), bitmap_info.image_format);
    try std.testing.expect(bitmap_info.is_png);
    try std.testing.expect(bitmap_info.data_length > 0);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap.source);
    try std.testing.expectEqual(@as(u16, 16), bitmap.ppem);
    try std.testing.expectEqual(@as(i16, 2), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bitmap.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);
    try std.testing.expect(std.mem.eql(u8, bitmap.data[1..4], "PNG"));
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(18));
}

test "exposes Skrifa-compatible premultiplied BGRA bitmap data" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildCbdtBgraTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    const info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(?u8, 32), info.bit_depth);
    try std.testing.expectEqual(@as(?u16, 1), info.image_format);
    try std.testing.expectEqual(@as(usize, 8), info.data_length);
    try std.testing.expect((try font.bitmapGlyphPng(glyph_id, 16)) == null);
    try std.testing.expect((try font.bitmapGlyphMask(glyph_id, 16)) == null);

    const bgra = (try font.bitmapGlyphBgra(glyph_id, 16)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bgra.source);
    try std.testing.expectEqual(@as(u16, 16), bgra.ppem);
    try std.testing.expectEqual(@as(i16, 2), bgra.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bgra.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 2), bgra.width);
    try std.testing.expectEqual(@as(u32, 1), bgra.height);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 7, 13, 64, 128, 10, 20, 30, 255 },
        bgra.data,
    );
    const selected = (try font.bitmapGlyphData(glyph_id, 16)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 16), selected.ppem());
    try std.testing.expectEqualSlices(u8, bgra.data, selected.bgra.data);
}

test "exposes FreeType-compatible BGRA from bit-aligned bitmap formats" {
    const allocator = std.testing.allocator;
    inline for ([_]u16{ 2, 5, 7 }) |format| {
        const bytes = try @import("../../../test_font.zig")
            .buildCbdtBgraTtfWithFormat(allocator, format);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const glyph_id = try font.glyphIndex('A');
        const bgra = (try font.bitmapGlyphBgra(glyph_id, 16)) orelse
            return error.MissingBitmapGlyph;
        try std.testing.expectEqual(@as(i16, 2), bgra.origin_offset_x);
        try std.testing.expectEqual(@as(i16, 13), bgra.origin_offset_y);
        try std.testing.expectEqualSlices(
            u8,
            &.{ 7, 13, 64, 128, 10, 20, 30, 255 },
            bgra.data,
        );
    }
}

test "preserves horizontal and vertical BigGlyphMetrics metadata" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildCbdtBgraVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(u16, 16), strikes[0].ppem_x);
    try std.testing.expectEqual(@as(u16, 18), strikes[0].ppem);
    try std.testing.expectEqual(@as(u8, 1), strikes[0].flags);

    const info = (try font.bitmapGlyphInfo(1, 18)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(i16, 2), info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), info.origin_offset_y);
    try std.testing.expectEqual(@as(?u16, 12), info.advance);
    try std.testing.expectEqual(@as(?i16, 0), info.vertical_origin_offset_x);
    try std.testing.expectEqual(@as(?i16, -1), info.vertical_origin_offset_y);
    try std.testing.expectEqual(@as(?u16, 15), info.vertical_advance);
}

test "flattens EBDT compound bitmap components into parent metrics" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildCompoundEbdtTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.bitmapGlyphInfo(2, 16)) orelse
        return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(?u16, 8), info.image_format);
    try std.testing.expectEqual(@as(u32, 4), info.width);
    try std.testing.expectEqual(@as(u32, 2), info.height);
    var compound = (try font.compoundBitmapGlyphAlloc(allocator, 2, 16)) orelse
        return error.MissingBitmapGlyph;
    defer compound.deinit();
    try std.testing.expectEqual(
        support.OwnedBitmapGlyphData.Kind.mask8,
        compound.kind,
    );
    try std.testing.expectEqual(@as(i16, 0), compound.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 2), compound.origin_offset_y);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 0, 0, 0, 0, 255, 0 },
        compound.data,
    );
}

test "rejects recursive compound bitmap cycles during materialization" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildRecursiveCompoundEbdtTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectError(
        error.BadSfnt,
        font.compoundBitmapGlyphAlloc(allocator, 1, 16),
    );
}
