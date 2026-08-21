//! Unicode script classification used by shaping and text itemization.
//!
//! Exact Script values come from the generated Unicode 17 page table. Focused
//! range predicates remain for hot-path shaping traits such as Arabic joining,
//! while unassigned scalar values resolve to `.unknown`.

const data = @import("data.zig");

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
    todhri,
    manichaean,
    beria_erfe,
    hanifi_rohingya,
    carian,
    ol_chiki,
    shavian,
    yezidi,
    syloti_nagri,
    ol_onal,
    sunuwar,
    mro,
    old_permic,
    nag_mundari,
    sogdian,
    elbasan,
    nabataean,
    old_sogdian,
    osmanya,
    mahajani,
    multani,
    bassa_vah,
    sora_sompeng,
    tai_le,
    palmyrene,
    toto,
    inscriptional_parthian,
    lycian,
    psalter_pahlavi,
    chorasmian,
    gothic,
    inscriptional_pahlavi,
    lydian,
    hatran,
    old_uyghur,
    sidetic,
    makasar,
    elymaic,
    unknown,
};

pub inline fn forCodepoint(codepoint: u21) Script {
    // The generated, deduplicated page table is exact for every Unicode 17
    // assigned scalar and defaults all unassigned scalar values to Unknown.
    return @enumFromInt(data.scriptId(codepoint));
}

test "primary Arabic block follows the exact Script property" {
    const std = @import("std");
    try std.testing.expectEqual(Script.common, forCodepoint(0x060c));
    try std.testing.expectEqual(Script.arabic, forCodepoint(0x0627));
    try std.testing.expectEqual(Script.inherited, forCodepoint(0x064b));
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
    return switch (forCodepoint(codepoint)) {
        .arabic, .mongolian, .adlam, .phags_pa => true,
        else => false,
    };
}

/// Fast block proof used by the coarse compatibility bidi classifier.
pub inline fn isArabic(codepoint: u21) bool {
    return forCodepoint(codepoint) == .arabic;
}

/// Fast block proof used by the coarse compatibility bidi classifier.
pub inline fn isHebrew(codepoint: u21) bool {
    return forCodepoint(codepoint) == .hebrew;
}

/// Fast range proof used by the coarse compatibility bidi classifier.
pub inline fn isDevanagari(codepoint: u21) bool {
    return forCodepoint(codepoint) == .devanagari;
}

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
