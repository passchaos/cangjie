//! Unicode script classification and OpenType mapping tests.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "Latin extension letters stay in Latin script runs" {
    const allocator = std.testing.allocator;

    const text = "Cafẹ Ạꞵ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.latin, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.latn, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1ea0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.latn, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa7b5)));
}

test "Greek and Cyrillic letters select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ῼЖ ҄";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(unicode.Script.greek, runs[0].script);
    try std.testing.expectEqualStrings("ῼ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(unicode.Script.cyrillic, runs[1].script);
    try std.testing.expectEqualStrings("Ж ҄", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.grek, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x03a9)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.grek, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1f88)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cyrl, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0416)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cyrl, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa66e)));
}

test "Glagolitic text keeps combining letters and selects Glagolitic OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{2c00}\u{1e000}\u{2c30} \u{2c5f}\u{1e02a}!";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.glagolitic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.glag, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2c00)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.glag, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1e000)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.glag, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2c5f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1e02b));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x2c00));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1e000));

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("\u{2c00}\u{1e000}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c30}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{2c5f}\u{1e02a}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("!", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{2c00}\u{1e000}\u{2c30}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c5f}\u{1e02a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Old Italic letters and numerals select Old Italic script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10300}\u{10301}\u{10320} \u{1032d}\u{1032e}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.old_italic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ital, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10300)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ital, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10320)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ital, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1032f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x10324));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x10300));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x10320));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10300}\u{10301}\u{10320}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1032d}\u{1032e}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Ugaritic letters select ugar LTR script and split on word divider" {
    const allocator = std.testing.allocator;

    const text = "\u{10380}\u{10381}\u{1039f}\u{10382}\u{1039d}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.ugaritic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ugar, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10380)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ugar, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1039f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1039e));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x10380));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1039f));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .ltr);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.ltr, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10380}\u{10381}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10382}\u{1039d}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Old Persian signs select xpeo script and split on word divider" {
    const allocator = std.testing.allocator;

    const text = "\u{103a0}\u{103a1}\u{103d0}\u{103a2}\u{103d1}\u{103d5}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.old_persian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.xpeo, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x103a0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.xpeo, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x103d0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.xpeo, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x103d5)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x103c4));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x103a0));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x103d1));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{103a0}\u{103a1}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{103a2}\u{103d1}\u{103d5}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Thai and Lao text select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ไทย ລາວ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(unicode.Script.thai, runs[0].script);
    try std.testing.expectEqualStrings("ไทย ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(unicode.Script.lao, runs[1].script);
    try std.testing.expectEqualStrings("ລາວ", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.thai, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0e17)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.thai, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0e48)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lao, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0ea5)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lao, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0eb5)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0e17));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0ea5));
}

test "Armenian text selects Armenian script, words, and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "Հայոց ﬓ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.armenian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.armn, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0540)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.armn, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xfb13)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0540));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("Հայոց", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ﬓ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Hangul conjoining jamo classify as Hangul script runs" {
    const allocator = std.testing.allocator;

    const text = "한 한";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.hangul, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.hang, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1100)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.hang, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xA960)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.hang, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xD7B0)));
}

test "Georgian text selects Georgian script runs and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "ქართული Ქⴐ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.georgian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.geor, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10d0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.geor, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c90)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.geor, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2d10)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x10d0));
}

test "Cherokee text selects Cherokee script runs and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "ᎣᏏᏲ ꭰꮝ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.cherokee, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cher, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x13a3)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cher, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xab70)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x13a3));
}

test "Tifinagh text keeps joiners and selects Tifinagh script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{2d30}\u{2d7f}\u{2d31} \u{2d37}\u{2d6f}\u{2d70}\u{2d59}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{2d30}\u{2d7f}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2d31}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{2d37}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{2d6f}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{2d70}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{2d59}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.tifinagh, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tfng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2d30)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tfng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2d6f)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tfng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2d7f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x2d68));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x2d30));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{2d30}\u{2d7f}\u{2d31}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2d37}\u{2d6f}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{2d59}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Ethiopic text selects Ethiopic script runs and direction" {
    const allocator = std.testing.allocator;

    const text = "ሰላም። ግዕዝ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.ethiopic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ethi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1230)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ethi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1380)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ethi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2d80)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ethi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xab20)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1230));
}

test "Mongolian text keeps free variation selectors and selects Mongolian script" {
    const allocator = std.testing.allocator;

    const text = "ᠮᠣᠩᠭᠣᠯ ᠠ᠋";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("ᠠ᠋", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.mongolian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mong, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x182E)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mong, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x180B)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x182E));
}

test "Tibetan stacks keep marks and select Tibetan OpenType script" {
    const allocator = std.testing.allocator;

    const text = "བོ ཀྱ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("བོ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ཀྱ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.tibetan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tibt, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0f56)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x0f56));
}

test "Phags-Pa selects joining script primitives" {
    const text = "\u{a85e}\u{a85e}\u{a85e} \u{a85e}";
    const runs = try unicode.itemizeScriptRuns(std.testing.allocator, text);
    defer std.testing.allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.phags_pa, runs[0].script);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.phag, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa85e)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa85e));
    try std.testing.expectEqual(unicode.JoiningType.dual, unicode.joiningTypeForCodepoint(0xa85e));
}

test "Balinese syllables keep marks and select Balinese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᬓᭀ ᬓ᭄ ᬩᬮᬶ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᬓᭀ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᬓ᭄", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᬩ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᬮᬶ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.balinese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bali, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1b13)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bali, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1b44)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1b13));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᬓᭀ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᬓ᭄", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᬩᬮᬶ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Javanese syllables keep marks and select Javanese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꦏꦺꦴ ꦏ꧀ ꦲꦤꦕꦫꦏ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("ꦏꦺꦴ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ꦏ꧀", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.javanese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.java, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa98f)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.java, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa9c0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa98f));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ꦏꦺꦴ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ꦏ꧀", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ꦲꦤꦕꦫꦏ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Tai Tham stacks select the lana OpenType script" {
    const allocator = std.testing.allocator;
    const text = "ᨲ᩠ᩅᩫᩡ";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqualSlices(
        unicode.GraphemeCluster,
        &.{
            .{ .byte_start = 0, .byte_len = "ᨲ᩠ᩅᩫ".len },
            .{ .byte_start = "ᨲ᩠ᩅᩫ".len, .byte_len = "ᩡ".len },
        },
        clusters,
    );

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.tai_tham, runs[0].script);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lana, unicode.openTypeScriptTag(runs[0].script));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1a32));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqualStrings(text, text[words[0].byte_start..][0..words[0].byte_len]);
}

test "Newa conjuncts select the newa OpenType script" {
    const allocator = std.testing.allocator;
    const text = "𑐬𑑂𑐎𑑞 𑐐𑑋𑐑";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 6), clusters.len);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{.{ .script = .newa, .byte_start = 0, .byte_len = text.len }},
        runs,
    );
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.newa, unicode.openTypeScriptTag(.newa));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1140e));
    try std.testing.expectEqual(unicode.Script.newa, unicode.scriptForCodepoint(0x1144b));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1145c));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x11462));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqualSlices(
        unicode.WordSegment,
        &.{
            .{ .byte_start = 0, .byte_len = "𑐬𑑂𑐎𑑞".len },
            .{ .byte_start = "𑐬𑑂𑐎𑑞 ".len, .byte_len = "𑐐".len },
            .{ .byte_start = "𑐬𑑂𑐎𑑞 𑐐𑑋".len, .byte_len = "𑐑".len },
        },
        words,
    );
}

test "Saurashtra signs select the saur OpenType script" {
    const allocator = std.testing.allocator;
    const text = "ꢬꢴ꣄";

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
        &.{.{ .script = .saurashtra, .byte_start = 0, .byte_len = text.len }},
        runs,
    );
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.saur, unicode.openTypeScriptTag(.saurashtra));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa8ac));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0xa8c6));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqualSlices(
        unicode.WordSegment,
        &.{.{ .byte_start = 0, .byte_len = text.len }},
        words,
    );
}

test "Marchen stacks select the Marchen OpenType script" {
    const allocator = std.testing.allocator;
    const text = "𑲊𑲒𑲩";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 1), clusters.len);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.marchen, runs[0].script);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.marc, unicode.openTypeScriptTag(runs[0].script));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11c8a));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqualStrings(text, text[words[0].byte_start..][0..words[0].byte_len]);
}

test "Kayah Li syllables keep marks and select Kayah Li OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{a90a}\u{a926}\u{a92b} \u{a900}\u{a901}\u{a92e} \u{a925}\u{a927}\u{a92f}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("\u{a90a}\u{a926}\u{a92b}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a900}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{a901}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{a92e}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{a925}\u{a927}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("\u{a92f}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.kayah_li, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kali, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa90a)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kali, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa926)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.kali, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa92f)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa90a));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0xa92e));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{a90a}\u{a926}\u{a92b}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a900}\u{a901}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a925}\u{a927}", text[words[2].byte_start..][0..words[2].byte_len]);
}
