//! Compile-time contract for the intentionally small supported facade.

const std = @import("std");
const cangjie = @import("../../root.zig");
const test_font = @import("../../test_font.zig");

test "public facade uses domain names without legacy aliases" {
    try std.testing.expect(@hasDecl(cangjie, "Engine"));
    try std.testing.expect(@hasDecl(cangjie.font, "Face"));
    try std.testing.expect(@hasDecl(cangjie.font, "Cascade"));
    try std.testing.expect(@hasDecl(cangjie.font.container, "OwnedFace"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Glyph"));
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
    try std.testing.expect(@typeInfo(cangjie.Engine) == .@"struct");
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

    var engine = cangjie.Engine.init(allocator, .{});
    defer engine.deinit();
    const run = try engine.shape(&face, .{ .text = "A", .font_size = 20 });
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(&face, run.font);
}

test "concrete engine remains valid after a value move" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();

    var original = cangjie.Engine.init(allocator, .{});
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
