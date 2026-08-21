const std = @import("std");
const line_break = @import("unicode/line_break/iterator.zig");
const grapheme_boundary = @import("unicode/grapheme/iterator.zig");
const word_boundary = @import("unicode/word/iterator.zig");
const word_selection = @import("unicode/word/selection.zig");
const sentence_boundary = @import("unicode/sentence/iterator.zig");
const joining = @import("unicode/joining.zig");
const mark = @import("unicode/mark/root.zig");
const script_mod = @import("unicode/script/root.zig");
const vertical = @import("unicode/vertical.zig");
const bidi_paragraph = @import("unicode/bidi/paragraph.zig");
const canonical_combining_class = @import("unicode/canonical_combining_class.zig");
const canonical_decomposition = @import("unicode/canonical_decomposition.zig");

/// Lightweight Unicode helpers used by the shaping/layout layers.
/// Boundary segmentation and bidirectional analysis use generated Unicode 17
/// datasets. Script and shaping-specific helper tables remain intentionally
/// focused on the scripts supported by Cangjie's OpenType pipeline.
pub const Script = script_mod.Script;

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

pub const ExactBidiClass = bidi_paragraph.Class;
pub const BidiBaseDirection = bidi_paragraph.BaseDirection;
pub const BidiParagraph = bidi_paragraph.Paragraph;
pub const bidi_unicode_version = bidi_paragraph.unicode_version;

pub const JoiningType = joining.Type;
pub const JoiningForm = joining.Form;

pub const VerticalOrientation = vertical.Orientation;
pub const vertical_orientation_unicode_version = vertical.unicode_version;

/// Complete Unicode 17 UAX #50 classifier.
pub fn verticalOrientationForCodepoint(codepoint: u21) VerticalOrientation {
    return vertical.orientation(codepoint);
}

pub fn verticalPresentationCodepoint(codepoint: u21) ?u21 {
    return vertical.presentationCodepoint(codepoint);
}

pub const joiningTypeForCodepoint = joining.typeForCodepoint;

const JoiningPolicy = struct {
    pub fn hasForms(codepoint: u21) bool {
        return script_mod.usesArabicJoiningForms(codepoint);
    }
};

/// Resolve Arabic-style positional forms in logical text order.
///
/// Script ownership remains in this root itemizer; the joining module receives
/// that policy as a comptime dependency and owns only property lookup and the
/// streaming state machine.
pub noinline fn resolveJoiningForms(
    codepoints: []const u21,
    forms: []JoiningForm,
) error{InvalidJoiningInput}!void {
    return joining.resolve(JoiningPolicy, codepoints, forms);
}

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
};

const BidiCluster = struct {
    scalar_start: usize,
    scalar_end: usize,
    level: u8,
};

pub fn isDefaultIgnorableForShaping(codepoint: u21) bool {
    // SOFT HYPHEN is the lowest default-ignorable scalar Cangjie preserves for
    // shaping. This authoritative lower bound lets the overwhelmingly common
    // ASCII path skip the remaining singleton and range comparisons.
    if (codepoint < 0x00ad) return false;
    return codepoint == 0x00ad or
        codepoint == 0x034f or
        codepoint == 0x061c or
        codepoint == 0x180e or
        (codepoint >= 0x180b and codepoint <= 0x180f) or
        (codepoint >= 0x200b and codepoint <= 0x200f) or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x206f) or
        (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        codepoint == 0xfeff or
        (codepoint >= 0xfff0 and codepoint <= 0xfff8) or
        (codepoint >= 0x1bca0 and codepoint <= 0x1bca3) or
        (codepoint >= 0x1d173 and codepoint <= 0x1d17a) or
        (codepoint >= 0xe0000 and codepoint <= 0xe0fff);
}

fn canonicalCombiningClass(codepoint: u21) u8 {
    return canonical_combining_class.forCodepoint(codepoint);
}

pub fn canonicalDecomposition(codepoint: u21) ?[]const u21 {
    return canonical_decomposition.forCodepoint(codepoint);
}

pub fn modifiedCombiningClassForShaping(codepoint: u21) u8 {
    // U+0300 is the first scalar with a non-zero canonical combining class,
    // and every shaping-specific override below is higher. Avoid searching the
    // generated CCC ranges for ASCII and Latin-1 text.
    if (codepoint < 0x0300) return 0;
    // Ordinary Arabic letters and punctuation occupy the dense U+0600 block
    // but have CCC=0. Only the disjoint authored mark ranges below can be
    // non-zero, so reject the common paragraph text before the generated
    // cross-Unicode binary search.
    if (codepoint >= 0x0600 and codepoint <= 0x08ff and
        !arabicCodepointMayHaveCombiningClass(codepoint))
    {
        return 0;
    }
    // Unicode 17 assigns non-zero CCC to only six scalars in the primary
    // Devanagari block. Ordinary letters and dependent vowels dominate Hindi
    // shaping, so avoid the generated cross-Unicode search for all other
    // U+0900..U+097F values.
    if (codepoint >= 0x0900 and codepoint <= 0x097f and
        codepoint != 0x093c and codepoint != 0x094d and
        (codepoint < 0x0951 or codepoint > 0x0954))
    {
        return 0;
    }
    // These script-specific overrides are part of HarfBuzz's normalization
    // contract. SAKOT and PADMA intentionally sort after ordinary tone/vowel
    // marks even though their canonical class is lower.
    return switch (codepoint) {
        0x1a60, 0x0fc6 => 254,
        0x0f39 => 127,
        else => modifiedCombiningClass(canonicalCombiningClass(codepoint)),
    };
}

fn arabicCodepointMayHaveCombiningClass(codepoint: u21) bool {
    return (codepoint >= 0x0610 and codepoint <= 0x061a) or
        (codepoint >= 0x064b and codepoint <= 0x065f) or
        codepoint == 0x0670 or
        (codepoint >= 0x06d6 and codepoint <= 0x06ed) or
        (codepoint >= 0x07eb and codepoint <= 0x07f3) or
        codepoint == 0x07fd or
        (codepoint >= 0x0816 and codepoint <= 0x082d) or
        (codepoint >= 0x0859 and codepoint <= 0x085b) or
        (codepoint >= 0x0897 and codepoint <= 0x089f) or
        (codepoint >= 0x08ca and codepoint <= 0x08ff);
}

fn modifiedCombiningClass(class: u8) u8 {
    return switch (class) {
        // Hebrew fixed-position classes follow SBL's practical mark order.
        10 => 22,
        11 => 15,
        12 => 16,
        13 => 17,
        14 => 23,
        15 => 18,
        16 => 19,
        17 => 20,
        18 => 21,
        19 => 14,
        20 => 24,
        21 => 12,
        22 => 25,
        23 => 13,
        24 => 10,
        25 => 11,
        26 => 26,
        // Move Arabic shadda (canonical class 33) before the other marks.
        27 => 28,
        28 => 29,
        29 => 30,
        30 => 31,
        31 => 32,
        32 => 33,
        33 => 27,
        34 => 34,
        35 => 35,
        // Telugu length marks must not reorder around the virama.
        84, 91 => 0,
        // Thai below vowels sort before U+0E3A.
        103 => 3,
        // Tibetan I/AA/U practical order.
        130 => 132,
        132 => 131,
        else => class,
    };
}

pub fn inheritsPreviousClusterInRtlShaping(codepoint: u21) bool {
    return mark.inheritsPreviousRtlCluster(codepoint);
}

pub const GraphemeCluster = grapheme_boundary.Cluster;

/// Zero-allocation Unicode 17.0 extended grapheme cluster iterator.
pub const GraphemeClusterIterator = grapheme_boundary.Iterator;
pub const grapheme_unicode_version = grapheme_boundary.unicode_version;

pub fn graphemeClusters(text: []const u8) error{InvalidUtf8}!GraphemeClusterIterator {
    return grapheme_boundary.clusters(text);
}

pub fn graphemeClustersAssumeValid(text: []const u8) GraphemeClusterIterator {
    return grapheme_boundary.assumeValid(text);
}

pub const WordBoundarySegment = word_boundary.Segment;
/// A selectable word span retained for editor/caret compatibility.
///
/// `wordSegments` exposes every UAX #29 segment and its `is_word` bit. This
/// compact type intentionally keeps the established word-only collector ABI.
pub const WordSegment = struct {
    byte_start: usize,
    byte_len: usize,
};
pub const WordBoundaryIterator = word_boundary.Iterator;
pub const word_unicode_version = word_boundary.unicode_version;

pub fn wordSegments(text: []const u8) word_boundary.Error!WordBoundaryIterator {
    return word_boundary.segments(text);
}

pub const SentenceSegment = sentence_boundary.Segment;
pub const SentenceBoundaryIterator = sentence_boundary.Iterator;
pub const sentence_unicode_version = sentence_boundary.unicode_version;

pub fn sentenceSegments(
    text: []const u8,
) sentence_boundary.Error!SentenceBoundaryIterator {
    return sentence_boundary.segments(text);
}

pub const LineBreakKind = line_break.BreakKind;
pub const LineBreak = line_break.Break;
pub const LineBreakIterator = line_break.Iterator;
pub const LineBreakClass = line_break.BreakClass;
pub const line_break_unicode_version = line_break.unicode_version;

pub fn lineBreaks(text: []const u8) line_break.Error!LineBreakIterator {
    return line_break.breaks(text);
}

pub fn lineBreaksAssumeValid(text: []const u8) LineBreakIterator {
    return line_break.breaksAssumeValid(text);
}

pub fn lineBreakClassForCodepoint(codepoint: u21) LineBreakClass {
    return line_break.classForCodepoint(codepoint);
}

pub const OpenTypeScriptTag = enum(u32) {
    dflt = tag("DFLT"),
    dflt_lower = tag("dflt"),
    latn = tag("latn"),
    grek = tag("grek"),
    cyrl = tag("cyrl"),
    glag = tag("glag"),
    ital = tag("ital"),
    ugar = tag("ugar"),
    xpeo = tag("xpeo"),
    avst = tag("avst"),
    armi = tag("armi"),
    sarb = tag("sarb"),
    narb = tag("narb"),
    mero = tag("mero"),
    merc = tag("merc"),
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
    samr = tag("samr"),
    mand = tag("mand"),
    armn = tag("armn"),
    thai = tag("thai"),
    lao = tag("lao "),
    tglg = tag("tglg"),
    hano = tag("hano"),
    buhd = tag("buhd"),
    tagb = tag("tagb"),
    khmr = tag("khmr"),
    qaag = tag("Qaag"),
    mym2 = tag("mym2"),
    mymr = tag("mymr"),
    dev3 = tag("dev3"),
    bng3 = tag("bng3"),
    ory3 = tag("ory3"),
    gur3 = tag("gur3"),
    gjr3 = tag("gjr3"),
    tel3 = tag("tel3"),
    knd3 = tag("knd3"),
    mlm3 = tag("mlm3"),
    tml3 = tag("tml3"),
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
    tml2 = tag("tml2"),
    deva = tag("deva"),
    beng = tag("beng"),
    orya = tag("orya"),
    guru = tag("guru"),
    gujr = tag("gujr"),
    telu = tag("telu"),
    knda = tag("knda"),
    mlym = tag("mlym"),
    ethi = tag("ethi"),
    geor = tag("geor"),
    cher = tag("cher"),
    tfng = tag("tfng"),
    tibt = tag("tibt"),
    phag = tag("phag"),
    nko = tag("nko "),
    thaa = tag("thaa"),
    adlm = tag("adlm"),
    mong = tag("mong"),
    bali = tag("bali"),
    java = tag("java"),
    lana = tag("lana"),
    marc = tag("marc"),
    newa = tag("newa"),
    kali = tag("kali"),
    saur = tag("saur"),
    rjng = tag("rjng"),
    gran = tag("gran"),
    limb = tag("limb"),
    shrd = tag("shrd"),
    lepc = tag("lepc"),
    bugi = tag("bugi"),
    sund = tag("sund"),
    batk = tag("batk"),
    mtei = tag("mtei"),
    cans = tag("cans"),
    cham = tag("cham"),
    brah = tag("brah"),
    kthi = tag("kthi"),
    cakm = tag("cakm"),
    sind = tag("sind"),
    tirh = tag("tirh"),
    modi = tag("modi"),
    takr = tag("takr"),
    nshu = tag("nshu"),
    runr = tag("runr"),
    copt = tag("copt"),
    ogam = tag("ogam"),
    dupl = tag("dupl"),
    tang = tag("tang"),
    egyp = tag("egyp"),
    xsux = tag("xsux"),
    sgnw = tag("sgnw"),
    bamu = tag("bamu"),
    hluw = tag("hluw"),
    kits = tag("kits"),
    lina = tag("lina"),
    brai = tag("brai"),
    mend = tag("mend"),
    linb = tag("linb"),
    plrd = tag("plrd"),
    hmng = tag("hmng"),
    hung = tag("hung"),
    cpmn = tag("cpmn"),
    bhks = tag("bhks"),
    sidd = tag("sidd"),
    medf = tag("medf"),
    tnsa = tag("tnsa"),
    kawi = tag("kawi"),
    wara = tag("wara"),
    talu = tag("talu"),
    soyo = tag("soyo"),
    dsrt = tag("dsrt"),
    tutg = tag("tutg"),
    bopo = tag("bopo"),
    gonm = tag("gonm"),
    orkh = tag("orkh"),
    diak = tag("diak"),
    osge = tag("osge"),
    tavt = tag("tavt"),
    zanb = tag("zanb"),
    hmnp = tag("hmnp"),
    vith = tag("vith"),
    gara = tag("gara"),
    khar = tag("khar"),
    ahom = tag("ahom"),
    khoj = tag("khoj"),
    nand = tag("nand"),
    gong = tag("gong"),
    dogr = tag("dogr"),
    wcho = tag("wcho"),
    gukh = tag("gukh"),
    krai = tag("krai"),
    pauc = tag("pauc"),
    cprt = tag("cprt"),
    tayo = tag("tayo"),
    tols = tag("tols"),
    aghb = tag("aghb"),
};

pub const ScriptTagCandidates = struct {
    tags: [3]OpenTypeScriptTag,
    len: u2,

    pub fn slice(self: *const ScriptTagCandidates) []const OpenTypeScriptTag {
        return self.tags[0..self.len];
    }
};

/// Return OpenType ScriptList candidates in HarfBuzz preference order.
///
/// Indic-v3 fonts deliberately select USE, while v2 and legacy tags select the
/// traditional Indic shaper. Keeping all candidates beside the semantic
/// Unicode script lets layout negotiate against each concrete font instead of
/// baking one OpenType generation into script itemization.
pub fn openTypeScriptTagCandidates(script: Script) ScriptTagCandidates {
    const primary = openTypeScriptTag(script);
    return switch (script) {
        .devanagari => .{ .tags = .{ .dev3, .dev2, .deva }, .len = 3 },
        .bengali => .{ .tags = .{ .bng3, .bng2, .beng }, .len = 3 },
        .odia => .{ .tags = .{ .ory3, .ory2, .orya }, .len = 3 },
        .gurmukhi => .{ .tags = .{ .gur3, .gur2, .guru }, .len = 3 },
        .gujarati => .{ .tags = .{ .gjr3, .gjr2, .gujr }, .len = 3 },
        .telugu => .{ .tags = .{ .tel3, .tel2, .telu }, .len = 3 },
        .kannada => .{ .tags = .{ .knd3, .knd2, .knda }, .len = 3 },
        .tamil => .{ .tags = .{ .tml3, .tml2, .taml }, .len = 3 },
        .malayalam => .{ .tags = .{ .mlm3, .mlm2, .mlym }, .len = 3 },
        .myanmar => .{ .tags = .{ .mym2, .mymr, .mymr }, .len = 2 },
        else => .{ .tags = .{ primary, primary, primary }, .len = 1 },
    };
}

pub const OpenTypeLanguageTag = enum(u32) {
    dflt = tag("dflt"),
    ara = tag("ARA "),
    far = tag("FAR "),
    jan = tag("JAN "),
    kor = tag("KOR "),
    zhh = tag("ZHH "),
    zhs = tag("ZHS "),
    zht = tag("ZHT "),
    hin = tag("HIN "),
    dhv = tag("DHV "),
};

pub const FeatureOverride = struct {
    tag: u32,
    enabled: bool,
    value: u32 = 1,

    pub fn effectiveValue(self: FeatureOverride) u32 {
        return if (self.enabled) self.value else 0;
    }
};

/// One OpenType GSUB feature value active for source clusters in
/// `[byte_start, byte_end)`. Offsets are UTF-8 bytes and later overlapping
/// entries with the same tag take precedence.
pub const GsubFeatureRange = @import("shaping/features/ranged_gsub/ranges.zig").Range;

/// Map the internal script enum to the OpenType script tag used for GSUB/GPOS
/// ScriptList selection.
pub fn openTypeScriptTag(script: Script) OpenTypeScriptTag {
    return switch (script) {
        .latin => .latn,
        .greek => .grek,
        .cyrillic => .cyrl,
        .glagolitic => .glag,
        .old_italic => .ital,
        .ugaritic => .ugar,
        .old_persian => .xpeo,
        .avestan => .avst,
        .imperial_aramaic => .armi,
        .old_south_arabian => .sarb,
        .old_north_arabian => .narb,
        .meroitic_hieroglyphs => .mero,
        .meroitic_cursive => .merc,
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
        .samaritan => .samr,
        .mandaic => .mand,
        .armenian => .armn,
        .thai => .thai,
        .lao => .lao,
        .tagalog => .tglg,
        .hanunoo => .hano,
        .buhid => .buhd,
        .tagbanwa => .tagb,
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
        .phags_pa => .phag,
        .nko => .nko,
        .thaana => .thaa,
        .adlam => .adlm,
        .mongolian => .mong,
        .balinese => .bali,
        .javanese => .java,
        .tai_tham => .lana,
        .marchen => .marc,
        .newa => .newa,
        .kayah_li => .kali,
        .saurashtra => .saur,
        .rejang => .rjng,
        .grantha => .gran,
        .limbu => .limb,
        .sharada => .shrd,
        .lepcha => .lepc,
        .buginese => .bugi,
        .sundanese => .sund,
        .batak => .batk,
        .meetei_mayek => .mtei,
        .canadian_aboriginal => .cans,
        .cham => .cham,
        .brahmi => .brah,
        .kaithi => .kthi,
        .chakma => .cakm,
        .khudawadi => .sind,
        .tirhuta => .tirh,
        .modi => .modi,
        .takri => .takr,
        .nushu => .nshu,
        .runic => .runr,
        .coptic => .copt,
        .ogham => .ogam,
        .duployan => .dupl,
        .tangut => .tang,
        .egyptian_hieroglyphs => .egyp,
        .cuneiform => .xsux,
        .signwriting => .sgnw,
        .bamum => .bamu,
        .anatolian_hieroglyphs => .hluw,
        .khitan_small_script => .kits,
        .linear_a => .lina,
        .braille => .brai,
        .mende_kikakui => .mend,
        .linear_b => .linb,
        .miao => .plrd,
        .pahawh_hmong => .hmng,
        .old_hungarian => .hung,
        .cypro_minoan => .cpmn,
        .bhaiksuki => .bhks,
        .siddham => .sidd,
        .medefaidrin => .medf,
        .tangsa => .tnsa,
        .kawi => .kawi,
        .warang_citi => .wara,
        .new_tai_lue => .talu,
        .soyombo => .soyo,
        .deseret => .dsrt,
        .tulu_tigalari => .tutg,
        .bopomofo => .bopo,
        .masaram_gondi => .gonm,
        .old_turkic => .orkh,
        .dives_akuru => .diak,
        .osage => .osge,
        .tai_viet => .tavt,
        .zanabazar_square => .zanb,
        .nyiakeng_puachue_hmong => .hmnp,
        .vithkuqi => .vith,
        .garay => .gara,
        .kharoshthi => .khar,
        .ahom => .ahom,
        .khojki => .khoj,
        .nandinagari => .nand,
        .gunjala_gondi => .gong,
        .dogra => .dogr,
        .wancho => .wcho,
        .gurung_khema => .gukh,
        .kirat_rai => .krai,
        .pau_cin_hau => .pauc,
        .cypriot => .cprt,
        .tai_yo => .tayo,
        .tolong_siki => .tols,
        .caucasian_albanian => .aghb,
        .common, .inherited, .unknown => .dflt,
    };
}

pub fn openTypeScriptHorizontalDirection(script_tag: OpenTypeScriptTag) ?BidiClass {
    return switch (script_tag) {
        .arab,
        .hebr,
        .phnx,
        .syrc,
        .samr,
        .mand,
        .nko,
        .thaa,
        .adlm,
        .ugar,
        .avst,
        .armi,
        .sarb,
        .narb,
        .mero,
        .merc,
        => .rtl,
        .dflt => null,
        else => .ltr,
    };
}

/// Script and language properties inferred together for OpenType selection.
pub const InferredOpenTypeProperties = struct {
    script: Script,
    language: OpenTypeLanguageTag,
    all_ascii: bool,
};

/// Infer only the first strong script, for callers that already have an
/// explicit language and therefore should not scan the remainder of the text.
pub fn inferOpenTypeScript(text: []const u8) Script {
    var cursor: usize = 0;
    while (cursor < text.len) {
        const decoded = decodeCodepointAt(text, cursor) orelse return .common;
        cursor = decoded.next;
        const script = scriptForCodepoint(decoded.codepoint);
        if (isStrongInferredScript(script)) return script;
    }
    return .common;
}

/// Infer the first strong script and the coarse default language in one scan.
///
/// Script selection needs the first non-Common/Inherited/Unknown script, while
/// language selection may inspect later content (for example Han followed by
/// Hiragana is Japanese). Keeping both decisions in one state machine avoids
/// decoding and classifying the same leading scalar twice during shaping.
pub fn inferOpenTypeProperties(text: []const u8) InferredOpenTypeProperties {
    var text_script: Script = .common;
    var saw_han = false;
    var all_ascii = true;
    var cursor: usize = 0;
    while (cursor < text.len) {
        if (text[cursor] < 0x80) {
            // No inferred non-default language uses an ASCII script. Once a
            // strong script is known, the remaining ASCII bytes therefore
            // require neither UTF-8 decoding nor Unicode Script lookup.
            if (text_script == .common) {
                const script = scriptForCodepoint(@intCast(text[cursor]));
                if (isStrongInferredScript(script)) text_script = script;
            }
            cursor += 1;
            continue;
        }

        all_ascii = false;
        const decoded = decodeCodepointAt(text, cursor) orelse return .{
            .script = text_script,
            .language = .dflt,
            .all_ascii = false,
        };
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
        const script = scriptForCodepoint(codepoint);
        if (text_script == .common and isStrongInferredScript(script)) {
            text_script = script;
        }
        switch (script) {
            .hiragana, .katakana => return .{ .script = text_script, .language = .jan, .all_ascii = false },
            .hangul => return .{ .script = text_script, .language = .kor, .all_ascii = false },
            .arabic => return .{ .script = text_script, .language = .ara, .all_ascii = false },
            .devanagari => return .{ .script = text_script, .language = .hin, .all_ascii = false },
            .bengali, .odia, .gurmukhi, .telugu, .kannada, .tamil, .thai, .lao => return .{ .script = text_script, .language = .dflt, .all_ascii = false },
            .han => saw_han = true,
            else => {},
        }
    }
    return .{
        .script = text_script,
        .language = if (saw_han) .zhs else .dflt,
        .all_ascii = all_ascii,
    };
}

fn isStrongInferredScript(script: Script) bool {
    return script != .common and script != .inherited and script != .unknown;
}

pub fn inferOpenTypeLanguageTag(text: []const u8) OpenTypeLanguageTag {
    return inferOpenTypeProperties(text).language;
}

/// Map a BCP47-ish locale tag to the OpenType language-system tags currently
/// modeled by this module. This is intentionally conservative: unsupported
/// languages return null so callers can fall back to content-based inference.
pub fn openTypeLanguageTagForLocale(locale_tag: []const u8) ?OpenTypeLanguageTag {
    var it = std.mem.tokenizeAny(u8, locale_tag, "-_");
    const language_raw = it.next() orelse return null;
    const language = canonicalLanguageAlias(language_raw);
    var script: ?[]const u8 = null;
    var region: ?[]const u8 = null;
    while (it.next()) |subtag| {
        if (script == null and isScriptSubtag(subtag)) {
            script = subtag;
            continue;
        }
        if (region == null and isRegionSubtag(subtag)) {
            region = subtag;
            continue;
        }
    }

    if (asciiEqlIgnoreCase(language, "ja")) return .jan;
    if (asciiEqlIgnoreCase(language, "ko")) return .kor;
    if (asciiEqlIgnoreCase(language, "ar")) return .ara;
    if (asciiEqlIgnoreCase(language, "fa")) return .far;
    if (asciiEqlIgnoreCase(language, "hi")) return .hin;
    if (asciiEqlIgnoreCase(language, "dv")) return .dhv;
    if (asciiEqlIgnoreCase(language, "zh")) {
        if (script) |script_value| {
            if (asciiEqlIgnoreCase(script_value, "Hant")) {
                if (region) |region_value| {
                    if (asciiEqlIgnoreCase(region_value, "HK") or asciiEqlIgnoreCase(region_value, "MO")) return .zhh;
                }
                return .zht;
            }
            if (asciiEqlIgnoreCase(script_value, "Hans")) return .zhs;
        }
        if (region) |region_value| {
            if (asciiEqlIgnoreCase(region_value, "HK") or asciiEqlIgnoreCase(region_value, "MO")) return .zhh;
            if (asciiEqlIgnoreCase(region_value, "TW")) return .zht;
        }
        return .zhs;
    }
    return null;
}

fn canonicalLanguageAlias(language: []const u8) []const u8 {
    if (asciiEqlIgnoreCase(language, "iw")) return "he";
    if (asciiEqlIgnoreCase(language, "in")) return "id";
    if (asciiEqlIgnoreCase(language, "ji")) return "yi";
    return language;
}

fn isScriptSubtag(subtag: []const u8) bool {
    if (subtag.len != 4) return false;
    for (subtag) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    return true;
}

fn isRegionSubtag(subtag: []const u8) bool {
    if (subtag.len == 2) {
        for (subtag) |byte| {
            if (!std.ascii.isAlphabetic(byte)) return false;
        }
        return true;
    }
    if (subtag.len == 3) {
        for (subtag) |byte| {
            if (!std.ascii.isDigit(byte)) return false;
        }
        return true;
    }
    return false;
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (std.ascii.toLower(lhs) != std.ascii.toLower(rhs)) return false;
    }
    return true;
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

pub const scriptForCodepoint = script_mod.forCodepoint;

/// Classify only strong LTR/RTL scripts and neutral punctuation/spacing. The
/// higher-level bidi functions use this coarse class to build visual runs.
pub fn bidiClassForCodepoint(codepoint: u21) BidiClass {
    if (bidiClassFast(codepoint)) |class| return class;
    return bidiClassForScript(scriptForCodepoint(codepoint));
}

pub fn exactBidiClassForCodepoint(codepoint: u21) ExactBidiClass {
    return bidi_paragraph.classForCodepoint(codepoint);
}

fn bidiClassFast(codepoint: u21) ?BidiClass {
    // This is the legacy four-class compatibility view, not the UAX #9 input
    // classifier. Exact paragraph analysis uses the generated property table.
    if (codepoint <= 0x7f) {
        if (codepoint >= '0' and codepoint <= '9') return .number;
        if ((codepoint >= 'A' and codepoint <= 'Z') or
            (codepoint >= 'a' and codepoint <= 'z'))
        {
            return .ltr;
        }
        return .neutral;
    }
    if ((codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9))
    {
        return .number;
    }
    if (script_mod.isArabic(codepoint) or
        script_mod.isHebrew(codepoint))
    {
        return .rtl;
    }
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .ltr;
    return null;
}

fn bidiClassForScript(script: Script) BidiClass {
    return switch (script) {
        .arabic, .hebrew, .phoenician, .syriac, .samaritan, .mandaic, .nko, .thaana, .adlam, .avestan, .imperial_aramaic, .old_south_arabian, .old_north_arabian, .meroitic_hieroglyphs, .meroitic_cursive, .old_hungarian, .old_turkic, .garay, .kharoshthi => .rtl,
        .latin, .greek, .cyrillic, .glagolitic, .old_italic, .ugaritic, .old_persian, .han, .yi, .lisu, .vai, .hiragana, .katakana, .hangul, .armenian, .thai, .lao, .tagalog, .hanunoo, .buhid, .tagbanwa, .khmer, .myanmar, .devanagari, .bengali, .odia, .gurmukhi, .gujarati, .telugu, .kannada, .sinhala, .tamil, .malayalam, .ethiopic, .georgian, .cherokee, .tifinagh, .tibetan, .phags_pa, .mongolian, .balinese, .javanese, .tai_tham, .marchen, .newa, .kayah_li, .saurashtra, .rejang, .grantha, .limbu, .sharada, .lepcha, .buginese, .sundanese, .batak, .meetei_mayek, .canadian_aboriginal, .cham, .brahmi, .kaithi, .chakma, .khudawadi, .tirhuta, .modi, .takri, .nushu, .runic, .coptic, .ogham, .duployan, .tangut, .egyptian_hieroglyphs, .cuneiform, .signwriting, .bamum, .anatolian_hieroglyphs, .khitan_small_script, .linear_a, .braille, .mende_kikakui, .linear_b, .miao, .pahawh_hmong, .cypro_minoan, .bhaiksuki, .siddham, .medefaidrin, .tangsa, .kawi, .warang_citi, .new_tai_lue, .soyombo, .deseret, .tulu_tigalari, .bopomofo, .masaram_gondi, .dives_akuru, .osage, .tai_viet, .zanabazar_square, .nyiakeng_puachue_hmong, .vithkuqi, .ahom, .khojki, .nandinagari, .gunjala_gondi, .dogra, .wancho, .gurung_khema, .kirat_rai, .pau_cin_hau, .cypriot, .tai_yo, .tolong_siki, .caucasian_albanian => .ltr,
        else => .neutral,
    };
}

/// Resolve a paragraph base direction from the first strong character.
/// Numbers and neutral formatting characters do not decide direction.
pub fn paragraphDirection(text: []const u8) error{InvalidUtf8}!BidiClass {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    var isolate_depth: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        switch (exactBidiClassForCodepoint(codepoint)) {
            .lri, .rli, .fsi => isolate_depth += 1,
            .pdi => if (isolate_depth != 0) {
                isolate_depth -= 1;
            },
            .l => if (isolate_depth == 0) return .ltr,
            .r, .al => if (isolate_depth == 0) return .rtl,
            .b => break,
            else => {},
        }
    }
    return .ltr;
}

pub fn resolveBidiParagraph(
    allocator: std.mem.Allocator,
    text: []const u8,
    base_direction: BidiBaseDirection,
) !BidiParagraph {
    return bidi_paragraph.resolve(allocator, text, base_direction);
}

pub fn itemizeBidiRuns(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]BidiRun {
    var paragraph = try resolveBidiParagraph(
        allocator,
        text,
        if (base_direction == .rtl) .rtl else .ltr,
    );
    defer paragraph.deinit();
    var runs = std.ArrayList(BidiRun).empty;
    errdefer runs.deinit(allocator);
    if (paragraph.scalars.len == 0) return try runs.toOwnedSlice(allocator);

    const cluster_levels = try graphemeClusterLevels(allocator, text, paragraph);
    defer allocator.free(cluster_levels);
    var run_start: usize = 0;
    var run_level = cluster_levels[0].level;
    for (cluster_levels[1..], 1..) |cluster, index| {
        const level = cluster.level;
        if (level == run_level) continue;
        const byte_start = paragraph.scalars[cluster_levels[run_start].scalar_start].byte_start;
        const byte_end = paragraph.scalars[cluster.scalar_start].byte_start;
        try runs.append(allocator, .{
            .direction = directionForLevel(run_level),
            .byte_start = byte_start,
            .byte_len = byte_end - byte_start,
        });
        run_start = index;
        run_level = level;
    }
    const byte_start = paragraph.scalars[cluster_levels[run_start].scalar_start].byte_start;
    try runs.append(allocator, .{
        .direction = directionForLevel(run_level),
        .byte_start = byte_start,
        .byte_len = text.len - byte_start,
    });
    return try runs.toOwnedSlice(allocator);
}

pub fn buildBidiMap(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) !BidiMap {
    // The map keeps both visual order and logical-to-visual lookup, which lets
    // editor code move between byte offsets and rendered caret positions.
    var paragraph = try resolveBidiParagraph(
        allocator,
        text,
        if (base_direction == .rtl) .rtl else .ltr,
    );
    defer paragraph.deinit();
    const cluster_order = try visualGraphemeClusters(allocator, text, paragraph);
    defer allocator.free(cluster_order.clusters);
    const order = cluster_order.order;
    defer allocator.free(order);

    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    const logical_to_visual = try allocator.alloc(usize, paragraph.scalars.len);
    errdefer allocator.free(logical_to_visual);

    for (order) |cluster_index| {
        const cluster = cluster_order.clusters[cluster_index];
        for (cluster.scalar_start..cluster.scalar_end) |logical_index| {
            const scalar = paragraph.scalars[logical_index];
            const visual_index = items.items.len;
            logical_to_visual[logical_index] = visual_index;
            try items.append(allocator, .{
                .logical_index = logical_index,
                .visual_index = visual_index,
                .byte_start = scalar.byte_start,
                .byte_len = scalar.byte_len,
                .codepoint = scalar.codepoint,
                .visual_codepoint = if (cluster.level & 1 != 0)
                    bidi_paragraph.mirroredCodepoint(scalar.codepoint)
                else
                    scalar.codepoint,
                .direction = directionForLevel(cluster.level),
            });
        }
    }

    return .{
        .allocator = allocator,
        .items = try items.toOwnedSlice(allocator),
        .logical_to_visual = logical_to_visual,
    };
}

const VisualClusters = struct {
    clusters: []BidiCluster,
    order: []usize,
};

fn graphemeClusterLevels(
    allocator: std.mem.Allocator,
    text: []const u8,
    paragraph: BidiParagraph,
) ![]BidiCluster {
    const graphemes = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    const result = try allocator.alloc(BidiCluster, graphemes.len);
    for (graphemes, result) |grapheme, *cluster| {
        const scalar_start = paragraph.scalarIndexForByte(grapheme.byte_start) orelse
            return error.InvalidBidiMap;
        const scalar_end = paragraph.scalarIndexForByte(
            grapheme.byte_start + grapheme.byte_len,
        ) orelse return error.InvalidBidiMap;
        var level: u8 = paragraph.base_level;
        for (paragraph.levels[scalar_start..scalar_end]) |candidate| {
            if (candidate == 0xff) continue;
            level = @max(level, candidate);
        }
        cluster.* = .{
            .scalar_start = scalar_start,
            .scalar_end = scalar_end,
            .level = level,
        };
    }
    return result;
}

fn visualGraphemeClusters(
    allocator: std.mem.Allocator,
    text: []const u8,
    paragraph: BidiParagraph,
) !VisualClusters {
    const clusters = try graphemeClusterLevels(allocator, text, paragraph);
    errdefer allocator.free(clusters);
    const order = try allocator.alloc(usize, clusters.len);
    errdefer allocator.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    reorderBidiClusters(clusters, order);
    return .{ .clusters = clusters, .order = order };
}

fn reorderBidiClusters(clusters: []const BidiCluster, order: []usize) void {
    var max_level: u8 = 0;
    var minimum_odd: u8 = 0xff;
    for (clusters) |cluster| {
        max_level = @max(max_level, cluster.level);
        if (cluster.level & 1 != 0) minimum_odd = @min(minimum_odd, cluster.level);
    }
    if (minimum_odd == 0xff) return;
    var level = max_level;
    while (true) : (level -= 1) {
        var cursor: usize = 0;
        while (cursor < order.len) {
            if (clusters[order[cursor]].level < level) {
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < order.len and clusters[order[cursor]].level >= level) {
                cursor += 1;
            }
            std.mem.reverse(usize, order[start..cursor]);
        }
        if (level == minimum_odd) break;
    }
}

pub fn itemizeGraphemeClusters(allocator: std.mem.Allocator, text: []const u8) ![]GraphemeCluster {
    var clusters = std.ArrayList(GraphemeCluster).empty;
    errdefer clusters.deinit(allocator);

    var iterator = try graphemeClusters(text);
    while (iterator.next()) |cluster| try clusters.append(allocator, cluster);
    return try clusters.toOwnedSlice(allocator);
}

pub fn itemizeWordSegments(allocator: std.mem.Allocator, text: []const u8) ![]WordSegment {
    // This collector is intentionally a compatibility tailoring for editor
    // word movement: it omits punctuation/whitespace and retains several
    // script-specific numeric/symbol ranges that users expect to select with
    // their neighboring letters. New code that needs standard UAX #29
    // boundaries, including every non-word segment, should use `wordSegments`.
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

pub fn itemizeLineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]LineBreak {
    var breaks = std.ArrayList(LineBreak).empty;
    errdefer breaks.deinit(allocator);

    var iterator = try lineBreaks(text);
    while (iterator.next()) |opportunity| {
        try breaks.append(allocator, opportunity);
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

fn directionForLevel(level: u8) BidiClass {
    return if (level & 1 == 0) .ltr else .rtl;
}

fn firstCodepoint(text: []const u8) ?u21 {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    return it.nextCodepoint();
}

pub fn mirroredCodepoint(codepoint: u21) u21 {
    return bidi_paragraph.mirroredCodepoint(codepoint);
}

const WordKind = word_selection.Kind;

fn wordKindForCodepoint(codepoint: u21) WordKind {
    const script: word_selection.Script = switch (scriptForCodepoint(codepoint)) {
        .han => .han,
        .yi => .yi,
        .nushu => .nushu,
        .hiragana => .hiragana,
        .katakana => .katakana,
        .hangul => .hangul,
        .tangut => .tangut,
        .egyptian_hieroglyphs => .egyptian_hieroglyphs,
        .cuneiform => .cuneiform,
        .signwriting => .signwriting,
        .bamum => .bamum,
        .anatolian_hieroglyphs => .anatolian_hieroglyphs,
        .khitan_small_script => .khitan_small_script,
        .linear_a => .linear_a,
        .braille => .braille,
        .mende_kikakui => .mende_kikakui,
        .linear_b => .linear_b,
        .miao => .miao,
        .pahawh_hmong => .pahawh_hmong,
        .old_hungarian => .old_hungarian,
        .cypro_minoan => .cypro_minoan,
        .bhaiksuki => .bhaiksuki,
        .siddham => .siddham,
        .medefaidrin => .medefaidrin,
        .tangsa => .tangsa,
        .kawi => .kawi,
        .warang_citi => .warang_citi,
        .new_tai_lue => .new_tai_lue,
        .soyombo => .soyombo,
        .deseret => .deseret,
        .tulu_tigalari => .tulu_tigalari,
        .bopomofo => .bopomofo,
        .masaram_gondi => .masaram_gondi,
        .old_turkic => .old_turkic,
        .dives_akuru => .dives_akuru,
        .osage => .osage,
        .tai_viet => .tai_viet,
        .zanabazar_square => .zanabazar_square,
        .nyiakeng_puachue_hmong => .nyiakeng_puachue_hmong,
        .vithkuqi => .vithkuqi,
        .garay => .garay,
        .kharoshthi => .kharoshthi,
        .ahom => .ahom,
        .khojki => .khojki,
        .nandinagari => .nandinagari,
        .gunjala_gondi => .gunjala_gondi,
        .dogra => .dogra,
        .wancho => .wancho,
        .gurung_khema => .gurung_khema,
        .kirat_rai => .kirat_rai,
        .pau_cin_hau => .pau_cin_hau,
        .cypriot => .cypriot,
        .tai_yo => .tai_yo,
        .tolong_siki => .tolong_siki,
        .caucasian_albanian => .caucasian_albanian,
        .tagalog => .tagalog,
        .hanunoo => .hanunoo,
        .buhid => .buhid,
        .tagbanwa => .tagbanwa,
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
        .khudawadi => .khudawadi,
        .tirhuta => .tirhuta,
        .modi => .modi,
        .takri => .takri,
        else => .other,
    };
    return word_selection.kindForCodepoint(codepoint, script);
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

const isCombiningMark = mark.isExtender;

pub const isVariationSelector = script_mod.isVariationSelector;

pub fn isMongolianFreeVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0x180b and codepoint <= 0x180d) or codepoint == 0x180f;
}

fn isEmojiModifier(codepoint: u21) bool {
    return codepoint >= 0x1f3fb and codepoint <= 0x1f3ff;
}

fn isRegionalIndicator(codepoint: u21) bool {
    return codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff;
}

pub const isSpacingMarkCodepoint = mark.isSpacing;

/// Return whether Unicode assigns General_Category=Nonspacing_Mark (Mn).
///
/// This is intentionally independent from grapheme Extend. OpenType shapers
/// use Mn to synthesize glyph classes when GDEF lacks a GlyphClassDef.
pub const isNonspacingMarkCodepoint = mark.isNonspacing;

pub const isUnicodeMarkCodepoint = mark.isUnicodeMark;

fn isEmojiTagCodepoint(codepoint: u21) bool {
    // Emoji flag tag sequences (for example subdivision flags such as England)
    // encode their tag letters in Plane 14. Unicode assigns these scalars
    // Grapheme_Cluster_Break=Extend, so they must stay attached to the
    // preceding pictograph instead of creating one caret stop per tag byte.
    return codepoint >= 0xe0020 and codepoint <= 0xe007f;
}

const isSpacingMark = mark.isSpacing;

fn scriptBelongsToRun(script: Script, current: Script) bool {
    // Common and inherited scripts adopt the current run script. If a run starts
    // as common, let the first strong script continue it.
    if (script == current) return true;
    if (script == .common or script == .inherited) return true;
    if (current == .common) return true;
    return false;
}

test {
    _ = @import("unicode/tests_contracts.zig");
    _ = @import("unicode/tests_rtl_scripts.zig");
    _ = @import("unicode/tests_segmentation.zig");
    _ = @import("unicode/tests_indic_use.zig");
    _ = @import("unicode/tests_scripts_core.zig");
    _ = @import("unicode/tests_scripts_extended.zig");
}
