const std = @import("std");

pub fn buildMinimalTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalTtfTables(allocator));
}

pub fn buildSingleCodepointTtf(allocator: std.mem.Allocator, codepoint: u16) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try singleCodepointTtfTables(allocator, codepoint));
}

pub fn buildNamedTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildNamedTtfWithNames(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular");
}

pub fn buildNamedTtfWithNames(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try namedTtfTables(allocator, family, subfamily, full_name));
}

pub fn buildNamedTtfWithPostScript(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8, postscript_name: []const u8) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try namedPostScriptTtfTables(allocator, family, subfamily, full_name, postscript_name));
}

pub fn buildNamedTtfWithStyle(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8, weight: u16, width: u16, italic: bool, bold: bool) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try styledTtfTables(allocator, family, subfamily, full_name, weight, width, italic, bold));
}

pub fn buildVariableTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try variableTtfTables(allocator));
}

pub fn buildColorTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try colorTtfTables(allocator));
}

pub fn buildColorV1Ttf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try colorV1TtfTables(allocator));
}

pub fn buildColorV1GlyphTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try colorV1GlyphTtfTables(allocator));
}

pub fn buildColorV1LayersTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try colorV1LayersTtfTables(allocator));
}

pub fn buildCbdtPngTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try cbdtPngTtfTables(allocator));
}

pub fn buildSvgTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgTtfTables(allocator));
}

pub fn buildSvgCurveTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgCurveTtfTables(allocator));
}

pub fn buildSvgShapeTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgShapeTtfTables(allocator));
}

pub fn buildSvgTransformTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgTransformTtfTables(allocator));
}

pub fn buildSvgRotateTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgRotateTtfTables(allocator));
}

pub fn buildSvgSkewTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgSkewTtfTables(allocator));
}

pub fn buildSvgGroupTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgGroupTtfTables(allocator));
}

pub fn buildSvgNestedGroupTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgNestedGroupTtfTables(allocator));
}

pub fn buildSvgStyleTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgStyleTtfTables(allocator));
}

pub fn buildSvgStrokeTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgStrokeTtfTables(allocator));
}

pub fn buildSvgLineCapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgLineCapTtfTables(allocator));
}

pub fn buildSvgDashTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgDashTtfTables(allocator));
}

pub fn buildSvgDashOffsetTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgDashOffsetTtfTables(allocator));
}

pub fn buildSvgLineJoinTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgLineJoinTtfTables(allocator));
}

pub fn buildSvgUseTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgUseTtfTables(allocator));
}

pub fn buildSvgClipTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgClipTtfTables(allocator));
}

pub fn buildSvgMaskTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgMaskTtfTables(allocator));
}

pub fn buildSvgVisibilityTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgVisibilityTtfTables(allocator));
}

pub fn buildSvgPathStrokeTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgPathStrokeTtfTables(allocator));
}

pub fn buildSvgPolylineTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgPolylineTtfTables(allocator));
}

pub fn buildSvgEllipseTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgEllipseTtfTables(allocator));
}

pub fn buildSvgGradientTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgGradientTtfTables(allocator));
}

pub fn buildSvgRadialGradientTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgRadialGradientTtfTables(allocator));
}

pub fn buildSvgGradientSpreadTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgGradientSpreadTtfTables(allocator));
}

pub fn buildSvgGradientTransformTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try svgGradientTransformTtfTables(allocator));
}

pub fn buildGdefClassTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try gdefClassTtfTables(allocator));
}

pub fn buildGsubIgnoreMarksTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try gsubIgnoreMarksTtfTables(allocator));
}

pub fn buildGposIgnoreMarksTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try gposIgnoreMarksTtfTables(allocator));
}

pub fn buildNamedSingleCodepointTtfWithNames(allocator: std.mem.Allocator, codepoint: u16, family: []const u8, subfamily: []const u8, full_name: []const u8) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try namedSingleCodepointTtfTables(allocator, codepoint, family, subfamily, full_name));
}

pub fn buildNamedCjkTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try namedCjkTtfTables(allocator));
}

pub fn buildLastResortCmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try lastResortCmapTtfTables(allocator));
}

pub fn buildTrimmedCmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try trimmedCmapTtfTables(allocator));
}

pub fn buildByteEncodingCmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try byteEncodingCmapTtfTables(allocator));
}

pub fn buildMixedEncodingCmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try mixedEncodingCmapTtfTables(allocator));
}

pub fn buildTrimmed32CmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try trimmed32CmapTtfTables(allocator));
}

pub fn buildVariationSelectorCmapTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try variationSelectorCmapTtfTables(allocator));
}

pub fn buildNamedCjkLanguageGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try namedCjkLanguageGsubTtfTables(allocator));
}

pub fn buildMinimalTtc(allocator: std.mem.Allocator) ![]u8 {
    const ttf = try buildMinimalTtf(allocator);
    defer allocator.free(ttf);

    const offset = 16;
    var bytes = try allocator.alloc(u8, offset + ttf.len);
    @memset(bytes, 0);
    writeTag(bytes, 0, "ttcf");
    writeU32(bytes, 4, 0x00010000);
    writeU32(bytes, 8, 1);
    writeU32(bytes, 12, offset);
    @memcpy(bytes[offset..], ttf);
    const table_count = std.mem.readInt(u16, bytes[offset + 4 ..][0..2], .big);
    for (0..table_count) |i| {
        const record_offset = offset + 12 + i * 16 + 8;
        const table_offset = std.mem.readInt(u32, bytes[record_offset..][0..4], .big);
        writeU32(bytes, record_offset, table_offset + offset);
    }
    return bytes;
}

pub fn buildNamedTtc(allocator: std.mem.Allocator) ![]u8 {
    const first = try buildNamedTtfWithNames(allocator, "Collection One", "Regular", "Collection One Regular");
    defer allocator.free(first);
    const second = try buildNamedTtfWithNames(allocator, "Collection Two", "Regular", "Collection Two Regular");
    defer allocator.free(second);

    const first_offset = 20;
    const second_offset = first_offset + first.len;
    var bytes = try allocator.alloc(u8, second_offset + second.len);
    @memset(bytes, 0);
    writeTag(bytes, 0, "ttcf");
    writeU32(bytes, 4, 0x00010000);
    writeU32(bytes, 8, 2);
    writeU32(bytes, 12, first_offset);
    writeU32(bytes, 16, @intCast(second_offset));
    @memcpy(bytes[first_offset..][0..first.len], first);
    @memcpy(bytes[second_offset..][0..second.len], second);
    offsetSfntTables(bytes, first_offset);
    offsetSfntTables(bytes, second_offset);
    return bytes;
}

pub fn buildMinimalGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGsubTtfTables(allocator));
}

pub fn buildMultipleGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try multipleGsubTtfTables(allocator));
}

pub fn buildAlternateGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try alternateGsubTtfTables(allocator));
}

pub fn buildExtensionGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try extensionGsubTtfTables(allocator));
}

pub fn buildSelectiveGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try selectiveGsubTtfTables(allocator));
}

pub fn buildContextGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try contextGsubTtfTables(allocator));
}

pub fn buildContextFormat3GsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try contextFormat3GsubTtfTables(allocator));
}

pub fn buildContextClassGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try contextClassGsubTtfTables(allocator));
}

pub fn buildChainingGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try chainingGsubTtfTables(allocator));
}

pub fn buildReverseChainingGsubTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try reverseChainingGsubTtfTables(allocator));
}

pub fn buildMinimalGposTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposTtfTables(allocator));
}

pub fn buildMinimalGposAndKernTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposAndKernTtfTables(allocator));
}

pub fn buildMinimalGposSingleTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposSingleTtfTables(allocator));
}

pub fn buildExtensionGposTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try extensionGposTtfTables(allocator));
}

pub fn buildMinimalGposClassTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposClassTtfTables(allocator));
}

pub fn buildMinimalGposMarkTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposMarkTtfTables(allocator));
}

pub fn buildGposMarkAnchorFormatsTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try gposMarkAnchorFormatsTtfTables(allocator));
}

pub fn buildMinimalGposMarkToMarkTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposMarkToMarkTtfTables(allocator));
}

pub fn buildMinimalGposCursiveTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposCursiveTtfTables(allocator));
}

pub fn buildMinimalGposMarkToLigatureTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposMarkToLigatureTtfTables(allocator));
}

pub fn buildMinimalGposContextTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposContextTtfTables(allocator));
}

pub fn buildMinimalGposChainingTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposChainingTtfTables(allocator));
}

pub fn buildMinimalGposGlyphChainingTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposGlyphChainingTtfTables(allocator));
}

pub fn buildMinimalGposClassChainingTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposClassChainingTtfTables(allocator));
}

pub fn buildMinimalGposGlyphContextTtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x00010000, try minimalGposGlyphContextTtfTables(allocator));
}

pub fn buildMinimalOtf(allocator: std.mem.Allocator) ![]u8 {
    return buildSfnt(allocator, 0x4f54544f, try minimalOtfTables(allocator));
}

fn minimalTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn singleCodepointTtfTables(allocator: std.mem.Allocator, codepoint: u16) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapSingleCodepointTable(allocator, codepoint) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn namedTtfTables(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8) ![]Table {
    return try namedPostScriptTtfTables(allocator, family, subfamily, full_name, full_name);
}

fn namedPostScriptTtfTables(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8, postscript_name: []const u8) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "name", .data = try nameTableWithPostScript(allocator, family, subfamily, full_name, postscript_name) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn styledTtfTables(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8, weight: u16, width: u16, italic: bool, bold: bool) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "OS/2", .data = try os2Table(allocator, weight, width, italic, bold) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "name", .data = try nameTable(allocator, family, subfamily, full_name) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn variableTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 11);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "avar", .data = try avarTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "fvar", .data = try fvarTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[9] = .{ .tag = "name", .data = try variableNameTable(allocator) };
    tables[10] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn colorTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "COLR", .data = try colrTable(allocator) };
    tables[1] = .{ .tag = "CPAL", .data = try cpalTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTableWithColorGlyphs(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn colorV1TtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "COLR", .data = try colrV1Table(allocator) };
    tables[1] = .{ .tag = "CPAL", .data = try cpalTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn colorV1GlyphTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "COLR", .data = try colrV1GlyphTable(allocator) };
    tables[1] = .{ .tag = "CPAL", .data = try cpalTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn colorV1LayersTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "COLR", .data = try colrV1LayersTable(allocator) };
    tables[1] = .{ .tag = "CPAL", .data = try cpalTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn cbdtPngTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "CBDT", .data = try cbdtPngTable(allocator) };
    tables[1] = .{ .tag = "CBLC", .data = try cblcPngTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgCurveTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgCurveTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgShapeTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgShapeTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgTransformTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgTransformTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgRotateTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgRotateTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgSkewTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgSkewTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgGroupTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgGroupTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgNestedGroupTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgNestedGroupTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgStyleTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgStyleTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgStrokeTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgStrokeTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgLineCapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgLineCapTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgDashTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgDashTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgDashOffsetTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgDashOffsetTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgLineJoinTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgLineJoinTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgUseTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgUseTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgClipTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgClipTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgMaskTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgMaskTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgVisibilityTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgVisibilityTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgPathStrokeTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgPathStrokeTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgPolylineTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgPolylineTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgEllipseTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgEllipseTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgGradientTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgGradientTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgRadialGradientTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgRadialGradientTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgGradientSpreadTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgGradientSpreadTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn svgGradientTransformTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "SVG ", .data = try svgGradientTransformTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn gdefClassTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GDEF", .data = try gdefClassTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 5) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithFiveGlyphs(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 5) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn gsubIgnoreMarksTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GDEF", .data = try gdefClassTable(allocator) };
    tables[1] = .{ .tag = "GSUB", .data = try gsubIgnoreMarksTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 5) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTableWithFiveGlyphs(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 5) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn gposIgnoreMarksTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GDEF", .data = try gdefClassTable(allocator) };
    tables[1] = .{ .tag = "GPOS", .data = try gposIgnoreMarksTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 5) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTableWithFiveGlyphs(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 5) };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn namedSingleCodepointTtfTables(allocator: std.mem.Allocator, codepoint: u16, family: []const u8, subfamily: []const u8, full_name: []const u8) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapSingleCodepointTable(allocator, codepoint) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "name", .data = try nameTable(allocator, family, subfamily, full_name) };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn namedCjkTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat12GlyphArrayTable(allocator, &.{ 0x4e00, 0x4e01, 0x4e02 }, 1) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "name", .data = try nameTable(allocator, "Cangjie CJK", "Regular", "Cangjie CJK Regular") };
    tables[8] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn lastResortCmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat13RangeTable(allocator, 0, 0x10ffff, 1) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn trimmedCmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat6Table(allocator, 'A', &.{ 1, 0, 3 }) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn byteEncodingCmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat0Table(allocator, &.{ .{ .code = 'A', .glyph = 1 }, .{ .code = 0xff, .glyph = 3 } }) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn mixedEncodingCmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat2Table(allocator) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn trimmed32CmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat10Table(allocator, 0x1f600, &.{ 1, 0, 3 }) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn variationSelectorCmapTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "cmap", .data = try cmapFormat14VariationTable(allocator) };
    tables[1] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[5] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[6] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    tables[7] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn namedCjkLanguageGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 10);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try haniJapaneseGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapFormat12GlyphArrayTable(allocator, &.{ 0x4e00, 0x4e01 }, 1) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    tables[8] = .{ .tag = "name", .data = try nameTable(allocator, "Cangjie CJK", "Regular", "Cangjie CJK Regular") };
    tables[9] = .{ .tag = "kern", .data = try kernTable(allocator) };
    return tables;
}

fn minimalGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try gsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    return tables;
}

fn multipleGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try multipleGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn alternateGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try alternateGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn extensionGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try extensionGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    return tables;
}

fn selectiveGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try selectiveGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn contextGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try contextGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn contextFormat3GsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try contextFormat3GsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn contextClassGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try contextClassGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn chainingGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try chainingGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn reverseChainingGsubTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GSUB", .data = try reverseChainingGsubTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 4) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithTwoExtraGlyphs(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 4) };
    return tables;
}

fn minimalGposTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposAndKernTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "kern", .data = try kernTable(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposSingleTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposSingleTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn extensionGposTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposExtensionTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposClassTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposClassTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposMarkTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposMarkTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    return tables;
}

fn gposMarkAnchorFormatsTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposMarkAnchorFormatsTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    return tables;
}

fn minimalGposMarkToMarkTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposMarkToMarkTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposCursiveTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposCursiveTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposMarkToLigatureTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 9);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposMarkToLigatureTable(allocator) };
    tables[1] = .{ .tag = "GSUB", .data = try gsubTable(allocator) };
    tables[2] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[3] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[4] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[5] = .{ .tag = "hhea", .data = try hheaTableWithMetrics(allocator, 3) };
    tables[6] = .{ .tag = "hmtx", .data = try hmtxTableWithLigature(allocator) };
    tables[7] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[8] = .{ .tag = "maxp", .data = try maxpTableWithGlyphs(allocator, 3) };
    return tables;
}

fn minimalGposContextTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposContextTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposChainingTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposChainingTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposGlyphChainingTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposGlyphChainingTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposClassChainingTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposClassChainingTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalGposGlyphContextTtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 8);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "GPOS", .data = try gposGlyphContextTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "glyf", .data = try glyfTable(allocator) };
    tables[3] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[4] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[5] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[6] = .{ .tag = "loca", .data = try locaTable(allocator) };
    tables[7] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn minimalOtfTables(allocator: std.mem.Allocator) ![]Table {
    const tables = try allocator.alloc(Table, 6);
    errdefer allocator.free(tables);
    tables[0] = .{ .tag = "CFF ", .data = try cffTable(allocator) };
    tables[1] = .{ .tag = "cmap", .data = try cmapTable(allocator) };
    tables[2] = .{ .tag = "head", .data = try headTable(allocator) };
    tables[3] = .{ .tag = "hhea", .data = try hheaTable(allocator) };
    tables[4] = .{ .tag = "hmtx", .data = try hmtxTable(allocator) };
    tables[5] = .{ .tag = "maxp", .data = try maxpTable(allocator) };
    return tables;
}

fn buildSfnt(allocator: std.mem.Allocator, scaler: u32, tables: []Table) ![]u8 {
    defer allocator.free(tables);
    errdefer for (tables) |*table| allocator.free(table.data);
    std.mem.sort(Table, tables, {}, struct {
        fn lessThan(_: void, a: Table, b: Table) bool {
            return std.mem.order(u8, a.tag, b.tag) == .lt;
        }
    }.lessThan);

    const offset_table_len = 12 + tables.len * 16;
    var total_len: usize = offset_table_len;
    for (tables) |*table| {
        total_len = align4(total_len);
        table.offset = total_len;
        total_len += table.data.len;
    }

    var bytes = try allocator.alloc(u8, total_len);
    @memset(bytes, 0);
    writeU32(bytes, 0, scaler);
    writeU16(bytes, 4, @intCast(tables.len));
    writeU16(bytes, 6, searchRange(tables.len));
    writeU16(bytes, 8, entrySelector(tables.len));
    writeU16(bytes, 10, @as(u16, @intCast(tables.len * 16)) - searchRange(tables.len));
    for (tables, 0..) |*table, i| {
        const rec = 12 + i * 16;
        @memcpy(bytes[rec .. rec + 4], table.tag);
        writeU32(bytes, rec + 4, checksum(table.data));
        writeU32(bytes, rec + 8, @intCast(table.offset));
        writeU32(bytes, rec + 12, @intCast(table.data.len));
        @memcpy(bytes[table.offset .. table.offset + table.data.len], table.data);
        allocator.free(table.data);
    }
    return bytes;
}

fn offsetSfntTables(bytes: []u8, sfnt_offset: usize) void {
    const table_count = std.mem.readInt(u16, bytes[sfnt_offset + 4 ..][0..2], .big);
    for (0..table_count) |i| {
        const record_offset = sfnt_offset + 12 + i * 16 + 8;
        const table_offset = std.mem.readInt(u32, bytes[record_offset..][0..4], .big);
        writeU32(bytes, record_offset, table_offset + @as(u32, @intCast(sfnt_offset)));
    }
}

const Table = struct {
    tag: []const u8,
    data: []u8,
    offset: usize = 0,
};

fn cmapTable(allocator: std.mem.Allocator) ![]u8 {
    return cmapSingleCodepointTable(allocator, 65);
}

fn cmapSingleCodepointTable(allocator: std.mem.Allocator, codepoint: u16) ![]u8 {
    const bytes = try allocator.alloc(u8, 44);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 1);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 4);
    writeU16(bytes, off + 2, 32);
    writeU16(bytes, off + 4, 0);
    writeU16(bytes, off + 6, 4);
    writeU16(bytes, off + 8, 4);
    writeU16(bytes, off + 10, 1);
    writeU16(bytes, off + 12, 0);
    writeU16(bytes, off + 14, codepoint);
    writeU16(bytes, off + 16, 0xffff);
    writeU16(bytes, off + 18, 0);
    writeU16(bytes, off + 20, codepoint);
    writeU16(bytes, off + 22, 0xffff);
    writeI16(bytes, off + 24, @as(i16, 1) - @as(i16, @bitCast(codepoint)));
    writeI16(bytes, off + 26, 1);
    writeU16(bytes, off + 28, 0);
    writeU16(bytes, off + 30, 0);
    return bytes;
}

fn cmapFormat10Table(allocator: std.mem.Allocator, start_code: u32, glyph_ids: []const u16) ![]u8 {
    const length = 20 + glyph_ids.len * 2;
    const bytes = try allocator.alloc(u8, 12 + length);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 10);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 10);
    writeU16(bytes, off + 2, 0);
    writeU32(bytes, off + 4, @intCast(length));
    writeU32(bytes, off + 8, 0);
    writeU32(bytes, off + 12, start_code);
    writeU32(bytes, off + 16, @intCast(glyph_ids.len));
    for (glyph_ids, 0..) |glyph_id, index| {
        writeU16(bytes, off + 20 + index * 2, glyph_id);
    }
    return bytes;
}

fn cmapFormat14VariationTable(allocator: std.mem.Allocator) ![]u8 {
    const base_len: usize = 14;
    const variation_len: usize = 38;
    const base_off: usize = 20;
    const variation_off = base_off + base_len;
    const bytes = try allocator.alloc(u8, variation_off + variation_len);
    @memset(bytes, 0);

    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 2);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 1);
    writeU32(bytes, 8, @intCast(base_off));
    writeU16(bytes, 12, 0);
    writeU16(bytes, 14, 5);
    writeU32(bytes, 16, @intCast(variation_off));

    writeU16(bytes, base_off + 0, 6);
    writeU16(bytes, base_off + 2, @intCast(base_len));
    writeU16(bytes, base_off + 4, 0);
    writeU16(bytes, base_off + 6, 'A');
    writeU16(bytes, base_off + 8, 2);
    writeU16(bytes, base_off + 10, 1);
    writeU16(bytes, base_off + 12, 2);

    writeU16(bytes, variation_off + 0, 14);
    writeU32(bytes, variation_off + 2, @intCast(variation_len));
    writeU32(bytes, variation_off + 6, 1);
    writeU24(bytes, variation_off + 10, 0xfe0f);
    writeU32(bytes, variation_off + 13, 21);
    writeU32(bytes, variation_off + 17, 29);

    writeU32(bytes, variation_off + 21, 1);
    writeU24(bytes, variation_off + 25, 'B');
    bytes[variation_off + 28] = 0;

    writeU32(bytes, variation_off + 29, 1);
    writeU24(bytes, variation_off + 33, 'A');
    writeU16(bytes, variation_off + 36, 3);
    return bytes;
}

fn cmapFormat12RangeTable(allocator: std.mem.Allocator, start: u32, end: u32, glyph_start: u32) ![]u8 {
    const bytes = try allocator.alloc(u8, 40);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 10);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 12);
    writeU16(bytes, off + 2, 0);
    writeU32(bytes, off + 4, 28);
    writeU32(bytes, off + 8, 0);
    writeU32(bytes, off + 12, 1);
    writeU32(bytes, off + 16, start);
    writeU32(bytes, off + 20, end);
    writeU32(bytes, off + 24, glyph_start);
    return bytes;
}

fn cmapFormat2Table(allocator: std.mem.Allocator) ![]u8 {
    const length: usize = 550;
    const bytes = try allocator.alloc(u8, 12 + length);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 1);
    writeU32(bytes, 8, 12);

    const off = 12;
    writeU16(bytes, off + 0, 2);
    writeU16(bytes, off + 2, @intCast(length));
    writeU16(bytes, off + 4, 0);

    writeU16(bytes, off + 6 + 1 * 2, 8);
    const subheaders = off + 6 + 512;
    writeU16(bytes, subheaders + 0, 'A');
    writeU16(bytes, subheaders + 2, 1);
    writeI16(bytes, subheaders + 4, 0);
    writeU16(bytes, subheaders + 6, 10);

    writeU16(bytes, subheaders + 8, 2);
    writeU16(bytes, subheaders + 10, 1);
    writeI16(bytes, subheaders + 12, 0);
    writeU16(bytes, subheaders + 14, 4);

    writeU16(bytes, subheaders + 16, 1);
    writeU16(bytes, subheaders + 18, 3);
    return bytes;
}

fn cmapFormat0Table(allocator: std.mem.Allocator, mappings: []const struct { code: u8, glyph: u8 }) ![]u8 {
    const bytes = try allocator.alloc(u8, 12 + 262);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 1);
    writeU16(bytes, 6, 0);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 0);
    writeU16(bytes, off + 2, 262);
    writeU16(bytes, off + 4, 0);
    for (mappings) |mapping| {
        bytes[off + 6 + @as(usize, mapping.code)] = mapping.glyph;
    }
    return bytes;
}

fn cmapFormat6Table(allocator: std.mem.Allocator, first_code: u16, glyph_ids: []const u16) ![]u8 {
    const length = 10 + glyph_ids.len * 2;
    const bytes = try allocator.alloc(u8, 12 + length);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 1);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 6);
    writeU16(bytes, off + 2, @intCast(length));
    writeU16(bytes, off + 4, 0);
    writeU16(bytes, off + 6, first_code);
    writeU16(bytes, off + 8, @intCast(glyph_ids.len));
    for (glyph_ids, 0..) |glyph_id, index| {
        writeU16(bytes, off + 10 + index * 2, glyph_id);
    }
    return bytes;
}

fn cmapFormat13RangeTable(allocator: std.mem.Allocator, start: u32, end: u32, glyph_id: u32) ![]u8 {
    const bytes = try allocator.alloc(u8, 40);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 10);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 13);
    writeU16(bytes, off + 2, 0);
    writeU32(bytes, off + 4, 28);
    writeU32(bytes, off + 8, 0);
    writeU32(bytes, off + 12, 1);
    writeU32(bytes, off + 16, start);
    writeU32(bytes, off + 20, end);
    writeU32(bytes, off + 24, glyph_id);
    return bytes;
}

fn cmapFormat12GlyphArrayTable(allocator: std.mem.Allocator, codepoints: []const u32, glyph_id: u32) ![]u8 {
    const bytes = try allocator.alloc(u8, 28 + codepoints.len * 12);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 10);
    writeU32(bytes, 8, 12);
    const off = 12;
    writeU16(bytes, off + 0, 12);
    writeU16(bytes, off + 2, 0);
    writeU32(bytes, off + 4, @intCast(16 + codepoints.len * 12));
    writeU32(bytes, off + 8, 0);
    writeU32(bytes, off + 12, @intCast(codepoints.len));
    for (codepoints, 0..) |codepoint, index| {
        const group = off + 16 + index * 12;
        writeU32(bytes, group + 0, codepoint);
        writeU32(bytes, group + 4, codepoint);
        writeU32(bytes, group + 8, glyph_id);
    }
    return bytes;
}

fn nameTable(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8) ![]u8 {
    return try nameTableWithPostScript(allocator, family, subfamily, full_name, full_name);
}

fn nameTableWithPostScript(allocator: std.mem.Allocator, family: []const u8, subfamily: []const u8, full_name: []const u8, postscript_name: []const u8) ![]u8 {
    const records = [_]struct { id: u16, value: []const u8 }{
        .{ .id = 1, .value = family },
        .{ .id = 2, .value = subfamily },
        .{ .id = 4, .value = full_name },
        .{ .id = 6, .value = postscript_name },
        .{ .id = 16, .value = family },
        .{ .id = 17, .value = subfamily },
    };
    var storage_len: usize = 0;
    for (records) |record| storage_len += record.value.len * 2;
    const header_len = 6 + records.len * 12;
    const bytes = try allocator.alloc(u8, header_len + storage_len);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, records.len);
    writeU16(bytes, 4, header_len);

    var storage_offset: usize = 0;
    for (records, 0..) |record, index| {
        const rec = 6 + index * 12;
        writeU16(bytes, rec + 0, 3);
        writeU16(bytes, rec + 2, 1);
        writeU16(bytes, rec + 4, 0x0409);
        writeU16(bytes, rec + 6, record.id);
        writeU16(bytes, rec + 8, @intCast(record.value.len * 2));
        writeU16(bytes, rec + 10, @intCast(storage_offset));
        for (record.value, 0..) |byte, i| {
            bytes[header_len + storage_offset + i * 2] = 0;
            bytes[header_len + storage_offset + i * 2 + 1] = byte;
        }
        storage_offset += record.value.len * 2;
    }
    return bytes;
}

fn variableNameTable(allocator: std.mem.Allocator) ![]u8 {
    const records = [_]struct { id: u16, value: []const u8 }{
        .{ .id = 1, .value = "Cangjie Variable" },
        .{ .id = 2, .value = "Regular" },
        .{ .id = 4, .value = "Cangjie Variable Regular" },
        .{ .id = 16, .value = "Cangjie Variable" },
        .{ .id = 17, .value = "Regular" },
        .{ .id = 256, .value = "Weight" },
        .{ .id = 257, .value = "Width" },
    };
    var storage_len: usize = 0;
    for (records) |record| storage_len += record.value.len * 2;
    const header_len = 6 + records.len * 12;
    const bytes = try allocator.alloc(u8, header_len + storage_len);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, records.len);
    writeU16(bytes, 4, header_len);

    var storage_offset: usize = 0;
    for (records, 0..) |record, index| {
        const rec = 6 + index * 12;
        writeU16(bytes, rec + 0, 3);
        writeU16(bytes, rec + 2, 1);
        writeU16(bytes, rec + 4, 0x0409);
        writeU16(bytes, rec + 6, record.id);
        writeU16(bytes, rec + 8, @intCast(record.value.len * 2));
        writeU16(bytes, rec + 10, @intCast(storage_offset));
        for (record.value, 0..) |byte, i| {
            bytes[header_len + storage_offset + i * 2] = 0;
            bytes[header_len + storage_offset + i * 2 + 1] = byte;
        }
        storage_offset += record.value.len * 2;
    }
    return bytes;
}

fn os2Table(allocator: std.mem.Allocator, weight: u16, width: u16, italic: bool, bold: bool) ![]u8 {
    const bytes = try allocator.alloc(u8, 64);
    @memset(bytes, 0);
    writeU16(bytes, 0, 4);
    writeU16(bytes, 4, weight);
    writeU16(bytes, 6, width);
    var selection: u16 = 0;
    if (italic) selection |= 0x0001;
    if (bold) selection |= 0x0020;
    writeU16(bytes, 62, selection);
    return bytes;
}

fn fvarTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 56);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 16);
    writeU16(bytes, 6, 2);
    writeU16(bytes, 8, 2);
    writeU16(bytes, 10, 20);
    writeU16(bytes, 12, 0);
    writeU16(bytes, 14, 0);
    writeTag(bytes, 16, "wght");
    writeF16Dot16(bytes, 20, 100.0);
    writeF16Dot16(bytes, 24, 400.0);
    writeF16Dot16(bytes, 28, 900.0);
    writeU16(bytes, 32, 0);
    writeU16(bytes, 34, 256);
    writeTag(bytes, 36, "wdth");
    writeF16Dot16(bytes, 40, 50.0);
    writeF16Dot16(bytes, 44, 100.0);
    writeF16Dot16(bytes, 48, 200.0);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 257);
    return bytes;
}

fn avarTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 42);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 0);
    writeU16(bytes, 4, 0);
    writeU16(bytes, 6, 2);
    writeU16(bytes, 8, 4);
    writeF2Dot14(bytes, 10, -1.0);
    writeF2Dot14(bytes, 12, -1.0);
    writeF2Dot14(bytes, 14, 0.0);
    writeF2Dot14(bytes, 16, 0.0);
    writeF2Dot14(bytes, 18, 0.5);
    writeF2Dot14(bytes, 20, 0.25);
    writeF2Dot14(bytes, 22, 1.0);
    writeF2Dot14(bytes, 24, 1.0);
    writeU16(bytes, 26, 3);
    writeF2Dot14(bytes, 28, -1.0);
    writeF2Dot14(bytes, 30, -1.0);
    writeF2Dot14(bytes, 32, 0.0);
    writeF2Dot14(bytes, 34, 0.0);
    writeF2Dot14(bytes, 36, 1.0);
    writeF2Dot14(bytes, 38, 1.0);
    return bytes;
}

fn colrTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 28);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU32(bytes, 4, 14);
    writeU32(bytes, 8, 20);
    writeU16(bytes, 12, 2);
    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 0);
    writeU16(bytes, 18, 2);
    writeU16(bytes, 20, 1);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 1);
    writeU16(bytes, 26, 1);
    return bytes;
}

fn cpalTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 24);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 2);
    writeU16(bytes, 4, 1);
    writeU16(bytes, 6, 2);
    writeU32(bytes, 8, 16);
    writeU16(bytes, 12, 0);
    bytes[16] = 0;
    bytes[17] = 0;
    bytes[18] = 255;
    bytes[19] = 255;
    bytes[20] = 255;
    bytes[21] = 0;
    bytes[22] = 0;
    bytes[23] = 255;
    return bytes;
}

fn colrV1Table(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 49);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 0);
    writeU32(bytes, 4, 0);
    writeU32(bytes, 8, 0);
    writeU16(bytes, 12, 0);
    writeU32(bytes, 14, 34);
    writeU32(bytes, 18, 0);
    writeU32(bytes, 22, 0);
    writeU32(bytes, 26, 0);
    writeU32(bytes, 30, 0);
    writeU32(bytes, 34, 1);
    writeU16(bytes, 38, 1);
    writeU32(bytes, 40, 10);
    bytes[44] = 2;
    writeU16(bytes, 45, 0);
    writeF2Dot14(bytes, 47, 0.5);
    return bytes;
}

fn colrV1GlyphTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 55);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 0);
    writeU32(bytes, 4, 0);
    writeU32(bytes, 8, 0);
    writeU16(bytes, 12, 0);
    writeU32(bytes, 14, 34);
    writeU32(bytes, 18, 0);
    writeU32(bytes, 22, 0);
    writeU32(bytes, 26, 0);
    writeU32(bytes, 30, 0);
    writeU32(bytes, 34, 1);
    writeU16(bytes, 38, 1);
    writeU32(bytes, 40, 10);
    bytes[44] = 10;
    bytes[45] = 0;
    bytes[46] = 0;
    bytes[47] = 6;
    writeU16(bytes, 48, 1);
    bytes[50] = 2;
    writeU16(bytes, 51, 0);
    writeF2Dot14(bytes, 53, 1.0);
    return bytes;
}

fn colrV1LayersTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 84);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU32(bytes, 14, 34);
    writeU32(bytes, 18, 50);
    writeU32(bytes, 34, 1);
    writeU16(bytes, 38, 1);
    writeU32(bytes, 40, 10);
    bytes[44] = 1;
    bytes[45] = 2;
    writeU32(bytes, 46, 0);
    writeU32(bytes, 50, 2);
    writeU32(bytes, 54, 12);
    writeU32(bytes, 58, 23);
    bytes[62] = 10;
    bytes[65] = 6;
    writeU16(bytes, 66, 1);
    bytes[68] = 2;
    writeU16(bytes, 69, 0);
    writeF2Dot14(bytes, 71, 1.0);
    bytes[73] = 10;
    bytes[76] = 6;
    writeU16(bytes, 77, 1);
    bytes[79] = 2;
    writeU16(bytes, 80, 1);
    writeF2Dot14(bytes, 82, 1.0);
    return bytes;
}

fn cbdtPngTable(allocator: std.mem.Allocator) ![]u8 {
    const png = cbdtFixturePng();
    const image_len = 5 + 4 + png.len;
    const bytes = try allocator.alloc(u8, 4 + image_len);
    @memset(bytes, 0);
    writeU16(bytes, 0, 3);
    writeU16(bytes, 2, 0);
    const off = 4;
    bytes[off + 0] = 1;
    bytes[off + 1] = 1;
    bytes[off + 2] = 2;
    bytes[off + 3] = 13;
    bytes[off + 4] = 12;
    writeU32(bytes, off + 5, @intCast(png.len));
    @memcpy(bytes[off + 9 .. off + 9 + png.len], png);
    return bytes;
}

fn cblcPngTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 8 + 48 + 8 + 12);
    @memset(bytes, 0);
    writeU16(bytes, 0, 3);
    writeU16(bytes, 2, 0);
    writeU32(bytes, 4, 1);

    const size = 8;
    writeU32(bytes, size + 0, 56);
    writeU32(bytes, size + 4, 20);
    writeU32(bytes, size + 8, 1);
    bytes[size + 16] = 13;
    bytes[size + 17] = @bitCast(@as(i8, -3));
    bytes[size + 18] = 12;
    bytes[size + 28] = 13;
    bytes[size + 29] = @bitCast(@as(i8, -3));
    bytes[size + 30] = 12;
    writeU16(bytes, size + 40, 1);
    writeU16(bytes, size + 42, 1);
    bytes[size + 44] = 16;
    bytes[size + 45] = 16;
    bytes[size + 46] = 32;

    const record = 56;
    writeU16(bytes, record + 0, 1);
    writeU16(bytes, record + 2, 1);
    writeU32(bytes, record + 4, 8);

    const subtable = 64;
    writeU16(bytes, subtable + 0, 3);
    writeU16(bytes, subtable + 2, 17);
    writeU32(bytes, subtable + 4, 4);
    writeU16(bytes, subtable + 8, 0);
    writeU16(bytes, subtable + 10, @intCast(5 + 4 + cbdtFixturePng().len));
    return bytes;
}

fn cbdtFixturePng() []const u8 {
    return &.{
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
        0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xd0,
        0x00, 0x00, 0x04, 0x81, 0x01, 0x80, 0x2c, 0x55, 0xce, 0xb0, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    };
}

fn svgTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M10 90 L50 10 L90 90 Z" fill="red"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgCurveTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M12 88 Q50 4 88 88 T12 88 Z" fill="red"/><path d="M20 82 C30 16 70 16 80 82 S30 96 20 82 Z" fill="rgba(0,0,255,0.5)"/><path d="M30 52 A20 16 0 0 1 70 52 L70 76 30 76 Z" fill="rgb(0%,50%,0%)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgShapeTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" opacity="0.75"><rect x="12" y="14" width="34" height="54" fill="green" fill-opacity="0.5"/><circle cx="70" cy="48" r="22" fill="#0000ff" opacity="0.5"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgTransformTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="0" y="0" width="20" height="20" fill="red" transform="translate(60 10)"/><rect x="10" y="10" width="10" height="10" fill="blue" transform="translate(10,50) scale(2 1.5)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgRotateTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="40" y="20" width="20" height="14" fill="red" transform="rotate(90 50 50)"/><rect x="12" y="72" width="12" height="10" fill="blue" transform="rotate(-45 18 77)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgSkewTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="10" y="20" width="16" height="20" fill="red" transform="skewX(45)"/><rect x="58" y="12" width="16" height="18" fill="blue" transform="skewY(45)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgGroupTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g fill="red" opacity="0.5" transform="translate(30 20)"><rect x="0" y="0" width="20" height="20"/><circle cx="50" cy="12" r="10" fill="blue"/></g></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgNestedGroupTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g fill="red" opacity="0.5" transform="translate(20 18)"><g transform="scale(1.5 1.25)"><rect x="0" y="0" width="16" height="16"/><circle cx="34" cy="10" r="8" fill="blue"/></g></g></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgStyleTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><style>.grouped{fill:red;opacity:0.5;transform:translate(30 20)}.accent{fill:red;fill-opacity:0.5}.accent, ellipse{fill:blue;fill-opacity:0.5}.hidden{display:none}#marked{fill:hsl(120,100%,25%);opacity:0.5}ellipse{fill:red;opacity:0.5}.accent, ellipse{fill:blue;opacity:0.5}.theme{color:hsla(240,100%,50%,0.5)}.ink{stroke:currentColor;stroke-width:6}.cyan{fill:cyan}.yellow{fill:yellow}.magenta{fill:magenta}.clear{fill:transparent}</style><g class="grouped"><rect x="0" y="0" width="20" height="20"/><circle cx="50" cy="12" r="10" class="accent"/></g><rect x="0" y="70" width="18" height="18" fill="green" class="hidden"/><rect id="marked" x="58" y="72" width="18" height="18"/><ellipse cx="26" cy="84" rx="8" ry="6"/><g class="theme"><rect x="78" y="72" width="14" height="14" fill="currentColor"/><line x1="78" y1="94" x2="94" y2="94" class="ink"/></g><rect x="2" y="2" width="8" height="8" class="cyan"/><rect x="12" y="2" width="8" height="8" class="yellow"/><rect x="22" y="2" width="8" height="8" class="magenta"/><rect x="32" y="2" width="8" height="8" class="clear"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgStrokeTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="14" y="16" width="32" height="40" fill="none" stroke="red" stroke-width="8"/><circle cx="72" cy="42" r="16" fill="none" style="stroke:blue; stroke-width:6; stroke-opacity:0.5"/><g stroke="green" stroke-width="6"><line x1="12" y1="86" x2="48" y2="86"/></g></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgLineCapTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><line x1="24" y1="24" x2="60" y2="24" stroke="red" stroke-width="10"/><line x1="24" y1="48" x2="60" y2="48" stroke="blue" stroke-width="10" stroke-linecap="round"/><line x1="24" y1="72" x2="60" y2="72" stroke="green" stroke-width="10" stroke-linecap="square"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgDashTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><line x1="10" y1="40" x2="90" y2="40" stroke="red" stroke-width="8" stroke-dasharray="12 8"/><polyline points="10 66 40 66 70 66 90 66" stroke="blue" stroke-width="6" stroke-dasharray="10"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgDashOffsetTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><line x1="10" y1="40" x2="90" y2="40" stroke="red" stroke-width="8" stroke-dasharray="12 8" stroke-dashoffset="12"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgLineJoinTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><polyline points="18 24 38 24 38 44" fill="none" stroke="red" stroke-width="10"/><polyline points="58 24 78 24 78 44" fill="none" stroke="blue" stroke-width="10" stroke-linejoin="round"/><polyline points="18 64 38 64 38 84" fill="none" stroke="green" stroke-width="10" stroke-linejoin="bevel"/><polyline points="58 64 78 64 78 84" fill="none" stroke="red" stroke-width="10" stroke-linejoin="miter" stroke-miterlimit="1"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgUseTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><rect id="tile" x="0" y="0" width="18" height="18" fill="red"/><circle id="dot" cx="8" cy="8" r="8" fill="blue"/><g id="pair" transform="translate(0 0)"><rect x="0" y="0" width="10" height="10" fill="red"/><circle cx="20" cy="5" r="5" fill="green"/></g></defs><use href="#tile" x="24" y="22"/><use href="#dot" x="58" y="48" opacity="0.5"/><use href="#pair" x="16" y="70"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgClipTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><clipPath id="leftHalf"><rect x="10" y="20" width="34" height="50"/></clipPath><clipPath id="roundClip"><circle cx="72" cy="48" r="16"/></clipPath><clipPath id="triClip"><path d="M48 80 L70 80 L59 58 Z"/></clipPath></defs><rect x="10" y="20" width="80" height="50" fill="red" clip-path="url(#leftHalf)"/><rect x="54" y="30" width="36" height="36" fill="blue" clip-path="url(#roundClip)"/><rect x="46" y="56" width="28" height="28" fill="green" clip-path="url(#triClip)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgMaskTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><mask id="fade"><rect x="10" y="20" width="36" height="50" fill="white" opacity="0.5"/></mask><mask id="spotMask"><circle cx="72" cy="48" r="16" fill="white" opacity="0.5"/></mask><mask id="triMask"><path d="M48 80 L70 80 L59 58 Z" fill="white" opacity="0.5"/></mask><mask id="comboMask"><rect x="12" y="78" width="16" height="12" fill="white" opacity="0.5"/><circle cx="42" cy="84" r="8" fill="white" opacity="0.5"/></mask><mask id="darkMask"><rect x="76" y="76" width="18" height="18" fill="black"/></mask></defs><rect x="10" y="20" width="80" height="50" fill="red" mask="url(#fade)"/><rect x="54" y="30" width="36" height="36" fill="blue" mask="url(#spotMask)"/><rect x="46" y="56" width="28" height="28" fill="green" mask="url(#triMask)"/><rect x="8" y="76" width="44" height="18" fill="blue" mask="url(#comboMask)"/><rect x="76" y="76" width="18" height="18" fill="green" mask="url(#darkMask)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgVisibilityTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="12" y="20" width="20" height="20" fill="red"/><rect x="40" y="20" width="20" height="20" fill="blue" display="none"/><g visibility="hidden"><rect x="68" y="20" width="20" height="20" fill="green"/></g><rect x="12" y="56" width="20" height="20" fill="blue" style="visibility:hidden"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgPathStrokeTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path d="M12 84 L50 16 L88 84 Z" fill="none" stroke="red" stroke-width="8"/><path d="M24 70 Q50 36 76 70" fill="none" style="stroke:blue; stroke-width:6; stroke-opacity:0.5"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgPolylineTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><polygon points="12,84 36,24 60,84" fill="red"/><polyline points="68 18 86 42 68 66" fill="none" stroke="blue" stroke-width="6"/><line x1="18" y1="18" x2="48" y2="18" stroke="green" stroke-width="6"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgEllipseTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><ellipse cx="32" cy="46" rx="22" ry="14" fill="red"/><ellipse cx="72" cy="46" rx="16" ry="24" fill="none" stroke="blue" stroke-width="6" stroke-opacity="0.5"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgGradientTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="rg" x1="10" y1="0" x2="90" y2="0"><stop offset="0" stop-color="red"/><stop offset="50%" stop-color="green"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect x="10" y="20" width="80" height="42" fill="url(#rg)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgRadialGradientTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><radialGradient id="spot" cx="50" cy="50" r="38"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></radialGradient></defs><circle cx="50" cy="50" r="38" fill="url(#spot)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgGradientSpreadTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="repeatg" x1="10" y1="0" x2="30" y2="0" spreadMethod="repeat"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><linearGradient id="reflectg" x1="10" y1="0" x2="30" y2="0" spreadMethod="reflect"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect x="10" y="16" width="80" height="24" fill="url(#repeatg)"/><rect x="10" y="56" width="80" height="24" fill="url(#reflectg)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn svgGradientTransformTable(allocator: std.mem.Allocator) ![]u8 {
    const document =
        \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="rotg" x1="0" y1="0" x2="80" y2="0" gradientTransform="rotate(90)"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><rect x="20" y="10" width="52" height="80" fill="url(#rotg)"/></svg>
    ;
    return svgTableForDocument(allocator, document);
}

fn gdefClassTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 38);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 0);
    writeU16(bytes, 4, 14);
    writeU16(bytes, 10, 28);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 1);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 1);
    writeU16(bytes, 22, 2);
    writeU16(bytes, 24, 3);
    writeU16(bytes, 26, 4);

    writeU16(bytes, 28, 1);
    writeU16(bytes, 30, 3);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 7);
    return bytes;
}

fn gsubIgnoreMarksTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 82);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 3);
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 28);
    writeU16(bytes, 20, 48);

    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 0x0002);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 8);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 6);
    writeI16(bytes, 34, 1);
    writeU16(bytes, 36, 1);
    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);

    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 0x0004);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 8);
    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 6);
    writeI16(bytes, 54, 1);
    writeU16(bytes, 56, 1);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 2);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 0x0008);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 8);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 6);
    writeI16(bytes, 74, 1);
    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 3);
    return bytes;
}

fn gposIgnoreMarksTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 88);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 3);
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 30);
    writeU16(bytes, 20, 52);

    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 0x0002);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 8);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 8);
    writeU16(bytes, 34, 0x0001);
    writeI16(bytes, 36, 50);
    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0x0004);
    writeU16(bytes, 48, 1);
    writeU16(bytes, 50, 8);
    writeU16(bytes, 52, 1);
    writeU16(bytes, 54, 8);
    writeU16(bytes, 56, 0x0001);
    writeI16(bytes, 58, 50);
    writeU16(bytes, 60, 1);
    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 2);

    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 0x0008);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 8);
    writeU16(bytes, 74, 1);
    writeU16(bytes, 76, 8);
    writeU16(bytes, 78, 0x0001);
    writeI16(bytes, 80, 50);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 3);
    return bytes;
}

fn svgTableForDocument(allocator: std.mem.Allocator, document: []const u8) ![]u8 {
    const document_list_offset = 10;
    const records_start = document_list_offset + 2;
    const document_offset = 2 + 12;
    const bytes = try allocator.alloc(u8, document_list_offset + document_offset + document.len);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU32(bytes, 2, document_list_offset);
    writeU32(bytes, 6, 0);
    writeU16(bytes, document_list_offset, 1);
    writeU16(bytes, records_start, 1);
    writeU16(bytes, records_start + 2, 1);
    writeU32(bytes, records_start + 4, document_offset);
    writeU32(bytes, records_start + 8, @intCast(document.len));
    @memcpy(bytes[document_list_offset + document_offset ..][0..document.len], document);
    return bytes;
}

fn writeF16Dot16(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i32 = @intFromFloat(value * 65536.0);
    writeU32(bytes, offset, @bitCast(fixed));
}

fn writeF2Dot14(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i16 = @intFromFloat(value * 16384.0);
    writeI16(bytes, offset, fixed);
}

fn glyfTable(allocator: std.mem.Allocator) ![]u8 {
    var bytes = try allocator.alloc(u8, 40);
    @memset(bytes, 0);
    const off = 12;
    writeI16(bytes, off + 0, 1);
    writeI16(bytes, off + 2, 0);
    writeI16(bytes, off + 4, 0);
    writeI16(bytes, off + 6, 700);
    writeI16(bytes, off + 8, 700);
    writeU16(bytes, off + 10, 2);
    writeU16(bytes, off + 12, 0);
    bytes[off + 14] = 0x31;
    bytes[off + 15] = 0x21;
    bytes[off + 16] = 0x25;
    writeU16(bytes, off + 17, 350);
    writeU16(bytes, off + 19, 350);
    bytes[off + 21] = 250;
    writeU16(bytes, off + 22, 700);
    return bytes;
}

fn cffTable(allocator: std.mem.Allocator) ![]u8 {
    var local_subrs = std.ArrayList(u8).empty;
    defer local_subrs.deinit(allocator);
    try appendBiasedSubrIndex(allocator, &local_subrs, &.{ 189, 189, 89, 189, 31, 28, 253, 218, 28, 253, 118, 5, 11 });

    var private_dict = std.ArrayList(u8).empty;
    defer private_dict.deinit(allocator);
    try appendDictInt(allocator, &private_dict, 2);
    try private_dict.append(allocator, 19);

    var charstrings = std.ArrayList(u8).empty;
    defer charstrings.deinit(allocator);
    try appendIndex(allocator, &charstrings, &.{
        &.{14},
        &.{ 139, 239, 1, 19, 0xff, 139, 139, 21, 28, 2, 188, 139, 5, 139, 10, 28, 254, 162, 28, 2, 188, 5, 14 },
    });

    var charstrings_offset: usize = 0;
    var private_offset: usize = 0;
    var prefix = std.ArrayList(u8).empty;
    defer prefix.deinit(allocator);
    while (true) {
        prefix.clearRetainingCapacity();
        try appendCffPrefix(allocator, &prefix, charstrings_offset, private_offset, private_dict.items.len);
        if (prefix.items.len == private_offset and prefix.items.len + private_dict.items.len + local_subrs.items.len == charstrings_offset) break;
        private_offset = prefix.items.len;
        charstrings_offset = prefix.items.len + private_dict.items.len + local_subrs.items.len;
    }

    try prefix.appendSlice(allocator, private_dict.items);
    try prefix.appendSlice(allocator, local_subrs.items);
    try prefix.appendSlice(allocator, charstrings.items);
    return try prefix.toOwnedSlice(allocator);
}

fn appendCffPrefix(allocator: std.mem.Allocator, out: *std.ArrayList(u8), charstrings_offset: usize, private_offset: usize, private_size: usize) !void {
    try out.appendSlice(allocator, &.{ 1, 0, 4, 1 });
    try appendIndex(allocator, out, &.{"Test"});
    var top_dict = std.ArrayList(u8).empty;
    defer top_dict.deinit(allocator);
    try appendDictInt(allocator, &top_dict, @intCast(private_size));
    try appendDictInt(allocator, &top_dict, @intCast(private_offset));
    try top_dict.append(allocator, 18);
    try appendDictInt(allocator, &top_dict, @intCast(charstrings_offset));
    try top_dict.append(allocator, 17);
    try appendIndex(allocator, out, &.{top_dict.items});
    try appendIndex(allocator, out, &.{});
    try appendIndex(allocator, out, &.{});
}

fn headTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 54);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU32(bytes, 4, 0x00010000);
    writeU32(bytes, 12, 0x5f0f3cf5);
    writeU16(bytes, 18, 1000);
    writeI16(bytes, 36, 0);
    writeI16(bytes, 38, 0);
    writeI16(bytes, 40, 700);
    writeI16(bytes, 42, 700);
    writeI16(bytes, 50, 0);
    return bytes;
}

fn hheaTable(allocator: std.mem.Allocator) ![]u8 {
    return hheaTableWithMetrics(allocator, 2);
}

fn hheaTableWithMetrics(allocator: std.mem.Allocator, h_metrics: u16) ![]u8 {
    const bytes = try allocator.alloc(u8, 36);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeI16(bytes, 4, 800);
    writeI16(bytes, 6, -200);
    writeI16(bytes, 8, 0);
    writeU16(bytes, 34, h_metrics);
    return bytes;
}

fn hmtxTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 8);
    writeU16(bytes, 0, 500);
    writeI16(bytes, 2, 0);
    writeU16(bytes, 4, 800);
    writeI16(bytes, 6, 0);
    return bytes;
}

fn hmtxTableWithLigature(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 12);
    writeU16(bytes, 0, 500);
    writeI16(bytes, 2, 0);
    writeU16(bytes, 4, 800);
    writeI16(bytes, 6, 0);
    writeU16(bytes, 8, 1000);
    writeI16(bytes, 10, 0);
    return bytes;
}

fn hmtxTableWithTwoExtraGlyphs(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 16);
    writeU16(bytes, 0, 500);
    writeI16(bytes, 2, 0);
    writeU16(bytes, 4, 800);
    writeI16(bytes, 6, 0);
    writeU16(bytes, 8, 1000);
    writeI16(bytes, 10, 0);
    writeU16(bytes, 12, 600);
    writeI16(bytes, 14, 0);
    return bytes;
}

fn hmtxTableWithFiveGlyphs(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 20);
    writeU16(bytes, 0, 500);
    writeI16(bytes, 2, 0);
    writeU16(bytes, 4, 800);
    writeI16(bytes, 6, 0);
    writeU16(bytes, 8, 800);
    writeI16(bytes, 10, 0);
    writeU16(bytes, 12, 800);
    writeI16(bytes, 14, 0);
    writeU16(bytes, 16, 800);
    writeI16(bytes, 18, 0);
    return bytes;
}

fn hmtxTableWithColorGlyphs(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 16);
    writeU16(bytes, 0, 500);
    writeI16(bytes, 2, 0);
    writeU16(bytes, 4, 800);
    writeI16(bytes, 6, 0);
    writeU16(bytes, 8, 800);
    writeI16(bytes, 10, 0);
    writeU16(bytes, 12, 800);
    writeI16(bytes, 14, 0);
    return bytes;
}

fn locaTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 6);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 6);
    writeU16(bytes, 4, 20);
    return bytes;
}

fn kernTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 24);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 0);
    writeU16(bytes, 6, 20);
    writeU16(bytes, 8, 1);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 0);
    writeU16(bytes, 14, 0);
    writeU16(bytes, 16, 1);
    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 1);
    writeI16(bytes, 22, -100);
    return bytes;
}

fn gsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 52);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 10);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 16);

    writeU16(bytes, 36, 1);
    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);

    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 4);

    writeU16(bytes, 46, 2);
    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 1);
    return bytes;
}

fn multipleGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 50);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 2);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 10);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 16);

    writeU16(bytes, 36, 1);
    writeU16(bytes, 38, 1);

    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 2);
    writeU16(bytes, 44, 2);
    writeU16(bytes, 46, 3);
    return bytes;
}

fn alternateGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 52);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 3);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 10);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 16);

    writeU16(bytes, 36, 1);
    writeU16(bytes, 38, 1);

    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 2);
    writeU16(bytes, 44, 3);
    writeU16(bytes, 46, 1);
    return bytes;
}

fn extensionGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 58);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 7);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 1);
    writeU32(bytes, 30, 8);

    writeU16(bytes, 34, 1);
    writeU16(bytes, 36, 6);
    writeI16(bytes, 38, 1);

    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 1);
    return bytes;
}

fn haniJapaneseGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 140);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 58);
    writeU16(bytes, 8, 84);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "hani");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 12);
    writeU16(bytes, 20, 1);
    writeTag(bytes, 22, "JAN ");
    writeU16(bytes, 26, 20);
    writeU16(bytes, 30, 0);
    writeU16(bytes, 32, 0xffff);
    writeU16(bytes, 34, 1);
    writeU16(bytes, 36, 0);
    writeU16(bytes, 38, 0);
    writeU16(bytes, 40, 0xffff);
    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 1);

    writeU16(bytes, 58, 2);
    writeTag(bytes, 60, "rlig");
    writeU16(bytes, 64, 14);
    writeTag(bytes, 66, "locl");
    writeU16(bytes, 70, 20);
    writeU16(bytes, 72, 0);
    writeU16(bytes, 74, 1);
    writeU16(bytes, 76, 0);
    writeU16(bytes, 78, 0);
    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);

    writeU16(bytes, 84, 2);
    writeU16(bytes, 86, 6);
    writeU16(bytes, 88, 26);
    writeU16(bytes, 90, 1);
    writeU16(bytes, 94, 1);
    writeU16(bytes, 96, 8);
    writeU16(bytes, 98, 1);
    writeU16(bytes, 100, 6);
    writeI16(bytes, 102, 0);
    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 1);
    writeU16(bytes, 108, 2);

    writeU16(bytes, 110, 1);
    writeU16(bytes, 114, 1);
    writeU16(bytes, 116, 8);
    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 6);
    writeI16(bytes, 122, 1);
    writeU16(bytes, 124, 1);
    writeU16(bytes, 126, 1);
    writeU16(bytes, 128, 1);
    return bytes;
}

fn selectiveGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 116);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "liga");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 1);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 34);

    writeU16(bytes, 54, 1);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);
    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 14);
    writeI16(bytes, 66, 2);
    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 0);

    writeU16(bytes, 82, 4);
    writeU16(bytes, 84, 0);
    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 8);
    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 10);
    writeU16(bytes, 94, 1);
    writeU16(bytes, 96, 16);
    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 1);
    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 1);
    writeU16(bytes, 108, 4);
    writeU16(bytes, 110, 2);
    writeU16(bytes, 112, 2);
    writeU16(bytes, 114, 1);
    return bytes;
}

fn contextGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 142);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "calt");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 70);

    writeU16(bytes, 54, 5);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 48);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 14);

    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 4);
    writeU16(bytes, 80, 2);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 1);

    writeU16(bytes, 110, 1);
    writeU16(bytes, 112, 1);
    writeU16(bytes, 114, 1);

    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 0);
    writeU16(bytes, 122, 1);
    writeU16(bytes, 124, 8);

    writeU16(bytes, 126, 1);
    writeU16(bytes, 128, 10);
    writeI16(bytes, 130, 2);
    writeU16(bytes, 136, 1);
    writeU16(bytes, 138, 1);
    writeU16(bytes, 140, 1);
    return bytes;
}

fn contextFormat3GsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 124);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "calt");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 52);

    writeU16(bytes, 54, 5);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 3);
    writeU16(bytes, 64, 2);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 16);
    writeU16(bytes, 70, 22);
    writeU16(bytes, 72, 1);
    writeU16(bytes, 74, 1);

    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);

    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 1);

    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 0);
    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 8);
    writeU16(bytes, 108, 1);
    writeU16(bytes, 110, 10);
    writeI16(bytes, 112, 2);
    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 1);
    writeU16(bytes, 122, 1);
    return bytes;
}

fn contextClassGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 142);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "calt");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 70);

    writeU16(bytes, 54, 5);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 2);
    writeU16(bytes, 64, 48);
    writeU16(bytes, 66, 14);
    writeU16(bytes, 68, 2);
    writeU16(bytes, 70, 0);
    writeU16(bytes, 72, 28);

    writeU16(bytes, 76, 2);
    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);

    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 4);
    writeU16(bytes, 94, 2);
    writeU16(bytes, 96, 1);
    writeU16(bytes, 98, 1);
    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 1);

    writeU16(bytes, 110, 1);
    writeU16(bytes, 112, 1);
    writeU16(bytes, 114, 1);

    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 0);
    writeU16(bytes, 122, 1);
    writeU16(bytes, 124, 8);

    writeU16(bytes, 126, 1);
    writeU16(bytes, 128, 10);
    writeI16(bytes, 130, 2);
    writeU16(bytes, 136, 1);
    writeU16(bytes, 138, 1);
    writeU16(bytes, 140, 1);
    return bytes;
}

fn chainingGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 150);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "calt");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 78);

    writeU16(bytes, 54, 6);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 42);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 16);

    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 4);
    writeU16(bytes, 82, 0);
    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 2);
    writeU16(bytes, 88, 1);
    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 1);
    writeU16(bytes, 94, 0);
    writeU16(bytes, 96, 1);

    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 1);
    writeU16(bytes, 108, 1);

    writeU16(bytes, 126, 1);
    writeU16(bytes, 128, 0);
    writeU16(bytes, 130, 1);
    writeU16(bytes, 132, 8);
    writeU16(bytes, 134, 1);
    writeU16(bytes, 136, 10);
    writeI16(bytes, 138, 2);
    writeU16(bytes, 144, 1);
    writeU16(bytes, 146, 1);
    writeU16(bytes, 148, 1);
    return bytes;
}

fn reverseChainingGsubTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 98);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "rclt");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 1);
    writeU16(bytes, 50, 4);

    writeU16(bytes, 52, 8);
    writeU16(bytes, 54, 0);
    writeU16(bytes, 56, 1);
    writeU16(bytes, 58, 8);

    writeU16(bytes, 60, 1);
    writeU16(bytes, 62, 20);
    writeU16(bytes, 64, 0);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 26);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 3);

    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);

    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 1);
    writeU16(bytes, 90, 1);
    return bytes;
}

fn gposTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 62);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 2);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 22);
    writeU16(bytes, 30, 0x0004);
    writeU16(bytes, 32, 0x0002);
    writeU16(bytes, 34, 1);
    writeU16(bytes, 36, 28);

    writeU16(bytes, 48, 1);
    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 1);

    writeU16(bytes, 54, 1);
    writeU16(bytes, 56, 1);
    writeI16(bytes, 58, -100);
    writeI16(bytes, 60, -50);
    return bytes;
}

fn gposSingleTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 46);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 0x0001);
    writeI16(bytes, 32, 50);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);
    return bytes;
}

fn gposExtensionTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 54);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 9);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 1);
    writeU32(bytes, 30, 8);

    writeU16(bytes, 34, 1);
    writeU16(bytes, 36, 12);
    writeU16(bytes, 38, 0x0001);
    writeI16(bytes, 40, 50);

    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 1);
    writeU16(bytes, 50, 1);
    return bytes;
}

fn gposClassTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 82);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 2);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 2);
    writeU16(bytes, 28, 34);
    writeU16(bytes, 30, 0x0004);
    writeU16(bytes, 32, 0);
    writeU16(bytes, 34, 40);
    writeU16(bytes, 36, 48);
    writeU16(bytes, 38, 2);
    writeU16(bytes, 40, 2);
    writeI16(bytes, 48, -100);

    writeU16(bytes, 60, 1);
    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 1);

    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 1);

    writeU16(bytes, 74, 1);
    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);
    return bytes;
}

fn gposMarkTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 80);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 18);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 24);
    writeU16(bytes, 36, 36);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 1);

    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 18);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 12);

    writeU16(bytes, 68, 1);
    writeI16(bytes, 70, 0);
    writeI16(bytes, 72, 0);

    writeU16(bytes, 74, 1);
    writeI16(bytes, 76, 50);
    writeI16(bytes, 78, 100);
    return bytes;
}

fn gposMarkAnchorFormatsTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 86);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 18);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 24);
    writeU16(bytes, 36, 36);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 1);

    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 18);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 14);

    writeU16(bytes, 68, 2);
    writeI16(bytes, 70, 0);
    writeI16(bytes, 72, 0);
    writeU16(bytes, 74, 7);

    writeU16(bytes, 76, 3);
    writeI16(bytes, 78, 50);
    writeI16(bytes, 80, 100);
    writeU16(bytes, 82, 0);
    writeU16(bytes, 84, 0);
    return bytes;
}

fn gposMarkToMarkTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 80);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 6);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 18);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 24);
    writeU16(bytes, 36, 36);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 1);

    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 18);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 12);

    writeU16(bytes, 68, 1);
    writeI16(bytes, 70, 0);
    writeI16(bytes, 72, 0);

    writeU16(bytes, 74, 1);
    writeI16(bytes, 76, 75);
    writeI16(bytes, 78, 125);
    return bytes;
}

fn gposCursiveTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 62);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 3);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 18);
    writeU16(bytes, 34, 24);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeI16(bytes, 46, 0);
    writeI16(bytes, 48, 0);

    writeU16(bytes, 50, 1);
    writeI16(bytes, 52, 80);
    writeI16(bytes, 54, 40);
    return bytes;
}

fn gposMarkToLigatureTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 82);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);

    writeU16(bytes, 10, 0);

    writeU16(bytes, 12, 0);

    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);

    writeU16(bytes, 18, 5);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);

    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 12);
    writeU16(bytes, 30, 18);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 24);
    writeU16(bytes, 36, 36);

    writeU16(bytes, 38, 1);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 1);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 2);

    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 20);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 4);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 10);

    writeU16(bytes, 70, 1);
    writeI16(bytes, 72, 0);
    writeI16(bytes, 74, 0);

    writeU16(bytes, 76, 1);
    writeI16(bytes, 78, 60);
    writeI16(bytes, 80, 120);
    return bytes;
}

fn gposContextTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 126);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "kern");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 52);

    writeU16(bytes, 54, 7);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 3);
    writeU16(bytes, 64, 2);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 16);
    writeU16(bytes, 70, 22);
    writeU16(bytes, 72, 1);
    writeU16(bytes, 74, 1);

    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);

    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 1);

    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 0);
    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 8);

    writeU16(bytes, 108, 1);
    writeU16(bytes, 110, 12);
    writeU16(bytes, 112, 0x0001);
    writeI16(bytes, 114, 50);

    writeU16(bytes, 120, 1);
    writeU16(bytes, 122, 1);
    writeU16(bytes, 124, 1);
    return bytes;
}

fn gposChainingTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 146);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "kern");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 72);

    writeU16(bytes, 54, 8);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 3);
    writeU16(bytes, 64, 1);
    writeU16(bytes, 66, 42);
    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 48);
    writeU16(bytes, 72, 1);
    writeU16(bytes, 74, 54);
    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 0);
    writeU16(bytes, 80, 1);

    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 1);
    writeU16(bytes, 108, 1);

    writeU16(bytes, 110, 1);
    writeU16(bytes, 112, 1);
    writeU16(bytes, 114, 1);

    writeU16(bytes, 116, 1);
    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 1);

    writeU16(bytes, 120, 1);
    writeU16(bytes, 122, 0);
    writeU16(bytes, 124, 1);
    writeU16(bytes, 126, 8);

    writeU16(bytes, 128, 1);
    writeU16(bytes, 130, 12);
    writeU16(bytes, 132, 0x0001);
    writeI16(bytes, 134, 50);

    writeU16(bytes, 140, 1);
    writeU16(bytes, 142, 1);
    writeU16(bytes, 144, 1);
    return bytes;
}

fn gposGlyphChainingTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 126);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "kern");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 52);

    writeU16(bytes, 54, 8);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 30);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 8);
    writeU16(bytes, 70, 1);
    writeU16(bytes, 72, 4);
    writeU16(bytes, 74, 1);
    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 0);
    writeU16(bytes, 88, 1);

    writeU16(bytes, 92, 1);
    writeU16(bytes, 94, 1);
    writeU16(bytes, 96, 1);

    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 0);
    writeU16(bytes, 104, 1);
    writeU16(bytes, 106, 8);

    writeU16(bytes, 108, 1);
    writeU16(bytes, 110, 12);
    writeU16(bytes, 112, 0x0001);
    writeI16(bytes, 114, 50);

    writeU16(bytes, 120, 1);
    writeU16(bytes, 122, 1);
    writeU16(bytes, 124, 1);
    return bytes;
}

fn gposClassChainingTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 154);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "kern");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 80);

    writeU16(bytes, 54, 8);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 2);
    writeU16(bytes, 64, 36);
    writeU16(bytes, 66, 42);
    writeU16(bytes, 68, 50);
    writeU16(bytes, 70, 58);
    writeU16(bytes, 72, 2);
    writeU16(bytes, 74, 0);
    writeU16(bytes, 76, 16);

    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 4);
    writeU16(bytes, 82, 1);
    writeU16(bytes, 84, 1);
    writeU16(bytes, 86, 1);
    writeU16(bytes, 88, 1);
    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 1);
    writeU16(bytes, 94, 0);
    writeU16(bytes, 96, 1);

    writeU16(bytes, 98, 1);
    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 1);

    writeClassDef1(bytes, 104, 1, 1);
    writeClassDef1(bytes, 112, 1, 1);
    writeClassDef1(bytes, 120, 1, 1);

    writeU16(bytes, 128, 1);
    writeU16(bytes, 130, 0);
    writeU16(bytes, 132, 1);
    writeU16(bytes, 134, 8);

    writeU16(bytes, 136, 1);
    writeU16(bytes, 138, 12);
    writeU16(bytes, 140, 0x0001);
    writeI16(bytes, 142, 50);

    writeU16(bytes, 148, 1);
    writeU16(bytes, 150, 1);
    writeU16(bytes, 152, 1);
    return bytes;
}

fn gposGlyphContextTable(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 132);
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 48);

    writeU16(bytes, 10, 1);
    writeTag(bytes, 12, "DFLT");
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 34, 1);
    writeTag(bytes, 36, "kern");
    writeU16(bytes, 40, 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 0);

    writeU16(bytes, 48, 2);
    writeU16(bytes, 50, 6);
    writeU16(bytes, 52, 62);

    writeU16(bytes, 54, 7);
    writeU16(bytes, 56, 0);
    writeU16(bytes, 58, 1);
    writeU16(bytes, 60, 8);

    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 14);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 28);

    writeU16(bytes, 76, 1);
    writeU16(bytes, 78, 1);
    writeU16(bytes, 80, 1);

    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 4);
    writeU16(bytes, 94, 2);
    writeU16(bytes, 96, 1);
    writeU16(bytes, 98, 1);
    writeU16(bytes, 100, 1);
    writeU16(bytes, 102, 1);

    writeU16(bytes, 110, 1);
    writeU16(bytes, 112, 0);
    writeU16(bytes, 114, 1);
    writeU16(bytes, 116, 8);
    writeU16(bytes, 118, 1);
    writeU16(bytes, 120, 8);
    writeU16(bytes, 122, 0x0001);
    writeI16(bytes, 124, 50);
    writeU16(bytes, 126, 1);
    writeU16(bytes, 128, 1);
    writeU16(bytes, 130, 1);
    return bytes;
}

fn maxpTable(allocator: std.mem.Allocator) ![]u8 {
    return maxpTableWithGlyphs(allocator, 2);
}

fn maxpTableWithGlyphs(allocator: std.mem.Allocator, glyph_count: u16) ![]u8 {
    const bytes = try allocator.alloc(u8, 6);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, glyph_count);
    return bytes;
}

fn align4(value: usize) usize {
    return (value + 3) & ~@as(usize, 3);
}

fn searchRange(table_count: usize) u16 {
    var power: usize = 1;
    while (power * 2 <= table_count) power *= 2;
    return @intCast(power * 16);
}

fn entrySelector(table_count: usize) u16 {
    var power: usize = 1;
    var selector: u16 = 0;
    while (power * 2 <= table_count) {
        power *= 2;
        selector += 1;
    }
    return selector;
}

fn appendIndex(allocator: std.mem.Allocator, out: *std.ArrayList(u8), objects: []const []const u8) !void {
    try appendIndexWithOffSize(allocator, out, objects, 1);
}

fn appendIndexWithOffSize(allocator: std.mem.Allocator, out: *std.ArrayList(u8), objects: []const []const u8, off_size: u8) !void {
    try appendU16(allocator, out, @intCast(objects.len));
    if (objects.len == 0) return;
    try out.append(allocator, off_size);
    var offset: usize = 1;
    try appendOffset(allocator, out, offset, off_size);
    for (objects) |object| {
        offset += object.len;
        try appendOffset(allocator, out, offset, off_size);
    }
    for (objects) |object| try out.appendSlice(allocator, object);
}

fn appendBiasedSubrIndex(allocator: std.mem.Allocator, out: *std.ArrayList(u8), useful_subr: []const u8) !void {
    const count = 108;
    var offsets = try allocator.alloc(usize, count + 1);
    defer allocator.free(offsets);
    offsets[0] = 1;
    for (0..107) |i| offsets[i + 1] = offsets[i] + 1;
    offsets[108] = offsets[107] + useful_subr.len;

    try appendU16(allocator, out, count);
    try out.append(allocator, 2);
    for (offsets) |offset| try appendOffset(allocator, out, offset, 2);
    for (0..107) |_| try out.append(allocator, 11);
    try out.appendSlice(allocator, useful_subr);
}

fn appendOffset(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: usize, off_size: u8) !void {
    var shift: u6 = @intCast((@as(u16, off_size) - 1) * 8);
    while (true) {
        try out.append(allocator, @intCast((value >> shift) & 0xff));
        if (shift == 0) break;
        shift -= 8;
    }
}

fn appendDictInt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: i32) !void {
    if (value >= -107 and value <= 107) {
        try out.append(allocator, @intCast(value + 139));
    } else {
        try out.append(allocator, 29);
        try appendU32(allocator, out, @bitCast(value));
    }
}

fn appendU16(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: u16) !void {
    try out.append(allocator, @intCast(value >> 8));
    try out.append(allocator, @intCast(value & 0xff));
}

fn appendU32(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: u32) !void {
    try out.append(allocator, @intCast(value >> 24));
    try out.append(allocator, @intCast((value >> 16) & 0xff));
    try out.append(allocator, @intCast((value >> 8) & 0xff));
    try out.append(allocator, @intCast(value & 0xff));
}

fn checksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 4) {
        var word: u32 = 0;
        for (0..4) |j| {
            word <<= 8;
            if (i + j < data.len) word |= data[i + j];
        }
        sum +%= word;
    }
    return sum;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeClassDef1(bytes: []u8, offset: usize, start: u16, class: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, class);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeTag(bytes: []u8, offset: usize, value: []const u8) void {
    std.debug.assert(value.len == 4);
    @memcpy(bytes[offset .. offset + 4], value);
}
