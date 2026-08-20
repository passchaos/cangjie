//! Unicode contract tests migrated from the former aggregate root.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "Khmer text selects Khmer script and keeps COENG clusters" {
    const allocator = std.testing.allocator;

    const text = "\u{1780}\u{17b6} \u{1780}\u{17d2}\u{1781} \u{17e1}\u{17d4} \u{19e0}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("\u{1780}\u{17b6}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1780}\u{17d2}\u{1781}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{17e1}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{17d4}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{19e0}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.khmer, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.khmr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1780)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.khmr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x17d2)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.khmr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x19e0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1780));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{1780}\u{17b6}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1780}\u{17d2}\u{1781}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{17e1}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Telugu and Kannada syllables select Indic v2 script tags" {
    const allocator = std.testing.allocator;

    const text = "కి కా క్‍ష ಕಿ ಕಾ ಕ್‍ಷ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 12), clusters.len);
    try std.testing.expectEqualStrings("కి", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("కా", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("క్‍ష", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("ಕಿ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("ಕಾ", text[clusters[8].byte_start..][0..clusters[8].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[9].byte_start..][0..clusters[9].byte_len]);
    try std.testing.expectEqualStrings("ಕ್‍", text[clusters[10].byte_start..][0..clusters[10].byte_len]);
    try std.testing.expectEqualStrings("ಷ", text[clusters[11].byte_start..][0..clusters[11].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(unicode.Script.telugu, runs[0].script);
    try std.testing.expectEqualStrings("కి కా క్‍ష ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(unicode.Script.kannada, runs[1].script);
    try std.testing.expectEqualStrings("ಕಿ ಕಾ ಕ್‍ಷ", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tel2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0c15)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tel2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0c4d)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.knd2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0c95)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.knd2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0ccd)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0c15));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0c95));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 6), words.len);
    try std.testing.expectEqualStrings("కి", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("కా", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("క్‍ష", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("ಕಿ", text[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("ಕಾ", text[words[4].byte_start..][0..words[4].byte_len]);
    try std.testing.expectEqualStrings("ಕ್‍ಷ", text[words[5].byte_start..][0..words[5].byte_len]);
}

test "Bengali syllables keep marks and select Bengali OpenType script" {
    const allocator = std.testing.allocator;

    const text = "কো ক্ বাংলা";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("কো", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ক্", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("বাং", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("লা", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.bengali, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bng2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0995)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bng2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x09cd)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x09ac));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("কো", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ক্", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("বাংলা", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Odia syllables keep marks and select Odia OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ଓଡ଼ିଆ କ୍‍ଷ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("ଓ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ଡ଼ି", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ଆ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("କ୍‍ଷ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.odia, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ory2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0b13)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ory2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0b4d)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0b13));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ଓଡ଼ିଆ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("କ୍‍ଷ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Gurmukhi syllables keep marks and select Gurmukhi OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ਗੁਰੂ ਗ੍‍ਰੰਥ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ਗੁ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ਰੂ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ਗ੍‍", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ਰੰ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ਥ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.gurmukhi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gur2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0a17)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gur2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0a4d)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0a17));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ਗੁਰੂ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ਗ੍‍ਰੰਥ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Gujarati syllables keep signs and select Gujarati OpenType script" {
    const allocator = std.testing.allocator;

    const text = "કિ કા ક્‍ષ ૧૨૰ ૐ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 11), clusters.len);
    try std.testing.expectEqualStrings("કિ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("કા", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ક્‍ષ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("૰", text[clusters[8].byte_start..][0..clusters[8].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.gujarati, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gjr2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0a95)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gjr2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0abf)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gjr2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0acd)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gjr2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0af0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0a95));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("કિ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("કા", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ક્‍ષ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("૧૨", text[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("ૐ", text[words[4].byte_start..][0..words[4].byte_len]);
}

test "Sinhala syllables keep dependent signs and select Sinhala OpenType script" {
    const allocator = std.testing.allocator;

    const text = "සිංහල ක්";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("සිං", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("හ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ල", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ක්", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.sinhala, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sinh, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0dc3)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0dc3));
}

test "Tamil syllables keep marks and select Tamil OpenType script" {
    const allocator = std.testing.allocator;

    const text = "கி கோ 𑿀";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("கி", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("கோ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("𑿀", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.tamil, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.taml, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0b95)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.taml, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11fc0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0b95));
}

test "Malayalam syllables keep marks and select Malayalam OpenType script" {
    const allocator = std.testing.allocator;

    const text = "കി ക്‍ഷ കോ മലയാളം";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 10), clusters.len);
    try std.testing.expectEqualStrings("കി", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ക്‍ഷ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("കോ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("മ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("ല", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("യാ", text[clusters[8].byte_start..][0..clusters[8].byte_len]);
    try std.testing.expectEqualStrings("ളം", text[clusters[9].byte_start..][0..clusters[9].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.malayalam, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mlm2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0d15)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mlm2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0d4d)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mlm2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0d7a)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0d15));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("കി", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ക്‍ഷ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("കോ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("മലയാളം", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Grantha marks select the gran OpenType script" {
    const allocator = std.testing.allocator;
    const text = "𑌠⃰𑍧";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqualSlices(
        unicode.GraphemeCluster,
        &.{.{ .byte_start = 0, .byte_len = text.len }},
        clusters,
    );

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{.{ .script = .grantha, .byte_start = 0, .byte_len = text.len }},
        runs,
    );
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.gran, unicode.openTypeScriptTag(.grantha));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11320));
    try std.testing.expectEqual(unicode.Script.inherited, unicode.scriptForCodepoint(0x1133b));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x11304));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqualSlices(
        unicode.WordSegment,
        &.{.{ .byte_start = 0, .byte_len = text.len }},
        words,
    );
}

test "Sharada additions keep the shrd script and mark boundaries" {
    const allocator = std.testing.allocator;
    const text = "𑆠𑭠𑭡";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqualSlices(
        unicode.GraphemeCluster,
        &.{.{ .byte_start = 0, .byte_len = text.len }},
        clusters,
    );

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{.{ .script = .sharada, .byte_start = 0, .byte_len = text.len }},
        runs,
    );
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.shrd, unicode.openTypeScriptTag(.sharada));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11b60));
    try std.testing.expect(unicode.isNonspacingMarkCodepoint(0x11b60));
    try std.testing.expect(!unicode.isNonspacingMarkCodepoint(0x11b61));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqualSlices(
        unicode.WordSegment,
        &.{.{ .byte_start = 0, .byte_len = text.len }},
        words,
    );
}

test "modern USE scripts retain assigned signs and reject reserved gaps" {
    const allocator = std.testing.allocator;
    const samples = [_]struct {
        text: []const u8,
        script: unicode.Script,
        tag_value: unicode.OpenTypeScriptTag,
    }{
        .{ .text = "𑊰𑋠", .script = .khudawadi, .tag_value = .sind },
        .{ .text = "𑒁𑒰", .script = .tirhuta, .tag_value = .tirh },
        .{ .text = "𑘀𑘹", .script = .modi, .tag_value = .modi },
        .{ .text = "𑚀𑚭", .script = .takri, .tag_value = .takr },
    };

    for (samples) |sample| {
        const runs = try unicode.itemizeScriptRuns(allocator, sample.text);
        defer allocator.free(runs);
        try std.testing.expectEqual(@as(usize, 1), runs.len);
        try std.testing.expectEqual(sample.script, runs[0].script);
        try std.testing.expectEqual(sample.tag_value, unicode.openTypeScriptTag(sample.script));

        const graphemes = try unicode.itemizeGraphemeClusters(allocator, sample.text);
        defer allocator.free(graphemes);
        try std.testing.expectEqual(@as(usize, 1), graphemes.len);
    }

    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x112eb));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x114c8));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x11645));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x116ba));
}

test "Indic OpenType candidates prefer v3 then v2 then legacy" {
    const devanagari = unicode.openTypeScriptTagCandidates(.devanagari);
    try std.testing.expectEqualSlices(
        unicode.OpenTypeScriptTag,
        &.{ .dev3, .dev2, .deva },
        devanagari.slice(),
    );

    const brahmi = unicode.openTypeScriptTagCandidates(.brahmi);
    try std.testing.expectEqualSlices(unicode.OpenTypeScriptTag, &.{.brah}, brahmi.slice());
}

test "Brahmi syllables keep marks and select Brahmi OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{11013}\u{11038} \u{11013}\u{11002} \u{11013}\u{11046}\u{200d}\u{11022} \u{11066}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("\u{11013}\u{11038}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11002}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11046}\u{200d}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{11022}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{11066}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.brahmi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.brah, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11013)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.brah, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11038)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.brah, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11046)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.brah, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11066)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11013));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("\u{11013}\u{11038}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11002}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11046}\u{200d}\u{11022}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{11066}", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Kaithi syllables keep signs and select Kaithi OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{1108d}\u{110b3} \u{1108d}\u{110b0} \u{1108d}\u{110b9}\u{200d}\u{1109e} \u{110bb} \u{110bd}\u{11083}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 10), clusters.len);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b3}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b0}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b9}\u{200d}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{1109e}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{110bb}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[8].byte_start..][0..clusters[8].byte_len]);
    try std.testing.expectEqualStrings("\u{110bd}\u{11083}", text[clusters[9].byte_start..][0..clusters[9].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.kaithi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kthi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1108d)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kthi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x110b3)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kthi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x110bb)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kthi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x110cd)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x110c3));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1108d));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b3}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b0}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1108d}\u{110b9}\u{200d}\u{1109e}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{11083}", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Chakma syllables keep signs and select Chakma OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{11107}\u{11127} \u{11107}\u{1112c} \u{11107}\u{11133}\u{200d}\u{11108} \u{11136}\u{11141} \u{11144}\u{11145}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 10), clusters.len);
    try std.testing.expectEqualStrings("\u{11107}\u{11127}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11107}\u{1112c}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{11107}\u{11133}\u{200d}\u{11108}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{11136}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{11141}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[8].byte_start..][0..clusters[8].byte_len]);
    try std.testing.expectEqualStrings("\u{11144}\u{11145}", text[clusters[9].byte_start..][0..clusters[9].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.chakma, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cakm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11107)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cakm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11127)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cakm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1112c)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cakm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11141)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cakm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11147)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x11135));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11107));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("\u{11107}\u{11127}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{11107}\u{1112c}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11107}\u{11133}\u{200d}\u{11108}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{11136}", text[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("\u{11144}\u{11145}", text[words[4].byte_start..][0..words[4].byte_len]);
}

test "Myanmar text selects Myanmar v2 script primitives across extensions" {
    const allocator = std.testing.allocator;

    const text = "ကေ့\u{104a} ကွာ \u{a9e0}\u{aa7b} \u{aa60}\u{aa7c}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 10), clusters.len);
    try std.testing.expectEqualStrings("ကေ့", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{104a}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ကွ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ာ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{a9e0}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{aa7b}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("\u{aa60}\u{aa7c}", text[clusters[9].byte_start..][0..clusters[9].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.myanmar, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mym2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1000)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mym2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa9e0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mym2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaa60)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mym2, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x116d0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1000));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ကေ့", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ကွာ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a9e0}\u{aa7b}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{aa60}\u{aa7c}", text[words[3].byte_start..][0..words[3].byte_len]);
}
