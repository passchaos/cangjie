//! Streaming Unicode grapheme, word, sentence, and line boundaries.

const std = @import("std");

const dictionary = @import("../../../text/segmentation/root.zig");
const dictionary_breaks =
    @import("../../../text/segmentation/dictionary_breaks.zig");
const unicode = @import("../../../unicode.zig");

pub const Grapheme = unicode.GraphemeCluster;
pub const GraphemeIterator = unicode.GraphemeClusterIterator;
pub const Word = unicode.WordBoundarySegment;
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

fn collectWords(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]Word {
    var result = std.ArrayList(Word).empty;
    errdefer result.deinit(allocator);
    var iterator = try words(text);
    while (iterator.next()) |segment| {
        try result.append(allocator, segment);
    }
    return result.toOwnedSlice(allocator);
}

fn collectSentences(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]Sentence {
    var result = std.ArrayList(Sentence).empty;
    errdefer result.deinit(allocator);
    var iterator = try sentences(text);
    while (iterator.next()) |segment| {
        try result.append(allocator, segment);
    }
    return result.toOwnedSlice(allocator);
}

fn collectLineBreaks(
    allocator: std.mem.Allocator,
    text: []const u8,
    word_dictionary: ?*const WordDictionary,
) ![]LineBreak {
    const grapheme_items = try unicode.itemizeGraphemeClusters(
        allocator,
        text,
    );
    defer allocator.free(grapheme_items);
    const base = try unicode.itemizeLineBreaks(allocator, text);
    defer allocator.free(base);
    const tailoring = word_dictionary orelse
        return try allocator.dupe(LineBreak, base);
    return dictionary_breaks.mergeLineBreaks(
        allocator,
        tailoring,
        text,
        grapheme_items,
        base,
    );
}

pub const collect = struct {
    pub const graphemes = unicode.itemizeGraphemeClusters;

    /// Collect every UAX #29 word-boundary segment, including punctuation and
    /// whitespace. `Word.is_word` is classification, not a filter.
    pub fn words(
        allocator: std.mem.Allocator,
        text: []const u8,
    ) ![]Word {
        return collectWords(allocator, text);
    }

    /// Collect every UAX #29 sentence segment without editor-oriented
    /// filtering of blank separator spans.
    pub fn sentences(
        allocator: std.mem.Allocator,
        text: []const u8,
    ) ![]Sentence {
        return collectSentences(allocator, text);
    }

    /// Collect line-break opportunities with optional dictionary tailoring.
    ///
    /// The returned slice is allocator-owned. Passing `null` yields the
    /// default UAX #14 opportunities; a dictionary adds soft boundaries for
    /// its script while preserving hard breaks and grapheme safety.
    pub fn lineBreaks(
        allocator: std.mem.Allocator,
        text: []const u8,
        word_dictionary: ?*const WordDictionary,
    ) ![]LineBreak {
        return collectLineBreaks(allocator, text, word_dictionary);
    }
};
