//! Existing editor word-selection tailoring.
//!
//! This is deliberately separate from the standards-conformant all-segment
//! iterator in `iterator.zig`. It preserves established script-specific word
//! grouping for cursor movement without presenting those choices as UAX #29.

pub const Script = enum {
    other,
    han,
    yi,
    nushu,
    hiragana,
    katakana,
    hangul,
    tangut,
    egyptian_hieroglyphs,
    cuneiform,
    signwriting,
    bamum,
    anatolian_hieroglyphs,
    khitan_small_script,
    linear_a,
    braille,
    tagalog,
    hanunoo,
    buhid,
    tagbanwa,
    arabic,
    hebrew,
    armenian,
    devanagari,
    bengali,
    odia,
    gurmukhi,
    telugu,
    kannada,
    sinhala,
    tamil,
    malayalam,
    balinese,
    javanese,
    tai_tham,
    marchen,
    limbu,
    buginese,
    sundanese,
    meetei_mayek,
    canadian_aboriginal,
    cham,
    brahmi,
    khudawadi,
    tirhuta,
    modi,
    takri,
};

pub const Kind = enum {
    none,
    single,
    latin_number,
    lisu,
    vai,
    tagalog,
    hanunoo,
    buhid,
    tagbanwa,
    arabic,
    hebrew,
    syriac,
    samaritan,
    phoenician,
    armenian,
    glagolitic,
    old_italic,
    ugaritic,
    old_persian,
    avestan,
    imperial_aramaic,
    old_south_arabian,
    old_north_arabian,
    meroitic_hieroglyphs,
    meroitic_cursive,
    thaana,
    adlam,
    mandaic,
    nko,
    khmer,
    myanmar,
    devanagari,
    bengali,
    odia,
    gurmukhi,
    gujarati,
    telugu,
    kannada,
    sinhala,
    tamil,
    malayalam,
    balinese,
    javanese,
    tai_tham,
    marchen,
    newa,
    kayah_li,
    saurashtra,
    rejang,
    grantha,
    limbu,
    sharada,
    lepcha,
    buginese,
    sundanese,
    batak,
    meetei_mayek,
    canadian_aboriginal,
    tifinagh,
    cham,
    brahmi,
    kaithi,
    chakma,
    runic,
    coptic,
    ogham,
    duployan,
};
pub fn kindForCodepoint(codepoint: u21, script: Script) Kind {
    if ((codepoint >= 'A' and codepoint <= 'Z') or
        (codepoint >= 'a' and codepoint <= 'z') or
        (codepoint >= '0' and codepoint <= '9') or
        codepoint == '_')
    {
        return .latin_number;
    }
    if (isLisuWordCodepoint(codepoint)) return .lisu;
    if (isVaiWordCodepoint(codepoint)) return .vai;
    if (isTagalogWordCodepoint(codepoint)) return .tagalog;
    if (isHanunooWordCodepoint(codepoint)) return .hanunoo;
    if (isBuhidWordCodepoint(codepoint)) return .buhid;
    if (isTagbanwaWordCodepoint(codepoint)) return .tagbanwa;
    if (isKhmerWordCodepoint(codepoint)) return .khmer;
    if (isMyanmarWordCodepoint(codepoint)) return .myanmar;
    if (isThaanaWordCodepoint(codepoint)) return .thaana;
    if (isAdlamWordCodepoint(codepoint)) return .adlam;
    if (isSyriacWordCodepoint(codepoint)) return .syriac;
    if (isSamaritanWordCodepoint(codepoint)) return .samaritan;
    if (isMandaicWordCodepoint(codepoint)) return .mandaic;
    if (isNkoWordCodepoint(codepoint)) return .nko;
    if (isPhoenicianWordCodepoint(codepoint)) return .phoenician;
    if (isLepchaWordCodepoint(codepoint)) return .lepcha;
    if (isGujaratiWordCodepoint(codepoint)) return .gujarati;
    if (isRunicWordCodepoint(codepoint)) return .runic;
    if (isCopticWordCodepoint(codepoint)) return .coptic;
    if (isOghamWordCodepoint(codepoint)) return .ogham;
    if (isDuployanWordCodepoint(codepoint)) return .duployan;
    if (isBatakWordCodepoint(codepoint)) return .batak;
    if (isTifinaghWordCodepoint(codepoint)) return .tifinagh;
    if (isGlagoliticWordCodepoint(codepoint)) return .glagolitic;
    if (isOldItalicWordCodepoint(codepoint)) return .old_italic;
    if (isUgariticWordCodepoint(codepoint)) return .ugaritic;
    if (isOldPersianWordCodepoint(codepoint)) return .old_persian;
    if (isAvestanWordCodepoint(codepoint)) return .avestan;
    if (isImperialAramaicWordCodepoint(codepoint)) return .imperial_aramaic;
    if (isOldSouthArabianWordCodepoint(codepoint)) return .old_south_arabian;
    if (isOldNorthArabianWordCodepoint(codepoint)) return .old_north_arabian;
    if (isMeroiticHieroglyphsWordCodepoint(codepoint)) return .meroitic_hieroglyphs;
    if (isMeroiticCursiveWordCodepoint(codepoint)) return .meroitic_cursive;
    if (isKayahLiWordCodepoint(codepoint)) return .kayah_li;
    if (isSaurashtraWordCodepoint(codepoint)) return .saurashtra;
    if (isRejangWordCodepoint(codepoint)) return .rejang;
    if (isGranthaWordCodepoint(codepoint)) return .grantha;
    if (isSharadaWordCodepoint(codepoint)) return .sharada;
    if (isKaithiWordCodepoint(codepoint)) return .kaithi;
    if (isChakmaWordCodepoint(codepoint)) return .chakma;
    if (isNewaWordCodepoint(codepoint)) return .newa;
    return switch (script) {
        .han, .yi, .nushu, .hiragana, .katakana, .hangul, .tangut, .egyptian_hieroglyphs, .cuneiform, .signwriting, .anatolian_hieroglyphs, .khitan_small_script, .linear_a, .braille => .single,
        .bamum => .latin_number,
        .arabic => .arabic,
        .hebrew => .hebrew,
        .armenian => .armenian,
        .devanagari => .devanagari,
        .bengali => .bengali,
        .odia => .odia,
        .gurmukhi => .gurmukhi,
        .telugu => .telugu,
        .kannada => .kannada,
        .sinhala => .sinhala,
        .tamil => .tamil,
        .malayalam => .malayalam,
        .balinese => .balinese,
        .javanese => .javanese,
        .tai_tham => .tai_tham,
        .marchen => .marchen,
        .limbu => .limbu,
        .buginese => .buginese,
        .sundanese => .sundanese,
        .meetei_mayek => .meetei_mayek,
        .canadian_aboriginal => .canadian_aboriginal,
        .cham => .cham,
        .brahmi => .brahmi,
        .khudawadi, .tirhuta, .modi, .takri => .single,
        .tagalog => .tagalog,
        .hanunoo => .hanunoo,
        .buhid => .buhid,
        .tagbanwa => .tagbanwa,
        else => .none,
    };
}

fn isVaiWordCodepoint(codepoint: u21) bool {
    // U+A60D..U+A60F are Vai punctuation. Syllables, the syllable lengthener,
    // supplementary syllables, and native digits should group into normal
    // space-delimited words instead of becoming one segment per codepoint.
    return (codepoint >= 0xa500 and codepoint <= 0xa60c) or
        (codepoint >= 0xa610 and codepoint <= 0xa62b);
}

fn isLisuWordCodepoint(codepoint: u21) bool {
    // U+A4FE/U+A4FF are Lisu punctuation, not word letters. The rest of the
    // base block plus U+11FB0 should group into normal space-delimited words.
    return (codepoint >= 0xa4d0 and codepoint <= 0xa4fd) or
        codepoint == 0x11fb0;
}

fn isTagalogWordCodepoint(codepoint: u21) bool {
    // Anchor editor-word spans on Baybayin letters. Dependent signs attach
    // through the generated Extend/SpacingMark properties after a word starts.
    return (codepoint >= 0x1700 and codepoint <= 0x1711) or
        codepoint == 0x171f;
}

fn isHanunooWordCodepoint(codepoint: u21) bool {
    // Philippine punctuation stays outside word spans. Dependent signs attach
    // through the generic Extend/SpacingMark path once a letter starts a word.
    return codepoint >= 0x1720 and codepoint <= 0x1731;
}

fn isBuhidWordCodepoint(codepoint: u21) bool {
    return codepoint >= 0x1740 and codepoint <= 0x1751;
}

fn isTagbanwaWordCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1760 and codepoint <= 0x176c) or
        (codepoint >= 0x176e and codepoint <= 0x1770);
}

fn isNewaWordCodepoint(codepoint: u21) bool {
    // Letters, dependent signs, native digits, and the sandhi/Vedic signs form
    // normal space-delimited words. Dandas and the punctuation ranges
    // U+11448..U+1144F/U+1145A..U+1145D remain separators.
    return (codepoint >= 0x11400 and codepoint <= 0x11447) or
        (codepoint >= 0x11450 and codepoint <= 0x11459) or
        (codepoint >= 0x1145e and codepoint <= 0x11461);
}

fn isKayahLiWordCodepoint(codepoint: u21) bool {
    // Anchor word spans on Kayah Li digits and base letters. Vowels and tones
    // attach through the generic extender table, while U+A92E/U+A92F are script
    // punctuation that should keep shaping context but break selectable words.
    return codepoint >= 0xa900 and codepoint <= 0xa925;
}

fn isSaurashtraWordCodepoint(codepoint: u21) bool {
    return (codepoint >= 0xa880 and codepoint <= 0xa8c5) or
        (codepoint >= 0xa8d0 and codepoint <= 0xa8d9);
}

fn isRejangWordCodepoint(codepoint: u21) bool {
    // Word spans are anchored on Rejang letters. Dependent vowels, final
    // consonant signs, and virama attach through the generic extender tables,
    // while the section mark remains script text but not selectable word text.
    return codepoint >= 0xa930 and codepoint <= 0xa946;
}

fn isGranthaWordCodepoint(codepoint: u21) bool {
    if (codepoint == 0x1133b) return false;
    return (codepoint >= 0x11300 and codepoint <= 0x11303) or
        (codepoint >= 0x11305 and codepoint <= 0x1130c) or
        (codepoint >= 0x1130f and codepoint <= 0x11310) or
        (codepoint >= 0x11313 and codepoint <= 0x11328) or
        (codepoint >= 0x1132a and codepoint <= 0x11330) or
        (codepoint >= 0x11332 and codepoint <= 0x11333) or
        (codepoint >= 0x11335 and codepoint <= 0x11344) or
        (codepoint >= 0x11347 and codepoint <= 0x11348) or
        (codepoint >= 0x1134b and codepoint <= 0x1134d) or
        codepoint == 0x11350 or codepoint == 0x11357 or
        (codepoint >= 0x1135d and codepoint <= 0x11363) or
        (codepoint >= 0x11366 and codepoint <= 0x1136c) or
        (codepoint >= 0x11370 and codepoint <= 0x11374);
}

fn isSharadaWordCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x11180 and codepoint <= 0x111c4) or
        (codepoint >= 0x111c9 and codepoint <= 0x111cc) or
        (codepoint >= 0x111ce and codepoint <= 0x111da) or
        codepoint == 0x111dc or
        (codepoint >= 0x11b60 and codepoint <= 0x11b67);
}

fn isLepchaWordCodepoint(codepoint: u21) bool {
    // Anchor word spans on Lepcha base letters and native digits. Dependent
    // vowels, subjoined letters, finals, and nukta attach through the generic
    // extender path, while Lepcha punctuation remains a word separator.
    return (codepoint >= 0x1c00 and codepoint <= 0x1c23) or
        (codepoint >= 0x1c40 and codepoint <= 0x1c49) or
        (codepoint >= 0x1c4d and codepoint <= 0x1c4f);
}

fn isBatakWordCodepoint(codepoint: u21) bool {
    // Anchor word spans on Batak letters. Dependent vowels/consonant signs and
    // pangolat attach through the generic extender tables; bindu punctuation
    // remains in the script run for shaping but deliberately breaks words.
    return codepoint >= 0x1bc0 and codepoint <= 0x1be5;
}

fn isKaithiWordCodepoint(codepoint: u21) bool {
    // Anchor word spans on Kaithi letters. Dependent signs attach through the
    // generic extender tables; number signs and punctuation stay in the script
    // run for shaping but do not become selectable word text by themselves.
    return codepoint >= 0x11083 and codepoint <= 0x110af;
}

fn isChakmaWordCodepoint(codepoint: u21) bool {
    // Word spans are anchored on Chakma letters and native digits. Dependent
    // signs and virama attach through the generic extender path, while danda,
    // section, and question punctuation remain shaping script text but break
    // selectable word spans.
    return (codepoint >= 0x11103 and codepoint <= 0x11126) or
        (codepoint >= 0x11136 and codepoint <= 0x1113f) or
        codepoint == 0x11144 or
        codepoint == 0x11147;
}

fn isRunicWordCodepoint(codepoint: u21) bool {
    // U+16EB..U+16ED are Runic word/division punctuation. Letters and Runic
    // numeric symbols should group into normal word spans, while those
    // separators deliberately break words just like spaces or punctuation.
    return (codepoint >= 0x16a0 and codepoint <= 0x16ea) or
        (codepoint >= 0x16ee and codepoint <= 0x16f8);
}

fn isCopticWordCodepoint(codepoint: u21) bool {
    // Exclude Coptic block punctuation/fraction signs from words, but keep the
    // historic letters and Epact number signs grouped as normal unspaced Coptic
    // tokens. Combining marks attach through isWordExtender().
    return (codepoint >= 0x03e2 and codepoint <= 0x03ef) or
        (codepoint >= 0x2c80 and codepoint <= 0x2ce4) or
        (codepoint >= 0x2ceb and codepoint <= 0x2cee) or
        (codepoint >= 0x2cf2 and codepoint <= 0x2cf3) or
        (codepoint >= 0x102e1 and codepoint <= 0x102fb);
}

fn isOghamWordCodepoint(codepoint: u21) bool {
    // U+1680 OGHAM SPACE MARK and U+169B/U+169C feather marks are separators,
    // not word letters. The twenty-five letter names form normal unspaced word
    // spans for caret movement and selection.
    return codepoint >= 0x1681 and codepoint <= 0x169a;
}

fn isDuployanWordCodepoint(codepoint: u21) bool {
    return codepoint >= 0x1bc00 and codepoint <= 0x1bc9f;
}

fn isPhoenicianWordCodepoint(codepoint: u21) bool {
    // Phoenician number signs are strong RTL script characters and should group
    // with adjacent letters for coarse word/caret primitives. U+1091F is a
    // word separator, so it stays in the script run but deliberately breaks the
    // selectable word span.
    return codepoint >= 0x10900 and codepoint <= 0x1091b;
}

fn isSamaritanWordCodepoint(codepoint: u21) bool {
    // Word spans are anchored on letters and spacing modifier letters. Vowel
    // and reading marks attach through isWordExtender(), while the native
    // punctuation remains part of the RTL script run but breaks word selection.
    return (codepoint >= 0x0800 and codepoint <= 0x0815) or
        codepoint == 0x081a or
        codepoint == 0x0824 or
        codepoint == 0x0828;
}

fn isNkoWordCodepoint(codepoint: u21) bool {
    // N'Ko words can contain native digits and spacing modifier letters. Tone
    // and nasalization marks attach through isWordExtender(); punctuation,
    // symbols, and currency signs stay in the script run but do not become
    // selectable word text by themselves.
    return (codepoint >= 0x07c0 and codepoint <= 0x07ea) or
        codepoint == 0x07f4 or
        codepoint == 0x07f5 or
        codepoint == 0x07fa;
}

fn isAdlamWordCodepoint(codepoint: u21) bool {
    // Word spans include cased Adlam letters, the spacing nasalization mark,
    // and native digits. Combining Adlam marks attach through isWordExtender(),
    // while initial question/exclamation punctuation deliberately terminates a
    // word rather than becoming selectable text by itself.
    return (codepoint >= 0x1e900 and codepoint <= 0x1e943) or
        codepoint == 0x1e94b or
        (codepoint >= 0x1e950 and codepoint <= 0x1e959);
}

fn isThaanaWordCodepoint(codepoint: u21) bool {
    // Keep words anchored on Thaana letters. Fili marks attach through the
    // generic word-extender path so a stray leading mark does not become a word
    // by itself, but normal letter+mark syllables remain one selectable token.
    return (codepoint >= 0x0780 and codepoint <= 0x07a5) or
        codepoint == 0x07b1;
}

fn isKhmerWordCodepoint(codepoint: u21) bool {
    // Khmer does not use spaces between every lexical word, so this compact
    // primitive only exposes contiguous letter/sign/digit spans. It
    // deliberately excludes Khmer sentence punctuation and lunar-date symbols:
    // those should remain in the script run for shaping but should not become
    // selectable "words" on their own.
    return (codepoint >= 0x1780 and codepoint <= 0x17d3) or
        codepoint == 0x17d7 or
        codepoint == 0x17dc or
        codepoint == 0x17dd or
        (codepoint >= 0x17e0 and codepoint <= 0x17f9);
}

fn isMyanmarWordCodepoint(codepoint: u21) bool {
    // Exclude Myanmar section punctuation and symbols from word spans while
    // keeping letters, dependent signs, medials, viramas/asat, tone marks, and
    // native digits together as one orthographic token for selection and layout
    // cache boundaries. Combining/spacing marks also attach through the generic
    // extender tables, but listing them here keeps a mark following a Myanmar
    // digit or extension letter in the same script-specific word class.
    return (codepoint >= 0x1000 and codepoint <= 0x1049) or
        (codepoint >= 0x1050 and codepoint <= 0x109d) or
        (codepoint >= 0xa9e0 and codepoint <= 0xa9fe) or
        (codepoint >= 0xaa60 and codepoint <= 0xaa76) or
        (codepoint >= 0xaa7a and codepoint <= 0xaa7f) or
        (codepoint >= 0x116d0 and codepoint <= 0x116e3);
}

fn isSyriacWordCodepoint(codepoint: u21) bool {
    // Anchor Syriac word spans on encoded letters only. Script punctuation and
    // U+070F abbreviation formatting must remain inside the RTL shaping run,
    // but they should not become selectable words; vowel/pointing marks attach
    // through isWordExtender() once a word has started.
    return codepoint == 0x0710 or
        (codepoint >= 0x0712 and codepoint <= 0x072f) or
        (codepoint >= 0x074d and codepoint <= 0x074f) or
        (codepoint >= 0x0860 and codepoint <= 0x086a);
}

fn isMandaicWordCodepoint(codepoint: u21) bool {
    // Mandaic words are anchored by letters. Combining marks attach through the
    // generic word-extender path, while U+085E punctuation remains a separator
    // even though it stays in the Mandaic script run for shaping and bidi.
    return codepoint >= 0x0840 and codepoint <= 0x0858;
}

fn isTifinaghWordCodepoint(codepoint: u21) bool {
    // Tifinagh words are anchored by letters plus U+2D6F labialization mark.
    // U+2D70 is punctuation and U+2D7F attaches through isWordExtender(), so
    // neither should start a selectable word on its own.
    return (codepoint >= 0x2d30 and codepoint <= 0x2d67) or
        codepoint == 0x2d6f;
}

fn isGujaratiWordCodepoint(codepoint: u21) bool {
    // Exclude Gujarati abbreviation/currency signs from word spans while
    // grouping letters, avagraha/OM, vocalic letters, and native digits.
    // Dependent signs attach through isWordExtender(), which avoids letting a
    // stray leading vowel mark become a selectable word by itself.
    return (codepoint >= 0x0a85 and codepoint <= 0x0a8d) or
        (codepoint >= 0x0a8f and codepoint <= 0x0a91) or
        (codepoint >= 0x0a93 and codepoint <= 0x0aa8) or
        (codepoint >= 0x0aaa and codepoint <= 0x0ab0) or
        (codepoint >= 0x0ab2 and codepoint <= 0x0ab3) or
        (codepoint >= 0x0ab5 and codepoint <= 0x0ab9) or
        codepoint == 0x0abd or
        codepoint == 0x0ad0 or
        (codepoint >= 0x0ae0 and codepoint <= 0x0ae1) or
        (codepoint >= 0x0ae6 and codepoint <= 0x0aef) or
        codepoint == 0x0af9;
}

fn isGlagoliticWordCodepoint(codepoint: u21) bool {
    // Word spans are anchored on Glagolitic base letters. Supplementary
    // combining letters attach through isWordExtender(), which avoids turning a
    // stray leading combining mark into a selectable word by itself while still
    // preserving marked manuscript abbreviations as one token.
    return codepoint >= 0x2c00 and codepoint <= 0x2c5f;
}

fn isOldItalicWordCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x10300 and codepoint <= 0x10323) or
        (codepoint >= 0x1032d and codepoint <= 0x1032f);
}

fn isUgariticWordCodepoint(codepoint: u21) bool {
    // U+1039F UGARITIC WORD DIVIDER separates words. Ugaritic letters form
    // normal selectable word spans; the reserved U+1039E remains unknown.
    return codepoint >= 0x10380 and codepoint <= 0x1039d;
}

fn isOldPersianWordCodepoint(codepoint: u21) bool {
    // U+103D0 OLD PERSIAN WORD DIVIDER is script punctuation and should keep the
    // surrounding shaping run in `xpeo`, but it deliberately breaks selectable
    // word spans. Signs, logograms, and native numbers remain grouped.
    return (codepoint >= 0x103a0 and codepoint <= 0x103c3) or
        (codepoint >= 0x103c8 and codepoint <= 0x103cf) or
        (codepoint >= 0x103d1 and codepoint <= 0x103d5);
}

fn isAvestanWordCodepoint(codepoint: u21) bool {
    // U+10B39..U+10B3F are Avestan separators and abbreviation punctuation,
    // not word letters. Keep only the encoded letters in selectable word
    // spans; the punctuation still remains in the surrounding RTL script run.
    return codepoint >= 0x10b00 and codepoint <= 0x10b35;
}

fn isImperialAramaicWordCodepoint(codepoint: u21) bool {
    // Native Imperial Aramaic number signs have strong RTL script behavior and
    // should group with adjacent letters for coarse word/caret primitives. The
    // section sign remains script text for shaping but deliberately separates
    // selectable word spans.
    return (codepoint >= 0x10840 and codepoint <= 0x10855) or
        (codepoint >= 0x10858 and codepoint <= 0x1085f);
}

fn isOldSouthArabianWordCodepoint(codepoint: u21) bool {
    // U+10A7F OLD SOUTH ARABIAN NUMERIC INDICATOR is script text but not a
    // letter/number value by itself. Let it separate coarse word spans while
    // grouping native number signs with adjacent letters like the other
    // historic RTL scripts handled here.
    return codepoint >= 0x10a60 and codepoint <= 0x10a7e;
}

fn isOldNorthArabianWordCodepoint(codepoint: u21) bool {
    return codepoint >= 0x10a80 and codepoint <= 0x10a9f;
}

fn isMeroiticHieroglyphsWordCodepoint(codepoint: u21) bool {
    return codepoint >= 0x10980 and codepoint <= 0x1099f;
}

fn isMeroiticCursiveWordCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x109a0 and codepoint <= 0x109b7) or
        (codepoint >= 0x109bc and codepoint <= 0x109cf) or
        (codepoint >= 0x109d2 and codepoint <= 0x109ff);
}
