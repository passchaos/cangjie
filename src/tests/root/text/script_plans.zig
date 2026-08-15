//! Integration coverage migrated from the former package root.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const ShapePlanCache = support.ShapePlanCache;
const ShapePlanKey = support.ShapePlanKey;
const TextShaper = support.TextShaper;
const Script = support.Script;
const FeatureOverride = support.FeatureOverride;
const OpenTypeLanguageTag = support.OpenTypeLanguageTag;
const OpenTypeScriptTag = support.OpenTypeScriptTag;
const Font = support.Font;
const FontFormat = support.FontFormat;
const GlyphClass = support.GlyphClass;
const NameEncoding = support.NameEncoding;
const NameId = support.NameId;
const VariationCoordinate = support.VariationCoordinate;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const inferOpenTypeLanguageTag = support.inferOpenTypeLanguageTag;
const openTypeTag = support.openTypeTag;
const testing = support.testing;

test "shapes mixed-script text with script run metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const latin_bytes = try test_font.buildNamedTtfWithNames(allocator, "Latin Sans", "Regular", "Latin Sans Regular");
    defer allocator.free(latin_bytes);
    const cjk_bytes = try test_font.buildNamedCjkTtf(allocator);
    defer allocator.free(cjk_bytes);

    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var cjk = try Font.parse(allocator, cjk_bytes);
    defer cjk.deinit();

    const fonts = [_]*const Font{ &latin, &cjk };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const scripted = try TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "A一丁", 20, .{});

    try std.testing.expectEqual(@as(usize, 3), scripted.glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), scripted.font_runs.len);
    try std.testing.expectEqual(@as(usize, 2), scripted.script_runs.len);
    try std.testing.expectEqual(Script.latin, scripted.script_runs[0].script);
    try std.testing.expectEqual(OpenTypeScriptTag.latn, scripted.script_runs[0].script_tag);
    try std.testing.expectEqual(OpenTypeLanguageTag.dflt, scripted.script_runs[0].language_tag);
    try std.testing.expectEqual(@as(usize, 0), scripted.script_runs[0].glyph_start);
    try std.testing.expectEqual(@as(usize, 1), scripted.script_runs[0].glyph_len);
    try std.testing.expectEqual(Script.han, scripted.script_runs[1].script);
    try std.testing.expectEqual(OpenTypeScriptTag.hani, scripted.script_runs[1].script_tag);
    try std.testing.expectEqual(OpenTypeLanguageTag.zhs, scripted.script_runs[1].language_tag);
    try std.testing.expectEqual(@as(usize, 1), scripted.script_runs[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 2), scripted.script_runs[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), scripted.font_runs[1].font_index);

    const japanese = try TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "一丁", 20, .{ .language_tag = .jan });
    try std.testing.expectEqual(@as(usize, 1), japanese.script_runs.len);
    try std.testing.expectEqual(Script.han, japanese.script_runs[0].script);
    try std.testing.expectEqual(OpenTypeScriptTag.hani, japanese.script_runs[0].script_tag);
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, japanese.script_runs[0].language_tag);
}

test "shapes script runs with script and language specific OpenType lookups" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedCjkLanguageGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const default_shape = try TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "一", 20, .{});
    try std.testing.expectEqual(@as(usize, 1), default_shape.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), default_shape.glyphs[0].glyph_id);
    try std.testing.expectEqual(OpenTypeLanguageTag.zhs, default_shape.script_runs[0].language_tag);

    const japanese_shape = try TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "一", 20, .{ .language_tag = .jan });
    try std.testing.expectEqual(@as(usize, 1), japanese_shape.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), japanese_shape.glyphs[0].glyph_id);
    try std.testing.expectEqual(OpenTypeScriptTag.hani, japanese_shape.script_runs[0].script_tag);
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, japanese_shape.script_runs[0].language_tag);

    try std.testing.expectEqual(OpenTypeLanguageTag.jan, inferOpenTypeLanguageTag("一あ"));
}

test "caches shape plans by direction script language and features" {
    const allocator = std.testing.allocator;
    var cache = ShapePlanCache.init(allocator);
    defer cache.deinit();

    const disable_liga = [_]FeatureOverride{.{ .tag = openTypeTag("liga"), .enabled = false }};
    const latin_key = ShapePlanKey.fromText("abc", .{});
    const latin_again = ShapePlanKey.fromText("def", .{});
    const rtl_key = ShapePlanKey.fromText("abc", .{ .direction = .rtl });
    const logical_key = ShapePlanKey.fromText("abc", .{ .reorder_bidi = false });
    const feature_key = ShapePlanKey.fromText("abc", .{ .features = &disable_liga });
    const superscript_key = ShapePlanKey.fromText("abc", .{ .script_position = .superscript });
    const japanese_key = ShapePlanKey.fromText("一", .{ .language_tag = .jan });

    const first = try cache.getOrPut(latin_key);
    try std.testing.expectEqual(@as(usize, 1), first.hits);
    const second = try cache.getOrPut(latin_again);
    try std.testing.expectEqual(@as(usize, 2), second.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.plans.items.len);

    _ = try cache.getOrPut(rtl_key);
    _ = try cache.getOrPut(logical_key);
    _ = try cache.getOrPut(feature_key);
    _ = try cache.getOrPut(superscript_key);
    _ = try cache.getOrPut(japanese_key);
    try std.testing.expectEqual(@as(usize, 6), cache.plans.items.len);
    try std.testing.expect(latin_key.feature_hash != feature_key.feature_hash);
    try std.testing.expect(latin_key.script_position != superscript_key.script_position);
    try std.testing.expect(japanese_key.language_tag == .jan);
}

test "loads the first face from a minimal TTC collection" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.truetype, font.format);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));

    var explicit_face = try Font.parseFace(allocator, bytes, 0);
    defer explicit_face.deinit();
    try std.testing.expectEqual(@as(GlyphId, 1), try explicit_face.glyphIndex('A'));
}

test "reads font family style and full names from the name table" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Cangjie Sans", (try font.familyName(&buffer)).?);
    try std.testing.expectEqualStrings("Regular", (try font.subfamilyName(&buffer)).?);
    try std.testing.expectEqualStrings("Cangjie Sans Regular", (try font.fullName(&buffer)).?);
    try std.testing.expectEqualStrings("Cangjie Sans", (try font.nameString(.typographic_family, &buffer)).?);
    try std.testing.expectEqualStrings("CangjieSans-Regular", (try font.nameString(.postscript_name, &buffer)).?);
}

test "enumerates raw SFNT name records" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.nameRecords(allocator);
    defer allocator.free(records);

    try std.testing.expectEqual(@as(usize, 6), records.len);
    try std.testing.expectEqual(@as(u16, 3), records[0].platform_id);
    try std.testing.expectEqual(@as(u16, 1), records[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 0x0409), records[0].language_id);
    try std.testing.expectEqual(@as(u16, @intFromEnum(NameId.family)), records[0].name_id);
    try std.testing.expectEqual(NameEncoding.utf16_be, records[0].encoding);
    try std.testing.expectEqual(@as(usize, "Cangjie Sans".len * 2), records[0].string.len);

    var decoded: [128]u8 = undefined;
    try std.testing.expectEqualStrings("Cangjie Sans", try records[0].decodeUtf8(&decoded));
    try std.testing.expectEqual(@as(u16, @intFromEnum(NameId.postscript_name)), records[3].name_id);
    try std.testing.expectEqualStrings("CangjieSans-Regular", try records[3].decodeUtf8(&decoded));

    const minimal_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(minimal_bytes);
    var minimal = try Font.parse(allocator, minimal_bytes);
    defer minimal.deinit();

    const empty = try minimal.nameRecords(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "enumerates SFNT name language tags" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNameLanguageTagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.nameRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqual(@as(u16, 0x8000), records[0].language_id);

    const tags = try font.nameLanguageTags(allocator);
    defer allocator.free(tags);
    try std.testing.expectEqual(@as(usize, 1), tags.len);
    try std.testing.expectEqual(@as(u16, 0x8000), tags[0].language_id);

    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("fr-CA", try tags[0].decodeUtf8(&out));
    try std.testing.expectEqualStrings("fr-CA", (try font.nameLanguageTag(0x8000, &out)).?);
    try std.testing.expect((try font.nameLanguageTag(0x0409, &out)) == null);
    try std.testing.expect((try font.nameLanguageTag(0x8001, &out)) == null);

    const named_bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(named_bytes);
    var named = try Font.parse(allocator, named_bytes);
    defer named.deinit();

    const empty = try named.nameLanguageTags(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect((try named.nameLanguageTag(0x8000, &out)) == null);
}

test "lazy SFNT language tag lookup revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNameLanguageTagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var out: [32]u8 = undefined;
    try std.testing.expectEqualStrings("fr-CA", (try font.nameLanguageTag(0x8000, &out)).?);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var name_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "name")) name_offset = table.offset;
    }
    bytes[name_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.nameLanguageTag(0x8000, &out));
    try std.testing.expectError(error.BadSfnt, font.nameLanguageTags(allocator));
}

test "reads variable font axis metadata from fvar" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);

    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqualStrings("wght", &axes[0].tag);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), axes[0].min_value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 400.0), axes[0].default_value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 900.0), axes[0].max_value, 0.001);
    try std.testing.expectEqual(@as(u16, 256), axes[0].name_id);
    try std.testing.expectEqualStrings("wdth", &axes[1].tag);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), axes[1].min_value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), axes[1].default_value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), axes[1].max_value, 0.001);
    try std.testing.expectEqual(@as(u16, 257), axes[1].name_id);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), axes[0].clamp(50.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 900.0), axes[0].clamp(1000.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), axes[0].normalize(100.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), axes[0].normalize(400.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), axes[0].normalize(650.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), axes[0].normalize(900.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), axes[1].normalize(50.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), axes[1].normalize(200.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), try font.mapVariationCoordinate(0, axes[0].normalize(650.0)), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.625), try font.mapVariationCoordinate(0, axes[0].normalize(775.0)), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), try font.mapVariationCoordinate(1, axes[1].normalize(200.0)), 0.001);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(99, 0.5));
    const coords = [_]VariationCoordinate{
        .{ .tag = .{ 'w', 'd', 't', 'h' }, .value = 200.0 },
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 650.0 },
    };
    const normalized = try font.normalizedVariationCoordinates(allocator, &coords);
    defer allocator.free(normalized);
    try std.testing.expectEqual(@as(usize, 2), normalized.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), normalized[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), normalized[1], 0.001);
    try std.testing.expectError(error.BadSfnt, font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'X', 'X', 'X', 'X' }, .value = 1.0 },
    }));
    const default_normalized = try font.normalizedVariationCoordinates(allocator, &.{});
    defer allocator.free(default_normalized);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), default_normalized[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), default_normalized[1], 0.001);

    var name_buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Weight", (try font.nameString(@enumFromInt(axes[0].name_id), &name_buffer)).?);
    try std.testing.expectEqualStrings("Width", (try font.nameString(@enumFromInt(axes[1].name_id), &name_buffer)).?);

    const instances = try font.variationInstances(allocator);
    defer font.freeVariationInstances(allocator, instances);
    try std.testing.expectEqual(@as(usize, 2), instances.len);
    try std.testing.expectEqual(@as(u16, 258), instances[0].subfamily_name_id);
    try std.testing.expectEqual(@as(?u16, 259), instances[0].postscript_name_id);
    try std.testing.expectEqual(@as(usize, 2), instances[0].coordinates.len);
    try std.testing.expectEqualStrings("wght", &instances[0].coordinates[0].tag);
    try std.testing.expectApproxEqAbs(@as(f32, 400.0), instances[0].coordinates[0].value, 0.001);
    try std.testing.expectEqualStrings("wdth", &instances[0].coordinates[1].tag);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), instances[0].coordinates[1].value, 0.001);
    try std.testing.expectEqual(@as(u16, 260), instances[1].subfamily_name_id);
    try std.testing.expectEqual(@as(?u16, 261), instances[1].postscript_name_id);
    try std.testing.expectApproxEqAbs(@as(f32, 700.0), instances[1].coordinates[0].value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 150.0), instances[1].coordinates[1].value, 0.001);
    try std.testing.expectEqualStrings("Bold Wide", (try font.nameString(@enumFromInt(instances[1].subfamily_name_id), &name_buffer)).?);
    try std.testing.expectEqualStrings("CangjieVariable-BoldWide", (try font.nameString(@enumFromInt(instances[1].postscript_name_id.?), &name_buffer)).?);
}

test "reads STAT axis value metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVariableStatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?u16, 2), try font.statElidedFallbackNameId(allocator));

    const values = try font.statAxisValues(allocator);
    defer font.freeStatAxisValues(allocator, values);

    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(@as(u16, 1), values[0].format);
    try std.testing.expectEqual(@as(?u16, 0), values[0].axis_index);
    try std.testing.expectEqual(@as(u16, 0x0002), values[0].flags);
    try std.testing.expectEqual(@as(u16, 2), values[0].name_id);
    try std.testing.expectApproxEqAbs(@as(f32, 400.0), values[0].value.?, 0.001);
    try std.testing.expectEqual(@as(?f32, null), values[0].linked_value);
    try std.testing.expectEqual(@as(usize, 0), values[0].coordinates.len);
}

test "reads GDEF glyph classes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(GlyphClass.unclassified, try font.glyphClass(0));
    try std.testing.expectEqual(GlyphClass.base, try font.glyphClass(1));
    try std.testing.expectEqual(GlyphClass.ligature, try font.glyphClass(2));
    try std.testing.expectEqual(GlyphClass.mark, try font.glyphClass(3));
    try std.testing.expectEqual(GlyphClass.component, try font.glyphClass(4));
    try std.testing.expectEqual(@as(u16, 0), try font.markAttachClass(2));
    try std.testing.expectEqual(@as(u16, 7), try font.markAttachClass(3));
}

test "GSUB lookup flags ignore GDEF glyph classes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGsubIgnoreMarksTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    try glyphs.append(allocator, 2);
    try glyphs.append(allocator, 3);

    try font_shaping.applyGsub(&font, &glyphs, allocator);

    try std.testing.expectEqual(@as(usize, 3), glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), glyphs.items[0]);
    try std.testing.expectEqual(@as(GlyphId, 2), glyphs.items[1]);
    try std.testing.expectEqual(@as(GlyphId, 3), glyphs.items[2]);
}

test "GPOS lookup flags ignore GDEF glyph classes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGposIgnoreMarksTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]GlyphId{ 1, 2, 3 };
    var adjustments = std.ArrayList(@import("../../../gpos.zig").Adjustment).empty;
    defer adjustments.deinit(allocator);

    try font_shaping.collectGposAdjustments(&font, &glyphs, &adjustments, allocator);

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
