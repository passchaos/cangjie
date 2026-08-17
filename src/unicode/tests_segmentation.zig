//! Unicode contract tests migrated from the former aggregate root.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "streaming grapheme iterator matches allocating collector" {
    const allocator = std.testing.allocator;
    const samples = [_][]const u8{
        "",
        "ASCII\r\ntext",
        "A\u{0301}B",
        "\u{1f469}\u{200d}\u{1f4bb}",
        "\u{0915}\u{094d}\u{200d}\u{0937}",
        "\u{1f1fa}\u{1f1f8}\u{1f1e8}",
    };
    for (samples) |sample| {
        const collected = try unicode.itemizeGraphemeClusters(allocator, sample);
        defer allocator.free(collected);
        var iterator = try unicode.graphemeClusters(sample);
        var index: usize = 0;
        while (iterator.next()) |cluster| : (index += 1) {
            try std.testing.expect(index < collected.len);
            try std.testing.expectEqual(collected[index], cluster);
        }
        try std.testing.expectEqual(collected.len, index);
    }
    try std.testing.expectError(error.InvalidUtf8, unicode.graphemeClusters("\xff"));
}

test "RTL bidi map walks long grapheme runs without losing item boundaries" {
    const allocator = std.testing.allocator;
    const grapheme = "א\u{05b0}";
    const grapheme_count = 64;
    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    for (0..grapheme_count) |_| try text.appendSlice(allocator, grapheme);

    var map = try unicode.buildBidiMap(allocator, text.items, .rtl);
    defer map.deinit();
    try std.testing.expectEqual(@as(usize, grapheme_count * 2), map.items.len);

    for (0..grapheme_count) |visual_cluster| {
        const logical_cluster = grapheme_count - 1 - visual_cluster;
        const logical_base = logical_cluster * 2;
        const visual_base = visual_cluster * 2;
        // UAX #9 reverses grapheme groups through their resolved level while
        // preserving the logical base-before-mark order inside each group.
        try std.testing.expectEqual(
            logical_base,
            map.items[visual_base].logical_index,
        );
        try std.testing.expectEqual(
            logical_base + 1,
            map.items[visual_base + 1].logical_index,
        );
        try std.testing.expectEqual(
            visual_base,
            map.logical_to_visual[logical_base],
        );
        try std.testing.expectEqual(
            visual_base + 1,
            map.logical_to_visual[logical_base + 1],
        );
    }
}

test "word segmentation keeps interior apostrophes but trims quotes" {
    const allocator = std.testing.allocator;

    const words = try unicode.itemizeWordSegments(allocator, "'alpha' don't rock 'n' roll");
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("alpha", "'alpha' don't rock 'n' roll"[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("don't", "'alpha' don't rock 'n' roll"[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("rock", "'alpha' don't rock 'n' roll"[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("n", "'alpha' don't rock 'n' roll"[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("roll", "'alpha' don't rock 'n' roll"[words[4].byte_start..][0..words[4].byte_len]);
}

test "line breaks do not start lines with East Asian closing punctuation" {
    const allocator = std.testing.allocator;

    const text = "你。好";
    const breaks = try unicode.itemizeLineBreaks(allocator, text);
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 2), breaks.len);
    try std.testing.expectEqual(@as(usize, 6), breaks[0].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, text.len), breaks[1].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.hard, breaks[1].kind);
}

test "line breaks include breakable Unicode space separators" {
    const allocator = std.testing.allocator;

    const breaks = try unicode.itemizeLineBreaks(allocator, "a\xe3\x80\x80b\xc2\xa0c\xe2\x80\x83d");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 3), breaks.len);
    try std.testing.expectEqual(@as(usize, 4), breaks[0].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 11), breaks[1].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 12), breaks[2].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.hard, breaks[2].kind);
}

test "sentence segmentation keeps Arabic-Indic decimal numbers together" {
    const text = "القيمة ١.٢ جيدة. انتهى";
    var sentences = try unicode.sentenceSegments(text);
    const first = sentences.next().?;
    const second = sentences.next().?;
    try std.testing.expect(sentences.next() == null);
    try std.testing.expectEqualStrings(
        "القيمة ١.٢ جيدة. ",
        text[first.byte_start..][0..first.byte_len],
    );
    try std.testing.expectEqualStrings(
        "انتهى",
        text[second.byte_start..][0..second.byte_len],
    );
}

test "sentence segmentation treats CRLF as a hard boundary" {
    const text = "First\r\nSecond. Third";
    var sentences = try unicode.sentenceSegments(text);
    const first = sentences.next().?;
    const second = sentences.next().?;
    const third = sentences.next().?;
    try std.testing.expect(sentences.next() == null);
    try std.testing.expectEqualStrings(
        "First\r\n",
        text[first.byte_start..][0..first.byte_len],
    );
    try std.testing.expectEqualStrings(
        "Second. ",
        text[second.byte_start..][0..second.byte_len],
    );
    try std.testing.expectEqualStrings(
        "Third",
        text[third.byte_start..][0..third.byte_len],
    );
}

test "grapheme clusters keep Devanagari virama ZWJ conjuncts atomic" {
    const allocator = std.testing.allocator;

    const text = "क्‍ष क्ष";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("क्‍ष", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("क्ष", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "grapheme clusters keep Gujarati virama ZWJ conjuncts atomic" {
    const allocator = std.testing.allocator;

    const text = "ક્‍ષ ક્ષ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ક્‍ષ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ક્ષ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "grapheme clusters keep Thai and Lao marks with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ก้ ກີ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ก้", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ກີ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "grapheme clusters keep Myanmar dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ကေ့ ကွာ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("ကေ့", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ကွ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ာ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
}

test "grapheme clusters keep Miao vowel and tone signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "\u{16f0a}\u{16f57}\u{16f8f}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 1), clusters.len);
    try std.testing.expectEqualStrings(text, text[clusters[0].byte_start..][0..clusters[0].byte_len]);
}

test "halfwidth katakana voiced marks stay in kana grapheme and script runs" {
    const allocator = std.testing.allocator;

    const text = "ｶﾞ ㇰ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ｶﾞ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ㇰ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.katakana, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kana, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xff76)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kana, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x31f0)));
}

test "grapheme clusters keep Khmer dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "កា ក់ កៀ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("កា", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ក់", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("កៀ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
}

test "grapheme clusters attach non-Arabic prepend signs to following bases" {
    const allocator = std.testing.allocator;

    const text = "ൎക 𑂽𑂦";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ൎക", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("𑂽𑂦", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "Ethiopic combining marks inherit one grapheme cluster" {
    const allocator = std.testing.allocator;
    const samples = [_][]const u8{ "ለ፝", "ለ፞", "ለ፟" };

    inline for (samples, 0x135d..) |text, mark| {
        const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
        defer allocator.free(clusters);

        try std.testing.expectEqual(@as(usize, 1), clusters.len);
        try std.testing.expectEqual(@as(usize, 0), clusters[0].byte_start);
        try std.testing.expectEqual(text.len, clusters[0].byte_len);
        try std.testing.expect(unicode.isNonspacingMarkCodepoint(@intCast(mark)));
        try std.testing.expect(unicode.isUnicodeMarkCodepoint(@intCast(mark)));
    }
}

test "Vedic marks retain their Brahmic grapheme cluster" {
    const allocator = std.testing.allocator;

    const nonspacing_text = "𑌨᳴";
    const nonspacing_clusters = try unicode.itemizeGraphemeClusters(allocator, nonspacing_text);
    defer allocator.free(nonspacing_clusters);
    try std.testing.expectEqualSlices(
        unicode.GraphemeCluster,
        &.{.{ .byte_start = 0, .byte_len = nonspacing_text.len }},
        nonspacing_clusters,
    );

    const spacing_text = "𑌨᳡";
    const spacing_clusters = try unicode.itemizeGraphemeClusters(allocator, spacing_text);
    defer allocator.free(spacing_clusters);
    try std.testing.expectEqualSlices(
        unicode.GraphemeCluster,
        &.{.{ .byte_start = 0, .byte_len = spacing_text.len }},
        spacing_clusters,
    );
}
