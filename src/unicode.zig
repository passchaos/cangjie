const std = @import("std");

/// Lightweight Unicode helpers used by the shaping/layout layers.
/// The tables are intentionally compact and cover the scripts and boundaries
/// currently exercised by Cangjie; they are not a replacement for the full UAX
/// datasets yet.
pub const Script = enum {
    common,
    inherited,
    latin,
    greek,
    cyrillic,
    glagolitic,
    old_italic,
    avestan,
    han,
    yi,
    lisu,
    vai,
    hiragana,
    katakana,
    hangul,
    arabic,
    hebrew,
    phoenician,
    syriac,
    mandaic,
    armenian,
    thai,
    lao,
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
    ethiopic,
    georgian,
    cherokee,
    tifinagh,
    tibetan,
    nko,
    thaana,
    adlam,
    mongolian,
    balinese,
    javanese,
    limbu,
    lepcha,
    buginese,
    sundanese,
    meetei_mayek,
    canadian_aboriginal,
    cham,
    brahmi,
    nushu,
    runic,
    coptic,
    ogham,
    unknown,
};

pub const ScriptRun = struct {
    script: Script,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiClass = enum {
    ltr,
    rtl,
    number,
    neutral,
};

pub const BidiRun = struct {
    direction: BidiClass,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiMapItem = struct {
    logical_index: usize,
    visual_index: usize,
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    visual_codepoint: u21,
    direction: BidiClass,
};

pub const BidiMap = struct {
    allocator: std.mem.Allocator,
    items: []BidiMapItem,
    logical_to_visual: []usize,

    pub fn deinit(self: *BidiMap) void {
        self.allocator.free(self.logical_to_visual);
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn visualToLogical(self: BidiMap, visual_index: usize) ?usize {
        if (visual_index >= self.items.len) return null;
        return self.items[visual_index].logical_index;
    }

    pub fn logicalToVisual(self: BidiMap, logical_index: usize) ?usize {
        if (logical_index >= self.logical_to_visual.len) return null;
        return self.logical_to_visual[logical_index];
    }
};

pub const GraphemeCluster = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const WordSegment = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const SentenceSegment = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const LineBreakKind = enum {
    soft,
    hard,
};

pub const LineBreak = struct {
    byte_offset: usize,
    kind: LineBreakKind,
};

pub const OpenTypeScriptTag = enum(u32) {
    dflt = tag("DFLT"),
    latn = tag("latn"),
    grek = tag("grek"),
    cyrl = tag("cyrl"),
    glag = tag("glag"),
    ital = tag("ital"),
    avst = tag("avst"),
    hani = tag("hani"),
    yi = tag("yi  "),
    lisu = tag("lisu"),
    vai = tag("vai "),
    hira = tag("hira"),
    kana = tag("kana"),
    hang = tag("hang"),
    arab = tag("arab"),
    hebr = tag("hebr"),
    phnx = tag("phnx"),
    syrc = tag("syrc"),
    mand = tag("mand"),
    armn = tag("armn"),
    thai = tag("thai"),
    lao = tag("lao "),
    khmr = tag("khmr"),
    mym2 = tag("mym2"),
    dev2 = tag("dev2"),
    bng2 = tag("bng2"),
    ory2 = tag("ory2"),
    gur2 = tag("gur2"),
    gjr2 = tag("gjr2"),
    tel2 = tag("tel2"),
    knd2 = tag("knd2"),
    sinh = tag("sinh"),
    taml = tag("taml"),
    mlm2 = tag("mlm2"),
    ethi = tag("ethi"),
    geor = tag("geor"),
    cher = tag("cher"),
    tfng = tag("tfng"),
    tibt = tag("tibt"),
    nko = tag("nko "),
    thaa = tag("thaa"),
    adlm = tag("adlm"),
    mong = tag("mong"),
    bali = tag("bali"),
    java = tag("java"),
    limb = tag("limb"),
    lepc = tag("lepc"),
    bugi = tag("bugi"),
    sund = tag("sund"),
    mtei = tag("mtei"),
    cans = tag("cans"),
    cham = tag("cham"),
    brah = tag("brah"),
    nshu = tag("nshu"),
    runr = tag("runr"),
    copt = tag("copt"),
    ogam = tag("ogam"),
};

pub const OpenTypeLanguageTag = enum(u32) {
    dflt = tag("dflt"),
    ara = tag("ARA "),
    jan = tag("JAN "),
    kor = tag("KOR "),
    zhs = tag("ZHS "),
    zht = tag("ZHT "),
    hin = tag("HIN "),
};

pub const FeatureOverride = struct {
    tag: u32,
    enabled: bool,
};

/// Map the internal script enum to the OpenType script tag used for GSUB/GPOS
/// ScriptList selection.
pub fn openTypeScriptTag(script: Script) OpenTypeScriptTag {
    return switch (script) {
        .latin => .latn,
        .greek => .grek,
        .cyrillic => .cyrl,
        .glagolitic => .glag,
        .old_italic => .ital,
        .avestan => .avst,
        .han => .hani,
        .yi => .yi,
        .lisu => .lisu,
        .vai => .vai,
        .hiragana => .hira,
        .katakana => .kana,
        .hangul => .hang,
        .arabic => .arab,
        .hebrew => .hebr,
        .phoenician => .phnx,
        .syriac => .syrc,
        .mandaic => .mand,
        .armenian => .armn,
        .thai => .thai,
        .lao => .lao,
        .khmer => .khmr,
        .myanmar => .mym2,
        .devanagari => .dev2,
        .bengali => .bng2,
        .odia => .ory2,
        .gurmukhi => .gur2,
        .gujarati => .gjr2,
        .telugu => .tel2,
        .kannada => .knd2,
        .sinhala => .sinh,
        .tamil => .taml,
        .malayalam => .mlm2,
        .ethiopic => .ethi,
        .georgian => .geor,
        .cherokee => .cher,
        .tifinagh => .tfng,
        .tibetan => .tibt,
        .nko => .nko,
        .thaana => .thaa,
        .adlam => .adlm,
        .mongolian => .mong,
        .balinese => .bali,
        .javanese => .java,
        .limbu => .limb,
        .lepcha => .lepc,
        .buginese => .bugi,
        .sundanese => .sund,
        .meetei_mayek => .mtei,
        .canadian_aboriginal => .cans,
        .cham => .cham,
        .brahmi => .brah,
        .nushu => .nshu,
        .runic => .runr,
        .coptic => .copt,
        .ogham => .ogam,
        .common, .inherited, .unknown => .dflt,
    };
}

/// Infer a coarse OpenType language tag from script content when the caller did
/// not specify one. This gives CJK, Arabic, and Indic fonts a better default
/// LangSys than always using `dflt`.
pub fn inferOpenTypeLanguageTag(text: []const u8) OpenTypeLanguageTag {
    var saw_han = false;
    var cursor: usize = 0;
    while (cursor < text.len) {
        const decoded = decodeCodepointAt(text, cursor) orelse return .dflt;
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
        const script = scriptForCodepoint(codepoint);
        switch (script) {
            .hiragana, .katakana => return .jan,
            .hangul => return .kor,
            .arabic => return .ara,
            .devanagari => return .hin,
            .bengali, .odia, .gurmukhi, .telugu, .kannada, .tamil, .thai, .lao => return .dflt,
            .han => saw_han = true,
            else => {},
        }
    }
    if (saw_han) return .zhs;
    return .dflt;
}

const DecodedCodepoint = struct {
    codepoint: u21,
    next: usize,
};

fn decodeCodepointAt(text: []const u8, cursor: usize) ?DecodedCodepoint {
    if (cursor >= text.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch return null;
    const end = cursor + @as(usize, len);
    if (end > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[cursor..end]) catch return null;
    return .{ .codepoint = codepoint, .next = end };
}

pub fn tag(comptime bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn scriptForCodepoint(codepoint: u21) Script {
    if ((codepoint >= 'A' and codepoint <= 'Z') or (codepoint >= 'a' and codepoint <= 'z')) return .latin;
    if (isLatinScriptCodepoint(codepoint)) return .latin;
    if (isCopticScriptCodepoint(codepoint)) return .coptic;
    if (isGreekScriptCodepoint(codepoint)) return .greek;
    if (isCyrillicScriptCodepoint(codepoint)) return .cyrillic;
    if (isGlagoliticScriptCodepoint(codepoint)) return .glagolitic;
    if (isOldItalicScriptCodepoint(codepoint)) return .old_italic;
    if (isAvestanScriptCodepoint(codepoint)) return .avestan;
    if (codepoint >= 0x0300 and codepoint <= 0x036f) return .inherited;
    if (isHebrewScriptCodepoint(codepoint)) return .hebrew;
    if (isPhoenicianScriptCodepoint(codepoint)) return .phoenician;
    if (isSyriacScriptCodepoint(codepoint)) return .syriac;
    if (isMandaicScriptCodepoint(codepoint)) return .mandaic;
    if (isArmenianScriptCodepoint(codepoint)) return .armenian;
    if (isArabicScriptCodepoint(codepoint)) return .arabic;
    if (isThaiScriptCodepoint(codepoint)) return .thai;
    if (isLaoScriptCodepoint(codepoint)) return .lao;
    if (isKhmerScriptCodepoint(codepoint)) return .khmer;
    if (isMyanmarScriptCodepoint(codepoint)) return .myanmar;
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .devanagari;
    if (isBengaliScriptCodepoint(codepoint)) return .bengali;
    if (isOdiaScriptCodepoint(codepoint)) return .odia;
    if (isGurmukhiScriptCodepoint(codepoint)) return .gurmukhi;
    if (isGujaratiScriptCodepoint(codepoint)) return .gujarati;
    if (isTeluguScriptCodepoint(codepoint)) return .telugu;
    if (isKannadaScriptCodepoint(codepoint)) return .kannada;
    if (isSinhalaScriptCodepoint(codepoint)) return .sinhala;
    if (isTamilScriptCodepoint(codepoint)) return .tamil;
    if (isMalayalamScriptCodepoint(codepoint)) return .malayalam;
    if (isEthiopicScriptCodepoint(codepoint)) return .ethiopic;
    if (isGeorgianScriptCodepoint(codepoint)) return .georgian;
    if (isCherokeeScriptCodepoint(codepoint)) return .cherokee;
    if (isTifinaghScriptCodepoint(codepoint)) return .tifinagh;
    if (isTibetanScriptCodepoint(codepoint)) return .tibetan;
    if (isThaanaScriptCodepoint(codepoint)) return .thaana;
    if (isNkoScriptCodepoint(codepoint)) return .nko;
    if (isAdlamScriptCodepoint(codepoint)) return .adlam;
    if (isMongolianScriptCodepoint(codepoint)) return .mongolian;
    if (isBalineseScriptCodepoint(codepoint)) return .balinese;
    if (isJavaneseScriptCodepoint(codepoint)) return .javanese;
    if (isLimbuScriptCodepoint(codepoint)) return .limbu;
    if (isLepchaScriptCodepoint(codepoint)) return .lepcha;
    if (isBugineseScriptCodepoint(codepoint)) return .buginese;
    if (isSundaneseScriptCodepoint(codepoint)) return .sundanese;
    if (isMeeteiMayekScriptCodepoint(codepoint)) return .meetei_mayek;
    if (isCanadianAboriginalScriptCodepoint(codepoint)) return .canadian_aboriginal;
    if (isChamScriptCodepoint(codepoint)) return .cham;
    if (isBrahmiScriptCodepoint(codepoint)) return .brahmi;
    if (isNushuScriptCodepoint(codepoint)) return .nushu;
    if (isRunicScriptCodepoint(codepoint)) return .runic;
    if (isOghamScriptCodepoint(codepoint)) return .ogham;
    if (codepoint >= 0x3040 and codepoint <= 0x309f) return .hiragana;
    if (codepoint >= 0x30a0 and codepoint <= 0x30ff) return .katakana;
    // Katakana is also encoded in phonetic-extension and halfwidth forms.
    // These are real script letters used by Japanese fonts; classifying them
    // as unknown would split shaping runs and bypass `kana` OpenType lookups.
    if (codepoint >= 0x31f0 and codepoint <= 0x31ff) return .katakana;
    if (codepoint >= 0xff66 and codepoint <= 0xff9d) return .katakana;
    if (codepoint == 0xff9e or codepoint == 0xff9f) return .inherited;
    // Modern and archaic Hangul Jamo must select the Hangul shaping script even
    // before they are composed into precomposed syllables. Grapheme clustering
    // already treats these ranges as Hangul L/V/T components; keeping script
    // classification in sync ensures conjoining-jamo text reaches `hang`
    // OpenType lookups instead of falling into DFLT/unknown runs.
    if (codepoint >= 0x1100 and codepoint <= 0x11ff) return .hangul;
    if (codepoint >= 0x3130 and codepoint <= 0x318f) return .hangul;
    if (codepoint >= 0xa960 and codepoint <= 0xa97f) return .hangul;
    if (codepoint >= 0xac00 and codepoint <= 0xd7af) return .hangul;
    if (codepoint >= 0xd7b0 and codepoint <= 0xd7ff) return .hangul;
    if (codepoint >= 0x3400 and codepoint <= 0x4dbf) return .han;
    if (codepoint >= 0x4e00 and codepoint <= 0x9fff) return .han;
    if (codepoint >= 0xf900 and codepoint <= 0xfaff) return .han;
    if (codepoint >= 0x20000 and codepoint <= 0x2fffd) return .han;
    if (codepoint >= 0x30000 and codepoint <= 0x3fffd) return .han;
    if (isYiScriptCodepoint(codepoint)) return .yi;
    if (isLisuScriptCodepoint(codepoint)) return .lisu;
    if (isVaiScriptCodepoint(codepoint)) return .vai;
    if (isCommonCodepoint(codepoint)) return .common;
    return .unknown;
}

fn isVaiScriptCodepoint(codepoint: u21) bool {
    // Vai fonts use the `vai ` OpenType ScriptList entry for the syllabary,
    // digits, lengthener, and script punctuation in the A500 block. Keeping the
    // whole block in one run prevents Vai words from falling back to DFLT when
    // they contain native digits or punctuation adjacent to syllables.
    return codepoint >= 0xa500 and codepoint <= 0xa63f;
}

fn isVaiWordCodepoint(codepoint: u21) bool {
    // U+A60D..U+A60F are Vai punctuation. Syllables, the syllable lengthener,
    // supplementary syllables, and native digits should group into normal
    // space-delimited words instead of becoming one segment per codepoint.
    return (codepoint >= 0xa500 and codepoint <= 0xa60c) or
        (codepoint >= 0xa610 and codepoint <= 0xa62b);
}

fn isLisuScriptCodepoint(codepoint: u21) bool {
    // Lisu fonts select the `lisu` OpenType ScriptList entry for the Fraser
    // alphabet, tone letters, script punctuation, and the supplementary letter
    // YHA. Keeping the base block and supplement together avoids splitting
    // older or dialectal Lisu text through DFLT/unknown shaping runs.
    return (codepoint >= 0xa4d0 and codepoint <= 0xa4ff) or
        codepoint == 0x11fb0;
}

fn isLisuWordCodepoint(codepoint: u21) bool {
    // U+A4FE/U+A4FF are Lisu punctuation, not word letters. The rest of the
    // base block plus U+11FB0 should group into normal space-delimited words.
    return (codepoint >= 0xa4d0 and codepoint <= 0xa4fd) or
        codepoint == 0x11fb0;
}

fn isYiScriptCodepoint(codepoint: u21) bool {
    // Yi fonts use a dedicated OpenType ScriptList entry (`yi  `) for the
    // syllabary and radicals. Keeping both adjacent blocks in one shaping run
    // prevents Nuosu/Yi text from falling through DFLT and also lets line
    // breaking treat Yi syllables like the East Asian ideographic units they
    // are in UAX #14.
    return (codepoint >= 0xa000 and codepoint <= 0xa48f) or
        (codepoint >= 0xa490 and codepoint <= 0xa4cf);
}

fn isBalineseScriptCodepoint(codepoint: u21) bool {
    // Balinese OpenType fonts expose script-specific substitutions and mark
    // positioning under the `bali` ScriptList entry. Keep the complete block in
    // one script run so aksara bases, dependent vowels, adeg-adeg, digits, and
    // Balinese punctuation do not get split through DFLT/unknown before layout.
    return codepoint >= 0x1b00 and codepoint <= 0x1b7f;
}

fn isJavaneseScriptCodepoint(codepoint: u21) bool {
    // Javanese uses script-specific OpenType shaping (`java`) for dependent
    // vowels, final consonant signs, and U+A9C0 PANGKON. Keeping the whole
    // block together avoids splitting aksara syllables through DFLT/unknown
    // runs before GSUB/GPOS lookup selection.
    return codepoint >= 0xa980 and codepoint <= 0xa9df;
}

fn isLimbuScriptCodepoint(codepoint: u21) bool {
    // Limbu has dependent vowel signs, subjoined letters, final consonant
    // signs, and native digits in one compact block. Fonts can expose these
    // under the `limb` ScriptList entry, so keep the block in one run instead
    // of routing combining pieces through DFLT/unknown before layout.
    return codepoint >= 0x1900 and codepoint <= 0x194f;
}

fn isLepchaScriptCodepoint(codepoint: u21) bool {
    // Lepcha letters, subjoined letters, vowel/consonant signs, digits, and
    // native punctuation select the `lepc` OpenType ScriptList entry. Keep only
    // assigned scalars in the shaping run so the reserved gaps in the block do
    // not silently inherit Lepcha script or LTR bidi behavior.
    return (codepoint >= 0x1c00 and codepoint <= 0x1c37) or
        (codepoint >= 0x1c3b and codepoint <= 0x1c49) or
        (codepoint >= 0x1c4d and codepoint <= 0x1c4f);
}

fn isLepchaWordCodepoint(codepoint: u21) bool {
    // Anchor word spans on Lepcha base letters and native digits. Dependent
    // vowels, subjoined letters, finals, and nukta attach through the generic
    // extender path, while Lepcha punctuation remains a word separator.
    return (codepoint >= 0x1c00 and codepoint <= 0x1c23) or
        (codepoint >= 0x1c40 and codepoint <= 0x1c49) or
        (codepoint >= 0x1c4d and codepoint <= 0x1c4f);
}

fn isBugineseScriptCodepoint(codepoint: u21) bool {
    // Buginese dependent vowels are split between nonspacing and spacing
    // marks, but fonts select one `bugi` OpenType script system for the whole
    // syllable. Treat the compact block as one shaping script so lontara text
    // is not split through DFLT/unknown before GSUB/GPOS lookup selection.
    return codepoint >= 0x1a00 and codepoint <= 0x1a1f;
}

fn isSundaneseScriptCodepoint(codepoint: u21) bool {
    // Sundanese fonts select script-specific shaping and mark positioning under
    // the `sund` ScriptList entry. The base block carries letters, dependent
    // marks, digits, and punctuation; the supplement extends punctuation used
    // with the same script, so keep both ranges out of DFLT/unknown runs.
    return (codepoint >= 0x1b80 and codepoint <= 0x1bbf) or
        (codepoint >= 0x1cc0 and codepoint <= 0x1ccf);
}

fn isMeeteiMayekScriptCodepoint(codepoint: u21) bool {
    // Meetei Mayek letters are split between the main block and an extensions
    // block that also contains dependent vowel signs. Fonts select the `mtei`
    // ScriptList entry for both, so keep letters, lonsum finals, signs, digits,
    // and punctuation in one shaping run instead of routing marks through DFLT.
    return (codepoint >= 0xaae0 and codepoint <= 0xaaff) or
        (codepoint >= 0xabc0 and codepoint <= 0xabff);
}

fn isCanadianAboriginalScriptCodepoint(codepoint: u21) bool {
    // Unified Canadian Aboriginal Syllabics are encoded across the original
    // block plus Extended/Extended-A additions used by Inuktitut, Cree, Ojibwe,
    // Carrier, and related orthographies. Fonts expose their substitutions and
    // mark positioning under `cans`; keeping all three ranges in one script run
    // avoids falling back to DFLT when a word mixes base and extended syllables.
    return (codepoint >= 0x1400 and codepoint <= 0x167f) or
        (codepoint >= 0x18b0 and codepoint <= 0x18ff) or
        (codepoint >= 0x11ab0 and codepoint <= 0x11abf);
}

fn isChamScriptCodepoint(codepoint: u21) bool {
    // Cham uses dependent vowels and final-consonant signs from the same block
    // as its letters, digits, and punctuation. Fonts select one `cham`
    // ScriptList entry for these pieces, so keep them in a single script run
    // instead of routing marks or finals through DFLT/unknown before shaping.
    return codepoint >= 0xaa00 and codepoint <= 0xaa5f;
}

fn isBrahmiScriptCodepoint(codepoint: u21) bool {
    // Brahmi is an historic Indic script with dependent vowel signs, viramas,
    // digits, and punctuation in one supplementary-plane block. Fonts expose
    // Brahmi-specific shaping through the `brah` ScriptList entry, so keep the
    // block together instead of routing marks or numbers through DFLT/unknown.
    return codepoint >= 0x11000 and codepoint <= 0x1107f;
}

fn isNushuScriptCodepoint(codepoint: u21) bool {
    // Nushu is encoded as a supplementary-plane ideographic script and has a
    // dedicated OpenType ScriptList tag (`nshu`). Classify the entire block as
    // one shaping script so Nushu text selects script-specific font lookups
    // instead of falling through DFLT/unknown primitives.
    return codepoint >= 0x1b170 and codepoint <= 0x1b2ff;
}

fn isRunicScriptCodepoint(codepoint: u21) bool {
    // The Runic block includes letters, word/division punctuation, and numeric
    // symbols that fonts expose through the `runr` ScriptList entry. Keeping
    // the whole block in one LTR shaping run prevents inscriptions that use
    // native separators or Golden Number signs from falling back to DFLT in the
    // middle of otherwise Runic text.
    return codepoint >= 0x16a0 and codepoint <= 0x16ff;
}

fn isRunicWordCodepoint(codepoint: u21) bool {
    // U+16EB..U+16ED are Runic word/division punctuation. Letters and Runic
    // numeric symbols should group into normal word spans, while those
    // separators deliberately break words just like spaces or punctuation.
    return (codepoint >= 0x16a0 and codepoint <= 0x16ea) or
        (codepoint >= 0x16ee and codepoint <= 0x16f8);
}

fn isCopticScriptCodepoint(codepoint: u21) bool {
    // Coptic is encoded partly as Coptic letters in the Greek block, partly in
    // the dedicated Coptic block, and partly as Coptic Epact Numbers in the
    // supplementary plane. Check this before Greek so fonts can select their
    // `copt` ScriptList entry instead of shaping U+03E2..U+03EF as Greek.
    return (codepoint >= 0x03e2 and codepoint <= 0x03ef) or
        (codepoint >= 0x2c80 and codepoint <= 0x2cff) or
        (codepoint >= 0x102e0 and codepoint <= 0x102ff);
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

fn isOghamScriptCodepoint(codepoint: u21) bool {
    // Ogham fonts use the historical `ogam` OpenType script tag for the block's
    // letters, native space mark, and feather punctuation. Keep those assigned
    // scalars in one shaping run while leaving the unassigned tail as unknown.
    return codepoint >= 0x1680 and codepoint <= 0x169c;
}

fn isOghamWordCodepoint(codepoint: u21) bool {
    // U+1680 OGHAM SPACE MARK and U+169B/U+169C feather marks are separators,
    // not word letters. The twenty-five letter names form normal unspaced word
    // spans for caret movement and selection.
    return codepoint >= 0x1681 and codepoint <= 0x169a;
}

fn isPhoenicianScriptCodepoint(codepoint: u21) bool {
    // Phoenician is an historic right-to-left script with a registered OpenType
    // script tag (`phnx`). Keep the assigned letters, native number signs, and
    // word separator in one script run so inscriptions do not fall back to
    // DFLT/neutral shaping between letters and native punctuation. The
    // unassigned U+1091C..U+1091E gap remains unknown on purpose.
    return (codepoint >= 0x10900 and codepoint <= 0x1091b) or
        codepoint == 0x1091f;
}

fn isPhoenicianWordCodepoint(codepoint: u21) bool {
    // Phoenician number signs are strong RTL script characters and should group
    // with adjacent letters for coarse word/caret primitives. U+1091F is a
    // word separator, so it stays in the script run but deliberately breaks the
    // selectable word span.
    return codepoint >= 0x10900 and codepoint <= 0x1091b;
}

fn isMongolianScriptCodepoint(codepoint: u21) bool {
    // Mongolian fonts expose positional shaping and variation forms under the
    // `mong` ScriptList entry. The block includes letters, Todo/Sibe/Manchu
    // additions, punctuation, digits, and free variation selectors; keeping the
    // assigned block together avoids splitting valid vertical-script words
    // through DFLT/unknown before GSUB/GPOS lookup selection.
    return codepoint >= 0x1800 and codepoint <= 0x18af;
}

fn isNkoScriptCodepoint(codepoint: u21) bool {
    // N'Ko is an RTL script with its own OpenType ScriptList tag (`nko `).
    // Its combining marks and digits live in the same block as letters; keeping
    // the block in one script run avoids routing valid syllables through DFLT
    // and preserves RTL direction for shaping/layout primitives.
    return codepoint >= 0x07c0 and codepoint <= 0x07ff;
}

fn isAdlamScriptCodepoint(codepoint: u21) bool {
    // Adlam is a right-to-left script for Fulani with dedicated OpenType
    // shaping under `adlm`. Keep the assigned letters, combining marks,
    // modifier mark, digits, and script punctuation in one RTL run so Adlam
    // text does not fall through DFLT or neutral bidi handling between bases,
    // marks, and native digits.
    return (codepoint >= 0x1e900 and codepoint <= 0x1e94b) or
        (codepoint >= 0x1e950 and codepoint <= 0x1e959) or
        (codepoint >= 0x1e95e and codepoint <= 0x1e95f);
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

fn isThaanaScriptCodepoint(codepoint: u21) bool {
    // Thaana is an RTL abugida used for Dhivehi. Its base letters and fili
    // vowel signs must select the `thaa` OpenType ScriptList entry together;
    // otherwise vowel-mark positioning falls back to DFLT or gets split from
    // the surrounding right-to-left shaping run.
    return codepoint >= 0x0780 and codepoint <= 0x07b1;
}

fn isThaanaWordCodepoint(codepoint: u21) bool {
    // Keep words anchored on Thaana letters. Fili marks attach through the
    // generic word-extender path so a stray leading mark does not become a word
    // by itself, but normal letter+mark syllables remain one selectable token.
    return (codepoint >= 0x0780 and codepoint <= 0x07a5) or
        codepoint == 0x07b1;
}

fn isThaiScriptCodepoint(codepoint: u21) bool {
    // Thai bases, dependent vowels, tone marks, digits, and punctuation select
    // the `thai` OpenType script system. Treat the whole assigned block as one
    // shaping script so marks and bases are not split through DFLT runs before
    // GSUB/GPOS lookup selection.
    return codepoint >= 0x0e01 and codepoint <= 0x0e5b;
}

fn isLaoScriptCodepoint(codepoint: u21) bool {
    // Lao is encoded analogously to Thai and uses its own `lao ` OpenType
    // ScriptList entry. Keeping letters, dependent signs, digits, and Lao
    // punctuation in one run avoids losing script-specific shaping lookups.
    return codepoint >= 0x0e81 and codepoint <= 0x0edf;
}

fn isKhmerScriptCodepoint(codepoint: u21) bool {
    // Khmer shaping depends on `khmr` ScriptList selection for COENG subscript
    // forms and dependent-vowel positioning. The base block also contains
    // script punctuation and digits, while Khmer Symbols carries lunar-date
    // signs that fonts commonly cover with the same Khmer face; keep both
    // ranges in one script run so punctuation/symbols do not force DFLT in the
    // middle of Khmer text.
    return (codepoint >= 0x1780 and codepoint <= 0x17ff) or
        (codepoint >= 0x19e0 and codepoint <= 0x19ff);
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

fn isMyanmarScriptCodepoint(codepoint: u21) bool {
    // Myanmar shaping depends on the modern `mym2` OpenType script system for
    // kinzi, medials, stacked consonants, and dependent vowel/tone placement.
    // Keep the base block and Myanmar Extended-A/B/C additions in one script
    // run so Burmese, Mon, Shan, Karen, Tai Laing, Khamti, Aiton, and related
    // text does not fall through DFLT between bases, signs, or native digits.
    return (codepoint >= 0x1000 and codepoint <= 0x109f) or
        (codepoint >= 0xa9e0 and codepoint <= 0xa9fe) or
        (codepoint >= 0xaa60 and codepoint <= 0xaa7f) or
        (codepoint >= 0x116d0 and codepoint <= 0x116e3);
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

fn isSyriacScriptCodepoint(codepoint: u21) bool {
    // Syriac is a right-to-left cursive script with script-specific OpenType
    // shaping. Its base letters, combining marks, abbreviations, and
    // supplementary letters all need to stay in one `syrc` shaping run rather
    // than being treated as DFLT/neutral text between Arabic/Hebrew support.
    return (codepoint >= 0x0700 and codepoint <= 0x074f) or
        (codepoint >= 0x0860 and codepoint <= 0x086f);
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

fn isMandaicScriptCodepoint(codepoint: u21) bool {
    // Mandaic is an RTL cursive script with script-specific OpenType shaping
    // under `mand`. Only assigned scalars in U+0840..U+085E should enter the
    // shaping run: the unassigned gap at U+085C/U+085D must remain unknown so
    // malformed/private data does not silently inherit Mandaic bidi behavior.
    return (codepoint >= 0x0840 and codepoint <= 0x085b) or
        codepoint == 0x085e;
}

fn isMandaicWordCodepoint(codepoint: u21) bool {
    // Mandaic words are anchored by letters. Combining marks attach through the
    // generic word-extender path, while U+085E punctuation remains a separator
    // even though it stays in the Mandaic script run for shaping and bidi.
    return codepoint >= 0x0840 and codepoint <= 0x0858;
}

fn isGeorgianScriptCodepoint(codepoint: u21) bool {
    // Georgian has casing split across Mkhedruli, Mtavruli, Nuskhuri, and
    // historic Asomtavruli blocks. Fonts expose substitutions and positioning
    // under the `geor` ScriptList entry, so all Georgian letters must remain in
    // one shaping run instead of falling back to DFLT/unknown.
    return (codepoint >= 0x10a0 and codepoint <= 0x10ff) or
        (codepoint >= 0x1c90 and codepoint <= 0x1cbf) or
        (codepoint >= 0x2d00 and codepoint <= 0x2d2f);
}

fn isCherokeeScriptCodepoint(codepoint: u21) bool {
    // Cherokee has bicameral letters split between the main block and the
    // Cherokee Supplement. Fonts expose script-specific substitutions and
    // positioning through the `cher` ScriptList entry, so upper/lowercase text
    // must remain in one shaping run instead of being routed through DFLT.
    return (codepoint >= 0x13a0 and codepoint <= 0x13ff) or
        (codepoint >= 0xab70 and codepoint <= 0xabbf);
}

fn isTifinaghScriptCodepoint(codepoint: u21) bool {
    // Tifinagh uses a dedicated OpenType ScriptList entry (`tfng`) for Amazigh
    // letters, the labialization modifier, native separator, and consonant
    // joiner. Keep the assigned scalars precise rather than treating the
    // unassigned gaps as script text, so fallback and bidi logic do not assign
    // Tifinagh behavior to malformed/private data in the block.
    return (codepoint >= 0x2d30 and codepoint <= 0x2d67) or
        codepoint == 0x2d6f or
        codepoint == 0x2d70 or
        codepoint == 0x2d7f;
}

fn isTifinaghWordCodepoint(codepoint: u21) bool {
    // Tifinagh words are anchored by letters plus U+2D6F labialization mark.
    // U+2D70 is punctuation and U+2D7F attaches through isWordExtender(), so
    // neither should start a selectable word on its own.
    return (codepoint >= 0x2d30 and codepoint <= 0x2d67) or
        codepoint == 0x2d6f;
}

fn isTibetanScriptCodepoint(codepoint: u21) bool {
    // Tibetan stacks rely on script-specific OpenType shaping (`tibt`) for
    // subjoined consonants, vowel signs, and marks. Keep the full Tibetan
    // block in one LTR script run so those syllables do not fall through DFLT
    // lookup selection before shaping.
    return codepoint >= 0x0f00 and codepoint <= 0x0fff;
}

fn isEthiopicScriptCodepoint(codepoint: u21) bool {
    // Ethiopic has no complex OpenType shaper, but fonts still commonly put
    // language and punctuation-sensitive substitutions/positioning under the
    // `ethi` ScriptList entry. Keep the base block, supplement, extended, and
    // extended-A letters/numerals in one LTR script run instead of routing them
    // through DFLT/unknown.
    return (codepoint >= 0x1200 and codepoint <= 0x139f) or
        (codepoint >= 0x2d80 and codepoint <= 0x2ddf) or
        (codepoint >= 0xab00 and codepoint <= 0xab2f);
}

fn isBengaliScriptCodepoint(codepoint: u21) bool {
    // Bengali/Assamese letters, dependent signs, digits, and punctuation select
    // the modern `bng2` OpenType script system. Cangjie already treats Bengali
    // split vowels as grapheme continuations; classifying the full assigned
    // block as Bengali keeps those syllables in the same shaping run instead
    // of routing them through DFLT/unknown.
    return codepoint >= 0x0980 and codepoint <= 0x09ff;
}

fn isGurmukhiScriptCodepoint(codepoint: u21) bool {
    // Gurmukhi text uses the Indic v2 OpenType shaping system (`gur2`). Keep
    // letters, dependent signs, digits, and script punctuation in one run so
    // Punjabi/Sikh-script syllables do not fall back to DFLT between bases,
    // vowel signs, virama forms, and nasalization marks.
    return codepoint >= 0x0a00 and codepoint <= 0x0a7f;
}

fn isGujaratiScriptCodepoint(codepoint: u21) bool {
    // Gujarati uses the Indic v2 shaping model under `gjr2`. Keep the complete
    // block together for script runs so dependent signs, digits, avagraha/OM,
    // and modern combining additions select the same GSUB/GPOS ScriptList as
    // their base consonants instead of falling through DFLT/unknown.
    return codepoint >= 0x0a80 and codepoint <= 0x0aff;
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

fn isOdiaScriptCodepoint(codepoint: u21) bool {
    // Odia/Oriya uses the Indic v2 OpenType shaping system (`ory2`). Its
    // letters, dependent signs, nukta, virama, digits, and script punctuation
    // occupy one Unicode block; keeping that block in one script run lets
    // fonts select Odia-specific GSUB/GPOS features for aksharas instead of
    // routing marks and consonants through DFLT/unknown.
    return codepoint >= 0x0b00 and codepoint <= 0x0b7f;
}

fn isTeluguScriptCodepoint(codepoint: u21) bool {
    // Telugu uses the Indic v2 OpenType shaping system (`tel2`). The block
    // contains independent letters, dependent vowel signs, virama, digits, and
    // length marks; treating the whole block as Telugu keeps aksharas in one
    // shaping run instead of routing marks through DFLT/unknown.
    return codepoint >= 0x0c00 and codepoint <= 0x0c7f;
}

fn isKannadaScriptCodepoint(codepoint: u21) bool {
    // Kannada has the same Indic v2 shaping requirements under `knd2`. Keeping
    // consonants, dependent signs, virama forms, digits, and script-specific
    // additions together avoids splitting Kannada syllables before GSUB/GPOS
    // feature selection.
    return codepoint >= 0x0c80 and codepoint <= 0x0cff;
}

fn isSinhalaScriptCodepoint(codepoint: u21) bool {
    // Sinhala vowels, consonants, dependent signs, punctuation, and numerals
    // live in one Unicode block and are shaped through the `sinh` OpenType
    // script system. Keeping the full block together prevents valid aksharas
    // from being split through DFLT/unknown runs before GSUB/GPOS selection.
    return codepoint >= 0x0d80 and codepoint <= 0x0dff;
}

fn isTamilScriptCodepoint(codepoint: u21) bool {
    // Tamil shaping depends on keeping consonants, dependent vowels, virama,
    // numerals, and historic additions in one `taml` script run. Unicode's
    // Tamil block has unassigned holes, but treating the assigned range as the
    // script is a safer primitive than splitting common Tamil syllables through
    // DFLT/unknown before OpenType lookup selection.
    return (codepoint >= 0x0b82 and codepoint <= 0x0bfa) or
        (codepoint >= 0x11fc0 and codepoint <= 0x11fff);
}

fn isMalayalamScriptCodepoint(codepoint: u21) bool {
    // Malayalam uses the Indic v2 OpenType shaping system (`mlm2`) for
    // reordering and conjunct formation. The base block contains letters,
    // dependent vowels, virama, chillus, digits, and script punctuation; keeping
    // it together avoids sending common Malayalam syllables through DFLT or
    // splitting marks into separate shaping runs.
    return codepoint >= 0x0d00 and codepoint <= 0x0d7f;
}

fn isArabicScriptCodepoint(codepoint: u21) bool {
    // Arabic Presentation Forms are compatibility encodings, but Unicode still
    // assigns them Script=Arabic. Legacy text and normalized-later input should
    // remain in Arabic RTL shaping runs so fonts can select `arab` features
    // instead of falling back to DFLT/neutral handling.
    return (codepoint >= 0x0600 and codepoint <= 0x06ff) or
        (codepoint >= 0x0750 and codepoint <= 0x077f) or
        (codepoint >= 0x0870 and codepoint <= 0x089f) or
        (codepoint >= 0x08a0 and codepoint <= 0x08ff) or
        (codepoint >= 0xfb50 and codepoint <= 0xfdff) or
        (codepoint >= 0xfe70 and codepoint <= 0xfeff);
}

fn isLatinScriptCodepoint(codepoint: u21) bool {
    // Keep all encoded Latin extension blocks in the Latin shaping script.
    // Precomposed Vietnamese, phonetic, and medievalist letters are alphabetic
    // bases, not inherited combining marks; splitting them into DFLT/unknown
    // runs prevents fonts from selecting their `latn` GSUB/GPOS features.
    return (codepoint >= 0x00c0 and codepoint <= 0x024f) or
        (codepoint >= 0x1d00 and codepoint <= 0x1d7f) or
        (codepoint >= 0x1d80 and codepoint <= 0x1dbf) or
        (codepoint >= 0x1e00 and codepoint <= 0x1eff) or
        (codepoint >= 0x2c60 and codepoint <= 0x2c7f) or
        (codepoint >= 0xa720 and codepoint <= 0xa7ff) or
        (codepoint >= 0xab30 and codepoint <= 0xab6f) or
        (codepoint >= 0x1df00 and codepoint <= 0x1dfff);
}

fn isGreekScriptCodepoint(codepoint: u21) bool {
    // Greek letters commonly rely on `grek` OpenType lookup selection for
    // mark positioning and localized alternates. Keep the full encoded Greek
    // script repertoire in one shaping script, including Coptic-era additions
    // and ancient Greek notation blocks whose Script property is Greek.
    return (codepoint >= 0x0370 and codepoint <= 0x03ff) or
        (codepoint >= 0x1d200 and codepoint <= 0x1d245) or
        (codepoint >= 0x1f00 and codepoint <= 0x1fff) or
        (codepoint >= 0x10140 and codepoint <= 0x1018f);
}

fn isHebrewScriptCodepoint(codepoint: u21) bool {
    // Hebrew presentation forms are compatibility characters, but they still
    // carry Script=Hebrew in Unicode. Treating them as unknown would split
    // Hebrew script runs and classify them as bidi-neutral, which breaks
    // low-level shaping and visual ordering for legacy or normalized-later text.
    return (codepoint >= 0x0590 and codepoint <= 0x05ff) or
        (codepoint >= 0xfb1d and codepoint <= 0xfb4f);
}

fn isArmenianScriptCodepoint(codepoint: u21) bool {
    // Armenian has dedicated OpenType shaping/script selection (`armn`) for
    // localized forms and mark positioning. Keep alphabetic letters,
    // punctuation, ligature codepoints, and modifier letters in one script run;
    // otherwise Armenian text is split through DFLT/unknown and loses script-
    // specific GSUB/GPOS coverage.
    return (codepoint >= 0x0531 and codepoint <= 0x058f) or
        (codepoint >= 0xfb13 and codepoint <= 0xfb17) or
        codepoint == 0x0559 or
        codepoint == 0x055a or
        codepoint == 0x055b or
        codepoint == 0x055c or
        codepoint == 0x055d or
        codepoint == 0x055e or
        codepoint == 0x055f;
}

fn isCyrillicScriptCodepoint(codepoint: u21) bool {
    // Cyrillic has several extension blocks used by living orthographies.
    // Classifying them as unknown would split runs and route GSUB/GPOS through
    // DFLT instead of the font's `cyrl` script system.
    return (codepoint >= 0x0400 and codepoint <= 0x052f) or
        (codepoint >= 0x1c80 and codepoint <= 0x1c8f) or
        (codepoint >= 0x2de0 and codepoint <= 0x2dff) or
        (codepoint >= 0xa640 and codepoint <= 0xa69f) or
        (codepoint >= 0x1e030 and codepoint <= 0x1e08f);
}

fn isGlagoliticScriptCodepoint(codepoint: u21) bool {
    // Glagolitic combines a BMP alphabet block with supplementary combining
    // letters used in historic manuscripts. Fonts expose both through the
    // `glag` ScriptList entry, so keep base letters and combining letters in a
    // single LTR shaping run instead of treating the supplement as unknown
    // combining data between otherwise Glagolitic bases.
    return (codepoint >= 0x2c00 and codepoint <= 0x2c5f) or
        (codepoint >= 0x1e000 and codepoint <= 0x1e02a);
}

fn isGlagoliticWordCodepoint(codepoint: u21) bool {
    // Word spans are anchored on Glagolitic base letters. Supplementary
    // combining letters attach through isWordExtender(), which avoids turning a
    // stray leading combining mark into a selectable word by itself while still
    // preserving marked manuscript abbreviations as one token.
    return codepoint >= 0x2c00 and codepoint <= 0x2c5f;
}

fn isOldItalicScriptCodepoint(codepoint: u21) bool {
    // Old Italic is a supplementary-plane historic script with a registered
    // OpenType ScriptList tag (`ital`). The Unicode block has unassigned gaps,
    // so classify only assigned letters and native numerals; treating the whole
    // block as script text would give private/malformed data LTR/script shaping
    // semantics it should not inherit.
    return (codepoint >= 0x10300 and codepoint <= 0x10323) or
        (codepoint >= 0x1032d and codepoint <= 0x1032f);
}

fn isOldItalicWordCodepoint(codepoint: u21) bool {
    // Native Old Italic numerals share the same strong LTR script behavior as
    // letters in Unicode. Group them with adjacent letters for coarse word and
    // caret primitives, while leaving the unassigned block gaps as separators.
    return isOldItalicScriptCodepoint(codepoint);
}

fn isAvestanScriptCodepoint(codepoint: u21) bool {
    // Avestan is an RTL historic script with its own OpenType ScriptList tag
    // (`avst`). Include its native punctuation in the script run so separators
    // do not force a neutral/DFLT shaping island between adjacent letters,
    // while preserving the unassigned U+10B36..U+10B38 gap as unknown.
    return (codepoint >= 0x10b00 and codepoint <= 0x10b35) or
        (codepoint >= 0x10b39 and codepoint <= 0x10b3f);
}

fn isAvestanWordCodepoint(codepoint: u21) bool {
    // U+10B39..U+10B3F are Avestan separators and abbreviation punctuation,
    // not word letters. Keep only the encoded letters in selectable word
    // spans; the punctuation still remains in the surrounding RTL script run.
    return codepoint >= 0x10b00 and codepoint <= 0x10b35;
}

/// Classify only strong LTR/RTL scripts and neutral punctuation/spacing. The
/// higher-level bidi functions use this coarse class to build visual runs.
pub fn bidiClassForCodepoint(codepoint: u21) BidiClass {
    if (isBidiNumberCodepoint(codepoint)) return .number;
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .arabic, .hebrew, .phoenician, .syriac, .mandaic, .nko, .thaana, .adlam, .avestan => .rtl,
        .latin, .greek, .cyrillic, .glagolitic, .old_italic, .han, .yi, .lisu, .vai, .hiragana, .katakana, .hangul, .armenian, .thai, .lao, .khmer, .myanmar, .devanagari, .bengali, .odia, .gurmukhi, .gujarati, .telugu, .kannada, .sinhala, .tamil, .malayalam, .ethiopic, .georgian, .cherokee, .tifinagh, .tibetan, .mongolian, .balinese, .javanese, .limbu, .lepcha, .buginese, .sundanese, .meetei_mayek, .canadian_aboriginal, .cham, .brahmi, .nushu, .runic, .coptic, .ogham => .ltr,
        else => .neutral,
    };
}

pub fn itemizeBidiRuns(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]BidiRun {
    var runs = std.ArrayList(BidiRun).empty;
    errdefer runs.deinit(allocator);

    var current_direction: ?BidiClass = null;
    var run_start: usize = 0;
    var run_end: usize = 0;
    var neutral_start: ?usize = null;
    var neutral_end: usize = 0;

    // Neutral spans are attached to the surrounding run when possible. If text
    // starts with neutrals, use the paragraph base direction as their run.
    var cursor: usize = 0;
    while (cursor < text.len) {
        const cluster = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const next_index = decoded.next;
        cursor = next_index;
        const bidi_class = bidiClassForCodepoint(codepoint);
        if (bidi_class == .neutral) {
            if (neutral_start == null) neutral_start = cluster;
            neutral_end = next_index;
            if (current_direction == null) {
                current_direction = baseDirectionOrLtr(base_direction);
                run_start = cluster;
            }
            run_end = next_index;
            continue;
        }

        if (current_direction == null) {
            current_direction = bidi_class;
            run_start = neutral_start orelse cluster;
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        if (current_direction.? == bidi_class) {
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        if (current_direction.? == .rtl and bidi_class == .number) {
            const split_at = neutral_start orelse cluster;
            try runs.append(allocator, .{
                .direction = current_direction.?,
                .byte_start = run_start,
                .byte_len = split_at - run_start,
            });
            current_direction = .number;
            run_start = neutral_start orelse cluster;
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        if (current_direction.? == .number and bidi_class == .rtl) {
            const split_at = neutral_start orelse cluster;
            try runs.append(allocator, .{
                .direction = current_direction.?,
                .byte_start = run_start,
                .byte_len = split_at - run_start,
            });
            current_direction = .rtl;
            run_start = neutral_start orelse cluster;
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        const split_at = neutral_start orelse cluster;
        try runs.append(allocator, .{
            .direction = current_direction.?,
            .byte_start = run_start,
            .byte_len = split_at - run_start,
        });
        current_direction = bidi_class;
        run_start = neutral_start orelse cluster;
        run_end = next_index;
        neutral_start = null;
    }

    if (current_direction) |direction| {
        try runs.append(allocator, .{
            .direction = direction,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
    }
    return try runs.toOwnedSlice(allocator);
}

pub fn visualOrderBidiRuns(allocator: std.mem.Allocator, runs: []const BidiRun, base_direction: BidiClass) ![]usize {
    // This is a deliberately small bidi reordering model: paragraph RTL reverses
    // run order; individual RTL runs are reversed when materialized.
    const order = try allocator.alloc(usize, runs.len);
    if (baseDirectionOrLtr(base_direction) == .rtl) {
        for (order, 0..) |*slot, index| {
            slot.* = runs.len - 1 - index;
        }
    } else {
        for (order, 0..) |*slot, index| {
            slot.* = index;
        }
    }
    return order;
}

pub fn visualOrderCodepoints(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]u21 {
    const runs = try itemizeBidiRuns(allocator, text, base_direction);
    defer allocator.free(runs);
    const order = try visualOrderBidiRuns(allocator, runs, base_direction);
    defer allocator.free(order);

    var output = std.ArrayList(u21).empty;
    errdefer output.deinit(allocator);
    for (order) |run_index| {
        const run = runs[run_index];
        const slice = text[run.byte_start .. run.byte_start + run.byte_len];
        if (run.direction == .rtl) {
            try appendRtlCodepointsByGrapheme(allocator, &output, slice);
        } else {
            try appendCodepoints(allocator, &output, slice);
        }
    }
    return try output.toOwnedSlice(allocator);
}

pub fn visualOrderUtf8(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]u8 {
    const codepoints = try visualOrderCodepoints(allocator, text, base_direction);
    defer allocator.free(codepoints);
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    for (codepoints) |codepoint| {
        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buffer) catch continue;
        try output.appendSlice(allocator, buffer[0..len]);
    }
    return try output.toOwnedSlice(allocator);
}

pub fn buildBidiMap(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) !BidiMap {
    // The map keeps both visual order and logical-to-visual lookup, which lets
    // editor code move between byte offsets and rendered caret positions.
    const logical = try collectLogicalBidiItems(allocator, text);
    defer allocator.free(logical);
    const runs = try itemizeBidiRuns(allocator, text, base_direction);
    defer allocator.free(runs);
    const order = try visualOrderBidiRuns(allocator, runs, base_direction);
    defer allocator.free(order);

    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    const logical_to_visual = try allocator.alloc(usize, logical.len);
    errdefer allocator.free(logical_to_visual);

    for (order) |run_index| {
        const run = runs[run_index];
        const range = logicalRangeForBytes(logical, run.byte_start, run.byte_start + run.byte_len);
        if (run.direction == .rtl) {
            try appendRtlVisualBidiItemsByGrapheme(allocator, &items, logical_to_visual, logical, text, run, range);
        } else {
            var index = range.start;
            while (index < range.end) : (index += 1) {
                try appendVisualBidiItem(allocator, &items, logical_to_visual, logical[index], run.direction);
            }
        }
    }

    return .{
        .allocator = allocator,
        .items = try items.toOwnedSlice(allocator),
        .logical_to_visual = logical_to_visual,
    };
}

pub fn itemizeGraphemeClusters(allocator: std.mem.Allocator, text: []const u8) ![]GraphemeCluster {
    var clusters = std.ArrayList(GraphemeCluster).empty;
    errdefer clusters.deinit(allocator);

    var cursor: usize = 0;
    var cluster_start: ?usize = null;
    var cluster_end: usize = 0;
    var previous_codepoint: ?u21 = null;
    var last_non_extend_codepoint: ?u21 = null;
    var zwj_after_extended_pictographic = false;
    var zwj_after_indic_virama = false;
    var regional_indicator_count: usize = 0;
    // Approximate UAX #29 extended grapheme clusters for the scripts supported
    // here: combining marks, variation selectors, emoji modifiers, emoji ZWJ
    // chains, Indic virama conjuncts, regional-indicator pairs, and Hangul Jamo
    // syllable sequences.
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;

        if (cluster_start == null) {
            cluster_start = byte_start;
            cluster_end = byte_end;
            previous_codepoint = codepoint;
            last_non_extend_codepoint = if (isGraphemeExtendCodepoint(codepoint) or codepoint == 0x200d) null else codepoint;
            zwj_after_extended_pictographic = false;
            zwj_after_indic_virama = false;
            regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
            continue;
        }

        if (extendsGrapheme(previous_codepoint.?, codepoint, regional_indicator_count, zwj_after_extended_pictographic, zwj_after_indic_virama)) {
            cluster_end = byte_end;
            if (codepoint == 0x200d) {
                // GB11 only suppresses the break after ZWJ for emoji ZWJ
                // sequences. A generic "letter + ZWJ + letter" should keep the
                // ZWJ with the previous cluster (GB9) but still break before the
                // following non-emoji letter.
                zwj_after_extended_pictographic = if (last_non_extend_codepoint) |last|
                    isExtendedPictographic(last)
                else
                    false;
                // UAX #29's InCB rule keeps virama+ZWJ Indic conjuncts at a
                // single caret stop. Without this side state, "क्‍ष" splits
                // before the final consonant even though the ZWJ requests a
                // conjunct glyph.
                zwj_after_indic_virama = isIndicViramaForZwjConjunct(previous_codepoint.?);
            } else {
                zwj_after_extended_pictographic = false;
                zwj_after_indic_virama = false;
                if (!isGraphemeExtendCodepoint(codepoint)) {
                    last_non_extend_codepoint = codepoint;
                }
            }
            previous_codepoint = codepoint;
            if (isRegionalIndicator(codepoint)) {
                regional_indicator_count += 1;
            } else if (codepoint != 0x200d) {
                regional_indicator_count = 0;
            }
            continue;
        }

        try clusters.append(allocator, .{
            .byte_start = cluster_start.?,
            .byte_len = cluster_end - cluster_start.?,
        });
        cluster_start = byte_start;
        cluster_end = byte_end;
        previous_codepoint = codepoint;
        last_non_extend_codepoint = if (isGraphemeExtendCodepoint(codepoint) or codepoint == 0x200d) null else codepoint;
        zwj_after_extended_pictographic = false;
        zwj_after_indic_virama = false;
        regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
    }

    if (cluster_start) |start| {
        try clusters.append(allocator, .{
            .byte_start = start,
            .byte_len = cluster_end - start,
        });
    }
    return try clusters.toOwnedSlice(allocator);
}

pub fn itemizeWordSegments(allocator: std.mem.Allocator, text: []const u8) ![]WordSegment {
    var words = std.ArrayList(WordSegment).empty;
    errdefer words.deinit(allocator);

    var current_kind: WordKind = .none;
    var word_start: usize = 0;
    var word_end: usize = 0;
    // Latin-like text forms multi-codepoint words. East Asian scripts are
    // exposed as single-codepoint words because they do not require spaces.
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;
        var kind = wordKindForCodepoint(codepoint);
        if (isAsciiApostrophe(codepoint)) {
            // Keep common contractions such as "don't" as one word without
            // letting leading/trailing quote marks become part of a word span.
            // This intentionally requires a word on the left and an alphanumeric
            // continuation on the right; otherwise the apostrophe behaves like
            // punctuation and closes the current segment.
            const next_kind = if (nextCodepointAt(text, byte_end)) |next_codepoint| wordKindForCodepoint(next_codepoint) else .none;
            kind = if (current_kind == .latin_number and next_kind == .latin_number) .latin_number else .none;
        }
        if (kind == .none) {
            if (isWordExtender(codepoint)) {
                // UAX #29 treats Extend/Format-like codepoints as part of the
                // surrounding word. Preserve their bytes so caret and selection
                // logic does not strand accents, variation selectors, or joiners
                // outside the word segment they visually modify.
                if (current_kind != .none) {
                    word_end = byte_end;
                } else if (words.items.len > 0) {
                    const last = &words.items[words.items.len - 1];
                    const last_end = last.byte_start + last.byte_len;
                    if (last_end == byte_start) last.byte_len = byte_end - last.byte_start;
                }
                continue;
            }
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            continue;
        }
        if (kind == .single) {
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            try words.append(allocator, .{ .byte_start = byte_start, .byte_len = byte_end - byte_start });
            continue;
        }
        if (current_kind == .none) {
            current_kind = kind;
            word_start = byte_start;
            word_end = byte_end;
            continue;
        }
        if (current_kind == kind) {
            word_end = byte_end;
            continue;
        }
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
        current_kind = kind;
        word_start = byte_start;
        word_end = byte_end;
    }

    if (current_kind != .none) {
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
    }
    return try words.toOwnedSlice(allocator);
}

pub fn itemizeSentenceSegments(allocator: std.mem.Allocator, text: []const u8) ![]SentenceSegment {
    var sentences = std.ArrayList(SentenceSegment).empty;
    errdefer sentences.deinit(allocator);

    var sentence_start: usize = 0;
    var sentence_end: usize = 0;
    var pending_break = false;
    var previous_codepoint: ?u21 = null;
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;
        sentence_end = byte_end;

        if (pending_break and !isSentenceTrailingSpace(codepoint) and !isSentenceTrailingClose(codepoint)) {
            try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, byte_start);
            sentence_start = byte_start;
            pending_break = false;
        }

        if (isSentenceTerminator(codepoint) and !isMidNumberSentencePeriod(codepoint, previous_codepoint, text, byte_end)) {
            pending_break = true;
        }
        previous_codepoint = codepoint;
    }

    try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, sentence_end);
    return try sentences.toOwnedSlice(allocator);
}

pub fn itemizeLineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]LineBreak {
    var breaks = std.ArrayList(LineBreak).empty;
    errdefer breaks.deinit(allocator);

    // Emit hard breaks for CR/LF and soft opportunities after whitespace or
    // East Asian grapheme clusters. Break offsets must point to cluster
    // boundaries: otherwise an ideograph followed by a variation selector, or a
    // kana base followed by a combining mark, could be split between the base
    // and its visual modifier.
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    for (clusters, 0..) |cluster, cluster_index| {
        const cluster_end = cluster.byte_start + cluster.byte_len;
        const codepoint = firstCodepoint(text[cluster.byte_start..cluster_end]) orelse continue;
        if (codepoint == '\n' or codepoint == '\r') {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .hard });
        } else if (isLineBreakSpace(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .soft });
        } else if (isLineBreakEastAsian(codepoint) and !nextClusterProhibitsEastAsianBreak(text, clusters, cluster_index)) {
            // East Asian text permits breaks between most ideographic/kana
            // clusters, but not immediately before closing punctuation. Keeping
            // that small UAX #14 invariant here prevents wrapped lines from
            // starting with common CJK closers such as U+3002 IDEOGRAPHIC FULL
            // STOP while preserving the compact line-break model.
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .soft });
        }
    }

    return try breaks.toOwnedSlice(allocator);
}

pub fn itemizeScriptRuns(allocator: std.mem.Allocator, text: []const u8) ![]ScriptRun {
    var runs = std.ArrayList(ScriptRun).empty;
    errdefer runs.deinit(allocator);

    var current_script: ?Script = null;
    var run_start: usize = 0;
    var run_end: usize = 0;
    // Script runs drive OpenType ScriptList selection. Common/inherited
    // codepoints stay with the surrounding run so punctuation does not split a
    // Latin, Arabic, or CJK shaping segment by itself.
    var cursor: usize = 0;
    while (cursor < text.len) {
        const cluster = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const next_index = decoded.next;
        cursor = next_index;
        const script = scriptForCodepoint(codepoint);
        if (current_script == null) {
            current_script = if (script == .common or script == .inherited) .common else script;
            run_start = cluster;
            run_end = next_index;
            continue;
        }
        if (scriptBelongsToRun(script, current_script.?)) {
            if (current_script.? == .common and script != .common and script != .inherited) {
                current_script = script;
            }
            run_end = next_index;
            continue;
        }
        try runs.append(allocator, .{
            .script = current_script.?,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
        current_script = if (script == .common or script == .inherited) .common else script;
        run_start = cluster;
        run_end = next_index;
    }

    if (current_script) |script| {
        try runs.append(allocator, .{
            .script = script,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
    }
    return try runs.toOwnedSlice(allocator);
}

fn baseDirectionOrLtr(direction: BidiClass) BidiClass {
    return if (direction == .rtl) .rtl else .ltr;
}

fn isBidiNumberCodepoint(codepoint: u21) bool {
    // Keep common European and Arabic-Indic decimal sequences in logical LTR
    // order even when the surrounding paragraph/run order is RTL. This is a
    // deliberately compact subset of UAX #9 weak-type handling, but it avoids
    // the most visible failure mode of rendering "12" as "21" in Hebrew/Arabic
    // text while preserving existing neutral punctuation behavior.
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

fn collectLogicalBidiItems(allocator: std.mem.Allocator, text: []const u8) ![]BidiMapItem {
    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
        try items.append(allocator, .{
            .logical_index = items.items.len,
            .visual_index = 0,
            .byte_start = byte_start,
            .byte_len = cursor - byte_start,
            .codepoint = codepoint,
            .visual_codepoint = codepoint,
            .direction = bidiClassForCodepoint(codepoint),
        });
    }
    return try items.toOwnedSlice(allocator);
}

const LogicalRange = struct { start: usize, end: usize };

fn logicalRangeForBytes(logical: []const BidiMapItem, byte_start: usize, byte_end: usize) LogicalRange {
    var start: ?usize = null;
    var end: usize = 0;
    for (logical, 0..) |item, index| {
        const item_end = item.byte_start + item.byte_len;
        if (item_end <= byte_start or item.byte_start >= byte_end) continue;
        if (start == null) start = index;
        end = index + 1;
    }
    return .{ .start = start orelse 0, .end = end };
}

fn appendRtlCodepointsByGrapheme(allocator: std.mem.Allocator, output: *std.ArrayList(u21), text: []const u8) !void {
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    var cluster_index = clusters.len;
    while (cluster_index > 0) {
        cluster_index -= 1;
        const cluster = clusters[cluster_index];
        const start_len = output.items.len;
        try appendCodepoints(allocator, output, text[cluster.byte_start .. cluster.byte_start + cluster.byte_len]);
        for (output.items[start_len..]) |*codepoint| {
            codepoint.* = mirroredCodepoint(codepoint.*);
        }
    }
}

fn appendRtlVisualBidiItemsByGrapheme(allocator: std.mem.Allocator, items: *std.ArrayList(BidiMapItem), logical_to_visual: []usize, logical: []const BidiMapItem, text: []const u8, run: BidiRun, range: LogicalRange) !void {
    const clusters = try itemizeGraphemeClusters(allocator, text[run.byte_start .. run.byte_start + run.byte_len]);
    defer allocator.free(clusters);
    var cluster_index = clusters.len;
    while (cluster_index > 0) {
        cluster_index -= 1;
        const cluster = clusters[cluster_index];
        const cluster_start = run.byte_start + cluster.byte_start;
        const cluster_end = cluster_start + cluster.byte_len;
        const cluster_range = logicalRangeForBytes(logical, cluster_start, cluster_end);
        var index = @max(cluster_range.start, range.start);
        const end = @min(cluster_range.end, range.end);
        while (index < end) : (index += 1) {
            try appendVisualBidiItem(allocator, items, logical_to_visual, logical[index], run.direction);
        }
    }
}

fn appendVisualBidiItem(allocator: std.mem.Allocator, items: *std.ArrayList(BidiMapItem), logical_to_visual: []usize, logical: BidiMapItem, direction: BidiClass) !void {
    const visual_index = items.items.len;
    logical_to_visual[logical.logical_index] = visual_index;
    try items.append(allocator, .{
        .logical_index = logical.logical_index,
        .visual_index = visual_index,
        .byte_start = logical.byte_start,
        .byte_len = logical.byte_len,
        .codepoint = logical.codepoint,
        .visual_codepoint = if (direction == .rtl) mirroredCodepoint(logical.codepoint) else logical.codepoint,
        .direction = direction,
    });
}

fn appendCodepoints(allocator: std.mem.Allocator, output: *std.ArrayList(u21), text: []const u8) !void {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        try output.append(allocator, codepoint);
    }
}

fn firstCodepoint(text: []const u8) ?u21 {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    return it.nextCodepoint();
}

pub fn mirroredCodepoint(codepoint: u21) u21 {
    return switch (codepoint) {
        '(' => ')',
        ')' => '(',
        '[' => ']',
        ']' => '[',
        '{' => '}',
        '}' => '{',
        '<' => '>',
        '>' => '<',
        0x00ab => 0x00bb,
        0x00bb => 0x00ab,
        0x2039 => 0x203a,
        0x203a => 0x2039,
        0x2045 => 0x2046,
        0x2046 => 0x2045,
        0x207d => 0x207e,
        0x207e => 0x207d,
        0x208d => 0x208e,
        0x208e => 0x208d,
        0x2308 => 0x2309,
        0x2309 => 0x2308,
        0x230a => 0x230b,
        0x230b => 0x230a,
        0x2329 => 0x232a,
        0x232a => 0x2329,
        0x2768 => 0x2769,
        0x2769 => 0x2768,
        0x276a => 0x276b,
        0x276b => 0x276a,
        0x276c => 0x276d,
        0x276d => 0x276c,
        0x276e => 0x276f,
        0x276f => 0x276e,
        0x2770 => 0x2771,
        0x2771 => 0x2770,
        0x2772 => 0x2773,
        0x2773 => 0x2772,
        0x2774 => 0x2775,
        0x2775 => 0x2774,
        0x27c5 => 0x27c6,
        0x27c6 => 0x27c5,
        0x27e6 => 0x27e7,
        0x27e7 => 0x27e6,
        0x27e8 => 0x27e9,
        0x27e9 => 0x27e8,
        0x27ea => 0x27eb,
        0x27eb => 0x27ea,
        0x27ec => 0x27ed,
        0x27ed => 0x27ec,
        0x27ee => 0x27ef,
        0x27ef => 0x27ee,
        0x2983 => 0x2984,
        0x2984 => 0x2983,
        0x2985 => 0x2986,
        0x2986 => 0x2985,
        0x2987 => 0x2988,
        0x2988 => 0x2987,
        0x2989 => 0x298a,
        0x298a => 0x2989,
        0x298b => 0x298c,
        0x298c => 0x298b,
        0x298d => 0x2990,
        0x298e => 0x298f,
        0x298f => 0x298e,
        0x2990 => 0x298d,
        0x2991 => 0x2992,
        0x2992 => 0x2991,
        0x2993 => 0x2994,
        0x2994 => 0x2993,
        0x2995 => 0x2996,
        0x2996 => 0x2995,
        0x2997 => 0x2998,
        0x2998 => 0x2997,
        0x29d8 => 0x29d9,
        0x29d9 => 0x29d8,
        0x29da => 0x29db,
        0x29db => 0x29da,
        0x29fc => 0x29fd,
        0x29fd => 0x29fc,
        0x3008 => 0x3009,
        0x3009 => 0x3008,
        0x300a => 0x300b,
        0x300b => 0x300a,
        0x300c => 0x300d,
        0x300d => 0x300c,
        0x300e => 0x300f,
        0x300f => 0x300e,
        else => codepoint,
    };
}

test "Latin extension letters stay in Latin script runs" {
    const allocator = std.testing.allocator;

    const text = "Cafẹ Ạꞵ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.latin, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(scriptForCodepoint(0x1ea0)));
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(scriptForCodepoint(0xa7b5)));
}

test "Greek and Cyrillic letters select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ῼЖ ҄";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(Script.greek, runs[0].script);
    try std.testing.expectEqualStrings("ῼ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(Script.cyrillic, runs[1].script);
    try std.testing.expectEqualStrings("Ж ҄", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(OpenTypeScriptTag.grek, openTypeScriptTag(scriptForCodepoint(0x03a9)));
    try std.testing.expectEqual(OpenTypeScriptTag.grek, openTypeScriptTag(scriptForCodepoint(0x1f88)));
    try std.testing.expectEqual(OpenTypeScriptTag.cyrl, openTypeScriptTag(scriptForCodepoint(0x0416)));
    try std.testing.expectEqual(OpenTypeScriptTag.cyrl, openTypeScriptTag(scriptForCodepoint(0xa66e)));
}

test "Glagolitic text keeps combining letters and selects Glagolitic OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{2c00}\u{1e000}\u{2c30} \u{2c5f}\u{1e02a}!";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.glagolitic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.glag, openTypeScriptTag(scriptForCodepoint(0x2c00)));
    try std.testing.expectEqual(OpenTypeScriptTag.glag, openTypeScriptTag(scriptForCodepoint(0x1e000)));
    try std.testing.expectEqual(OpenTypeScriptTag.glag, openTypeScriptTag(scriptForCodepoint(0x2c5f)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x1e02b));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x2c00));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1e000));

    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("\u{2c00}\u{1e000}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c30}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{2c5f}\u{1e02a}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("!", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{2c00}\u{1e000}\u{2c30}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c5f}\u{1e02a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Old Italic letters and numerals select Old Italic script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10300}\u{10301}\u{10320} \u{1032d}\u{1032e}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.old_italic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.ital, openTypeScriptTag(scriptForCodepoint(0x10300)));
    try std.testing.expectEqual(OpenTypeScriptTag.ital, openTypeScriptTag(scriptForCodepoint(0x10320)));
    try std.testing.expectEqual(OpenTypeScriptTag.ital, openTypeScriptTag(scriptForCodepoint(0x1032f)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x10324));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x10300));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x10320));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10300}\u{10301}\u{10320}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1032d}\u{1032e}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Avestan text selects Avestan RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10b00}\u{10b01}\u{10b39}\u{10b02}\u{10b35}\u{10b3f}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.avestan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.avst, openTypeScriptTag(scriptForCodepoint(0x10b00)));
    try std.testing.expectEqual(OpenTypeScriptTag.avst, openTypeScriptTag(scriptForCodepoint(0x10b35)));
    try std.testing.expectEqual(OpenTypeScriptTag.avst, openTypeScriptTag(scriptForCodepoint(0x10b3f)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x10b36));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x10b00));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x10b3f));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10b00}\u{10b01}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10b02}\u{10b35}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Arabic presentation forms keep Arabic script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "اﻟ ﻢ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.arabic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.arab, openTypeScriptTag(scriptForCodepoint(0xfedf)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0xfedf));
}

test "Hebrew presentation forms keep Hebrew script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "אשׁ ב";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.hebrew, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.hebr, openTypeScriptTag(scriptForCodepoint(0xfb2a)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0xfb2a));
}

test "Phoenician text selects Phoenician RTL script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{10900}\u{10901}\u{1091f}\u{10902}\u{10916}\u{1091a}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.phoenician, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.phnx, openTypeScriptTag(scriptForCodepoint(0x10900)));
    try std.testing.expectEqual(OpenTypeScriptTag.phnx, openTypeScriptTag(scriptForCodepoint(0x10916)));
    try std.testing.expectEqual(OpenTypeScriptTag.phnx, openTypeScriptTag(scriptForCodepoint(0x1091f)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x1091c));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x10900));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x10916));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{10900}\u{10901}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{10902}\u{10916}\u{1091a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Syriac text selects Syriac script and RTL shaping direction" {
    const allocator = std.testing.allocator;

    const text = "ܫܠܡ ݍ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.syriac, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x072b)));
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x086d)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x072b));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x086d));
}

test "Syriac words keep pointing marks but exclude native punctuation" {
    const allocator = std.testing.allocator;

    const text = "\u{0712}\u{0730}\u{0713}\u{0701} \u{074d}\u{074e} \u{0860}\u{0734}\u{086a}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("\u{0712}\u{0730}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0713}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0701}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{0860}\u{0734}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.syriac, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x0730)));
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x074d)));
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x086a)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x0730));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{0712}\u{0730}\u{0713}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{074d}\u{074e}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{0860}\u{0734}\u{086a}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Mandaic text keeps marks and selects Mandaic RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "\u{0840}\u{0859}\u{0841} \u{084C}\u{085A}\u{085B}\u{0840} \u{085E}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{0840}\u{0859}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{0841}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{084C}\u{085A}\u{085B}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{0840}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{085E}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.mandaic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.mand, openTypeScriptTag(scriptForCodepoint(0x0840)));
    try std.testing.expectEqual(OpenTypeScriptTag.mand, openTypeScriptTag(scriptForCodepoint(0x0859)));
    try std.testing.expectEqual(OpenTypeScriptTag.mand, openTypeScriptTag(scriptForCodepoint(0x085e)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x085c));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x0840));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x0859));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{0840}\u{0859}\u{0841}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{084C}\u{085A}\u{085B}\u{0840}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "NKo text selects NKo script and RTL shaping direction" {
    const allocator = std.testing.allocator;

    const text = "ߒߞߏ ߛߓߍ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.nko, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.nko, openTypeScriptTag(scriptForCodepoint(0x07d2)));
    try std.testing.expectEqual(OpenTypeScriptTag.nko, openTypeScriptTag(scriptForCodepoint(0x07eb)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x07d2));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x07eb));
}

test "Adlam text keeps marks and selects Adlam RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "\u{1e922}\u{1e944}\u{1e94a}\u{1e925} \u{1e950}\u{1e951} \u{1e95e}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{1e922}\u{1e944}\u{1e94a}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1e925}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{1e950}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{1e951}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{1e95e}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.adlam, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.adlm, openTypeScriptTag(scriptForCodepoint(0x1e922)));
    try std.testing.expectEqual(OpenTypeScriptTag.adlm, openTypeScriptTag(scriptForCodepoint(0x1e944)));
    try std.testing.expectEqual(OpenTypeScriptTag.adlm, openTypeScriptTag(scriptForCodepoint(0x1e950)));
    try std.testing.expectEqual(OpenTypeScriptTag.adlm, openTypeScriptTag(scriptForCodepoint(0x1e95e)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x1e922));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x1e944));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x1e950));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{1e922}\u{1e944}\u{1e94a}\u{1e925}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1e950}\u{1e951}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Thaana text keeps fili marks and selects Thaana RTL shaping" {
    const allocator = std.testing.allocator;

    const text = "ދިވެހި ބަސް";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ދި", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ވެ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ހި", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ބަ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ސް", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.thaana, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.thaa, openTypeScriptTag(scriptForCodepoint(0x078b)));
    try std.testing.expectEqual(OpenTypeScriptTag.thaa, openTypeScriptTag(scriptForCodepoint(0x07a8)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x078b));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x07a8));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ދިވެހި", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ބަސް", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Thai and Lao text select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ไทย ລາວ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(Script.thai, runs[0].script);
    try std.testing.expectEqualStrings("ไทย ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(Script.lao, runs[1].script);
    try std.testing.expectEqualStrings("ລາວ", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(OpenTypeScriptTag.thai, openTypeScriptTag(scriptForCodepoint(0x0e17)));
    try std.testing.expectEqual(OpenTypeScriptTag.thai, openTypeScriptTag(scriptForCodepoint(0x0e48)));
    try std.testing.expectEqual(OpenTypeScriptTag.lao, openTypeScriptTag(scriptForCodepoint(0x0ea5)));
    try std.testing.expectEqual(OpenTypeScriptTag.lao, openTypeScriptTag(scriptForCodepoint(0x0eb5)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0e17));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0ea5));
}

test "Armenian text selects Armenian script, words, and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "Հայոց ﬓ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.armenian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.armn, openTypeScriptTag(scriptForCodepoint(0x0540)));
    try std.testing.expectEqual(OpenTypeScriptTag.armn, openTypeScriptTag(scriptForCodepoint(0xfb13)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0540));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("Հայոց", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ﬓ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "bidi mirroring covers mathematical bracket pairs" {
    try std.testing.expectEqual(@as(u21, 0x27e9), mirroredCodepoint(0x27e8));
    try std.testing.expectEqual(@as(u21, 0x27e8), mirroredCodepoint(0x27e9));
    try std.testing.expectEqual(@as(u21, 0x2309), mirroredCodepoint(0x2308));
    try std.testing.expectEqual(@as(u21, 0x298f), mirroredCodepoint(0x298e));
    try std.testing.expectEqual(@as(u21, 0x298d), mirroredCodepoint(0x2990));
}

test "word segmentation keeps interior apostrophes but trims quotes" {
    const allocator = std.testing.allocator;

    const words = try itemizeWordSegments(allocator, "'alpha' don't rock 'n' roll");
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
    const breaks = try itemizeLineBreaks(allocator, text);
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 1), breaks.len);
    try std.testing.expectEqual(@as(usize, text.len), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
}

test "line breaks include breakable Unicode space separators" {
    const allocator = std.testing.allocator;

    const breaks = try itemizeLineBreaks(allocator, "a\xe3\x80\x80b\xc2\xa0c\xe2\x80\x83d");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 2), breaks.len);
    try std.testing.expectEqual(@as(usize, 4), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 11), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[1].kind);
}

test "sentence segmentation keeps Arabic-Indic decimal numbers together" {
    const allocator = std.testing.allocator;

    const text = "القيمة ١.٢ جيدة. انتهى";
    const sentences = try itemizeSentenceSegments(allocator, text);
    defer allocator.free(sentences);

    try std.testing.expectEqual(@as(usize, 2), sentences.len);
    try std.testing.expectEqualStrings("القيمة ١.٢ جيدة. ", text[sentences[0].byte_start..][0..sentences[0].byte_len]);
    try std.testing.expectEqualStrings("انتهى", text[sentences[1].byte_start..][0..sentences[1].byte_len]);
}

test "grapheme clusters keep Devanagari virama ZWJ conjuncts atomic" {
    const allocator = std.testing.allocator;

    const text = "क्‍ष क्ष";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("क्‍ष", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("क्", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ष", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
}

test "grapheme clusters keep Gujarati virama ZWJ conjuncts atomic" {
    const allocator = std.testing.allocator;

    const text = "ક્‍ષ ક્ષ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("ક્‍ષ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ક્", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ષ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
}

test "grapheme clusters keep Thai and Lao marks with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ก้ ກີ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ก้", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ກີ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "grapheme clusters keep Myanmar dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ကေ့ ကွာ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ကေ့", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ကွာ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "halfwidth katakana voiced marks stay in kana grapheme and script runs" {
    const allocator = std.testing.allocator;

    const text = "ｶﾞ ㇰ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ｶﾞ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ㇰ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.katakana, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.kana, openTypeScriptTag(scriptForCodepoint(0xff76)));
    try std.testing.expectEqual(OpenTypeScriptTag.kana, openTypeScriptTag(scriptForCodepoint(0x31f0)));
}

test "grapheme clusters keep Khmer dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "កា ក់ កៀ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("កា", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ក់", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("កៀ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
}

test "Khmer text selects Khmer script and keeps COENG clusters" {
    const allocator = std.testing.allocator;

    const text = "\u{1780}\u{17b6} \u{1780}\u{17d2}\u{1781} \u{17e1}\u{17d4} \u{19e0}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
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

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.khmer, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.khmr, openTypeScriptTag(scriptForCodepoint(0x1780)));
    try std.testing.expectEqual(OpenTypeScriptTag.khmr, openTypeScriptTag(scriptForCodepoint(0x17d2)));
    try std.testing.expectEqual(OpenTypeScriptTag.khmr, openTypeScriptTag(scriptForCodepoint(0x19e0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1780));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{1780}\u{17b6}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1780}\u{17d2}\u{1781}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{17e1}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Telugu and Kannada syllables select Indic v2 script tags" {
    const allocator = std.testing.allocator;

    const text = "కి కా క్‍ష ಕಿ ಕಾ ಕ್‍ಷ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 11), clusters.len);
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
    try std.testing.expectEqualStrings("ಕ್‍ಷ", text[clusters[10].byte_start..][0..clusters[10].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(Script.telugu, runs[0].script);
    try std.testing.expectEqualStrings("కి కా క్‍ష ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(Script.kannada, runs[1].script);
    try std.testing.expectEqualStrings("ಕಿ ಕಾ ಕ್‍ಷ", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(OpenTypeScriptTag.tel2, openTypeScriptTag(scriptForCodepoint(0x0c15)));
    try std.testing.expectEqual(OpenTypeScriptTag.tel2, openTypeScriptTag(scriptForCodepoint(0x0c4d)));
    try std.testing.expectEqual(OpenTypeScriptTag.knd2, openTypeScriptTag(scriptForCodepoint(0x0c95)));
    try std.testing.expectEqual(OpenTypeScriptTag.knd2, openTypeScriptTag(scriptForCodepoint(0x0ccd)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0c15));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0c95));

    const words = try itemizeWordSegments(allocator, text);
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
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("কো", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ক্", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("বাং", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("লা", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.bengali, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.bng2, openTypeScriptTag(scriptForCodepoint(0x0995)));
    try std.testing.expectEqual(OpenTypeScriptTag.bng2, openTypeScriptTag(scriptForCodepoint(0x09cd)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x09ac));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("কো", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ক্", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("বাংলা", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Odia syllables keep marks and select Odia OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ଓଡ଼ିଆ କ୍‍ଷ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("ଓ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ଡ଼ି", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ଆ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("କ୍‍ଷ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.odia, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.ory2, openTypeScriptTag(scriptForCodepoint(0x0b13)));
    try std.testing.expectEqual(OpenTypeScriptTag.ory2, openTypeScriptTag(scriptForCodepoint(0x0b4d)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0b13));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ଓଡ଼ିଆ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("କ୍‍ଷ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Gurmukhi syllables keep marks and select Gurmukhi OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ਗੁਰੂ ਗ੍‍ਰੰਥ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("ਗੁ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ਰੂ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ਗ੍‍ਰੰ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ਥ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.gurmukhi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.gur2, openTypeScriptTag(scriptForCodepoint(0x0a17)));
    try std.testing.expectEqual(OpenTypeScriptTag.gur2, openTypeScriptTag(scriptForCodepoint(0x0a4d)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0a17));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("ਗੁਰੂ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ਗ੍‍ਰੰਥ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Gujarati syllables keep signs and select Gujarati OpenType script" {
    const allocator = std.testing.allocator;

    const text = "કિ કા ક્‍ષ ૧૨૰ ૐ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 11), clusters.len);
    try std.testing.expectEqualStrings("કિ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("કા", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ક્‍ષ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("૰", text[clusters[8].byte_start..][0..clusters[8].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.gujarati, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.gjr2, openTypeScriptTag(scriptForCodepoint(0x0a95)));
    try std.testing.expectEqual(OpenTypeScriptTag.gjr2, openTypeScriptTag(scriptForCodepoint(0x0abf)));
    try std.testing.expectEqual(OpenTypeScriptTag.gjr2, openTypeScriptTag(scriptForCodepoint(0x0acd)));
    try std.testing.expectEqual(OpenTypeScriptTag.gjr2, openTypeScriptTag(scriptForCodepoint(0x0af0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0a95));

    const words = try itemizeWordSegments(allocator, text);
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
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("සිං", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("හ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ල", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ක්", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.sinhala, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.sinh, openTypeScriptTag(scriptForCodepoint(0x0dc3)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0dc3));
}

test "Tamil syllables keep marks and select Tamil OpenType script" {
    const allocator = std.testing.allocator;

    const text = "கி கோ 𑿀";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("கி", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("கோ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("𑿀", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.tamil, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.taml, openTypeScriptTag(scriptForCodepoint(0x0b95)));
    try std.testing.expectEqual(OpenTypeScriptTag.taml, openTypeScriptTag(scriptForCodepoint(0x11fc0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0b95));
}

test "Malayalam syllables keep marks and select Malayalam OpenType script" {
    const allocator = std.testing.allocator;

    const text = "കി ക്‍ഷ കോ മലയാളം";
    const clusters = try itemizeGraphemeClusters(allocator, text);
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

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.malayalam, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.mlm2, openTypeScriptTag(scriptForCodepoint(0x0d15)));
    try std.testing.expectEqual(OpenTypeScriptTag.mlm2, openTypeScriptTag(scriptForCodepoint(0x0d4d)));
    try std.testing.expectEqual(OpenTypeScriptTag.mlm2, openTypeScriptTag(scriptForCodepoint(0x0d7a)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0d15));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("കി", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ക്‍ഷ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("കോ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("മലയാളം", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "grapheme clusters attach non-Arabic prepend signs to following bases" {
    const allocator = std.testing.allocator;

    const text = "ൎക 𑂽𑂦";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ൎക", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("𑂽𑂦", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "Hangul conjoining jamo classify as Hangul script runs" {
    const allocator = std.testing.allocator;

    const text = "한 한";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.hangul, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0x1100)));
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0xA960)));
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0xD7B0)));
}

test "Georgian text selects Georgian script runs and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "ქართული Ქⴐ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.georgian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x10d0)));
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x1c90)));
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x2d10)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x10d0));
}

test "Cherokee text selects Cherokee script runs and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "ᎣᏏᏲ ꭰꮝ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.cherokee, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.cher, openTypeScriptTag(scriptForCodepoint(0x13a3)));
    try std.testing.expectEqual(OpenTypeScriptTag.cher, openTypeScriptTag(scriptForCodepoint(0xab70)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x13a3));
}

test "Tifinagh text keeps joiners and selects Tifinagh script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{2d30}\u{2d7f}\u{2d31} \u{2d37}\u{2d6f}\u{2d70}\u{2d59}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{2d30}\u{2d7f}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2d31}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{2d37}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{2d6f}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("\u{2d70}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{2d59}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.tifinagh, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.tfng, openTypeScriptTag(scriptForCodepoint(0x2d30)));
    try std.testing.expectEqual(OpenTypeScriptTag.tfng, openTypeScriptTag(scriptForCodepoint(0x2d6f)));
    try std.testing.expectEqual(OpenTypeScriptTag.tfng, openTypeScriptTag(scriptForCodepoint(0x2d7f)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x2d68));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x2d30));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{2d30}\u{2d7f}\u{2d31}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2d37}\u{2d6f}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{2d59}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Ethiopic text selects Ethiopic script runs and direction" {
    const allocator = std.testing.allocator;

    const text = "ሰላም። ግዕዝ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.ethiopic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x1230)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x1380)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x2d80)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0xab20)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1230));
}

test "Mongolian text keeps free variation selectors and selects Mongolian script" {
    const allocator = std.testing.allocator;

    const text = "ᠮᠣᠩᠭᠣᠯ ᠠ᠋";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("ᠠ᠋", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.mongolian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.mong, openTypeScriptTag(scriptForCodepoint(0x182E)));
    try std.testing.expectEqual(OpenTypeScriptTag.mong, openTypeScriptTag(scriptForCodepoint(0x180B)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x182E));
}

test "Tibetan stacks keep marks and select Tibetan OpenType script" {
    const allocator = std.testing.allocator;

    const text = "བོ ཀྱ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("བོ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ཀྱ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.tibetan, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.tibt, openTypeScriptTag(scriptForCodepoint(0x0f56)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0f56));
}

test "Balinese syllables keep marks and select Balinese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᬓᭀ ᬓ᭄ ᬩᬮᬶ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᬓᭀ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᬓ᭄", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᬩ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᬮᬶ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.balinese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.bali, openTypeScriptTag(scriptForCodepoint(0x1b13)));
    try std.testing.expectEqual(OpenTypeScriptTag.bali, openTypeScriptTag(scriptForCodepoint(0x1b44)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1b13));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᬓᭀ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᬓ᭄", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᬩᬮᬶ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Javanese syllables keep marks and select Javanese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꦏꦺꦴ ꦏ꧀ ꦲꦤꦕꦫꦏ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 9), clusters.len);
    try std.testing.expectEqualStrings("ꦏꦺꦴ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ꦏ꧀", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.javanese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.java, openTypeScriptTag(scriptForCodepoint(0xa98f)));
    try std.testing.expectEqual(OpenTypeScriptTag.java, openTypeScriptTag(scriptForCodepoint(0xa9c0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xa98f));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ꦏꦺꦴ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ꦏ꧀", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ꦲꦤꦕꦫꦏ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Limbu syllables keep marks and select Limbu OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᤁᤠ᤹ ᤁᤩ ᤋ᤺ᤛ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᤁᤠ᤹", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᤁᤩ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᤋ᤺", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᤛ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.limbu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.limb, openTypeScriptTag(scriptForCodepoint(0x1901)));
    try std.testing.expectEqual(OpenTypeScriptTag.limb, openTypeScriptTag(scriptForCodepoint(0x1929)));
    try std.testing.expectEqual(OpenTypeScriptTag.limb, openTypeScriptTag(scriptForCodepoint(0x1946)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1901));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᤁᤠ᤹", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᤁᤩ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᤋ᤺ᤛ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Lepcha syllables keep signs and select Lepcha OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᰀᰦ ᰁᰤᰬ ᱍ᰷ ᱀᰻";
    const clusters = try itemizeGraphemeClusters(allocator, text);
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

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.lepcha, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.lepc, openTypeScriptTag(scriptForCodepoint(0x1c00)));
    try std.testing.expectEqual(OpenTypeScriptTag.lepc, openTypeScriptTag(scriptForCodepoint(0x1c24)));
    try std.testing.expectEqual(OpenTypeScriptTag.lepc, openTypeScriptTag(scriptForCodepoint(0x1c37)));
    try std.testing.expectEqual(OpenTypeScriptTag.lepc, openTypeScriptTag(scriptForCodepoint(0x1c3b)));
    try std.testing.expectEqual(OpenTypeScriptTag.lepc, openTypeScriptTag(scriptForCodepoint(0x1c4d)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x1c38));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1c00));
    try std.testing.expectEqual(BidiClass.neutral, bidiClassForCodepoint(0x1c38));

    const words = try itemizeWordSegments(allocator, text);
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
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 6), clusters.len);
    try std.testing.expectEqualStrings("ᨀᨗ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ᨔᨛ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ᨄᨙ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings("ᨑᨗ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.buginese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.bugi, openTypeScriptTag(scriptForCodepoint(0x1a00)));
    try std.testing.expectEqual(OpenTypeScriptTag.bugi, openTypeScriptTag(scriptForCodepoint(0x1a17)));
    try std.testing.expectEqual(OpenTypeScriptTag.bugi, openTypeScriptTag(scriptForCodepoint(0x1a19)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1a00));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᨀᨗ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᨔᨛ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᨄᨙᨑᨗ", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Sundanese syllables keep signs and select Sundanese OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ᮊᮥ ᮔ᮪ ᮞᮥᮔ᮪ᮓ ᳀";
    const clusters = try itemizeGraphemeClusters(allocator, text);
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

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.sundanese, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.sund, openTypeScriptTag(scriptForCodepoint(0x1b8a)));
    try std.testing.expectEqual(OpenTypeScriptTag.sund, openTypeScriptTag(scriptForCodepoint(0x1ba5)));
    try std.testing.expectEqual(OpenTypeScriptTag.sund, openTypeScriptTag(scriptForCodepoint(0x1baa)));
    try std.testing.expectEqual(OpenTypeScriptTag.sund, openTypeScriptTag(scriptForCodepoint(0x1cc0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1b8a));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ᮊᮥ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᮔ᮪", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ᮞᮥᮔ᮪ᮓ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("᳀", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Meetei Mayek syllables keep signs and select Meetei OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꯀꯤ ꯑꯩ ꫠꫫ ꯄ꯭ ꯱";
    const clusters = try itemizeGraphemeClusters(allocator, text);
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

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.meetei_mayek, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.mtei, openTypeScriptTag(scriptForCodepoint(0xabc0)));
    try std.testing.expectEqual(OpenTypeScriptTag.mtei, openTypeScriptTag(scriptForCodepoint(0xabe4)));
    try std.testing.expectEqual(OpenTypeScriptTag.mtei, openTypeScriptTag(scriptForCodepoint(0xaae0)));
    try std.testing.expectEqual(OpenTypeScriptTag.mtei, openTypeScriptTag(scriptForCodepoint(0xabf1)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xabc0));

    const words = try itemizeWordSegments(allocator, text);
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
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 12), clusters.len);
    try std.testing.expectEqualStrings("ᐃ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("ᢰ", text[clusters[7].byte_start..][0..clusters[7].byte_len]);
    try std.testing.expectEqualStrings("𑪰", text[clusters[10].byte_start..][0..clusters[10].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.canadian_aboriginal, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.cans, openTypeScriptTag(scriptForCodepoint(0x1403)));
    try std.testing.expectEqual(OpenTypeScriptTag.cans, openTypeScriptTag(scriptForCodepoint(0x18b0)));
    try std.testing.expectEqual(OpenTypeScriptTag.cans, openTypeScriptTag(scriptForCodepoint(0x11ab0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1403));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("ᐃᓄᒃᑎᑐᑦ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ᢰᣵ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("𑪰𑪿", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Cham syllables keep signs and select Cham OpenType script" {
    const allocator = std.testing.allocator;

    const text = "ꨆꨩ ꨆꨯ ꩀꩃꩍ ꩐";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("ꨆꨩ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ꨆꨯ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ꩀꩃꩍ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("꩐", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.cham, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.cham, openTypeScriptTag(scriptForCodepoint(0xaa06)));
    try std.testing.expectEqual(OpenTypeScriptTag.cham, openTypeScriptTag(scriptForCodepoint(0xaa29)));
    try std.testing.expectEqual(OpenTypeScriptTag.cham, openTypeScriptTag(scriptForCodepoint(0xaa4d)));
    try std.testing.expectEqual(OpenTypeScriptTag.cham, openTypeScriptTag(scriptForCodepoint(0xaa50)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xaa06));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ꨆꨩ", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ꨆꨯ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("ꩀꩃꩍ", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("꩐", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Brahmi syllables keep marks and select Brahmi OpenType script" {
    const allocator = std.testing.allocator;

    const text = "\u{11013}\u{11038} \u{11013}\u{11002} \u{11013}\u{11046}\u{200d}\u{11022} \u{11066}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("\u{11013}\u{11038}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11002}", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11046}\u{200d}\u{11022}", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{11066}", text[clusters[6].byte_start..][0..clusters[6].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.brahmi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.brah, openTypeScriptTag(scriptForCodepoint(0x11013)));
    try std.testing.expectEqual(OpenTypeScriptTag.brah, openTypeScriptTag(scriptForCodepoint(0x11038)));
    try std.testing.expectEqual(OpenTypeScriptTag.brah, openTypeScriptTag(scriptForCodepoint(0x11046)));
    try std.testing.expectEqual(OpenTypeScriptTag.brah, openTypeScriptTag(scriptForCodepoint(0x11066)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x11013));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("\u{11013}\u{11038}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11002}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{11013}\u{11046}\u{200d}\u{11022}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{11066}", text[words[3].byte_start..][0..words[3].byte_len]);
}

test "Yi syllables and radicals select Yi script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a000}\u{a001} \u{a490}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.yi, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.yi, openTypeScriptTag(scriptForCodepoint(0xa000)));
    try std.testing.expectEqual(OpenTypeScriptTag.yi, openTypeScriptTag(scriptForCodepoint(0xa490)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xa000));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{a000}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a001}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a490}", text[words[2].byte_start..][0..words[2].byte_len]);

    const breaks = try itemizeLineBreaks(allocator, "\u{a000}\u{a001}\u{a490}");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 3), breaks.len);
    try std.testing.expectEqual(@as(usize, 3), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 6), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 9), breaks[2].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[2].kind);
}

test "Vai syllables select Vai script and word primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a500}\u{a501}\u{a60c} \u{a610}\u{a620}\u{a60d}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.vai, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.vai, openTypeScriptTag(scriptForCodepoint(0xa500)));
    try std.testing.expectEqual(OpenTypeScriptTag.vai, openTypeScriptTag(scriptForCodepoint(0xa60c)));
    try std.testing.expectEqual(OpenTypeScriptTag.vai, openTypeScriptTag(scriptForCodepoint(0xa620)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xa500));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{a500}\u{a501}\u{a60c}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{a610}\u{a620}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Lisu letters select Lisu script primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{a4d0}\u{a4f4}\u{a4fd} \u{11fb0}\u{a4f0}\u{a4ff}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.lisu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.lisu, openTypeScriptTag(scriptForCodepoint(0xa4d0)));
    try std.testing.expectEqual(OpenTypeScriptTag.lisu, openTypeScriptTag(scriptForCodepoint(0xa4fd)));
    try std.testing.expectEqual(OpenTypeScriptTag.lisu, openTypeScriptTag(scriptForCodepoint(0x11fb0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0xa4d0));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x11fb0));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{a4d0}\u{a4f4}\u{a4fd}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{11fb0}\u{a4f0}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Nushu characters select Nushu script and ideographic layout primitives" {
    const allocator = std.testing.allocator;

    const text = "\u{1b170}\u{1b171} \u{1b2ff}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.nushu, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.nshu, openTypeScriptTag(scriptForCodepoint(0x1b170)));
    try std.testing.expectEqual(OpenTypeScriptTag.nshu, openTypeScriptTag(scriptForCodepoint(0x1b2ff)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1b170));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{1b170}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{1b171}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{1b2ff}", text[words[2].byte_start..][0..words[2].byte_len]);

    const breaks = try itemizeLineBreaks(allocator, "\u{1b170}\u{1b171}\u{1b2ff}");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 3), breaks.len);
    try std.testing.expectEqual(@as(usize, 4), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 8), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[1].kind);
    try std.testing.expectEqual(@as(usize, 12), breaks[2].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[2].kind);
}

test "Runic text selects Runic script primitives and groups words around separators" {
    const allocator = std.testing.allocator;

    const text = "\u{16a0}\u{16b1}\u{16eb}\u{16f0} \u{16ee}\u{16f8}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.runic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.runr, openTypeScriptTag(scriptForCodepoint(0x16a0)));
    try std.testing.expectEqual(OpenTypeScriptTag.runr, openTypeScriptTag(scriptForCodepoint(0x16f8)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x16a0));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x16ee));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("\u{16a0}\u{16b1}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{16f0}", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{16ee}\u{16f8}", text[words[2].byte_start..][0..words[2].byte_len]);
}

test "Coptic text selects Coptic script primitives across blocks" {
    const allocator = std.testing.allocator;

    const text = "\u{03e2}\u{2cef}\u{2c81} \u{102e1}\u{102e0}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.coptic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.copt, openTypeScriptTag(scriptForCodepoint(0x03e2)));
    try std.testing.expectEqual(OpenTypeScriptTag.copt, openTypeScriptTag(scriptForCodepoint(0x2c81)));
    try std.testing.expectEqual(OpenTypeScriptTag.copt, openTypeScriptTag(scriptForCodepoint(0x102e1)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x2c81));

    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("\u{03e2}\u{2cef}", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{2c81}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("\u{102e1}\u{102e0}", text[clusters[3].byte_start..][0..clusters[3].byte_len]);

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{03e2}\u{2cef}\u{2c81}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{102e1}\u{102e0}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Ogham text selects Ogham script and excludes native separators from words" {
    const allocator = std.testing.allocator;

    const text = "\u{1681}\u{1682}\u{1680}\u{169a}\u{169b}\u{169c}";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.ogham, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.ogam, openTypeScriptTag(scriptForCodepoint(0x1681)));
    try std.testing.expectEqual(OpenTypeScriptTag.ogam, openTypeScriptTag(scriptForCodepoint(0x1680)));
    try std.testing.expectEqual(OpenTypeScriptTag.ogam, openTypeScriptTag(scriptForCodepoint(0x169c)));
    try std.testing.expectEqual(Script.unknown, scriptForCodepoint(0x169d));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1681));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("\u{1681}\u{1682}", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("\u{169a}", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "Myanmar text selects Myanmar v2 script primitives across extensions" {
    const allocator = std.testing.allocator;

    const text = "ကေ့\u{104a} ကွာ \u{a9e0}\u{aa7b} \u{aa60}\u{aa7c}";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 8), clusters.len);
    try std.testing.expectEqualStrings("ကေ့", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("\u{104a}", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ကွာ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("\u{a9e0}\u{aa7b}", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("\u{aa60}\u{aa7c}", text[clusters[7].byte_start..][0..clusters[7].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.myanmar, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.mym2, openTypeScriptTag(scriptForCodepoint(0x1000)));
    try std.testing.expectEqual(OpenTypeScriptTag.mym2, openTypeScriptTag(scriptForCodepoint(0xa9e0)));
    try std.testing.expectEqual(OpenTypeScriptTag.mym2, openTypeScriptTag(scriptForCodepoint(0xaa60)));
    try std.testing.expectEqual(OpenTypeScriptTag.mym2, openTypeScriptTag(scriptForCodepoint(0x116d0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1000));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 4), words.len);
    try std.testing.expectEqualStrings("ကေ့", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ကွာ", text[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("\u{a9e0}\u{aa7b}", text[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("\u{aa60}\u{aa7c}", text[words[3].byte_start..][0..words[3].byte_len]);
}

const WordKind = enum {
    none,
    single,
    latin_number,
    lisu,
    vai,
    arabic,
    hebrew,
    syriac,
    phoenician,
    armenian,
    glagolitic,
    old_italic,
    avestan,
    thaana,
    adlam,
    mandaic,
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
    limbu,
    lepcha,
    buginese,
    sundanese,
    meetei_mayek,
    canadian_aboriginal,
    tifinagh,
    cham,
    brahmi,
    runic,
    coptic,
    ogham,
};

fn appendSentenceIfNotBlank(allocator: std.mem.Allocator, sentences: *std.ArrayList(SentenceSegment), text: []const u8, start: usize, end: usize) !void {
    var cursor = start;
    while (cursor < end) {
        const codepoint_len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch break;
        const codepoint = std.unicode.utf8Decode(text[cursor..][0..codepoint_len]) catch break;
        if (!isSentenceTrailingSpace(codepoint)) break;
        cursor += codepoint_len;
    }
    if (cursor >= end) return;
    try sentences.append(allocator, .{ .byte_start = start, .byte_len = end - start });
}

fn isSentenceTerminator(codepoint: u21) bool {
    return codepoint == '.' or codepoint == '!' or codepoint == '?' or
        codepoint == 0x3002 or codepoint == 0xff01 or codepoint == 0xff1f;
}

fn isMidNumberSentencePeriod(codepoint: u21, previous: ?u21, text: []const u8, byte_end: usize) bool {
    // UAX #29 keeps full stops and similar STerm codepoints inside numeric
    // tokens (SB8), e.g. version strings and decimal values. The segmenter is
    // intentionally compact, but avoiding breaks in the common digit '.' digit
    // case prevents obviously incorrect sentence cuts in UI text. Treat the
    // decimal digit sets already recognized by the bidi layer as digits here
    // too, so Arabic-Indic and Extended Arabic-Indic numbers are not split in
    // mixed-script documents.
    if (codepoint != '.') return false;
    const before = previous orelse return false;
    if (!isDecimalDigit(before)) return false;
    const after = nextCodepointAt(text, byte_end) orelse return false;
    return isDecimalDigit(after);
}

fn nextCodepointAt(text: []const u8, offset: usize) ?u21 {
    return (decodeCodepointAt(text, offset) orelse return null).codepoint;
}

fn isDecimalDigit(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

fn isAsciiApostrophe(codepoint: u21) bool {
    return codepoint == '\'';
}

fn isSentenceTrailingSpace(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t' or codepoint == '\n' or codepoint == '\r';
}

fn isSentenceTrailingClose(codepoint: u21) bool {
    return switch (codepoint) {
        '\'', '"', ')', ']', '}', 0x00bb, 0x2019, 0x201d, 0x3009, 0x300b, 0x300d, 0x300f, 0x3011, 0x3015, 0x3017, 0x3019, 0x301b => true,
        else => false,
    };
}

fn isLineBreakSpace(codepoint: u21) bool {
    return codepoint == ' ' or
        codepoint == '\t' or
        // Unicode space separators that permit wrapping should behave like
        // ASCII spaces here. Keep no-break spaces out of this compact list so
        // callers do not wrap inside intentionally glued labels or numbers.
        codepoint == 0x1680 or
        (codepoint >= 0x2000 and codepoint <= 0x200a) or
        codepoint == 0x205f or
        codepoint == 0x3000;
}

fn nextClusterProhibitsEastAsianBreak(text: []const u8, clusters: []const GraphemeCluster, cluster_index: usize) bool {
    const next_index = cluster_index + 1;
    if (next_index >= clusters.len) return false;
    const next = clusters[next_index];
    const next_end = next.byte_start + next.byte_len;
    const next_codepoint = firstCodepoint(text[next.byte_start..next_end]) orelse return false;
    return isEastAsianClosingPunctuation(next_codepoint);
}

fn isEastAsianClosingPunctuation(codepoint: u21) bool {
    return switch (codepoint) {
        0x3001,
        0x3002,
        0xff0c,
        0xff0e,
        0xff1a,
        0xff1b,
        0xff01,
        0xff1f,
        0x3009,
        0x300b,
        0x300d,
        0x300f,
        0x3011,
        0x3015,
        0x3017,
        0x3019,
        0x301b,
        0xff09,
        0xff3d,
        0xff5d,
        0xff60,
        => true,
        else => false,
    };
}

fn isLineBreakEastAsian(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0x2e80 and codepoint <= 0x2eff) or
        (codepoint >= 0x2f00 and codepoint <= 0x2fdf) or
        (codepoint >= 0x3040 and codepoint <= 0x30ff) or
        (codepoint >= 0x3130 and codepoint <= 0x318f) or
        (codepoint >= 0x31a0 and codepoint <= 0x31ff) or
        (codepoint >= 0x3400 and codepoint <= 0x4dbf) or
        (codepoint >= 0x4e00 and codepoint <= 0x9fff) or
        (codepoint >= 0xa000 and codepoint <= 0xa4cf) or
        // Nushu is a supplementary-plane ideographic script. Treat it like
        // Han/Yi for this compact line-break primitive so long unspaced Nushu
        // text can wrap between characters instead of only at ASCII spaces.
        (codepoint >= 0x1b170 and codepoint <= 0x1b2ff) or
        (codepoint >= 0xac00 and codepoint <= 0xd7af) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0x20000 and codepoint <= 0x2fffd) or
        (codepoint >= 0x30000 and codepoint <= 0x3fffd);
}

fn wordKindForCodepoint(codepoint: u21) WordKind {
    if ((codepoint >= 'A' and codepoint <= 'Z') or
        (codepoint >= 'a' and codepoint <= 'z') or
        (codepoint >= '0' and codepoint <= '9') or
        codepoint == '_')
    {
        return .latin_number;
    }
    if (isLisuWordCodepoint(codepoint)) return .lisu;
    if (isVaiWordCodepoint(codepoint)) return .vai;
    if (isKhmerWordCodepoint(codepoint)) return .khmer;
    if (isMyanmarWordCodepoint(codepoint)) return .myanmar;
    if (isThaanaWordCodepoint(codepoint)) return .thaana;
    if (isAdlamWordCodepoint(codepoint)) return .adlam;
    if (isSyriacWordCodepoint(codepoint)) return .syriac;
    if (isMandaicWordCodepoint(codepoint)) return .mandaic;
    if (isPhoenicianWordCodepoint(codepoint)) return .phoenician;
    if (isLepchaWordCodepoint(codepoint)) return .lepcha;
    if (isGujaratiWordCodepoint(codepoint)) return .gujarati;
    if (isRunicWordCodepoint(codepoint)) return .runic;
    if (isCopticWordCodepoint(codepoint)) return .coptic;
    if (isOghamWordCodepoint(codepoint)) return .ogham;
    if (isTifinaghWordCodepoint(codepoint)) return .tifinagh;
    if (isGlagoliticWordCodepoint(codepoint)) return .glagolitic;
    if (isOldItalicWordCodepoint(codepoint)) return .old_italic;
    if (isAvestanWordCodepoint(codepoint)) return .avestan;
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .han, .yi, .nushu, .hiragana, .katakana, .hangul => .single,
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
        .limbu => .limbu,
        .buginese => .buginese,
        .sundanese => .sundanese,
        .meetei_mayek => .meetei_mayek,
        .canadian_aboriginal => .canadian_aboriginal,
        .cham => .cham,
        .brahmi => .brahmi,
        else => .none,
    };
}

fn isWordExtender(codepoint: u21) bool {
    return codepoint == 0x200c or
        codepoint == 0x200d or
        isCombiningMark(codepoint) or
        isVariationSelector(codepoint) or
        isEmojiModifier(codepoint) or
        isSpacingMark(codepoint) or
        isWordFormat(codepoint);
}

fn isWordFormat(codepoint: u21) bool {
    return codepoint == 0x00ad or
        codepoint == 0x061c or
        codepoint == 0x180e or
        codepoint == 0x200e or
        codepoint == 0x200f or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x2064) or
        (codepoint >= 0x2066 and codepoint <= 0x206f) or
        codepoint == 0xfeff;
}

fn extendsGrapheme(previous: u21, current: u21, regional_indicator_count: usize, zwj_after_extended_pictographic: bool, zwj_after_indic_virama: bool) bool {
    // Keep this predicate conservative: it only returns true for continuation
    // codepoints that should share a caret stop with the previous codepoint.
    if (previous == '\r' and current == '\n') return true;
    // UAX #29 GB4/GB5 make controls atomic grapheme clusters. Check this
    // before Prepend/Extend/ZWJ rules so stray format or paragraph controls do
    // not absorb adjacent marks and hide caret stops around them.
    if (isGraphemeControl(previous) or isGraphemeControl(current)) return false;
    if (isGraphemePrependCodepoint(previous)) return true;
    if (current == 0x200d) return true;
    if (extendsHangulGrapheme(previous, current)) return true;
    if (isRegionalIndicator(previous) and isRegionalIndicator(current) and regional_indicator_count % 2 == 1) return true;
    if (isGraphemeExtendCodepoint(current)) return true;
    if (previous == 0x17d2 and isKhmerConsonant(current)) return true;
    if (previous == 0x200d) {
        return (zwj_after_extended_pictographic and isExtendedPictographic(current)) or
            (zwj_after_indic_virama and isIndicConsonant(current));
    }
    return false;
}

const HangulGraphemeClass = enum {
    other,
    l,
    v,
    t,
    lv,
    lvt,
};

fn extendsHangulGrapheme(previous: u21, current: u21) bool {
    const previous_class = hangulGraphemeClass(previous);
    const current_class = hangulGraphemeClass(current);
    return switch (previous_class) {
        .l => current_class == .l or current_class == .v or current_class == .lv or current_class == .lvt,
        .v, .lv => current_class == .v or current_class == .t,
        .t, .lvt => current_class == .t,
        .other => false,
    };
}

fn hangulGraphemeClass(codepoint: u21) HangulGraphemeClass {
    if ((codepoint >= 0x1100 and codepoint <= 0x115f) or (codepoint >= 0xa960 and codepoint <= 0xa97c)) return .l;
    if ((codepoint >= 0x1160 and codepoint <= 0x11a7) or (codepoint >= 0xd7b0 and codepoint <= 0xd7c6)) return .v;
    if ((codepoint >= 0x11a8 and codepoint <= 0x11ff) or (codepoint >= 0xd7cb and codepoint <= 0xd7fb)) return .t;
    if (codepoint >= 0xac00 and codepoint <= 0xd7a3) {
        return if ((codepoint - 0xac00) % 28 == 0) .lv else .lvt;
    }
    return .other;
}

fn isCombiningMark(codepoint: u21) bool {
    return (codepoint >= 0x0300 and codepoint <= 0x036f) or
        // These compact script-specific ranges cover combining marks for the
        // non-Latin scripts Cangjie already itemizes. Without them, accents,
        // vowel signs, and viramas become separate grapheme/word units even
        // though UAX #29 treats them as Extend.
        (codepoint >= 0x0591 and codepoint <= 0x05bd) or
        codepoint == 0x05bf or
        (codepoint >= 0x05c1 and codepoint <= 0x05c2) or
        (codepoint >= 0x05c4 and codepoint <= 0x05c5) or
        codepoint == 0x05c7 or
        (codepoint >= 0x0610 and codepoint <= 0x061a) or
        (codepoint >= 0x064b and codepoint <= 0x065f) or
        codepoint == 0x0670 or
        (codepoint >= 0x06d6 and codepoint <= 0x06dc) or
        (codepoint >= 0x06df and codepoint <= 0x06e4) or
        (codepoint >= 0x06e7 and codepoint <= 0x06e8) or
        (codepoint >= 0x06ea and codepoint <= 0x06ed) or
        // Syriac superscript alaph plus pointing/vowel marks are nonspacing
        // signs typed after right-to-left bases. Treat them as Extend so
        // grapheme, word, and shaping boundaries preserve one Syriac syllable
        // instead of separating a base letter from its diacritics.
        codepoint == 0x0711 or
        (codepoint >= 0x0730 and codepoint <= 0x074a) or
        // Mandaic affrication, vocalization, and gemination marks are
        // nonspacing signs typed after RTL bases. Treat them as Extend so
        // grapheme, word, and shaping boundaries do not split a Mandaic letter
        // from its marks before OpenType lookup selection.
        (codepoint >= 0x0859 and codepoint <= 0x085b) or
        // Thaana fili vowel signs and sukun are nonspacing marks. They are
        // typed after RTL bases but form one caret/word/shaping unit with the
        // base letter, so keep them in the compact Extend table.
        (codepoint >= 0x07a6 and codepoint <= 0x07b0) or
        // Adlam vowel length, gemination, hamza, consonant modifiers, and
        // nukta are GCB=Extend. They are typed after RTL Adlam letters but
        // must share one caret/word/shaping unit with the base glyph.
        (codepoint >= 0x1e944 and codepoint <= 0x1e94a) or
        // Combining Glagolitic letters are encoded in the supplementary plane
        // and stack with BMP Glagolitic bases. Treat them as Extend so
        // manuscript-style abbreviations stay one grapheme, word, and shaping
        // unit under the `glag` OpenType script selection.
        (codepoint >= 0x1e000 and codepoint <= 0x1e02a) or
        // Tibetan vowel signs, halanta, subjoined-letter marks, and other
        // signs are typed after the base but form one stack/syllable for
        // grapheme and shaping boundaries.
        codepoint == 0x0f35 or
        codepoint == 0x0f37 or
        codepoint == 0x0f39 or
        (codepoint >= 0x0f71 and codepoint <= 0x0f7e) or
        (codepoint >= 0x0f80 and codepoint <= 0x0f84) or
        (codepoint >= 0x0f86 and codepoint <= 0x0f87) or
        (codepoint >= 0x0f8d and codepoint <= 0x0f97) or
        (codepoint >= 0x0f99 and codepoint <= 0x0fbc) or
        codepoint == 0x0fc6 or
        (codepoint >= 0x0900 and codepoint <= 0x0902) or
        codepoint == 0x093a or
        codepoint == 0x093c or
        (codepoint >= 0x0941 and codepoint <= 0x0948) or
        codepoint == 0x094d or
        (codepoint >= 0x0951 and codepoint <= 0x0957) or
        (codepoint >= 0x0962 and codepoint <= 0x0963) or
        // Bengali nonspacing signs include nukta, dependent vowels, virama,
        // and vocalic marks. These are typed after the base consonant but
        // shape as one orthographic unit, so grapheme and word boundaries must
        // keep them attached just like the existing Bengali spacing vowels.
        codepoint == 0x09bc or
        (codepoint >= 0x09c1 and codepoint <= 0x09c4) or
        codepoint == 0x09cd or
        (codepoint >= 0x09e2 and codepoint <= 0x09e3) or
        // Odia nonspacing signs cover chandrabindu, nukta, short dependent
        // vowels, virama, ai-length marks, and vocalic signs. Treating them as
        // Extend prevents caret and shaping boundaries from splitting
        // orthographic syllables such as ଡ଼ି and virama-ZWJ conjuncts.
        codepoint == 0x0b01 or
        codepoint == 0x0b3c or
        (codepoint >= 0x0b41 and codepoint <= 0x0b44) or
        codepoint == 0x0b4d or
        (codepoint >= 0x0b55 and codepoint <= 0x0b56) or
        (codepoint >= 0x0b62 and codepoint <= 0x0b63) or
        // Gurmukhi nonspacing signs cover nasalization, nukta, short vowels,
        // virama, and addak/yakash. Keeping them as grapheme extenders avoids
        // extra caret stops inside syllables such as ਗੁ and virama-ZWJ conjuncts.
        (codepoint >= 0x0a01 and codepoint <= 0x0a02) or
        codepoint == 0x0a3c or
        (codepoint >= 0x0a41 and codepoint <= 0x0a42) or
        (codepoint >= 0x0a47 and codepoint <= 0x0a48) or
        (codepoint >= 0x0a4b and codepoint <= 0x0a4d) or
        codepoint == 0x0a51 or
        (codepoint >= 0x0a70 and codepoint <= 0x0a71) or
        codepoint == 0x0a75 or
        // Gujarati nonspacing signs cover nasalization, nukta, dependent
        // vowels, virama, vocalic signs, and modern Arabic-style diacritics.
        // Keep them attached so Gujarati aksharas and virama-ZWJ conjuncts
        // stay one low-level caret/shaping unit.
        (codepoint >= 0x0a81 and codepoint <= 0x0a82) or
        codepoint == 0x0abc or
        (codepoint >= 0x0ac1 and codepoint <= 0x0ac5) or
        (codepoint >= 0x0ac7 and codepoint <= 0x0ac8) or
        codepoint == 0x0acd or
        (codepoint >= 0x0ae2 and codepoint <= 0x0ae3) or
        (codepoint >= 0x0afa and codepoint <= 0x0aff) or
        // Sinhala nonspacing signs include anusvara/visarga-like marks,
        // dependent vowels, and virama. They are typed after the base but form
        // one akshara for caret and shaping boundaries.
        (codepoint >= 0x0d81 and codepoint <= 0x0d81) or
        codepoint == 0x0d82 or
        (codepoint >= 0x0dca and codepoint <= 0x0dca) or
        (codepoint >= 0x0dd2 and codepoint <= 0x0dd4) or
        codepoint == 0x0dd6 or
        // Tamil dependent vowel signs, pulli, and length mark are Extend in
        // UAX #29. Keeping them attached prevents caret/shaping clusters from
        // bisecting syllables such as கி, க், and கோ.
        codepoint == 0x0b82 or
        codepoint == 0x0bc0 or
        codepoint == 0x0bcd or
        codepoint == 0x0bd7 or
        // Malayalam dependent signs include combining vowels, dot reph, virama,
        // and vocalic marks. They share the base consonant's caret and shaping
        // unit, and U+0D4D VIRAMA also participates in Malayalam ZWJ conjuncts.
        (codepoint >= 0x0d00 and codepoint <= 0x0d01) or
        (codepoint >= 0x0d3b and codepoint <= 0x0d3c) or
        (codepoint >= 0x0d41 and codepoint <= 0x0d44) or
        codepoint == 0x0d4d or
        (codepoint >= 0x0d62 and codepoint <= 0x0d63) or
        // Thai and Lao vowels/tone marks are typed after their base consonant
        // but render as a single unit. Treating them as Extend avoids extra
        // caret stops between the consonant and its visible accent/vowel.
        (codepoint >= 0x0e31 and codepoint <= 0x0e31) or
        (codepoint >= 0x0e34 and codepoint <= 0x0e3a) or
        (codepoint >= 0x0e47 and codepoint <= 0x0e4e) or
        (codepoint >= 0x0eb1 and codepoint <= 0x0eb1) or
        (codepoint >= 0x0eb4 and codepoint <= 0x0ebc) or
        (codepoint >= 0x0ec8 and codepoint <= 0x0ecd) or
        // Khmer vowel signs, robat, coeng, and register/shifter signs are
        // encoded after the consonant but participate in one orthographic
        // syllable. Treating them as Extend preserves UAX #29 grapheme cluster
        // boundaries for Khmer text without requiring a full Khmer shaper.
        (codepoint >= 0x17b7 and codepoint <= 0x17bd) or
        codepoint == 0x17c6 or
        (codepoint >= 0x17c9 and codepoint <= 0x17d3) or
        codepoint == 0x17dd or
        // Myanmar dependent signs are encoded after the base consonant but
        // include both nonspacing and visible-spacing pieces of one orthographic
        // syllable. Keeping the compact GCB coverage here prevents caret and
        // shaping clusters from splitting between kinzi/medial/vowel/tone signs.
        (codepoint >= 0x102d and codepoint <= 0x1030) or
        (codepoint >= 0x1032 and codepoint <= 0x1037) or
        (codepoint >= 0x1039 and codepoint <= 0x103a) or
        (codepoint >= 0x103d and codepoint <= 0x103e) or
        (codepoint >= 0x1058 and codepoint <= 0x1059) or
        (codepoint >= 0x105e and codepoint <= 0x1060) or
        (codepoint >= 0x1071 and codepoint <= 0x1074) or
        codepoint == 0x1082 or
        (codepoint >= 0x1085 and codepoint <= 0x1086) or
        codepoint == 0x108d or
        codepoint == 0x109d or
        // Myanmar Extended-A/B add Shan, Tai Laing, Pao Karen, and Khamti tone
        // marks used with the same `mym2` shaping model as the base block.
        // Keep them in the compact Extend table so extension syllables do not
        // expose caret stops between base letters and tone signs.
        codepoint == 0xa9e5 or
        codepoint == 0xaa7c or
        // Balinese nonspacing signs are encoded after the aksara base but
        // render as one syllable with it. Keep vowel signs, rerekan, and
        // musical combining marks attached so caret/word primitives do not
        // split Balinese orthographic units before shaping.
        (codepoint >= 0x1b00 and codepoint <= 0x1b03) or
        codepoint == 0x1b34 or
        (codepoint >= 0x1b36 and codepoint <= 0x1b3a) or
        codepoint == 0x1b3c or
        codepoint == 0x1b42 or
        (codepoint >= 0x1b6b and codepoint <= 0x1b73) or
        // Javanese nonspacing signs include final consonant signs, vowel
        // signs, and consonant modifiers. They are typed after an aksara base
        // but form one caret/shaping unit with it, so keep them as grapheme
        // and word extenders alongside the spacing Javanese signs below.
        (codepoint >= 0xa980 and codepoint <= 0xa982) or
        codepoint == 0xa9b3 or
        (codepoint >= 0xa9b6 and codepoint <= 0xa9b9) or
        (codepoint >= 0xa9bc and codepoint <= 0xa9bd) or
        // Limbu vowel/final-consonant signs are typed after the base letter
        // but combine with it as one orthographic unit. Preserve that unit for
        // caret, word, and shaping-boundary primitives.
        (codepoint >= 0x1920 and codepoint <= 0x1922) or
        (codepoint >= 0x1927 and codepoint <= 0x1928) or
        codepoint == 0x1932 or
        (codepoint >= 0x1939 and codepoint <= 0x193b) or
        // Lepcha final-consonant signs, vowel E, ran, and nukta are nonspacing
        // marks typed after a base or subjoined letter. Keep them as Extend so
        // low-level caret, word, and shaping boundaries preserve one Lepcha
        // orthographic syllable instead of isolating finals from their base.
        (codepoint >= 0x1c2c and codepoint <= 0x1c33) or
        (codepoint >= 0x1c36 and codepoint <= 0x1c37) or
        // Buginese nonspacing vowel signs share the base lontara letter's
        // caret and shaping unit. Without these small GCB=Extend ranges,
        // syllables such as ᨀᨗ and ᨔᨛ split between base and dependent vowel.
        (codepoint >= 0x1a17 and codepoint <= 0x1a18) or
        codepoint == 0x1a1b or
        // Sundanese nonspacing dependent signs and pamaeh are typed after the
        // base aksara but shape as one orthographic syllable. Treating them as
        // Extend preserves caret, word, and shaping boundaries for text such as
        // ᮊᮥ and final-consonant forms like ᮔ᮪.
        (codepoint >= 0x1ba2 and codepoint <= 0x1ba5) or
        (codepoint >= 0x1ba8 and codepoint <= 0x1ba9) or
        codepoint == 0x1bab or
        // Meetei Mayek has nonspacing vowels and viramas in both the extension
        // and main blocks. They are typed after a base letter but form one
        // orthographic unit for caret placement and shaping feature selection.
        (codepoint >= 0xaaec and codepoint <= 0xaaed) or
        codepoint == 0xaaf6 or
        codepoint == 0xabe5 or
        codepoint == 0xabe8 or
        codepoint == 0xabed or
        // Cham nonspacing vowels and final-consonant marks are typed after
        // their base letters but form one orthographic syllable. Treating them
        // as Extend keeps caret, word, and shaping boundaries out of the
        // middle of Cham syllables such as ꨆꨩ and final clusters like ꩀꩃ.
        (codepoint >= 0xaa29 and codepoint <= 0xaa2e) or
        (codepoint >= 0xaa31 and codepoint <= 0xaa32) or
        (codepoint >= 0xaa35 and codepoint <= 0xaa36) or
        codepoint == 0xaa43 or
        codepoint == 0xaa4c or
        // Brahmi dependent vowels, viramas, and number joiner are combining
        // signs typed after bases or numbers. Keeping them attached preserves
        // historic Indic syllable boundaries for caret and shaping primitives.
        codepoint == 0x11001 or
        (codepoint >= 0x11038 and codepoint <= 0x11046) or
        codepoint == 0x11070 or
        (codepoint >= 0x11073 and codepoint <= 0x11074) or
        codepoint == 0x1107f or
        // Coptic combining marks are used both with Coptic letters and with
        // Coptic Epact Numbers. Keep them attached so caret, word, and shaping
        // primitives do not split a marked Coptic token between base and mark.
        (codepoint >= 0x2cef and codepoint <= 0x2cf1) or
        codepoint == 0x102e0 or
        // U+2D7F TIFINAGH CONSONANT JOINER is a nonspacing sign that requests
        // joined behavior with the preceding Tifinagh letter. Treat it as an
        // Extend codepoint so caret, word, and shaping runs do not split the
        // requested orthographic unit before font lookup selection.
        codepoint == 0x2d7f or
        // Mongolian free variation selectors choose contextual glyph forms
        // and have Grapheme_Cluster_Break=Extend. They must stay attached to
        // the preceding Mongolian letter so shaping clusters retain the
        // requested variant instead of exposing a caret stop before it.
        (codepoint >= 0x180b and codepoint <= 0x180d) or
        codepoint == 0x180f or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f) or
        // Halfwidth katakana voiced/semi-voiced marks are compatibility
        // combining marks (GCB=Extend). They are spacing glyphs, but a base
        // halfwidth kana plus U+FF9E/U+FF9F is one user-perceived character.
        codepoint == 0xff9e or
        codepoint == 0xff9f;
}

fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn isEmojiModifier(codepoint: u21) bool {
    return codepoint >= 0x1f3fb and codepoint <= 0x1f3ff;
}

fn isRegionalIndicator(codepoint: u21) bool {
    return codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff;
}

fn isGraphemeExtendCodepoint(codepoint: u21) bool {
    return codepoint == 0x200c or
        isCombiningMark(codepoint) or
        isVariationSelector(codepoint) or
        isEmojiModifier(codepoint) or
        isEmojiTagCodepoint(codepoint) or
        isSpacingMark(codepoint);
}

fn isEmojiTagCodepoint(codepoint: u21) bool {
    // Emoji flag tag sequences (for example subdivision flags such as England)
    // encode their tag letters in Plane 14. Unicode assigns these scalars
    // Grapheme_Cluster_Break=Extend, so they must stay attached to the
    // preceding pictograph instead of creating one caret stop per tag byte.
    return codepoint >= 0xe0020 and codepoint <= 0xe007f;
}

fn isIndicViramaForZwjConjunct(codepoint: u21) bool {
    return codepoint == 0x094d or // Devanagari sign virama.
        codepoint == 0x0acd or // Gujarati sign virama.
        codepoint == 0x0b4d or // Odia sign virama.
        codepoint == 0x0a4d or // Gurmukhi sign virama.
        codepoint == 0x0c4d or // Telugu sign virama.
        codepoint == 0x0ccd or // Kannada sign virama.
        codepoint == 0x0d4d or // Malayalam sign virama.
        codepoint == 0x11046 or // Brahmi virama.
        codepoint == 0x11070; // Brahmi old Tamil virama.
}

fn isKhmerConsonant(codepoint: u21) bool {
    // U+17D2 COENG turns the following Khmer consonant into a subscript form.
    // Treating that following consonant as a grapheme continuation keeps the
    // orthographic syllable atomic for caret movement and for any future Khmer
    // shaping pass that consumes one cluster at a time.
    return codepoint >= 0x1780 and codepoint <= 0x17a2;
}

fn isIndicConsonant(codepoint: u21) bool {
    // Compact InCB=Consonant coverage for Indic blocks Cangjie clusters today.
    // The ranges are deliberately narrow so ZWJ after a virama only glues to
    // real consonants, not punctuation, digits, or vowel letters.
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        codepoint == 0x0958 or
        codepoint == 0x0959 or
        codepoint == 0x095a or
        codepoint == 0x095b or
        codepoint == 0x095c or
        codepoint == 0x095d or
        codepoint == 0x095e or
        codepoint == 0x095f or
        (codepoint >= 0x0a95 and codepoint <= 0x0ab9) or
        (codepoint >= 0x0b15 and codepoint <= 0x0b39) or
        codepoint == 0x0b5c or
        codepoint == 0x0b5d or
        codepoint == 0x0b5f or
        (codepoint >= 0x0a15 and codepoint <= 0x0a39) or
        (codepoint >= 0x0a59 and codepoint <= 0x0a5e) or
        (codepoint >= 0x0a72 and codepoint <= 0x0a74) or
        (codepoint >= 0x0c15 and codepoint <= 0x0c39) or
        codepoint == 0x0c58 or
        codepoint == 0x0c59 or
        (codepoint >= 0x0c95 and codepoint <= 0x0cb9) or
        (codepoint >= 0x0d15 and codepoint <= 0x0d39) or
        codepoint == 0x0d3a or
        (codepoint >= 0x11013 and codepoint <= 0x11037);
}

fn isGraphemePrependCodepoint(codepoint: u21) bool {
    // Grapheme_Cluster_Break=Prepend signs render with the following base and
    // therefore must not expose a caret/shaping boundary after themselves. Keep
    // this compact table current for the non-Arabic prepend scalars as well;
    // otherwise scripts such as Malayalam and Kaithi split a single user-
    // perceived cluster before the base character.
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or
        codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2 or
        codepoint == 0x0d4e or
        codepoint == 0x110bd or
        codepoint == 0x110cd;
}

fn isGraphemeControl(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x001f) or
        (codepoint >= 0x007f and codepoint <= 0x009f) or
        // Grapheme_Cluster_Break=Control also includes several format and
        // separator scalars. They are invisible text controls, but UAX #29
        // still gives them their own caret stop; otherwise a following Extend
        // mark can be incorrectly absorbed into the control's cluster.
        codepoint == 0x00ad or
        codepoint == 0x061c or
        codepoint == 0x180e or
        codepoint == 0x200b or
        (codepoint >= 0x200e and codepoint <= 0x200f) or
        codepoint == 0x2028 or
        codepoint == 0x2029 or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x206f) or
        codepoint == 0xfeff or
        (codepoint >= 0xfff0 and codepoint <= 0xfff8);
}

fn isExtendedPictographic(codepoint: u21) bool {
    // Compact Extended_Pictographic coverage for emoji families/professions and
    // symbol ZWJ sequences commonly encountered by text editors. This is not
    // the full emoji-data.txt table, but it makes GB11 conditional instead of
    // treating every ZWJ as a universal grapheme glue.
    return codepoint == 0x00a9 or
        codepoint == 0x00ae or
        codepoint == 0x203c or
        codepoint == 0x2049 or
        codepoint == 0x2122 or
        codepoint == 0x2139 or
        (codepoint >= 0x2194 and codepoint <= 0x21aa) or
        codepoint == 0x231a or
        codepoint == 0x231b or
        codepoint == 0x2328 or
        codepoint == 0x23cf or
        (codepoint >= 0x23e9 and codepoint <= 0x23f3) or
        (codepoint >= 0x23f8 and codepoint <= 0x23fa) or
        codepoint == 0x24c2 or
        codepoint == 0x25aa or
        codepoint == 0x25ab or
        codepoint == 0x25b6 or
        codepoint == 0x25c0 or
        (codepoint >= 0x25fb and codepoint <= 0x25fe) or
        (codepoint >= 0x2600 and codepoint <= 0x27bf) or
        codepoint == 0x2934 or
        codepoint == 0x2935 or
        (codepoint >= 0x2b05 and codepoint <= 0x2b55) or
        codepoint == 0x3030 or
        codepoint == 0x303d or
        codepoint == 0x3297 or
        codepoint == 0x3299 or
        (codepoint >= 0x1f000 and codepoint <= 0x1faff);
}

fn isSpacingMark(codepoint: u21) bool {
    return (codepoint >= 0x0903 and codepoint <= 0x0903) or
        (codepoint >= 0x093e and codepoint <= 0x0940) or
        (codepoint >= 0x0949 and codepoint <= 0x094c) or
        (codepoint >= 0x0982 and codepoint <= 0x0983) or
        // Telugu and Kannada dependent vowels/viramas are encoded after the
        // consonant but form a single orthographic unit. Covering both Extend
        // and SpacingMark classes here prevents layout/caret primitives from
        // creating invalid boundaries inside common South Indian syllables.
        (codepoint >= 0x0c00 and codepoint <= 0x0c04) or
        (codepoint >= 0x0c3c and codepoint <= 0x0c44) or
        (codepoint >= 0x0c46 and codepoint <= 0x0c48) or
        (codepoint >= 0x0c4a and codepoint <= 0x0c4d) or
        (codepoint >= 0x0c55 and codepoint <= 0x0c56) or
        (codepoint >= 0x0c62 and codepoint <= 0x0c63) or
        (codepoint >= 0x0cbc and codepoint <= 0x0cbe) or
        (codepoint >= 0x0cbf and codepoint <= 0x0cc4) or
        (codepoint >= 0x0cc6 and codepoint <= 0x0cc8) or
        (codepoint >= 0x0cca and codepoint <= 0x0ccd) or
        (codepoint >= 0x0cd5 and codepoint <= 0x0cd6) or
        (codepoint >= 0x0ce2 and codepoint <= 0x0ce3) or
        // Bengali dependent vowels/length marks with Grapheme_Cluster_Break=SpacingMark.
        // Bengali split vowels such as U+09CB are encoded after the consonant
        // but render around it; exposing a caret stop between base and vowel
        // would bisect one orthographic syllable and desynchronize shaping clusters.
        (codepoint >= 0x09be and codepoint <= 0x09c0) or
        (codepoint >= 0x09c7 and codepoint <= 0x09c8) or
        (codepoint >= 0x09cb and codepoint <= 0x09cc) or
        codepoint == 0x09d7 or
        // Odia spacing marks include anusvara/visarga and split vowel signs.
        // They are encoded after the consonant but render as part of the same
        // akshara, so grapheme and shaping primitives must keep them attached.
        (codepoint >= 0x0b02 and codepoint <= 0x0b03) or
        (codepoint >= 0x0b3e and codepoint <= 0x0b40) or
        (codepoint >= 0x0b47 and codepoint <= 0x0b48) or
        (codepoint >= 0x0b4b and codepoint <= 0x0b4c) or
        codepoint == 0x0b57 or
        // Gurmukhi dependent vowel signs with Grapheme_Cluster_Break=SpacingMark
        // render with the base consonant and should share its caret/shaping unit.
        codepoint == 0x0a03 or
        (codepoint >= 0x0a3e and codepoint <= 0x0a40) or
        // Gujarati spacing marks include visible dependent vowels and visarga.
        // They are encoded after the base but render as part of the same
        // akshara, so grapheme and word segmentation must not split before them.
        codepoint == 0x0a83 or
        (codepoint >= 0x0abe and codepoint <= 0x0ac0) or
        codepoint == 0x0ac9 or
        (codepoint >= 0x0acb and codepoint <= 0x0acc) or
        (codepoint >= 0x0dcf and codepoint <= 0x0dd1) or
        (codepoint >= 0x0dd8 and codepoint <= 0x0ddf) or
        (codepoint >= 0x0bbe and codepoint <= 0x0bbf) or
        (codepoint >= 0x0bc1 and codepoint <= 0x0bc2) or
        (codepoint >= 0x0bc6 and codepoint <= 0x0bc8) or
        (codepoint >= 0x0bca and codepoint <= 0x0bcc) or
        (codepoint >= 0x0d02 and codepoint <= 0x0d03) or
        (codepoint >= 0x0d3e and codepoint <= 0x0d40) or
        (codepoint >= 0x0d46 and codepoint <= 0x0d48) or
        (codepoint >= 0x0d4a and codepoint <= 0x0d4c) or
        codepoint == 0x0d57 or
        // Khmer split/spaced dependent vowels are GCB=SpacingMark. They render
        // around or after the base consonant, so a cluster break before them
        // would expose an invalid low-level caret/shaping boundary.
        codepoint == 0x17b6 or
        (codepoint >= 0x17be and codepoint <= 0x17c5) or
        (codepoint >= 0x17c7 and codepoint <= 0x17c8) or
        (codepoint >= 0x102b and codepoint <= 0x102c) or
        codepoint == 0x1031 or
        codepoint == 0x1038 or
        (codepoint >= 0x103b and codepoint <= 0x103c) or
        (codepoint >= 0x1056 and codepoint <= 0x1057) or
        (codepoint >= 0x1062 and codepoint <= 0x1064) or
        (codepoint >= 0x1067 and codepoint <= 0x106d) or
        (codepoint >= 0x1083 and codepoint <= 0x1084) or
        (codepoint >= 0x1087 and codepoint <= 0x108c) or
        codepoint == 0x108f or
        (codepoint >= 0x109a and codepoint <= 0x109c) or
        // Myanmar Extended-B spacing tone signs are visible glyph cells but
        // still belong to the previous Myanmar base for grapheme/word/shaping
        // boundaries, matching the base-block spacing signs above.
        codepoint == 0xaa7b or
        codepoint == 0xaa7d or
        // Balinese spacing signs include visarga-like signs, visible dependent
        // vowels, and U+1B44 ADEG ADEG. They are typed after the base aksara
        // but must remain in the same grapheme/word/shaping unit.
        codepoint == 0x1b04 or
        codepoint == 0x1b35 or
        codepoint == 0x1b3b or
        (codepoint >= 0x1b3d and codepoint <= 0x1b41) or
        (codepoint >= 0x1b43 and codepoint <= 0x1b44) or
        // Lepcha subjoined letters, spacing vowels, and visible consonant signs
        // are encoded after the base but belong to the same orthographic
        // syllable for caret placement and shaping lookup boundaries.
        (codepoint >= 0x1c24 and codepoint <= 0x1c2b) or
        (codepoint >= 0x1c34 and codepoint <= 0x1c35) or
        // Javanese spacing signs include dependent vowels, consonant signs,
        // and U+A9C0 PANGKON. These visible signs still belong to the base
        // aksara for grapheme, word, and shaping-boundary purposes.
        codepoint == 0xa983 or
        (codepoint >= 0xa9b4 and codepoint <= 0xa9b5) or
        (codepoint >= 0xa9ba and codepoint <= 0xa9bb) or
        (codepoint >= 0xa9be and codepoint <= 0xa9c0) or
        // Limbu spacing vowels, subjoined letters, and visible final
        // consonant signs are GCB=SpacingMark. Keeping them attached avoids
        // exposing invalid boundaries inside syllables such as ᤁᤩ and ᤁᤠ.
        (codepoint >= 0x1923 and codepoint <= 0x1926) or
        (codepoint >= 0x1929 and codepoint <= 0x192b) or
        (codepoint >= 0x1930 and codepoint <= 0x1931) or
        (codepoint >= 0x1933 and codepoint <= 0x1938) or
        // Buginese U+1A19/U+1A1A are visible dependent vowels with
        // Grapheme_Cluster_Break=SpacingMark. They are encoded after the base
        // but belong to the same orthographic syllable for caret/word/layout
        // primitives.
        (codepoint >= 0x1a19 and codepoint <= 0x1a1a) or
        // Sundanese spacing signs include pangwisad/visarga-like signs and
        // visible dependent vowels. They are part of the same aksara syllable
        // even though they occupy spacing glyph cells, so do not expose a
        // grapheme or word boundary before them.
        codepoint == 0x1b82 or
        codepoint == 0x1ba1 or
        (codepoint >= 0x1ba6 and codepoint <= 0x1ba7) or
        codepoint == 0x1baa or
        // Meetei Mayek spacing vowel signs and visarga-like marks are visible
        // glyphs but still belong to the preceding base letter's grapheme,
        // word, and shaping unit. Include both encoded blocks so old and new
        // orthographies behave consistently.
        codepoint == 0xaaeb or
        (codepoint >= 0xaaee and codepoint <= 0xaaef) or
        codepoint == 0xaaf5 or
        (codepoint >= 0xabe3 and codepoint <= 0xabe4) or
        (codepoint >= 0xabe6 and codepoint <= 0xabe7) or
        (codepoint >= 0xabe9 and codepoint <= 0xabec) or
        // Cham visible dependent vowels and final H are GCB=SpacingMark. They
        // occupy spacing glyph cells, but still belong to the preceding Cham
        // base/final letter for low-level grapheme and shaping boundaries.
        (codepoint >= 0xaa2f and codepoint <= 0xaa30) or
        (codepoint >= 0xaa33 and codepoint <= 0xaa34) or
        codepoint == 0xaa4d or
        // Brahmi candrabindu and visarga are spacing signs encoded before the
        // letters in the same block but belong to adjacent Brahmi syllables for
        // UAX #29 grapheme and low-level shaping boundaries.
        codepoint == 0x11000 or
        codepoint == 0x11002;
}

fn scriptBelongsToRun(script: Script, current: Script) bool {
    // Common and inherited scripts adopt the current run script. If a run starts
    // as common, let the first strong script continue it.
    if (script == current) return true;
    if (script == .common or script == .inherited) return true;
    if (current == .common) return true;
    return false;
}

fn isCommonCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x0040) or
        (codepoint >= 0x005b and codepoint <= 0x0060) or
        (codepoint >= 0x007b and codepoint <= 0x00a9) or
        (codepoint >= 0x2000 and codepoint <= 0x206f) or
        (codepoint >= 0x3000 and codepoint <= 0x303f);
}
