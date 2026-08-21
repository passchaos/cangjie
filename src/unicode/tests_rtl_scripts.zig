//! Unicode contract tests migrated from the former aggregate root.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "coarse bidi compatibility view derives from exact Unicode 17 classes" {
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint('A'));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0628));
    try std.testing.expectEqual(unicode.BidiClass.number, unicode.bidiClassForCodepoint('1'));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(' '));
    try std.testing.expectEqual(unicode.ExactBidiClass.lri, unicode.exactBidiClassForCodepoint(0x2066));
}

test "Avestan text selects Avestan RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10b00}\u{10b01}\u{10b39}\u{10b02}\u{10b35}\u{10b3f}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.avestan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.avst, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10b00)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.avst, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10b35)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.avst, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10b3f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x10b36));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10b00));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10b3f));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10b00}\u{10b01}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10b02}\u{10b35}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Imperial Aramaic text selects armi RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10840}\u{10841}\u{10857}\u{10842}\u{10858}\u{1085f}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.imperial_aramaic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.armi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10840)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.armi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10857)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.armi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1085f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x10856));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10840));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10858));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .rtl);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.rtl, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10840}\u{10841}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10842}\u{10858}\u{1085f}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Old South Arabian text selects sarb RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10a60}\u{10a61}\u{10a7f}\u{10a62}\u{10a7e}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.old_south_arabian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sarb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10a60)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sarb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10a7f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x10aa0));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10a60));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10a7f));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .rtl);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.rtl, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10a60}\u{10a61}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10a62}\u{10a7e}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Old North Arabian text selects narb RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10a80}\u{10a81} \u{10a9d}\u{10a9f}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.old_north_arabian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.narb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10a80)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.narb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10a9f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x10aa0));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10a80));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10a9f));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .rtl);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.rtl, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10a80}\u{10a81}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10a9d}\u{10a9f}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Meroitic Hieroglyphs select mero RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10980}\u{10981} \u{1099e}\u{1099f}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.meroitic_hieroglyphs, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mero, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10980)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mero, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1099f)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10980));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x1099f));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .rtl);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.rtl, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10980}\u{10981}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1099e}\u{1099f}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Meroitic Cursive selects merc RTL script primitives across assigned gaps" {
    const allocator = std.testing.allocator;

    const text = "\u{109a0}\u{109a1}\u{109bc} \u{109be}\u{109c0}\u{109ff}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.meroitic_cursive, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.merc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x109a0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.merc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x109bc)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.merc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x109ff)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x109b8));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x109d0));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x109a0));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x109c0));

    const bidi_runs = try unicode.itemizeBidiRuns(allocator, text, .rtl);
    defer allocator.free(bidi_runs);

    try std.testing.expectEqual(@as(usize, 1), bidi_runs.len);
    try std.testing.expectEqual(unicode.BidiClass.rtl, bidi_runs[0].direction);
    try std.testing.expectEqual(@as(usize, 0), bidi_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), bidi_runs[0].byte_len);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{109a0}\u{109a1}\u{109bc}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{109be}\u{109c0}\u{109ff}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Arabic presentation forms keep Arabic script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "اﻟ ﻢ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.arabic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.arab, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xfedf)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0xfedf));
    try std.testing.expectEqual(unicode.Script.common, unicode.scriptForCodepoint(0xfeff));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0xfeff));
}

test "Arabic joining forms skip transparent marks and honor join controls" {
    try std.testing.expectEqual(unicode.JoiningType.non_joining, unicode.joiningTypeForCodepoint(0x0621)); // hamza
    try std.testing.expectEqual(unicode.JoiningType.right, unicode.joiningTypeForCodepoint(0x0627)); // alef
    try std.testing.expectEqual(unicode.JoiningType.dual, unicode.joiningTypeForCodepoint(0x0628)); // beh
    try std.testing.expectEqual(unicode.JoiningType.transparent, unicode.joiningTypeForCodepoint(0x064E)); // fatha
    try std.testing.expectEqual(unicode.JoiningType.join_causing, unicode.joiningTypeForCodepoint(0x200D)); // ZWJ
    try std.testing.expectEqual(unicode.JoiningType.non_joining, unicode.joiningTypeForCodepoint(0x200C)); // ZWNJ

    const word = [_]u21{ 0x0628, 0x064E, 0x0628, 0x0627 };
    var word_forms: [word.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&word, &word_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .initial, .none, .medial, .final }, &word_forms);

    const hamza = [_]u21{0x0621};
    var hamza_forms: [hamza.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&hamza, &hamza_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{.none}, &hamza_forms);

    const with_zwnj = [_]u21{ 0x0628, 0x200C, 0x0628 };
    var zwnj_forms: [with_zwnj.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&with_zwnj, &zwnj_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .isolated, .none, .isolated }, &zwnj_forms);

    const with_zwj = [_]u21{ 0x0628, 0x200D, 0x0628 };
    var zwj_forms: [with_zwj.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&with_zwj, &zwj_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .initial, .none, .final }, &zwj_forms);

    const persian_kaf_lam = [_]u21{ 0x0627, 0x0644, 0x06af, 0x0648 };
    var persian_forms: [persian_kaf_lam.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&persian_kaf_lam, &persian_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .isolated, .initial, .medial, .final }, &persian_forms);

    const supplementary_mark = [_]u21{ 0x0628, 0x10efd, 0x0628 };
    var supplementary_forms: [supplementary_mark.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&supplementary_mark, &supplementary_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .initial, .none, .final }, &supplementary_forms);

    const cgj = [_]u21{ 0x0635, 0x0650, 0x034f, 0x0651, 0x0627 };
    var cgj_forms: [cgj.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&cgj, &cgj_forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .initial, .none, .none, .none, .final }, &cgj_forms);
}

test "Mongolian joining data includes punctuation and transparent selectors" {
    try std.testing.expectEqual(unicode.JoiningType.dual, unicode.joiningTypeForCodepoint(0x1807)); // Sibe boundary marker
    try std.testing.expectEqual(unicode.JoiningType.join_causing, unicode.joiningTypeForCodepoint(0x180A)); // NIRUGU
    try std.testing.expectEqual(unicode.JoiningType.transparent, unicode.joiningTypeForCodepoint(0x180B)); // FVS1
    try std.testing.expectEqual(unicode.JoiningType.dual, unicode.joiningTypeForCodepoint(0x1843)); // TODO long vowel sign
    try std.testing.expectEqual(unicode.JoiningType.transparent, unicode.joiningTypeForCodepoint(0x1885)); // BALUDA
    try std.testing.expectEqual(unicode.JoiningType.transparent, unicode.joiningTypeForCodepoint(0x18A9)); // DAGALGA
    try std.testing.expectEqual(unicode.JoiningType.dual, unicode.joiningTypeForCodepoint(0x18AA)); // Manchu Ali Gali LHA

    const text = [_]u21{ 0x180A, 0x1868, 0x180B, 0x180A };
    var forms: [text.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&text, &forms);
    try std.testing.expectEqualSlices(unicode.JoiningForm, &.{ .initial, .medial, .none, .final }, &forms);
}

test "paragraph direction follows the first strong character" {
    try std.testing.expectEqual(unicode.BidiClass.rtl, try unicode.paragraphDirection("123 مرحبا"));
    try std.testing.expectEqual(unicode.BidiClass.ltr, try unicode.paragraphDirection("123 hello مرحبا"));
    try std.testing.expectEqual(unicode.BidiClass.ltr, try unicode.paragraphDirection("123 !"));
    try std.testing.expectError(error.InvalidUtf8, unicode.paragraphDirection("\xff"));
}

test "RTL shaping cluster inheritance covers RTL nonspacing marks" {
    try std.testing.expect(unicode.inheritsPreviousClusterInRtlShaping(0x064e));
    try std.testing.expect(unicode.inheritsPreviousClusterInRtlShaping(0x0898));
    try std.testing.expect(unicode.inheritsPreviousClusterInRtlShaping(0x10efd));
    try std.testing.expect(!unicode.inheritsPreviousClusterInRtlShaping(0x0628));
    try std.testing.expect(unicode.inheritsPreviousClusterInRtlShaping(0x05b0));
    try std.testing.expect(unicode.inheritsPreviousClusterInRtlShaping(0x200d));
    try std.testing.expectEqual(unicode.Script.arabic, unicode.scriptForCodepoint(0x10efd));
}

test "Hebrew presentation forms keep Hebrew script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "אשׁ ב";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.hebrew, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.hebr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xfb2a)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0xfb2a));
}

test "Phoenician text selects Phoenician RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10900}\u{10901}\u{1091f}\u{10902}\u{10916}\u{1091a}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.phoenician, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.phnx, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10900)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.phnx, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x10916)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.phnx, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1091f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1091c));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10900));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x10916));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10900}\u{10901}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10902}\u{10916}\u{1091a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Samaritan text keeps vowel marks and selects Samaritan RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "\u{0800}\u{0816}\u{081b}\u{0801}\u{0830} \u{0802}\u{0829}\u{082a}\u{0824}\u{082d}\u{0803}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{0800}\u{0816}\u{081b}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0801}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0830}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{0802}\u{0829}\u{082a}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{0824}\u{082d}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{0803}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.samaritan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.samr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0800)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.samr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0816)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.samr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x083e)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x083f));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0800));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0830));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{0800}\u{0816}\u{081b}\u{0801}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0802}\u{0829}\u{082a}\u{0824}\u{082d}\u{0803}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Syriac text selects Syriac script and RTL shaping direction" {
    const allocator = std.testing.allocator;

    const text = "ܫܠܡ ݍ";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.syriac, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.syrc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x072b)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.dflt, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x086d)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x072b));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0x086d));
}

test "Syriac words keep pointing marks but exclude native punctuation" {
    const allocator = std.testing.allocator;

    const text = "\u{0712}\u{0730}\u{0713}\u{0701} \u{074d}\u{074e} \u{0860}\u{0734}\u{086a}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("\u{0712}\u{0730}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0713}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0701}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{0860}\u{0734}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.syriac, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.syrc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0730)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.syrc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x074d)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.syrc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x086a)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0730));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{0712}\u{0730}\u{0713}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{074d}\u{074e}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0860}\u{0734}\u{086a}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Mandaic text keeps marks and selects Mandaic RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "\u{0840}\u{0859}\u{0841} \u{084C}\u{085A}\u{085B}\u{0840} \u{085E}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{0840}\u{0859}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0841}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{084C}\u{085A}\u{085B}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{0840}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{085E}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.mandaic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mand, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0840)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mand, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x0859)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mand, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x085e)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x085c));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0840));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x0859));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{0840}\u{0859}\u{0841}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{084C}\u{085A}\u{085B}\u{0840}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "NKo text keeps tone marks with words and selects RTL shaping primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{07d2}\u{07eb}\u{07ec}\u{07f4}\u{07e3} \u{07c1}\u{07fd}\u{07c2} \u{07f8}\u{07fe}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("\u{07d2}\u{07eb}\u{07ec}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{07f4}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{07e3}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{07c1}\u{07fd}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{07c2}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.nko, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.nko, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x07d2)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.nko, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x07eb)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.nko, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x07fd)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x07fb));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x07fc));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x07d2));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x07eb));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x07c1));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{07d2}\u{07eb}\u{07ec}\u{07f4}\u{07e3}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{07c1}\u{07fd}\u{07c2}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Adlam text keeps marks and selects Adlam RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "\u{1e922}\u{1e944}\u{1e94a}\u{1e925} \u{1e950}\u{1e951} \u{1e95e}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{1e922}\u{1e944}\u{1e94a}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1e925}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{1e950}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{1e951}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{1e95e}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.adlam, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.adlm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1e922)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.adlm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1e944)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.adlm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1e950)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.adlm, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1e95e)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x1e922));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x1e944));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x1e950));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{1e922}\u{1e944}\u{1e94a}\u{1e925}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1e950}\u{1e951}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Thaana text keeps fili marks and selects Thaana RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "ދިވެހި ބަސް";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ދި", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ވެ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ހި", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ބަ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ސް", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.thaana, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.thaa, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x078b)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.thaa, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x07a8)));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x078b));
    try std.testing.expectEqual(unicode.BidiClass.rtl, unicode.bidiClassForCodepoint(0x07a8));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ދިވެހި", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ބަސް", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "bidi mirroring covers mathematical bracket pairs" {
    try std.testing.expectEqual(@as(u21, 0x27e9), unicode.mirroredCodepoint(0x27e8));
    try std.testing.expectEqual(@as(u21, 0x27e8), unicode.mirroredCodepoint(0x27e9));
    try std.testing.expectEqual(@as(u21, 0x2309), unicode.mirroredCodepoint(0x2308));
    try std.testing.expectEqual(@as(u21, 0x298f), unicode.mirroredCodepoint(0x298e));
    try std.testing.expectEqual(@as(u21, 0x298d), unicode.mirroredCodepoint(0x2990));
}
