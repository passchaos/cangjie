//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const FontFallbackCache = support.FontFallbackCache;
const GlyphIndexCache = support.GlyphIndexCache;
const GlyphMetricsCache = support.GlyphMetricsCache;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const FontDatabase = support.FontDatabase;
const manifestEntryMatchesBytes = support.manifestEntryMatchesBytes;
const Font = support.Font;
const LoadedFont = support.LoadedFont;
const FontFormat = support.FontFormat;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const RenderTarget = support.RenderTarget;
const Rasterizer = support.Rasterizer;
const testing = support.testing;

test "measures paragraphs and batches text metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const metrics = try TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    try std.testing.expectApproxEqAbs(@as(f32, 30.0), metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), metrics.baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), metrics.ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), metrics.descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), metrics.leading, 0.001);

    const texts = [_][]const u8{ "A", "AA" };
    const batch = try TextShaper.measureParagraphsUtf8(allocator, cascade, &texts, 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    defer allocator.free(batch);

    try std.testing.expectEqual(@as(usize, 2), batch.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), batch[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), batch[1].width, 0.001);
}

test "loads a minimal OTF CFF font and rasterizes its charstring outline" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.opentype_cff, font.format);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));

    var outline = try font.glyphOutline(allocator, 1);
    defer outline.deinit();
    try std.testing.expect(outline.commands.items.len >= 4);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    var target = try RenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderRun(&target, run, 4, 24);

    var covered: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel > 0) covered += 1;
    }
    try std.testing.expect(covered > 10);
}

test "FontDatabase loads and scans WOFF1 font sources" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const sfnt = try test_font.buildNamedTtfWithNames(
        allocator,
        "Database WOFF",
        "Regular",
        "Database WOFF Regular",
    );
    defer allocator.free(sfnt);
    const woff = try testing.font_container.buildWoff1(allocator, sfnt, true);
    defer allocator.free(woff);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFontBytes(woff));
    const face = database.match(.{ .family = "Database WOFF" }) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(GlyphId, 1), try face.font.glyphIndex('A'));
    const manifest = try database.manifest(allocator);
    defer FontDatabase.freeManifest(allocator, manifest);
    try std.testing.expectEqual(@as(usize, 1), manifest.len);
    try std.testing.expect(manifestEntryMatchesBytes(manifest[0], woff));
    try std.testing.expect(!manifestEntryMatchesBytes(manifest[0], sfnt));

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "scan.woff",
        .data = woff,
    });
    var scanned = FontDatabase.init(allocator);
    defer scanned.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        try scanned.scanFontDir(
            std.testing.io,
            tmp_dir.dir,
            .limited(sfnt.len),
        ),
    );
    try std.testing.expect(scanned.match(.{ .family = "Database WOFF" }) != null);
    var limited = FontDatabase.init(allocator);
    defer limited.deinit();
    try std.testing.expectError(
        error.OutputTooLarge,
        limited.addFontFile(
            std.testing.io,
            tmp_dir.dir,
            "scan.woff",
            .limited(sfnt.len - 1),
        ),
    );
}

test "FontDatabase scans every face from DFONT sources" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const first = try test_font.buildNamedTtfWithNames(
        allocator,
        "Database DFont One",
        "Regular",
        "Database DFont One Regular",
    );
    defer allocator.free(first);
    const second = try test_font.buildNamedTtfWithNames(
        allocator,
        "Database DFont Two",
        "Regular",
        "Database DFont Two Regular",
    );
    defer allocator.free(second);
    const dfont = try testing.font_container.buildDfont(
        allocator,
        &.{ first, second },
    );
    defer allocator.free(dfont);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(
        @as(usize, 2),
        try database.addFontCollectionBytes(dfont),
    );
    try std.testing.expect(database.match(.{
        .family = "Database DFont One",
    }) != null);
    try std.testing.expect(database.match(.{
        .family = "Database DFont Two",
    }) != null);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "collection.dfont",
        .data = dfont,
    });
    var scanned = FontDatabase.init(allocator);
    defer scanned.deinit();
    try std.testing.expectEqual(
        @as(usize, 2),
        try scanned.scanFontDir(
            std.testing.io,
            tmp_dir.dir,
            .limited(dfont.len + 1),
        ),
    );
}

test "loads retained HarfBuzz DFONT fixture when installed" {
    const path = "/home/passchaos/Work/harfbuzz/test/shape/data/in-house/fonts/DFONT.dfont";
    const bytes = std.Io.Dir.readFileAlloc(
        std.Io.Dir.cwd(),
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(bytes);

    var loaded = try LoadedFont.loadFace(
        std.testing.allocator,
        bytes,
        0,
        16 * 1024 * 1024,
    );
    defer loaded.deinit();
    try std.testing.expectEqual(@as(GlyphId, 6), try loaded.font.glyphIndex(0x2026));
}

test "loads real WOFF1 and WOFF2 fonts when fixtures are installed" {
    const Case = struct {
        path: []const u8,
        codepoint: u21,
        expect_variations: bool = false,
    };
    const cases = [_]Case{
        .{
            .path = "/usr/share/yelp/mathjax/fonts/HTML-CSS/TeX/woff/MathJax_Main-Regular.woff",
            .codepoint = 'A',
        },
        .{
            .path = "/usr/share/fonts-sil-annapurna/woff/AnnapurnaSIL-Regular.woff",
            .codepoint = 0x0915,
        },
        .{
            .path = "/home/passchaos/Work/rustls/website/static/GeneralSans-Variable.woff2",
            .codepoint = 'A',
            .expect_variations = true,
        },
        .{
            .path = "/usr/share/fonts-sil-annapurna/woff2/AnnapurnaSIL-Regular.woff2",
            .codepoint = 0x0915,
        },
    };
    for (cases) |case| {
        const input = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            case.path,
            std.testing.allocator,
            .limited(16 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer std.testing.allocator.free(input);
        var loaded = try LoadedFont.load(
            std.testing.allocator,
            input,
            64 * 1024 * 1024,
        );
        defer loaded.deinit();
        try std.testing.expect((try loaded.font.glyphIndex(case.codepoint)) != 0);
        const axes = try loaded.font.variationAxes(std.testing.allocator);
        defer std.testing.allocator.free(axes);
        if (case.expect_variations) try std.testing.expect(axes.len != 0);

        var database = FontDatabase.init(std.testing.allocator);
        defer database.deinit();
        _ = try database.addFontBytesWithLimit(input, 64 * 1024 * 1024);
        try std.testing.expectEqual(@as(usize, 1), database.familyCount());
    }
}

test "shapes text across a fallback font cascade" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(allocator, 'B');
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &layout_buffer, "ABA", 20);

    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[2].font_index);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'B'), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs[2].cluster);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), shaped.width(), 0.001);

    var target = try RenderTarget.init(allocator, 80, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderShapedText(&target, shaped, 4, 24);

    var covered: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel > 0) covered += 1;
    }
    try std.testing.expect(covered > 20);
}

test "caches font fallback coverage by codepoint" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(allocator, 'B');
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var glyph_cache = GlyphIndexCache.init(allocator);
    defer glyph_cache.deinit();

    try std.testing.expectEqual(@as(usize, 0), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), fallback_cache.misses);
    try std.testing.expectEqual(@as(usize, 0), try fallback_cache.selectFont(cascade, 'A'));
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFont(cascade, 'B'));
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFont(cascade, 'B'));
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 2), fallback_cache.misses);
    try std.testing.expectEqual(@as(usize, 2), fallback_cache.entries.count());
    fallback_cache.clear();

    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontWithGlyphCache(cascade, &glyph_cache, 'B'));
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontWithGlyphCache(cascade, &glyph_cache, 'B'));
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.misses);
    try std.testing.expect(glyph_cache.entries.count() >= 2);
    try std.testing.expect(glyph_cache.misses >= 2);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeCached(cascade, &fallback_cache, &layout_buffer, "BABA", 20);

    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs.len);
    try std.testing.expectEqual(@as(usize, 4), shaped.runs.len);
    try std.testing.expect(fallback_cache.hits >= 3);
    try std.testing.expectEqual(@as(usize, 2), fallback_cache.misses);
    try std.testing.expectEqual(@as(usize, 2), fallback_cache.entries.count());

    fallback_cache.clear();
    try std.testing.expectEqual(@as(usize, 0), fallback_cache.entries.count());
    try std.testing.expectEqual(@as(usize, 0), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), fallback_cache.misses);
}

test "caches glyph metrics by font and glyph id during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var metrics_cache = GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();

    const first = try metrics_cache.horizontalMetrics(&font, 1);
    const second = try metrics_cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(first.advance_width, second.advance_width);
    try std.testing.expectEqual(first.left_side_bearing, second.left_side_bearing);
    try std.testing.expectEqual(@as(usize, 1), metrics_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), metrics_cache.misses);
    try std.testing.expectEqual(@as(usize, 1), metrics_cache.entries.count());

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeFullyCached(cascade, null, &metrics_cache, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 44.0), shaped.width(), 0.001);
    try std.testing.expect(metrics_cache.hits >= 4);
    try std.testing.expectEqual(@as(usize, 1), metrics_cache.misses);

    metrics_cache.clear();
    try std.testing.expectEqual(@as(usize, 0), metrics_cache.entries.count());
    try std.testing.expectEqual(@as(usize, 0), metrics_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), metrics_cache.misses);
}

test "caches glyph metrics by variation coordinates during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var metrics_cache = GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();

    const default_metrics = try metrics_cache.horizontalMetricsAtCoords(&font, 1, &.{});
    const varied_metrics = try metrics_cache.horizontalMetricsAtCoords(&font, 1, &.{0.5});
    const varied_again = try metrics_cache.horizontalMetricsAtCoords(&font, 1, &.{0.5});
    try std.testing.expectEqual(@as(u16, 800), default_metrics.advance_width);
    try std.testing.expectEqual(@as(u16, 804), varied_metrics.advance_width);
    try std.testing.expectEqual(varied_metrics.advance_width, varied_again.advance_width);
    try std.testing.expectEqual(@as(usize, 1), metrics_cache.hits);
    try std.testing.expectEqual(@as(usize, 2), metrics_cache.misses);
    try std.testing.expectEqual(@as(usize, 2), metrics_cache.entries.count());

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeFullyCachedWithOptions(cascade, null, &metrics_cache, null, &layout_buffer, "AAA", 20, .{
        .normalized_variation_coords = &.{0.5},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 44.24), shaped.width(), 0.001);
    try std.testing.expect(metrics_cache.hits >= 3);
    try std.testing.expectEqual(@as(usize, 2), metrics_cache.misses);
}

test "caches glyph indices by font and codepoint during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var glyph_cache = GlyphIndexCache.init(allocator);
    defer glyph_cache.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try glyph_cache.glyphIndex(&font, 'A'));
    try std.testing.expectEqual(@as(GlyphId, 1), try glyph_cache.glyphIndex(&font, 'A'));
    try std.testing.expectEqual(@as(usize, 1), glyph_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), glyph_cache.misses);
    try std.testing.expectEqual(@as(usize, 1), glyph_cache.entries.count());

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var metrics_cache = GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeFullyCachedWithOptions(cascade, null, &metrics_cache, &glyph_cache, &layout_buffer, "AAA", 20, .{});

    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expect(glyph_cache.hits >= 4);
    try std.testing.expectEqual(@as(usize, 1), glyph_cache.misses);

    glyph_cache.clear();
    try std.testing.expectEqual(@as(usize, 0), glyph_cache.entries.count());
    try std.testing.expectEqual(@as(usize, 0), glyph_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), glyph_cache.misses);
}

test "caches shaped runs for repeated shaping requests" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var metrics_cache = GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();

    var first_buffer = LayoutBuffer.init(allocator);
    defer first_buffer.deinit();
    const first = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, &metrics_cache, null, &shaped_cache, &first_buffer, "AAA", 20, .{});

    try std.testing.expectEqual(@as(usize, 3), first.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.entries.items.len);
    try std.testing.expectEqual(@as(usize, 0), shaped_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.misses);
    const fallback_misses_after_first = fallback_cache.misses;
    const metrics_misses_after_first = metrics_cache.misses;
    try std.testing.expect(fallback_misses_after_first > 0);
    try std.testing.expect(metrics_misses_after_first > 0);

    var second_buffer = LayoutBuffer.init(allocator);
    defer second_buffer.deinit();
    const second = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, &metrics_cache, null, &shaped_cache, &second_buffer, "AAA", 20, .{});

    try std.testing.expectEqual(@as(usize, 3), second.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.misses);
    try std.testing.expectEqual(fallback_misses_after_first, fallback_cache.misses);
    try std.testing.expectEqual(metrics_misses_after_first, metrics_cache.misses);
    try std.testing.expectApproxEqAbs(first.width(), second.width(), 0.001);
    try std.testing.expectEqual(first.runs.len, second.runs.len);
    try std.testing.expectEqual(first.glyphs[0].glyph_id, second.glyphs[0].glyph_id);

    shaped_cache.clear();
    try std.testing.expectEqual(@as(usize, 0), shaped_cache.entries.items.len);
    try std.testing.expectEqual(@as(usize, 0), shaped_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), shaped_cache.misses);
}
