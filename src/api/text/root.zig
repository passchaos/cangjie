//! Unicode analysis, OpenType segment properties, and paragraph styles.

const core = @import("../../core.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode_impl = @import("../../unicode.zig");

pub const Script = unicode_impl.Script;
pub const ScriptRun = unicode_impl.ScriptRun;
pub const BidiClass = unicode_impl.BidiClass;
pub const ExactBidiClass = unicode_impl.ExactBidiClass;
pub const BidiBaseDirection = unicode_impl.BidiBaseDirection;
pub const BidiParagraph = unicode_impl.BidiParagraph;
pub const BidiMap = unicode_impl.BidiMap;
pub const BidiMapItem = unicode_impl.BidiMapItem;
pub const BidiRun = unicode_impl.BidiRun;
pub const JoiningForm = unicode_impl.JoiningForm;
pub const JoiningType = unicode_impl.JoiningType;
pub const VerticalOrientation = unicode_impl.VerticalOrientation;

pub const GraphemeCluster = unicode_impl.GraphemeCluster;
pub const GraphemeIterator = unicode_impl.GraphemeClusterIterator;
pub const WordSegment = unicode_impl.WordSegment;
pub const WordBoundarySegment = unicode_impl.WordBoundarySegment;
pub const WordIterator = unicode_impl.WordBoundaryIterator;
pub const SentenceSegment = unicode_impl.SentenceSegment;
pub const SentenceIterator = unicode_impl.SentenceBoundaryIterator;
pub const LineBreak = unicode_impl.LineBreak;
pub const LineBreakKind = unicode_impl.LineBreakKind;
pub const LineBreakClass = unicode_impl.LineBreakClass;
pub const LineBreakIterator = unicode_impl.LineBreakIterator;

pub const bidi_unicode_version = unicode_impl.bidi_unicode_version;
pub const grapheme_unicode_version = unicode_impl.grapheme_unicode_version;
pub const word_unicode_version = unicode_impl.word_unicode_version;
pub const sentence_unicode_version = unicode_impl.sentence_unicode_version;
pub const line_break_unicode_version = unicode_impl.line_break_unicode_version;

pub const Feature = unicode_impl.FeatureOverride;
pub const FeatureRange = unicode_impl.GsubFeatureRange;
pub const OpenTypeLanguage = unicode_impl.OpenTypeLanguageTag;
pub const OpenTypeScript = unicode_impl.OpenTypeScriptTag;
pub const WordBreakDictionary = segmentation.WordBreakDictionary;

pub const AttributedText = core.AttributedText;
pub const AttributedRun = core.AttributedRun;
pub const AttributedRunLayout = core.AttributedRunLayout;
pub const AttributedGlyphRun = core.AttributedGlyphRun;
pub const AttributedGlyphRunLayout = core.AttributedGlyphRunLayout;
pub const AttributedParagraphLayout = core.AttributedParagraphLayout;
pub const AttributedStyleRun = core.AttributedStyleRun;
pub const ByteRange = core.ByteRange;
pub const CharRange = core.CharRange;
pub const ClusterRange = core.ClusterRange;
pub const GraphemeRange = core.GraphemeRange;
pub const GlyphCluster = core.GlyphCluster;
pub const GlyphRange = core.GlyphRange;
pub const Language = core.Language;
pub const Locale = core.Locale;
pub const OverflowMode = core.OverflowMode;
pub const ParagraphStyle = core.ParagraphStyle;
pub const StyleSpan = core.StyleSpan;
pub const Decoration = core.TextDecoration;
pub const FontStyle = core.TextFontStyle;
pub const Metrics = core.TextMetrics;
pub const Range = core.TextRange;
pub const Span = core.TextSpan;
pub const Style = core.TextStyle;
pub const VerticalAlign = core.VerticalAlign;
pub const WrapMode = core.WrapMode;
pub const FontWeight = core.FontWeight;
pub const FontId = core.FontId;

pub const graphemes = unicode_impl.graphemeClusters;
pub const words = unicode_impl.wordSegments;
pub const sentences = unicode_impl.sentenceSegments;
pub const lineBreaks = unicode_impl.lineBreaks;
pub const lineBreakClass = unicode_impl.lineBreakClassForCodepoint;
pub const resolveBidi = unicode_impl.resolveBidiParagraph;
pub const buildBidiMap = unicode_impl.buildBidiMap;
pub const script = unicode_impl.scriptForCodepoint;
pub const bidiClass = unicode_impl.bidiClassForCodepoint;
pub const exactBidiClass = unicode_impl.exactBidiClassForCodepoint;
pub const paragraphDirection = unicode_impl.paragraphDirection;
pub const joiningType = unicode_impl.joiningTypeForCodepoint;
pub const resolveJoiningForms = unicode_impl.resolveJoiningForms;
pub const mirroredCodepoint = unicode_impl.mirroredCodepoint;
pub const verticalOrientation = unicode_impl.verticalOrientationForCodepoint;

pub const openTypeTag = unicode_impl.tag;
pub const openTypeScript = unicode_impl.openTypeScriptTag;
pub const openTypeScriptHorizontalDirection =
    unicode_impl.openTypeScriptHorizontalDirection;
pub const inferOpenTypeLanguage = unicode_impl.inferOpenTypeLanguageTag;
pub const openTypeLanguageForLocale = unicode_impl.openTypeLanguageTagForLocale;

/// Allocating collectors remain available explicitly, but the streaming
/// functions above are the preferred default for analysis pipelines.
pub const collect = struct {
    pub const bidiRuns = unicode_impl.itemizeBidiRuns;
    pub const graphemes = unicode_impl.itemizeGraphemeClusters;
    pub const lineBreaks = unicode_impl.itemizeLineBreaks;
    pub const sentences = unicode_impl.itemizeSentenceSegments;
    pub const scriptRuns = unicode_impl.itemizeScriptRuns;
    pub const words = unicode_impl.itemizeWordSegments;
    pub const visualOrderBidiRuns = unicode_impl.visualOrderBidiRuns;
    pub const visualOrderCodepoints = unicode_impl.visualOrderCodepoints;
    pub const visualOrderUtf8 = unicode_impl.visualOrderUtf8;
};

pub const attributed = struct {
    pub const measureRuns = core.measureAttributedRunsUtf8;
    pub const measure = core.measureAttributedTextUtf8;
    pub const layoutRuns = core.layoutAttributedRunsUtf8;
    pub const layoutGlyphRuns = core.layoutAttributedGlyphRunsUtf8;
    pub const layoutParagraph = core.layoutAttributedParagraphUtf8;
};
