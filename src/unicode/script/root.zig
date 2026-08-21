//! Unicode script classification used by shaping and text itemization.
//!
//! The classifier owns ordering-sensitive decisions such as Coptic-before-Greek
//! and variation-selector inheritance. Scalar range facts live in `ranges.zig`
//! so callers consume semantic answers rather than individual block tests.
//! This is intentionally the script repertoire supported by Cangjie's shaping
//! pipeline, not a replacement for the complete generated Unicode Script
//! property. Unmodeled and reserved scalars remain `.unknown`.

const ranges = @import("ranges.zig");

pub const Script = enum {
    common,
    inherited,
    latin,
    greek,
    cyrillic,
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
    samaritan,
    mandaic,
    armenian,
    thai,
    lao,
    tagalog,
    hanunoo,
    buhid,
    tagbanwa,
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
    phags_pa,
    nko,
    thaana,
    adlam,
    mongolian,
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
    cham,
    brahmi,
    kaithi,
    chakma,
    khudawadi,
    tirhuta,
    modi,
    takri,
    nushu,
    runic,
    coptic,
    ogham,
    duployan,
    tangut,
    egyptian_hieroglyphs,
    cuneiform,
    signwriting,
    bamum,
    anatolian_hieroglyphs,
    khitan_small_script,
    linear_a,
    braille,
    mende_kikakui,
    linear_b,
    miao,
    pahawh_hmong,
    old_hungarian,
    cypro_minoan,
    bhaiksuki,
    siddham,
    medefaidrin,
    tangsa,
    kawi,
    warang_citi,
    new_tai_lue,
    soyombo,
    deseret,
    tulu_tigalari,
    bopomofo,
    masaram_gondi,
    old_turkic,
    dives_akuru,
    osage,
    tai_viet,
    zanabazar_square,
    nyiakeng_puachue_hmong,
    vithkuqi,
    garay,
    kharoshthi,
    ahom,
    khojki,
    nandinagari,
    gunjala_gondi,
    dogra,
    wancho,
    gurung_khema,
    kirat_rai,
    pau_cin_hau,
    cypriot,
    tai_yo,
    tolong_siki,
    caucasian_albanian,
    unknown,
};

pub fn forCodepoint(codepoint: u21) Script {
    // The primary Arabic block is disjoint from every earlier specialized
    // script predicate. Keep it ahead of the long supplementary-script chain
    // so ordinary Arabic letters and marks do not execute dozens of unrelated
    // range tests during itemization. Other Arabic ranges remain at the
    // overlap-sensitive classifier position below.
    if (codepoint >= 0x0600 and codepoint <= 0x06ff) return .arabic;
    if ((codepoint >= 'A' and codepoint <= 'Z') or
        (codepoint >= 'a' and codepoint <= 'z') or
        ranges.isLatin(codepoint))
    {
        return .latin;
    }

    // Unicode variation selectors have Script=Inherited. Classify them before
    // block-specific tests so FE0E/FE0F and supplementary IVS selectors stay
    // attached to the base script run as well as its grapheme cluster.
    if (isVariationSelector(codepoint)) return .inherited;
    if (ranges.isCoptic(codepoint)) return .coptic;
    if (ranges.isGreek(codepoint)) return .greek;
    if (ranges.isCyrillic(codepoint)) return .cyrillic;
    if (ranges.isGlagolitic(codepoint)) return .glagolitic;
    if (ranges.isOldItalic(codepoint)) return .old_italic;
    if (ranges.isUgaritic(codepoint)) return .ugaritic;
    if (ranges.isOldPersian(codepoint)) return .old_persian;
    if (ranges.isAvestan(codepoint)) return .avestan;
    if (ranges.isImperialAramaic(codepoint)) return .imperial_aramaic;
    if (ranges.isOldSouthArabian(codepoint)) return .old_south_arabian;
    if (ranges.isOldNorthArabian(codepoint)) return .old_north_arabian;
    if (ranges.isMeroiticHieroglyphs(codepoint)) return .meroitic_hieroglyphs;
    if (ranges.isMeroiticCursive(codepoint)) return .meroitic_cursive;
    if ((codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        codepoint == 0x1133b)
    {
        return .inherited;
    }
    if (ranges.isHebrew(codepoint)) return .hebrew;
    if (ranges.isPhoenician(codepoint)) return .phoenician;
    if (ranges.isSyriac(codepoint)) return .syriac;
    if (ranges.isSamaritan(codepoint)) return .samaritan;
    if (ranges.isMandaic(codepoint)) return .mandaic;
    if (ranges.isArmenian(codepoint)) return .armenian;
    if (ranges.isArabic(codepoint)) return .arabic;
    if (ranges.isThai(codepoint)) return .thai;
    if (ranges.isLao(codepoint)) return .lao;
    if (ranges.isTagalog(codepoint)) return .tagalog;
    if (ranges.isHanunoo(codepoint)) return .hanunoo;
    if (ranges.isBuhid(codepoint)) return .buhid;
    if (ranges.isTagbanwa(codepoint)) return .tagbanwa;
    if (ranges.isKhmer(codepoint)) return .khmer;
    if (ranges.isMyanmar(codepoint)) return .myanmar;
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .devanagari;
    if (ranges.isBengali(codepoint)) return .bengali;
    if (ranges.isOdia(codepoint)) return .odia;
    if (ranges.isGurmukhi(codepoint)) return .gurmukhi;
    if (ranges.isGujarati(codepoint)) return .gujarati;
    if (ranges.isTelugu(codepoint)) return .telugu;
    if (ranges.isKannada(codepoint)) return .kannada;
    if (ranges.isSinhala(codepoint)) return .sinhala;
    if (ranges.isTamil(codepoint)) return .tamil;
    if (ranges.isMalayalam(codepoint)) return .malayalam;
    if (ranges.isEthiopic(codepoint)) return .ethiopic;
    if (ranges.isGeorgian(codepoint)) return .georgian;
    if (ranges.isCherokee(codepoint)) return .cherokee;
    if (ranges.isTifinagh(codepoint)) return .tifinagh;
    if (ranges.isTibetan(codepoint)) return .tibetan;
    if (ranges.isPhagsPa(codepoint)) return .phags_pa;
    if (ranges.isThaana(codepoint)) return .thaana;
    if (ranges.isNko(codepoint)) return .nko;
    if (ranges.isAdlam(codepoint)) return .adlam;
    if (ranges.isMongolian(codepoint)) return .mongolian;
    if (ranges.isBalinese(codepoint)) return .balinese;
    if (ranges.isJavanese(codepoint)) return .javanese;
    if (ranges.isTaiTham(codepoint)) return .tai_tham;
    if (ranges.isMarchen(codepoint)) return .marchen;
    if (ranges.isNewa(codepoint)) return .newa;
    if (ranges.isKayahLi(codepoint)) return .kayah_li;
    if (ranges.isSaurashtra(codepoint)) return .saurashtra;
    if (ranges.isRejang(codepoint)) return .rejang;
    if (ranges.isGrantha(codepoint)) return .grantha;
    if (ranges.isLimbu(codepoint)) return .limbu;
    if (ranges.isSharada(codepoint)) return .sharada;
    if (ranges.isLepcha(codepoint)) return .lepcha;
    if (ranges.isBuginese(codepoint)) return .buginese;
    if (ranges.isSundanese(codepoint)) return .sundanese;
    if (ranges.isBatak(codepoint)) return .batak;
    if (ranges.isMeeteiMayek(codepoint)) return .meetei_mayek;
    if (ranges.isCanadianAboriginal(codepoint)) return .canadian_aboriginal;
    if (ranges.isCham(codepoint)) return .cham;
    if (ranges.isBrahmi(codepoint)) return .brahmi;
    if (ranges.isKaithi(codepoint)) return .kaithi;
    if (ranges.isChakma(codepoint)) return .chakma;
    if (ranges.isKhudawadi(codepoint)) return .khudawadi;
    if (ranges.isTirhuta(codepoint)) return .tirhuta;
    if (ranges.isModi(codepoint)) return .modi;
    if (ranges.isTakri(codepoint)) return .takri;
    if (ranges.isNushu(codepoint)) return .nushu;
    if (ranges.isRunic(codepoint)) return .runic;
    if (ranges.isOgham(codepoint)) return .ogham;
    if (ranges.isDuployan(codepoint)) return .duployan;
    if (ranges.isTangut(codepoint)) return .tangut;
    if (ranges.isEgyptianHieroglyphs(codepoint)) return .egyptian_hieroglyphs;
    if (ranges.isCuneiform(codepoint)) return .cuneiform;
    if (ranges.isSignWriting(codepoint)) return .signwriting;
    if (ranges.isBamum(codepoint)) return .bamum;
    if (ranges.isAnatolianHieroglyphs(codepoint)) return .anatolian_hieroglyphs;
    if (ranges.isKhitanSmallScript(codepoint)) return .khitan_small_script;
    if (ranges.isLinearA(codepoint)) return .linear_a;
    if (ranges.isBraille(codepoint)) return .braille;
    if (ranges.isMendeKikakui(codepoint)) return .mende_kikakui;
    if (ranges.isLinearB(codepoint)) return .linear_b;
    if (ranges.isMiao(codepoint)) return .miao;
    if (ranges.isPahawhHmong(codepoint)) return .pahawh_hmong;
    if (ranges.isOldHungarian(codepoint)) return .old_hungarian;
    if (ranges.isCyproMinoan(codepoint)) return .cypro_minoan;
    if (ranges.isBhaiksuki(codepoint)) return .bhaiksuki;
    if (ranges.isSiddham(codepoint)) return .siddham;
    if (ranges.isMedefaidrin(codepoint)) return .medefaidrin;
    if (ranges.isTangsa(codepoint)) return .tangsa;
    if (ranges.isKawi(codepoint)) return .kawi;
    if (ranges.isWarangCiti(codepoint)) return .warang_citi;
    if (ranges.isNewTaiLue(codepoint)) return .new_tai_lue;
    if (ranges.isSoyombo(codepoint)) return .soyombo;
    if (ranges.isDeseret(codepoint)) return .deseret;
    if (ranges.isTuluTigalari(codepoint)) return .tulu_tigalari;
    if (ranges.isBopomofo(codepoint)) return .bopomofo;
    if (ranges.isMasaramGondi(codepoint)) return .masaram_gondi;
    if (ranges.isOldTurkic(codepoint)) return .old_turkic;
    if (ranges.isDivesAkuru(codepoint)) return .dives_akuru;
    if (ranges.isOsage(codepoint)) return .osage;
    if (ranges.isTaiViet(codepoint)) return .tai_viet;
    if (ranges.isZanabazarSquare(codepoint)) return .zanabazar_square;
    if (ranges.isNyiakengPuachueHmong(codepoint)) return .nyiakeng_puachue_hmong;
    if (ranges.isVithkuqi(codepoint)) return .vithkuqi;
    if (ranges.isGaray(codepoint)) return .garay;
    if (ranges.isKharoshthi(codepoint)) return .kharoshthi;
    if (ranges.isAhom(codepoint)) return .ahom;
    if (ranges.isKhojki(codepoint)) return .khojki;
    if (ranges.isNandinagari(codepoint)) return .nandinagari;
    if (ranges.isGunjalaGondi(codepoint)) return .gunjala_gondi;
    if (ranges.isDogra(codepoint)) return .dogra;
    if (ranges.isWancho(codepoint)) return .wancho;
    if (ranges.isGurungKhema(codepoint)) return .gurung_khema;
    if (ranges.isKiratRai(codepoint)) return .kirat_rai;
    if (ranges.isPauCinHau(codepoint)) return .pau_cin_hau;
    if (ranges.isCypriot(codepoint)) return .cypriot;
    if (ranges.isTaiYo(codepoint)) return .tai_yo;
    if (ranges.isTolongSiki(codepoint)) return .tolong_siki;
    if (ranges.isCaucasianAlbanian(codepoint)) return .caucasian_albanian;
    if (codepoint >= 0x3040 and codepoint <= 0x309f) return .hiragana;
    if (codepoint >= 0x30a0 and codepoint <= 0x30ff) return .katakana;

    // Katakana is also encoded in phonetic-extension and halfwidth forms.
    if (codepoint >= 0x31f0 and codepoint <= 0x31ff) return .katakana;
    if (codepoint >= 0xff66 and codepoint <= 0xff9d) return .katakana;
    if (codepoint == 0xff9e or codepoint == 0xff9f) return .inherited;

    // Modern and archaic Hangul Jamo select the Hangul shaping script before
    // composition into precomposed syllables.
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
    if (ranges.isYi(codepoint)) return .yi;
    if (ranges.isLisu(codepoint)) return .lisu;
    if (ranges.isVai(codepoint)) return .vai;
    if (isCommon(codepoint)) return .common;
    return .unknown;
}

test "primary Arabic block keeps the Arabic script fast path" {
    const std = @import("std");
    try std.testing.expectEqual(Script.arabic, forCodepoint(0x060c));
    try std.testing.expectEqual(Script.arabic, forCodepoint(0x0627));
    try std.testing.expectEqual(Script.arabic, forCodepoint(0x064b));
    try std.testing.expectEqual(Script.arabic, forCodepoint(0x06ff));
    // Adjacent non-Arabic scalars must retain their existing classifications.
    try std.testing.expectEqual(Script.hebrew, forCodepoint(0x05d0));
    try std.testing.expectEqual(Script.common, forCodepoint(' '));
}

/// Whether a scalar belongs to a script that applies Arabic-style positional
/// OpenType forms. This is intentionally narrower than Joining_Type coverage:
/// join-causing and transparent controls can influence neighbors without
/// receiving a positional form themselves.
pub fn usesArabicJoiningForms(codepoint: u21) bool {
    return ranges.isArabic(codepoint) or
        ranges.isMongolian(codepoint) or
        ranges.isAdlam(codepoint) or
        ranges.isPhagsPa(codepoint);
}

/// Fast block proof used by the coarse compatibility bidi classifier.
pub const isArabic = ranges.isArabic;

/// Fast block proof used by the coarse compatibility bidi classifier.
pub const isHebrew = ranges.isHebrew;

pub fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn isCommon(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x0040) or
        (codepoint >= 0x005b and codepoint <= 0x0060) or
        (codepoint >= 0x007b and codepoint <= 0x00a9) or
        (codepoint >= 0x1735 and codepoint <= 0x1736) or
        (codepoint >= 0x2000 and codepoint <= 0x206f) or
        (codepoint >= 0x3000 and codepoint <= 0x303f);
}
