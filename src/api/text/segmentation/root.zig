//! Streaming Unicode grapheme, word, sentence, and line boundaries.

const dictionary = @import("../../../text/segmentation/root.zig");
const unicode = @import("../../../unicode.zig");

pub const Grapheme = unicode.GraphemeCluster;
pub const GraphemeIterator = unicode.GraphemeClusterIterator;
pub const Word = unicode.WordSegment;
pub const WordBoundary = unicode.WordBoundarySegment;
pub const WordIterator = unicode.WordBoundaryIterator;
pub const Sentence = unicode.SentenceSegment;
pub const SentenceIterator = unicode.SentenceBoundaryIterator;
pub const LineBreak = unicode.LineBreak;
pub const LineBreakKind = unicode.LineBreakKind;
pub const LineBreakClass = unicode.LineBreakClass;
pub const LineBreakIterator = unicode.LineBreakIterator;
pub const WordDictionary = dictionary.WordBreakDictionary;

pub const grapheme_unicode_version = unicode.grapheme_unicode_version;
pub const word_unicode_version = unicode.word_unicode_version;
pub const sentence_unicode_version = unicode.sentence_unicode_version;
pub const line_break_unicode_version = unicode.line_break_unicode_version;

pub const graphemes = unicode.graphemeClusters;
pub const words = unicode.wordSegments;
pub const sentences = unicode.sentenceSegments;
pub const lineBreaks = unicode.lineBreaks;
pub const lineBreakClass = unicode.lineBreakClassForCodepoint;

pub const collect = struct {
    pub const graphemes = unicode.itemizeGraphemeClusters;
    pub const words = unicode.itemizeWordSegments;
    pub const sentences = unicode.itemizeSentenceSegments;
    pub const lineBreaks = unicode.itemizeLineBreaks;
};
