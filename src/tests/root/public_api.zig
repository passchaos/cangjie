//! Compile-time contract for the intentionally small supported facade.

const std = @import("std");
const cangjie = @import("../../root.zig");
const test_font = @import("../../test_font.zig");

test "public facade uses domain names without legacy aliases" {
    try std.testing.expect(!@hasDecl(cangjie, "Engine"));
    try std.testing.expect(@hasDecl(cangjie.font, "Face"));
    try std.testing.expect(@hasDecl(cangjie.font, "Cascade"));
    try std.testing.expect(@hasDecl(cangjie.font.container, "OwnedFace"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Glyph"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Engine"));
    try std.testing.expect(@hasDecl(cangjie.text, "segmentation"));
    try std.testing.expect(@hasDecl(cangjie.font.metadata, "variations"));

    // The redesign deliberately carries no compatibility layer. These checks
    // make accidental reintroduction of redundant names a test failure instead
    // of allowing the facade to grow flat again.
    try std.testing.expect(!@hasDecl(cangjie.shaping, "Context"));
    try std.testing.expect(!@hasDecl(cangjie.font, "Font"));
    try std.testing.expect(!@hasDecl(cangjie.font.container, "LoadedFont"));
    try std.testing.expect(!@hasDecl(cangjie.shaping, "FontCascade"));
    try std.testing.expect(!@hasDecl(cangjie.shaping, "GlyphPosition"));
    try std.testing.expect(!@hasDecl(cangjie.text, "OpenTypeScript"));
    try std.testing.expect(!@hasDecl(cangjie.text.bidi, "ExactClass"));
    try std.testing.expect(!@hasDecl(cangjie.text.bidi, "exactClass"));
    try std.testing.expect(!@hasDecl(cangjie.text.bidi, "Map"));
    try std.testing.expect(!@hasDecl(cangjie.text.segmentation, "WordBoundary"));
    try std.testing.expect(
        !@hasDecl(cangjie.font.metadata, "VariationCoordinate"),
    );

    const Face = cangjie.font.Face;
    try std.testing.expect(@typeInfo(Face) == .@"struct");
    try std.testing.expect(@hasDecl(Face, "parse"));
    try std.testing.expect(@hasDecl(Face, "parseIndex"));
    try std.testing.expect(@hasDecl(Face, "properties"));
    try std.testing.expect(@hasDecl(Face, "glyphs"));
    try std.testing.expect(@hasDecl(Face, "metrics"));
    try std.testing.expect(@hasDecl(Face, "names"));
    try std.testing.expect(@hasDecl(Face, "variations"));
    try std.testing.expect(@hasDecl(Face, "color"));
    try std.testing.expect(!@hasDecl(Face, "parseFace"));
    try std.testing.expect(!@hasDecl(Face, "glyphIndex"));
    try std.testing.expect(!@hasDecl(Face, "glyphOutline"));
    try std.testing.expect(!@hasDecl(Face, "horizontalMetrics"));
    try std.testing.expect(!@hasDecl(Face, "variationAxes"));
    try std.testing.expect(!@hasDecl(Face, "colorPaint"));
    try std.testing.expect(!@hasDecl(Face, "tables"));
    try std.testing.expect(!@hasDecl(Face, "tableData"));
    try std.testing.expect(!@hasDecl(Face, "applyGsub"));
    try std.testing.expect(!@hasDecl(Face, "collectGposAdjustments"));
    try std.testing.expect(!@hasDecl(Face, "LayoutScriptSelection"));
    try std.testing.expect(!@hasDecl(Face, "proveGsubTableForShaping"));
    try std.testing.expect(!@hasDecl(Face, "selectGsubLookupsForShaping"));
    try std.testing.expect(!@hasDecl(Face, "gdefLookupMetadataForShaping"));
    try std.testing.expect(!@hasDecl(Face, "glyphOutlineForRaster"));
    try std.testing.expect(
        !@hasDecl(Face, "resolvedSvgGlyphDocumentForRaster"),
    );
    inline for (.{
        cangjie.font.Glyphs,
        cangjie.font.Metrics,
        cangjie.font.Names,
        cangjie.font.Variations,
        cangjie.font.Color,
    }) |View| {
        try std.testing.expect(@typeInfo(View) == .@"struct");
    }
    inline for (.{
        cangjie.font.metadata.variations.Axis,
        cangjie.font.metadata.variations.Coordinate,
        cangjie.font.metadata.variations.Instance,
        cangjie.font.metadata.variations.StatAxis,
        cangjie.font.metadata.variations.StatValue,
        cangjie.font.metadata.variations.StatCoordinate,
    }) |Value| {
        // Variable-font values cross only the source-level Zig API. Keep them
        // concrete and inspectable rather than regressing to ABI-style opaque
        // handles when their implementation module changes.
        try std.testing.expect(@typeInfo(Value) == .@"struct");
    }

    const Rasterizer = cangjie.render.Rasterizer;
    try std.testing.expect(@typeInfo(Rasterizer) == .@"struct");
    try std.testing.expect(@typeInfo(cangjie.render.Prepared) == .@"struct");
    try std.testing.expect(@hasDecl(Rasterizer, "drawRun"));
    try std.testing.expect(@hasDecl(Rasterizer, "drawColorGlyph"));
    try std.testing.expect(!@hasDecl(Rasterizer, "renderRun"));
    try std.testing.expect(!@hasDecl(Rasterizer, "renderColorGlyph"));

    const Database = cangjie.font.database.Database;
    try std.testing.expect(@typeInfo(Database) == .@"struct");
    try std.testing.expect(@hasDecl(Database, "addFace"));
    try std.testing.expect(@hasDecl(Database, "cascadeForText"));
    try std.testing.expect(@hasDecl(Database, "layoutAttributed"));
    try std.testing.expect(!@hasDecl(Database, "addFont"));
    try std.testing.expect(!@hasDecl(Database, "buildCascadeForText"));
    try std.testing.expect(
        !@hasDecl(Database, "layoutAttributedParagraphUtf8"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.container.OwnedFace) == .@"struct",
    );
    try std.testing.expect(@typeInfo(cangjie.shaping.Engine) == .@"struct");
    try std.testing.expect(
        @typeInfo(cangjie.text.segmentation.WordDictionary) == .@"struct",
    );
}

test "concrete face views cover the normal application workflow" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();

    const properties = face.properties();
    try std.testing.expectEqual(cangjie.font.Format.truetype, properties.format);
    try std.testing.expectEqual(@as(u16, 1000), properties.units_per_em);
    try std.testing.expectEqual(@as(cangjie.font.GlyphId, 1), try face.glyphs().index('A'));
    const metrics = try face.metrics().horizontal(1);
    try std.testing.expect(metrics.advance_width > 0);

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const run = try engine.shape(&face, .{ .text = "A", .font_size = 20 });
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(&face, run.font);
}

test "core font inspection is reachable through the public metadata domain" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const inspection = cangjie.font.metadata.core.inspect(&face);

    const header = try inspection.header();
    try std.testing.expectEqual(@as(u16, 1000), header.units_per_em);
    const max_profile = try inspection.maxProfile();
    try std.testing.expectEqual(@as(u16, 2), max_profile.glyph_count);

    const tables = try inspection.tables(allocator);
    defer allocator.free(tables);
    try std.testing.expect(tables.len != 0);
    const head_data = (try inspection.tableData(.{ 'h', 'e', 'a', 'd' })).?;
    try std.testing.expect(head_data.len >= 54);

    const charmaps = try inspection.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expect(charmaps.len != 0);
    const selected = (try inspection.defaultCharmap()).?;
    try std.testing.expectEqual(
        @as(cangjie.font.GlyphId, 1),
        try inspection.glyphIndex(selected, 'A'),
    );
    const first = (try inspection.firstMapping(selected)).?;
    try std.testing.expect(first.codepoint <= 'A');

    const names = try inspection.nameRecords(allocator);
    defer allocator.free(names);
    const meta = try inspection.metaRecords(allocator);
    defer allocator.free(meta);
    try std.testing.expect((try inspection.digitalSignature(allocator)) == null);
    try std.testing.expect((try inspection.gridFitAndScan(allocator)) == null);

    const locations = try inspection.glyphLocations(allocator);
    defer allocator.free(locations);
    try std.testing.expectEqual(max_profile.glyph_count, locations.len);
}

test "metric inspection exposes table and presentation metrics" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const inspection = cangjie.font.metadata.metrics.inspect(&face);

    const header = try inspection.horizontalHeader();
    try std.testing.expectEqual(@as(u16, 2), header.long_metric_count);
    try std.testing.expect((try inspection.verticalHeader()) == null);

    const metric = try inspection.horizontal(1);
    const table = try inspection.horizontalTable(allocator);
    defer allocator.free(table);
    try std.testing.expectEqual(@as(usize, 2), table.len);
    try std.testing.expectEqual(metric, table[1]);
    try std.testing.expect((try inspection.vertical(1)) == null);
    try std.testing.expect((try inspection.verticalTable(allocator)) == null);

    const decoration = try inspection.decoration();
    try std.testing.expect(decoration.underline_thickness > 0);
    try std.testing.expect((try inspection.deviceWidths(allocator)) == null);
    try std.testing.expect((try inspection.linearThresholds(allocator)) == null);
    try std.testing.expect((try inspection.verticalOrigins(allocator)) == null);
}

test "variation inspection exposes table-level variable font data" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const inspection = cangjie.font.metadata.variations.inspect(&face);

    const hvar = (try inspection.horizontalMetrics(allocator)).?;
    defer inspection.freeHorizontalMetrics(allocator, hvar);
    try std.testing.expectEqual(@as(u32, 0x00010000), hvar.version);
    try std.testing.expectEqual(
        @as(?i32, 4),
        try inspection.horizontalAdvanceDelta(1, &.{0.5}),
    );

    const vvar = (try inspection.verticalMetrics(allocator)).?;
    defer inspection.freeVerticalMetrics(allocator, vvar);
    try std.testing.expectEqual(
        @as(?i32, 4),
        try inspection.verticalAdvanceDelta(1, &.{0.5}),
    );
    try std.testing.expect((try inspection.metricVariations(allocator)) == null);
    const stat_axes = try inspection.statAxes(allocator);
    defer allocator.free(stat_axes);
    const stat_values = try inspection.statValues(allocator);
    defer inspection.freeStatValues(allocator, stat_values);
    try std.testing.expect(
        (try inspection.compositeVariations(allocator)) == null,
    );
}

test "layout inspection covers cross-platform and AAT metadata" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const layout = cangjie.font.metadata.layout.inspect(&face);
    try std.testing.expect((try layout.baseline(allocator)) == null);
    try std.testing.expectEqual(
        cangjie.font.metadata.layout.GlyphClass.unclassified,
        try layout.glyphClass(1),
    );
    try std.testing.expectEqual(@as(u16, 0), try layout.markAttachClass(1));
    try std.testing.expectEqual(@as(i16, 0), try layout.kerning(0, 1));
    if (try layout.kern(allocator)) |kern| {
        defer layout.freeKern(allocator, kern);
        try std.testing.expect(kern.subtables.len != 0);
    }
    try std.testing.expect((try layout.cff2()) == null);
    const language_tags = try layout.languageTags(allocator);
    defer allocator.free(language_tags);

    const aat = cangjie.font.metadata.layout.aat.inspect(&face);
    try std.testing.expect((try aat.anchors(allocator)) == null);
    const features = try aat.features(allocator);
    defer aat.freeFeatures(allocator, features);
    try std.testing.expect((try aat.tracking(allocator)) == null);
    try std.testing.expect((try aat.extendedKerning(allocator)) == null);
    try std.testing.expect((try aat.glyphMetamorphosis(allocator)) == null);
}

test "MATH inspection is consumable by formula layout libraries" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMathTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const math = cangjie.font.metadata.math.inspect(&face);

    const info = (try math.table(allocator)).?;
    defer math.freeTable(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(
        @as(?i32, 80),
        try math.constant(.script_percent_scale_down),
    );
    try std.testing.expectEqual(
        @as(i16, -12),
        (try math.italicsCorrection(1)).?.value,
    );
    try std.testing.expect(try math.isExtendedShape(1));

    const variants = (try math.variants(allocator, 1, true)).?;
    defer math.freeVariants(allocator, variants);
    try std.testing.expectEqual(@as(usize, 1), variants.len);
    const parts = (try math.assemblyParts(allocator, 1, true)).?;
    defer math.freeAssemblyParts(allocator, parts);
    try std.testing.expectEqual(@as(usize, 1), parts.len);
    try std.testing.expectEqual(
        @as(?i16, -20),
        try math.kernValue(allocator, 1, .top_right, 0),
    );
}

test "color inspection exposes table-level palette and asset metadata" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const color = cangjie.font.metadata.color.inspect(&face);

    const palettes = try color.palettes(allocator);
    defer allocator.free(palettes);
    const labels = try color.paletteEntryLabels(allocator);
    defer allocator.free(labels);
    try std.testing.expect((try color.layerPaint(0, &.{})) == null);
    try std.testing.expect((try color.glyphPaint(1, &.{})) == null);
    try std.testing.expect((try color.svg(1)) == null);
    try std.testing.expect((try color.resolvedSvg(allocator, 1)) == null);
    const strikes = try color.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 0), strikes.len);
    try std.testing.expect((try color.bestBitmapPpem(16)) == null);
}

test "incremental font transfer inspection and patch parsers are public" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const incremental = cangjie.font.metadata.incremental;
    const inspection = incremental.inspect(&face);
    const patch_map = (try inspection.patchMap()).?;
    try std.testing.expectEqual(@as(u8, 2), patch_map.format);
    try std.testing.expect((try inspection.extensionPatchMap()) == null);

    var table_patch: [34]u8 = .{0} ** 34;
    @memcpy(table_patch[0..4], "IFTB");
    for (0..16) |index| table_patch[8 + index] = @intCast(index);
    std.mem.writeInt(u16, table_patch[24..26], 1, .big);
    std.mem.writeInt(u32, table_patch[26..30], 0, .big);
    std.mem.writeInt(u32, table_patch[30..34], 0, .big);
    const parsed_table = try incremental.parseTablePatch(
        allocator,
        &table_patch,
    );
    defer incremental.freeTablePatch(allocator, parsed_table);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0, 0 },
        parsed_table.patch_offsets,
    );

    var glyph_patch: [31]u8 = .{0} ** 31;
    @memcpy(glyph_patch[0..4], "IFTG");
    std.mem.writeInt(u32, glyph_patch[25..29], 256, .big);
    glyph_patch[29] = 0xaa;
    glyph_patch[30] = 0xbb;
    const parsed_glyph = try incremental.parseGlyphPatch(&glyph_patch);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xaa, 0xbb },
        parsed_glyph.brotli_stream,
    );
}

test "concrete engine remains valid after a value move" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();

    var original = cangjie.shaping.Engine.init(allocator, .{});
    // Moving before first use is the normal return-value path. Moving after a
    // call additionally proves that work methods rebind cache pointers that
    // previously targeted the old value address.
    _ = try original.shape(&face, .{ .text = "A", .font_size = 20 });
    var moved = original;
    original = undefined;
    defer moved.deinit();

    const run = try moved.shape(
        &face,
        .{ .text = "AA", .font_size = 20 },
    );
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
}

test "text domains are usable without font or shaping state" {
    const allocator = std.testing.allocator;
    const segmentation = cangjie.text.segmentation;
    const text = "A\u{0301} beta. \u{05d0}";

    var graphemes = try segmentation.graphemes(text);
    const first = graphemes.next().?;
    try std.testing.expectEqual(@as(usize, 0), first.byte_start);
    try std.testing.expectEqual("A\u{0301}".len, first.byte_len);

    var words = try segmentation.words(text);
    var saw_word = false;
    var saw_non_word = false;
    while (words.next()) |segment| {
        saw_word = saw_word or segment.is_word;
        saw_non_word = saw_non_word or !segment.is_word;
    }
    try std.testing.expect(saw_word);
    try std.testing.expect(saw_non_word);

    var sentences = try segmentation.sentences(text);
    try std.testing.expect(sentences.next() != null);
    var line_breaks = try segmentation.lineBreaks(text);
    try std.testing.expect(line_breaks.next() != null);

    var bidi = try cangjie.text.bidi.resolve(
        allocator,
        text,
        .auto,
    );
    defer bidi.deinit();
    try std.testing.expect(bidi.scalars.len != 0);
    try std.testing.expectEqual(
        cangjie.text.bidi.Class.lri,
        cangjie.text.bidi.class(0x2066),
    );

    const runs = try cangjie.text.script.collectRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expect(runs.len != 0);
    try std.testing.expectEqual(
        cangjie.text.joining.Type.dual,
        cangjie.text.joining.typeOf(0x0628),
    );
    try std.testing.expectEqual(
        cangjie.text.vertical.Orientation.upright,
        cangjie.text.vertical.orientation(0x4e00),
    );
}

test "allocating segmentation preserves streaming semantics" {
    const allocator = std.testing.allocator;
    const segmentation = cangjie.text.segmentation;
    const text = "hello, world";

    const words = try segmentation.collect.words(allocator, text);
    defer allocator.free(words);
    try std.testing.expect(words.len >= 3);
    var saw_punctuation = false;
    for (words) |segment| {
        saw_punctuation = saw_punctuation or !segment.is_word;
    }
    try std.testing.expect(saw_punctuation);

    const sentences = try segmentation.collect.sentences(
        allocator,
        " \t\r\n",
    );
    defer allocator.free(sentences);
    try std.testing.expect(sentences.len != 0);
}

test "dictionary line segmentation is independently consumable" {
    const allocator = std.testing.allocator;
    const segmentation = cangjie.text.segmentation;
    const text = "\u{0e20}\u{0e32}\u{0e29}\u{0e32}\u{0e44}\u{0e17}\u{0e22}";
    var dictionary = try segmentation.WordDictionary.init(
        allocator,
        .thai,
        &.{ "\u{0e20}\u{0e32}\u{0e29}\u{0e32}", "\u{0e44}\u{0e17}\u{0e22}" },
    );
    defer dictionary.deinit();

    const breaks = try segmentation.collect.lineBreaks(
        allocator,
        text,
        &dictionary,
    );
    defer allocator.free(breaks);
    var found_dictionary_boundary = false;
    for (breaks) |opportunity| {
        found_dictionary_boundary =
            found_dictionary_boundary or opportunity.byte_offset == 12;
    }
    try std.testing.expect(found_dictionary_boundary);
}

test "shaping and paragraph domains expose reusable library workflows" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();

    const shaped = try engine.shapeText(cascade, .{
        .text = "AAA",
        .font_size = 20,
    });
    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);

    const fallback = try cangjie.shaping.diagnostics.fontFallback(
        allocator,
        cascade,
        "A",
    );
    defer allocator.free(fallback);
    try std.testing.expectEqual(@as(usize, 1), fallback.len);
    try std.testing.expectEqual(@as(usize, 0), fallback[0].font_index);

    var quality = try cangjie.shaping.diagnostics.quality(
        allocator,
        cascade,
        "A",
        20,
        .{},
    );
    defer quality.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), quality.glyph_count);
    try std.testing.expectEqual(@as(usize, 0), quality.missing_glyph_count);

    var caret = try cangjie.shaping.diagnostics.caretConsistency(
        allocator,
        cascade,
        "A",
        20,
        .{},
    );
    defer caret.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), caret.issue_count);

    var paragraph = try engine.prepareParagraph(cascade, .{
        .text = "A A A",
        .font_size = 20,
        .options = .{ .max_width = 100 },
    });
    defer paragraph.deinit();
    var reflow = cangjie.paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try paragraph.layout(
        &reflow,
        .{ .max_width = 15 },
    );
    try std.testing.expect(narrow.lines.len > 1);
}

test "public container value keeps decoded bytes alive for its face" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var owned = try cangjie.font.container.OwnedFace.load(
        allocator,
        bytes,
        bytes.len,
    );
    defer owned.deinit();
    try std.testing.expectEqual(
        @as(cangjie.font.GlyphId, 1),
        try owned.face().glyphs().index('A'),
    );
}

test "public database returns concrete faces and cascades" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);

    var database = cangjie.font.database.Database.init(allocator);
    defer database.deinit();
    _ = try database.addBytes(bytes);

    const matched = database.match(.{ .family = "Cangjie Sans" }).?;
    try std.testing.expectEqual(
        @as(cangjie.font.GlyphId, 1),
        try matched.face.glyphs().index('A'),
    );
    const cascade = try database.cascadeForText(
        allocator,
        .{ .family = "Cangjie Sans" },
        "A",
    );
    defer allocator.free(cascade.faces);
    try std.testing.expectEqual(@as(usize, 1), cascade.len());
    try std.testing.expectEqual(matched.face, cascade.faces[0]);
}
