//! Unicode script classification and OpenType mapping tests.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "Unicode 17 Script Extensions expose explicit and fallback memberships" {
    // Explicit Script_Extensions rows replace the primary Script value.
    try std.testing.expect(unicode.scriptExtensionsContain(0x00b7, .latin));
    try std.testing.expect(unicode.scriptExtensionsContain(0x00b7, .greek));
    try std.testing.expect(unicode.scriptExtensionsContain(0x00b7, .shavian));
    try std.testing.expect(!unicode.scriptExtensionsContain(0x00b7, .common));

    try std.testing.expect(unicode.scriptExtensionsContain(0x0964, .devanagari));
    try std.testing.expect(unicode.scriptExtensionsContain(0x0964, .bengali));
    try std.testing.expect(unicode.scriptExtensionsContain(0x0964, .tamil));
    try std.testing.expect(!unicode.scriptExtensionsContain(0x0964, .common));

    try std.testing.expect(unicode.scriptExtensionsContain(0x30fc, .hiragana));
    try std.testing.expect(unicode.scriptExtensionsContain(0x30fc, .katakana));
    try std.testing.expect(!unicode.scriptExtensionsContain(0x30fc, .common));

    // Scalars without an explicit row inherit exactly their Script value.
    try std.testing.expect(unicode.scriptExtensionsContain('A', .latin));
    try std.testing.expect(!unicode.scriptExtensionsContain('A', .greek));
    try std.testing.expect(unicode.scriptExtensionsContain(0x0370, .greek));
    try std.testing.expect(!unicode.scriptExtensionsContain(0x0370, .latin));

    const explicit = unicode.scriptExtensionsForCodepoint(0x30fc);
    try std.testing.expectEqual(@as(usize, 2), explicit.len());
    try std.testing.expectEqual(unicode.Script.hiragana, explicit.at(0).?);
    try std.testing.expectEqual(unicode.Script.katakana, explicit.at(1).?);
    try std.testing.expect(explicit.at(2) == null);
    const fallback = unicode.scriptExtensionsForCodepoint('A');
    try std.testing.expectEqual(@as(usize, 1), fallback.len());
    try std.testing.expectEqual(unicode.Script.latin, fallback.at(0).?);
}

test "Script Extensions keep shared characters with compatible runs" {
    const allocator = std.testing.allocator;

    const arabic = "A\u{060c}\u{0628}";
    const arabic_runs = try unicode.itemizeScriptRuns(allocator, arabic);
    defer allocator.free(arabic_runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{
            .{ .script = .latin, .byte_start = 0, .byte_len = 1 },
            .{ .script = .arabic, .byte_start = 1, .byte_len = arabic.len - 1 },
        },
        arabic_runs,
    );

    const kana = "A\u{30fc}\u{30a2}";
    const kana_runs = try unicode.itemizeScriptRuns(allocator, kana);
    defer allocator.free(kana_runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{
            .{ .script = .latin, .byte_start = 0, .byte_len = 1 },
            .{ .script = .katakana, .byte_start = 1, .byte_len = kana.len - 1 },
        },
        kana_runs,
    );

    const incompatible_trailing = "A\u{060c}";
    const incompatible_runs = try unicode.itemizeScriptRuns(allocator, incompatible_trailing);
    defer allocator.free(incompatible_runs);
    try std.testing.expectEqualSlices(
        unicode.ScriptRun,
        &.{
            .{ .script = .latin, .byte_start = 0, .byte_len = 1 },
            .{ .script = .common, .byte_start = 1, .byte_len = incompatible_trailing.len - 1 },
        },
        incompatible_runs,
    );
}

test "streaming script runs match the collecting compatibility API" {
    const allocator = std.testing.allocator;
    const samples = [_][]const u8{
        "",
        "ASCII only",
        "A\u{060c}\u{0628}",
        "\u{30fc}\u{30a2} A\u{0301}\u{4e00}",
        "\u{0915}\u{0964}\u{09ac}",
    };
    for (samples) |sample| {
        const collected = try unicode.itemizeScriptRuns(allocator, sample);
        defer allocator.free(collected);

        var streamed = std.ArrayList(unicode.ScriptRun).empty;
        defer streamed.deinit(allocator);
        var iterator = unicode.scriptRuns(sample);
        while (try iterator.next()) |run| {
            try streamed.append(allocator, run);
        }
        try std.testing.expectEqualSlices(
            unicode.ScriptRun,
            collected,
            streamed.items,
        );
    }
}

test "streaming script runs report malformed UTF-8" {
    var leading = unicode.scriptRuns("\xff");
    try std.testing.expectError(error.InvalidUtf8, leading.next());

    var after_run = unicode.scriptRuns("A\u{0628}\xff");
    try std.testing.expectEqual(
        unicode.ScriptRun{ .script = .latin, .byte_start = 0, .byte_len = 1 },
        (try after_run.next()).?,
    );
    try std.testing.expectError(error.InvalidUtf8, after_run.next());
}

test "large Unicode 17 scripts select distinct OpenType primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        reserved: u21,
        reserved_script: unicode.Script = .unknown,
    };
    const cases = [_]Case{
        .{ .scalar = 0x17000, .script = .tangut, .tag = .tang, .reserved = 0x18dff },
        .{ .scalar = 0x13440, .script = .egyptian_hieroglyphs, .tag = .egyp, .reserved = 0x13456 },
        .{ .scalar = 0x12470, .script = .cuneiform, .tag = .xsux, .reserved = 0x12475 },
        .{ .scalar = 0x1da75, .script = .signwriting, .tag = .sgnw, .reserved = 0x1da90 },
        .{ .scalar = 0x16800, .script = .bamum, .tag = .bamu, .reserved = 0x16a39 },
        .{ .scalar = 0x14400, .script = .anatolian_hieroglyphs, .tag = .hluw, .reserved = 0x14647 },
        .{ .scalar = 0x16fe4, .script = .khitan_small_script, .tag = .kits, .reserved = 0x18cd6 },
        .{ .scalar = 0x10760, .script = .linear_a, .tag = .lina, .reserved = 0x10737 },
        .{ .scalar = 0x2800, .script = .braille, .tag = .brai, .reserved = 0x2900, .reserved_script = .common },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(case.scalar));
        try std.testing.expectEqual(case.reserved_script, unicode.scriptForCodepoint(case.reserved));
    }
}

test "next Unicode 17 script tranche selects OpenType and bidi primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        bidi: unicode.BidiClass = .ltr,
    };
    const cases = [_]Case{
        .{ .scalar = 0x1e800, .script = .mende_kikakui, .tag = .mend },
        .{ .scalar = 0x10000, .script = .linear_b, .tag = .linb },
        .{ .scalar = 0x16f00, .script = .miao, .tag = .plrd },
        .{ .scalar = 0x16b00, .script = .pahawh_hmong, .tag = .hmng },
        .{ .scalar = 0x10c80, .script = .old_hungarian, .tag = .hung, .bidi = .rtl },
        .{ .scalar = 0x12f90, .script = .cypro_minoan, .tag = .cpmn },
        .{ .scalar = 0x11c00, .script = .bhaiksuki, .tag = .bhks },
        .{ .scalar = 0x11580, .script = .siddham, .tag = .sidd },
        .{ .scalar = 0x16e40, .script = .medefaidrin, .tag = .medf },
        .{ .scalar = 0x16a70, .script = .tangsa, .tag = .tnsa },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
    }
}

test "third Unicode 17 script tranche selects OpenType and bidi primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        bidi: unicode.BidiClass = .ltr,
    };
    const cases = [_]Case{
        .{ .scalar = 0x11f00, .script = .kawi, .tag = .kawi },
        .{ .scalar = 0x118a0, .script = .warang_citi, .tag = .wara },
        .{ .scalar = 0x1980, .script = .new_tai_lue, .tag = .talu },
        .{ .scalar = 0x11a50, .script = .soyombo, .tag = .soyo },
        .{ .scalar = 0x10400, .script = .deseret, .tag = .dsrt },
        .{ .scalar = 0x11380, .script = .tulu_tigalari, .tag = .tutg },
        .{ .scalar = 0x3105, .script = .bopomofo, .tag = .bopo },
        .{ .scalar = 0x11d00, .script = .masaram_gondi, .tag = .gonm },
        .{ .scalar = 0x10c00, .script = .old_turkic, .tag = .orkh, .bidi = .rtl },
        .{ .scalar = 0x11900, .script = .dives_akuru, .tag = .diak },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
    }
}

test "fourth Unicode 17 script tranche selects OpenType and bidi primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        bidi: unicode.BidiClass = .ltr,
    };
    const cases = [_]Case{
        .{ .scalar = 0x104b0, .script = .osage, .tag = .osge },
        .{ .scalar = 0xaa80, .script = .tai_viet, .tag = .tavt },
        .{ .scalar = 0x11a00, .script = .zanabazar_square, .tag = .zanb },
        .{ .scalar = 0x1e100, .script = .nyiakeng_puachue_hmong, .tag = .hmnp },
        .{ .scalar = 0x10570, .script = .vithkuqi, .tag = .vith },
        .{ .scalar = 0x10d50, .script = .garay, .tag = .gara, .bidi = .rtl },
        .{ .scalar = 0x10a10, .script = .kharoshthi, .tag = .khar, .bidi = .rtl },
        .{ .scalar = 0x11700, .script = .ahom, .tag = .ahom },
        .{ .scalar = 0x11200, .script = .khojki, .tag = .khoj },
        .{ .scalar = 0x119a0, .script = .nandinagari, .tag = .nand },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
    }
}

test "fifth Unicode 17 script tranche selects OpenType and bidi primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        bidi: unicode.BidiClass = .ltr,
    };
    const cases = [_]Case{
        .{ .scalar = 0x104b0, .script = .osage, .tag = .osge },
        .{ .scalar = 0xaa80, .script = .tai_viet, .tag = .tavt },
        .{ .scalar = 0x11a00, .script = .zanabazar_square, .tag = .zanb },
        .{ .scalar = 0x1e100, .script = .nyiakeng_puachue_hmong, .tag = .hmnp },
        .{ .scalar = 0x10570, .script = .vithkuqi, .tag = .vith },
        .{ .scalar = 0x10d50, .script = .garay, .tag = .gara, .bidi = .rtl },
        .{ .scalar = 0x10a10, .script = .kharoshthi, .tag = .khar, .bidi = .rtl },
        .{ .scalar = 0x11700, .script = .ahom, .tag = .ahom },
        .{ .scalar = 0x11200, .script = .khojki, .tag = .khoj },
        .{ .scalar = 0x119a0, .script = .nandinagari, .tag = .nand },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
    }
}

test "sixth Unicode 17 script tranche selects OpenType primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
    };
    const cases = [_]Case{
        .{ .scalar = 0x11d60, .script = .gunjala_gondi, .tag = .gong },
        .{ .scalar = 0x11800, .script = .dogra, .tag = .dogr },
        .{ .scalar = 0x1e2c0, .script = .wancho, .tag = .wcho },
        .{ .scalar = 0x16100, .script = .gurung_khema, .tag = .gukh },
        .{ .scalar = 0x16d40, .script = .kirat_rai, .tag = .krai },
        .{ .scalar = 0x11ac0, .script = .pau_cin_hau, .tag = .pauc },
        .{ .scalar = 0x10800, .script = .cypriot, .tag = .cprt },
        .{ .scalar = 0x1e6c0, .script = .tai_yo, .tag = .tayo },
        .{ .scalar = 0x11db0, .script = .tolong_siki, .tag = .tols },
        .{ .scalar = 0x10530, .script = .caucasian_albanian, .tag = .aghb },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
    }
}

test "seventh Unicode 17 script tranche selects OpenType and bidi primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        text: []const u8,
        bidi: unicode.BidiClass = .ltr,
        reserved: ?u21 = null,
    };
    const cases = [_]Case{
        .{ .scalar = 0x105c0, .script = .todhri, .tag = .todr, .text = "\u{105c0}\u{105c1}", .reserved = 0x105f4 },
        .{ .scalar = 0x10ac0, .script = .manichaean, .tag = .mani, .text = "\u{10ac0}\u{10ac1}", .bidi = .rtl, .reserved = 0x10ae7 },
        .{ .scalar = 0x16ea0, .script = .beria_erfe, .tag = .berf, .text = "\u{16ea0}\u{16ea1}", .reserved = 0x16eb9 },
        .{ .scalar = 0x10d00, .script = .hanifi_rohingya, .tag = .rohg, .text = "\u{10d00}\u{10d01}", .bidi = .rtl, .reserved = 0x10d28 },
        .{ .scalar = 0x102a0, .script = .carian, .tag = .cari, .text = "\u{102a0}\u{102a1}" },
        .{ .scalar = 0x1c50, .script = .ol_chiki, .tag = .olck, .text = "\u{1c5a}\u{1c5b}" },
        .{ .scalar = 0x10450, .script = .shavian, .tag = .shaw, .text = "\u{10450}\u{10451}" },
        .{ .scalar = 0x10e80, .script = .yezidi, .tag = .yezi, .text = "\u{10e80}\u{10e81}", .bidi = .rtl, .reserved = 0x10eaa },
        .{ .scalar = 0xa800, .script = .syloti_nagri, .tag = .sylo, .text = "\u{a800}\u{a801}", .reserved = 0xa82d },
        .{ .scalar = 0x1e5d0, .script = .ol_onal, .tag = .onao, .text = "\u{1e5d0}\u{1e5d1}", .reserved = 0x1e5fb },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
        try std.testing.expectEqual(case.bidi, unicode.openTypeScriptHorizontalDirection(case.tag).?);
        if (case.reserved) |scalar| {
            try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(scalar));
        }

        // These less-common scripts deliberately use the editor's generic
        // letter/number grouping until script-specific word tailoring exists.
        const words = try unicode.itemizeWordSegments(std.testing.allocator, case.text);
        defer std.testing.allocator.free(words);
        try std.testing.expectEqual(@as(usize, 1), words.len);
        try std.testing.expectEqual(@as(usize, 0), words[0].byte_start);
        try std.testing.expectEqual(case.text.len, words[0].byte_len);
    }
}

test "final Unicode 17 script tranche selects OpenType bidi and word primitives" {
    const Case = struct {
        scalar: u21,
        script: unicode.Script,
        tag: unicode.OpenTypeScriptTag,
        text: []const u8,
        bidi: unicode.BidiClass = .ltr,
    };
    const cases = [_]Case{
        .{ .scalar = 0x0370, .script = .greek, .tag = .grek, .text = "\u{0370}\u{0371}" },
        .{ .scalar = 0x0900, .script = .devanagari, .tag = .dev2, .text = "\u{0915}\u{0916}" },
        .{ .scalar = 0x11bc0, .script = .sunuwar, .tag = .sunu, .text = "\u{11bc0}\u{11bc1}" },
        .{ .scalar = 0x16a40, .script = .mro, .tag = .mroo, .text = "\u{16a40}\u{16a41}" },
        .{ .scalar = 0x10350, .script = .old_permic, .tag = .perm, .text = "\u{10350}\u{10351}" },
        .{ .scalar = 0x1e4d0, .script = .nag_mundari, .tag = .nagm, .text = "\u{1e4d0}\u{1e4d1}" },
        .{ .scalar = 0x10f30, .script = .sogdian, .tag = .sogd, .text = "\u{10f30}\u{10f31}", .bidi = .rtl },
        .{ .scalar = 0x10500, .script = .elbasan, .tag = .elba, .text = "\u{10500}\u{10501}" },
        .{ .scalar = 0x10880, .script = .nabataean, .tag = .nbat, .text = "\u{10880}\u{10881}", .bidi = .rtl },
        .{ .scalar = 0x10f00, .script = .old_sogdian, .tag = .sogo, .text = "\u{10f00}\u{10f01}", .bidi = .rtl },
        .{ .scalar = 0x10480, .script = .osmanya, .tag = .osma, .text = "\u{10480}\u{10481}" },
        .{ .scalar = 0x11150, .script = .mahajani, .tag = .mahj, .text = "\u{11150}\u{11151}" },
        .{ .scalar = 0x11280, .script = .multani, .tag = .mult, .text = "\u{11280}\u{11282}" },
        .{ .scalar = 0x16ad0, .script = .bassa_vah, .tag = .bass, .text = "\u{16ad0}\u{16ad1}" },
        .{ .scalar = 0x110d0, .script = .sora_sompeng, .tag = .sora, .text = "\u{110d0}\u{110d1}" },
        .{ .scalar = 0x1950, .script = .tai_le, .tag = .tale, .text = "\u{1950}\u{1951}" },
        .{ .scalar = 0x10860, .script = .palmyrene, .tag = .palm, .text = "\u{10860}\u{10861}", .bidi = .rtl },
        .{ .scalar = 0x1e290, .script = .toto, .tag = .toto, .text = "\u{1e290}\u{1e291}" },
        .{ .scalar = 0x10b40, .script = .inscriptional_parthian, .tag = .prti, .text = "\u{10b40}\u{10b41}", .bidi = .rtl },
        .{ .scalar = 0x10280, .script = .lycian, .tag = .lyci, .text = "\u{10280}\u{10281}" },
        .{ .scalar = 0x10b80, .script = .psalter_pahlavi, .tag = .phlp, .text = "\u{10b80}\u{10b81}", .bidi = .rtl },
        .{ .scalar = 0x10fb0, .script = .chorasmian, .tag = .chrs, .text = "\u{10fb0}\u{10fb1}", .bidi = .rtl },
        .{ .scalar = 0x10330, .script = .gothic, .tag = .goth, .text = "\u{10330}\u{10331}" },
        .{ .scalar = 0x10b60, .script = .inscriptional_pahlavi, .tag = .phli, .text = "\u{10b60}\u{10b61}", .bidi = .rtl },
        .{ .scalar = 0x10920, .script = .lydian, .tag = .lydi, .text = "\u{10920}\u{10921}", .bidi = .rtl },
        .{ .scalar = 0x108e0, .script = .hatran, .tag = .hatr, .text = "\u{108e0}\u{108e1}", .bidi = .rtl },
        .{ .scalar = 0x10f70, .script = .old_uyghur, .tag = .ougr, .text = "\u{10f70}\u{10f71}", .bidi = .rtl },
        .{ .scalar = 0x10940, .script = .sidetic, .tag = .sidt, .text = "\u{10940}\u{10941}" },
        .{ .scalar = 0x11ee0, .script = .makasar, .tag = .maka, .text = "\u{11ee0}\u{11ee1}" },
        .{ .scalar = 0x10fe0, .script = .elymaic, .tag = .elym, .text = "\u{10fe0}\u{10fe1}", .bidi = .rtl },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.script, unicode.scriptForCodepoint(case.scalar));
        try std.testing.expectEqual(case.tag, unicode.openTypeScriptTag(case.script));
        try std.testing.expectEqual(case.bidi, unicode.bidiClassForCodepoint(case.scalar));
        try std.testing.expectEqual(case.bidi, unicode.openTypeScriptHorizontalDirection(case.tag).?);

        const words = try unicode.itemizeWordSegments(std.testing.allocator, case.text);
        defer std.testing.allocator.free(words);
        try std.testing.expectEqual(@as(usize, 1), words.len);
        try std.testing.expectEqual(case.text.len, words[0].byte_len);
    }

    // Former whole-block approximations now preserve Common/Inherited scalars
    // rather than assigning them to the surrounding shaping script.
    try std.testing.expectEqual(unicode.Script.common, unicode.scriptForCodepoint(0x0374));
    try std.testing.expectEqual(unicode.Script.inherited, unicode.scriptForCodepoint(0x0951));
    try std.testing.expectEqual(unicode.Script.devanagari, unicode.scriptForCodepoint(0xa8e0));
    try std.testing.expectEqual(unicode.Script.devanagari, unicode.scriptForCodepoint(0x11b09));
}

test "Tagalog text selects Baybayin script primitives" {
    const allocator = std.testing.allocator;
    const text = "\u{1703}\u{1712}\u{1714} \u{171f}\u{1715}";

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings(
        "\u{1703}\u{1712}\u{1714}",
        text[clusters[0].byte_start..][0..clusters[0].byte_len],
    );
    try std.testing.expectEqualStrings(
        "\u{171f}\u{1715}",
        text[clusters[2].byte_start..][0..clusters[2].byte_len],
    );

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.tagalog, runs[0].script);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tglg, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1703)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.tglg, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1715)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1716));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1703));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings(
        "\u{1703}\u{1712}\u{1714}",
        text[words[0].byte_start..][0..words[0].byte_len],
    );
    try std.testing.expectEqualStrings(
        "\u{171f}\u{1715}",
        text[words[1].byte_start..][0..words[1].byte_len],
    );
}

test "Hanunoo Buhid and Tagbanwa select distinct Philippine script primitives" {
    const allocator = std.testing.allocator;

    const Cases = struct {
        text: []const u8,
        expected_script: unicode.Script,
        expected_tag: unicode.OpenTypeScriptTag,
        reserved: u21,
    };
    const cases = [_]Cases{
        .{ .text = "\u{1723}\u{1732}\u{1734}", .expected_script = .hanunoo, .expected_tag = .hano, .reserved = 0x1737 },
        .{ .text = "\u{1743}\u{1752}", .expected_script = .buhid, .expected_tag = .buhd, .reserved = 0x1754 },
        .{ .text = "\u{1763}\u{1772}", .expected_script = .tagbanwa, .expected_tag = .tagb, .reserved = 0x176d },
    };

    for (cases) |case| {
        const clusters = try unicode.itemizeGraphemeClusters(allocator, case.text);
        defer allocator.free(clusters);
        try std.testing.expectEqual(@as(usize, 1), clusters.len);
        try std.testing.expectEqual(@as(usize, 0), clusters[0].byte_start);
        try std.testing.expectEqual(case.text.len, clusters[0].byte_len);

        const runs = try unicode.itemizeScriptRuns(allocator, case.text);
        defer allocator.free(runs);
        try std.testing.expectEqual(@as(usize, 1), runs.len);
        try std.testing.expectEqual(case.expected_script, runs[0].script);
        try std.testing.expectEqual(case.expected_tag, unicode.openTypeScriptTag(runs[0].script));
        try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(try std.unicode.utf8Decode(case.text[0..3])));
        try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(case.reserved));

        const words = try unicode.itemizeWordSegments(allocator, case.text);
        defer allocator.free(words);
        try std.testing.expectEqual(@as(usize, 1), words.len);
        try std.testing.expectEqual(@as(usize, 0), words[0].byte_start);
        try std.testing.expectEqual(case.text.len, words[0].byte_len);
    }

    // The two shared punctuation marks have Script=Common. In surrounding
    // text they inherit the neighboring script run, but they do not become
    // editor words by themselves.
    try std.testing.expectEqual(unicode.Script.common, unicode.scriptForCodepoint(0x1735));
    try std.testing.expectEqual(unicode.Script.common, unicode.scriptForCodepoint(0x1736));
    const punctuation_words = try unicode.itemizeWordSegments(allocator, "\u{1735}\u{1736}");
    defer allocator.free(punctuation_words);
    try std.testing.expectEqual(@as(usize, 0), punctuation_words.len);
}

test "Rejang syllables keep signs and select Rejang OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{a930}\u{a947} \u{a930}\u{a952} \u{a930}\u{a953} \u{a95f}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{a930}\u{a947}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a930}\u{a952}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{a930}\u{a953}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{a95f}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.rejang, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.rjng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa930)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.rjng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa947)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.rjng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa953)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.rjng, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa95f)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0xa954));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa930));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0xa954));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{a930}\u{a947}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a930}\u{a952}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a930}\u{a953}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Limbu syllables keep marks and select Limbu OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᤁᤠ᤹ ᤁᤩ ᤋ᤺ᤛ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᤁᤠ᤹", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᤁᤩ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᤋ᤺", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᤛ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.limbu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.limb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1901)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.limb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1929)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.limb, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1946)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1901));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᤁᤠ᤹", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᤁᤩ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᤋ᤺ᤛ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Lepcha syllables keep signs and select Lepcha OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᰀᰦ ᰁᰤᰬ ᱍ᰷ ᱀᰻";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("ᰀᰦ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᰁᰤᰬ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᱍ᰷", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("᱀", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings("᰻", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.lepcha, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lepc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c00)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lepc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c24)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lepc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c37)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lepc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c3b)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lepc, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1c4d)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1c38));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1c00));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0x1c38));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ᰀᰦ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᰁᰤᰬ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᱍ᰷", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("᱀", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Buginese syllables keep vowels and select Buginese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᨀᨗ ᨔᨛ ᨄᨙᨑᨗ";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᨀᨗ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᨔᨛ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᨄᨙ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᨑᨗ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.buginese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bugi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1a00)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bugi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1a17)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.bugi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1a19)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1a00));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᨀᨗ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᨔᨛ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᨄᨙᨑᨗ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Sundanese syllables keep signs and select Sundanese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᮊᮥ ᮔ᮪ ᮞᮥᮔ᮪ᮓ ᳀";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("ᮊᮥ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᮔ᮪", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᮞᮥ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᮔ᮪", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("ᮓ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("᳀", text[clusters[8].byte_start..][0..clusters[8].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.sundanese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sund, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1b8a)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sund, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1ba5)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sund, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1baa)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.sund, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1cc0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1b8a));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ᮊᮥ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᮔ᮪", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᮞᮥᮔ᮪ᮓ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("᳀", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Batak syllables keep signs and select Batak OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{1bc5}\u{1be6}\u{1be7} \u{1bd4}\u{1bf0}\u{1bf2} \u{1bfc}";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("\u{1bc5}\u{1be6}\u{1be7}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1bd4}\u{1bf0}\u{1bf2}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{1bfc}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.batak, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.batk, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1bc5)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.batk, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1be6)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.batk, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1bf2)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.batk, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1bfc)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x1bf4));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1bc5));
    try std.testing.expectEqual(unicode.BidiClass.neutral, unicode.bidiClassForCodepoint(0x1bf4));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{1bc5}\u{1be6}\u{1be7}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1bd4}\u{1bf0}\u{1bf2}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Meetei Mayek syllables keep signs and select Meetei OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꯀꯤ ꯑꯩ ꫠꫫ ꯄ꯭ ꯱";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("ꯀꯤ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ꯑꯩ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ꫠꫫ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("ꯄ꯭", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("꯱", text[clusters[8].byte_start..][0..clusters[8].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.meetei_mayek, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mtei, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xabc0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mtei, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xabe4)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mtei, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaae0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.mtei, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xabf1)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xabc0));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("ꯀꯤ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ꯑꯩ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ꫠꫫ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("ꯄ꯭", text[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("꯱", text[words[4].byte_start..][0..words[4].byte_len]);
}

test "Canadian Aboriginal syllabics select cans script across extensions" {
    const allocator = std.testing.allocator;

    const text = "ᐃᓄᒃᑎᑐᑦ ᢰᣵ 𑪰𑪿";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 12), clusters.len);
    try std.testing.expectEqualStrings("ᐃ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ᢰ", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("𑪰", text[clusters[10].byte_start..][0..clusters[10].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.canadian_aboriginal, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cans, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1403)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cans, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x18b0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cans, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11ab0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1403));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᐃᓄᒃᑎᑐᑦ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᢰᣵ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("𑪰𑪿", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Cham syllables keep signs and select Cham OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꨆꨩ ꨆꨯ ꩀꩃꩍ ꩐";
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("ꨆꨩ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ꨆꨯ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ꩀꩃꩍ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("꩐", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.cham, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cham, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaa06)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cham, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaa29)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cham, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaa4d)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.cham, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xaa50)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xaa06));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ꨆꨩ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ꨆꨯ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ꩀꩃꩍ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("꩐", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Yi syllables and radicals select Yi script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a000}\u{a001} \u{a490}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.yi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.yi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa000)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.yi, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa490)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa000));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{a000}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a001}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a490}", text[words[2].byte_start..][0..words[2].byte_len]);

    const breaks = try unicode.itemizeLineBreaks(allocator, "\u{a000}\u{a001}\u{a490}");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 3), breaks.len);
    try std.testing.expectEqual(@as(usize, 3), breaks[0].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 6), breaks[1].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 9), breaks[2].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.hard, breaks[2].kind);
}

test "Vai syllables select Vai script and word primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a500}\u{a501}\u{a60c} \u{a610}\u{a620}\u{a60d}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.vai, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.vai, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa500)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.vai, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa60c)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.vai, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa620)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa500));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{a500}\u{a501}\u{a60c}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a610}\u{a620}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Lisu letters select Lisu script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a4d0}\u{a4f4}\u{a4fd} \u{11fb0}\u{a4f0}\u{a4ff}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.lisu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lisu, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa4d0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lisu, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0xa4fd)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.lisu, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x11fb0)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0xa4d0));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x11fb0));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{a4d0}\u{a4f4}\u{a4fd}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{11fb0}\u{a4f0}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Nushu characters select Nushu script and ideographic layout primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{1b170}\u{1b171} \u{1b2fb}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.nushu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.nshu, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1b170)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.nshu, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1b2fb)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1b170));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{1b170}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1b171}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1b2fb}", text[words[2].byte_start..][0..words[2].byte_len]);

    const breaks = try unicode.itemizeLineBreaks(allocator, "\u{1b170}\u{1b171}\u{1b2fb}");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 3), breaks.len);
    try std.testing.expectEqual(@as(usize, 4), breaks[0].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 8), breaks[1].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.soft, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 12), breaks[2].byte_offset);
    try std.testing.expectEqual(unicode.LineBreakKind.hard, breaks[2].kind);
}

test "Runic text selects Runic script primitives and groups words around separators" {
    const allocator = std.testing.allocator;

    const text = "\u{16a0}\u{16b1}\u{16eb}\u{16f0} \u{16ee}\u{16f8}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.runic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.runr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x16a0)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.runr, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x16f8)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x16a0));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x16ee));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{16a0}\u{16b1}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{16f0}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{16ee}\u{16f8}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Coptic text selects Coptic script primitives across blocks" {
    const allocator = std.testing.allocator;

    const text = "\u{03e2}\u{2cef}\u{2c81} \u{102e1}\u{102e0}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.coptic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.copt, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x03e2)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.copt, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x2c81)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.dflt, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x102e1)));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x2c81));

    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("\u{03e2}\u{2cef}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c81}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{102e1}\u{102e0}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{03e2}\u{2cef}\u{2c81}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{102e1}\u{102e0}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Ogham text selects Ogham script and excludes native separators from words" {
    const allocator = std.testing.allocator;

    const text = "\u{1681}\u{1682}\u{1680}\u{169a}\u{169b}\u{169c}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.ogham, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ogam, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1681)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ogam, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1680)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.ogam, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x169c)));
    try std.testing.expectEqual(unicode.Script.unknown, unicode.scriptForCodepoint(0x169d));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1681));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{1681}\u{1682}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{169a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Duployan text selects Duployan script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{1bc02}\u{1bc5b}\u{034f}\u{034f}\u{034f}\u{1bc1c}\u{200c}\u{1bc02}";
    const runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(unicode.Script.duployan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.dupl, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1bc02)));
    try std.testing.expectEqual(unicode.OpenTypeScriptTag.dupl, unicode.openTypeScriptTag(unicode.scriptForCodepoint(0x1bc9f)));
    try std.testing.expectEqual(unicode.Script.common, unicode.scriptForCodepoint(0x1bca0));
    try std.testing.expectEqual(unicode.BidiClass.ltr, unicode.bidiClassForCodepoint(0x1bc02));

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 1), words.len);
    try std.testing.expectEqualStrings(text, text[words[0].byte_start..][0..words[0].byte_len]);
}
