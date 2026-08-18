//! Cangjie is a small Zig font stack focused on SFNT based TTF/OTF files.
//!
//! The current implementation covers table directory parsing, core TrueType
//! metric tables, Unicode cmap lookup, simple glyph outlines, text layout, and
//! a CPU grayscale rasterizer. The public API leaves room for OpenType shaping
//! and CFF outline expansion without changing callers that load and render text.

const std = @import("std");

const layout_cache = @import("../../shaping/context/cache/root.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
pub const LayoutBuffer = @import("../../shaping/context/output.zig").Buffer;
pub const FontFallbackCache = layout_cache.FontFallbackCache;
pub const GlyphIndexCache = layout_cache.GlyphIndexCache;
pub const GlyphMetricsCache = layout_cache.GlyphMetricsCache;
pub const ShapedRunCache = layout_cache.ShapedRunCache;
pub const ShapePlanCache = shaping_plan.ShapePlanCache;
pub const ShapePlanKey = shaping_plan.ShapePlanKey;
pub const TextShaper = @import("../../shaping/text_shaper.zig").TextShaper;

pub const Script = @import("../../unicode.zig").Script;
pub const ScriptRun = @import("../../unicode.zig").ScriptRun;
pub const BidiClass = @import("../../unicode.zig").BidiClass;
pub const ExactBidiClass = @import("../../unicode.zig").ExactBidiClass;
pub const BidiBaseDirection = @import("../../unicode.zig").BidiBaseDirection;
pub const BidiParagraph = @import("../../unicode.zig").BidiParagraph;
pub const bidi_unicode_version = @import("../../unicode.zig").bidi_unicode_version;
pub const BidiMap = @import("../../unicode.zig").BidiMap;
pub const BidiMapItem = @import("../../unicode.zig").BidiMapItem;
pub const BidiRun = @import("../../unicode.zig").BidiRun;
pub const JoiningForm = @import("../../unicode.zig").JoiningForm;
pub const JoiningType = @import("../../unicode.zig").JoiningType;
pub const VerticalOrientation = @import("../../unicode.zig").VerticalOrientation;
pub const AttributedText = @import("../../text/attributed/root.zig").AttributedText;
pub const AttributedRun = @import("../../text/attributed/root.zig").AttributedRun;
pub const AttributedRunLayout = @import("../../text/attributed/root.zig").AttributedRunLayout;
pub const AttributedGlyphRun = @import("../../text/attributed/root.zig").AttributedGlyphRun;
pub const AttributedGlyphRunLayout = @import("../../text/attributed/root.zig").AttributedGlyphRunLayout;
pub const AttributedParagraphLayout = @import("../../text/attributed/root.zig").AttributedParagraphLayout;
pub const AttributedStyleRun = @import("../../text/attributed/root.zig").AttributedStyleRun;
pub const ByteRange = @import("../../text/style/root.zig").ByteRange;
pub const CharRange = @import("../../text/style/root.zig").CharRange;
pub const ClusterRange = @import("../../text/style/root.zig").ClusterRange;
pub const CoreBaselineMetrics = @import("../../text/style/root.zig").CoreBaselineMetrics;
pub const FontWeight = @import("../../text/style/root.zig").FontWeight;
pub const FontId = @import("../../text/style/root.zig").FontId;
pub const GraphemeRange = @import("../../text/style/root.zig").GraphemeRange;
pub const GraphemeCluster = @import("../../unicode.zig").GraphemeCluster;
pub const GraphemeClusterIterator = @import("../../unicode.zig").GraphemeClusterIterator;
pub const graphemeClusters = @import("../../unicode.zig").graphemeClusters;
pub const grapheme_unicode_version = @import("../../unicode.zig").grapheme_unicode_version;
pub const GlyphCluster = @import("../../text/style/root.zig").GlyphCluster;
pub const GlyphRange = @import("../../text/style/root.zig").GlyphRange;
pub const Language = @import("../../text/style/root.zig").Language;
pub const Locale = @import("../../text/style/root.zig").Locale;
pub const WordSegment = @import("../../unicode.zig").WordSegment;
pub const WordBoundarySegment = @import("../../unicode.zig").WordBoundarySegment;
pub const WordBoundaryIterator = @import("../../unicode.zig").WordBoundaryIterator;
pub const wordSegments = @import("../../unicode.zig").wordSegments;
pub const word_unicode_version = @import("../../unicode.zig").word_unicode_version;
pub const SentenceSegment = @import("../../unicode.zig").SentenceSegment;
pub const SentenceBoundaryIterator = @import("../../unicode.zig").SentenceBoundaryIterator;
pub const sentenceSegments = @import("../../unicode.zig").sentenceSegments;
pub const sentence_unicode_version = @import("../../unicode.zig").sentence_unicode_version;
pub const LineBreak = @import("../../unicode.zig").LineBreak;
pub const LineBreakKind = @import("../../unicode.zig").LineBreakKind;
pub const LineBreakClass = @import("../../unicode.zig").LineBreakClass;
pub const LineBreakIterator = @import("../../unicode.zig").LineBreakIterator;
pub const line_break_unicode_version = @import("../../unicode.zig").line_break_unicode_version;
pub const WordBreakDictionary =
    @import("../../text/segmentation/root.zig").WordBreakDictionary;
pub const OverflowMode = @import("../../text/style/root.zig").OverflowMode;
pub const FeatureOverride = @import("../../unicode.zig").FeatureOverride;
pub const GsubFeatureRange = @import("../../unicode.zig").GsubFeatureRange;
pub const ParagraphStyle = @import("../../text/style/root.zig").ParagraphStyle;
pub const StyleSpan = @import("../../text/style/root.zig").StyleSpan;
pub const TextDecoration = @import("../../text/style/root.zig").TextDecoration;
pub const TextFontStyle = @import("../../text/style/root.zig").TextFontStyle;
pub const TextMetrics = @import("../../text/style/root.zig").TextMetrics;
pub const TextRange = @import("../../text/style/root.zig").TextRange;
pub const TextSpan = @import("../../text/style/root.zig").TextSpan;
pub const TextStyle = @import("../../text/style/root.zig").TextStyle;
pub const VerticalAlign = @import("../../text/style/root.zig").VerticalAlign;
pub const WrapMode = @import("../../text/style/root.zig").WrapMode;
pub const OpenTypeLanguageTag = @import("../../unicode.zig").OpenTypeLanguageTag;
pub const OpenTypeScriptTag = @import("../../unicode.zig").OpenTypeScriptTag;
pub const FontDatabase = @import("../../font/database/root.zig").FontDatabase;
pub const FontFaceInfo = @import("../../font/database/root.zig").FontFaceInfo;
pub const FontManifestEntry = @import("../../font/database/root.zig").FontManifestEntry;
pub const FontQuery = @import("../../font/database/root.zig").FontQuery;
pub const FontSource = @import("../../font/database/root.zig").FontSource;
pub const FontStyle = @import("../../font/database/root.zig").FontStyle;
pub const DebugOverlay = @import("../../debug/root.zig").DebugOverlay;
pub const DebugOverlayList = @import("../../debug/root.zig").DebugOverlayList;
pub const OverlayKind = @import("../../debug/root.zig").OverlayKind;
pub const OverlayOptions = @import("../../debug/root.zig").OverlayOptions;
pub const combinedSystemFontSourcesForOs = @import("../../font/database/root.zig").combinedSystemFontSourcesForOs;
pub const defaultSystemFontSources = @import("../../font/database/root.zig").defaultSystemFontSources;
pub const defaultSystemFontSourcesForOs = @import("../../font/database/root.zig").defaultSystemFontSourcesForOs;
pub const manifestEntryMatchesBytes = @import("../../font/database/root.zig").manifestEntryMatchesBytes;
pub const measureAttributedRunsUtf8 = @import("../../text/attributed/root.zig").measureAttributedRunsUtf8;
pub const measureAttributedTextUtf8 = @import("../../text/attributed/root.zig").measureAttributedTextUtf8;
pub const parseManifest = @import("../../font/database/root.zig").parseManifest;
pub const readManifestFile = @import("../../font/database/root.zig").readManifestFile;
pub const serializeManifest = @import("../../font/database/root.zig").serializeManifest;
pub const userFontSourcesForOs = @import("../../font/database/root.zig").userFontSourcesForOs;
pub const writeManifestFile = @import("../../font/database/root.zig").writeManifestFile;
pub const Font = @import("../../font.zig").Font;
pub const FontContainerError = @import("../../font/container/root.zig").Error;
pub const FontContainerFormat = @import("../../font/container/root.zig").Format;
pub const default_max_decoded_font_size = @import("../../font/container/root.zig").default_max_decoded_size;
pub const OwnedFace = @import("../../font/container/root.zig").OwnedFace;
pub const decodeFontContainerAlloc = @import("../../font/container/root.zig").decodeFontContainerAlloc;
pub const detectFontContainerFormat = @import("../../font/container/root.zig").detectFormat;
pub const AnkrAnchorInfo = @import("../../font.zig").AnkrAnchorInfo;
pub const AnkrGlyphAnchorsInfo = @import("../../font.zig").AnkrGlyphAnchorsInfo;
pub const AnkrInfo = @import("../../font.zig").AnkrInfo;
pub const BaseAxisInfo = @import("../../font.zig").BaseAxisInfo;
pub const BaseInfo = @import("../../font.zig").BaseInfo;
pub const BaseScriptInfo = @import("../../font.zig").BaseScriptInfo;
pub const FeatureNameInfo = @import("../../font.zig").FeatureNameInfo;
pub const FeatureSettingInfo = @import("../../font.zig").FeatureSettingInfo;
pub const TrackInfo = @import("../../font.zig").TrackInfo;
pub const TrackTableInfo = @import("../../font.zig").TrackTableInfo;
pub const TrackValueInfo = @import("../../font.zig").TrackValueInfo;
pub const DsigInfo = @import("../../font.zig").DsigInfo;
pub const DsigSignatureInfo = @import("../../font.zig").DsigSignatureInfo;
pub const GaspInfo = @import("../../font.zig").GaspInfo;
pub const GaspRange = @import("../../font.zig").GaspRange;
pub const CharmapInfo = @import("../../font.zig").CharmapInfo;
pub const CharmapMapping = @import("../../font.zig").CharmapMapping;
pub const FontDecorationMetrics = @import("../../font.zig").FontDecorationMetrics;
pub const FontDecorationMetricSource = @import("../../font.zig").FontDecorationMetricSource;
pub const FontScriptMetrics = @import("../../font.zig").FontScriptMetrics;
pub const ScaledFontDecorationMetrics = @import("../../font.zig").ScaledFontDecorationMetrics;
pub const ScaledFontScriptMetrics = @import("../../font.zig").ScaledFontScriptMetrics;
pub const FontError = @import("../../font.zig").FontError;
pub const FontFormat = @import("../../font.zig").FontFormat;
pub const FontHeaderInfo = @import("../../font.zig").FontHeaderInfo;
pub const Cff2Info = @import("../../font.zig").Cff2Info;
pub const Cff2FontDictInfo = @import("../../font.zig").Cff2FontDictInfo;
pub const Cff2PrivateDictInfo = @import("../../font.zig").Cff2PrivateDictInfo;
pub const Cff2CharStringScanInfo = @import("../../font.zig").Cff2CharStringScanInfo;
pub const Cff2CharStringBoundsInfo = @import("../../font.zig").Cff2CharStringBoundsInfo;
pub const GvarInfo = @import("../../font.zig").GvarInfo;
pub const GvarGlyphInfo = @import("../../font.zig").GvarGlyphInfo;
pub const GvarTupleInfo = @import("../../font.zig").GvarTupleInfo;
pub const GvarScaledPointDelta = @import("../../font.zig").GvarScaledPointDelta;
pub const GvarPhantomPointDeltas = @import("../../font.zig").GvarPhantomPointDeltas;
pub const CvarInfo = @import("../../font.zig").CvarInfo;
pub const CvarTupleInfo = @import("../../font.zig").CvarTupleInfo;
pub const TrueTypeProgramInfo = @import("../../font.zig").TrueTypeProgramInfo;
pub const TrueTypeProgramInstructionInfo = @import("../../font.zig").TrueTypeProgramInstructionInfo;
pub const TrueTypeProgramKind = @import("../../font.zig").TrueTypeProgramKind;
pub const FontTableInfo = @import("../../font.zig").FontTableInfo;
pub const MathConstant = @import("../../font.zig").MathConstant;
pub const MathInfo = @import("../../font.zig").MathInfo;
pub const MathConstantsInfo = @import("../../font.zig").MathConstantsInfo;
pub const MathValueRecordInfo = @import("../../font.zig").MathValueRecordInfo;
pub const MathGlyphValueRecordInfo = @import("../../font.zig").MathGlyphValueRecordInfo;
pub const MathVariantRecordInfo = @import("../../font.zig").MathVariantRecordInfo;
pub const MathPartRecordInfo = @import("../../font.zig").MathPartRecordInfo;
pub const MathAssemblyInfo = @import("../../font.zig").MathAssemblyInfo;
pub const MathConstructionInfo = @import("../../font.zig").MathConstructionInfo;
pub const MathKernInfo = @import("../../font.zig").MathKernInfo;
pub const MathKernRecordInfo = @import("../../font.zig").MathKernRecordInfo;
pub const MathKernTableInfo = @import("../../font.zig").MathKernTableInfo;
pub const MaxProfileInfo = @import("../../font.zig").MaxProfileInfo;
pub const IftPatchMapInfo = @import("../../font.zig").IftPatchMapInfo;
pub const IftTableKeyedPatchInfo = @import("../../font.zig").IftTableKeyedPatchInfo;
pub const IftGlyphKeyedPatchInfo = @import("../../font.zig").IftGlyphKeyedPatchInfo;
pub const HdmxInfo = @import("../../font.zig").HdmxInfo;
pub const HdmxRecord = @import("../../font.zig").HdmxRecord;
pub const HvarInfo = @import("../../font.zig").HvarInfo;
pub const MetricVariationIndexMapEntryInfo = @import("../../font.zig").MetricVariationIndexMapEntryInfo;
pub const MetricVariationIndexMapInfo = @import("../../font.zig").MetricVariationIndexMapInfo;
pub const LtshInfo = @import("../../font.zig").LtshInfo;
pub const LtagRecordInfo = @import("../../font.zig").LtagRecordInfo;
pub const HorizontalMetricInfo = @import("../../font.zig").HorizontalMetricInfo;
pub const MetricHeaderInfo = @import("../../font.zig").MetricHeaderInfo;
pub const VerticalMetricInfo = @import("../../font.zig").VerticalMetricInfo;
pub const VerticalOriginInfo = @import("../../font.zig").VerticalOriginInfo;
pub const VerticalOriginMetric = @import("../../font.zig").VerticalOriginMetric;
pub const GlyphClass = @import("../../font.zig").GlyphClass;
pub const NameEncoding = @import("../../font.zig").NameEncoding;
pub const NameId = @import("../../font.zig").NameId;
pub const NameLanguageTagInfo = @import("../../font.zig").NameLanguageTagInfo;
pub const NameRecordInfo = @import("../../font.zig").NameRecordInfo;
pub const MetaRecordInfo = @import("../../font.zig").MetaRecordInfo;
pub const MvarInfo = @import("../../font.zig").MvarInfo;
pub const MvarValueRecordInfo = @import("../../font.zig").MvarValueRecordInfo;
pub const VvarInfo = @import("../../font.zig").VvarInfo;
pub const VarcInfo = @import("../../font.zig").VarcInfo;
pub const Os2Info = @import("../../font.zig").Os2Info;
pub const FontFallbackDecision = @import("../../shaping/diagnostics/types.zig").FontFallbackDecision;
pub const KernInfo = @import("../../font.zig").KernInfo;
pub const KernSubtableInfo = @import("../../font.zig").KernSubtableInfo;
pub const KerxInfo = @import("../../font.zig").KerxInfo;
pub const KerxPairInfo = @import("../../font.zig").KerxPairInfo;
pub const KerxSubtableInfo = @import("../../font.zig").KerxSubtableInfo;
pub const MorxChainInfo = @import("../../font.zig").MorxChainInfo;
pub const MorxFeatureInfo = @import("../../font.zig").MorxFeatureInfo;
pub const MorxInfo = @import("../../font.zig").MorxInfo;
pub const MorxSubtableInfo = @import("../../font.zig").MorxSubtableInfo;
pub const KernTableDialect = @import("../../font.zig").KernTableDialect;
pub const GlyphMetrics = layout_cache.GlyphMetrics;
pub const MissingGlyphDiagnostic = @import("../../shaping/diagnostics/types.zig").MissingGlyphDiagnostic;
pub const BitmapGlyphPng = @import("../../font.zig").BitmapGlyphPng;
pub const BitmapGlyphInfo = @import("../../font.zig").BitmapGlyphInfo;
pub const BitmapStrikeInfo = @import("../../font.zig").BitmapStrikeInfo;
pub const BitmapStrikeSource = @import("../../font.zig").BitmapStrikeSource;
pub const ColorLayer = @import("../../font.zig").ColorLayer;
pub const ColorPaint = @import("../../font.zig").ColorPaint;
pub const ColorClipBox = @import("../../font.zig").ColorClipBox;
pub const ColorAffine = @import("../../font.zig").ColorAffine;
pub const ColorGlyphPaint = @import("../../render/bridge/root.zig").ColorGlyphPaint;
pub const PaletteColor = @import("../../font.zig").PaletteColor;
pub const PaletteInfo = @import("../../font.zig").PaletteInfo;
pub const PcltInfo = @import("../../font.zig").PcltInfo;
pub const PostInfo = @import("../../font.zig").PostInfo;
pub const SvgGlyphDocument = @import("../../font.zig").SvgGlyphDocument;
pub const ResolvedSvgGlyphDocument = @import("../../font.zig").ResolvedSvgGlyphDocument;
pub const StatAxisValue = @import("../../font.zig").StatAxisValue;
pub const StatAxisValueCoordinate = @import("../../font.zig").StatAxisValueCoordinate;
pub const StatDesignAxis = @import("../../font.zig").StatDesignAxis;
pub const VariationAxis = @import("../../font.zig").VariationAxis;
pub const VariationCoordinate = @import("../../font.zig").VariationCoordinate;
pub const VariationInstance = @import("../../font.zig").VariationInstance;
pub const VariationSequenceKind = @import("../../font.zig").VariationSequenceKind;
pub const VerticalMetrics = @import("../../font.zig").VerticalMetrics;
pub const GlyphId = @import("../../glyph.zig").GlyphId;
pub const GlyphLocationInfo = @import("../../font.zig").GlyphLocationInfo;
pub const Bounds = @import("../../glyph.zig").Bounds;
pub const GlyphOutline = @import("../../glyph.zig").GlyphOutline;
pub const OutlineBuilder = @import("../../glyph.zig").OutlineBuilder;
pub const BaselineMetrics = @import("../../layout/line_break/reflow/root.zig").BaselineMetrics;
pub const GlyphRun = @import("../../layout/types/runs.zig").GlyphRun;
pub const GlyphOrientation =
    @import("../../layout/glyph_position.zig").Orientation;
pub const GlyphPosition = @import("../../layout/glyph_position.zig").GlyphPosition;
pub const BridgeOptions = @import("../../render/bridge/root.zig").BridgeOptions;
pub const ColorGlyphDrawCommand = @import("../../render/bridge/root.zig").ColorGlyphDrawCommand;
pub const ColorGlyphLayerCommand = @import("../../render/bridge/root.zig").ColorGlyphLayerCommand;
pub const CascadeRun = @import("../../layout/types/runs.zig").CascadeRun;
pub const FontCascade = @import("../../shaping/fallback/font/root.zig").Cascade;
pub const GlyphAtlasCacheKey = @import("../../render/bridge/root.zig").GlyphAtlasCacheKey;
pub const GlyphAtlasContent = @import("../../render/bridge/root.zig").GlyphAtlasContent;
pub const GlyphAtlasRequest = @import("../../render/bridge/root.zig").GlyphAtlasRequest;
pub const GlyphDrawList = @import("../../render/bridge/root.zig").GlyphDrawList;
pub const GlyphPathCacheKey = @import("../../render/bridge/root.zig").GlyphPathCacheKey;
pub const GlyphPathRequest = @import("../../render/bridge/root.zig").GlyphPathRequest;
pub const GlyphPathSource = @import("../../render/bridge/root.zig").GlyphPathSource;
pub const GlyphRenderMode = @import("../../render/bridge/root.zig").GlyphRenderMode;
pub const GlyphRunDrawCommand = @import("../../render/bridge/root.zig").GlyphRunDrawCommand;
pub const ParagraphLayout = @import("../../layout/types/paragraph.zig").ParagraphLayout;
pub const ParagraphLine = @import("../../layout/types/paragraph.zig").ParagraphLine;
pub const ParagraphOptions = @import("../../layout/paragraph/options.zig").Options;
pub const ReflowBuffer = @import("../../layout/paragraph/retained.zig").ReflowBuffer;
pub const ShapedParagraph = @import("../../layout/paragraph/retained.zig").ShapedParagraph;
pub const StyledGlyphMetadata = @import("../../layout/styled_buffer.zig").Metadata;
pub const StyledParagraphBuffer = @import("../../layout/styled_buffer.zig").Buffer;
pub const StyledParagraphSpan = @import("../../layout/styled_paragraph.zig").Span;
pub const PositionedGlyph = @import("../../render/bridge/root.zig").PositionedGlyph;
pub const PositionedAttributedRun = @import("../../text/attributed/root.zig").PositionedAttributedRun;
pub const ClusterLevel = @import("../../shaping/pipeline/types.zig").ClusterLevel;
pub const ScriptPosition = @import("../../shaping/pipeline/types.zig").ScriptPosition;
pub const ShapeOptions = shaping_plan.ShapeOptions;
pub const ShapeStageProfile = @import("../../shape_profile.zig").ShapeStageProfile;
pub const ClusterCaretConsistencyReport = @import("../../shaping/diagnostics/types.zig").ClusterCaretConsistencyReport;
pub const ClusterCaretDiagnostic = @import("../../shaping/diagnostics/types.zig").ClusterCaretDiagnostic;
pub const ClusterCaretIssueKind = @import("../../shaping/diagnostics/types.zig").ClusterCaretIssueKind;
pub const ShapeQualityFontRunDiagnostic = @import("../../shaping/diagnostics/types.zig").ShapeQualityFontRunDiagnostic;
pub const ShapeQualityReport = @import("../../shaping/diagnostics/types.zig").ShapeQualityReport;
pub const ShapeQualityScriptRunDiagnostic = @import("../../shaping/diagnostics/types.zig").ShapeQualityScriptRunDiagnostic;
pub const ShapedText = @import("../../layout/types/runs.zig").ShapedText;
pub const ScriptedRun = @import("../../layout/types/runs.zig").ScriptedRun;
pub const ScriptedText = @import("../../layout/types/runs.zig").ScriptedText;
pub const TextAlign = @import("../../layout/types/paragraph.zig").TextAlign;
pub const TextCursorGeometry = @import("../../render/bridge/root.zig").TextCursorGeometry;
pub const TextDirection = @import("../../shaping/pipeline/types.zig").TextDirection;
pub const TextOrientation = @import("../../shaping/pipeline/types.zig").TextOrientation;
pub const WritingMode = @import("../../shaping/pipeline/types.zig").WritingMode;
pub const TextPosition = @import("../../layout/types/paragraph.zig").TextPosition;
pub const TextRect = @import("../../layout/types/paragraph.zig").TextRect;
pub const TextSelectionGeometry = @import("../../render/bridge/root.zig").TextSelectionGeometry;
pub const Engine = @import("../../shaping/context/root.zig").Engine;
pub const buildBidiMap = @import("../../unicode.zig").buildBidiMap;
pub const buildDebugOverlays = @import("../../debug/root.zig").buildDebugOverlays;
pub const buildGlyphDrawList = @import("../../render/bridge/root.zig").buildGlyphDrawList;
pub const dumpBidiMap = @import("../../debug/root.zig").dumpBidiMap;
pub const dumpBidiRuns = @import("../../debug/root.zig").dumpBidiRuns;
pub const dumpDebugOverlays = @import("../../debug/root.zig").dumpDebugOverlays;
pub const dumpFontCoverage = @import("../../debug/root.zig").dumpFontCoverage;
pub const dumpFontFallback = @import("../../debug/root.zig").dumpFontFallback;
pub const dumpGlyphClusters = @import("../../debug/root.zig").dumpGlyphClusters;
pub const dumpHitTest = @import("../../debug/root.zig").dumpHitTest;
pub const dumpLineBreaks = @import("../../debug/root.zig").dumpLineBreaks;
pub const dumpMissingGlyphs = @import("../../debug/root.zig").dumpMissingGlyphs;
pub const dumpParagraphLayout = @import("../../debug/root.zig").dumpParagraphLayout;
pub const dumpSelectionRects = @import("../../debug/root.zig").dumpSelectionRects;
pub const dumpShapeRuns = @import("../../debug/root.zig").dumpShapeRuns;
pub const dumpUnicodeSegmentation = @import("../../debug/root.zig").dumpUnicodeSegmentation;
pub const diagnoseClusterCaretConsistencyUtf8 = test_diagnostics.clusterCaretConsistency;
pub const diagnoseFontFallbackUtf8 = @import("../../shaping/diagnostics/fallback.zig").analyze;
pub const diagnoseShapeQualityUtf8 = test_diagnostics.shapeQuality;
pub const inferOpenTypeLanguageTag = @import("../../unicode.zig").inferOpenTypeLanguageTag;
pub const lineBreakClassForCodepoint = @import("../../unicode.zig").lineBreakClassForCodepoint;
pub const lineBreaks = @import("../../unicode.zig").lineBreaks;
pub const openTypeLanguageTagForLocale = @import("../../unicode.zig").openTypeLanguageTagForLocale;
pub const itemizeBidiRuns = @import("../../unicode.zig").itemizeBidiRuns;
pub const itemizeGraphemeClusters = @import("../../unicode.zig").itemizeGraphemeClusters;
pub const itemizeLineBreaks = @import("../../unicode.zig").itemizeLineBreaks;
pub const itemizeScriptRuns = @import("../../unicode.zig").itemizeScriptRuns;
pub const itemizeWordSegments = @import("../../unicode.zig").itemizeWordSegments;
pub const layoutAttributedRunsUtf8 = @import("../../text/attributed/root.zig").layoutAttributedRunsUtf8;
pub const layoutAttributedGlyphRunsUtf8 = @import("../../text/attributed/root.zig").layoutAttributedGlyphRunsUtf8;
pub const layoutAttributedParagraphUtf8 = @import("../../text/attributed/root.zig").layoutAttributedParagraphUtf8;
pub const openTypeTag = @import("../../unicode.zig").tag;
pub const openTypeScriptTag = @import("../../unicode.zig").openTypeScriptTag;
pub const openTypeScriptHorizontalDirection = @import("../../unicode.zig").openTypeScriptHorizontalDirection;
pub const paragraphDirection = @import("../../unicode.zig").paragraphDirection;
pub const joiningTypeForCodepoint = @import("../../unicode.zig").joiningTypeForCodepoint;
pub const resolveJoiningForms = @import("../../unicode.zig").resolveJoiningForms;
pub const verticalOrientationForCodepoint = @import("../../unicode.zig").verticalOrientationForCodepoint;
pub const scriptForCodepoint = @import("../../unicode.zig").scriptForCodepoint;
pub const mirroredCodepoint = @import("../../unicode.zig").mirroredCodepoint;
pub const ColorRenderTarget = @import("../../raster.zig").ColorRenderTarget;
pub const PreparedGlyph = @import("../../raster.zig").PreparedGlyph;
pub const RenderTarget = @import("../../raster.zig").RenderTarget;
pub const Rgba = @import("../../raster.zig").Rgba;
pub const Rasterizer = @import("../../raster.zig").Rasterizer;
pub const bidiClassForCodepoint = @import("../../unicode.zig").bidiClassForCodepoint;
pub const exactBidiClassForCodepoint = @import("../../unicode.zig").exactBidiClassForCodepoint;
pub const resolveBidiParagraph = @import("../../unicode.zig").resolveBidiParagraph;

const test_diagnostics = struct {
    const orchestration = @import("../../shaping/diagnostics/orchestration.zig");
    const ordinary_shaper = @import("../../shaping/orchestrator.zig").TextShaper;

    pub fn clusterCaretConsistency(
        allocator: std.mem.Allocator,
        cascade: @import("../../shaping/fallback/font/root.zig").Cascade,
        text: []const u8,
        font_size: f32,
        options: shaping_plan.ShapeOptions,
    ) !@import("../../shaping/diagnostics/types.zig").ClusterCaretConsistencyReport {
        return orchestration.clusterCaretConsistency(
            ordinary_shaper,
            allocator,
            cascade,
            text,
            font_size,
            options,
        );
    }

    pub fn shapeQuality(
        allocator: std.mem.Allocator,
        cascade: @import("../../shaping/fallback/font/root.zig").Cascade,
        text: []const u8,
        font_size: f32,
        options: shaping_plan.ShapeOptions,
    ) !@import("../../shaping/diagnostics/types.zig").ShapeQualityReport {
        return orchestration.shapeQuality(
            ordinary_shaper,
            allocator,
            cascade,
            text,
            font_size,
            options,
        );
    }
};

pub const testing = struct {
    pub const test_font = @import("../../test_font.zig");
    pub const font_container = @import("../../font/container/root.zig").testing;
    /// Internal shaping boundaries shared with repository-owned parity tools.
    /// They are intentionally not part of the supported font-stack API.
    pub const shaping_cluster = @import("../../unicode/grapheme/shaping_cluster.zig");
};

pub fn renderTargetPixelDifference(a: *const RenderTarget, b: *const RenderTarget) usize {
    if (a.width != b.width or a.height != b.height or a.pixels.len != b.pixels.len) return std.math.maxInt(usize);
    var diff: usize = 0;
    for (a.pixels, b.pixels) |lhs, rhs| {
        if (lhs != rhs) diff += 1;
    }
    return diff;
}

pub fn colorRenderTargetPixelDifference(a: *const ColorRenderTarget, b: *const ColorRenderTarget) usize {
    if (a.width != b.width or a.height != b.height or a.pixels.len != b.pixels.len) return std.math.maxInt(usize);
    var diff: usize = 0;
    for (a.pixels, b.pixels) |lhs, rhs| {
        if (lhs.r != rhs.r or lhs.g != rhs.g or lhs.b != rhs.b or lhs.a != rhs.a) diff += 1;
    }
    return diff;
}

pub fn lineAdvanceSum(glyphs: []const GlyphPosition) f32 {
    var sum: f32 = 0;
    for (glyphs) |glyph| sum += glyph.x_advance;
    return sum;
}

pub fn writeKernFormat0SubtableTest(bytes: []u8, offset: usize, coverage: u16, left: GlyphId, right: GlyphId, value: i16) void {
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

pub fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    writeU16Test(bytes, offset, @bitCast(value));
}

pub fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

pub fn writeI32Test(bytes: []u8, offset: usize, value: i32) void {
    writeU32Test(bytes, offset, @bitCast(value));
}

pub fn writeU16Root(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32Root(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
