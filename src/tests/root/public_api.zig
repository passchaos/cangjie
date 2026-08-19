//! Compile-time contract for the intentionally small supported facade.

const std = @import("std");
const cangjie = @import("../../root.zig");
const test_font = @import("../../test_font.zig");

test "public facade uses domain names without legacy aliases" {
    try std.testing.expect(!@hasDecl(cangjie, "Engine"));
    try std.testing.expect(!@hasDecl(cangjie, "editor"));
    try std.testing.expect(@hasDecl(cangjie.font, "Face"));
    try std.testing.expect(@hasDecl(cangjie.font, "Cascade"));
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingInstance) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingTarget) == .@"enum",
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingInterpreter) == .@"enum",
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingOptions) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingError) == .error_set,
    );
    try std.testing.expect(@hasDecl(cangjie.font.Face, "hintingInstance"));
    try std.testing.expect(@hasDecl(cangjie.font.Face, "hintingInstanceAt"));
    try std.testing.expect(
        @hasDecl(cangjie.font.Face, "hintingInstanceWithOptions"),
    );
    try std.testing.expect(
        @hasDecl(cangjie.font.Face, "hintingInstanceAtWithOptions"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.HintingPointTransaction) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.font.PixelOutline) == .@"struct",
    );
    try std.testing.expect(
        @hasDecl(cangjie.font.Face, "hintingPointTransaction"),
    );
    try std.testing.expect(
        @hasDecl(cangjie.font.Face, "executeHintingTransaction"),
    );
    try std.testing.expect(@hasDecl(cangjie.font.container, "OwnedFace"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Glyph"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Engine"));
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.InlineObject) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.PositionedInlineObject) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.OutOfFlowResolver) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.OutOfFlowPlacementRequest) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.TabStop) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.TabAlignment) == .@"enum",
    );
    try std.testing.expectEqual(
        @as(u21, 0xfffc),
        cangjie.paragraph.object_replacement_character,
    );
    try std.testing.expect(
        @typeInfo(cangjie.render.InlineObjectDrawCommand) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.render.TextDecorationDrawCommand) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.text.attributed.DecorationSegment) == .@"struct",
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.enums.values(cangjie.paragraph.LineBreakStrategy).len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        std.enums.values(cangjie.paragraph.WordBreak).len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        std.enums.values(cangjie.paragraph.OverflowWrap).len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        std.enums.values(cangjie.paragraph.WhiteSpaceCollapse).len,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        std.enums.values(cangjie.text.style.VerticalAlign).len,
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Text, "vertical_align"),
    );
    try std.testing.expect(
        !@hasField(cangjie.text.style.Paragraph, "vertical_align"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "line_break_strategy"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "writing_mode"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "text_orientation"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Layout, "writing_mode"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.GraphemeGeometry, "inline_size"),
    );
    try std.testing.expect(
        @hasField(
            cangjie.paragraph.TextGeometryVisualCaretStop,
            "inline_position",
        ),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "word_break"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "overflow_wrap"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "white_space_collapse"),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "line_break_policy_ranges"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.LineBreakPolicyRange) == .@"struct",
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Text, "wrap_mode"),
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Text, "word_break"),
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Text, "overflow_wrap"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.ContentWidths) == .@"struct",
    );
    try std.testing.expect(
        @hasDecl(cangjie.paragraph.Shaped, "contentWidths"),
    );
    try std.testing.expect(
        @hasDecl(cangjie.shaping.Engine, "contentWidths"),
    );
    try std.testing.expect(
        @hasField(
            cangjie.text.attributed.ParagraphLayout,
            "content_widths",
        ),
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.StyledResult, "content_widths"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.LineRegion) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.LineRegionResolver) == .@"struct",
    );
    try std.testing.expect(
        @hasField(cangjie.paragraph.Options, "line_regions"),
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.Breaker) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.BreakerCheckpoint) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.BreakerStep) == .@"union",
    );
    try std.testing.expect(
        @hasDecl(cangjie.paragraph.Shaped, "breakLines"),
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Paragraph, "line_break_strategy"),
    );
    try std.testing.expect(
        @hasField(cangjie.text.style.Paragraph, "writing_mode"),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        std.enums.values(cangjie.text.attributed.DecorationKind).len,
    );
    try std.testing.expect(@hasDecl(cangjie.text, "segmentation"));
    try std.testing.expect(@hasDecl(cangjie.text, "hyphenation"));
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
        cangjie.font.GlyphSession,
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
    try std.testing.expect(@hasDecl(Rasterizer, "drawHintedGlyph"));
    try std.testing.expect(@hasDecl(Rasterizer, "drawHintedRun"));
    try std.testing.expect(@hasDecl(Rasterizer, "drawPixelOutline"));
    try std.testing.expect(@hasDecl(Rasterizer, "preparePixelOutline"));
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
    try std.testing.expect(
        @typeInfo(cangjie.text.hyphenation.Dictionary) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.text.hyphenation.Dictionary.Mapping) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.Hyphenation) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.Kashida) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.FontExpansion) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.Punctuation) == .@"struct",
    );
    try std.testing.expect(
        @typeInfo(cangjie.paragraph.PunctuationConvention) == .@"enum",
    );
    try std.testing.expect(@hasDecl(
        cangjie.shaping.Glyph,
        "isSafeToInsertTatweel",
    ));
    try std.testing.expect(@hasDecl(
        cangjie.shaping.Glyph,
        "isKashida",
    ));
    try std.testing.expect(
        @typeInfo(cangjie.shaping.GlyphOrientation) == .@"enum",
    );
    try std.testing.expect(@hasDecl(
        cangjie.shaping.Glyph,
        "isSideways",
    ));
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

test "localized names match the Fontations names-only reference fixture" {
    const allocator = std.testing.allocator;
    const upstream = @embedFile("../data/fontations_names_only.ttf");
    // The 200-byte upstream fixture intentionally contains only `name`, so
    // reuse its exact table bytes inside a minimal outline-bearing SFNT that
    // satisfies Face's stronger whole-font contract.
    const table_count = std.mem.readInt(u16, upstream[4..6], .big);
    var name_offset: usize = 0;
    var name_length: usize = 0;
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (!std.mem.eql(u8, upstream[record_offset..][0..4], "name")) continue;
        name_offset = std.mem.readInt(u32, upstream[record_offset + 8 ..][0..4], .big);
        name_length = std.mem.readInt(u32, upstream[record_offset + 12 ..][0..4], .big);
        break;
    }
    try std.testing.expect(name_length != 0);
    try std.testing.expect(name_offset <= upstream.len);
    try std.testing.expect(name_length <= upstream.len - name_offset);
    const bytes = try test_font.buildTtfWithNameTable(
        allocator,
        upstream[name_offset .. name_offset + name_length],
    );
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const names = face.names();
    const localized = try names.localized(allocator, .subfamily);
    defer allocator.free(localized);
    try std.testing.expectEqual(@as(usize, 6), localized.len);

    const expected_languages = [_][]const u8{
        "en", "ar-SA", "el-GR", "pl-PL", "eu-ES", "zh-Hans",
    };
    const expected_values = [_][]const u8{
        "Regular",
        "عادي",
        "Κανονικά",
        "Normalny",
        "Arrunta",
        "正常",
    };
    var language_buffer: [32]u8 = undefined;
    var value_buffer: [64]u8 = undefined;
    for (localized, expected_languages, expected_values) |value, language, text| {
        try std.testing.expectEqualStrings(
            language,
            (try value.languageUtf8(&language_buffer)).?,
        );
        try std.testing.expectEqualStrings(text, try value.decodeUtf8(&value_buffer));
    }

    const english = (try names.englishOrFirst(
        allocator,
        .subfamily,
    )).?;
    try std.testing.expectEqualStrings("en", (try english.languageUtf8(&language_buffer)).?);
    try std.testing.expectEqualStrings("Regular", try english.decodeUtf8(&value_buffer));

    const family = try names.localized(allocator, .family);
    defer allocator.free(family);
    try std.testing.expectEqual(@as(usize, 1), family.len);
    try std.testing.expectEqualStrings("en-US", (try family[0].languageUtf8(&language_buffer)).?);
    try std.testing.expectEqualStrings("NameTest", try family[0].decodeUtf8(&value_buffer));

    // Put the en-US family record in the same name-ID set as the earlier Mac
    // English record. The higher-level selector must prefer en-US regardless
    // of canonical record order, exactly as Skrifa's english_or_first does.
    const priority_name = try allocator.dupe(
        u8,
        upstream[name_offset .. name_offset + name_length],
    );
    defer allocator.free(priority_name);
    const record_count = std.mem.readInt(u16, priority_name[2..4], .big);
    var changed = false;
    for (0..record_count) |index| {
        const record_offset = 6 + index * 12;
        const name_id = std.mem.readInt(u16, priority_name[record_offset + 6 ..][0..2], .big);
        if (name_id != @intFromEnum(cangjie.font.NameId.family)) continue;
        std.mem.writeInt(
            u16,
            priority_name[record_offset + 6 ..][0..2],
            @intFromEnum(cangjie.font.NameId.subfamily),
            .big,
        );
        changed = true;
    }
    try std.testing.expect(changed);
    const priority_bytes = try test_font.buildTtfWithNameTable(allocator, priority_name);
    defer allocator.free(priority_bytes);
    var priority_face = try cangjie.font.Face.parse(allocator, priority_bytes);
    defer priority_face.deinit();
    const preferred = (try priority_face.names().englishOrFirst(
        allocator,
        .subfamily,
    )).?;
    try std.testing.expectEqualStrings("en-US", (try preferred.languageUtf8(&language_buffer)).?);
    try std.testing.expectEqualStrings("NameTest", try preferred.decodeUtf8(&value_buffer));
}

test "face attributes match Skrifa's Fontations reference fixtures" {
    const allocator = std.testing.allocator;

    const fallback_upstream = @embedFile("../data/fontations_cmap12_font1.ttf");
    const fallback_head = try sfntTable(fallback_upstream, "head");
    const fallback_head_copy = try allocator.dupe(u8, fallback_head);
    defer allocator.free(fallback_head_copy);
    // A transplanted head table needs a fresh font-wide adjustment; the test
    // builder intentionally owns only table checksums, so zero the field as it
    // does for its native head fixture.
    @memset(fallback_head_copy[8..12], 0);
    const fallback_bytes = try test_font.buildTtfWithMetadataTables(allocator, &.{
        .{ .tag = "head".*, .data = fallback_head_copy },
    });
    defer allocator.free(fallback_bytes);
    var fallback = try cangjie.font.Face.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fallback_attributes = try fallback.attributes();
    try std.testing.expectEqual(cangjie.font.Stretch.normal, fallback_attributes.stretch);
    try std.testing.expectEqual(cangjie.font.Style.italic, fallback_attributes.style);
    try std.testing.expectEqual(cangjie.font.Weight.bold, fallback_attributes.weight);

    const os2_upstream = @embedFile("../data/fontations_cmap14_font1.ttf");
    const os2_head = try allocator.dupe(u8, try sfntTable(os2_upstream, "head"));
    defer allocator.free(os2_head);
    @memset(os2_head[8..12], 0);
    const os2_bytes = try test_font.buildTtfWithMetadataTables(allocator, &.{
        .{ .tag = "head".*, .data = os2_head },
        .{ .tag = "OS/2".*, .data = try sfntTable(os2_upstream, "OS/2") },
        .{ .tag = "post".*, .data = try sfntTable(os2_upstream, "post") },
    });
    defer allocator.free(os2_bytes);
    var os2 = try cangjie.font.Face.parse(allocator, os2_bytes);
    defer os2.deinit();
    const os2_attributes = try os2.attributes();
    try std.testing.expectEqual(cangjie.font.Stretch.semi_condensed, os2_attributes.stretch);
    try std.testing.expectEqual(@as(f32, 87.5), os2_attributes.stretch.percentage());
    try std.testing.expectEqual(cangjie.font.Weight.extra_bold, os2_attributes.weight);
    switch (os2_attributes.style) {
        .oblique => |angle| try std.testing.expectEqual(@as(?f32, -14.0), angle),
        else => return error.TestExpectedOblique,
    }

    // The italic bit has higher precedence than oblique when both are set.
    const italic_os2 = try allocator.dupe(u8, try sfntTable(os2_upstream, "OS/2"));
    defer allocator.free(italic_os2);
    const selection = std.mem.readInt(u16, italic_os2[62..64], .big);
    std.mem.writeInt(u16, italic_os2[62..64], selection | 0x0001, .big);
    const italic_bytes = try test_font.buildTtfWithMetadataTables(allocator, &.{
        .{ .tag = "head".*, .data = os2_head },
        .{ .tag = "OS/2".*, .data = italic_os2 },
        .{ .tag = "post".*, .data = try sfntTable(os2_upstream, "post") },
    });
    defer allocator.free(italic_bytes);
    var italic = try cangjie.font.Face.parse(allocator, italic_bytes);
    defer italic.deinit();
    try std.testing.expectEqual(cangjie.font.Style.italic, (try italic.attributes()).style);

    // Without post, retain oblique classification but leave its angle unknown.
    const no_post_bytes = try test_font.buildTtfWithMetadataTables(allocator, &.{
        .{ .tag = "head".*, .data = os2_head },
        .{ .tag = "OS/2".*, .data = try sfntTable(os2_upstream, "OS/2") },
    });
    defer allocator.free(no_post_bytes);
    var no_post = try cangjie.font.Face.parse(allocator, no_post_bytes);
    defer no_post.deinit();
    switch ((try no_post.attributes()).style) {
        .oblique => |angle| try std.testing.expect(angle == null),
        else => return error.TestExpectedOblique,
    }
}

fn sfntTable(bytes: []const u8, tag: []const u8) ![]const u8 {
    if (tag.len != 4 or bytes.len < 12) return error.InvalidFixture;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset > bytes.len or bytes.len - record_offset < 16) {
            return error.InvalidFixture;
        }
        if (!std.mem.eql(u8, bytes[record_offset..][0..4], tag)) continue;
        const offset: usize = @intCast(std.mem.readInt(u32, bytes[record_offset + 8 ..][0..4], .big));
        const length: usize = @intCast(std.mem.readInt(u32, bytes[record_offset + 12 ..][0..4], .big));
        if (offset > bytes.len or length > bytes.len - offset) return error.InvalidFixture;
        return bytes[offset .. offset + length];
    }
    return error.MissingTable;
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
    try std.testing.expect((try layout.justification(allocator)) == null);

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
    try std.testing.expect((try color.bitmapMask(1, 16)) == null);
    try std.testing.expect((try color.bitmapBgra(1, 16)) == null);
}

test "color inspection exposes borrowed premultiplied BGRA bitmaps" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCbdtBgraTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const color = cangjie.font.metadata.color.inspect(&face);
    const bgra = (try color.bitmapBgra(1, 16)) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 2), bgra.width);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 7, 13, 64, 128, 10, 20, 30, 255 },
        bgra.data,
    );
    const selected = (try color.bitmapData(1, 16)) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u8, bgra.data, selected.bgra.data);
}

test "color inspection exposes owned compound bitmap materialization" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCompoundEbdtTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var compound = (try cangjie.font.metadata.color.inspect(&face)
        .compoundBitmapAlloc(allocator, 2, 16)) orelse
        return error.TestUnexpectedResult;
    defer compound.deinit();
    try std.testing.expectEqual(
        cangjie.font.metadata.color.OwnedBitmapData.Kind.mask8,
        compound.kind,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 255, 0, 0, 0, 0, 0, 255, 0 },
        compound.data,
    );
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

test "table-keyed IFT patches rebuild a validated owned SFNT" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);
    const patch = try test_font.buildIftTableKeyedPatch(allocator);
    defer allocator.free(patch);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var compatibility_id: [16]u8 = undefined;
    for (&compatibility_id, 0..) |*byte, index| byte.* = @intCast(index);
    const patched = cangjie.font.metadata.incremental.applyTablePatchAlloc(
        allocator,
        &face,
        compatibility_id,
        patch,
        1024 * 1024,
    ) catch |err| switch (err) {
        error.BrotliRuntimeUnavailable => return,
        else => return err,
    };
    defer allocator.free(patched);
    var patched_face = try cangjie.font.Face.parse(allocator, patched);
    defer patched_face.deinit();
    const core = cangjie.font.metadata.core.inspect(&patched_face);
    // Fontations processes the first occurrence of a duplicate tag and ignores
    // later entries, so replacement wins over the duplicate drop record.
    try std.testing.expectEqualStrings(
        "replaced",
        (try core.tableData("kern".*)).?,
    );
    try std.testing.expect((try core.tableData("glyf".*)) != null);
}

test "table-keyed IFT patching rejects compatibility and offset failures" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);
    const patch = try test_font.buildIftTableKeyedPatch(allocator);
    defer allocator.free(patch);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var compatibility_id: [16]u8 = undefined;
    for (&compatibility_id, 0..) |*byte, index| byte.* = @intCast(index);

    var wrong = compatibility_id;
    wrong[0] = 99;
    try std.testing.expectError(
        error.IncompatiblePatch,
        cangjie.font.metadata.incremental.applyTablePatchAlloc(
            allocator,
            &face,
            wrong,
            patch,
            1024 * 1024,
        ),
    );
    const malformed = try allocator.dupe(u8, patch);
    defer allocator.free(malformed);
    std.mem.writeInt(u32, malformed[30..34], 1, .big);
    try std.testing.expectError(
        error.BadSfnt,
        cangjie.font.metadata.incremental.applyTablePatchAlloc(
            allocator,
            &face,
            compatibility_id,
            malformed,
            1024 * 1024,
        ),
    );
}

test "table-keyed IFT applies shared-dictionary Brotli diffs" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);
    const patch = try test_font.buildIftSharedDictionaryPatch(allocator);
    defer allocator.free(patch);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var compatibility_id: [16]u8 = undefined;
    for (&compatibility_id, 0..) |*byte, index| byte.* = @intCast(index);

    const patched = cangjie.font.metadata.incremental.applyTablePatchAlloc(
        allocator,
        &face,
        compatibility_id,
        patch,
        1024 * 1024,
    ) catch |err| switch (err) {
        error.BrotliRuntimeUnavailable => return,
        else => return err,
    };
    defer allocator.free(patched);
    var patched_face = try cangjie.font.Face.parse(allocator, patched);
    defer patched_face.deinit();
    try std.testing.expectEqualStrings(
        "hijkabcdeflmnohijkabcdeflmno\n",
        (try cangjie.font.metadata.core.inspect(&patched_face)
            .tableData("dict".*)).?,
    );
}

test "table-keyed IFT drop removes an optional table" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);
    const patch = try test_font.buildIftDropTablePatch(allocator);
    defer allocator.free(patch);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var compatibility_id: [16]u8 = undefined;
    for (&compatibility_id, 0..) |*byte, index| byte.* = @intCast(index);
    const patched = try cangjie.font.metadata.incremental.applyTablePatchAlloc(
        allocator,
        &face,
        compatibility_id,
        patch,
        1024 * 1024,
    );
    defer allocator.free(patched);
    var patched_face = try cangjie.font.Face.parse(allocator, patched);
    defer patched_face.deinit();
    try std.testing.expect(
        (try cangjie.font.metadata.core.inspect(&patched_face)
            .tableData("dict".*)) == null,
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
    try std.testing.expectEqualStrings(
        "17.0.0",
        cangjie.text.vertical.unicode_version,
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

    var gray_target = try cangjie.render.GrayTarget.init(
        allocator,
        32,
        32,
    );
    defer gray_target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setSmallGlyphEmboldening(false);
    try rasterizer.drawText(&gray_target, shaped, 2, 24);
    var covered_pixels: usize = 0;
    for (gray_target.pixels) |pixel| {
        if (pixel != 0) covered_pixels += 1;
    }
    try std.testing.expect(covered_pixels != 0);

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

    var draw_list = try cangjie.render.buildGlyphDrawList(
        allocator,
        narrow,
        .{},
    );
    defer draw_list.deinit();
    // Paragraph output retains spaces for hit testing and line geometry, while
    // the draw list omits empty outlines. The three visible "A" glyphs must
    // still preserve their source clusters through the renderer bridge.
    try std.testing.expectEqual(@as(usize, 3), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), draw_list.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 4), draw_list.glyphs[2].cluster);

    var debug_storage: [2048]u8 = undefined;
    var debug_writer = std.Io.Writer.fixed(&debug_storage);
    try cangjie.debug.dumpShapeRuns(&debug_writer, shaped);
    try cangjie.debug.dumpParagraphLayout(&debug_writer, narrow);
    try cangjie.debug.dumpFontFallback(&debug_writer, cascade, "A");
    try cangjie.debug.dumpMissingGlyphs(&debug_writer, cascade, "Z");
    const debug_output = debug_writer.buffered();
    try std.testing.expect(
        std.mem.indexOf(u8, debug_output, "shape.runs") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            debug_output,
            "paragraph mode=horizontal_tb size=",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, debug_output, "font_fallback") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, debug_output, "missing_glyphs") != null,
    );
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

    const spans = [_]cangjie.text.style.Span{.{
        .byte_range = .{ .start = 0, .len = 3 },
        .style = .{ .font_family = "Cangjie Sans", .font_size = 20 },
    }};
    const attributed = cangjie.text.attributed.Text{
        .text = "AAA",
        .spans = &spans,
    };

    const standalone_metrics = try cangjie.text.attributed.measure(
        allocator,
        cascade,
        attributed,
        100,
    );
    try std.testing.expect(standalone_metrics.width > 0);

    var standalone = try cangjie.text.attributed.layoutParagraph(
        allocator,
        cascade,
        attributed,
        100,
    );
    defer standalone.deinit();
    try std.testing.expectEqual(@as(usize, 3), standalone.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), standalone.style_runs.len);

    const query = cangjie.font.database.Query{
        .family = "Cangjie Sans",
    };
    const database_metrics = try database.measureAttributed(
        allocator,
        attributed,
        query,
        100,
    );
    try std.testing.expectApproxEqAbs(
        standalone_metrics.width,
        database_metrics.width,
        0.001,
    );

    var resolved = try database.layoutAttributed(
        allocator,
        attributed,
        query,
        100,
    );
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 3), resolved.glyphs.len);
    try std.testing.expectEqual(matched.face, resolved.font_runs[0].font);
}
