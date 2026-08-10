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
pub const JoiningForm = @import("unicode.zig").JoiningForm;
pub const JoiningType = @import("unicode.zig").JoiningType;
pub const VerticalOrientation = @import("unicode.zig").VerticalOrientation;
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
pub const GraphemeClusterIterator = @import("unicode.zig").GraphemeClusterIterator;
pub const graphemeClusters = @import("unicode.zig").graphemeClusters;
pub const GlyphCluster = @import("core.zig").GlyphCluster;
pub const GlyphRange = @import("core.zig").GlyphRange;
pub const Language = @import("core.zig").Language;
pub const Locale = @import("core.zig").Locale;
pub const WordSegment = @import("unicode.zig").WordSegment;
pub const SentenceSegment = @import("unicode.zig").SentenceSegment;
pub const LineBreak = @import("unicode.zig").LineBreak;
pub const LineBreakKind = @import("unicode.zig").LineBreakKind;
pub const LineBreakClass = @import("unicode.zig").LineBreakClass;
pub const LineBreakIterator = @import("unicode.zig").LineBreakIterator;
pub const line_break_unicode_version = @import("unicode.zig").line_break_unicode_version;
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
pub const FontContainerError = @import("font_container.zig").Error;
pub const FontContainerFormat = @import("font_container.zig").Format;
pub const default_max_decoded_font_size = @import("font_container.zig").default_max_decoded_size;
pub const LoadedFont = @import("font_container.zig").LoadedFont;
pub const decodeFontContainerAlloc = @import("font_container.zig").decodeFontContainerAlloc;
pub const detectFontContainerFormat = @import("font_container.zig").detectFormat;
pub const AnkrAnchorInfo = @import("font.zig").AnkrAnchorInfo;
pub const AnkrGlyphAnchorsInfo = @import("font.zig").AnkrGlyphAnchorsInfo;
pub const AnkrInfo = @import("font.zig").AnkrInfo;
pub const BaseAxisInfo = @import("font.zig").BaseAxisInfo;
pub const BaseInfo = @import("font.zig").BaseInfo;
pub const BaseScriptInfo = @import("font.zig").BaseScriptInfo;
pub const FeatureNameInfo = @import("font.zig").FeatureNameInfo;
pub const FeatureSettingInfo = @import("font.zig").FeatureSettingInfo;
pub const TrackInfo = @import("font.zig").TrackInfo;
pub const TrackTableInfo = @import("font.zig").TrackTableInfo;
pub const TrackValueInfo = @import("font.zig").TrackValueInfo;
pub const DsigInfo = @import("font.zig").DsigInfo;
pub const DsigSignatureInfo = @import("font.zig").DsigSignatureInfo;
pub const GaspInfo = @import("font.zig").GaspInfo;
pub const GaspRange = @import("font.zig").GaspRange;
pub const CharmapInfo = @import("font.zig").CharmapInfo;
pub const CharmapMapping = @import("font.zig").CharmapMapping;
pub const FontDecorationMetrics = @import("font.zig").FontDecorationMetrics;
pub const FontDecorationMetricSource = @import("font.zig").FontDecorationMetricSource;
pub const FontScriptMetrics = @import("font.zig").FontScriptMetrics;
pub const ScaledFontDecorationMetrics = @import("font.zig").ScaledFontDecorationMetrics;
pub const ScaledFontScriptMetrics = @import("font.zig").ScaledFontScriptMetrics;
pub const FontError = @import("font.zig").FontError;
pub const FontFormat = @import("font.zig").FontFormat;
pub const FontHeaderInfo = @import("font.zig").FontHeaderInfo;
pub const Cff2Info = @import("font.zig").Cff2Info;
pub const Cff2FontDictInfo = @import("font.zig").Cff2FontDictInfo;
pub const Cff2PrivateDictInfo = @import("font.zig").Cff2PrivateDictInfo;
pub const Cff2CharStringScanInfo = @import("font.zig").Cff2CharStringScanInfo;
pub const Cff2CharStringBoundsInfo = @import("font.zig").Cff2CharStringBoundsInfo;
pub const GvarInfo = @import("font.zig").GvarInfo;
pub const GvarGlyphInfo = @import("font.zig").GvarGlyphInfo;
pub const GvarTupleInfo = @import("font.zig").GvarTupleInfo;
pub const GvarScaledPointDelta = @import("font.zig").GvarScaledPointDelta;
pub const GvarPhantomPointDeltas = @import("font.zig").GvarPhantomPointDeltas;
pub const CvarInfo = @import("font.zig").CvarInfo;
pub const CvarTupleInfo = @import("font.zig").CvarTupleInfo;
pub const TrueTypeProgramInfo = @import("font.zig").TrueTypeProgramInfo;
pub const TrueTypeProgramInstructionInfo = @import("font.zig").TrueTypeProgramInstructionInfo;
pub const TrueTypeProgramKind = @import("font.zig").TrueTypeProgramKind;
pub const FontTableInfo = @import("font.zig").FontTableInfo;
pub const MathConstant = @import("font.zig").MathConstant;
pub const MathInfo = @import("font.zig").MathInfo;
pub const MathConstantsInfo = @import("font.zig").MathConstantsInfo;
pub const MathValueRecordInfo = @import("font.zig").MathValueRecordInfo;
pub const MathGlyphValueRecordInfo = @import("font.zig").MathGlyphValueRecordInfo;
pub const MathVariantRecordInfo = @import("font.zig").MathVariantRecordInfo;
pub const MathPartRecordInfo = @import("font.zig").MathPartRecordInfo;
pub const MathAssemblyInfo = @import("font.zig").MathAssemblyInfo;
pub const MathConstructionInfo = @import("font.zig").MathConstructionInfo;
pub const MathKernInfo = @import("font.zig").MathKernInfo;
pub const MathKernRecordInfo = @import("font.zig").MathKernRecordInfo;
pub const MathKernTableInfo = @import("font.zig").MathKernTableInfo;
pub const MaxProfileInfo = @import("font.zig").MaxProfileInfo;
pub const IftPatchMapInfo = @import("font.zig").IftPatchMapInfo;
pub const IftTableKeyedPatchInfo = @import("font.zig").IftTableKeyedPatchInfo;
pub const IftGlyphKeyedPatchInfo = @import("font.zig").IftGlyphKeyedPatchInfo;
pub const HdmxInfo = @import("font.zig").HdmxInfo;
pub const HdmxRecord = @import("font.zig").HdmxRecord;
pub const HvarInfo = @import("font.zig").HvarInfo;
pub const MetricVariationIndexMapEntryInfo = @import("font.zig").MetricVariationIndexMapEntryInfo;
pub const MetricVariationIndexMapInfo = @import("font.zig").MetricVariationIndexMapInfo;
pub const LtshInfo = @import("font.zig").LtshInfo;
pub const LtagRecordInfo = @import("font.zig").LtagRecordInfo;
pub const HorizontalMetricInfo = @import("font.zig").HorizontalMetricInfo;
pub const MetricHeaderInfo = @import("font.zig").MetricHeaderInfo;
pub const VerticalMetricInfo = @import("font.zig").VerticalMetricInfo;
pub const VerticalOriginInfo = @import("font.zig").VerticalOriginInfo;
pub const VerticalOriginMetric = @import("font.zig").VerticalOriginMetric;
pub const GlyphClass = @import("font.zig").GlyphClass;
pub const NameEncoding = @import("font.zig").NameEncoding;
pub const NameId = @import("font.zig").NameId;
pub const NameLanguageTagInfo = @import("font.zig").NameLanguageTagInfo;
pub const NameRecordInfo = @import("font.zig").NameRecordInfo;
pub const MetaRecordInfo = @import("font.zig").MetaRecordInfo;
pub const MvarInfo = @import("font.zig").MvarInfo;
pub const MvarValueRecordInfo = @import("font.zig").MvarValueRecordInfo;
pub const VvarInfo = @import("font.zig").VvarInfo;
pub const VarcInfo = @import("font.zig").VarcInfo;
pub const Os2Info = @import("font.zig").Os2Info;
pub const FontFallbackCache = @import("layout.zig").FontFallbackCache;
pub const FontFallbackDecision = @import("layout.zig").FontFallbackDecision;
pub const KernInfo = @import("font.zig").KernInfo;
pub const KernSubtableInfo = @import("font.zig").KernSubtableInfo;
pub const KerxInfo = @import("font.zig").KerxInfo;
pub const KerxPairInfo = @import("font.zig").KerxPairInfo;
pub const KerxSubtableInfo = @import("font.zig").KerxSubtableInfo;
pub const MorxChainInfo = @import("font.zig").MorxChainInfo;
pub const MorxFeatureInfo = @import("font.zig").MorxFeatureInfo;
pub const MorxInfo = @import("font.zig").MorxInfo;
pub const MorxSubtableInfo = @import("font.zig").MorxSubtableInfo;
pub const KernTableDialect = @import("font.zig").KernTableDialect;
pub const GdefMetadataCache = @import("layout.zig").GdefMetadataCache;
pub const GposTableProofCache = @import("layout.zig").GposTableProofCache;
pub const GlyphIndexCache = @import("layout.zig").GlyphIndexCache;
pub const GlyphMetrics = @import("layout.zig").GlyphMetrics;
pub const GlyphMetricsCache = @import("layout.zig").GlyphMetricsCache;
pub const LookupSelectionCache = @import("layout.zig").LookupSelectionCache;
pub const GsubTableProofCache = @import("layout.zig").GsubTableProofCache;
pub const MissingGlyphDiagnostic = @import("layout.zig").MissingGlyphDiagnostic;
pub const DirtyRange = @import("buffer.zig").DirtyRange;
pub const LayoutConfig = @import("buffer.zig").LayoutConfig;
pub const Selection = @import("buffer.zig").Selection;
pub const CursorMoveDirection = @import("buffer.zig").CursorMoveDirection;
pub const VisibleByteRange = @import("buffer.zig").VisibleByteRange;
pub const VisibleLineRange = @import("buffer.zig").VisibleLineRange;
pub const TextBuffer = @import("buffer.zig").TextBuffer;
pub const TextEditor = @import("editor.zig").TextEditor;
pub const BitmapGlyphPng = @import("font.zig").BitmapGlyphPng;
pub const BitmapGlyphInfo = @import("font.zig").BitmapGlyphInfo;
pub const BitmapStrikeInfo = @import("font.zig").BitmapStrikeInfo;
pub const BitmapStrikeSource = @import("font.zig").BitmapStrikeSource;
pub const ColorLayer = @import("font.zig").ColorLayer;
pub const ColorPaint = @import("font.zig").ColorPaint;
pub const ColorClipBox = @import("font.zig").ColorClipBox;
pub const ColorAffine = @import("font.zig").ColorAffine;
pub const ColorGlyphPaint = @import("render_bridge.zig").ColorGlyphPaint;
pub const PaletteColor = @import("font.zig").PaletteColor;
pub const PaletteInfo = @import("font.zig").PaletteInfo;
pub const PcltInfo = @import("font.zig").PcltInfo;
pub const PostInfo = @import("font.zig").PostInfo;
pub const SvgGlyphDocument = @import("font.zig").SvgGlyphDocument;
pub const ResolvedSvgGlyphDocument = @import("font.zig").ResolvedSvgGlyphDocument;
pub const StatAxisValue = @import("font.zig").StatAxisValue;
pub const StatAxisValueCoordinate = @import("font.zig").StatAxisValueCoordinate;
pub const StatDesignAxis = @import("font.zig").StatDesignAxis;
pub const VariationAxis = @import("font.zig").VariationAxis;
pub const VariationCoordinate = @import("font.zig").VariationCoordinate;
pub const VariationInstance = @import("font.zig").VariationInstance;
pub const VariationSequenceKind = @import("font.zig").VariationSequenceKind;
pub const VerticalMetrics = @import("font.zig").VerticalMetrics;
pub const GlyphId = @import("glyph.zig").GlyphId;
pub const GlyphLocationInfo = @import("font.zig").GlyphLocationInfo;
pub const Bounds = @import("glyph.zig").Bounds;
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
pub const GlyphAtlasContent = @import("render_bridge.zig").GlyphAtlasContent;
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
pub const ReflowBuffer = @import("layout.zig").ReflowBuffer;
pub const ShapedParagraph = @import("layout.zig").ShapedParagraph;
pub const PositionedGlyph = @import("render_bridge.zig").PositionedGlyph;
pub const PositionedAttributedRun = @import("core.zig").PositionedAttributedRun;
pub const ScriptPosition = @import("layout.zig").ScriptPosition;
pub const ShapeOptions = @import("layout.zig").ShapeOptions;
pub const ShapeStageProfile = @import("shape_profile.zig").ShapeStageProfile;
pub const ShapePlan = @import("layout.zig").ShapePlan;
pub const ShapePlanCache = @import("layout.zig").ShapePlanCache;
pub const ShapePlanKey = @import("layout.zig").ShapePlanKey;
pub const ClusterCaretConsistencyReport = @import("layout.zig").ClusterCaretConsistencyReport;
pub const ClusterCaretDiagnostic = @import("layout.zig").ClusterCaretDiagnostic;
pub const ClusterCaretIssueKind = @import("layout.zig").ClusterCaretIssueKind;
pub const ShapeQualityFontRunDiagnostic = @import("layout.zig").ShapeQualityFontRunDiagnostic;
pub const ShapeQualityReport = @import("layout.zig").ShapeQualityReport;
pub const ShapeQualityScriptRunDiagnostic = @import("layout.zig").ShapeQualityScriptRunDiagnostic;
pub const ShapedRunCache = @import("layout.zig").ShapedRunCache;
pub const ShapedRunCacheEntry = @import("layout.zig").ShapedRunCacheEntry;
pub const ShapedRunCacheKey = @import("layout.zig").ShapedRunCacheKey;
pub const ShapedText = @import("layout.zig").ShapedText;
pub const ScriptedRun = @import("layout.zig").ScriptedRun;
pub const ScriptedText = @import("layout.zig").ScriptedText;
pub const TextAlign = @import("layout.zig").TextAlign;
pub const TextCursorGeometry = @import("render_bridge.zig").TextCursorGeometry;
pub const TextDirection = @import("layout.zig").TextDirection;
pub const TextOrientation = @import("layout.zig").TextOrientation;
pub const WritingMode = @import("layout.zig").WritingMode;
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
pub const diagnoseClusterCaretConsistencyUtf8 = @import("layout.zig").diagnoseClusterCaretConsistencyUtf8;
pub const diagnoseFontFallbackUtf8 = @import("layout.zig").diagnoseFontFallbackUtf8;
pub const diagnoseShapeQualityUtf8 = @import("layout.zig").diagnoseShapeQualityUtf8;
pub const inferOpenTypeLanguageTag = @import("unicode.zig").inferOpenTypeLanguageTag;
pub const lineBreakClassForCodepoint = @import("unicode.zig").lineBreakClassForCodepoint;
pub const lineBreaks = @import("unicode.zig").lineBreaks;
pub const openTypeLanguageTagForLocale = @import("unicode.zig").openTypeLanguageTagForLocale;
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
pub const openTypeScriptHorizontalDirection = @import("unicode.zig").openTypeScriptHorizontalDirection;
pub const paragraphDirection = @import("unicode.zig").paragraphDirection;
pub const joiningTypeForCodepoint = @import("unicode.zig").joiningTypeForCodepoint;
pub const resolveJoiningForms = @import("unicode.zig").resolveJoiningForms;
pub const verticalOrientationForCodepoint = @import("unicode.zig").verticalOrientationForCodepoint;
pub const scriptForCodepoint = @import("unicode.zig").scriptForCodepoint;
pub const mirroredCodepoint = @import("unicode.zig").mirroredCodepoint;
pub const visualOrderBidiRuns = @import("unicode.zig").visualOrderBidiRuns;
pub const visualOrderCodepoints = @import("unicode.zig").visualOrderCodepoints;
pub const visualOrderUtf8 = @import("unicode.zig").visualOrderUtf8;
pub const ColorRenderTarget = @import("raster.zig").ColorRenderTarget;
pub const PreparedGlyph = @import("raster.zig").PreparedGlyph;
pub const RenderTarget = @import("raster.zig").RenderTarget;
pub const Rgba = @import("raster.zig").Rgba;
pub const Rasterizer = @import("raster.zig").Rasterizer;
pub const bidiClassForCodepoint = @import("unicode.zig").bidiClassForCodepoint;
pub const testing = struct {
    pub const test_font = @import("test_font.zig");
    pub const font_container = @import("font_container.zig").testing;
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

    const header = try font.headInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), header.table_version);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), header.font_revision, 0.001);
    try std.testing.expectEqual(@as(u16, 1000), header.units_per_em);
    try std.testing.expectEqual(Bounds{ .x_min = 0, .y_min = 0, .x_max = 700, .y_max = 700 }, header.bounds);
    try std.testing.expectEqual(@as(u16, 8), header.lowest_rec_ppem);
    try std.testing.expectEqual(@as(i16, 0), header.index_to_loc_format);

    const maxp = try font.maxpInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), maxp.version);
    try std.testing.expectEqual(@as(u16, 2), maxp.glyph_count);
    try std.testing.expectEqual(@as(?u16, 3), maxp.max_points);
    try std.testing.expectEqual(@as(?u16, 1), maxp.max_contours);
    try std.testing.expectEqual(@as(?u16, 2), maxp.max_zones);
    try std.testing.expectEqual(@as(?u16, 0), maxp.max_component_depth);

    const hhea = try font.horizontalHeaderInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), hhea.version);
    try std.testing.expectEqual(@as(i16, 800), hhea.ascender);
    try std.testing.expectEqual(@as(i16, -200), hhea.descender);
    try std.testing.expectEqual(@as(i16, 0), hhea.line_gap);
    try std.testing.expectEqual(@as(u16, 2), hhea.long_metric_count);
    try std.testing.expect((try font.verticalHeaderInfo()) == null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    try std.testing.expect(tables.len >= 6);
    var saw_head = false;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "head")) {
            saw_head = true;
            try std.testing.expect(table.length >= 54);
        }
    }
    try std.testing.expect(saw_head);

    var hhea_info: ?FontTableInfo = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hhea")) hhea_info = table;
    }
    const hhea_record = hhea_info orelse return error.MissingTable;
    const hhea_data = (try font.tableData(.{ 'h', 'h', 'e', 'a' })).?;
    try std.testing.expectEqual(hhea_record.length, hhea_data.len);
    try std.testing.expectEqualSlices(u8, bytes[hhea_record.offset .. hhea_record.offset + hhea_record.length], hhea_data);
    try std.testing.expect((try font.tableData(.{ 'N', 'O', 'P', 'E' })) == null);

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 1), charmaps.len);
    try std.testing.expectEqual(@as(u16, 3), charmaps[0].platform_id);
    try std.testing.expectEqual(@as(u16, 1), charmaps[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 4), charmaps[0].format);
    try std.testing.expectEqual(@as(?u32, 0), charmaps[0].language);

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(charmaps[0], default_charmap);
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'A', .glyph_id = 1 }), (try font.firstCharmapMapping(default_charmap)).?);
    try std.testing.expect((try font.nextCharmapMapping(default_charmap, 'A')) == null);

    const hmetrics = try font.horizontalMetricsTable(allocator);
    defer allocator.free(hmetrics);
    try std.testing.expectEqual(@as(usize, 2), hmetrics.len);
    try std.testing.expectEqual(HorizontalMetricInfo{ .advance_width = 500, .left_side_bearing = 0 }, hmetrics[0]);
    try std.testing.expectEqual(HorizontalMetricInfo{ .advance_width = 800, .left_side_bearing = 0 }, hmetrics[1]);
    try std.testing.expect((try font.verticalMetricsTable(allocator)) == null);

    const locations = try font.glyphLocations(allocator);
    defer allocator.free(locations);
    try std.testing.expectEqual(@as(usize, 2), locations.len);
    try std.testing.expectEqual(@as(GlyphId, 0), locations[0].glyph_id);
    try std.testing.expect(locations[0].length > 0);
    try std.testing.expect(!locations[0].empty);
    try std.testing.expectEqual(@as(GlyphId, 1), locations[1].glyph_id);
    try std.testing.expect(locations[1].length > 0);
    try std.testing.expect(!locations[1].empty);

    var outline = try font.glyphOutline(allocator, 1);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(u16, 800), outline.advance_width);
    const bounds = try font.glyphBounds(1);
    try std.testing.expectEqual(outline.bounds, bounds);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), run.width(), 0.001);

    const kerned = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), kerned.width(), 0.001);

    const disable_kern = [_]FeatureOverride{.{ .tag = openTypeTag("kern"), .enabled = false }};
    const unkerned = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "AA", 20, .{ .features = &disable_kern });
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), unkerned.width(), 0.001);

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

test "VORG vertical origins are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVorgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const origins = (try font.verticalOrigins(allocator)).?;
    defer font.freeVerticalOrigins(allocator, origins);
    try std.testing.expectEqual(@as(i16, 880), origins.default_origin_y);
    try std.testing.expectEqual(@as(usize, 1), origins.metrics.len);
    try std.testing.expectEqual(VerticalOriginMetric{ .glyph_id = 1, .origin_y = 910 }, origins.metrics[0]);

    try std.testing.expectEqual(@as(?i16, 880), try font.verticalOriginY(0));
    try std.testing.expectEqual(@as(?i16, 910), try font.verticalOriginY(1));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.verticalOrigins(allocator)) == null);
    try std.testing.expect((try missing.verticalOriginY(1)) == null);
}

test "lazy VORG metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVorgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?i16, 910), try font.verticalOriginY(1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var vorg_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "VORG")) vorg_offset = table.offset;
    }
    bytes[vorg_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.verticalOriginY(1));
    try std.testing.expectError(error.BadSfnt, font.verticalOrigins(allocator));
}

test "vertical header metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const vhea = (try font.verticalHeaderInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00011000), vhea.version);
    try std.testing.expectEqual(@as(i16, 800), vhea.ascender);
    try std.testing.expectEqual(@as(i16, -200), vhea.descender);
    try std.testing.expectEqual(@as(u16, 1), vhea.long_metric_count);

    const vmetrics = (try font.verticalMetricsTable(allocator)).?;
    defer allocator.free(vmetrics);
    try std.testing.expectEqual(@as(usize, 2), vmetrics.len);
    try std.testing.expectEqual(VerticalMetricInfo{ .advance_height = 1000, .top_side_bearing = 0 }, vmetrics[0]);
    try std.testing.expectEqual(VerticalMetricInfo{ .advance_height = 1000, .top_side_bearing = 0 }, vmetrics[1]);
}

test "CFF2 top-level metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.cff2Info()).?;
    try std.testing.expectEqual(@as(u8, 2), info.major_version);
    try std.testing.expectEqual(@as(u8, 0), info.minor_version);
    try std.testing.expectEqual(@as(u8, 5), info.header_size);
    try std.testing.expectEqual(@as(u16, 10), info.top_dict_length);
    const global_subrs = info.global_subrs_index;
    try std.testing.expectEqual(@as(usize, 15), global_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), global_subrs.count);
    try std.testing.expectEqual(@as(u8, 1), global_subrs.off_size);
    try std.testing.expectEqual(@as(usize, 22), global_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), global_subrs.data_length);
    try std.testing.expectEqual(@as(?usize, 23), info.top_dict.charstrings_offset);
    try std.testing.expectEqual(@as(?usize, 43), info.top_dict.fd_array_offset);
    try std.testing.expectEqual(@as(?usize, 53), info.top_dict.fd_select_offset);
    try std.testing.expectEqual(@as(?usize, 70), info.top_dict.vstore_offset);
    const charstrings = info.charstrings_index.?;
    try std.testing.expectEqual(@as(u32, 1), charstrings.count);
    try std.testing.expectEqual(@as(u8, 1), charstrings.off_size);
    try std.testing.expectEqual(@as(usize, 30), charstrings.data_offset);
    try std.testing.expectEqual(@as(usize, 13), charstrings.data_length);
    const fd_array = info.fd_array_index.?;
    try std.testing.expectEqual(@as(u32, 1), fd_array.count);
    try std.testing.expectEqual(@as(usize, 50), fd_array.data_offset);
    try std.testing.expectEqual(@as(usize, 3), fd_array.data_length);
    const fd_select = info.fd_select.?;
    try std.testing.expectEqual(@as(usize, 53), fd_select.offset);
    try std.testing.expectEqual(@as(u8, 0), fd_select.format);
    try std.testing.expectEqual(@as(?u16, 0), try font.cff2FontDictIndex(0));
    try std.testing.expectEqual(@as(?u16, 0), try font.cff2FontDictIndex(1));
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2GlobalSubrData(0)).?);
    try std.testing.expect((try font.cff2GlobalSubrData(1)) == null);
    const font_dict = (try font.cff2FontDictInfo(0)).?;
    try std.testing.expectEqual(@as(usize, 0), font_dict.index);
    try std.testing.expectEqual(@as(usize, 50), font_dict.data_offset);
    try std.testing.expectEqual(@as(usize, 3), font_dict.data_length);
    const private = font_dict.private_dict;
    try std.testing.expectEqual(@as(usize, 56), private.offset);
    try std.testing.expectEqual(@as(usize, 6), private.size);
    try std.testing.expectEqualSlices(u8, &.{ 146, 20, 119, 21, 145, 19 }, private.data);
    try std.testing.expectEqual(@as(?i32, 7), private.default_width_x);
    try std.testing.expectEqual(@as(?i32, -20), private.nominal_width_x);
    try std.testing.expectEqual(@as(?usize, 62), private.local_subrs_offset);
    const local_subrs = private.local_subrs_index.?;
    try std.testing.expectEqual(@as(usize, 62), local_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), local_subrs.count);
    try std.testing.expectEqual(@as(usize, 69), local_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), local_subrs.data_length);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2LocalSubrData(0, 0)).?);
    try std.testing.expect((try font.cff2LocalSubrData(0, 1)) == null);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2GlobalSubrDataForOperand(-107)).?);
    try std.testing.expect((try font.cff2GlobalSubrDataForOperand(-106)) == null);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2LocalSubrDataForOperand(0, -107)).?);
    try std.testing.expect((try font.cff2LocalSubrDataForOperand(0, -106)) == null);
    try std.testing.expect((try font.cff2FontDictInfo(1)) == null);
    try std.testing.expectEqualSlices(u8, &.{ 32, 10, 32, 29, 189, 159, 21, 239, 139, 139, 169, 5, 14 }, (try font.cff2CharStringData(0)).?);
    const scanned = (try font.cff2CharStringScanInfo(0)).?;
    try std.testing.expectEqual(@as(usize, 3), scanned.charstring_count);
    try std.testing.expectEqual(@as(usize, 15), scanned.byte_count);
    try std.testing.expectEqual(@as(usize, 8), scanned.number_count);
    try std.testing.expectEqual(@as(usize, 7), scanned.operator_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.global_subr_call_count);
    try std.testing.expectEqual(@as(u8, 1), scanned.max_depth);
    try std.testing.expect(scanned.has_return);
    try std.testing.expect(scanned.has_endchar);
    const bounds = (try font.cff2CharStringBoundsInfo(0)).?;
    try std.testing.expect(bounds.has_bounds);
    try std.testing.expectEqual(@as(f32, 50), bounds.x_min);
    try std.testing.expectEqual(@as(f32, 20), bounds.y_min);
    try std.testing.expectEqual(@as(f32, 150), bounds.x_max);
    try std.testing.expectEqual(@as(f32, 50), bounds.y_max);
    try std.testing.expectEqual(@as(usize, 1), bounds.move_count);
    try std.testing.expectEqual(@as(usize, 2), bounds.line_count);
    try std.testing.expectEqual(@as(usize, 0), bounds.curve_count);
    try std.testing.expectEqual(@as(usize, 3), bounds.scan.charstring_count);
    try std.testing.expectEqual(@as(usize, 1), bounds.scan.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), bounds.scan.global_subr_call_count);
    const bounds_at_coords = (try font.cff2CharStringBoundsInfoAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 50), bounds_at_coords.x_min);
    try std.testing.expectEqual(@as(f32, 150), bounds_at_coords.x_max);
    const glyph_bounds_at_coords = (try font.cff2GlyphBoundsAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(i16, 50), glyph_bounds_at_coords.x_min);
    try std.testing.expectEqual(@as(i16, 150), glyph_bounds_at_coords.x_max);
    try std.testing.expectError(error.BadSfnt, font.cff2CharStringBoundsInfoAtCoords(0, &.{std.math.nan(f32)}));
    try std.testing.expectError(error.BadSfnt, font.cff2CharStringBoundsInfoAtCoords(0, &.{1.0001}));
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphBoundsAtCoords(0, &.{std.math.inf(f32)}));
    const public_bounds = try font.glyphBounds(0);
    try std.testing.expectEqual(@as(i16, 50), public_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), public_bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), public_bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), public_bounds.y_max);
    var outline = try font.glyphOutline(allocator, 0);
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), outline.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), outline.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.y_max);
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 20), outline.commands.items[0].move_to.y);
    try std.testing.expectEqual(@as(f32, 150), outline.commands.items[1].line_to.x);
    try std.testing.expectEqual(@as(f32, 20), outline.commands.items[1].line_to.y);
    try std.testing.expectEqual(@as(f32, 150), outline.commands.items[2].line_to.x);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[2].line_to.y);
    try std.testing.expectEqual(.close, outline.commands.items[3]);
    var outline_at_coords = (try font.cff2GlyphOutlineAtCoords(allocator, 0, &.{0.5})).?;
    defer outline_at_coords.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline_at_coords.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 150), outline_at_coords.bounds.x_max);
    try std.testing.expectEqual(@as(usize, 4), outline_at_coords.commands.items.len);
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphOutlineAtCoords(allocator, 0, &.{std.math.inf(f32)}));
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphOutlineAtCoords(allocator, 0, &.{-1.0001}));
    try std.testing.expect((try font.cff2CharStringData(1)) == null);
    try std.testing.expect((try font.cff2CharStringScanInfo(1)) == null);
    try std.testing.expect((try font.cff2CharStringBoundsInfo(1)) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.cff2Info()) == null);
    try std.testing.expect((try missing.cff2GlobalSubrData(0)) == null);
    try std.testing.expect((try missing.cff2GlobalSubrDataForOperand(-107)) == null);
    try std.testing.expect((try missing.cff2FontDictInfo(0)) == null);
    try std.testing.expect((try missing.cff2LocalSubrData(0, 0)) == null);
    try std.testing.expect((try missing.cff2LocalSubrDataForOperand(0, -107)) == null);
    try std.testing.expect((try missing.cff2CharStringData(1)) == null);
    try std.testing.expect((try missing.cff2CharStringScanInfo(1)) == null);
    try std.testing.expect((try missing.cff2CharStringBoundsInfo(1)) == null);
    try std.testing.expect((try missing.cff2CharStringBoundsInfoAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2GlyphBoundsAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2GlyphOutlineAtCoords(allocator, 1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2FontDictIndex(1)) == null);
}

test "CFF2 variation outline changes with normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_bounds = (try font.cff2GlyphBoundsAtCoords(0, &.{})).?;
    try std.testing.expectEqual(@as(i16, 50), default_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 60), default_bounds.x_max);
    const varied_bounds = (try font.cff2GlyphBoundsAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(i16, 60), varied_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), varied_bounds.x_max);
    const generic_varied_bounds = try font.glyphBoundsAtCoords(0, &.{0.5});
    try std.testing.expectEqual(@as(i16, 60), generic_varied_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), generic_varied_bounds.x_max);

    var outline = (try font.cff2GlyphOutlineAtCoords(allocator, 0, &.{0.5})).?;
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 3), outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), outline.commands.items[1].line_to.x);
    var generic_outline = try font.glyphOutlineAtCoords(allocator, 0, &.{0.5});
    defer generic_outline.deinit();
    try std.testing.expectEqual(@as(f32, 60), generic_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), generic_outline.commands.items[1].line_to.x);
}

test "gvar metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gvarInfo()).?;
    try std.testing.expectEqual(@as(u16, 1), info.major_version);
    try std.testing.expectEqual(@as(u16, 0), info.minor_version);
    try std.testing.expectEqual(@as(u16, 1), info.axis_count);
    try std.testing.expectEqual(@as(u16, 2), info.glyph_count);
    try std.testing.expectEqual(@as(u8, 2), info.offset_size);
    try std.testing.expectEqual(@as(usize, 0), info.glyph_variation_data_count);
    try std.testing.expect((try font.gvarGlyphInfo(0)) == null);
    try std.testing.expect((try font.gvarTupleInfo(0, 0)) == null);
    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 0), deltas.len);
    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied_outline.deinit();
    try std.testing.expectEqual(default_outline.bounds, varied_outline.bounds);
    try std.testing.expectEqual(default_outline.advance_width, varied_outline.advance_width);
    try std.testing.expectEqual(@as(usize, default_outline.commands.items.len), varied_outline.commands.items.len);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.gvarInfo()) == null);
    try std.testing.expect((try missing.gvarGlyphInfo(0)) == null);
    try std.testing.expect((try missing.gvarTupleInfo(0, 0)) == null);
    try std.testing.expect((try missing.gvarPointDeltasAtCoords(allocator, 0, &.{0.5})) == null);
    try std.testing.expect((try missing.gvarPhantomPointDeltasAtCoords(allocator, 0, &.{0.5})) == null);
    try std.testing.expect((try missing.gvarGlyphBoundsAtCoords(allocator, 0, &.{0.5})) == null);
}

test "gvar point deltas are exposed for non-empty glyph data" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gvarInfo()).?;
    try std.testing.expectEqual(@as(usize, 1), info.glyph_variation_data_count);
    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 7), deltas.len);
    try std.testing.expectEqual(@as(u16, 0), deltas[0].point);
    try std.testing.expectEqual(@as(f32, 5), deltas[0].x);
    try std.testing.expectEqual(@as(f32, 0), deltas[0].y);
    try std.testing.expectEqual(@as(f32, 1), deltas[3].x);
    try std.testing.expectEqual(@as(f32, 10), deltas[4].x);
    try std.testing.expectEqual(@as(f32, 4), deltas[5].y);
    try std.testing.expectEqual(@as(f32, -2), deltas[6].y);
    try std.testing.expectEqual(@as(u16, 6), deltas[6].point);
    try std.testing.expectEqual(@as(f32, 0), deltas[6].x);

    const phantom = (try font.gvarPhantomPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 1), phantom.left.x);
    try std.testing.expectEqual(@as(f32, 10), phantom.right.x);
    try std.testing.expectEqual(@as(f32, 9), phantom.horizontalAdvanceDelta());
    try std.testing.expectEqual(@as(f32, 4), phantom.top.y);
    try std.testing.expectEqual(@as(f32, -2), phantom.bottom.y);
    try std.testing.expectEqual(@as(f32, 6), phantom.verticalAdvanceDelta());

    const varied_metrics = try font.horizontalMetricsAtCoords(1, &.{0.5});
    try std.testing.expectEqual(@as(u16, 809), varied_metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 1), varied_metrics.left_side_bearing);

    const varied_bounds = (try font.gvarGlyphBoundsAtCoords(allocator, 1, &.{0.5})).?;
    const default_bounds = try font.glyphBounds(1);
    try std.testing.expectEqual(default_bounds.x_min + 5, varied_bounds.x_min);

    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied_outline.deinit();
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 5), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[1].line_to.x + 5), varied_outline.commands.items[1].line_to.x);
    try std.testing.expectEqual(default_outline.bounds.x_min + 5, varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(u16, 809), varied_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 4), varied_outline.left_side_bearing);
}

test "gvar compound glyph deltas adjust component offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 2, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 5), deltas.len);
    try std.testing.expectEqual(@as(f32, 10), deltas[0].x);
    try std.testing.expectEqual(@as(f32, 9), deltas[2].x);

    const phantom = (try font.gvarPhantomPointDeltasAtCoords(allocator, 2, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 9), phantom.horizontalAdvanceDelta());
    const varied_metrics = try font.horizontalMetricsAtCoords(2, &.{0.5});
    try std.testing.expectEqual(@as(u16, 1009), varied_metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 0), varied_metrics.left_side_bearing);

    var default_outline = try font.glyphOutline(allocator, 2);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 2, &.{0.5});
    defer varied_outline.deinit();

    // Compound `gvar` point deltas apply to component placement, not to contour
    // IUP. The fixture's only component moves +10 design units at coord 0.5.
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 10), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 720), varied_outline.bounds.x_max);
    try std.testing.expectEqual(@as(u16, 1009), varied_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.left_side_bearing);

    const varied_bounds = (try font.gvarGlyphBoundsAtCoords(allocator, 2, &.{0.5})).?;
    try std.testing.expectEqual(varied_outline.bounds, varied_bounds);
}

test "compound glyph point matching preserves raw off-curve indexes and nesting" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCompoundPointMatchTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var matched = try font.glyphOutline(allocator, 2);
    defer matched.deinit();
    try std.testing.expectEqual(@as(usize, 6), matched.commands.items.len);
    try std.testing.expectEqual(@as(f32, 10), matched.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 110), matched.commands.items[1].quad_to.control.x);
    try std.testing.expectEqual(@as(f32, 100), matched.commands.items[1].quad_to.control.y);
    try std.testing.expectEqual(@as(f32, 60), matched.commands.items[3].move_to.x);
    try std.testing.expectEqual(@as(f32, 50), matched.commands.items[3].move_to.y);
    // The two off-curve raw point 1 anchors coincide after the second
    // component's 0.5 linear transform and point-derived translation.
    try std.testing.expectEqual(matched.commands.items[1].quad_to.control, matched.commands.items[4].quad_to.control);

    var nested = try font.glyphOutline(allocator, 3);
    defer nested.deinit();
    try std.testing.expectEqual(@as(usize, 9), nested.commands.items.len);
    // Parent point 4 is relative to nested glyph 2, not to the top-level
    // scratch buffer. It anchors the third contour's raw origin at (110, 100).
    try std.testing.expectEqual(@as(f32, 110), nested.commands.items[6].move_to.x);
    try std.testing.expectEqual(@as(f32, 100), nested.commands.items[6].move_to.y);
    try std.testing.expectEqual(@as(f32, 210), nested.commands.items[7].quad_to.control.x);
    try std.testing.expectEqual(@as(f32, 200), nested.commands.items[7].quad_to.control.y);
}

test "gvar ignores component deltas for point-matched placement" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarPointMatchTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_outline = try font.glyphOutline(allocator, 4);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 4, &.{0.5});
    defer varied_outline.deinit();

    // At coord 0.5 component 0's +20 peak delta becomes +10. The anchor point
    // therefore moves +10 and carries component 1 with it. Component 1 also has
    // a deliberately non-zero +50 peak delta; applying it would add another
    // +25 and break the point match, so all corresponding commands must differ
    // by exactly the first component's +10.
    try std.testing.expectEqual(default_outline.commands.items.len, varied_outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 10), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[3].move_to.x + 10), varied_outline.commands.items[3].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[4].quad_to.control.x + 10), varied_outline.commands.items[4].quad_to.control.x);
    try std.testing.expectEqual(varied_outline.commands.items[1].quad_to.control, varied_outline.commands.items[3].move_to);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 220), varied_outline.bounds.x_max);
}

test "rasterizer renders variable outlines at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]GlyphPosition{.{
        .glyph_id = 2,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 1,
        .x_advance = 200,
    }};
    const run = GlyphRun{ .font = &font, .font_size = 200, .glyphs = &glyphs };

    var default_target = try RenderTarget.init(allocator, 220, 220);
    defer default_target.deinit();
    var varied_target = try RenderTarget.init(allocator, 220, 220);
    defer varied_target.deinit();

    var rasterizer = Rasterizer.init(allocator);
    rasterizer.hint_size_px = 200;
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderRun(&default_target, run, 20, 180);
    try rasterizer.renderRunAtCoords(&varied_target, run, 20, 180, &.{0.5});

    try std.testing.expect(renderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "color rasterizer renders variable outlines at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_target = try ColorRenderTarget.init(allocator, 220, 220);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 220, 220);
    defer varied_target.deinit();

    var rasterizer = Rasterizer.init(allocator);
    rasterizer.hint_size_px = 200;
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderColorGlyph(&default_target, &font, 2, 200, 20, 180, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 2, 200, 20, 180, 0, &.{0.5});

    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

fn renderTargetPixelDifference(a: *const RenderTarget, b: *const RenderTarget) usize {
    if (a.width != b.width or a.height != b.height or a.pixels.len != b.pixels.len) return std.math.maxInt(usize);
    var diff: usize = 0;
    for (a.pixels, b.pixels) |lhs, rhs| {
        if (lhs != rhs) diff += 1;
    }
    return diff;
}

fn colorRenderTargetPixelDifference(a: *const ColorRenderTarget, b: *const ColorRenderTarget) usize {
    if (a.width != b.width or a.height != b.height or a.pixels.len != b.pixels.len) return std.math.maxInt(usize);
    var diff: usize = 0;
    for (a.pixels, b.pixels) |lhs, rhs| {
        if (lhs.r != rhs.r or lhs.g != rhs.g or lhs.b != rhs.b or lhs.a != rhs.a) diff += 1;
    }
    return diff;
}

test "lazy gvar metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.gvarInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.gvarInfo());
}

test "generic glyph at-coords APIs validate coordinates and fall back" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const bounds = try font.glyphBoundsAtCoords(1, &.{0.5});
    try std.testing.expectEqual(@as(i16, 0), bounds.x_min);
    var outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expect(outline.commands.items.len != 0);
    try std.testing.expectError(error.BadSfnt, font.glyphBoundsAtCoords(1, &.{std.math.nan(f32)}));
    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{1.0001}));
}

test "lazy CFF2 metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.cff2Info()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_offset = table.offset;
    }
    bytes[cff2_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.cff2Info());
}

test "CFF2 raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    // Mutate a trailing CFF2 byte that invalidates the table checksum without
    // touching the already-validated CharStrings/FD data used by the parsed-font
    // raster fast path.
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 0));
    var outline = try font.glyphOutlineForRaster(allocator, 0);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), outline.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), outline.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.y_max);
}

test "CFF2 variation raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 0, &.{0.5}));
    var outline = try font.glyphOutlineForRasterAtCoords(allocator, 0, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 60), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), outline.bounds.x_max);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), outline.commands.items[1].line_to.x);
}

test "CFF2 default variation raster outline skips variation table reread" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 0, &.{0.5}));
    var outline = try font.glyphOutlineForRasterAtCoords(allocator, 0, &.{0.0});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 60), outline.bounds.x_max);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[1].line_to.x);
}

test "gvar raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font.glyphOutlineForRasterAtCoords(allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 5), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 5), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 809), outline.advance_width);
}

test "gvar default raster outline skips gvar reread" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font.glyphOutlineForRasterAtCoords(allocator, 1, &.{0.0});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 0), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 0), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 800), outline.advance_width);
}

test "gvar raster outline reuses parsed fvar axis count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var fvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "fvar")) fvar_offset = table.offset;
    }

    // The parsed-font raster path should not re-read the fvar header on every
    // glyph. Mutating axisCount after parse makes defensive public APIs reject
    // the now-inconsistent borrowed bytes, while the raster fast path continues
    // to use the parse-time axis count paired with the already-validated gvar.
    writeU16Test(bytes, (fvar_offset orelse return error.MissingTable) + 8, 2);

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font.glyphOutlineForRasterAtCoords(allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 5), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 5), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 809), outline.advance_width);
}

test "MATH constants metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    try std.testing.expectEqual(KerxPairInfo{ .left = 0, .right = 1, .value = -30 }, info.subtables[0].pairs[1]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.kerxInfo(allocator)) == null);
}

test "lazy AAT kerx metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

test "shaping applies normalized variation metric coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    try std.testing.expectEqual(@as(usize, 2), shaped_cache.entries.items.len);
    try std.testing.expectEqual(@as(usize, 1), shaped_cache.hits);
}

test "lazy HVAR and VVAR metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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

test "MVAR value records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.mvarInfo(allocator)).?;
    defer font.freeMvarInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(u16, 8), info.value_record_size);
    try std.testing.expectEqual(@as(?usize, 28), info.item_variation_store_offset);
    try std.testing.expectEqual(@as(usize, 2), info.value_records.len);
    try std.testing.expectEqual(MvarValueRecordInfo{
        .value_tag = .{ 'h', 'a', 's', 'c' },
        .delta_set_outer_index = 0,
        .delta_set_inner_index = 0,
    }, info.value_records[0]);
    try std.testing.expect(info.value_records[0].hasVariationData());
    try std.testing.expectEqualStrings("hdsc", &info.value_records[1].value_tag);
    try std.testing.expectEqual(@as(u16, 0xffff), info.value_records[1].delta_set_outer_index);
    try std.testing.expectEqual(@as(u16, 0xffff), info.value_records[1].delta_set_inner_index);
    try std.testing.expect(!info.value_records[1].hasVariationData());

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.mvarInfo(allocator)) == null);
}

test "lazy MVAR metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.mvarInfo(allocator)).?;
    defer font.freeMvarInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 2), info.value_records.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var mvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "MVAR")) mvar_offset = table.offset;
    }
    bytes[mvar_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.mvarInfo(allocator));
}

test "BASE baseline metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildBaseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.baseInfo(allocator)).?;
    defer font.freeBaseInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    const horizontal = info.horizontal.?;
    try std.testing.expectEqual(@as(usize, 2), horizontal.baseline_tags.len);
    try std.testing.expectEqualStrings("ideo", &horizontal.baseline_tags[0]);
    try std.testing.expectEqualStrings("romn", &horizontal.baseline_tags[1]);
    try std.testing.expectEqual(@as(usize, 1), horizontal.scripts.len);
    try std.testing.expectEqualStrings("latn", &horizontal.scripts[0].tag);
    try std.testing.expectEqual(@as(?u16, 1), horizontal.scripts[0].default_baseline_index);
    try std.testing.expectEqual(@as(?i16, 0), horizontal.scripts[0].coordinates[0]);
    try std.testing.expectEqual(@as(?i16, 500), horizontal.scripts[0].coordinates[1]);
    try std.testing.expect(info.vertical == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.baseInfo(allocator)) == null);
}

test "lazy BASE metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildBaseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.baseInfo(allocator)).?;
    defer font.freeBaseInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var base_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "BASE")) base_offset = table.offset;
    }
    bytes[base_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.baseInfo(allocator));
}

test "AAT trak records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildTrakTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.trakInfo(allocator)).?;
    defer font.freeTrakInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 1), info.horizontal.len);
    try std.testing.expectEqual(@as(usize, 0), info.vertical.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), info.horizontal[0].track, 0.001);
    try std.testing.expectEqual(@as(u16, 300), info.horizontal[0].name_id);
    try std.testing.expectEqual(@as(usize, 2), info.horizontal[0].values.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), info.horizontal[0].values[0].size, 0.001);
    try std.testing.expectEqual(@as(i16, -5), info.horizontal[0].values[0].value);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), info.horizontal[0].values[1].size, 0.001);
    try std.testing.expectEqual(@as(i16, 10), info.horizontal[0].values[1].value);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.trakInfo(allocator)) == null);
}

test "lazy AAT trak records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildTrakTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.trakInfo(allocator)).?;
    defer font.freeTrakInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 1), info.horizontal.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var trak_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "trak")) trak_offset = table.offset;
    }
    bytes[trak_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.trakInfo(allocator));
}

test "AAT feat records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildFeatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const features = try font.featFeatures(allocator);
    defer font.freeFeatFeatures(allocator, features);
    try std.testing.expectEqual(@as(usize, 1), features.len);
    try std.testing.expectEqual(@as(u16, 1), features[0].feature);
    try std.testing.expectEqual(@as(u16, 0x8000), features[0].flags);
    try std.testing.expectEqual(@as(u16, 300), features[0].name_id);
    try std.testing.expectEqual(@as(usize, 2), features[0].settings.len);
    try std.testing.expectEqual(FeatureSettingInfo{ .setting = 0, .name_id = 301 }, features[0].settings[0]);
    try std.testing.expectEqual(FeatureSettingInfo{ .setting = 1, .name_id = 302 }, features[0].settings[1]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.featFeatures(allocator);
    defer missing.freeFeatFeatures(allocator, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "lazy AAT feat records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildFeatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const features = try font.featFeatures(allocator);
    defer font.freeFeatFeatures(allocator, features);
    try std.testing.expectEqual(@as(usize, 1), features.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var feat_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "feat")) feat_offset = table.offset;
    }
    bytes[feat_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.featFeatures(allocator));
}

test "ltag records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildLtagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.ltagRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualStrings("zh-Hant", records[0].tag);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.ltagRecords(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "lazy ltag records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildLtagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const records = try font.ltagRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqualStrings("zh-Hant", records[0].tag);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ltag_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "ltag")) ltag_offset = table.offset;
    }
    bytes[ltag_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.ltagRecords(allocator));
}

test "LTSH thresholds are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildLtshTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.ltshInfo(allocator)).?;
    defer font.freeLtshInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 0), info.version);
    try std.testing.expectEqualSlices(u8, &.{ 7, 11 }, info.thresholds);

    try std.testing.expectEqual(@as(?u8, 7), try font.linearThreshold(0));
    try std.testing.expectEqual(@as(?u8, 11), try font.linearThreshold(1));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.ltshInfo(allocator)) == null);
    try std.testing.expect((try missing.linearThreshold(1)) == null);
}

test "lazy LTSH metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildLtshTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?u8, 11), try font.linearThreshold(1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ltsh_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "LTSH")) ltsh_offset = table.offset;
    }
    bytes[ltsh_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.linearThreshold(1));
    try std.testing.expectError(error.BadSfnt, font.ltshInfo(allocator));
}

test "hdmx metadata and widths are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildHdmxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.hdmxInfo(allocator)).?;
    defer font.freeHdmxInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 0), info.version);
    try std.testing.expectEqual(@as(u32, 4), info.record_size);
    try std.testing.expectEqual(@as(usize, 2), info.records.len);
    try std.testing.expectEqual(@as(u8, 10), info.records[0].ppem);
    try std.testing.expectEqual(@as(u8, 8), info.records[0].max_width);
    try std.testing.expectEqualSlices(u8, &.{ 5, 8 }, info.records[0].widths);
    try std.testing.expectEqualSlices(u8, &.{ 6, 12 }, info.records[1].widths);

    try std.testing.expectEqual(@as(?u8, 8), try font.hdmxWidth(10, 1));
    try std.testing.expectEqual(@as(?u8, 12), try font.hdmxWidth(16, 1));
    try std.testing.expect((try font.hdmxWidth(11, 1)) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.hdmxInfo(allocator)) == null);
    try std.testing.expect((try missing.hdmxWidth(10, 1)) == null);
}

test "lazy hdmx metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildHdmxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?u8, 8), try font.hdmxWidth(10, 1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var hdmx_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hdmx")) hdmx_offset = table.offset;
    }
    bytes[hdmx_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.hdmxWidth(10, 1));
    try std.testing.expectError(error.BadSfnt, font.hdmxInfo(allocator));
}

test "meta records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMetaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.metaRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualStrings("dlng", &records[0].tag);
    try std.testing.expectEqualStrings("latn", records[0].data);

    try std.testing.expectEqualStrings("latn", (try font.metaData(.{ 'd', 'l', 'n', 'g' })).?);
    try std.testing.expect((try font.metaData(.{ 's', 'l', 'n', 'g' })) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.metaRecords(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect((try missing.metaData(.{ 'd', 'l', 'n', 'g' })) == null);
}

test "lazy meta records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMetaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqualStrings("latn", (try font.metaData(.{ 'd', 'l', 'n', 'g' })).?);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var meta_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "meta")) meta_offset = table.offset;
    }
    bytes[meta_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.metaData(.{ 'd', 'l', 'n', 'g' }));
    try std.testing.expectError(error.BadSfnt, font.metaRecords(allocator));
}

test "DSIG metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildDsigTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.dsigInfo(allocator)).?;
    defer font.freeDsigInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 1), info.version);
    try std.testing.expectEqual(@as(u16, 1), info.flags);
    try std.testing.expectEqual(@as(usize, 1), info.signatures.len);
    try std.testing.expectEqual(@as(u32, 1), info.signatures[0].format);
    try std.testing.expectEqualStrings("sig", info.signatures[0].signature);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.dsigInfo(allocator)) == null);
}

test "lazy DSIG metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildDsigTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const initial = (try font.dsigInfo(allocator)).?;
    defer font.freeDsigInfo(allocator, initial);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var dsig_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "DSIG")) dsig_offset = table.offset;
    }
    bytes[dsig_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.dsigInfo(allocator));
}

test "gasp metadata and PPEM behavior are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGaspTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gaspInfo(allocator)).?;
    defer font.freeGaspInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 1), info.version);
    try std.testing.expectEqual(@as(usize, 2), info.ranges.len);
    try std.testing.expectEqual(GaspRange{ .max_ppem = 8, .behavior = 0x0003 }, info.ranges[0]);
    try std.testing.expectEqual(GaspRange{ .max_ppem = 0xffff, .behavior = 0x000f }, info.ranges[1]);

    try std.testing.expectEqual(@as(?u16, 0x0003), try font.gaspBehavior(8));
    try std.testing.expectEqual(@as(?u16, 0x000f), try font.gaspBehavior(9));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.gaspInfo(allocator)) == null);
    try std.testing.expect((try missing.gaspBehavior(12)) == null);
}

test "lazy gasp metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGaspTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?u16, 0x0003), try font.gaspBehavior(8));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gasp_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gasp")) gasp_offset = table.offset;
    }
    bytes[gasp_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.gaspBehavior(8));
    try std.testing.expectError(error.BadSfnt, font.gaspInfo(allocator));
}

test "lazy head metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 1000), (try font.headInfo()).units_per_em);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var head_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "head")) head_offset = table.offset;
    }
    bytes[head_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.headInfo());
}

test "lazy metric header metadata revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(u16, 2), (try font.horizontalHeaderInfo()).long_metric_count);
        const tables = try font.tables(allocator);
        defer allocator.free(tables);
        var hhea_offset: ?usize = null;
        for (tables) |table| {
            if (std.mem.eql(u8, &table.tag, "hhea")) hhea_offset = table.offset;
        }
        bytes[hhea_offset orelse return error.MissingTable] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.horizontalHeaderInfo());
        try std.testing.expectError(error.InvalidMetrics, font.horizontalMetricsTable(allocator));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expect((try font.verticalHeaderInfo()) != null);
        const tables = try font.tables(allocator);
        defer allocator.free(tables);
        var vhea_offset: ?usize = null;
        for (tables) |table| {
            if (std.mem.eql(u8, &table.tag, "vhea")) vhea_offset = table.offset;
        }
        bytes[vhea_offset orelse return error.MissingTable] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.verticalHeaderInfo());
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetricsTable(allocator));
    }
}

test "kern metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0SubtableTest(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.kernInfo(allocator)).?;
    defer font.freeKernInfo(allocator, info);
    try std.testing.expectEqual(KernTableDialect.legacy, info.dialect);
    try std.testing.expectEqual(@as(u32, 0), info.version);
    try std.testing.expectEqual(@as(usize, 1), info.subtables.len);
    try std.testing.expectEqual(@as(u16, 0), info.subtables[0].format);
    try std.testing.expectEqual(@as(u16, 0x0001), info.subtables[0].coverage);
    try std.testing.expect(info.subtables[0].horizontal);
    try std.testing.expect(!info.subtables[0].minimum);
    try std.testing.expect(!info.subtables[0].cross_stream);
    try std.testing.expectEqual(@as(?u16, 1), info.subtables[0].pair_count);

    const missing_bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.kernInfo(allocator)) == null);
}

test "lazy kern metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0SubtableTest(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = (try font.kernInfo(allocator)).?;
    defer font.freeKernInfo(allocator, initial);
    try std.testing.expectEqual(@as(usize, 1), initial.subtables.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var kern_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "kern")) kern_offset = table.offset;
    }
    bytes[(kern_offset orelse return error.MissingTable) + 22] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.kernInfo(allocator));
}

test "PCLT metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildPcltTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.pcltInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(u32, 1234), info.font_number);
    try std.testing.expectEqual(@as(u16, 500), info.pitch);
    try std.testing.expectEqual(@as(u16, 450), info.x_height);
    try std.testing.expectEqual(@as(u16, 700), info.cap_height);
    try std.testing.expectEqual(@as(u16, 0x1234), info.symbol_set);
    try std.testing.expectEqualStrings("CangjiePCLTTest!", &info.typeface);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &info.character_complement);
    try std.testing.expectEqualStrings("CJTEST", &info.file_name);
    try std.testing.expectEqual(@as(i8, -2), info.stroke_weight);
    try std.testing.expectEqual(@as(i8, 3), info.width_type);
    try std.testing.expectEqual(@as(u8, 4), info.serif_style);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.pcltInfo()) == null);
}

test "lazy PCLT metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildPcltTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.pcltInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var pclt_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "PCLT")) pclt_offset = table.offset;
    }
    bytes[pclt_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.pcltInfo());
}

test "post metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var post: [44]u8 = .{0} ** 44;
    writeU32Test(&post, 0, 0x00020000);
    writeI32Test(&post, 4, 0x00008000); // 0.5 degree italic angle.
    writeI16Test(&post, 8, -75);
    writeI16Test(&post, 10, 25);
    writeU32Test(&post, 12, 1);
    writeU32Test(&post, 16, 2);
    writeU32Test(&post, 20, 3);
    writeU32Test(&post, 24, 4);
    writeU32Test(&post, 28, 5);
    writeU16Test(&post, 32, 2);
    writeU16Test(&post, 34, 0);
    writeU16Test(&post, 36, 258);
    post[38] = 5;
    @memcpy(post[39..44], "A.alt");

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.postInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00020000), info.format);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), info.italic_angle, 0.001);
    try std.testing.expectEqual(@as(i16, -75), info.underline_position);
    try std.testing.expectEqual(@as(i16, 25), info.underline_thickness);
    try std.testing.expect(info.is_fixed_pitch);
    try std.testing.expectEqual(@as(u32, 2), info.min_mem_type42);
    try std.testing.expectEqual(@as(u32, 5), info.max_mem_type1);
    try std.testing.expectEqual(@as(?u16, 2), info.glyph_name_count);
}

test "post metadata handles missing and borrowed mutated tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.postInfo()) == null);

    var post: [32]u8 = .{0} ** 32;
    writeU32Test(&post, 0, 0x00030000);
    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(u32, 0x00030000), (try font.postInfo()).?.format);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var post_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "post")) post_offset = table.offset;
    }
    bytes[post_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.postInfo());
}

test "lazy maxp metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 2), (try font.maxpInfo()).glyph_count);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var maxp_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "maxp")) maxp_offset = table.offset;
    }
    bytes[maxp_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.maxpInfo());
}

test "lazy glyph locations revalidate borrowed loca bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const locations = try font.glyphLocations(allocator);
    defer allocator.free(locations);
    try std.testing.expectEqual(@as(usize, 2), locations.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var loca_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "loca")) loca_offset = table.offset;
    }
    bytes[loca_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphLocations(allocator));
}

test "raw SFNT table data revalidates borrowed checksums" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const hhea_data = (try font.tableData(.{ 'h', 'h', 'e', 'a' })).?;
    try std.testing.expect(hhea_data.len >= 8);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var hhea_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hhea")) hhea_offset = table.offset;
    }
    bytes[hhea_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.tableData(.{ 'h', 'h', 'e', 'a' }));
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

test "IFT table-keyed and glyph-keyed patch metadata decode from supplied bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const font_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();

    var table_patch: [38]u8 = .{0} ** 38;
    @memcpy(table_patch[0..4], "IFTB");
    for (0..16) |index| table_patch[8 + index] = @intCast(index);
    writeU16Root(&table_patch, 24, 1);
    writeU32Root(&table_patch, 26, 0);
    writeU32Root(&table_patch, 30, 4);
    @memcpy(table_patch[34..38], "data");
    const table_info = try font.iftTableKeyedPatchInfo(allocator, &table_patch);
    defer font.freeIftTableKeyedPatchInfo(allocator, table_info);
    try std.testing.expectEqualStrings("IFTB", &table_info.format);
    try std.testing.expectEqualSlices(u32, &.{ 0, 4 }, table_info.patch_offsets);

    var glyph_patch: [31]u8 = .{0} ** 31;
    @memcpy(glyph_patch[0..4], "IFTG");
    glyph_patch[8] = 1;
    for (0..16) |index| glyph_patch[9 + index] = @intCast(15 - index);
    writeU32Root(&glyph_patch, 25, 256);
    glyph_patch[29] = 0xaa;
    glyph_patch[30] = 0xbb;
    const glyph_info = try font.iftGlyphKeyedPatchInfo(&glyph_patch);
    try std.testing.expectEqualStrings("IFTG", &glyph_info.format);
    try std.testing.expectEqual(@as(u8, 1), glyph_info.flags);
    try std.testing.expectEqual(@as(u32, 256), glyph_info.max_uncompressed_length);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, glyph_info.brotli_stream);
}

test "IFT patch map metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.iftPatchMapInfo()).?;
    try std.testing.expectEqual(@as(u8, 2), info.format);
    try std.testing.expectEqual(@as(u8, 0x01), info.field_flags);
    try std.testing.expectEqual(@as(u8, 15), info.compatibility_id[15]);
    try std.testing.expectEqual(@as(u8, 1), info.default_patch_format);
    try std.testing.expectEqual(@as(u32, 1), info.entry_count);
    try std.testing.expectEqualStrings("https://patch.example/{id}", info.url_template);
    try std.testing.expectEqual(@as(?u32, 24), info.cff_charstrings_offset);
    try std.testing.expect(info.cff2_charstrings_offset == null);
    try std.testing.expect((try font.iftxPatchMapInfo()) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.iftPatchMapInfo()) == null);
}

test "lazy IFT patch map metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildIftTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.iftPatchMapInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ift_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "IFT ")) ift_offset = table.offset;
    }
    bytes[ift_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.iftPatchMapInfo());
}

test "VARC top-level metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVarcTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.varcInfo(allocator)).?;
    defer font.freeVarcInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(usize, 24), info.coverage_offset);
    try std.testing.expectEqual(@as(?usize, null), info.multi_var_store_offset);
    try std.testing.expectEqual(@as(?usize, null), info.condition_list_offset);
    try std.testing.expectEqual(@as(usize, 32), info.var_composite_glyphs_offset);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, info.glyphs);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.varcInfo(allocator)) == null);
}

test "lazy VARC metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVarcTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.varcInfo(allocator)).?;
    defer font.freeVarcInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var varc_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "VARC")) varc_offset = table.offset;
    }
    bytes[varc_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.varcInfo(allocator));
}

test "VARC outlines recurse, filter conditions, and apply static transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVarcTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var base = try font.glyphOutline(allocator, 1);
    defer base.deinit();
    var composite = try font.glyphOutline(allocator, 0);
    defer composite.deinit();

    try std.testing.expectEqual(base.commands.items.len, composite.commands.items.len);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.x * 2 + 10), composite.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.y * 0.5 + 20), composite.commands.items[0].move_to.y);
    try std.testing.expectEqual(@as(f32, base.commands.items[1].line_to.x * 2 + 10), composite.commands.items[1].line_to.x);
    try std.testing.expectEqual(@as(f32, base.commands.items[1].line_to.y * 0.5 + 20), composite.commands.items[1].line_to.y);
    try std.testing.expectEqual(@as(i16, 10), composite.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), composite.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 1410), composite.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 145), composite.bounds.y_max);

    // At a non-default location condition 1 also matches, so the second
    // self-component contributes another untransformed copy of glyph 1.
    var varied = try font.glyphOutlineAtCoords(allocator, 0, &.{0.75});
    defer varied.deinit();
    try std.testing.expectEqual(base.commands.items.len * 2, varied.commands.items.len);
    try std.testing.expectEqual(@as(f32, base.commands.items[0].move_to.x * 2 + 10), varied.commands.items[0].move_to.x);
    try std.testing.expectEqual(base.commands.items[0].move_to.x, varied.commands.items[base.commands.items.len].move_to.x);
    try std.testing.expectEqual(@as(i16, 0), (try font.glyphBoundsAtCoords(0, &.{0.75})).x_min);
    try std.testing.expectEqual(composite.bounds, try font.glyphBounds(0));
}

test "VARC non-default outlines apply HVAR metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVarcHvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    try std.testing.expectEqual(@as(u16, 800), default_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 0), default_outline.left_side_bearing);

    var varied = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied.deinit();
    try std.testing.expectEqual(@as(u16, 804), varied.advance_width);
    try std.testing.expectEqual(@as(i16, 4), varied.left_side_bearing);

    var raster = try font.glyphOutlineForRasterAtCoords(allocator, 1, &.{0.5});
    defer raster.deinit();
    try std.testing.expectEqual(varied.advance_width, raster.advance_width);
    try std.testing.expectEqual(varied.left_side_bearing, raster.left_side_bearing);
}

test "parses EBDT EBLC bitmap glyph metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildEbdtBitmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(BitmapStrikeSource.eblc_ebdt, strikes[0].source);
    try std.testing.expectEqual(@as(u16, 12), strikes[0].ppem);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].start_glyph);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].end_glyph);

    const glyph_id = try font.glyphIndex('A');
    const bitmap_info = (try font.bitmapGlyphInfo(glyph_id, 12)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.eblc_ebdt, bitmap_info.source);
    try std.testing.expectEqual(@as(?u16, 1), bitmap_info.image_format);
    try std.testing.expectEqual(@as(i16, 1), bitmap_info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 9), bitmap_info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 8), bitmap_info.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.height);
    try std.testing.expect(!bitmap_info.is_png);
    try std.testing.expectEqual(@as(usize, 1), bitmap_info.data_length);
    try std.testing.expect((try font.bitmapGlyphPng(glyph_id, 12)) == null);
    try std.testing.expectEqual(@as(?u16, 12), try font.bestBitmapStrikePpem(12));
}

test "parses CBDT CBLC PNG bitmap glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, strikes[0].source);
    try std.testing.expectEqual(@as(u16, 16), strikes[0].ppem);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].start_glyph);
    try std.testing.expectEqual(@as(GlyphId, 1), strikes[0].end_glyph);

    const glyph_id = try font.glyphIndex('A');
    const bitmap_info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap_info.source);
    try std.testing.expectEqual(glyph_id, bitmap_info.glyph_id);
    try std.testing.expectEqual(@as(u16, 16), bitmap_info.ppem);
    try std.testing.expectEqual(@as(i16, 2), bitmap_info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bitmap_info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap_info.height);
    try std.testing.expectEqual(@as(?u16, 17), bitmap_info.image_format);
    try std.testing.expect(bitmap_info.is_png);
    try std.testing.expect(bitmap_info.data_length > 0);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap.source);
    try std.testing.expectEqual(@as(u16, 16), bitmap.ppem);
    try std.testing.expectEqual(@as(i16, 2), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 13), bitmap.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);
    try std.testing.expect(std.mem.eql(u8, bitmap.data[1..4], "PNG"));
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(18));
}

test "renders CBDT RGBA PNG at bitmap bearings with premultiplied source-over" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    // ColorRenderTarget uses premultiplied storage. A half-alpha green
    // backdrop makes this exercise both image alpha and source-over.
    target.clear(.{ .r = 0, .g = 128, .b = 0, .a = 128 });
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);

    // The fixture is a 1x1 half-alpha red PNG. CBDT bearing (2, 13) places its
    // top-left at (5 + 2, 20 - 13) = (7, 7).
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 63, .b = 0, .a = 191 }, target.at(7, 7));
    try std.testing.expectEqual(Rgba{ .r = 0, .g = 128, .b = 0, .a = 128 }, target.at(6, 7));
    try std.testing.expectEqual(Rgba{ .r = 0, .g = 128, .b = 0, .a = 128 }, target.at(7, 6));
}

test "renders CBDT format 19 with shared CBLC metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCbdtFormat19PngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');

    const info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(?u16, 19), info.image_format);
    try std.testing.expectEqual(@as(i16, 4), info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 11), info.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), info.width);
    try std.testing.expectEqual(@as(u32, 1), info.height);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(i16, 4), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 11), bitmap.origin_offset_y);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);
    // Format 19 has no inline metrics: CBLC index format 2 supplies the shared
    // bearing, placing this pixel at (5 + 4, 20 - 11) = (9, 9).
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 0, .b = 0, .a = 128 }, target.at(9, 9));
    try std.testing.expectEqual(@as(u8, 0), target.at(5, 20).a);
}

test "selects a larger CBDT strike before upscaling a smaller image when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/cbdt.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id: GlyphId = 2;

    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(12));
    try std.testing.expectEqual(@as(?u16, 64), try font.bestBitmapStrikePpem(17));
    try std.testing.expectEqual(@as(?u16, 64), try font.bestBitmapStrikePpem(60));
    try std.testing.expectEqual(@as(?u16, 128), try font.bestBitmapStrikePpem(65));
    try std.testing.expectEqual(@as(?u16, 128), try font.bestBitmapStrikePpem(200));

    const at_17 = (try font.bitmapGlyphPng(glyph_id, 17)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 64), at_17.ppem);
    try std.testing.expectEqual(@as(u32, 39), at_17.width);
    try std.testing.expectEqual(@as(u32, 52), at_17.height);

    const info = (try font.bitmapGlyphInfo(glyph_id, 17)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(u16, 64), info.ppem);
    try std.testing.expectEqual(at_17.width, info.width);
    try std.testing.expectEqual(at_17.height, info.height);
}

test "bitmap-only fonts leave missing strike glyphs transparent" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect(!font.hasOutlineData());

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    // Glyph 0 has neither a CBDT image nor an outline. Rendering it is a valid
    // no-op rather than a MissingTable failure.
    try rasterizer.renderColorGlyph(&target, &font, 0, 16, 5, 20, 0);
    for (target.pixels) |pixel| try std.testing.expectEqual(@as(u8, 0), pixel.a);
}

test "renders indexed CBDT PNG from Noto Color Emoji when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x1f600);
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 109)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.cblc_cbdt, bitmap.source);

    var target = try ColorRenderTarget.init(allocator, 180, 200);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 109, 16, 160, 0);

    var colored_pixels: usize = 0;
    var nontransparent_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        nontransparent_pixels += 1;
        // Decoded PNG samples are converted to the target's premultiplied
        // representation before filtering and blending.
        try std.testing.expect(pixel.r <= pixel.a);
        try std.testing.expect(pixel.g <= pixel.a);
        try std.testing.expect(pixel.b <= pixel.a);
        if (pixel.r != pixel.g or pixel.g != pixel.b) colored_pixels += 1;
    }
    try std.testing.expect(nontransparent_pixels > 1_000);
    try std.testing.expect(colored_pixels > 1_000);
}

test "renders indexed sbix PNG with bottom-left origin when available" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/noto_handwriting-sbix.ttf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x270d);
    const bitmap = (try font.bitmapGlyphPng(glyph_id, 109)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.sbix, bitmap.source);
    try std.testing.expectEqual(@as(i16, 4), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -27), bitmap.origin_offset_y);

    var target = try ColorRenderTarget.init(allocator, 180, 220);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 109, 20, 160, 0);

    // sbix is bottom-left based: x = 20 + 4 and
    // top = 160 - (128 - 27) = 59 for this known fixture.
    var nontransparent_pixels: usize = 0;
    for (target.pixels, 0..) |pixel, index| {
        if (pixel.a == 0) continue;
        nontransparent_pixels += 1;
        const px = index % target.width;
        const py = index / target.width;
        try std.testing.expect(px >= 24 and px < 152);
        try std.testing.expect(py >= 59 and py < 187);
    }
    try std.testing.expect(nontransparent_pixels > 1_000);
    try std.testing.expectEqual(@as(u8, 0), target.at(24, 58).a);
    try std.testing.expectEqual(@as(u8, 0), target.at(23, 59).a);
}

test "resolves and renders sbix dupe PNG glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildSbixDupePngTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const glyph_id = try font.glyphIndex('A');
    try std.testing.expectEqual(@as(GlyphId, 1), glyph_id);

    const info = (try font.bitmapGlyphInfo(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(BitmapStrikeSource.sbix, info.source);
    try std.testing.expect(info.is_png);
    // Placement and bytes come from the final direct record, not from the
    // intermediate dupe header's deliberately-distinct 99/99 offsets.
    try std.testing.expectEqual(@as(i16, 3), info.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -2), info.origin_offset_y);

    const bitmap = (try font.bitmapGlyphPng(glyph_id, 16)) orelse return error.MissingBitmapGlyph;
    try std.testing.expectEqual(@as(i16, 3), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -2), bitmap.origin_offset_y);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 16, 5, 20, 0);
    // sbix uses bottom-left placement: left=5+3, top=20-(1-2)=21.
    try std.testing.expectEqual(Rgba{ .r = 128, .g = 0, .b = 0, .a = 128 }, target.at(8, 21));
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

    const selectors = try font.variationSelectors(allocator);
    defer allocator.free(selectors);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors);

    const selectors_for_a = try font.variationSelectorsForCodepoint(allocator, 'A');
    defer allocator.free(selectors_for_a);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors_for_a);

    const selectors_for_b = try font.variationSelectorsForCodepoint(allocator, 'B');
    defer allocator.free(selectors_for_b);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors_for_b);

    const selectors_for_c = try font.variationSelectorsForCodepoint(allocator, 'C');
    defer allocator.free(selectors_for_c);
    try std.testing.expectEqual(@as(usize, 0), selectors_for_c.len);

    const codepoints = try font.variationCodepointsForSelector(allocator, 0xfe0f);
    defer allocator.free(codepoints);
    try std.testing.expectEqualSlices(u21, &.{ 'A', 'B' }, codepoints);

    const no_codepoints = try font.variationCodepointsForSelector(allocator, 0xfe0e);
    defer allocator.free(no_codepoints);
    try std.testing.expectEqual(@as(usize, 0), no_codepoints.len);

    try std.testing.expectEqual(VariationSequenceKind.non_default, (try font.variationSequenceKind('A', 0xfe0f)).?);
    try std.testing.expectEqual(VariationSequenceKind.default, (try font.variationSequenceKind('B', 0xfe0f)).?);
    try std.testing.expect((try font.variationSequenceKind('A', 0xfe0e)) == null);
}

test "lazy variation selector enumeration revalidates borrowed cmap bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const selectors = try font.variationSelectors(allocator);
    defer allocator.free(selectors);
    try std.testing.expectEqualSlices(u21, &.{0xfe0f}, selectors);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cmap_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) cmap_offset = table.offset;
    }
    bytes[cmap_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.variationSelectors(allocator));
    try std.testing.expectError(error.BadSfnt, font.variationSelectorsForCodepoint(allocator, 'A'));
    try std.testing.expectError(error.BadSfnt, font.variationCodepointsForSelector(allocator, 0xfe0f));
    try std.testing.expectError(error.BadSfnt, font.variationSequenceKind('A', 0xfe0f));
}

test "enumerates cmap charmaps including variation selector subtables" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 2), charmaps.len);

    try std.testing.expectEqual(@as(u16, 0), charmaps[0].platform_id);
    try std.testing.expectEqual(@as(u16, 3), charmaps[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 6), charmaps[0].format);
    try std.testing.expectEqual(@as(?u32, 0), charmaps[0].language);

    try std.testing.expectEqual(@as(u16, 0), charmaps[1].platform_id);
    try std.testing.expectEqual(@as(u16, 5), charmaps[1].encoding_id);
    try std.testing.expectEqual(@as(u16, 14), charmaps[1].format);
    try std.testing.expectEqual(@as(?u32, null), charmaps[1].language);

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(charmaps[0], default_charmap);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithCharmap(default_charmap, 'A'));
    try std.testing.expectError(error.UnsupportedCmap, font.glyphIndexWithCharmap(charmaps[1], 'A'));
    try std.testing.expectError(error.UnsupportedCmap, font.firstCharmapMapping(charmaps[1]));
}

test "maps glyphs through explicitly selected charmaps" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 1), charmaps.len);
    try std.testing.expectEqual(@as(u16, 10), charmaps[0].format);

    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndexWithCharmap(charmaps[0], 0x1f600));
    try std.testing.expectEqual(@as(GlyphId, 0), try font.glyphIndexWithCharmap(charmaps[0], 'A'));

    var stale = charmaps[0];
    stale.encoding_id = 99;
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithCharmap(stale, 0x1f600));
    try std.testing.expectError(error.InvalidCodepoint, font.glyphIndexWithCharmap(charmaps[0], 0xd800));
}

test "iterates selected charmap mappings" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildTrimmedCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const charmap = (try font.defaultCharmap()).?;
        const first = (try font.firstCharmapMapping(charmap)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'A', .glyph_id = 1 }), first);
        const second = (try font.nextCharmapMapping(charmap, first.codepoint)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'C', .glyph_id = 3 }), second);
        try std.testing.expect((try font.nextCharmapMapping(charmap, second.codepoint)) == null);
    }

    {
        const bytes = try test_font.buildTrimmed32CmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const charmap = (try font.defaultCharmap()).?;
        const first = (try font.firstCharmapMapping(charmap)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x1f600, .glyph_id = 1 }), first);
        const second = (try font.nextCharmapMapping(charmap, first.codepoint)).?;
        try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0x1f602, .glyph_id = 3 }), second);
        try std.testing.expect((try font.nextCharmapMapping(charmap, second.codepoint)) == null);
    }
}

test "iterates last-resort cmap ranges without entering surrogates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const charmap = (try font.defaultCharmap()).?;
    const first = (try font.firstCharmapMapping(charmap)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0, .glyph_id = 1 }), first);
    const after_bmp = (try font.nextCharmapMapping(charmap, 0xd7ff)).?;
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 0xe000, .glyph_id = 1 }), after_bmp);
    try std.testing.expect((try font.nextCharmapMapping(charmap, 0x10ffff)) == null);
}

test "lazy charmap enumeration revalidates borrowed cmap bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(@as(u16, 4), default_charmap.format);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cmap_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) cmap_offset = table.offset;
    }
    const stale_charmap = default_charmap;
    bytes[cmap_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.defaultCharmap());
    try std.testing.expectError(error.BadSfnt, font.charmaps(allocator));
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithCharmap(stale_charmap, 'A'));
    try std.testing.expectError(error.BadSfnt, font.firstCharmapMapping(stale_charmap));
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
    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .features = &.{.{ .tag = 0, .enabled = true }},
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
    try std.testing.expectEqual(Script.greek, scriptForCodepoint(0x03a9));
    try std.testing.expectEqual(Script.cyrillic, scriptForCodepoint(0x0416));
    try std.testing.expectEqual(Script.inherited, scriptForCodepoint(0x0301));
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(.latin));
    try std.testing.expectEqual(OpenTypeScriptTag.hani, openTypeScriptTag(.han));
    try std.testing.expectEqual(OpenTypeScriptTag.arab, openTypeScriptTag(.arabic));
    try std.testing.expectEqual(OpenTypeScriptTag.grek, openTypeScriptTag(.greek));
    try std.testing.expectEqual(OpenTypeScriptTag.cyrl, openTypeScriptTag(.cyrillic));
    try std.testing.expectEqual(OpenTypeScriptTag.dflt, openTypeScriptTag(.common));
    try std.testing.expectEqual(@intFromEnum(OpenTypeLanguageTag.jan), openTypeTag("JAN "));
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, inferOpenTypeLanguageTag("日本語かな"));
    try std.testing.expectEqual(OpenTypeLanguageTag.zhs, inferOpenTypeLanguageTag("一丁"));
    try std.testing.expectEqual(OpenTypeLanguageTag.kor, inferOpenTypeLanguageTag("한글"));
    try std.testing.expectEqual(OpenTypeLanguageTag.ara, inferOpenTypeLanguageTag("ب"));
    try std.testing.expectEqual(OpenTypeLanguageTag.dflt, inferOpenTypeLanguageTag("ASCII 123"));
    try std.testing.expectEqual(OpenTypeLanguageTag.dflt, inferOpenTypeLanguageTag("A\xff一"));
    const han_japanese = @import("unicode.zig").inferOpenTypeProperties("一あ");
    try std.testing.expectEqual(Script.han, han_japanese.script);
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, han_japanese.language);
    try std.testing.expect(!han_japanese.all_ascii);
    const ascii = @import("unicode.zig").inferOpenTypeProperties("ASCII 123");
    try std.testing.expectEqual(Script.latin, ascii.script);
    try std.testing.expectEqual(OpenTypeLanguageTag.dflt, ascii.language);
    try std.testing.expect(ascii.all_ascii);
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .jan), openTypeLanguageTagForLocale("ja-JP"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .zhs), openTypeLanguageTagForLocale("zh-Hans-CN"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .zht), openTypeLanguageTagForLocale("zh-Hant-TW"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .zhh), openTypeLanguageTagForLocale("zh-HK"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .zhh), openTypeLanguageTagForLocale("zh-Hant-mo"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .dhv), openTypeLanguageTagForLocale("dv-MV"));
    try std.testing.expect(openTypeLanguageTagForLocale("en-US") == null);

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

    try std.testing.expectError(error.InvalidUtf8, itemizeScriptRuns(allocator, "ab\xffج"));
}

test "detects bidi classes and itemizes bidi runs" {
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint('A'));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x0628));
    try std.testing.expectEqual(BidiClass.number, bidiClassForCodepoint('1'));
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
    try std.testing.expectError(error.InvalidUtf8, itemizeBidiRuns(allocator, "abc \xff xyz", .ltr));

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

    const number_visual = try visualOrderCodepoints(allocator, "א12ב", .rtl);
    defer allocator.free(number_visual);
    try std.testing.expectEqualSlices(u21, &.{ 0x05d1, '1', '2', 0x05d0 }, number_visual);
    const neutral_before_number_visual = try visualOrderCodepoints(allocator, "א 12ב", .rtl);
    defer allocator.free(neutral_before_number_visual);
    try std.testing.expectEqualSlices(u21, &.{ 0x05d1, '1', '2', ' ', 0x05d0 }, neutral_before_number_visual);

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

    var number_map = try buildBidiMap(allocator, "א12ב", .rtl);
    defer number_map.deinit();
    try std.testing.expectEqual(@as(usize, 3), number_map.visualToLogical(0).?);
    try std.testing.expectEqual(@as(usize, 1), number_map.visualToLogical(1).?);
    try std.testing.expectEqual(@as(usize, 2), number_map.visualToLogical(2).?);
    try std.testing.expectEqual(@as(usize, 0), number_map.visualToLogical(3).?);
    try std.testing.expectEqual(BidiClass.number, number_map.items[1].direction);

    var neutral_number_map = try buildBidiMap(allocator, "א 12ב", .rtl);
    defer neutral_number_map.deinit();
    try std.testing.expectEqual(@as(usize, 4), neutral_number_map.visualToLogical(0).?);
    try std.testing.expectEqual(@as(usize, 2), neutral_number_map.visualToLogical(1).?);
    try std.testing.expectEqual(@as(usize, 3), neutral_number_map.visualToLogical(2).?);
    try std.testing.expectEqual(@as(usize, 1), neutral_number_map.visualToLogical(3).?);
    try std.testing.expectEqual(@as(usize, 0), neutral_number_map.visualToLogical(4).?);

    try std.testing.expectError(error.InvalidUtf8, buildBidiMap(allocator, "ab\xffב", .ltr));
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

    try std.testing.expectError(error.InvalidUtf8, itemizeGraphemeClusters(allocator, "a\xffb"));
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

    const bengali_split_vowel = try itemizeGraphemeClusters(allocator, "কো!");
    defer allocator.free(bengali_split_vowel);
    try std.testing.expectEqual(@as(usize, 2), bengali_split_vowel.len);
    try std.testing.expectEqualStrings("কো", "কো!"[bengali_split_vowel[0].byte_start..][0..bengali_split_vowel[0].byte_len]);
    try std.testing.expectEqualStrings("!", "কো!"[bengali_split_vowel[1].byte_start..][0..bengali_split_vowel[1].byte_len]);
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

    try std.testing.expectError(error.InvalidUtf8, itemizeWordSegments(allocator, "hi\xffthere"));
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

    try std.testing.expectError(error.InvalidUtf8, itemizeSentenceSegments(allocator, "Hello.\xffNext"));
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
    try std.testing.expectEqual(LineBreakKind.hard, breaks[3].kind);

    const crlf = try itemizeLineBreaks(allocator, "A\r\nB");
    defer allocator.free(crlf);
    try std.testing.expectEqual(@as(usize, 2), crlf.len);
    try std.testing.expectEqual(@as(usize, 3), crlf[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.hard, crlf[0].kind);
    try std.testing.expectEqual(@as(usize, 4), crlf[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.hard, crlf[1].kind);

    try std.testing.expectError(error.InvalidUtf8, lineBreaks("A\xff"));
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
    try std.testing.expectEqual(LineBreakKind.hard, breaks[1].kind);
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

test "enumerates raw SFNT name records" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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
    const test_font = @import("test_font.zig");

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

    const palettes = try font.colorPalettes(allocator);
    defer allocator.free(palettes);
    try std.testing.expectEqual(@as(usize, 1), palettes.len);
    try std.testing.expectEqual(@as(u16, 0), palettes[0].first_color_index);
    try std.testing.expectEqual(@as(u16, 2), palettes[0].color_count);
    try std.testing.expectEqual(@as(u32, 0), palettes[0].palette_type);
    try std.testing.expectEqual(@as(?u16, null), palettes[0].label_name_id);

    const entry_labels = try font.paletteEntryLabels(allocator);
    defer allocator.free(entry_labels);
    try std.testing.expectEqual(@as(usize, 2), entry_labels.len);
    try std.testing.expectEqual(@as(?u16, null), entry_labels[0]);
    try std.testing.expectEqual(@as(?u16, null), entry_labels[1]);

    const layers = try font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 2), layers.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 0), layers[0].palette_index);
    try std.testing.expectEqual(@as(GlyphId, 1), layers[1].glyph_id);
    try std.testing.expectEqual(@as(u16, 1), layers[1].palette_index);

    const palette_colors = try font.paletteColors(allocator, 0);
    defer allocator.free(palette_colors);
    try std.testing.expectEqual(@as(usize, 2), palette_colors.len);
    try std.testing.expectEqual(@as(u8, 255), palette_colors[0].red);
    try std.testing.expectEqual(@as(u8, 0), palette_colors[0].green);
    try std.testing.expectEqual(@as(u8, 0), palette_colors[0].blue);
    try std.testing.expectEqual(@as(u8, 255), palette_colors[1].blue);
    const missing_palette_colors = try font.paletteColors(allocator, 1);
    defer allocator.free(missing_palette_colors);
    try std.testing.expectEqual(@as(usize, 0), missing_palette_colors.len);

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
            switch (glyph_paint.brush) {
                .solid => |solid| {
                    try std.testing.expectEqual(@as(u16, 0), solid.palette_index);
                    try std.testing.expectApproxEqAbs(@as(f32, 1.0), solid.alpha, 0.001);
                },
                else => return error.TestUnexpectedResult,
            }
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
            switch (glyph_paint.brush) {
                .solid => |solid| try std.testing.expectEqual(@as(u16, 0), solid.palette_index),
                else => return error.TestUnexpectedResult,
            }
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

test "reads and renders COLR v1 PaintLinearGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1LinearGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    const clip = (try font.colorClipBox(1)).?;
    try std.testing.expectEqual(@as(f32, 0), clip.x_min);
    try std.testing.expectEqual(@as(f32, 0), clip.y_min);
    try std.testing.expectEqual(@as(f32, 700), clip.x_max);
    try std.testing.expectEqual(@as(f32, 125), clip.y_max);
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .linear_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 0), gradient.p0.x);
                try std.testing.expectEqual(@as(f32, 700), gradient.p1.x);
                try std.testing.expectEqual(ColorPaint.Extend.pad, gradient.color_line.extend);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
                const first = gradient.color_line.stop(0).?;
                const last = gradient.color_line.stop(1).?;
                try std.testing.expectEqual(@as(u16, 0), first.palette_index);
                try std.testing.expectEqual(@as(f32, 0), first.offset);
                try std.testing.expectEqual(@as(u16, 1), last.palette_index);
                try std.testing.expectEqual(@as(f32, 1), last.offset);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_dominant: usize = 0;
    var blue_dominant: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        if (pixel.r > pixel.b) red_dominant += 1;
        if (pixel.b > pixel.r) blue_dominant += 1;
    }
    try std.testing.expect(red_dominant > 0);
    try std.testing.expect(blue_dominant > 0);
    // Font-space y=125 maps to pixel y=29 at this size/baseline. The upper
    // half of the triangle would be covered without the COLR ClipBox.
    try std.testing.expectEqual(@as(u8, 0), target.at(20, 27).a);
    try std.testing.expect(target.at(16, 31).a > 0);
}

test "COLR v1 variable ClipBox resolves and clips at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1VariableClipTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_clip = (try font.colorClipBox(1)).?;
    try std.testing.expectEqual(@as(f32, 100), default_clip.x_min);
    try std.testing.expectEqual(@as(f32, 100), default_clip.y_min);
    try std.testing.expectEqual(@as(f32, 900), default_clip.x_max);
    try std.testing.expectEqual(@as(f32, 900), default_clip.y_max);

    // Logical indexes 1/2 map to a +500 row, while indexes 3/4 map
    // to -500 and exercise DeltaSetIndexMap's required final-entry reuse.
    const varied_clip = (try font.colorClipBoxAtCoords(1, &.{0.4})).?;
    // 0.4 is quantized to the F2Dot14 location 0.4000244140625 before
    // ItemVariationStore evaluation, matching Fontations/Skrifa.
    try std.testing.expectApproxEqAbs(@as(f32, 300.0122), varied_clip.x_min, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 300.0122), varied_clip.y_min, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 699.9878), varied_clip.x_max, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 699.9878), varied_clip.y_max, 0.0001);
    try std.testing.expectError(error.BadSfnt, font.colorClipBoxAtCoords(1, &.{1.01}));

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.4});

    var default_opaque: usize = 0;
    var varied_opaque: usize = 0;
    for (default_target.pixels, varied_target.pixels) |default_pixel, varied_pixel| {
        if (default_pixel.a != 0) default_opaque += 1;
        if (varied_pixel.a != 0) varied_opaque += 1;
    }
    try std.testing.expect(default_opaque > 0);
    try std.testing.expect(varied_opaque < default_opaque);
}

test "COLR v1 variable paints resolve and render at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1VariablePaintTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_paint = (try font.colorPaint(1)).?;
    const varied_paint = (try font.colorPaintAtCoords(1, &.{0.5})).?;
    const default_alpha = switch (default_paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .solid => |solid| solid.alpha,
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    };
    const varied_alpha = switch (varied_paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .solid => |solid| solid.alpha,
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(f32, 1), default_alpha);
    try std.testing.expectEqual(@as(f32, 0.5), varied_alpha);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.5});

    var default_max_alpha: u8 = 0;
    var varied_max_alpha: u8 = 0;
    for (default_target.pixels, varied_target.pixels) |default_pixel, varied_pixel| {
        default_max_alpha = @max(default_max_alpha, default_pixel.a);
        varied_max_alpha = @max(varied_max_alpha, varied_pixel.a);
    }
    try std.testing.expect(default_max_alpha > 0);
    try std.testing.expect(varied_max_alpha > 0);
    try std.testing.expect(varied_max_alpha < default_max_alpha);
}

test "COLR v1 variable gradients resolve geometry and stops" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const linear_bytes = try test_font.buildColorV1VariableLinearGradientTtf(allocator);
    defer allocator.free(linear_bytes);
    var linear_font = try Font.parse(allocator, linear_bytes);
    defer linear_font.deinit();
    const linear = (try linear_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.linear_gradient;
    try std.testing.expectEqual(@as(f32, 100), linear.p0.x);
    try std.testing.expectEqual(@as(f32, 600), linear.p1.x);
    const linear_stops = try linear_font.colorStopsAtCoords(allocator, linear.color_line, &.{0.5});
    defer allocator.free(linear_stops);
    try std.testing.expectEqual(@as(usize, 2), linear_stops.len);
    try std.testing.expectEqual(@as(f32, 0.25), linear_stops[0].offset);
    try std.testing.expectEqual(@as(u16, 1), linear_stops[0].palette_index);
    try std.testing.expectEqual(@as(f32, 0.75), linear_stops[1].offset);
    try std.testing.expectEqual(@as(u16, 0), linear_stops[1].palette_index);
    try std.testing.expectEqual(@as(f32, 0.5), linear_stops[1].alpha);

    const radial_bytes = try test_font.buildColorV1VariableRadialGradientTtf(allocator);
    defer allocator.free(radial_bytes);
    var radial_font = try Font.parse(allocator, radial_bytes);
    defer radial_font.deinit();
    const radial = (try radial_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.radial_gradient;
    try std.testing.expectEqual(@as(f32, 100), radial.r0);
    try std.testing.expectEqual(@as(f32, 250), radial.r1);

    const sweep_bytes = try test_font.buildColorV1VariableSweepGradientTtf(allocator);
    defer allocator.free(sweep_bytes);
    var sweep_font = try Font.parse(allocator, sweep_bytes);
    defer sweep_font.deinit();
    const sweep = (try sweep_font.colorPaintAtCoords(1, &.{0.5})).?.glyph.brush.sweep_gradient;
    try std.testing.expectEqual(@as(f32, 450), sweep.center.x);
    try std.testing.expectEqual(@as(f32, 0), sweep.center.y);
    try std.testing.expectEqual(@as(f32, 45), sweep.start_angle);
    try std.testing.expectEqual(@as(f32, 315), sweep.end_angle);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &linear_font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &linear_font, 1, 24, 8, 32, 0, &.{0.5});
    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "COLR v1 variable transforms affect geometry and brush space" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1VariableTransformTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_transform = (try font.colorPaint(1)).?.transform.affine;
    const varied_transform = (try font.colorPaintAtCoords(1, &.{0.5})).?.transform.affine;
    try std.testing.expectEqual(ColorAffine.identity, default_transform);
    try std.testing.expectEqual(@as(f32, 100), varied_transform.dx);
    try std.testing.expectEqual(@as(f32, 50), varied_transform.dy);

    var default_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 48, 48);
    defer varied_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&default_target, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 1, 24, 8, 32, 0, &.{0.5});
    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "COLR v1 nested PaintGlyph transforms match live Skrifa matrices" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const first = (try font.colorPaint(207)).?.clip_glyph;
    try std.testing.expectEqual(@as(GlyphId, 7), first.glyph_id);
    const outer = (try font.colorPaintChildAtCoords(first.child, &.{})).transform;
    try std.testing.expectEqual(ColorAffine.identity, outer.affine);
    const second = (try font.colorPaintChildAtCoords(outer.child, &.{})).clip_glyph;
    try std.testing.expectEqual(@as(GlyphId, 6), second.glyph_id);
    const rotation = (try font.colorPaintChildAtCoords(second.child, &.{})).transform.affine;

    // Skrifa's current source resolves the same nested PaintRotate to this
    // matrix before its fill_glyph optimization.
    try std.testing.expectApproxEqAbs(@as(f32, 0.9848152), rotation.xx, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.17360622), rotation.yx, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.17360622), rotation.xy, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9848152), rotation.yy, 0.000001);

    var identity_target = try ColorRenderTarget.init(allocator, 256, 256);
    defer identity_target.deinit();
    var rotated_target = try ColorRenderTarget.init(allocator, 256, 256);
    defer rotated_target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&identity_target, &font, 205, 200, 20, 220, 0);
    try rasterizer.renderColorGlyph(&rotated_target, &font, 207, 200, 20, 220, 0);
    try std.testing.expect(colorRenderTargetPixelDifference(&identity_target, &rotated_target) > 0);
}

test "COLR v1 foreground palette sentinel renders current color" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1ForegroundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var white_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a != 0 and pixel.r == pixel.g and pixel.g == pixel.b and pixel.r > 0) white_pixels += 1;
    }
    try std.testing.expect(white_pixels > 10);
}

test "reads and renders COLR v1 PaintRadialGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1RadialGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .radial_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 350), gradient.c0.x);
                try std.testing.expectEqual(@as(f32, 0), gradient.r0);
                try std.testing.expectEqual(@as(f32, 350), gradient.r1);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    const center = target.at(16, 30);
    const edge = target.at(9, 31);
    try std.testing.expect(center.r > center.b);
    try std.testing.expect(edge.b > edge.r);
}

test "reads and renders COLR v1 PaintSweepGradient" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1SweepGradientTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    switch (paint) {
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .sweep_gradient => |gradient| {
                try std.testing.expectEqual(@as(f32, 350), gradient.center.x);
                try std.testing.expectEqual(@as(f32, 0), gradient.start_angle);
                try std.testing.expectEqual(@as(f32, 360), gradient.end_angle);
                try std.testing.expectEqual(@as(u16, 2), gradient.color_line.stop_count);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    const upper = target.at(17, 29);
    const lower = target.at(17, 30);
    try std.testing.expect(upper.r > upper.b);
    try std.testing.expect(lower.b > lower.r);
}

test "rejects COLR v1 ClipList offsets that alias records" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1InvalidClipListTtf(allocator);
    defer allocator.free(bytes);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "accepts COLR v1 exact shared paint payloads" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1RecursivePaintAliasTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
}

test "accepts fonts containing isolated COLR v1 PaintColrGlyph cycles" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1IndirectPaintColrGlyphCycleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(1)).?;
    try std.testing.expectEqual(@as(GlyphId, 2), paint.colr_glyph.glyph_id);

    var target = try ColorRenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try std.testing.expectError(error.BadSfnt, rasterizer.renderColorGlyph(&target, &font, 1, 20, 4, 24, 0));
}

test "COLR v1 PaintColrGlyph traverses referenced paints and clips" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1PaintColrGlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(0)).?;
    try std.testing.expectEqual(@as(GlyphId, 1), paint.colr_glyph.glyph_id);

    var referenced = try ColorRenderTarget.init(allocator, 48, 48);
    defer referenced.deinit();
    var caller = try ColorRenderTarget.init(allocator, 48, 48);
    defer caller.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&referenced, &font, 1, 24, 8, 32, 0);
    try rasterizer.renderColorGlyph(&caller, &font, 0, 24, 8, 32, 0);

    try std.testing.expectEqualSlices(Rgba, referenced.pixels, caller.pixels);
    // The referenced glyph's ClipBox starts at y=350 font units, so the lower
    // triangle tip is removed in both direct and PaintColrGlyph traversal.
    try std.testing.expectEqual(@as(u8, 0), caller.at(16, 31).a);
}

test "COLR v1 PaintColrGlyph matches live Skrifa referenced clip traversal" {
    const allocator = std.testing.allocator;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaint(166)).?;
    try std.testing.expectEqual(@as(GlyphId, 95), paint.colr_glyph.glyph_id);
    const referenced_clip = (try font.colorClipBox(95)).?;
    try std.testing.expectEqual(@as(f32, 0), referenced_clip.x_min);
    try std.testing.expectEqual(@as(f32, 0), referenced_clip.y_min);
    try std.testing.expectEqual(@as(f32, 1000), referenced_clip.x_max);
    try std.testing.expectEqual(@as(f32, 1000), referenced_clip.y_max);

    var referenced = try ColorRenderTarget.init(allocator, 256, 256);
    defer referenced.deinit();
    var caller = try ColorRenderTarget.init(allocator, 256, 256);
    defer caller.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&referenced, &font, 95, 200, 20, 220, 0);
    try rasterizer.renderColorGlyph(&caller, &font, 166, 200, 20, 220, 0);
    // Skrifa traversal first applies glyph 166's inset clip, then glyph 95's
    // own 0..1000 clip around the referenced radial paint.
    try std.testing.expect(colorRenderTargetPixelDifference(&referenced, &caller) > 0);
}

test "COLR v1 PaintComposite renders all current modes" {
    const allocator = std.testing.allocator;
    const path = "/home/passchaos/Work/fontations/font-test-data/test_data/ttf/test_glyphs-glyf_colr_1_variable.ttf";
    const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const expected_overlap = [_]Rgba{
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 104, .g = 199, .b = 232, .a = 255 },
        .{ .r = 255, .g = 220, .b = 1, .a = 255 },
        .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .{ .r = 255, .g = 255, .b = 233, .a = 255 },
        .{ .r = 255, .g = 247, .b = 232, .a = 255 },
        .{ .r = 255, .g = 240, .b = 2, .a = 255 },
        .{ .r = 104, .g = 199, .b = 1, .a = 255 },
        .{ .r = 255, .g = 220, .b = 232, .a = 255 },
        .{ .r = 255, .g = 255, .b = 11, .a = 255 },
        .{ .r = 255, .g = 210, .b = 0, .a = 255 },
        .{ .r = 208, .g = 240, .b = 209, .a = 255 },
        .{ .r = 255, .g = 229, .b = 3, .a = 255 },
        .{ .r = 151, .g = 21, .b = 231, .a = 255 },
        .{ .r = 151, .g = 76, .b = 231, .a = 255 },
        .{ .r = 104, .g = 172, .b = 1, .a = 255 },
        .{ .r = 145, .g = 227, .b = 255, .a = 255 },
        .{ .r = 230, .g = 213, .b = 102, .a = 255 },
        .{ .r = 145, .g = 227, .b = 255, .a = 255 },
        .{ .r = 217, .g = 187, .b = 0, .a = 255 },
    };

    for (expected_overlap, 0..) |expected, raw_mode| {
        const glyph_id: GlyphId = @intCast(120 + raw_mode);
        var target = try ColorRenderTarget.init(allocator, 256, 256);
        defer target.deinit();
        var rasterizer = Rasterizer.init(allocator);
        try rasterizer.renderColorGlyph(&target, &font, glyph_id, 200, 20, 220, 0);
        try std.testing.expectEqual(expected, target.at(120, 120));
    }
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

test "resolves and renders gzip OpenType SVG documents" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildGzipSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const raw = (try font.svgGlyphDocument(1)) orelse return error.MissingSvgGlyph;
    try std.testing.expectEqualSlices(u8, &.{ 0x1f, 0x8b, 0x08 }, raw.data[0..3]);

    var resolved = (try font.resolvedSvgGlyphDocument(allocator, 1)) orelse return error.MissingSvgGlyph;
    defer resolved.deinit();
    try std.testing.expect(resolved.allocator != null);
    try std.testing.expect(std.mem.startsWith(u8, resolved.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, resolved.data, "<rect") != null);

    var target = try ColorRenderTarget.init(allocator, 48, 48);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, 1, 24, 8, 32, 0);

    var red_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.r > 0 and pixel.g == 0 and pixel.b == 0 and pixel.a > 0) red_pixels += 1;
    }
    try std.testing.expect(red_pixels > 50);
}

test "resolves real HarfBuzz gzip SVG fixture" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = "/home/passchaos/Work/harfbuzz/test/shape/data/text-rendering-tests/fonts/TestSVGgzip.otf";
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return,
        else => return err,
    };
    defer allocator.free(data);

    var font = try Font.parse(allocator, data);
    defer font.deinit();
    const glyph_id = try font.glyphIndex(0x1f600);
    try std.testing.expectEqual(@as(GlyphId, 3), glyph_id);

    var resolved = (try font.resolvedSvgGlyphDocument(allocator, glyph_id)) orelse return error.MissingSvgGlyph;
    defer resolved.deinit();
    try std.testing.expectEqual(@as(usize, 3166), resolved.data.len);
    try std.testing.expect(std.mem.startsWith(u8, resolved.data, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, resolved.data, "<linearGradient") != null);

    var target = try ColorRenderTarget.init(allocator, 160, 160);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderColorGlyph(&target, &font, glyph_id, 128, 16, 144, 0);
    var painted_pixels: usize = 0;
    var colored_pixels: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel.a == 0) continue;
        painted_pixels += 1;
        if (pixel.r != pixel.g or pixel.g != pixel.b) colored_pixels += 1;
    }
    try std.testing.expect(painted_pixels > 400);
    try std.testing.expect(colored_pixels > 400);
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

test "font database manifest frees partial entries on allocation failure" {
    const allocator = std.testing.allocator;
    const bytes = try @import("test_font.zig").buildNamedTtfWithNames(allocator, "OOM Manifest", "Regular", "OOM Manifest Regular");
    defer allocator.free(bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(bytes);

    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 2 });
    try std.testing.expectError(error.OutOfMemory, database.manifest(failing.allocator()));
}

test "font manifest parser accepts CRLF line endings" {
    const allocator = std.testing.allocator;
    const text =
        "cangjie-font-manifest-v3\r\n" ++
        "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\r\n" ++
        "CRLF Sans\tRegular\tCRLF Sans Regular\tCRLFSans-Regular\t0\t0\t400\t100\tnormal\r\n";
    const parsed = try parseManifest(allocator, text);
    defer FontDatabase.freeManifest(allocator, parsed);

    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqualStrings("CRLF Sans", parsed[0].family);
    try std.testing.expectEqual(FontStyle.normal, parsed[0].style);
}

test "font manifest parse errors free decoded fields" {
    const allocator = std.testing.allocator;
    const prefix =
        "cangjie-font-manifest-v3\n" ++
        "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\n";

    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\tnot-hex\t0\t400\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky\\x-Regular\t0\t0\t400\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t100\tslant\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t0\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t1001\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t0\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t1001\tnormal\n"));
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

    const ignored_unsupported = [_]FontSource{.{ .file = .{ .path = "notes.txt", .ignore_missing = true } }};
    try std.testing.expectEqual(@as(usize, 0), try database.scanFontSources(std.testing.io, tmp_dir.dir, &ignored_unsupported, .limited(1024 * 1024)));
    const strict_unsupported = [_]FontSource{.{ .file = .{ .path = "notes.txt", .ignore_missing = false } }};
    try std.testing.expectError(error.UnsupportedFontSource, database.scanFontSources(std.testing.io, tmp_dir.dir, &strict_unsupported, .limited(1024 * 1024)));
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

    const os2 = (try narrow_italic.os2Info()).?;
    try std.testing.expectEqual(@as(u16, 4), os2.version);
    try std.testing.expectEqual(@as(u16, 650), os2.weight_class);
    try std.testing.expectEqual(@as(u16, 3), os2.width_class);
    try std.testing.expectEqual(@as(u16, 0x0001), os2.selection);
    try std.testing.expectEqual(@as(i16, 650), os2.subscript_x_size);
    try std.testing.expectEqual(@as(i16, 120), os2.subscript_y_offset);
    try std.testing.expectEqual(@as(i16, 0), os2.typo_ascender);
    try std.testing.expect(os2.code_page_ranges != null);
    try std.testing.expect(os2.x_height != null);
    try std.testing.expect(os2.lower_optical_point_size == null);

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

test "OS/2 info handles missing and borrowed mutated tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.os2Info()) == null);

    const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.os2Info()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var os2_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "OS/2")) os2_offset = table.offset;
    }
    bytes[os2_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.os2Info());
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

test "cascade shaping can preserve caller-materialized visual order" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(allocator, "Visual Sans", "Regular", "Visual Sans Regular");
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const reordered = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &layout_buffer,
        "A\u{05d0}",
        20,
        .{ .direction = .rtl },
    );
    try std.testing.expectEqual(@as(u21, 0x05d0), reordered.glyphs[0].codepoint);

    const preserved = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &layout_buffer,
        "A\u{05d0}",
        20,
        .{ .direction = .rtl, .reorder_bidi = false },
    );
    try std.testing.expectEqual(@as(u21, 'A'), preserved.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), preserved.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 0), preserved.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 1), preserved.glyphs[1].cluster);
}

test "native-direction shaping exposes HarfBuzz buffer order for explicit RTL Old Italic" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 0x10300, 0x10301 });
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &layout_buffer,
        "\u{10300}\u{10301}",
        20,
        .{
            .direction = .rtl,
            .reorder_bidi = false,
            .native_direction_shaping = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x10301), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x10300), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 4), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[1].cluster);
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

test "shapes mirrored bidi punctuation with mirrored glyph ids" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(allocator, "Mirror Sans", "Regular", "Mirror Sans Regular");
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "(\u{05d0})", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqual(@as(u21, '('), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, ')'), run.glyphs[2].codepoint);
    try std.testing.expectEqual(try font.glyphIndex('('), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(try font.glyphIndex(0x05d0), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(try font.glyphIndex(')'), run.glyphs[2].glyph_id);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1, 0 }, &.{
        run.glyphs[0].cluster,
        run.glyphs[1].cluster,
        run.glyphs[2].cluster,
    });
}

test "shapes right-to-left text with numeric subruns left-to-right" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const one_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '1', "One Sans", "Regular", "One Sans Regular");
    defer allocator.free(one_bytes);
    const two_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '2', "Two Sans", "Regular", "Two Sans Regular");
    defer allocator.free(two_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);

    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var one = try Font.parse(allocator, one_bytes);
    defer one.deinit();
    var two = try Font.parse(allocator, two_bytes);
    defer two.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();

    const fonts = [_]*const Font{ &alef, &one, &two, &bet };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "\u{05d0}12\u{05d1}", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 0x05d1), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, '1'), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, '2'), shaped.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[3].codepoint);
    try std.testing.expectEqualSlices(usize, &.{ 4, 2, 3, 0 }, &.{
        shaped.glyphs[0].cluster,
        shaped.glyphs[1].cluster,
        shaped.glyphs[2].cluster,
        shaped.glyphs[3].cluster,
    });
}

test "maps logical carets onto visually reordered bidi glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const one_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '1', "One Sans", "Regular", "One Sans Regular");
    defer allocator.free(one_bytes);
    const two_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '2', "Two Sans", "Regular", "Two Sans Regular");
    defer allocator.free(two_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);

    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var one = try Font.parse(allocator, one_bytes);
    defer one.deinit();
    var two = try Font.parse(allocator, two_bytes);
    defer two.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();

    const fonts = [_]*const Font{ &alef, &one, &two, &bet };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "\u{05d0}12\u{05d1}", 20, .{ .max_width = 200, .direction = .rtl });
    const clusters = try itemizeGraphemeClusters(allocator, "\u{05d0}12\u{05d1}");
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, "\u{05d0}12\u{05d1}".len), paragraph.lines[0].byte_len);

    const after_alef = paragraph.nextGraphemeCaret(clusters, .{ .glyph_index = 3, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 1), after_alef.glyph_index);
    try std.testing.expectEqual(@as(usize, 2), after_alef.cluster);
    try std.testing.expect(!after_alef.trailing);

    const after_one = paragraph.nextGraphemeCaret(clusters, after_alef);
    try std.testing.expectEqual(@as(usize, 2), after_one.glyph_index);
    try std.testing.expectEqual(@as(usize, 3), after_one.cluster);
    try std.testing.expect(!after_one.trailing);

    const digit_selection = paragraph.selectionRectForBytes(2, 4);
    try std.testing.expect(digit_selection.width > 0);
    try std.testing.expect(digit_selection.x >= 0);
}

test "mixed bidi paragraphs wrap and reorder each visual line independently" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "AB אב 12 אב";
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 60,
        .line_height = 24,
        .direction = .ltr,
    });

    try std.testing.expectEqual(@as(usize, 4), paragraph.lines.len);
    const expected_codepoints = [_][]const u21{
        &.{ 'A', 'B' },
        &.{ 0x05d1, 0x05d0 },
        &.{ '1', '2' },
        &.{ 0x05d1, 0x05d0 },
    };
    const expected_byte_starts = [_]usize{ 0, 3, 8, 11 };
    const expected_byte_lens = [_]usize{ 3, 5, 3, 4 };
    for (paragraph.lines, 0..) |line, line_index| {
        try std.testing.expectEqual(expected_byte_starts[line_index], line.byte_start);
        try std.testing.expectEqual(expected_byte_lens[line_index], line.byte_len);
        const line_glyphs = line.glyphs(paragraph);
        try std.testing.expectEqual(expected_codepoints[line_index].len, line_glyphs.len);
        for (line_glyphs, expected_codepoints[line_index]) |glyph, expected| {
            try std.testing.expectEqual(expected, glyph.codepoint);
        }
    }
    try std.testing.expectEqual(text.len, paragraph.lines[paragraph.lines.len - 1].byteEnd());
}

test "paragraph shaping retains logical order before per-line bidi reordering" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Logical Hebrew",
        "Regular",
        "Logical Hebrew Regular",
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "אב",
        20,
        .{ .max_width = 100, .direction = .ltr },
    );
    defer paragraph.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, &.{
        paragraph.glyphs[0].cluster,
        paragraph.glyphs[1].cluster,
    });

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const visual = try paragraph.layout(&reflow, .{
        .max_width = 100,
        .direction = .ltr,
    });
    try std.testing.expectEqualSlices(usize, &.{ 2, 0 }, &.{
        visual.glyphs[0].cluster,
        visual.glyphs[1].cluster,
    });
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
    try std.testing.expectApproxEqAbs(@as(f32, 29.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), paragraph.lines[1].width, 0.001);
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

test "paragraph wrapping keeps multiple-substitution glyph atoms together" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMultipleGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 1,
        .line_height = 24,
    });

    // Both output glyphs represent the same source scalar. Breaking between
    // them would create a line boundary with no corresponding source caret.
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(paragraph.glyphs[0].cluster, paragraph.glyphs[1].cluster);
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
    try std.testing.expectEqual(@as(usize, 0), crlf.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), crlf.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 3), crlf.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[1].byte_len);
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
    try std.testing.expectEqual(@as(usize, 0), ivs.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 7), ivs.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 7), ivs.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 3), ivs.lines[1].byte_len);
}

test "paragraph layout preserves an empty caret line after trailing newline" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\n", 20, .{
        .max_width = 80,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[1].glyph_len);
    try std.testing.expectEqual(paragraph.glyphs.len, paragraph.lines[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[1].byte_len);
}

test "paragraph wrapping honors UAX 14 punctuation and no-break glue" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const cjk_bytes = try test_font.buildNamedCjkTtf(allocator);
    defer allocator.free(cjk_bytes);
    var cjk_font = try Font.parse(allocator, cjk_bytes);
    defer cjk_font.deinit();
    const cjk_fonts = [_]*const Font{&cjk_font};
    const cjk_cascade = FontCascade.init(&cjk_fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const punctuation = try TextShaper.layoutParagraphUtf8(cjk_cascade, &layout_buffer, "你。好", 20, .{
        .max_width = 20,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), punctuation.lines.len);
    try std.testing.expectEqual(@as(usize, 2), punctuation.lines[0].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x4f60), punctuation.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x3002), punctuation.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x597d), punctuation.glyphs[2].codepoint);

    const ascii_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ascii_bytes);
    var ascii_font = try Font.parse(allocator, ascii_bytes);
    defer ascii_font.deinit();
    const ascii_fonts = [_]*const Font{&ascii_font};
    const ascii_cascade = FontCascade.init(&ascii_fonts);
    const glued = try TextShaper.layoutParagraphUtf8(ascii_cascade, &layout_buffer, "A A\u{00a0}A", 20, .{
        .max_width = 50,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), glued.lines.len);
    try std.testing.expectEqual(@as(usize, 1), glued.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), glued.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x00a0), glued.glyphs[3].codepoint);
}

test "paragraph no-wrap mode preserves explicit hard breaks" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A\nA A", 20, .{
        .max_width = 10,
        .wrap_mode = .no_wrap,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[1].glyph_len);
    try std.testing.expect(paragraph.lines[0].width > 10);
    try std.testing.expect(paragraph.lines[1].width > 10);
}

test "shaped paragraphs reflow repeatedly without reshaping or accumulating layout changes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var source = [_]u8{ 'A', '\t', 'A', ' ', 'A', ' ', 'A' };
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        &source,
        20,
        .{
            .max_width = 200,
            .letter_spacing = 2,
            .word_spacing = 3,
        },
    );
    defer paragraph.deinit();
    source[0] = 'Z';
    try std.testing.expectEqualStrings("A\tA A A", paragraph.text);
    const pristine_glyphs = try allocator.dupe(GlyphPosition, paragraph.glyphs);
    defer allocator.free(pristine_glyphs);
    const pristine_runs = try allocator.dupe(CascadeRun, paragraph.runs);
    defer allocator.free(pristine_runs);
    const pristine_graphemes = try allocator.dupe(GraphemeCluster, paragraph.grapheme_clusters);
    defer allocator.free(pristine_graphemes);
    const pristine_breaks = try allocator.dupe(LineBreak, paragraph.line_breaks);
    defer allocator.free(pristine_breaks);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try paragraph.layout(&reflow, .{
        .max_width = 45,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expect(narrow.lines.len > 1);
    const narrow_line_count = narrow.lines.len;
    const narrow_first_width = narrow.lines[0].width;

    const wide = try paragraph.layout(&reflow, .{
        .max_width = 500,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);

    const narrow_again = try paragraph.layout(&reflow, .{
        .max_width = 45,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expectEqual(narrow_line_count, narrow_again.lines.len);
    try std.testing.expectApproxEqAbs(narrow_first_width, narrow_again.lines[0].width, 0.001);
    try std.testing.expectEqualSlices(GlyphPosition, pristine_glyphs, paragraph.glyphs);
    try std.testing.expectEqualSlices(CascadeRun, pristine_runs, paragraph.runs);
    try std.testing.expectEqualSlices(GraphemeCluster, pristine_graphemes, paragraph.grapheme_clusters);
    try std.testing.expectEqualSlices(LineBreak, pristine_breaks, paragraph.line_breaks);
}

test "shaped paragraph reflow restores content after ellipsis truncation" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "A A A A A",
        20,
        .{ .max_width = 200 },
    );
    defer paragraph.deinit();
    const shaped_glyph_count = paragraph.glyphs.len;

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const clipped = try paragraph.layout(&reflow, .{
        .max_width = 42,
        .max_lines = 1,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 1), clipped.lines.len);
    try std.testing.expect(clipped.glyphs.len <= shaped_glyph_count);

    const restored = try paragraph.layout(&reflow, .{ .max_width = 500 });
    try std.testing.expectEqual(shaped_glyph_count, restored.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), restored.lines.len);
    try std.testing.expectEqual(@as(u21, 'A'), restored.glyphs[restored.glyphs.len - 1].codepoint);
}

test "shaped paragraph rejects options that require reshaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "AA",
        20,
        .{ .max_width = 100 },
    );
    defer paragraph.deinit();

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    try std.testing.expectError(error.ParagraphShapingOptionsChanged, paragraph.layout(&reflow, .{
        .max_width = 100,
        .direction = .rtl,
    }));
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.lines.items.len);
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
    try std.testing.expectApproxEqAbs(@as(f32, 17.0), letter_spaced.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 17.0), letter_spaced.glyphs[1].x_advance, 0.001);
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

test "FontDatabase loads and scans WOFF1 font sources" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
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

test "caches glyph metrics by variation coordinates during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].byte_len);
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
                try std.testing.expectApproxEqAbs(@as(f32, 15.0), overlay.rect.x, 0.001);
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

    const byte_selection = paragraph.selectionRectForBytes(1, 4);
    try std.testing.expectApproxEqAbs(selection.x, byte_selection.x, 0.001);
    try std.testing.expectApproxEqAbs(selection.y, byte_selection.y, 0.001);
    try std.testing.expectApproxEqAbs(selection.width, byte_selection.width, 0.001);
    try std.testing.expectApproxEqAbs(selection.height, byte_selection.height, 0.001);

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

test "applies optional GSUB superscript and subscript features when enabled" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildScriptFeatureGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const plain = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), plain.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), plain.glyphs[0].glyph_id);

    const enable_sups = [_]FeatureOverride{.{ .tag = openTypeTag("sups"), .enabled = true }};
    const superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &enable_sups });
    try std.testing.expectEqual(@as(usize, 1), superscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), superscript.glyphs[0].glyph_id);

    const enable_subs = [_]FeatureOverride{.{ .tag = openTypeTag("subs"), .enabled = true }};
    const subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &enable_subs });
    try std.testing.expectEqual(@as(usize, 1), subscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), subscript.glyphs[0].glyph_id);

    const preset_superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .superscript });
    try std.testing.expectEqual(@as(usize, 1), preset_superscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), preset_superscript.glyphs[0].glyph_id);

    const preset_subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .subscript });
    try std.testing.expectEqual(@as(usize, 1), preset_subscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), preset_subscript.glyphs[0].glyph_id);
}

test "script feature visual test font gives substitute glyphs outlines" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildScriptFeatureGsubVisualTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const normal = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    const normal_id = normal.glyphs[0].glyph_id;
    const superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .superscript });
    const superscript_id = superscript.glyphs[0].glyph_id;
    const subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .subscript });
    const subscript_id = subscript.glyphs[0].glyph_id;
    try std.testing.expectEqual(@as(GlyphId, 1), normal_id);
    try std.testing.expectEqual(@as(GlyphId, 2), superscript_id);
    try std.testing.expectEqual(@as(GlyphId, 3), subscript_id);

    var normal_outline = try font.glyphOutline(allocator, 1);
    defer normal_outline.deinit();
    var superscript_outline = try font.glyphOutline(allocator, 2);
    defer superscript_outline.deinit();
    var subscript_outline = try font.glyphOutline(allocator, 3);
    defer subscript_outline.deinit();

    try std.testing.expect(normal_outline.commands.items.len >= 4);
    try std.testing.expect(superscript_outline.commands.items.len >= 4);
    try std.testing.expect(subscript_outline.commands.items.len >= 4);
    const normal_second_x = switch (normal_outline.commands.items[1]) {
        .line_to => |point| point.x,
        else => return error.UnexpectedOutlineCommand,
    };
    const superscript_second_x = switch (superscript_outline.commands.items[1]) {
        .line_to => |point| point.x,
        else => return error.UnexpectedOutlineCommand,
    };
    const normal_peak_y = switch (normal_outline.commands.items[2]) {
        .line_to => |point| point.y,
        else => return error.UnexpectedOutlineCommand,
    };
    const subscript_peak_y = switch (subscript_outline.commands.items[2]) {
        .line_to => |point| point.y,
        else => return error.UnexpectedOutlineCommand,
    };
    try std.testing.expect(superscript_second_x < normal_second_x);
    try std.testing.expect(subscript_peak_y < normal_peak_y);
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
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_offset, 0.001);
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

fn writeKernFormat0SubtableTest(bytes: []u8, offset: usize, coverage: u16, left: GlyphId, right: GlyphId, value: i16) void {
    writeU16Test(bytes, offset + 0, 0);
    writeU16Test(bytes, offset + 2, 20);
    writeU16Test(bytes, offset + 4, coverage);
    writeU16Test(bytes, offset + 6, 1);
    writeU16Test(bytes, offset + 8, 6);
    writeU16Test(bytes, offset + 10, 0);
    writeU16Test(bytes, offset + 12, 0);
    writeU16Test(bytes, offset + 14, left);
    writeU16Test(bytes, offset + 16, right);
    writeI16Test(bytes, offset + 18, value);
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    writeU16Test(bytes, offset, @bitCast(value));
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeI32Test(bytes: []u8, offset: usize, value: i32) void {
    writeU32Test(bytes, offset, @bitCast(value));
}

test {
    std.testing.refAllDecls(@This());
}

fn writeU16Root(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32Root(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
