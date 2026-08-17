//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const FontFallbackCache = support.FontFallbackCache;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const Font = support.Font;
const AnkrAnchorInfo = support.AnkrAnchorInfo;
const FeatureSettingInfo = support.FeatureSettingInfo;
const GaspRange = support.GaspRange;
const TrueTypeProgramKind = support.TrueTypeProgramKind;
const MathValueRecordInfo = support.MathValueRecordInfo;
const MathGlyphValueRecordInfo = support.MathGlyphValueRecordInfo;
const MathVariantRecordInfo = support.MathVariantRecordInfo;
const MathPartRecordInfo = support.MathPartRecordInfo;
const MetricVariationIndexMapEntryInfo = support.MetricVariationIndexMapEntryInfo;
const MvarValueRecordInfo = support.MvarValueRecordInfo;
const KerxPairInfo = support.KerxPairInfo;
const MorxFeatureInfo = support.MorxFeatureInfo;
const FontCascade = support.FontCascade;
const testing = support.testing;

test "MATH constants metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMathTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.mathInfo(allocator)).?;
    defer font.freeMathInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(usize, 10), info.constants_offset);
    try std.testing.expectEqual(@as(usize, 224), info.glyph_info_offset);
    try std.testing.expectEqual(@as(usize, 270), info.variants_offset);
    try std.testing.expectEqual(@as(i16, 80), info.constants.script_percent_scale_down);
    try std.testing.expectEqual(@as(i16, 60), info.constants.script_script_percent_scale_down);
    try std.testing.expectEqual(@as(u16, 1000), info.constants.delimited_sub_formula_min_height);
    try std.testing.expectEqual(@as(u16, 1200), info.constants.display_operator_min_height);
    try std.testing.expectEqual(@as(usize, 51), info.constants.value_records.len);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = 11, .device_offset = 0 }, info.constants.value_records[0]);
    try std.testing.expectEqual(@as(i16, 55), info.constants.radical_degree_bottom_raise_percent);
    try std.testing.expectEqual(@as(?i32, 80), try font.mathConstantRaw(.script_percent_scale_down));
    try std.testing.expectEqual(@as(?i32, 1200), try font.mathConstantRaw(.display_operator_min_height));
    try std.testing.expectEqual(@as(?i32, 11), try font.mathConstantRaw(.math_leading));
    try std.testing.expectEqual(@as(?i32, 55), try font.mathConstantRaw(.radical_degree_bottom_raise_percent));
    try std.testing.expectEqual(@as(?usize, 8), info.glyph_info.italics_correction_info_offset);
    try std.testing.expectEqual(@as(?usize, 24), info.glyph_info.top_accent_attachment_offset);
    try std.testing.expectEqual(@as(?usize, 40), info.glyph_info.extended_shape_coverage_offset);
    try std.testing.expectEqual(@as(?usize, 100), info.glyph_info.math_kern_info_offset);
    try std.testing.expectEqual(@as(usize, 1), info.glyph_info.italics_corrections.len);
    try std.testing.expectEqual(MathGlyphValueRecordInfo{ .glyph_id = 1, .value_record = .{ .value = -12, .device_offset = 0 } }, info.glyph_info.italics_corrections[0]);
    try std.testing.expectEqual(MathGlyphValueRecordInfo{ .glyph_id = 1, .value_record = .{ .value = 42, .device_offset = 0 } }, info.glyph_info.top_accent_attachments[0]);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = -12, .device_offset = 0 }, (try font.mathItalicsCorrection(1)).?);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = 42, .device_offset = 0 }, (try font.mathTopAccentAttachment(1)).?);
    try std.testing.expect((try font.mathItalicsCorrection(0)) == null);
    try std.testing.expectEqualSlices(u16, &.{1}, info.glyph_info.extended_shape_glyphs);
    try std.testing.expect(try font.mathIsExtendedShape(1));
    try std.testing.expect(!try font.mathIsExtendedShape(0));
    try std.testing.expectEqual(@as(u16, 5), info.variants.min_connector_overlap);
    try std.testing.expectEqualSlices(u16, &.{1}, info.variants.vertical_glyphs);
    try std.testing.expectEqualSlices(u16, &.{0}, info.variants.horizontal_glyphs);
    try std.testing.expectEqual(@as(usize, 2), info.variants.construction_offsets.len);
    try std.testing.expectEqual(@as(?usize, 26), info.variants.construction_offsets[0]);
    try std.testing.expect(info.variants.construction_offsets[1] == null);
    try std.testing.expectEqual(@as(usize, 1), info.variants.constructions.len);
    try std.testing.expectEqual(@as(u16, 1), info.variants.constructions[0].glyph_id);
    try std.testing.expect(info.variants.constructions[0].vertical);
    try std.testing.expectEqual(MathVariantRecordInfo{ .glyph_id = 1, .advance_measurement = 900 }, info.variants.constructions[0].variants[0]);
    const assembly = info.variants.constructions[0].assembly.?;
    try std.testing.expectEqual(MathValueRecordInfo{ .value = -7, .device_offset = 0 }, assembly.italics_correction);
    try std.testing.expectEqual(MathPartRecordInfo{ .glyph_id = 1, .start_connector_length = 1, .end_connector_length = 2, .full_advance = 3, .flags = 1 }, assembly.parts[0]);

    const variants = (try font.mathGlyphVariants(allocator, 1, true)).?;
    defer font.freeMathGlyphVariants(allocator, variants);
    try std.testing.expectEqualSlices(MathVariantRecordInfo, &.{.{ .glyph_id = 1, .advance_measurement = 900 }}, variants);
    try std.testing.expect((try font.mathGlyphVariants(allocator, 0, true)) == null);

    const parts = (try font.mathGlyphAssemblyParts(allocator, 1, true)).?;
    defer font.freeMathGlyphAssemblyParts(allocator, parts);
    try std.testing.expectEqualSlices(MathPartRecordInfo, &.{.{ .glyph_id = 1, .start_connector_length = 1, .end_connector_length = 2, .full_advance = 3, .flags = 1 }}, parts);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = -7, .device_offset = 0 }, (try font.mathGlyphAssemblyItalicsCorrection(allocator, 1, true)).?);

    const kern_info = info.glyph_info.math_kern_info.?;
    try std.testing.expectEqual(@as(usize, 1), kern_info.records.len);
    try std.testing.expectEqual(@as(u16, 1), kern_info.records[0].glyph_id);
    const top_right = kern_info.records[0].kerns[0].?;
    try std.testing.expectEqual(MathValueRecordInfo{ .value = 10, .device_offset = 0 }, top_right.correction_heights[0]);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = -20, .device_offset = 0 }, top_right.kern_values[0]);
    try std.testing.expectEqual(MathValueRecordInfo{ .value = -30, .device_offset = 0 }, top_right.kern_values[1]);
    try std.testing.expectEqual(@as(?i16, -20), try font.mathKernValue(allocator, 1, .top_right, 0));
    try std.testing.expectEqual(@as(?i16, -30), try font.mathKernValue(allocator, 1, .top_right, 10));
    try std.testing.expectEqual(@as(?i16, null), try font.mathKernValue(allocator, 0, .top_right, 0));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.mathInfo(allocator)) == null);
    try std.testing.expect((try missing.mathConstantRaw(.math_leading)) == null);
    try std.testing.expect((try missing.mathItalicsCorrection(1)) == null);
    try std.testing.expect(!try missing.mathIsExtendedShape(1));
    try std.testing.expect((try missing.mathGlyphVariants(allocator, 1, true)) == null);
    try std.testing.expect((try missing.mathGlyphAssemblyParts(allocator, 1, true)) == null);
    try std.testing.expect((try missing.mathGlyphAssemblyItalicsCorrection(allocator, 1, true)) == null);
    try std.testing.expect((try missing.mathKernValue(allocator, 1, .top_right, 0)) == null);
}

test "lazy MATH metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMathTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.mathInfo(allocator)).?;
    defer font.freeMathInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var math_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "MATH")) math_offset = table.offset;
    }
    bytes[math_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.mathInfo(allocator));
}

test "minimal OTF exposes compact maxp metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const maxp = try font.maxpInfo();
    try std.testing.expectEqual(@as(u32, 0x00005000), maxp.version);
    try std.testing.expectEqual(@as(u16, 2), maxp.glyph_count);
    try std.testing.expectEqual(@as(?u16, null), maxp.max_points);
    try std.testing.expectEqual(@as(?u16, null), maxp.max_zones);
}

test "AAT morx chain metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMorxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.morxInfo(allocator)).?;
    defer font.freeMorxInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 2), info.version);
    try std.testing.expectEqual(@as(usize, 1), info.chains.len);
    try std.testing.expectEqual(@as(u32, 1), info.chains[0].default_flags);
    try std.testing.expectEqual(@as(usize, 44), info.chains[0].length);
    try std.testing.expectEqual(@as(usize, 1), info.chains[0].features.len);
    try std.testing.expectEqual(MorxFeatureInfo{ .feature_type = 1, .feature_setting = 2, .enable_flags = 4, .disable_flags = 0xfffffffb }, info.chains[0].features[0]);
    try std.testing.expectEqual(@as(usize, 1), info.chains[0].subtables.len);
    try std.testing.expectEqual(@as(u8, 4), info.chains[0].subtables[0].format);
    try std.testing.expect(info.chains[0].subtables[0].all_directions);
    try std.testing.expectEqual(@as(u32, 4), info.chains[0].subtables[0].sub_feature_flags);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, info.chains[0].subtables[0].data);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.morxInfo(allocator)) == null);
}

test "lazy AAT morx metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMorxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.morxInfo(allocator)).?;
    defer font.freeMorxInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var morx_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "morx")) morx_offset = table.offset;
    }
    bytes[morx_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.morxInfo(allocator));
}

test "AAT kerx format 0 pairs are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.kerxInfo(allocator)).?;
    defer font.freeKerxInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 2), info.version);
    try std.testing.expectEqual(@as(usize, 1), info.subtables.len);
    try std.testing.expectEqual(@as(u8, 0), info.subtables[0].format);
    try std.testing.expect(info.subtables[0].horizontal);
    try std.testing.expect(!info.subtables[0].cross_stream);
    try std.testing.expectEqual(@as(u32, 0), info.subtables[0].tuple_count);
    try std.testing.expectEqual(@as(usize, 2), info.subtables[0].pairs.len);
    try std.testing.expectEqual(KerxPairInfo{ .left = 0, .right = 0, .value = -10 }, info.subtables[0].pairs[0]);
    try std.testing.expectEqual(KerxPairInfo{ .left = 1, .right = 1, .value = -30 }, info.subtables[0].pairs[1]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.kerxInfo(allocator)) == null);
}

test "lazy AAT kerx metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.kerxInfo(allocator)).?;
    defer font.freeKerxInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var kerx_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "kerx")) kerx_offset = table.offset;
    }
    bytes[kerx_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.kerxInfo(allocator));
}

test "AAT ankr anchor points are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildAnkrTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.ankrInfo(allocator)).?;
    defer font.freeAnkrInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 0), info.version);
    try std.testing.expectEqual(@as(u16, 6), info.lookup_format);
    try std.testing.expectEqual(@as(usize, 12), info.lookup_table_offset);
    try std.testing.expectEqual(@as(usize, 32), info.glyph_data_table_offset);
    try std.testing.expectEqual(@as(usize, 2), info.glyphs.len);
    try std.testing.expectEqual(@as(u16, 0), info.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), info.glyphs[0].anchors.len);
    try std.testing.expectEqual(AnkrAnchorInfo{ .x = 10, .y = 20 }, info.glyphs[0].anchors[0]);
    try std.testing.expectEqual(AnkrAnchorInfo{ .x = -5, .y = 7 }, info.glyphs[0].anchors[1]);
    try std.testing.expectEqual(@as(u16, 1), info.glyphs[1].glyph_id);
    try std.testing.expectEqual(AnkrAnchorInfo{ .x = 100, .y = -50 }, info.glyphs[1].anchors[0]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.ankrInfo(allocator)) == null);
}

test "lazy AAT ankr metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildAnkrTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.ankrInfo(allocator)).?;
    defer font.freeAnkrInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ankr_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "ankr")) ankr_offset = table.offset;
    }
    bytes[ankr_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.ankrInfo(allocator));
}

test "TrueType fpgm and prep programs expose structural bytecode" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildTrueTypeProgramTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fpgm = (try font.fontProgramInfo(allocator)).?;
    defer font.freeTrueTypeProgramInfo(allocator, fpgm);
    try std.testing.expectEqual(TrueTypeProgramKind.font, fpgm.kind);
    try std.testing.expectEqual(@as(usize, 10), fpgm.bytecode.len);
    try std.testing.expectEqual(@as(usize, 3), fpgm.instructions.len);
    try std.testing.expectEqual(@as(u8, 0xb1), fpgm.instructions[0].opcode);
    try std.testing.expectEqual(@as(?u16, 2), fpgm.instructions[0].push_value_count);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, fpgm.instructions[0].immediate);
    try std.testing.expectEqual(@as(u8, 0x41), fpgm.instructions[1].opcode);
    try std.testing.expect(fpgm.instructions[1].push_words);
    try std.testing.expect(!fpgm.instructions[2].isPush());

    const prep = (try font.controlValueProgramInfo(allocator)).?;
    defer font.freeTrueTypeProgramInfo(allocator, prep);
    try std.testing.expectEqual(TrueTypeProgramKind.control_value, prep.kind);
    try std.testing.expectEqual(@as(usize, 1), prep.instructions.len);
    try std.testing.expectEqual(@as(u8, 0x40), prep.instructions[0].opcode);
    try std.testing.expectEqual(@as(?u16, 2), prep.instructions[0].push_value_count);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.fontProgramInfo(allocator)) == null);
    try std.testing.expect((try missing.controlValueProgramInfo(allocator)) == null);
}

test "lazy TrueType program metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildTrueTypeProgramTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fpgm = (try font.fontProgramInfo(allocator)).?;
    defer font.freeTrueTypeProgramInfo(allocator, fpgm);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var fpgm_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "fpgm")) fpgm_offset = table.offset;
    }
    // Mutating borrowed table bytes after parse invalidates the checksum
    // recorded in the table directory, so the lazy API must reject it.
    bytes[(fpgm_offset orelse return error.MissingTable) + 2] = 0x40;

    try std.testing.expectError(error.BadSfnt, font.fontProgramInfo(allocator));
}

test "cvt values and cvar tuple metadata are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const cvt_values = try font.cvtValues(allocator);
    defer allocator.free(cvt_values);
    try std.testing.expectEqualSlices(i16, &.{ 10, 20, -5, 0 }, cvt_values);

    const cvar = (try font.cvarInfo(allocator)).?;
    defer font.freeCvarInfo(allocator, cvar);
    try std.testing.expectEqual(@as(u32, 0x00010000), cvar.version);
    try std.testing.expectEqual(@as(u16, 1), cvar.tuple_count);
    try std.testing.expect(!cvar.uses_shared_point_numbers);
    try std.testing.expectEqual(@as(usize, 14), cvar.data_offset);
    try std.testing.expectEqual(@as(usize, 1), cvar.tuples.len);
    try std.testing.expectEqual(@as(u16, 5), cvar.tuples[0].variation_data_size);
    try std.testing.expect(!cvar.tuples[0].hasPrivatePointNumbers());
    try std.testing.expect(!cvar.tuples[0].hasIntermediateRegion());
    try std.testing.expectEqual(@as(usize, 1), cvar.tuples[0].peak_coordinates.len);
    try std.testing.expectEqual(@as(i16, 0x4000), cvar.tuples[0].peak_coordinates[0]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty_cvt = try missing.cvtValues(allocator);
    defer allocator.free(empty_cvt);
    try std.testing.expectEqual(@as(usize, 0), empty_cvt.len);
    try std.testing.expect((try missing.cvarInfo(allocator)) == null);
}

test "lazy cvar metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cvar = (try font.cvarInfo(allocator)).?;
    defer font.freeCvarInfo(allocator, cvar);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cvar")) cvar_offset = table.offset;
    }
    bytes[cvar_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.cvarInfo(allocator));
}

test "HVAR and VVAR metric variation maps are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const hvar = (try font.hvarInfo(allocator)).?;
    defer font.freeHvarInfo(allocator, hvar);
    try std.testing.expectEqual(@as(u32, 0x00010000), hvar.version);
    try std.testing.expectEqual(@as(usize, 42), hvar.item_variation_store_offset);
    const advance_width = hvar.advance_width_mapping.?;
    try std.testing.expectEqual(@as(u8, 0), advance_width.format);
    try std.testing.expectEqual(@as(u8, 1), advance_width.entry_size);
    try std.testing.expectEqual(@as(u8, 1), advance_width.inner_index_bit_count);
    try std.testing.expectEqual(@as(usize, 2), advance_width.entries.len);
    try std.testing.expectEqual(MetricVariationIndexMapEntryInfo{ .delta_set_outer_index = 0, .delta_set_inner_index = 0 }, advance_width.entries[0]);
    try std.testing.expectEqual(MetricVariationIndexMapEntryInfo{ .delta_set_outer_index = 0, .delta_set_inner_index = 1 }, advance_width.entries[1]);
    try std.testing.expect(hvar.rsb_mapping != null);

    try std.testing.expectEqual(@as(?i32, 4), try font.hvarAdvanceWidthDeltaAtCoords(1, &.{0.5}));
    try std.testing.expectEqual(@as(?i32, 4), try font.hvarRightSideBearingDeltaAtCoords(1, &.{0.5}));
    const default_metrics = try font.horizontalMetrics(1);
    try std.testing.expectEqual(@as(u16, 800), default_metrics.advance_width);
    const varied_metrics = try font.horizontalMetricsAtCoords(1, &.{0.5});
    try std.testing.expectEqual(@as(u16, 804), varied_metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 4), varied_metrics.left_side_bearing);

    const vvar = (try font.vvarInfo(allocator)).?;
    defer font.freeVvarInfo(allocator, vvar);
    try std.testing.expectEqual(@as(usize, 48), vvar.item_variation_store_offset);
    try std.testing.expect(vvar.tsb_mapping != null);
    try std.testing.expect(vvar.bsb_mapping != null);
    try std.testing.expectEqual(@as(usize, 2), vvar.advance_height_mapping.?.entries.len);
    try std.testing.expectEqual(@as(usize, 2), vvar.v_org_mapping.?.entries.len);
    try std.testing.expectEqual(@as(?i32, 4), try font.vvarAdvanceHeightDeltaAtCoords(1, &.{0.5}));
    try std.testing.expectEqual(@as(?i32, 4), try font.vvarBottomSideBearingDeltaAtCoords(1, &.{0.5}));
    const default_vertical = (try font.verticalMetrics(1)).?;
    try std.testing.expectEqual(@as(u16, 1000), default_vertical.advance_height);
    const varied_vertical = (try font.verticalMetricsAtCoords(1, &.{0.5})).?;
    try std.testing.expectEqual(@as(u16, 1004), varied_vertical.advance_height);
    try std.testing.expectEqual(@as(i16, 4), varied_vertical.top_side_bearing);
    try std.testing.expectEqual(@as(?i16, 914), try font.verticalOriginYAtCoords(1, &.{0.5}));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.hvarInfo(allocator)) == null);
    try std.testing.expect((try missing.hvarAdvanceWidthDeltaAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.hvarRightSideBearingDeltaAtCoords(1, &.{0.5})) == null);
    try std.testing.expectEqual(try missing.horizontalMetrics(1), try missing.horizontalMetricsAtCoords(1, &.{0.5}));
    try std.testing.expect((try missing.vvarInfo(allocator)) == null);
    try std.testing.expect((try missing.vvarAdvanceHeightDeltaAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.vvarBottomSideBearingDeltaAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.verticalMetricsAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.verticalOriginYAtCoords(1, &.{0.5})) == null);
}

test "gvar phantom points supply vertical metrics when VVAR is absent" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_bounds = try font.glyphBounds(1);
    const varied_bounds = try font.glyphBoundsAtCoords(1, &.{0.5});
    const default_metrics = (try font.verticalMetrics(1)) orelse return error.TestUnexpectedResult;
    const phantom = (try font.gvarPhantomPointDeltasAtCoords(allocator, 1, &.{0.5})) orelse return error.TestUnexpectedResult;
    const varied_metrics = (try font.verticalMetricsAtCoords(1, &.{0.5})) orelse return error.TestUnexpectedResult;

    const expected_origin: i32 = @intFromFloat(@floor(
        @as(f32, @floatFromInt(default_bounds.y_max)) +
            @as(f32, @floatFromInt(default_metrics.top_side_bearing)) +
            phantom.top.y +
            0.5,
    ));
    try std.testing.expectEqual(
        expected_origin - @as(i32, varied_bounds.y_max),
        @as(i32, varied_metrics.top_side_bearing),
    );
    try std.testing.expectEqual(
        @as(i32, default_metrics.advance_height) +
            @as(i32, @intFromFloat(@floor(phantom.verticalAdvanceDelta() + 0.5))),
        @as(i32, varied_metrics.advance_height),
    );
}

test "shaping applies normalized variation metric coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const default_run = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{});
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), default_run.width(), 0.001);

    const varied_run = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .normalized_variation_coords = &.{0.5} });
    try std.testing.expectApproxEqAbs(@as(f32, 16.08), varied_run.width(), 0.001);
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        varied_run.normalized_variation_coords,
    );
    try std.testing.expectError(error.BadSfnt, TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .normalized_variation_coords = &.{1.1} }));

    const vertical_default = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .writing_mode = .vertical_rl });
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), vertical_default.height(), 0.001);
    const vertical_varied = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .writing_mode = .vertical_rl, .normalized_variation_coords = &.{0.5} });
    try std.testing.expectApproxEqAbs(@as(f32, 20.08), vertical_varied.height(), 0.001);

    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    const first = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{});
    const first_width = first.width();
    const second = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .normalized_variation_coords = &.{0.5} });
    const second_width = second.width();
    const third = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .normalized_variation_coords = &.{0.5} });
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), first_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.08), second_width, 0.001);
    try std.testing.expectApproxEqAbs(second_width, third.width(), 0.001);
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        third.normalized_variation_coords,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        third.runs[0].normalizedVariationCoords(third),
    );
    try std.testing.expectEqual(@as(usize, 2), shaped_cache.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.hits);
}

test "lazy HVAR and VVAR metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const hvar = (try font.hvarInfo(allocator)).?;
    defer font.freeHvarInfo(allocator, hvar);
    const vvar = (try font.vvarInfo(allocator)).?;
    defer font.freeVvarInfo(allocator, vvar);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var hvar_offset: ?usize = null;
    var vvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "HVAR")) hvar_offset = table.offset;
        if (std.mem.eql(u8, &table.tag, "VVAR")) vvar_offset = table.offset;
    }

    bytes[hvar_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.hvarInfo(allocator));
    bytes[hvar_offset.?] -%= 1;

    bytes[vvar_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.vvarInfo(allocator));
}
