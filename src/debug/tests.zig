//! Integrated debug dump and overlay coverage.

const std = @import("std");
const dumps = @import("dumps.zig");
const overlay_mod = @import("overlays.zig");
const font_mod = @import("../font.zig");
const layout_cache = @import("../shaping/context/cache/root.zig");
const context_output = @import("../shaping/context/output.zig");
const font_fallback = @import("../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../shaping/orchestrator.zig");
const shaping_plan = @import("../shaping/plan/root.zig");
const test_font = @import("../test_font.zig");
const unicode = @import("../unicode.zig");

const buildDebugOverlays = overlay_mod.buildDebugOverlays;
const dumpBidiMap = dumps.dumpBidiMap;
const dumpBidiRuns = dumps.dumpBidiRuns;
const dumpDebugOverlays = dumps.dumpDebugOverlays;
const dumpFontCoverage = dumps.dumpFontCoverage;
const dumpFontFallback = dumps.dumpFontFallback;
const dumpFontFallbackCacheStats = dumps.dumpFontFallbackCacheStats;
const dumpGlyphClusters = dumps.dumpGlyphClusters;
const dumpGlyphIndexCacheStats = dumps.dumpGlyphIndexCacheStats;
const dumpGlyphMetricsCacheStats = dumps.dumpGlyphMetricsCacheStats;
const dumpHitTest = dumps.dumpHitTest;
const dumpLineBreaks = dumps.dumpLineBreaks;
const dumpMissingGlyphs = dumps.dumpMissingGlyphs;
const dumpParagraphLayout = dumps.dumpParagraphLayout;
const dumpSelectionRects = dumps.dumpSelectionRects;
const dumpShapePlanCacheStats = dumps.dumpShapePlanCacheStats;
const dumpShapedRunCacheStats = dumps.dumpShapedRunCacheStats;
const dumpShapeRuns = dumps.dumpShapeRuns;
const dumpUnicodeSegmentation = dumps.dumpUnicodeSegmentation;

test "debug dumps unicode bidi paragraph hit selection and cache stats" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try shaping_orchestrator.TextShaper.shapeUtf8Cascade(cascade, &layout_buffer, "A A", 20);
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var plan_cache = shaping_plan.ShapePlanCache.init(allocator);
    defer plan_cache.deinit();
    _ = try plan_cache.getOrPut(shaping_plan.ShapePlanKey.fromText("A", .{}));
    var shaped_cache = layout_cache.ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var fallback_cache = layout_cache.FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    _ = try fallback_cache.selectFont(cascade, 'A');
    _ = try fallback_cache.selectFont(cascade, 'A');
    var metrics_cache = layout_cache.GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();
    _ = try metrics_cache.horizontalMetrics(&font, 1);
    _ = try metrics_cache.horizontalMetrics(&font, 1);
    var glyph_index_cache = layout_cache.GlyphIndexCache.init(allocator);
    defer glyph_index_cache.deinit();
    _ = try glyph_index_cache.glyphIndex(&font, 'A');
    _ = try glyph_index_cache.glyphIndex(&font, 'A');

    var storage: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    try dumpUnicodeSegmentation(&writer, allocator, "A\u{0301} B");
    try dumpBidiRuns(&writer, allocator, "A ב", .ltr);
    var bidi_map = try unicode.buildBidiMap(allocator, "A ב", .ltr);
    defer bidi_map.deinit();
    try dumpBidiMap(&writer, bidi_map);
    try dumpLineBreaks(&writer, allocator, "A B\n一丁");
    try dumpFontFallback(&writer, cascade, "AZ");
    try dumpShapeRuns(&writer, shaped);
    try dumpGlyphClusters(&writer, paragraph.glyphs);
    try dumpParagraphLayout(&writer, paragraph);
    try dumpHitTest(&writer, paragraph, 5, 5);
    try dumpSelectionRects(&writer, allocator, paragraph, 0, 2);
    var overlay_list = try buildDebugOverlays(allocator, paragraph, .{
        .cursor = .{ .glyph_index = 1, .cluster = 1 },
        .selection_start_glyph = 0,
        .selection_end_glyph = 2,
        .bidi_text = "A ב",
    });
    defer overlay_list.deinit();
    try dumpDebugOverlays(&writer, overlay_list);
    try dumpMissingGlyphs(&writer, cascade, "Z");
    try dumpFontCoverage(&writer, &font, "AZ");
    try dumpShapePlanCacheStats(&writer, plan_cache);
    try dumpShapedRunCacheStats(&writer, shaped_cache);
    try dumpFontFallbackCacheStats(&writer, fallback_cache);
    try dumpGlyphIndexCacheStats(&writer, glyph_index_cache);
    try dumpGlyphMetricsCacheStats(&writer, metrics_cache);

    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "unicode.graphemes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi.runs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line_breaks") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_fallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shape.runs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_clusters") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, output, "paragraph mode=horizontal_tb size=") !=
            null,
    );
    try std.testing.expect(std.mem.indexOf(u8, output, "hit_test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "selection_rects") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "debug_overlays") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "baseline") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "cursor_rect") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "selection_rect") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi_run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "missing_glyphs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_coverage") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shape_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shaped_run_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_fallback_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_index_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_metrics_cache") != null);
}
