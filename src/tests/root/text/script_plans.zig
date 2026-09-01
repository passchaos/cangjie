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
const inline_object = @import("../../../layout/inline_object/root.zig");

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

test "ordinary cascade itemizes scripts before same-face fallback" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedScriptDirectionalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\u{0628}";
    const options: @import("../../../shaping/plan/root.zig").ShapeOptions = .{
        .reorder_bidi = false,
        .native_direction_shaping = true,
    };

    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &buffer,
        text,
        20,
        options,
    );
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 3, 4 },
        &.{ shaped.glyphs[0].glyph_id, shaped.glyphs[1].glyph_id },
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 1 },
        &.{ shaped.glyphs[0].cluster, shaped.glyphs[1].cluster },
    );
    // Script boundaries are not rendering ownership boundaries. Adjacent
    // output from the same face remains one CascadeRun for fast bidi/reflow.
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs[0].glyph_len);

    var shaped_cache = support.ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    _ = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &shaped_cache,
        &buffer,
        text,
        20,
        options,
    );
    const cached = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &shaped_cache,
        &buffer,
        text,
        20,
        options,
    );
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.hits);
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 3, 4 },
        &.{ cached.glyphs[0].glyph_id, cached.glyphs[1].glyph_id },
    );
    try std.testing.expectEqual(@as(usize, 1), cached.runs.len);

    const scripted = try TextShaper.shapeUtf8ScriptRuns(
        cascade,
        &buffer,
        text,
        20,
        options,
    );
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 3, 4 },
        &.{ scripted.glyphs[0].glyph_id, scripted.glyphs[1].glyph_id },
    );
    try std.testing.expectEqual(@as(usize, 1), scripted.font_runs.len);
    try std.testing.expectEqual(@as(usize, 2), scripted.script_runs.len);
    try std.testing.expectEqual(Script.latin, scripted.script_runs[0].script);
    try std.testing.expectEqual(OpenTypeScriptTag.latn, scripted.script_runs[0].script_tag);
    try std.testing.expectEqual(Script.arabic, scripted.script_runs[1].script);
    try std.testing.expectEqual(OpenTypeScriptTag.arab, scripted.script_runs[1].script_tag);
}

test "ordinary cascade preserves caller direction for already-visual text" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const directional_bytes =
        try test_font.buildMixedScriptDirectionalGsubTtf(allocator);
    defer allocator.free(directional_bytes);
    var directional_font = try Font.parse(allocator, directional_bytes);
    defer directional_font.deinit();
    const directional_cascade = FontCascade.init(&.{&directional_font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    // Disabling the paragraph bidi pass is the public contract for text whose
    // visual order was established by the caller. The Latin `ltra` feature
    // maps glyph 1 to 3, so retaining glyph 1 proves that script itemization
    // did not replace the explicit RTL direction with a resolved LTR level.
    const visual_rtl = try TextShaper.shapeUtf8CascadeWithOptions(
        directional_cascade,
        &buffer,
        "A\u{0628}",
        20,
        .{ .direction = .rtl, .reorder_bidi = false },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 4 }, &.{
        visual_rtl.glyphs[0].glyph_id,
        visual_rtl.glyphs[1].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, &.{
        visual_rtl.glyphs[0].cluster,
        visual_rtl.glyphs[1].cluster,
    });

    const arabic_bytes = try test_font.buildMixedScriptArabicRligTtf(allocator);
    defer allocator.free(arabic_bytes);
    var arabic_font = try Font.parse(allocator, arabic_bytes);
    defer arabic_font.deinit();
    const arabic_cascade = FontCascade.init(&.{&arabic_font});

    // Alef-lam is the caller-materialized visual order of logical lam-alef.
    // Native-direction shaping must reverse just that Arabic script item for
    // GSUB, where the order-sensitive required ligature maps it to glyph 7.
    // Bidi-level itemization used to clear `native_direction_shaping`, leaving
    // two glyphs and violating the already-visual input contract.
    const native_arabic = try TextShaper.shapeUtf8CascadeWithOptions(
        arabic_cascade,
        &buffer,
        "A \u{0627}\u{0644}",
        20,
        .{
            .reorder_bidi = false,
            .native_direction_shaping = true,
        },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 7 }, &.{
        native_arabic.glyphs[0].glyph_id,
        native_arabic.glyphs[1].glyph_id,
        native_arabic.glyphs[2].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &.{
        native_arabic.glyphs[0].cluster,
        native_arabic.glyphs[1].cluster,
        native_arabic.glyphs[2].cluster,
    });
    try std.testing.expectEqual(
        @as(usize, 4),
        native_arabic.glyphs[2].source_byte_len,
    );
}

test "LTR mixed Arabic rlig follows logical script-run order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedScriptArabicRligTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    // Logical alef-lam becomes visually adjacent as lam-alef, but that visual
    // order must never be fed back through Arabic required-ligature shaping.
    const no_ligature = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &buffer,
        "A ال",
        20,
        .{ .direction = .ltr },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 4, 3 }, &.{
        no_ligature.glyphs[0].glyph_id,
        no_ligature.glyphs[1].glyph_id,
        no_ligature.glyphs[2].glyph_id,
        no_ligature.glyphs[3].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 4, 2 }, &.{
        no_ligature.glyphs[0].cluster,
        no_ligature.glyphs[1].cluster,
        no_ligature.glyphs[2].cluster,
        no_ligature.glyphs[3].cluster,
    });

    const ligature = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &buffer,
        "A لا",
        20,
        .{ .direction = .ltr },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 7 }, &.{
        ligature.glyphs[0].glyph_id,
        ligature.glyphs[1].glyph_id,
        ligature.glyphs[2].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &.{
        ligature.glyphs[0].cluster,
        ligature.glyphs[1].cluster,
        ligature.glyphs[2].cluster,
    });
    try std.testing.expectEqual(@as(usize, 4), ligature.glyphs[2].source_byte_len);

    const with_digits = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &buffer,
        "A لا 12",
        20,
        .{ .direction = .ltr },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 5, 6, 2, 7 }, &.{
        with_digits.glyphs[0].glyph_id,
        with_digits.glyphs[1].glyph_id,
        with_digits.glyphs[2].glyph_id,
        with_digits.glyphs[3].glyph_id,
        with_digits.glyphs[4].glyph_id,
        with_digits.glyphs[5].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 7, 8, 6, 2 }, &.{
        with_digits.glyphs[0].cluster,
        with_digits.glyphs[1].cluster,
        with_digits.glyphs[2].cluster,
        with_digits.glyphs[3].cluster,
        with_digits.glyphs[4].cluster,
        with_digits.glyphs[5].cluster,
    });
}

test "uniform retained paragraph shapes Arabic rlig before bidi presentation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedScriptArabicRligTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    var no_ligature = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &buffer,
        "A ال",
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer no_ligature.deinit();
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 3, 4 }, &.{
        no_ligature.glyphs[0].glyph_id,
        no_ligature.glyphs[1].glyph_id,
        no_ligature.glyphs[2].glyph_id,
        no_ligature.glyphs[3].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 4 }, &.{
        no_ligature.glyphs[0].cluster,
        no_ligature.glyphs[1].cluster,
        no_ligature.glyphs[2].cluster,
        no_ligature.glyphs[3].cluster,
    });

    var ligature = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &buffer,
        "A لا",
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer ligature.deinit();
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 7 }, &.{
        ligature.glyphs[0].glyph_id,
        ligature.glyphs[1].glyph_id,
        ligature.glyphs[2].glyph_id,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &.{
        ligature.glyphs[0].cluster,
        ligature.glyphs[1].cluster,
        ligature.glyphs[2].cluster,
    });
    try std.testing.expectEqual(@as(usize, 4), ligature.glyphs[2].source_byte_len);
}

test "uniform paragraph keeps full-text script ownership across tab and object ranges" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedScriptDirectionalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text =
        "A\u{0628}\tA" ++ inline_object.object_replacement_utf8 ++
        "\u{0628}";
    const object = inline_object.Object{
        .id = 1,
        .byte_index = 5,
        .width = 8,
        .height = 8,
    };
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 200, .inline_objects = &.{object} },
    );
    defer paragraph.deinit();
    const shaped = paragraph.shapedText();

    try std.testing.expectEqual(@as(usize, 6), shaped.glyphs.len);
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 3, 4, 0, 3, 0, 4 },
        &.{
            shaped.glyphs[0].glyph_id,
            shaped.glyphs[1].glyph_id,
            shaped.glyphs[2].glyph_id,
            shaped.glyphs[3].glyph_id,
            shaped.glyphs[4].glyph_id,
            shaped.glyphs[5].glyph_id,
        },
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 1, 3, 4, 5, 8 },
        &.{
            shaped.glyphs[0].cluster,
            shaped.glyphs[1].cluster,
            shaped.glyphs[2].cluster,
            shaped.glyphs[3].cluster,
            shaped.glyphs[4].cluster,
            shaped.glyphs[5].cluster,
        },
    );
    try std.testing.expect(shaped.glyphs[2].isTab());
    try std.testing.expect(shaped.glyphs[4].isInlineObject());
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs[0].glyph_len);
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
