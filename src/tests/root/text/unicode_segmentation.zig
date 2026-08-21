//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const Script = support.Script;
const BidiClass = support.BidiClass;
const WordBoundarySegment = support.WordBoundarySegment;
const wordSegments = support.wordSegments;
const word_unicode_version = support.word_unicode_version;
const SentenceSegment = support.SentenceSegment;
const sentenceSegments = support.sentenceSegments;
const sentence_unicode_version = support.sentence_unicode_version;
const LineBreakKind = support.LineBreakKind;
const OpenTypeLanguageTag = support.OpenTypeLanguageTag;
const OpenTypeScriptTag = support.OpenTypeScriptTag;
const buildBidiMap = support.buildBidiMap;
const inferOpenTypeLanguageTag = support.inferOpenTypeLanguageTag;
const lineBreaks = support.lineBreaks;
const openTypeLanguageTagForLocale = support.openTypeLanguageTagForLocale;
const itemizeBidiRuns = support.itemizeBidiRuns;
const itemizeGraphemeClusters = support.itemizeGraphemeClusters;
const itemizeLineBreaks = support.itemizeLineBreaks;
const itemizeScriptRuns = support.itemizeScriptRuns;
const itemizeWordSegments = support.itemizeWordSegments;
const openTypeTag = support.openTypeTag;
const openTypeScriptTag = support.openTypeScriptTag;
const scriptForCodepoint = support.scriptForCodepoint;
const mirroredCodepoint = support.mirroredCodepoint;
const bidiClassForCodepoint = support.bidiClassForCodepoint;
const testing = support.testing;

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
    const han_japanese = @import("../../../unicode.zig").inferOpenTypeProperties("一あ");
    try std.testing.expectEqual(Script.han, han_japanese.script);
    try std.testing.expectEqual(OpenTypeLanguageTag.jan, han_japanese.language);
    try std.testing.expect(!han_japanese.all_ascii);
    const ascii = @import("../../../unicode.zig").inferOpenTypeProperties("ASCII 123");
    try std.testing.expectEqual(Script.latin, ascii.script);
    try std.testing.expectEqual(OpenTypeLanguageTag.dflt, ascii.language);
    try std.testing.expect(ascii.all_ascii);
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .jan), openTypeLanguageTagForLocale("ja-JP"));
    try std.testing.expectEqual(@as(?OpenTypeLanguageTag, .far), openTypeLanguageTagForLocale("fa-IR"));
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
    try std.testing.expectEqual(@as(usize, 8), runs[1].byte_len);
    try std.testing.expectEqual(Script.arabic, runs[2].script);
    try std.testing.expectEqual(@as(usize, 13), runs[2].byte_start);

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
    try std.testing.expectEqual(@as(usize, 4), runs[0].byte_len);
    try std.testing.expectEqual(BidiClass.rtl, runs[1].direction);
    try std.testing.expectEqual(@as(usize, 4), runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 6), runs[1].byte_len);
    try std.testing.expectEqual(BidiClass.ltr, runs[2].direction);
    try std.testing.expectEqual(@as(usize, 10), runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 4), runs[2].byte_len);
    try std.testing.expectError(error.InvalidUtf8, itemizeBidiRuns(allocator, "abc \xff xyz", .ltr));

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
    try std.testing.expectEqual(@as(usize, 0), ltr_map.logical_to_visual[0]);
    try std.testing.expectEqual(@as(usize, 1), ltr_map.logical_to_visual[1]);
    try std.testing.expectEqual(@as(usize, 3), ltr_map.logical_to_visual[2]);
    try std.testing.expectEqual(@as(usize, 2), ltr_map.logical_to_visual[3]);
    try std.testing.expectEqual(@as(usize, 4), ltr_map.logical_to_visual[4]);
    try std.testing.expectEqual(@as(usize, 5), ltr_map.logical_to_visual[5]);
    try std.testing.expectEqual(@as(usize, 3), ltr_map.items[2].logical_index);
    try std.testing.expectEqual(@as(u21, 0x05d2), ltr_map.items[2].visual_codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d1), ltr_map.items[3].visual_codepoint);
    try std.testing.expectEqual(BidiClass.rtl, ltr_map.items[2].direction);

    var variation_map = try buildBidiMap(allocator, "א\u{fe0f}ב", .rtl);
    defer variation_map.deinit();
    try std.testing.expectEqual(@as(usize, 3), variation_map.items.len);
    try std.testing.expectEqual(@as(u21, 0x05d1), variation_map.items[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), variation_map.items[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0xfe0f), variation_map.items[2].codepoint);
    try std.testing.expectEqual(@as(usize, 1), variation_map.logical_to_visual[0]);
    try std.testing.expectEqual(@as(usize, 2), variation_map.logical_to_visual[1]);
    try std.testing.expectEqual(@as(usize, 0), variation_map.logical_to_visual[2]);

    var rtl_map = try buildBidiMap(allocator, "abבגcd", .rtl);
    defer rtl_map.deinit();

    try std.testing.expectEqual(@as(usize, 4), rtl_map.items[0].logical_index);
    try std.testing.expectEqual(@as(usize, 5), rtl_map.items[1].logical_index);
    try std.testing.expectEqual(@as(usize, 3), rtl_map.items[2].logical_index);
    try std.testing.expectEqual(@as(usize, 2), rtl_map.items[3].logical_index);
    try std.testing.expectEqual(@as(usize, 0), rtl_map.items[4].logical_index);
    try std.testing.expectEqual(@as(usize, 1), rtl_map.items[5].logical_index);
    try std.testing.expectEqual(@as(usize, 4), rtl_map.logical_to_visual[0]);
    try std.testing.expectEqual(@as(usize, 3), rtl_map.logical_to_visual[2]);
    try std.testing.expectEqual(@as(usize, 0), rtl_map.logical_to_visual[4]);

    var mirrored = try buildBidiMap(allocator, "(אב)", .rtl);
    defer mirrored.deinit();
    try std.testing.expectEqual(@as(u21, '('), mirrored.items[0].visual_codepoint);
    try std.testing.expectEqual(@as(u21, ')'), mirrored.items[3].visual_codepoint);

    var number_map = try buildBidiMap(allocator, "א12ב", .rtl);
    defer number_map.deinit();
    try std.testing.expectEqual(@as(usize, 3), number_map.items[0].logical_index);
    try std.testing.expectEqual(@as(usize, 1), number_map.items[1].logical_index);
    try std.testing.expectEqual(@as(usize, 2), number_map.items[2].logical_index);
    try std.testing.expectEqual(@as(usize, 0), number_map.items[3].logical_index);
    // The compatibility direction is derived from the final embedding level;
    // numeric identity remains available through the exact input class API.
    try std.testing.expectEqual(BidiClass.ltr, number_map.items[1].direction);

    var neutral_number_map = try buildBidiMap(allocator, "א 12ב", .rtl);
    defer neutral_number_map.deinit();
    try std.testing.expectEqual(@as(usize, 4), neutral_number_map.items[0].logical_index);
    try std.testing.expectEqual(@as(usize, 2), neutral_number_map.items[1].logical_index);
    try std.testing.expectEqual(@as(usize, 3), neutral_number_map.items[2].logical_index);
    try std.testing.expectEqual(@as(usize, 1), neutral_number_map.items[3].logical_index);
    try std.testing.expectEqual(@as(usize, 0), neutral_number_map.items[4].logical_index);

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

test "streams Unicode word boundaries separately from selectable words" {
    const text = "can't 3.14 一丁 ក";
    var iterator = try wordSegments(text);
    const expected = [_][]const u8{
        "can't",
        " ",
        "3.14",
        " ",
        "一",
        "丁",
        " ",
        "ក",
    };
    const expected_word = [_]bool{
        true,
        false,
        true,
        false,
        true,
        true,
        false,
        true,
    };
    for (expected, expected_word) |segment_text, is_word| {
        const segment = iterator.next() orelse return error.MissingWordSegment;
        try std.testing.expectEqualStrings(
            segment_text,
            text[segment.byte_start..][0..segment.byte_len],
        );
        try std.testing.expectEqual(is_word, segment.is_word);
    }
    try std.testing.expectEqual(@as(?WordBoundarySegment, null), iterator.next());
    try std.testing.expectEqual([3]u8{ 17, 0, 0 }, word_unicode_version);
    try std.testing.expectError(error.InvalidUtf8, wordSegments("word\xff"));
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

test "streams Unicode sentence boundaries with lowercase abbreviation context" {
    const text = "etc. there is more. Next.";
    var iterator = try sentenceSegments(text);
    const first = iterator.next() orelse return error.MissingSentenceSegment;
    try std.testing.expectEqualStrings(
        "etc. there is more. ",
        text[first.byte_start..][0..first.byte_len],
    );
    const second = iterator.next() orelse return error.MissingSentenceSegment;
    try std.testing.expectEqualStrings(
        "Next.",
        text[second.byte_start..][0..second.byte_len],
    );
    try std.testing.expectEqual(@as(?SentenceSegment, null), iterator.next());
    try std.testing.expectEqual([3]u8{ 17, 0, 0 }, sentence_unicode_version);
    try std.testing.expectError(error.InvalidUtf8, sentenceSegments("One.\xffTwo"));
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
