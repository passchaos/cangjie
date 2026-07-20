//! Cangjie is a small Zig font stack focused on SFNT based TTF/OTF files.
//!
//! The current implementation covers table directory parsing, core TrueType
//! metric tables, Unicode cmap lookup, simple glyph outlines, text layout, and
//! a CPU grayscale rasterizer. The public API leaves room for OpenType shaping
//! and CFF outline expansion without changing callers that load and render text.

const std = @import("std");

pub const Script = @import("unicode.zig").Script;
pub const ScriptRun = @import("unicode.zig").ScriptRun;
pub const BidiClass = @import("unicode.zig").BidiClass;
pub const BidiMap = @import("unicode.zig").BidiMap;
pub const BidiMapItem = @import("unicode.zig").BidiMapItem;
pub const BidiRun = @import("unicode.zig").BidiRun;
pub const AttributedText = @import("core.zig").AttributedText;
pub const AttributedRun = @import("core.zig").AttributedRun;
pub const AttributedRunLayout = @import("core.zig").AttributedRunLayout;
pub const AttributedGlyphRun = @import("core.zig").AttributedGlyphRun;
pub const AttributedGlyphRunLayout = @import("core.zig").AttributedGlyphRunLayout;
pub const ByteRange = @import("core.zig").ByteRange;
pub const CharRange = @import("core.zig").CharRange;
pub const ClusterRange = @import("core.zig").ClusterRange;
pub const CoreBaselineMetrics = @import("core.zig").CoreBaselineMetrics;
pub const FontWeight = @import("core.zig").FontWeight;
pub const FontId = @import("core.zig").FontId;
pub const GraphemeRange = @import("core.zig").GraphemeRange;
pub const GraphemeCluster = @import("unicode.zig").GraphemeCluster;
pub const GlyphCluster = @import("core.zig").GlyphCluster;
pub const GlyphRange = @import("core.zig").GlyphRange;
pub const Language = @import("core.zig").Language;
pub const Locale = @import("core.zig").Locale;
pub const WordSegment = @import("unicode.zig").WordSegment;
pub const SentenceSegment = @import("unicode.zig").SentenceSegment;
pub const LineBreak = @import("unicode.zig").LineBreak;
pub const LineBreakKind = @import("unicode.zig").LineBreakKind;
pub const OverflowMode = @import("core.zig").OverflowMode;
pub const FeatureOverride = @import("unicode.zig").FeatureOverride;
pub const ParagraphStyle = @import("core.zig").ParagraphStyle;
pub const StyleSpan = @import("core.zig").StyleSpan;
pub const TextDecoration = @import("core.zig").TextDecoration;
pub const TextFontStyle = @import("core.zig").TextFontStyle;
pub const TextMetrics = @import("core.zig").TextMetrics;
pub const TextRange = @import("core.zig").TextRange;
pub const TextSpan = @import("core.zig").TextSpan;
pub const TextStyle = @import("core.zig").TextStyle;
pub const VerticalAlign = @import("core.zig").VerticalAlign;
pub const WrapMode = @import("core.zig").WrapMode;
pub const OpenTypeLanguageTag = @import("unicode.zig").OpenTypeLanguageTag;
pub const OpenTypeScriptTag = @import("unicode.zig").OpenTypeScriptTag;
pub const FontDatabase = @import("database.zig").FontDatabase;
pub const FontFaceInfo = @import("database.zig").FontFaceInfo;
pub const FontManifestEntry = @import("database.zig").FontManifestEntry;
pub const FontQuery = @import("database.zig").FontQuery;
pub const FontSource = @import("database.zig").FontSource;
pub const FontStyle = @import("database.zig").FontStyle;
pub const ImeComposition = @import("editor.zig").ImeComposition;
pub const LineColumn = @import("editor.zig").LineColumn;
pub const DebugOverlay = @import("debug.zig").DebugOverlay;
pub const DebugOverlayList = @import("debug.zig").DebugOverlayList;
pub const EditRecord = @import("editor.zig").EditRecord;
pub const DisplayWidthMode = @import("editor.zig").DisplayWidthMode;
pub const MultiCursorSet = @import("editor.zig").MultiCursorSet;
pub const OverlayKind = @import("debug.zig").OverlayKind;
pub const OverlayOptions = @import("debug.zig").OverlayOptions;
pub const SyntaxHighlightSet = @import("editor.zig").SyntaxHighlightSet;
pub const SyntaxHighlightSpan = @import("editor.zig").SyntaxHighlightSpan;
pub const SyntaxHighlightPalette = @import("editor.zig").SyntaxHighlightPalette;
pub const TerminalColumnOptions = @import("editor.zig").TerminalColumnOptions;
pub const combinedSystemFontSourcesForOs = @import("database.zig").combinedSystemFontSourcesForOs;
pub const defaultSystemFontSources = @import("database.zig").defaultSystemFontSources;
pub const defaultSystemFontSourcesForOs = @import("database.zig").defaultSystemFontSourcesForOs;
pub const manifestEntryMatchesBytes = @import("database.zig").manifestEntryMatchesBytes;
pub const measureAttributedRunsUtf8 = @import("core.zig").measureAttributedRunsUtf8;
pub const measureAttributedTextUtf8 = @import("core.zig").measureAttributedTextUtf8;
pub const parseManifest = @import("database.zig").parseManifest;
pub const readManifestFile = @import("database.zig").readManifestFile;
pub const serializeManifest = @import("database.zig").serializeManifest;
pub const userFontSourcesForOs = @import("database.zig").userFontSourcesForOs;
pub const writeManifestFile = @import("database.zig").writeManifestFile;
pub const Font = @import("font.zig").Font;
pub const FontError = @import("font.zig").FontError;
pub const FontFormat = @import("font.zig").FontFormat;
pub const GlyphClass = @import("font.zig").GlyphClass;
pub const NameId = @import("font.zig").NameId;
pub const FontFallbackCache = @import("layout.zig").FontFallbackCache;
pub const GlyphIndexCache = @import("layout.zig").GlyphIndexCache;
pub const GlyphMetrics = @import("layout.zig").GlyphMetrics;
pub const GlyphMetricsCache = @import("layout.zig").GlyphMetricsCache;
pub const DirtyRange = @import("buffer.zig").DirtyRange;
pub const LayoutConfig = @import("buffer.zig").LayoutConfig;
pub const Selection = @import("buffer.zig").Selection;
pub const CursorMoveDirection = @import("buffer.zig").CursorMoveDirection;
pub const VisibleByteRange = @import("buffer.zig").VisibleByteRange;
pub const VisibleLineRange = @import("buffer.zig").VisibleLineRange;
pub const TextBuffer = @import("buffer.zig").TextBuffer;
pub const TextEditor = @import("editor.zig").TextEditor;
pub const ColorLayer = @import("font.zig").ColorLayer;
pub const ColorPaint = @import("font.zig").ColorPaint;
pub const ColorGlyphPaint = @import("render_bridge.zig").ColorGlyphPaint;
pub const PaletteColor = @import("font.zig").PaletteColor;
pub const SvgGlyphDocument = @import("font.zig").SvgGlyphDocument;
pub const StatDesignAxis = @import("font.zig").StatDesignAxis;
pub const VariationAxis = @import("font.zig").VariationAxis;
pub const VariationCoordinate = @import("font.zig").VariationCoordinate;
pub const VerticalMetrics = @import("font.zig").VerticalMetrics;
pub const GlyphId = @import("glyph.zig").GlyphId;
pub const GlyphOutline = @import("glyph.zig").GlyphOutline;
pub const OutlineBuilder = @import("glyph.zig").OutlineBuilder;
pub const BaselineMetrics = @import("layout.zig").BaselineMetrics;
pub const LayoutBuffer = @import("layout.zig").LayoutBuffer;
pub const GlyphRun = @import("layout.zig").GlyphRun;
pub const GlyphPosition = @import("layout.zig").GlyphPosition;
pub const BridgeOptions = @import("render_bridge.zig").BridgeOptions;
pub const ColorGlyphDrawCommand = @import("render_bridge.zig").ColorGlyphDrawCommand;
pub const ColorGlyphLayerCommand = @import("render_bridge.zig").ColorGlyphLayerCommand;
pub const ClipboardPayload = @import("editor.zig").ClipboardPayload;
pub const CascadeRun = @import("layout.zig").CascadeRun;
pub const FontCascade = @import("layout.zig").FontCascade;
pub const GlyphAtlasCacheKey = @import("render_bridge.zig").GlyphAtlasCacheKey;
pub const GlyphAtlasRequest = @import("render_bridge.zig").GlyphAtlasRequest;
pub const GlyphDrawList = @import("render_bridge.zig").GlyphDrawList;
pub const GlyphPathCacheKey = @import("render_bridge.zig").GlyphPathCacheKey;
pub const GlyphPathRequest = @import("render_bridge.zig").GlyphPathRequest;
pub const GlyphPathSource = @import("render_bridge.zig").GlyphPathSource;
pub const GlyphRenderMode = @import("render_bridge.zig").GlyphRenderMode;
pub const GlyphRunDrawCommand = @import("render_bridge.zig").GlyphRunDrawCommand;
pub const ParagraphLayout = @import("layout.zig").ParagraphLayout;
pub const ParagraphLine = @import("layout.zig").ParagraphLine;
pub const ParagraphOptions = @import("layout.zig").ParagraphOptions;
pub const PositionedGlyph = @import("render_bridge.zig").PositionedGlyph;
pub const PositionedAttributedRun = @import("core.zig").PositionedAttributedRun;
pub const ShapeOptions = @import("layout.zig").ShapeOptions;
pub const ShapePlan = @import("layout.zig").ShapePlan;
pub const ShapePlanCache = @import("layout.zig").ShapePlanCache;
pub const ShapePlanKey = @import("layout.zig").ShapePlanKey;
pub const ShapedRunCache = @import("layout.zig").ShapedRunCache;
pub const ShapedRunCacheEntry = @import("layout.zig").ShapedRunCacheEntry;
pub const ShapedRunCacheKey = @import("layout.zig").ShapedRunCacheKey;
pub const ShapedText = @import("layout.zig").ShapedText;
pub const ScriptedRun = @import("layout.zig").ScriptedRun;
pub const ScriptedText = @import("layout.zig").ScriptedText;
pub const TextAlign = @import("layout.zig").TextAlign;
pub const TextCursorGeometry = @import("render_bridge.zig").TextCursorGeometry;
pub const TextDirection = @import("layout.zig").TextDirection;
pub const TextPosition = @import("layout.zig").TextPosition;
pub const TextRect = @import("layout.zig").TextRect;
pub const TextSelectionGeometry = @import("render_bridge.zig").TextSelectionGeometry;
pub const TextShaper = @import("layout.zig").TextShaper;
pub const buildBidiMap = @import("unicode.zig").buildBidiMap;
pub const buildDebugOverlays = @import("debug.zig").buildDebugOverlays;
pub const buildGlyphDrawList = @import("render_bridge.zig").buildGlyphDrawList;
pub const codepointDisplayWidth = @import("editor.zig").codepointDisplayWidth;
pub const highlightZigSyntax = @import("editor.zig").highlightZigSyntax;
pub const dumpBidiMap = @import("debug.zig").dumpBidiMap;
pub const dumpBidiRuns = @import("debug.zig").dumpBidiRuns;
pub const dumpDebugOverlays = @import("debug.zig").dumpDebugOverlays;
pub const dumpFontFallbackCacheStats = @import("debug.zig").dumpFontFallbackCacheStats;
pub const dumpFontCoverage = @import("debug.zig").dumpFontCoverage;
pub const dumpFontFallback = @import("debug.zig").dumpFontFallback;
pub const dumpGlyphClusters = @import("debug.zig").dumpGlyphClusters;
pub const dumpGlyphIndexCacheStats = @import("debug.zig").dumpGlyphIndexCacheStats;
pub const dumpGlyphMetricsCacheStats = @import("debug.zig").dumpGlyphMetricsCacheStats;
pub const dumpHitTest = @import("debug.zig").dumpHitTest;
pub const dumpLineBreaks = @import("debug.zig").dumpLineBreaks;
pub const dumpMissingGlyphs = @import("debug.zig").dumpMissingGlyphs;
pub const dumpParagraphLayout = @import("debug.zig").dumpParagraphLayout;
pub const dumpSelectionRects = @import("debug.zig").dumpSelectionRects;
pub const dumpShapePlanCacheStats = @import("debug.zig").dumpShapePlanCacheStats;
pub const dumpShapedRunCacheStats = @import("debug.zig").dumpShapedRunCacheStats;
pub const dumpShapeRuns = @import("debug.zig").dumpShapeRuns;
pub const dumpTextBufferLayoutStats = @import("debug.zig").dumpTextBufferLayoutStats;
pub const dumpUnicodeSegmentation = @import("debug.zig").dumpUnicodeSegmentation;
pub const inferOpenTypeLanguageTag = @import("unicode.zig").inferOpenTypeLanguageTag;
pub const itemizeBidiRuns = @import("unicode.zig").itemizeBidiRuns;
pub const itemizeGraphemeClusters = @import("unicode.zig").itemizeGraphemeClusters;
pub const itemizeLineBreaks = @import("unicode.zig").itemizeLineBreaks;
pub const itemizeSentenceSegments = @import("unicode.zig").itemizeSentenceSegments;
pub const itemizeScriptRuns = @import("unicode.zig").itemizeScriptRuns;
pub const itemizeWordSegments = @import("unicode.zig").itemizeWordSegments;
pub const layoutAttributedRunsUtf8 = @import("core.zig").layoutAttributedRunsUtf8;
pub const layoutAttributedGlyphRunsUtf8 = @import("core.zig").layoutAttributedGlyphRunsUtf8;
pub const openTypeTag = @import("unicode.zig").tag;
pub const openTypeScriptTag = @import("unicode.zig").openTypeScriptTag;
pub const scriptForCodepoint = @import("unicode.zig").scriptForCodepoint;
pub const mirroredCodepoint = @import("unicode.zig").mirroredCodepoint;
pub const visualOrderBidiRuns = @import("unicode.zig").visualOrderBidiRuns;
pub const visualOrderCodepoints = @import("unicode.zig").visualOrderCodepoints;
pub const visualOrderUtf8 = @import("unicode.zig").visualOrderUtf8;
pub const ColorRenderTarget = @import("raster.zig").ColorRenderTarget;
pub const RenderTarget = @import("raster.zig").RenderTarget;
pub const Rgba = @import("raster.zig").Rgba;
pub const Rasterizer = @import("raster.zig").Rasterizer;
pub const bidiClassForCodepoint = @import("unicode.zig").bidiClassForCodepoint;
pub const testing = struct {
    pub const test_font = @import("test_font.zig");
};

test "loads a minimal TTF, maps Unicode, reads outline, lays out, and rasterizes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.truetype, font.format);
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));

    var outline = try font.glyphOutline(allocator, 1);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(u16, 800), outline.advance_width);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), run.width(), 0.001);

    const kerned = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), kerned.width(), 0.001);

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

test "parses CBDT CBLC PNG bitmap glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyph_id = try font.glyphIndex('A');
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 16), bitmap.ppem);
    try std.testing.expectEqual(@as(i16, 2), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bitmap.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);
    try std.testing.expect(std.mem.eql(u8, bitmap.data[1..4], "PNG"));
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(18));
}

test "maps many-to-one cmap format 13 last-resort ranges" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x4e00));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x1f600));
}

test "maps trimmed cmap format 6 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildTrimmedCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex('C'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('D'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f600));
}

test "maps byte-encoding cmap format 0 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0xff));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x100));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f600));
}

test "maps mixed byte cmap format 2 subheaders" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMixedEncodingCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x0102));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x0101));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x0202));
}

test "maps trimmed 32-bit cmap format 10 glyph arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f5ff));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex(0x1f600));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f601));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndex(0x1f602));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndex(0x1f603));
}

test "maps cmap format 14 variation selector records" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndex('B'));
    try std.testing.expectEqual(@as(?GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));
    try std.testing.expectEqual(@as(GlyphId, 3), try font.glyphIndexWithVariation('A', 0xfe0f));
    try std.testing.expectEqual(@as(?GlyphId, 2), try font.variationGlyphIndex('B', 0xfe0f));
    try std.testing.expectEqual(@as(GlyphId, 2), try font.glyphIndexWithVariation('B', 0xfe0f));
    try std.testing.expectEqual(@as(?GlyphId, null), try font.variationGlyphIndex('A', 0xfe0e));
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithVariation('A', 0xfe0e));
}

test "shapes cmap format 14 variation selectors as base glyph variants" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A\u{fe0f}B", 20);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 'A'), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(u21, 'B'), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 4), run.glyphs[1].cluster);
}

test "shaping rejects malformed UTF-8 without clearing existing glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);
    try std.testing.expectError(error.InvalidUtf8, TextShaper.shapeUtf8(&font, &layout_buffer, "\xf0\x28\x8c\x28", 20));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);
}

test "public shaping APIs reject invalid font sizes before mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), valid.width(), 0.001);

    // Invalid sizes would otherwise become NaN/Inf/negative advances and cache
    // keys. Public entry points reject them before clearing the caller's last
    // good layout or touching fallback/shaped-run caches.
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", 0));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", std.math.inf(f32)));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", std.math.nan(f32)));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);

    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", -1, .{}));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "A", 0, .{}));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", -20, .{ .max_width = 100 }));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "A", std.math.inf(f32), .{ .max_width = 100 }));
}

test "public shaping APIs reject malformed feature overrides before mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);

    const invalid_feature = [_]FeatureOverride{.{ .tag = 0x6c696700, .enabled = true }};
    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &invalid_feature }));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);

    const duplicate_features = [_]FeatureOverride{
        .{ .tag = openTypeTag("liga"), .enabled = true },
        .{ .tag = openTypeTag("liga"), .enabled = false },
    };
    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;
    try std.testing.expectError(error.DuplicateFeatureTag, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .features = &duplicate_features }));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "A", 20, .{ .features = &invalid_feature }));
}

test "paragraph layout rejects non-finite options before shaping mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .max_width = 100 });
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);

    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;

    // These geometry knobs are applied after shaping. Validate them first so a
    // rejected paragraph call cannot clear the previous layout or populate
    // caches with text that never produced valid line metrics.
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "AA", 20, .{
        .max_width = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .letter_spacing = std.math.inf(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .word_spacing = -std.math.inf(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .first_line_indent = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\nA", 20, .{
        .max_width = 100,
        .paragraph_spacing = std.math.inf(f32),
    }));

    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.lines.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    // Infinite max_width remains a valid way to request unbounded paragraph
    // layout; only NaN/non-finite secondary geometry is rejected.
    _ = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{ .max_width = std.math.inf(f32) });
}

test "cascade and paragraph shaping reject malformed UTF-8 before cache mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const shaped = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{});
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs.len);
    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;

    // Public UTF-8 APIs must reject malformed bytes before std.unicode.Utf8Iterator
    // can hit its unreachable path, and before malformed text enters caches.
    try std.testing.expectError(error.InvalidUtf8, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "\xc3\x28", 20, .{}));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);
    try std.testing.expectError(error.InvalidUtf8, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "\xe2\x82", 20, .{ .max_width = 100 }));
    try std.testing.expectError(error.InvalidUtf8, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "\x80", 20, .{ .max_width = 100 }));
}

test "cascade shaping keeps variation selectors with fallback base font" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'C', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A\u{fe0f}C", 20);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), shaped.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(GlyphId, 1), shaped.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs[1].cluster);
}

test "cascade fallback prefers fonts with variation selector records" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const variant_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(variant_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var variant = try Font.parse(allocator, variant_bytes);
    defer variant.deinit();

    const fonts = [_]*const Font{ &primary, &variant };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const base = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), base.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), base.runs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 1), base.glyphs[0].glyph_id);

    const varied = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A\u{fe0f}", 20);
    try std.testing.expectEqual(@as(usize, 1), varied.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), varied.runs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 3), varied.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), varied.glyphs[0].cluster);
}

test "detects scripts and itemizes script runs" {
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(Script.latin, scriptForCodepoint('A'));
    try std.testing.expectEqual(Script.han, scriptForCodepoint(0x4e00));
    try std.testing.expectEqual(Script.arabic, scriptForCodepoint(0x0628));
    try std.testing.expectEqual(Script.inherited, scriptForCodepoint(0x0301));
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(.latin));
    try std.testing.expectEqual(OpenTypeScriptTag.hani, openTypeScriptTag(.han));
    try std.testing.expectEqual(OpenTypeScriptTag.arab, openTypeScriptTag(.arabic));
    try std.testing.expectEqual(OpenTypeScriptTag.dflt, openTypeScriptTag(.common));
    try std.testing.expectEqual(@intFromEnum(OpenTypeLanguageTag.jan), openTypeTag("JAN "));
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, inferOpenTypeLanguageTag("日本語かな"));
    try std.testing.expectEqual(OpenTypeLanguageTag.zhs, inferOpenTypeLanguageTag("一丁"));
    try std.testing.expectEqual(OpenTypeLanguageTag.kor, inferOpenTypeLanguageTag("한글"));
    try std.testing.expectEqual(OpenTypeLanguageTag.ara, inferOpenTypeLanguageTag("ب"));

    const runs = try itemizeScriptRuns(allocator, "ab 12一丁،ب");
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 3), runs.len);
    try std.testing.expectEqual(Script.latin, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 5), runs[0].byte_len);
    try std.testing.expectEqual(Script.han, runs[1].script);
    try std.testing.expectEqual(@as(usize, 5), runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 6), runs[1].byte_len);
    try std.testing.expectEqual(Script.arabic, runs[2].script);
    try std.testing.expectEqual(@as(usize, 11), runs[2].byte_start);

    const combining_runs = try itemizeScriptRuns(allocator, "a\u{0301}ب");
    defer allocator.free(combining_runs);
    try std.testing.expectEqual(@as(usize, 2), combining_runs.len);
    try std.testing.expectEqual(Script.latin, combining_runs[0].script);
    try std.testing.expectEqual(@as(usize, 3), combining_runs[0].byte_len);
    try std.testing.expectEqual(Script.arabic, combining_runs[1].script);

    const leading_common = try itemizeScriptRuns(allocator, "  (ab)");
    defer allocator.free(leading_common);
    try std.testing.expectEqual(@as(usize, 1), leading_common.len);
    try std.testing.expectEqual(Script.latin, leading_common[0].script);
    try std.testing.expectEqual(@as(usize, 0), leading_common[0].byte_start);
    try std.testing.expectEqual(@as(usize, 6), leading_common[0].byte_len);

    const leading_inherited = try itemizeScriptRuns(allocator, "\u{0301}ب");
    defer allocator.free(leading_inherited);
    try std.testing.expectEqual(@as(usize, 1), leading_inherited.len);
    try std.testing.expectEqual(Script.arabic, leading_inherited[0].script);
    try std.testing.expectEqual(@as(usize, 0), leading_inherited[0].byte_start);
}

test "detects bidi classes and itemizes bidi runs" {
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint('A'));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x0628));
    try std.testing.expectEqual(BidiClass.neutral, bidiClassForCodepoint(' '));

    const runs = try itemizeBidiRuns(allocator, "abc بجد xyz", .ltr);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 3), runs.len);
    try std.testing.expectEqual(BidiClass.ltr, runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), runs[0].byte_len);
    try std.testing.expectEqual(BidiClass.rtl, runs[1].direction);
    try std.testing.expectEqual(@as(usize, 3), runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 7), runs[1].byte_len);
    try std.testing.expectEqual(BidiClass.ltr, runs[2].direction);
    try std.testing.expectEqual(@as(usize, 10), runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 4), runs[2].byte_len);

    const ltr_order = try visualOrderBidiRuns(allocator, runs, .ltr);
    defer allocator.free(ltr_order);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, ltr_order);
    const rtl_order = try visualOrderBidiRuns(allocator, runs, .rtl);
    defer allocator.free(rtl_order);
    try std.testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, rtl_order);

    const ltr_visual = try visualOrderCodepoints(allocator, "abבגcd", .ltr);
    defer allocator.free(ltr_visual);
    try std.testing.expectEqualSlices(u21, &.{ 'a', 'b', 0x05d2, 0x05d1, 'c', 'd' }, ltr_visual);
    const rtl_visual = try visualOrderCodepoints(allocator, "abבגcd", .rtl);
    defer allocator.free(rtl_visual);
    try std.testing.expectEqualSlices(u21, &.{ 'c', 'd', 0x05d2, 0x05d1, 'a', 'b' }, rtl_visual);
    try std.testing.expectEqual(@as(u21, ')'), mirroredCodepoint('('));
    try std.testing.expectEqual(@as(u21, '('), mirroredCodepoint(')'));
    const mirrored_visual = try visualOrderCodepoints(allocator, "(אב)", .rtl);
    defer allocator.free(mirrored_visual);
    try std.testing.expectEqualSlices(u21, &.{ '(', 0x05d1, 0x05d0, ')' }, mirrored_visual);
    const mirrored_utf8 = try visualOrderUtf8(allocator, "(אב)", .rtl);
    defer allocator.free(mirrored_utf8);
    try std.testing.expectEqualStrings("(בא)", mirrored_utf8);

    const variation_visual = try visualOrderCodepoints(allocator, "א\u{fe0f}ב", .rtl);
    defer allocator.free(variation_visual);
    try std.testing.expectEqualSlices(u21, &.{ 0x05d1, 0x05d0, 0xfe0f }, variation_visual);

    const neutral_prefix = try itemizeBidiRuns(allocator, "  ב", .rtl);
    defer allocator.free(neutral_prefix);
    try std.testing.expectEqual(@as(usize, 1), neutral_prefix.len);
    try std.testing.expectEqual(BidiClass.rtl, neutral_prefix[0].direction);
    try std.testing.expectEqual(@as(usize, 0), neutral_prefix[0].byte_start);
}

test "builds bidi logical visual maps" {
    const allocator = std.testing.allocator;

    var ltr_map = try buildBidiMap(allocator, "abבגcd", .ltr);
    defer ltr_map.deinit();

    try std.testing.expectEqual(@as(usize, 6), ltr_map.items.len);
    try std.testing.expectEqual(@as(usize, 0), ltr_map.logicalToVisual(0).?);
    try std.testing.expectEqual(@as(usize, 1), ltr_map.logicalToVisual(1).?);
    try std.testing.expectEqual(@as(usize, 3), ltr_map.logicalToVisual(2).?);
    try std.testing.expectEqual(@as(usize, 2), ltr_map.logicalToVisual(3).?);
    try std.testing.expectEqual(@as(usize, 4), ltr_map.logicalToVisual(4).?);
    try std.testing.expectEqual(@as(usize, 5), ltr_map.logicalToVisual(5).?);
    try std.testing.expectEqual(@as(usize, 3), ltr_map.visualToLogical(2).?);
    try std.testing.expectEqual(@as(u21, 0x05d2), ltr_map.items[2].visual_codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d1), ltr_map.items[3].visual_codepoint);
    try std.testing.expectEqual(BidiClass.rtl, ltr_map.items[2].direction);

    var variation_map = try buildBidiMap(allocator, "א\u{fe0f}ב", .rtl);
    defer variation_map.deinit();
    try std.testing.expectEqual(@as(usize, 3), variation_map.items.len);
    try std.testing.expectEqual(@as(u21, 0x05d1), variation_map.items[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), variation_map.items[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0xfe0f), variation_map.items[2].codepoint);
    try std.testing.expectEqual(@as(usize, 1), variation_map.logicalToVisual(0).?);
    try std.testing.expectEqual(@as(usize, 2), variation_map.logicalToVisual(1).?);
    try std.testing.expectEqual(@as(usize, 0), variation_map.logicalToVisual(2).?);

    var rtl_map = try buildBidiMap(allocator, "abבגcd", .rtl);
    defer rtl_map.deinit();

    try std.testing.expectEqual(@as(usize, 4), rtl_map.visualToLogical(0).?);
    try std.testing.expectEqual(@as(usize, 5), rtl_map.visualToLogical(1).?);
    try std.testing.expectEqual(@as(usize, 3), rtl_map.visualToLogical(2).?);
    try std.testing.expectEqual(@as(usize, 2), rtl_map.visualToLogical(3).?);
    try std.testing.expectEqual(@as(usize, 0), rtl_map.visualToLogical(4).?);
    try std.testing.expectEqual(@as(usize, 1), rtl_map.visualToLogical(5).?);
    try std.testing.expectEqual(@as(usize, 4), rtl_map.logicalToVisual(0).?);
    try std.testing.expectEqual(@as(usize, 3), rtl_map.logicalToVisual(2).?);
    try std.testing.expectEqual(@as(usize, 0), rtl_map.logicalToVisual(4).?);

    var mirrored = try buildBidiMap(allocator, "(אב)", .rtl);
    defer mirrored.deinit();
    try std.testing.expectEqual(@as(u21, '('), mirrored.items[0].visual_codepoint);
    try std.testing.expectEqual(@as(u21, ')'), mirrored.items[3].visual_codepoint);
}

test "itemizes basic grapheme clusters" {
    const allocator = std.testing.allocator;

    const clusters = try itemizeGraphemeClusters(allocator, "a\u{0301}b\r\nc");
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqual(@as(usize, 0), clusters[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), clusters[0].byte_len);
    try std.testing.expectEqual(@as(usize, 3), clusters[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), clusters[1].byte_len);
    try std.testing.expectEqual(@as(usize, 4), clusters[2].byte_start);
    try std.testing.expectEqual(@as(usize, 2), clusters[2].byte_len);
    try std.testing.expectEqual(@as(usize, 6), clusters[3].byte_start);
    try std.testing.expectEqual(@as(usize, 1), clusters[3].byte_len);

    const leading_mark = try itemizeGraphemeClusters(allocator, "\u{0301}a");
    defer allocator.free(leading_mark);
    try std.testing.expectEqual(@as(usize, 2), leading_mark.len);
    try std.testing.expectEqual(@as(usize, 0), leading_mark[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), leading_mark[0].byte_len);
}

test "grapheme clusters keep emoji tag sequences atomic" {
    const allocator = std.testing.allocator;

    const england = try itemizeGraphemeClusters(allocator, "🏴\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}!");
    defer allocator.free(england);
    try std.testing.expectEqual(@as(usize, 2), england.len);
    try std.testing.expectEqualStrings("🏴\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}", "🏴\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}!"[england[0].byte_start..][0..england[0].byte_len]);
    try std.testing.expectEqualStrings("!", "🏴\u{e0067}\u{e0062}\u{e0065}\u{e006e}\u{e0067}\u{e007f}!"[england[1].byte_start..][0..england[1].byte_len]);

    const dangling_tag = try itemizeGraphemeClusters(allocator, "a\u{e0067}b");
    defer allocator.free(dangling_tag);
    try std.testing.expectEqual(@as(usize, 2), dangling_tag.len);
    try std.testing.expectEqualStrings("a\u{e0067}", "a\u{e0067}b"[dangling_tag[0].byte_start..][0..dangling_tag[0].byte_len]);
    try std.testing.expectEqualStrings("b", "a\u{e0067}b"[dangling_tag[1].byte_start..][0..dangling_tag[1].byte_len]);
}

test "itemizes emoji regional indicator and spacing-mark grapheme clusters" {
    const allocator = std.testing.allocator;

    const emoji_zwj = try itemizeGraphemeClusters(allocator, "👩‍💻!");
    defer allocator.free(emoji_zwj);
    try std.testing.expectEqual(@as(usize, 2), emoji_zwj.len);
    try std.testing.expectEqual(@as(usize, 0), emoji_zwj[0].byte_start);
    try std.testing.expectEqual(@as(usize, 11), emoji_zwj[0].byte_len);
    try std.testing.expectEqual(@as(usize, 11), emoji_zwj[1].byte_start);

    const flags = try itemizeGraphemeClusters(allocator, "🇺🇸🇨🇦");
    defer allocator.free(flags);
    try std.testing.expectEqual(@as(usize, 2), flags.len);
    try std.testing.expectEqual(@as(usize, 0), flags[0].byte_start);
    try std.testing.expectEqual(@as(usize, 8), flags[0].byte_len);
    try std.testing.expectEqual(@as(usize, 8), flags[1].byte_start);
    try std.testing.expectEqual(@as(usize, 8), flags[1].byte_len);

    const skin_tone = try itemizeGraphemeClusters(allocator, "👍🏽");
    defer allocator.free(skin_tone);
    try std.testing.expectEqual(@as(usize, 1), skin_tone.len);
    try std.testing.expectEqual(@as(usize, 8), skin_tone[0].byte_len);

    const spacing_mark = try itemizeGraphemeClusters(allocator, "का");
    defer allocator.free(spacing_mark);
    try std.testing.expectEqual(@as(usize, 1), spacing_mark.len);
    try std.testing.expectEqual(@as(usize, 6), spacing_mark[0].byte_len);
}

test "grapheme clusters retain supported-script combining marks and ZWNJ" {
    const allocator = std.testing.allocator;

    const arabic_fatha = try itemizeGraphemeClusters(allocator, "بَت");
    defer allocator.free(arabic_fatha);
    try std.testing.expectEqual(@as(usize, 2), arabic_fatha.len);
    try std.testing.expectEqualStrings("بَ", "بَت"[arabic_fatha[0].byte_start..][0..arabic_fatha[0].byte_len]);
    try std.testing.expectEqualStrings("ت", "بَت"[arabic_fatha[1].byte_start..][0..arabic_fatha[1].byte_len]);

    const hebrew_qamats = try itemizeGraphemeClusters(allocator, "שָל");
    defer allocator.free(hebrew_qamats);
    try std.testing.expectEqual(@as(usize, 2), hebrew_qamats.len);
    try std.testing.expectEqualStrings("שָ", "שָל"[hebrew_qamats[0].byte_start..][0..hebrew_qamats[0].byte_len]);
    try std.testing.expectEqualStrings("ל", "שָל"[hebrew_qamats[1].byte_start..][0..hebrew_qamats[1].byte_len]);

    const devanagari_zwnj = try itemizeGraphemeClusters(allocator, "क्\u{200c}ष");
    defer allocator.free(devanagari_zwnj);
    try std.testing.expectEqual(@as(usize, 2), devanagari_zwnj.len);
    try std.testing.expectEqualStrings("क्\u{200c}", "क्\u{200c}ष"[devanagari_zwnj[0].byte_start..][0..devanagari_zwnj[0].byte_len]);
    try std.testing.expectEqualStrings("ष", "क्\u{200c}ष"[devanagari_zwnj[1].byte_start..][0..devanagari_zwnj[1].byte_len]);
}

test "grapheme clusters only let ZWJ join extended pictographs" {
    const allocator = std.testing.allocator;

    const emoji_zwj = try itemizeGraphemeClusters(allocator, "👩\u{0301}‍💻!");
    defer allocator.free(emoji_zwj);
    try std.testing.expectEqual(@as(usize, 2), emoji_zwj.len);
    try std.testing.expectEqualStrings("👩\u{0301}‍💻", "👩\u{0301}‍💻!"[emoji_zwj[0].byte_start..][0..emoji_zwj[0].byte_len]);

    const generic_zwj = try itemizeGraphemeClusters(allocator, "a‍b");
    defer allocator.free(generic_zwj);
    try std.testing.expectEqual(@as(usize, 2), generic_zwj.len);
    try std.testing.expectEqualStrings("a‍", "a‍b"[generic_zwj[0].byte_start..][0..generic_zwj[0].byte_len]);
    try std.testing.expectEqualStrings("b", "a‍b"[generic_zwj[1].byte_start..][0..generic_zwj[1].byte_len]);
}

test "itemizes Hangul Jamo grapheme clusters" {
    const allocator = std.testing.allocator;

    const jamo = try itemizeGraphemeClusters(allocator, "\u{1100}\u{1161}\u{11a8}x");
    defer allocator.free(jamo);
    try std.testing.expectEqual(@as(usize, 2), jamo.len);
    try std.testing.expectEqual(@as(usize, 0), jamo[0].byte_start);
    try std.testing.expectEqual(@as(usize, 9), jamo[0].byte_len);
    try std.testing.expectEqual(@as(usize, 9), jamo[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), jamo[1].byte_len);

    const precomposed_lv = try itemizeGraphemeClusters(allocator, "\u{ac00}\u{11a8}");
    defer allocator.free(precomposed_lv);
    try std.testing.expectEqual(@as(usize, 1), precomposed_lv.len);
    try std.testing.expectEqual(@as(usize, 6), precomposed_lv[0].byte_len);

    const precomposed_lvt = try itemizeGraphemeClusters(allocator, "\u{ac01}\u{11a8}");
    defer allocator.free(precomposed_lvt);
    try std.testing.expectEqual(@as(usize, 1), precomposed_lvt.len);
    try std.testing.expectEqual(@as(usize, 6), precomposed_lvt[0].byte_len);
}

test "itemizes basic word segments" {
    const allocator = std.testing.allocator;

    const words = try itemizeWordSegments(allocator, "hello, world42 一丁 مرحبا");
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("hello", "hello, world42 一丁 مرحبا"[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("world42", "hello, world42 一丁 مرحبا"[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("一", "hello, world42 一丁 مرحبا"[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("丁", "hello, world42 一丁 مرحبا"[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("مرحبا", "hello, world42 一丁 مرحبا"[words[4].byte_start..][0..words[4].byte_len]);

    const apostrophe = try itemizeWordSegments(allocator, "can't stop");
    defer allocator.free(apostrophe);
    try std.testing.expectEqual(@as(usize, 2), apostrophe.len);
    try std.testing.expectEqualStrings("can't", "can't stop"[apostrophe[0].byte_start..][0..apostrophe[0].byte_len]);
}

test "word segments retain combining marks variation selectors and joiners" {
    const allocator = std.testing.allocator;

    const latin_combining = try itemizeWordSegments(allocator, "cafe\u{0301} stop");
    defer allocator.free(latin_combining);
    try std.testing.expectEqual(@as(usize, 2), latin_combining.len);
    try std.testing.expectEqualStrings("cafe\u{0301}", "cafe\u{0301} stop"[latin_combining[0].byte_start..][0..latin_combining[0].byte_len]);

    const ideographic_variation = try itemizeWordSegments(allocator, "\u{4e00}\u{e0100}丁");
    defer allocator.free(ideographic_variation);
    try std.testing.expectEqual(@as(usize, 2), ideographic_variation.len);
    try std.testing.expectEqualStrings("\u{4e00}\u{e0100}", "\u{4e00}\u{e0100}丁"[ideographic_variation[0].byte_start..][0..ideographic_variation[0].byte_len]);
    try std.testing.expectEqualStrings("丁", "\u{4e00}\u{e0100}丁"[ideographic_variation[1].byte_start..][0..ideographic_variation[1].byte_len]);

    const devanagari_joiner = try itemizeWordSegments(allocator, "क्\u{200d}ष ok");
    defer allocator.free(devanagari_joiner);
    try std.testing.expectEqual(@as(usize, 2), devanagari_joiner.len);
    try std.testing.expectEqualStrings("क्\u{200d}ष", "क्\u{200d}ष ok"[devanagari_joiner[0].byte_start..][0..devanagari_joiner[0].byte_len]);
}

test "grapheme clusters keep Unicode prepend controls with following base" {
    const allocator = std.testing.allocator;

    const clusters = try itemizeGraphemeClusters(allocator, "\u{0600}a b");
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("\u{0600}a", "\u{0600}a b"[clusters[0].byte_start..][0..clusters[0].byte_len]);
}

test "grapheme clusters keep controls atomic" {
    const allocator = std.testing.allocator;

    const before_mark = try itemizeGraphemeClusters(allocator, "a\n\u{0301}b");
    defer allocator.free(before_mark);
    try std.testing.expectEqual(@as(usize, 4), before_mark.len);
    try std.testing.expectEqualStrings("a", "a\n\u{0301}b"[before_mark[0].byte_start..][0..before_mark[0].byte_len]);
    try std.testing.expectEqualStrings("\n", "a\n\u{0301}b"[before_mark[1].byte_start..][0..before_mark[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0301}", "a\n\u{0301}b"[before_mark[2].byte_start..][0..before_mark[2].byte_len]);
    try std.testing.expectEqualStrings("b", "a\n\u{0301}b"[before_mark[3].byte_start..][0..before_mark[3].byte_len]);

    const before_zwj = try itemizeGraphemeClusters(allocator, "a\n\u{200d}b");
    defer allocator.free(before_zwj);
    try std.testing.expectEqual(@as(usize, 4), before_zwj.len);
    try std.testing.expectEqualStrings("\n", "a\n\u{200d}b"[before_zwj[1].byte_start..][0..before_zwj[1].byte_len]);
    try std.testing.expectEqualStrings("\u{200d}", "a\n\u{200d}b"[before_zwj[2].byte_start..][0..before_zwj[2].byte_len]);

    const after_control = try itemizeGraphemeClusters(allocator, "\u{0600}\na");
    defer allocator.free(after_control);
    try std.testing.expectEqual(@as(usize, 3), after_control.len);
    try std.testing.expectEqualStrings("\u{0600}", "\u{0600}\na"[after_control[0].byte_start..][0..after_control[0].byte_len]);
    try std.testing.expectEqualStrings("\n", "\u{0600}\na"[after_control[1].byte_start..][0..after_control[1].byte_len]);

    const crlf = try itemizeGraphemeClusters(allocator, "a\r\n\u{0301}");
    defer allocator.free(crlf);
    try std.testing.expectEqual(@as(usize, 3), crlf.len);
    try std.testing.expectEqualStrings("\r\n", "a\r\n\u{0301}"[crlf[1].byte_start..][0..crlf[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0301}", "a\r\n\u{0301}"[crlf[2].byte_start..][0..crlf[2].byte_len]);

    const format_control = try itemizeGraphemeClusters(allocator, "a\u{200e}\u{0301}b");
    defer allocator.free(format_control);
    try std.testing.expectEqual(@as(usize, 4), format_control.len);
    try std.testing.expectEqualStrings("a", "a\u{200e}\u{0301}b"[format_control[0].byte_start..][0..format_control[0].byte_len]);
    try std.testing.expectEqualStrings("\u{200e}", "a\u{200e}\u{0301}b"[format_control[1].byte_start..][0..format_control[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0301}", "a\u{200e}\u{0301}b"[format_control[2].byte_start..][0..format_control[2].byte_len]);
    try std.testing.expectEqualStrings("b", "a\u{200e}\u{0301}b"[format_control[3].byte_start..][0..format_control[3].byte_len]);

    const paragraph_separator = try itemizeGraphemeClusters(allocator, "x\u{2029}\u{0301}y");
    defer allocator.free(paragraph_separator);
    try std.testing.expectEqual(@as(usize, 4), paragraph_separator.len);
    try std.testing.expectEqualStrings("\u{2029}", "x\u{2029}\u{0301}y"[paragraph_separator[1].byte_start..][0..paragraph_separator[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0301}", "x\u{2029}\u{0301}y"[paragraph_separator[2].byte_start..][0..paragraph_separator[2].byte_len]);
}

test "word segments retain Unicode format controls" {
    const allocator = std.testing.allocator;

    const ltr_mark = try itemizeWordSegments(allocator, "ab\u{200e}cd ef");
    defer allocator.free(ltr_mark);
    try std.testing.expectEqual(@as(usize, 2), ltr_mark.len);
    try std.testing.expectEqualStrings("ab\u{200e}cd", "ab\u{200e}cd ef"[ltr_mark[0].byte_start..][0..ltr_mark[0].byte_len]);

    const word_joiner = try itemizeWordSegments(allocator, "hello\u{2060}world");
    defer allocator.free(word_joiner);
    try std.testing.expectEqual(@as(usize, 1), word_joiner.len);
    try std.testing.expectEqualStrings("hello\u{2060}world", "hello\u{2060}world"[word_joiner[0].byte_start..][0..word_joiner[0].byte_len]);
}

test "itemizes basic sentence segments" {
    const allocator = std.testing.allocator;
    const text = "Hello world!  Are you ok? 好。再见！";
    const sentences = try itemizeSentenceSegments(allocator, text);
    defer allocator.free(sentences);

    try std.testing.expectEqual(@as(usize, 4), sentences.len);
    try std.testing.expectEqualStrings("Hello world!  ", text[sentences[0].byte_start..][0..sentences[0].byte_len]);
    try std.testing.expectEqualStrings("Are you ok? ", text[sentences[1].byte_start..][0..sentences[1].byte_len]);
    try std.testing.expectEqualStrings("好。", text[sentences[2].byte_start..][0..sentences[2].byte_len]);
    try std.testing.expectEqualStrings("再见！", text[sentences[3].byte_start..][0..sentences[3].byte_len]);

    const no_terminal = try itemizeSentenceSegments(allocator, "No terminator");
    defer allocator.free(no_terminal);
    try std.testing.expectEqual(@as(usize, 1), no_terminal.len);
    try std.testing.expectEqualStrings("No terminator", "No terminator"[no_terminal[0].byte_start..][0..no_terminal[0].byte_len]);

    const quoted_text = "He said ‘hi!’ Next.";
    const quoted = try itemizeSentenceSegments(allocator, quoted_text);
    defer allocator.free(quoted);
    try std.testing.expectEqual(@as(usize, 2), quoted.len);
    try std.testing.expectEqualStrings("He said ‘hi!’ ", quoted_text[quoted[0].byte_start..][0..quoted[0].byte_len]);
    try std.testing.expectEqualStrings("Next.", quoted_text[quoted[1].byte_start..][0..quoted[1].byte_len]);
}

test "sentence segments keep decimal full stops inside numbers" {
    const allocator = std.testing.allocator;
    const text = "Version 1.2 works. Next.";

    const sentences = try itemizeSentenceSegments(allocator, text);
    defer allocator.free(sentences);

    try std.testing.expectEqual(@as(usize, 2), sentences.len);
    try std.testing.expectEqualStrings("Version 1.2 works. ", text[sentences[0].byte_start..][0..sentences[0].byte_len]);
    try std.testing.expectEqualStrings("Next.", text[sentences[1].byte_start..][0..sentences[1].byte_len]);
}

test "itemizes line break opportunities" {
    const allocator = std.testing.allocator;

    const breaks = try itemizeLineBreaks(allocator, "A B\n一丁");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 4), breaks.len);
    try std.testing.expectEqual(@as(usize, 2), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 4), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.hard, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 7), breaks[2].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[2].kind);
    try std.testing.expectEqual(@as(usize, 10), breaks[3].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[3].kind);

    const crlf = try itemizeLineBreaks(allocator, "A\r\nB");
    defer allocator.free(crlf);
    try std.testing.expectEqual(@as(usize, 1), crlf.len);
    try std.testing.expectEqual(@as(usize, 3), crlf[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.hard, crlf[0].kind);
}

test "line break opportunities stay on grapheme cluster boundaries" {
    const allocator = std.testing.allocator;
    const text = "\u{4e00}\u{e0100}丁";

    const breaks = try itemizeLineBreaks(allocator, text);
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 2), breaks.len);
    try std.testing.expectEqual(@as(usize, 7), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqualStrings("\u{4e00}\u{e0100}", text[0..breaks[0].byte_offset]);
    try std.testing.expectEqual(@as(usize, text.len), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[1].kind);
}

test "shapes mixed-script text with script run metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const feature_key = ShapePlanKey.fromText("abc", .{ .features = &disable_liga });
    const japanese_key = ShapePlanKey.fromText("一", .{ .language_tag = .jan });

    const first = try cache.getOrPut(latin_key);
    try std.testing.expectEqual(@as(usize, 1), first.hits);
    const second = try cache.getOrPut(latin_again);
    try std.testing.expectEqual(@as(usize, 2), second.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.plans.items.len);

    _ = try cache.getOrPut(rtl_key);
    _ = try cache.getOrPut(feature_key);
    _ = try cache.getOrPut(japanese_key);
    try std.testing.expectEqual(@as(usize, 4), cache.plans.items.len);
    try std.testing.expect(latin_key.feature_hash != feature_key.feature_hash);
    try std.testing.expect(japanese_key.language_tag == .jan);
}

test "loads the first face from a minimal TTC collection" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

test "reads variable font axis metadata from fvar" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
}

test "reads GDEF glyph classes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGsubIgnoreMarksTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    try glyphs.append(allocator, 2);
    try glyphs.append(allocator, 3);

    try font.applyGsub(&glyphs, allocator);

    try std.testing.expectEqual(@as(usize, 3), glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), glyphs.items[0]);
    try std.testing.expectEqual(@as(GlyphId, 2), glyphs.items[1]);
    try std.testing.expectEqual(@as(GlyphId, 3), glyphs.items[2]);
}

test "GPOS lookup flags ignore GDEF glyph classes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGposIgnoreMarksTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]GlyphId{ 1, 2, 3 };
    var adjustments = std.ArrayList(@import("gpos.zig").Adjustment).empty;
    defer adjustments.deinit(allocator);

    try font.collectGposAdjustments(&glyphs, &adjustments, allocator);

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "reads COLR layers and CPAL palette colors" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const layers = try font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 2), layers.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 0), layers[0].palette_index);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[1].glyph_id);
    try std.testing.expectEqual(@as(u16, 1), layers[1].palette_index);

    const red = (try font.paletteColor(0, layers[0].palette_index)).?;
    try std.testing.expectEqual(@as(u8, 255), red.red);
    try std.testing.expectEqual(@as(u8, 0), red.green);
    try std.testing.expectEqual(@as(u8, 0), red.blue);
    try std.testing.expectEqual(@as(u8, 255), red.alpha);

    const blue = (try font.paletteColor(0, layers[1].palette_index)).?;
    try std.testing.expectEqual(@as(u8, 0), blue.red);
    try std.testing.expectEqual(@as(u8, 0), blue.green);
    try std.testing.expectEqual(@as(u8, 255), blue.blue);
    try std.testing.expectEqual(@as(u8, 255), blue.alpha);
    try std.testing.expect(try font.paletteColor(1, 0) == null);

    const missing_layers = try font.colorLayers(allocator, 2);
    defer allocator.free(missing_layers);
    try std.testing.expectEqual(@as(usize, 0), missing_layers.len);
}

test "reads COLR v1 PaintSolid metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .solid => |solid| {
            try std.testing.expectEqual(@as(u16, 0), solid.palette_index);
            try std.testing.expectApproxEqAbs(@as(f32, 0.5), solid.alpha, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(try font.colorPaint(0) == null);
}

test "renders COLR v1 PaintSolid glyph into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    var translucent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.a < 255) translucent_pixels += 1;
    }

    try std.testing.expect(red_pixels > 10);
    try std.testing.expect(translucent_pixels > 0);
}

test "reads and renders COLR v1 PaintGlyph with nested PaintSolid" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1GlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| {
            try std.testing.expectEqual(@as(GlyphId, 1), glyph_paint.glyph_id);
            try std.testing.expectEqual(@as(u16, 0), glyph_paint.solid.palette_index);
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), glyph_paint.solid.alpha, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
    }
    try std.testing.expect(red_pixels > 10);
}

test "reads and renders COLR v1 PaintColrLayers" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1LayersTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .layers => |layers| {
            try std.testing.expectEqual(@as(u8, 2), layers.layer_count);
            try std.testing.expectEqual(@as(u32, 0), layers.first_layer_index);
        },
        else => return error.TestUnexpectedResult,
    }
    const first_layer = (try font.colorPaintLayer(0)).?;
    switch (first_layer) {
        .glyph => |glyph_paint| {
            try std.testing.expectEqual(@as(GlyphId, 1), glyph_paint.glyph_id);
            try std.testing.expectEqual(@as(u16, 0), glyph_paint.solid.palette_index);
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_channel_pixels: usize = 0;
    var blue_channel_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0) red_channel_pixels += 1;
        if (pixel.b > 0) blue_channel_pixels += 1;
    }
    try std.testing.expect(red_channel_pixels > 0);
    try std.testing.expect(blue_channel_pixels > 0);
}

test "rejects COLR v1 ClipList offsets that alias records" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1InvalidClipListTtf(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "rejects COLR v1 recursive paint payload aliasing" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1RecursivePaintAliasTtf(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "rejects COLR v1 indirect PaintColrGlyph cycles" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1IndirectPaintColrGlyphCycleTtf(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "reads OpenType SVG glyph document metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const document = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqual(@as(GlyphId, 1), document.start_glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), document.end_glyph_id);
    try std.testing.expect(std.mem.startsWith(u8, document.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, document.data, "<path") != null);

    const bytes_only = (try font.svgDocument(1)).?;
    try std.testing.expectEqualSlices(u8, document.data, bytes_only);
    try std.testing.expect(try font.svgGlyphDocument(0) == null);
}

test "renders OpenType SVG glyph document into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    var non_red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) {
            red_pixels += 1;
        } else {
            non_red_pixels += 1;
        }
    }
    try std.testing.expect(red_pixels > 20);
    try std.testing.expectEqual(@as(usize, 0), non_red_pixels);
}

test "renders OpenType SVG glyph with multiple curved paths" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgCurveTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 64, 64);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 40, 12, 52, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
    }
    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);
    try std.testing.expect(green_pixels > 20);
}

test "renders OpenType SVG rect circle and opacity paints" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgShapeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var green_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
        if (pixel.a < 255) translucent_pixels += 1;
    }
    try std.testing.expect(green_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_pixels > 20);
}

test "renders OpenType SVG transformed shapes at transformed positions" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(47, 17);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);

    const blue_sample = target.at(29, 46);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);

    const untransformed_red_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_red_origin.a);
}

test "renders OpenType SVG rotate transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgRotateTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const rotated_red = target.at(46, 36);
    try std.testing.expect(rotated_red.r > 0);
    try std.testing.expectEqual(@as(u8, 0), rotated_red.g);
    try std.testing.expectEqual(@as(u8, 0), rotated_red.b);

    const original_red_position = target.at(36, 22);
    try std.testing.expectEqual(@as(u8, 0), original_red_position.a);

    var blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
    }
    try std.testing.expect(blue_pixels > 10);
}

test "renders OpenType SVG skew transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgSkewTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const skewed_red = target.at(32, 26);
    try std.testing.expect(skewed_red.r > 0);
    try std.testing.expectEqual(@as(u8, 0), skewed_red.g);
    try std.testing.expectEqual(@as(u8, 0), skewed_red.b);

    const unskewed_red_top_right = target.at(18, 22);
    try std.testing.expectEqual(@as(u8, 0), unskewed_red_top_right.a);

    const skewed_blue = target.at(43, 52);
    try std.testing.expect(skewed_blue.b > 0);
    try std.testing.expectEqual(@as(u8, 0), skewed_blue.r);
    try std.testing.expectEqual(@as(u8, 0), skewed_blue.g);
}

test "renders OpenType SVG grouped inherited paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgGroupTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(31, 26);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(50, 24);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < 255);

    const untransformed_group_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_group_origin.a);
}

test "renders OpenType SVG nested grouped inherited paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgNestedGroupTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(27, 30);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(48, 28);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < 255);

    const untransformed_nested_origin = target.at(16, 14);
    try std.testing.expectEqual(@as(u8, 0), untransformed_nested_origin.a);
}

test "renders OpenType SVG style attributes for paints and transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgStyleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const red_sample = target.at(31, 26);
    try std.testing.expect(red_sample.r > 0);
    try std.testing.expectEqual(@as(u8, 0), red_sample.g);
    try std.testing.expectEqual(@as(u8, 0), red_sample.b);
    try std.testing.expect(red_sample.a < 255);

    const blue_sample = target.at(50, 24);
    try std.testing.expect(blue_sample.b > 0);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.r);
    try std.testing.expectEqual(@as(u8, 0), blue_sample.g);
    try std.testing.expect(blue_sample.a < red_sample.a);

    const untransformed_style_origin = target.at(20, 20);
    try std.testing.expectEqual(@as(u8, 0), untransformed_style_origin.a);

    const hidden_class = target.at(16, 51);
    try std.testing.expectEqual(@as(u8, 0), hidden_class.a);

    const id_style = target.at(44, 52);
    try std.testing.expect(id_style.g > 0);
    try std.testing.expectEqual(@as(u8, 0), id_style.r);
    try std.testing.expect(id_style.a > 0 and id_style.a < 255);

    const element_style = target.at(24, 54);
    try std.testing.expect(element_style.b > 0);
    try std.testing.expectEqual(@as(u8, 0), element_style.r);
    try std.testing.expect(element_style.a > 0 and element_style.a < 255);

    const current_color_fill = target.at(53, 53);
    try std.testing.expect(current_color_fill.b > 0);
    try std.testing.expectEqual(@as(u8, 0), current_color_fill.r);
    try std.testing.expect(current_color_fill.a > 0 and current_color_fill.a < 255);

    const current_color_stroke = target.at(53, 57);
    try std.testing.expect(current_color_stroke.b > 0);
    try std.testing.expectEqual(@as(u8, 0), current_color_stroke.r);
    try std.testing.expect(current_color_stroke.a > 0 and current_color_stroke.a < 255);

    const cyan_keyword = target.at(14, 14);
    try std.testing.expect(cyan_keyword.g > 0);
    try std.testing.expect(cyan_keyword.b > 0);
    try std.testing.expectEqual(@as(u8, 0), cyan_keyword.r);

    const yellow_keyword = target.at(18, 14);
    try std.testing.expect(yellow_keyword.r > 0);
    try std.testing.expect(yellow_keyword.g > 0);
    try std.testing.expectEqual(@as(u8, 0), yellow_keyword.b);

    const magenta_keyword = target.at(23, 14);
    try std.testing.expect(magenta_keyword.r > 0);
    try std.testing.expect(magenta_keyword.b > 0);
    try std.testing.expectEqual(@as(u8, 0), magenta_keyword.g);

    const transparent_keyword = target.at(28, 14);
    try std.testing.expectEqual(@as(u8, 0), transparent_keyword.a);
}

test "renders OpenType SVG rect and circle strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgStrokeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(green_pixels > 10);
    try std.testing.expect(translucent_blue_pixels > 20);

    const rect_center = target.at(27, 41);
    try std.testing.expectEqual(@as(u8, 0), rect_center.a);
}

test "renders OpenType SVG stroke line caps" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgLineCapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const butt_before_start = target.at(22, 23);
    try std.testing.expectEqual(@as(u8, 0), butt_before_start.a);

    const round_before_start = target.at(22, 35);
    try std.testing.expect(round_before_start.b > 0);
    try std.testing.expectEqual(@as(u8, 0), round_before_start.r);

    const square_before_start = target.at(22, 47);
    try std.testing.expect(square_before_start.g > 0);
    try std.testing.expectEqual(@as(u8, 0), square_before_start.r);
}

test "renders OpenType SVG dashed strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgDashTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const first_dash = target.at(19, 31);
    try std.testing.expect(first_dash.r > 0);
    try std.testing.expectEqual(@as(u8, 0), first_dash.b);

    const first_gap = target.at(24, 31);
    try std.testing.expectEqual(@as(u8, 0), first_gap.a);

    const second_dash = target.at(29, 31);
    try std.testing.expect(second_dash.r > 0);

    const odd_dash_polyline = target.at(19, 44);
    try std.testing.expect(odd_dash_polyline.b > 0);

    const odd_dash_gap = target.at(24, 44);
    try std.testing.expectEqual(@as(u8, 0), odd_dash_gap.a);
}

test "renders OpenType SVG dash offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgDashOffsetTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const offset_start_gap = target.at(19, 31);
    try std.testing.expectEqual(@as(u8, 0), offset_start_gap.a);

    const offset_first_dash = target.at(25, 31);
    try std.testing.expect(offset_first_dash.r > 0);
    try std.testing.expectEqual(@as(u8, 0), offset_first_dash.b);
}

test "renders OpenType SVG round stroke joins" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgLineJoinTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const default_join_outer_corner = target.at(32, 22);
    try std.testing.expectEqual(@as(u8, 0), default_join_outer_corner.a);

    const round_join_outer_corner = target.at(51, 22);
    try std.testing.expect(round_join_outer_corner.b > 0);
    try std.testing.expectEqual(@as(u8, 0), round_join_outer_corner.r);

    const bevel_join_outer_corner = target.at(29, 44);
    try std.testing.expect(bevel_join_outer_corner.g > 0);
    try std.testing.expectEqual(@as(u8, 0), bevel_join_outer_corner.r);

    const miterlimit_bevel_outer_corner = target.at(51, 44);
    try std.testing.expect(miterlimit_bevel_outer_corner.r > 0);
    try std.testing.expectEqual(@as(u8, 0), miterlimit_bevel_outer_corner.b);
}

test "renders OpenType SVG defs and use references" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgUseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const defs_origin = target.at(13, 13);
    try std.testing.expectEqual(@as(u8, 0), defs_origin.a);

    const used_rect = target.at(25, 25);
    try std.testing.expect(used_rect.r > 0);
    try std.testing.expectEqual(@as(u8, 0), used_rect.b);

    const used_circle = target.at(44, 38);
    try std.testing.expect(used_circle.b > 0);
    try std.testing.expectEqual(@as(u8, 0), used_circle.r);
    try std.testing.expect(used_circle.a < 255);

    const used_group_rect = target.at(21, 49);
    try std.testing.expect(used_group_rect.r > 0);
    try std.testing.expectEqual(@as(u8, 0), used_group_rect.b);

    const used_group_circle = target.at(29, 48);
    try std.testing.expect(used_group_circle.g > 0);
    try std.testing.expectEqual(@as(u8, 0), used_group_circle.r);
}

test "renders OpenType SVG rect clip paths" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgClipTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const inside_clip = target.at(24, 32);
    try std.testing.expect(inside_clip.r > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_clip.b);

    const outside_clip = target.at(62, 24);
    try std.testing.expectEqual(@as(u8, 0), outside_clip.a);

    const inside_circle_clip = target.at(47, 35);
    try std.testing.expect(inside_circle_clip.b > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_circle_clip.r);

    const outside_circle_clip = target.at(59, 35);
    try std.testing.expectEqual(@as(u8, 0), outside_circle_clip.a);

    const inside_path_clip = target.at(40, 49);
    try std.testing.expect(inside_path_clip.g > 0);
    try std.testing.expectEqual(@as(u8, 0), inside_path_clip.r);

    const outside_path_clip = target.at(36, 42);
    try std.testing.expectEqual(@as(u8, 0), outside_path_clip.a);
}

test "renders OpenType SVG alpha masks" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgMaskTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const inside_rect_mask = target.at(24, 32);
    try std.testing.expect(inside_rect_mask.r > 0);
    try std.testing.expect(inside_rect_mask.a > 0 and inside_rect_mask.a < 255);

    const outside_rect_mask = target.at(62, 24);
    try std.testing.expectEqual(@as(u8, 0), outside_rect_mask.a);

    const inside_circle_mask = target.at(47, 35);
    try std.testing.expect(inside_circle_mask.b > 0);
    try std.testing.expect(inside_circle_mask.a > 0 and inside_circle_mask.a < 255);

    const outside_circle_mask = target.at(59, 35);
    try std.testing.expectEqual(@as(u8, 0), outside_circle_mask.a);

    const inside_path_mask = target.at(40, 49);
    try std.testing.expect(inside_path_mask.g > 0);
    try std.testing.expect(inside_path_mask.a > 0 and inside_path_mask.a < 255);

    const outside_path_mask = target.at(36, 42);
    try std.testing.expectEqual(@as(u8, 0), outside_path_mask.a);

    const combo_rect_mask = target.at(20, 52);
    try std.testing.expect(combo_rect_mask.b > 0);
    try std.testing.expect(combo_rect_mask.a > 0 and combo_rect_mask.a < 255);

    const combo_circle_mask = target.at(32, 52);
    try std.testing.expect(combo_circle_mask.b > 0);
    try std.testing.expect(combo_circle_mask.a > 0 and combo_circle_mask.a < 255);

    const combo_gap_mask = target.at(27, 52);
    try std.testing.expectEqual(@as(u8, 0), combo_gap_mask.a);

    const black_masked = target.at(51, 52);
    try std.testing.expectEqual(@as(u8, 0), black_masked.a);
}

test "honors OpenType SVG display and visibility" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgVisibilityTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const visible = target.at(21, 27);
    try std.testing.expect(visible.r > 0);
    try std.testing.expectEqual(@as(u8, 0), visible.b);

    const display_none = target.at(34, 27);
    try std.testing.expectEqual(@as(u8, 0), display_none.a);

    const hidden_group = target.at(47, 27);
    try std.testing.expectEqual(@as(u8, 0), hidden_group.a);

    const style_hidden = target.at(21, 44);
    try std.testing.expectEqual(@as(u8, 0), style_hidden.a);
}

test "renders OpenType SVG path strokes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgPathStrokeTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);

    const triangle_center = target.at(36, 48);
    try std.testing.expectEqual(@as(u8, 0), triangle_center.a);
}

test "renders OpenType SVG line polyline and polygon shapes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgPolylineTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var green_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) blue_pixels += 1;
        if (pixel.g > 0 and pixel.r == 0 and pixel.b == 0) green_pixels += 1;
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(green_pixels > 10);
}

test "renders OpenType SVG ellipse fill and stroke" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgEllipseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    var red_pixels: usize = 0;
    var blue_pixels: usize = 0;
    var translucent_blue_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0) red_pixels += 1;
        if (pixel.b > 0 and pixel.r == 0 and pixel.g == 0) {
            blue_pixels += 1;
            if (pixel.a < 255) translucent_blue_pixels += 1;
        }
    }

    try std.testing.expect(red_pixels > 20);
    try std.testing.expect(blue_pixels > 20);
    try std.testing.expect(translucent_blue_pixels > 20);

    const stroke_center = target.at(47, 37);
    try std.testing.expectEqual(@as(u8, 0), stroke_center.a);
}

test "renders OpenType SVG linear gradient fills" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const left = target.at(20, 32);
    try std.testing.expect(left.r > left.b);
    try std.testing.expect(left.a > 0);

    const right = target.at(50, 32);
    try std.testing.expect(right.b > right.r);
    try std.testing.expect(right.a > 0);

    const middle = target.at(36, 32);
    try std.testing.expect(middle.g > middle.r);
    try std.testing.expect(middle.g > middle.b);
}

test "renders OpenType SVG radial gradient fills" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgRadialGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const center = target.at(36, 36);
    try std.testing.expect(center.r > center.b);
    try std.testing.expect(center.a > 0);

    const edge = target.at(54, 36);
    try std.testing.expect(edge.b > edge.r);
    try std.testing.expect(edge.a > 0);

    const outside = target.at(63, 36);
    try std.testing.expectEqual(@as(u8, 0), outside.a);
}

test "renders OpenType SVG gradient spread methods" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgGradientSpreadTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const repeat_second_period_start = target.at(27, 26);
    try std.testing.expect(repeat_second_period_start.r > repeat_second_period_start.b);

    const repeat_second_period_end = target.at(35, 26);
    try std.testing.expect(repeat_second_period_end.b > repeat_second_period_end.r);

    const reflect_second_period_start = target.at(27, 45);
    try std.testing.expect(reflect_second_period_start.b > reflect_second_period_start.r);

    const reflect_second_period_end = target.at(36, 45);
    try std.testing.expect(reflect_second_period_end.r > reflect_second_period_end.b);
}

test "renders OpenType SVG gradient transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgGradientTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 72, 72);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 48, 12, 60, 0);

    const top = target.at(36, 20);
    try std.testing.expect(top.r > top.b);

    const bottom = target.at(36, 55);
    try std.testing.expect(bottom.b > bottom.r);
}

test "renders COLR glyph layers into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_channel_pixels: usize = 0;
    var blue_channel_pixels: usize = 0;
    var covered_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        covered_pixels += 1;
        if (pixel.r > 0) red_channel_pixels += 1;
        if (pixel.b > 0) blue_channel_pixels += 1;
    }

    try std.testing.expect(covered_pixels > 10);
    try std.testing.expect(red_channel_pixels > 0);
    try std.testing.expect(blue_channel_pixels > 0);
}

test "renders shaped text with COLR glyph layers into an RGBA target" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const fonts = [_]*const Font{&font};
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A", 24);

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorShapedText(&target, shaped, 8, 32, 0);

    var red_channel_pixels: usize = 0;
    var blue_channel_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > 0) red_channel_pixels += 1;
        if (pixel.b > 0) blue_channel_pixels += 1;
    }
    try std.testing.expect(red_channel_pixels > 0);
    try std.testing.expect(blue_channel_pixels > 0);
}

test "matches font database faces by family weight and style" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithNames(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular");
    defer allocator.free(regular_bytes);
    const bold_italic_bytes = try test_font.buildNamedTtfWithNames(allocator, "Cangjie Sans", "Bold Italic", "Cangjie Sans Bold Italic");
    defer allocator.free(bold_italic_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var bold_italic = try Font.parse(allocator, bold_italic_bytes);
    defer bold_italic.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&bold_italic);

    try std.testing.expectEqual(@as(usize, 1), database.familyCount());

    const regular_match = database.match(.{ .family = "cangjie sans", .weight = 400, .style = .normal }).?;
    try std.testing.expectEqual(@as(*const Font, &regular), regular_match.font);
    try std.testing.expectEqual(@as(u16, 400), regular_match.weight);
    try std.testing.expectEqual(FontStyle.normal, regular_match.style);

    const bold_match = database.match(.{ .family = "Cangjie Sans", .weight = 700, .style = .italic }).?;
    try std.testing.expectEqual(@as(*const Font, &bold_italic), bold_match.font);
    try std.testing.expectEqual(@as(u16, 700), bold_match.weight);
    try std.testing.expectEqual(FontStyle.italic, bold_match.style);

    try std.testing.expect(database.match(.{ .family = "Missing Sans" }) == null);
}

test "enumerates font database families and faces" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Sans", "Regular", "Enum Sans Regular");
    defer allocator.free(regular_bytes);
    const bold_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Sans", "Bold", "Enum Sans Bold");
    defer allocator.free(bold_bytes);
    const serif_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Serif", "Regular", "Enum Serif Regular");
    defer allocator.free(serif_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var bold = try Font.parse(allocator, bold_bytes);
    defer bold.deinit();
    var serif = try Font.parse(allocator, serif_bytes);
    defer serif.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&bold);
    _ = try database.addFont(&serif);

    const families = try database.familyNames(allocator);
    defer allocator.free(families);
    try std.testing.expectEqual(@as(usize, 2), families.len);
    try std.testing.expectEqualStrings("Enum Sans", families[0]);
    try std.testing.expectEqualStrings("Enum Serif", families[1]);

    const sans_indices = try database.faceIndicesForFamily(allocator, "enum sans");
    defer allocator.free(sans_indices);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sans_indices);
    const missing_indices = try database.faceIndicesForFamily(allocator, "Missing");
    defer allocator.free(missing_indices);
    try std.testing.expectEqual(@as(usize, 0), missing_indices.len);

    const manifest = try database.manifest(allocator);
    defer FontDatabase.freeManifest(allocator, manifest);
    try std.testing.expectEqual(@as(usize, 3), manifest.len);
    try std.testing.expectEqualStrings("Enum Sans", manifest[0].family);
    try std.testing.expectEqualStrings("Regular", manifest[0].subfamily);
    try std.testing.expectEqualStrings("Enum Sans Regular", manifest[0].full_name);
    try std.testing.expectEqualStrings("EnumSans-Regular", manifest[0].postscript_name);
    try std.testing.expectEqual(@as(u16, 400), manifest[0].weight);
    try std.testing.expectEqual(@as(u16, 100), manifest[0].stretch);
    try std.testing.expectEqual(FontStyle.normal, manifest[0].style);
}

test "serializes font manifest entries with escaping" {
    const allocator = std.testing.allocator;
    const entries = [_]FontManifestEntry{
        .{
            .family = "Family\tOne",
            .subfamily = "Regular",
            .full_name = "Family\\One Regular",
            .postscript_name = "FamilyOne\nRegular",
            .weight = 400,
            .stretch = 100,
            .style = .normal,
        },
        .{
            .family = "Family Two",
            .subfamily = "Italic",
            .full_name = "Family Two Italic",
            .postscript_name = "FamilyTwo-Italic",
            .weight = 700,
            .stretch = 75,
            .style = .italic,
        },
    };
    const text = try serializeManifest(allocator, &entries);
    defer allocator.free(text);
    try std.testing.expectEqualStrings(
        "cangjie-font-manifest-v3\n" ++
            "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\n" ++
            "Family\\tOne\tRegular\tFamily\\\\One Regular\tFamilyOne\\nRegular\t0\t0\t400\t100\tnormal\n" ++
            "Family Two\tItalic\tFamily Two Italic\tFamilyTwo-Italic\t0\t0\t700\t75\titalic\n",
        text,
    );

    const parsed = try parseManifest(allocator, text);
    defer FontDatabase.freeManifest(allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    try std.testing.expectEqualStrings("Family\tOne", parsed[0].family);
    try std.testing.expectEqualStrings("Family\\One Regular", parsed[0].full_name);
    try std.testing.expectEqualStrings("FamilyOne\nRegular", parsed[0].postscript_name);
    try std.testing.expectEqual(@as(u64, 0), parsed[0].content_hash);
    try std.testing.expectEqual(@as(u64, 0), parsed[0].content_size);
    try std.testing.expectEqual(@as(u16, 700), parsed[1].weight);
    try std.testing.expectEqual(@as(u16, 75), parsed[1].stretch);
    try std.testing.expectEqual(FontStyle.italic, parsed[1].style);

    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, "bad\n"));
}

test "writes and reads font manifest files" {
    const allocator = std.testing.allocator;
    const entries = [_]FontManifestEntry{.{
        .family = "Disk Family",
        .subfamily = "Regular",
        .full_name = "Disk Family Regular",
        .postscript_name = "DiskFamily-Regular",
        .content_hash = 0x1234,
        .content_size = 4096,
        .weight = 500,
        .stretch = 100,
        .style = .normal,
    }};

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try writeManifestFile(allocator, std.testing.io, tmp_dir.dir, "manifest.tsv", &entries);
    const parsed = try readManifestFile(allocator, std.testing.io, tmp_dir.dir, "manifest.tsv", .limited(1024 * 1024));
    defer FontDatabase.freeManifest(allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqualStrings("Disk Family", parsed[0].family);
    try std.testing.expectEqualStrings("DiskFamily-Regular", parsed[0].postscript_name);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed[0].content_hash);
    try std.testing.expectEqual(@as(u64, 4096), parsed[0].content_size);
    try std.testing.expectEqual(@as(u16, 500), parsed[0].weight);
}

test "font database owns parsed font bytes and builds fallback cascades" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Owned Primary", "Regular", "Owned Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Owned Fallback", "Regular", "Owned Fallback Regular");
    defer allocator.free(fallback_bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(primary_bytes);
    _ = try database.addFontBytes(fallback_bytes);

    const primary = database.match(.{ .family = "Owned Primary" }).?;
    try std.testing.expectEqualStrings("Owned Primary", primary.family);

    const cascade_fonts = try database.buildCascadeForText(allocator, .{ .family = "Owned Primary" }, "ABA");
    defer allocator.free(cascade_fonts);
    try std.testing.expectEqual(@as(usize, 2), cascade_fonts.len);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(cascade_fonts), &layout_buffer, "ABA", 20);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[2].font_index);
}

test "font database cascade construction rejects malformed UTF-8" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithNames(allocator, "UTF8 Sans", "Regular", "UTF8 Sans Regular");
    defer allocator.free(bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(bytes);

    const face_count = database.faces.items.len;
    // buildCascadeForText feeds text into Utf8Iterator for fallback discovery.
    // Reject malformed bytes rather than returning a truncated primary-only
    // cascade for the prefix before the invalid sequence.
    try std.testing.expectError(error.InvalidUtf8, database.buildCascadeForText(allocator, .{ .family = "UTF8 Sans" }, "A\xc3("));
    try std.testing.expectEqual(face_count, database.faces.items.len);

    try std.testing.expectError(error.InvalidUtf8, database.cascadeForText(allocator, .{ .family = "UTF8 Sans" }, "\xf0\x28\x8c\x28"));
}

test "font database deduplicates equivalent faces" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithNames(allocator, "Dedupe Sans", "Regular", "Dedupe Sans Regular");
    defer allocator.free(bytes);

    var borrowed_a = try Font.parse(allocator, bytes);
    defer borrowed_a.deinit();
    var borrowed_b = try Font.parse(allocator, bytes);
    defer borrowed_b.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&borrowed_a));
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&borrowed_b));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);

    try std.testing.expectEqual(@as(usize, 0), try database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);
    try std.testing.expectEqual(@as(usize, 1), database.familyCount());

    var owned_database = FontDatabase.init(allocator);
    defer owned_database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try owned_database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 0), try owned_database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 1), owned_database.faces.items.len);
    try std.testing.expectEqual(@as(usize, 1), owned_database.familyCount());
    const owned_manifest = try owned_database.manifest(allocator);
    defer FontDatabase.freeManifest(allocator, owned_manifest);
    try std.testing.expect(owned_manifest[0].content_hash != 0);
    try std.testing.expectEqual(@as(u64, @intCast(bytes.len)), owned_manifest[0].content_size);
    try std.testing.expect(manifestEntryMatchesBytes(owned_manifest[0], bytes));
    try std.testing.expect(!manifestEntryMatchesBytes(owned_manifest[0], bytes[0 .. bytes.len - 1]));
}

test "font database uses PostScript names as stable duplicate ids" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const first_bytes = try test_font.buildNamedTtfWithPostScript(allocator, "PS Family A", "Regular", "PS Family A Regular", "SharedPS-Regular");
    defer allocator.free(first_bytes);
    const second_bytes = try test_font.buildNamedTtfWithPostScript(allocator, "PS Family B", "Regular", "PS Family B Regular", "SharedPS-Regular");
    defer allocator.free(second_bytes);

    var first_font = try Font.parse(allocator, first_bytes);
    defer first_font.deinit();
    var second_font = try Font.parse(allocator, second_bytes);
    defer second_font.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&first_font));
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&second_font));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);
    try std.testing.expectEqualStrings("SharedPS-Regular", database.faces.items[0].postscript_name);

    const matched = database.match(.{ .family = "", .postscript_name = "sharedps-regular" }).?;
    try std.testing.expectEqualStrings("PS Family A", matched.family);
    try std.testing.expect(database.match(.{ .family = "", .postscript_name = "MissingPS-Regular" }) == null);
}

test "font database ingests all faces from a TTC collection" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 2), try Font.faceCount(bytes));

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 2), try database.addFontCollectionBytes(bytes));
    try std.testing.expectEqual(@as(usize, 0), try database.addFontCollectionBytes(bytes));
    try std.testing.expectEqual(@as(usize, 2), database.familyCount());

    const first = database.match(.{ .family = "Collection One" }).?;
    try std.testing.expectEqualStrings("Collection One", first.family);
    const second = database.match(.{ .family = "Collection Two" }).?;
    try std.testing.expectEqualStrings("Collection Two", second.family);
}

test "font database ingests font files from an Io directory" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const font_bytes = try test_font.buildNamedTtfWithNames(allocator, "File Sans", "Regular", "File Sans Regular");
    defer allocator.free(font_bytes);
    const collection_bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(collection_bytes);

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "file.ttf", .data = font_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "collection.ttc", .data = collection_bytes });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontFile(std.testing.io, tmp_dir.dir, "file.ttf", .limited(1024 * 1024));
    try std.testing.expectEqual(@as(usize, 2), try database.addFontCollectionFile(std.testing.io, tmp_dir.dir, "collection.ttc", .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 3), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "File Sans" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection One" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection Two" }) != null);
}

test "font database scans supported font files in a directory" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const font_bytes = try test_font.buildNamedTtfWithNames(allocator, "Scan Sans", "Regular", "Scan Sans Regular");
    defer allocator.free(font_bytes);
    const collection_bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(collection_bytes);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "scan.ttf", .data = font_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "collection.TTC", .data = collection_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "ignore.txt", .data = font_bytes });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 3), try database.scanFontDir(std.testing.io, tmp_dir.dir, .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 3), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "Scan Sans" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection One" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection Two" }) != null);
}

test "font database recursively scans supported font files" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const root_font = try test_font.buildNamedTtfWithNames(allocator, "Root Scan", "Regular", "Root Scan Regular");
    defer allocator.free(root_font);
    const nested_font = try test_font.buildNamedTtfWithNames(allocator, "Nested Scan", "Regular", "Nested Scan Regular");
    defer allocator.free(nested_font);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.createDirPath(std.testing.io, "nested/deeper");
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "root.ttf", .data = root_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "nested/deeper/nested.OTF", .data = nested_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "nested/deeper/ignore.md", .data = nested_font });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 2), try database.scanFontTree(std.testing.io, tmp_dir.dir, .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 2), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "Root Scan" }) != null);
    try std.testing.expect(database.match(.{ .family = "Nested Scan" }) != null);
}

test "font database scans configured font sources" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const flat_font = try test_font.buildNamedTtfWithNames(allocator, "Flat Source", "Regular", "Flat Source Regular");
    defer allocator.free(flat_font);
    const recursive_font = try test_font.buildNamedTtfWithNames(allocator, "Recursive Source", "Regular", "Recursive Source Regular");
    defer allocator.free(recursive_font);
    const file_font = try test_font.buildNamedTtfWithNames(allocator, "File Source", "Regular", "File Source Regular");
    defer allocator.free(file_font);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.createDirPath(std.testing.io, "flat");
    try tmp_dir.dir.createDirPath(std.testing.io, "tree/deep");
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "flat/flat.ttf", .data = flat_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "tree/deep/recursive.ttf", .data = recursive_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "direct.otf", .data = file_font });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    const sources = [_]FontSource{
        .{ .directory = .{ .path = "flat", .recursive = false } },
        .{ .directory = .{ .path = "tree", .recursive = true } },
        .{ .file = .{ .path = "direct.otf" } },
        .{ .file = .{ .path = "missing.ttf", .ignore_missing = true } },
        .{ .directory = .{ .path = "missing", .recursive = true, .ignore_missing = true } },
    };
    try std.testing.expectEqual(@as(usize, 3), try database.scanFontSources(std.testing.io, tmp_dir.dir, &sources, .limited(1024 * 1024)));
    try std.testing.expect(database.match(.{ .family = "Flat Source" }) != null);
    try std.testing.expect(database.match(.{ .family = "Recursive Source" }) != null);
    try std.testing.expect(database.match(.{ .family = "File Source" }) != null);
}

test "builds conservative default system font source lists" {
    const macos_sources = defaultSystemFontSourcesForOs(.macos);
    try std.testing.expectEqual(@as(usize, 2), macos_sources.len);
    try std.testing.expectEqualStrings("/System/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expect(macos_sources[0].directory.recursive);
    try std.testing.expect(macos_sources[0].directory.ignore_missing);
    try std.testing.expectEqualStrings("/Library/Fonts", macos_sources[1].directory.path);

    const linux_sources = defaultSystemFontSourcesForOs(.linux);
    try std.testing.expectEqual(@as(usize, 2), linux_sources.len);
    try std.testing.expectEqualStrings("/usr/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/usr/local/share/fonts", linux_sources[1].directory.path);

    const windows_sources = defaultSystemFontSourcesForOs(.windows);
    try std.testing.expectEqual(@as(usize, 1), windows_sources.len);
    try std.testing.expectEqualStrings("C:\\Windows\\Fonts", windows_sources[0].directory.path);

    const unknown_sources = defaultSystemFontSourcesForOs(.freestanding);
    try std.testing.expectEqual(@as(usize, 0), unknown_sources.len);
}

test "builds user font source lists from a home path" {
    var source_buffer: [4]FontSource = undefined;
    var path_buffer: [256]u8 = undefined;

    const macos_sources = try userFontSourcesForOs("/Users/example", .macos, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 1), macos_sources.len);
    try std.testing.expectEqualStrings("/Users/example/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expect(macos_sources[0].directory.recursive);
    try std.testing.expect(macos_sources[0].directory.ignore_missing);

    const linux_sources = try userFontSourcesForOs("/home/example/", .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 2), linux_sources.len);
    try std.testing.expectEqualStrings("/home/example/.local/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/home/example/.fonts", linux_sources[1].directory.path);

    const windows_sources = try userFontSourcesForOs("C:\\Users\\example", .windows, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 0), windows_sources.len);
}

test "builds combined system and user font source lists" {
    var source_buffer: [8]FontSource = undefined;
    var path_buffer: [256]u8 = undefined;

    const macos_sources = try combinedSystemFontSourcesForOs("/Users/example", .macos, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 3), macos_sources.len);
    try std.testing.expectEqualStrings("/System/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expectEqualStrings("/Library/Fonts", macos_sources[1].directory.path);
    try std.testing.expectEqualStrings("/Users/example/Library/Fonts", macos_sources[2].directory.path);

    const linux_sources = try combinedSystemFontSourcesForOs("/home/example", .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 4), linux_sources.len);
    try std.testing.expectEqualStrings("/usr/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/usr/local/share/fonts", linux_sources[1].directory.path);
    try std.testing.expectEqualStrings("/home/example/.local/share/fonts", linux_sources[2].directory.path);
    try std.testing.expectEqualStrings("/home/example/.fonts", linux_sources[3].directory.path);

    const no_home_sources = try combinedSystemFontSourcesForOs(null, .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 2), no_home_sources.len);
}

test "uses OS/2 style attributes for database matching" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(regular_bytes);
    const narrow_italic_bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 650, 3, true, false);
    defer allocator.free(narrow_italic_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var narrow_italic = try Font.parse(allocator, narrow_italic_bytes);
    defer narrow_italic.deinit();

    const attributes = try narrow_italic.styleAttributes();
    try std.testing.expectEqual(@as(u16, 650), attributes.weight);
    try std.testing.expectEqual(@as(u16, 3), attributes.width);
    try std.testing.expect(attributes.italic);
    try std.testing.expect(!attributes.bold);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&narrow_italic);

    const matched = database.match(.{ .family = "Metric Sans", .weight = 650, .stretch = 75, .style = .italic }).?;
    try std.testing.expectEqual(@as(*const Font, &narrow_italic), matched.font);
    try std.testing.expectEqual(@as(u16, 650), matched.weight);
    try std.testing.expectEqual(@as(u16, 75), matched.stretch);
    try std.testing.expectEqual(FontStyle.italic, matched.style);
}

test "builds coverage-aware fallback cascades from the font database" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Fallback Sans", "Regular", "Fallback Sans Regular");
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&primary);
    _ = try database.addFont(&fallback);

    const cascade_fonts = try database.buildCascadeForText(allocator, .{ .family = "Primary Sans" }, "ABA");
    defer allocator.free(cascade_fonts);
    try std.testing.expectEqual(@as(usize, 2), cascade_fonts.len);
    try std.testing.expectEqual(@as(*const Font, &primary), cascade_fonts[0]);
    try std.testing.expectEqual(@as(*const Font, &fallback), cascade_fonts[1]);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(cascade_fonts), &layout_buffer, "ABA", 20);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[2].font_index);
}

test "shapes cascade text right-to-left with visual glyph order" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const hebrew_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Hebrew Sans", "Regular", "Hebrew Sans Regular");
    defer allocator.free(hebrew_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var hebrew = try Font.parse(allocator, hebrew_bytes);
    defer hebrew.deinit();

    const fonts = [_]*const Font{ &primary, &hebrew };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "A\u{05d0}", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[1].font_index);
}

test "shapes mixed-direction cascade text in bidi visual order" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);
    const trailing_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Trailing Sans", "Regular", "Trailing Sans Regular");
    defer allocator.free(trailing_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();
    var trailing = try Font.parse(allocator, trailing_bytes);
    defer trailing.deinit();

    const fonts = [_]*const Font{ &primary, &alef, &bet, &trailing };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "A\u{05d0}\u{05d1}B", 20, .{ .direction = .ltr });

    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d1), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(u21, 'B'), shaped.glyphs[3].codepoint);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 1, 5 }, &.{
        shaped.glyphs[0].cluster,
        shaped.glyphs[1].cluster,
        shaped.glyphs[2].cluster,
        shaped.glyphs[3].cluster,
    });

    try std.testing.expectEqual(@as(usize, 4), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs[3].font_index);
}

test "defaults right-to-left paragraph alignment to the right edge" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .rtl,
    });

    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectEqual(@as(u21, 'A'), paragraph.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), paragraph.glyphs[0].cluster);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), paragraph.lines[0].x, 0.001);
}

test "wraps CJK text at character boundaries without spaces" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedCjkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "一丁丂", 20, .{
        .max_width = 32,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectEqual(@as(u21, 0x4e00), paragraph.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x4e01), paragraph.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x4e02), paragraph.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(usize, 0), paragraph.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 6), paragraph.glyphs[2].cluster);
}

test "paragraph wrapping keeps combining grapheme clusters atomic" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\u{0301}A", 20, .{
        .max_width = 20,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 'A'), paragraph.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x0301), paragraph.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), paragraph.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(usize, 0), paragraph.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs[2].cluster);
}

test "paragraph wrapping consumes Unicode line break data" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const ascii_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ascii_bytes);
    var ascii_font = try Font.parse(allocator, ascii_bytes);
    defer ascii_font.deinit();
    const ascii_fonts = [_]*const Font{&ascii_font};
    const ascii_cascade = FontCascade.init(&ascii_fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const crlf = try TextShaper.layoutParagraphUtf8(ascii_cascade, &layout_buffer, "A\r\nA", 20, .{
        .max_width = 80,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), crlf.lines.len);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 'A'), crlf.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), crlf.glyphs[3].codepoint);

    const cjk_bytes = try test_font.buildNamedCjkTtf(allocator);
    defer allocator.free(cjk_bytes);
    var cjk_font = try Font.parse(allocator, cjk_bytes);
    defer cjk_font.deinit();
    const cjk_fonts = [_]*const Font{&cjk_font};
    const cjk_cascade = FontCascade.init(&cjk_fonts);

    const ivs = try TextShaper.layoutParagraphUtf8(cjk_cascade, &layout_buffer, "\u{4e00}\u{e0100}丁", 20, .{
        .max_width = 20,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), ivs.lines.len);
    try std.testing.expectEqual(@as(usize, 1), ivs.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), ivs.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x4e00), ivs.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), ivs.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 7), ivs.glyphs[0].source_byte_len);
    try std.testing.expectEqual(@as(usize, 7), ivs.glyphs[1].cluster);
}

test "limits paragraph lines and appends ellipsis" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const ellipsized = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = true,
    });

    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    try std.testing.expectEqual(@as(usize, ellipsized.lines[0].glyph_len), ellipsized.glyphs.len);
    try std.testing.expect(ellipsized.lines[0].width <= 42);
    try std.testing.expect(ellipsized.glyphs.len >= 3);
    const glyph_count = ellipsized.glyphs.len;
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 1].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 2].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 3].codepoint);

    const truncated = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = false,
    });
    try std.testing.expectEqual(@as(usize, 1), truncated.lines.len);
    try std.testing.expect(truncated.glyphs[truncated.glyphs.len - 1].codepoint != '.');

    const hidden = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 0,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 0), hidden.lines.len);
    try std.testing.expectEqual(@as(usize, 0), hidden.glyphs.len);

    const exactly_limited = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 1), exactly_limited.lines.len);
    try std.testing.expectEqual(@as(usize, 1), exactly_limited.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), exactly_limited.glyphs[0].codepoint);
}

test "expands tabs to configurable tab stops" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const default_tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA", 20, .{
        .max_width = 200,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 3), default_tabs.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), default_tabs.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), default_tabs.lines[0].width, 0.001);

    const narrow_tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA", 20, .{
        .max_width = 200,
        .line_height = 24,
        .tab_width = 2,
    });

    try std.testing.expectApproxEqAbs(@as(f32, 16.0), narrow_tabs.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), narrow_tabs.lines[0].width, 0.001);
}

test "applies letter and word spacing during paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const letter_spaced = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 200,
        .line_height = 24,
        .letter_spacing = 2,
    });

    try std.testing.expectEqual(@as(usize, 2), letter_spaced.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), letter_spaced.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), letter_spaced.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 34.0), letter_spaced.lines[0].width, 0.001);

    const word_spaced = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 200,
        .line_height = 24,
        .letter_spacing = 2,
        .word_spacing = 5,
    });

    try std.testing.expectEqual(@as(usize, 3), word_spaced.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), word_spaced.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), word_spaced.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), word_spaced.glyphs[2].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 51.0), word_spaced.lines[0].width, 0.001);

    const wrapped = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 45,
        .line_height = 24,
        .letter_spacing = 2,
        .word_spacing = 5,
    });
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
}

test "applies first line indent to paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 48,
        .line_height = 24,
        .first_line_indent = 16,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), paragraph.width, 0.001);

    const centered = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 80,
        .line_height = 24,
        .alignment = .center,
        .first_line_indent = 20,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), centered.lines[0].x, 0.001);
}

test "applies paragraph spacing after hard breaks" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const hard_break = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\nA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
    });

    try std.testing.expectEqual(@as(usize, 2), hard_break.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), hard_break.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), hard_break.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), hard_break.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), hard_break.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 54.0), hard_break.height, 0.001);

    const soft_wrap = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 48,
        .line_height = 24,
        .first_line_indent = 16,
        .paragraph_spacing = 6,
    });

    try std.testing.expectEqual(@as(usize, 2), soft_wrap.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), soft_wrap.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), soft_wrap.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), soft_wrap.lines[1].y, 0.001);
}

test "measures paragraphs and batches text metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

test "shapes text across a fallback font cascade" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

test "caches glyph indices by font and codepoint during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

test "lays out wrapped and aligned fallback text into paragraph lines" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A B A", 20, .{
        .max_width = 42,
        .alignment = .right,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), paragraph.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), paragraph.height, 0.001);
    try std.testing.expect(paragraph.lines[0].run_len >= 2);
}

test "paragraph lines expose baseline metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const natural = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
    });
    try std.testing.expectEqual(@as(usize, 1), natural.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), natural.lines[0].baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), natural.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), natural.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), natural.lines[0].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), natural.lines[0].height, 0.001);

    const expanded = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), expanded.lines[0].baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), expanded.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), expanded.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), expanded.lines[0].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), expanded.lines[0].height, 0.001);
}

test "builds debug overlay geometry for paragraph text" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var overlays = try buildDebugOverlays(allocator, paragraph, .{
        .cursor = .{ .glyph_index = 1, .cluster = 1 },
        .selection_start_glyph = 0,
        .selection_end_glyph = 2,
        .bidi_text = "A ב",
    });
    defer overlays.deinit();

    var saw_baseline = false;
    var saw_line_box = false;
    var saw_cursor = false;
    var saw_selection = false;
    var saw_bidi = false;
    var saw_glyph = false;
    var saw_cluster = false;
    var saw_fallback = false;
    for (overlays.items) |overlay| {
        switch (overlay.kind) {
            .baseline => {
                saw_baseline = true;
                try std.testing.expectApproxEqAbs(@as(f32, 18.0), overlay.line_start_y, 0.001);
                try std.testing.expectApproxEqAbs(@as(f32, 30.0), overlay.line_end_x, 0.001);
            },
            .line_box => {
                saw_line_box = true;
                try std.testing.expectApproxEqAbs(@as(f32, 24.0), overlay.rect.height, 0.001);
            },
            .cursor_rect => {
                saw_cursor = true;
                try std.testing.expectApproxEqAbs(@as(f32, 14.0), overlay.rect.x, 0.001);
            },
            .selection_rect => saw_selection = true,
            .glyph_box => {
                saw_glyph = true;
                try std.testing.expect(overlay.rect.width > 0);
                try std.testing.expect(overlay.rect.height > 0);
            },
            .cluster_boundary => {
                saw_cluster = true;
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), overlay.rect.width, 0.001);
                try std.testing.expect(overlay.line_end_y > overlay.line_start_y);
            },
            .fallback_font_region => {
                saw_fallback = true;
                try std.testing.expect(overlay.rect.width > 0);
            },
            .bidi_run => {
                saw_bidi = true;
                try std.testing.expect(overlay.byte_end > overlay.byte_start);
            },
        }
    }
    try std.testing.expect(saw_baseline);
    try std.testing.expect(saw_line_box);
    try std.testing.expect(saw_cursor);
    try std.testing.expect(saw_selection);
    try std.testing.expect(saw_bidi);
    try std.testing.expect(saw_glyph);
    try std.testing.expect(saw_cluster);
    try std.testing.expect(saw_fallback);
}

test "hit tests carets and selection geometry in paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A B A", 20, .{
        .max_width = 42,
        .alignment = .right,
        .line_height = 24,
    });

    const first = paragraph.hitTest(1, 8);
    try std.testing.expectEqual(@as(usize, 0), first.glyph_index);
    try std.testing.expect(!first.trailing);

    const after_first = paragraph.hitTest(15, 8);
    try std.testing.expectEqual(@as(usize, 0), after_first.glyph_index);
    try std.testing.expect(after_first.trailing);

    const second_line = paragraph.hitTest(30, 30);
    try std.testing.expectEqual(@as(usize, 4), second_line.glyph_index);
    try std.testing.expect(!second_line.trailing);

    const caret = paragraph.caretRect(.{ .glyph_index = 4, .cluster = 4 });
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), caret.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), caret.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), caret.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), caret.height, 0.001);

    const selection = paragraph.selectionRect(1, 4);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), selection.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), selection.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), selection.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), selection.height, 0.001);

    const rects = try paragraph.selectionRects(allocator, 1, 5);
    defer allocator.free(rects);
    try std.testing.expectEqual(@as(usize, 2), rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), rects[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), rects[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), rects[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), rects[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), rects[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[1].height, 0.001);

    var rect_buffer: [1]TextRect = undefined;
    const clipped_rects = paragraph.selectionRectsInto(&rect_buffer, 1, 5);
    try std.testing.expectEqual(@as(usize, 1), clipped_rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), clipped_rects[0].x, 0.001);
}

test "moves paragraph carets across grapheme cluster boundaries" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\u{0301}A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    const clusters = try itemizeGraphemeClusters(allocator, "A\u{0301}A");
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 2), clusters.len);
    const start = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 0, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 0), start.cluster);
    const next = paragraph.nextGraphemeCaret(clusters, start);
    try std.testing.expectEqual(@as(usize, 3), next.cluster);
    try std.testing.expectEqual(@as(usize, 2), next.glyph_index);
    const previous = paragraph.previousGraphemeCaret(clusters, next);
    try std.testing.expectEqual(@as(usize, 0), previous.cluster);

    const inside_mark = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 1, .cluster = 1 });
    try std.testing.expectEqual(@as(usize, 0), inside_mark.cluster);
}

test "hit testing reports trailing source byte offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "A\u{fe0f}";
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs.len);
    try std.testing.expectEqual(@as(usize, text.len), paragraph.glyphs[0].source_byte_len);

    const leading = paragraph.hitTest(1, 8);
    try std.testing.expectEqual(@as(usize, 0), leading.glyph_index);
    try std.testing.expectEqual(@as(usize, 0), leading.cluster);
    try std.testing.expect(!leading.trailing);

    const trailing = paragraph.hitTest(15, 8);
    try std.testing.expectEqual(@as(usize, 0), trailing.glyph_index);
    try std.testing.expectEqual(@as(usize, text.len), trailing.cluster);
    try std.testing.expect(trailing.trailing);
}

test "paragraph carets use shaped glyph source extents" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "A\u{fe0f}";
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), paragraph.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, text.len), paragraph.glyphs[0].source_byte_len);
    // A variation selector does not produce its own glyph, so the last glyph's
    // trailing edge must carry the selector byte extent. Otherwise snapping a
    // clicked trailing caret would jump back to the start of the grapheme.
    const snapped = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 0, .cluster = 0, .trailing = true });
    try std.testing.expect(snapped.trailing);
    try std.testing.expectEqual(@as(usize, text.len), snapped.cluster);
}

test "moves paragraph carets across word boundaries" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA BB", 20, .{
        .max_width = 120,
        .line_height = 24,
    });
    const words = try itemizeWordSegments(allocator, "AA BB");
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    const start = paragraph.snapToWordCaret(words, .{ .glyph_index = 0, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 0), start.cluster);
    const first_end = paragraph.nextWordCaret(words, start);
    try std.testing.expectEqual(@as(usize, 2), first_end.cluster);
    const second_end = paragraph.nextWordCaret(words, first_end);
    try std.testing.expectEqual(@as(usize, 5), second_end.cluster);
    const previous = paragraph.previousWordCaret(words, .{ .glyph_index = 3, .cluster = 3 });
    try std.testing.expectEqual(@as(usize, 0), previous.cluster);
    const snapped_inside = paragraph.snapToWordCaret(words, .{ .glyph_index = 1, .cluster = 1 });
    try std.testing.expectEqual(@as(usize, 2), snapped_inside.cluster);
}

test "applies GSUB ligature substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs[0].source_byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), run.width(), 0.001);
}

test "applies GSUB multiple substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMultipleGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
}

test "applies GSUB alternate substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildAlternateGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
}

test "applies GSUB extension substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildExtensionGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
}

test "applies only GSUB lookups referenced by active features" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSelectiveGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);

    const disabled = [_]FeatureOverride{.{ .tag = openTypeTag("liga"), .enabled = false }};
    const unligated = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "AA", 20, .{ .features = &disabled });
    try std.testing.expectEqual(@as(usize, 2), unligated.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), unligated.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), unligated.glyphs[1].glyph_id);
}

test "applies GSUB contextual substitution with nested lookup" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildContextGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
}

test "applies GSUB coverage-based contextual substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildContextFormat3GsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
}

test "applies GSUB class-based contextual substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildContextClassGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
}

test "applies GSUB chaining contextual substitution with nested lookup" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildChainingGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[2].glyph_id);
}

test "applies GSUB reverse chaining single substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildReverseChainingGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
}

test "applies GPOS pair positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), run.glyphs[1].y_offset, 0.001);
}

test "prefers GPOS pair positioning over legacy kern for same pair" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposAndKernTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
}

test "applies GPOS single positioning offsets during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_offset, 0.001);
}

test "applies GPOS extension positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildExtensionGposTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_offset, 0.001);
}

test "applies GPOS class pair positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposClassTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
}

test "applies GPOS mark-to-base positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS mark anchors with contour and device formats" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGposMarkAnchorFormatsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS mark-to-base positioning across intervening marks" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[2].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[2].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[2].y_offset, 0.001);
}

test "applies GPOS mark-to-mark positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkToMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS cursive positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposCursiveTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS mark-to-ligature positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkToLigatureTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.4), run.glyphs[1].y_offset, 0.001);
}

test "passes GSUB ligature component sources into GPOS mark-to-ligature shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGsubGposMarkToLigatureComponentsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.4), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS coverage-based contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposContextTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
}

test "applies GPOS chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
}

test "applies GPOS glyph-based chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposGlyphChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
}

test "applies GPOS class-based chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposClassChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
}

test "applies GPOS glyph-based contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalGposGlyphContextTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
}

test {
    std.testing.refAllDecls(@This());
}
