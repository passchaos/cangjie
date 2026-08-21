//! Scalar-range facts used by the script classifier.
//!
//! These predicates intentionally remain policy-free. The classification order
//! in `root.zig` resolves overlaps such as Coptic letters inside the Greek block
//! and inherited selectors inside otherwise script-specific blocks.
//! Some scripts use whole assigned blocks because their shaping model applies to
//! letters, marks, digits, and native punctuation together; others enumerate
//! holes precisely so reserved scalars do not silently gain script or bidi
//! semantics. Preserve that distinction when updating Unicode coverage.

pub fn isVai(codepoint: u21) bool {
    return codepoint >= 0xa500 and codepoint <= 0xa63f;
}

pub fn isLisu(codepoint: u21) bool {
    return (codepoint >= 0xa4d0 and codepoint <= 0xa4ff) or
        codepoint == 0x11fb0;
}

pub fn isYi(codepoint: u21) bool {
    return (codepoint >= 0xa000 and codepoint <= 0xa48f) or
        (codepoint >= 0xa490 and codepoint <= 0xa4cf);
}

pub fn isBalinese(codepoint: u21) bool {
    return codepoint >= 0x1b00 and codepoint <= 0x1b7f;
}

pub fn isJavanese(codepoint: u21) bool {
    return codepoint >= 0xa980 and codepoint <= 0xa9df;
}

pub fn isTaiTham(codepoint: u21) bool {
    return codepoint >= 0x1a20 and codepoint <= 0x1aaf;
}

pub fn isMarchen(codepoint: u21) bool {
    return (codepoint >= 0x11c70 and codepoint <= 0x11c8f) or
        (codepoint >= 0x11c92 and codepoint <= 0x11ca7) or
        (codepoint >= 0x11ca9 and codepoint <= 0x11cb6);
}

pub fn isNewa(codepoint: u21) bool {
    // U+1145C and U+11462..U+1147F remain reserved.
    return codepoint >= 0x11400 and codepoint <= 0x11461 and
        codepoint != 0x1145c;
}

pub fn isKayahLi(codepoint: u21) bool {
    return codepoint >= 0xa900 and codepoint <= 0xa92f;
}

pub fn isSaurashtra(codepoint: u21) bool {
    return (codepoint >= 0xa880 and codepoint <= 0xa8c5) or
        (codepoint >= 0xa8ce and codepoint <= 0xa8d9);
}

pub fn isRejang(codepoint: u21) bool {
    return (codepoint >= 0xa930 and codepoint <= 0xa953) or
        codepoint == 0xa95f;
}

pub fn isGrantha(codepoint: u21) bool {
    // Script=Inherited U+1133B participates in Grantha shaping but must remain
    // inherited for script-run resolution.
    if (codepoint == 0x1133b) return false;
    return (codepoint >= 0x11300 and codepoint <= 0x11303) or
        (codepoint >= 0x11305 and codepoint <= 0x1130c) or
        (codepoint >= 0x1130f and codepoint <= 0x11310) or
        (codepoint >= 0x11313 and codepoint <= 0x11328) or
        (codepoint >= 0x1132a and codepoint <= 0x11330) or
        (codepoint >= 0x11332 and codepoint <= 0x11333) or
        (codepoint >= 0x11335 and codepoint <= 0x11340) or
        (codepoint >= 0x11341 and codepoint <= 0x11344) or
        (codepoint >= 0x11347 and codepoint <= 0x11348) or
        (codepoint >= 0x1134b and codepoint <= 0x1134d) or
        codepoint == 0x11350 or
        codepoint == 0x11357 or
        (codepoint >= 0x1135d and codepoint <= 0x11363) or
        (codepoint >= 0x11366 and codepoint <= 0x1136c) or
        (codepoint >= 0x11370 and codepoint <= 0x11374);
}

pub fn isLimbu(codepoint: u21) bool {
    return codepoint >= 0x1900 and codepoint <= 0x194f;
}

pub fn isSharada(codepoint: u21) bool {
    return (codepoint >= 0x11180 and codepoint <= 0x111df) or
        (codepoint >= 0x11b60 and codepoint <= 0x11b67);
}

pub fn isLepcha(codepoint: u21) bool {
    return (codepoint >= 0x1c00 and codepoint <= 0x1c37) or
        (codepoint >= 0x1c3b and codepoint <= 0x1c49) or
        (codepoint >= 0x1c4d and codepoint <= 0x1c4f);
}

pub fn isBuginese(codepoint: u21) bool {
    return codepoint >= 0x1a00 and codepoint <= 0x1a1f;
}

pub fn isSundanese(codepoint: u21) bool {
    return (codepoint >= 0x1b80 and codepoint <= 0x1bbf) or
        (codepoint >= 0x1cc0 and codepoint <= 0x1ccf);
}

pub fn isBatak(codepoint: u21) bool {
    return (codepoint >= 0x1bc0 and codepoint <= 0x1bf3) or
        (codepoint >= 0x1bfc and codepoint <= 0x1bff);
}

pub fn isMeeteiMayek(codepoint: u21) bool {
    return (codepoint >= 0xaae0 and codepoint <= 0xaaff) or
        (codepoint >= 0xabc0 and codepoint <= 0xabff);
}

pub fn isCanadianAboriginal(codepoint: u21) bool {
    return (codepoint >= 0x1400 and codepoint <= 0x167f) or
        (codepoint >= 0x18b0 and codepoint <= 0x18ff) or
        (codepoint >= 0x11ab0 and codepoint <= 0x11abf);
}

pub fn isCham(codepoint: u21) bool {
    return codepoint >= 0xaa00 and codepoint <= 0xaa5f;
}

pub fn isBrahmi(codepoint: u21) bool {
    return codepoint >= 0x11000 and codepoint <= 0x1107f;
}

pub fn isKaithi(codepoint: u21) bool {
    return (codepoint >= 0x11080 and codepoint <= 0x110c2) or
        codepoint == 0x110cd;
}

pub fn isChakma(codepoint: u21) bool {
    return (codepoint >= 0x11100 and codepoint <= 0x11134) or
        (codepoint >= 0x11136 and codepoint <= 0x11147);
}

pub fn isKhudawadi(codepoint: u21) bool {
    return (codepoint >= 0x112b0 and codepoint <= 0x112ea) or
        (codepoint >= 0x112f0 and codepoint <= 0x112f9);
}

pub fn isTirhuta(codepoint: u21) bool {
    return (codepoint >= 0x11480 and codepoint <= 0x114c7) or
        (codepoint >= 0x114d0 and codepoint <= 0x114d9);
}

pub fn isModi(codepoint: u21) bool {
    return (codepoint >= 0x11600 and codepoint <= 0x11644) or
        (codepoint >= 0x11650 and codepoint <= 0x11659);
}

pub fn isTakri(codepoint: u21) bool {
    return (codepoint >= 0x11680 and codepoint <= 0x116b9) or
        (codepoint >= 0x116c0 and codepoint <= 0x116c9);
}

pub fn isNushu(codepoint: u21) bool {
    return codepoint >= 0x1b170 and codepoint <= 0x1b2ff;
}

pub fn isRunic(codepoint: u21) bool {
    return codepoint >= 0x16a0 and codepoint <= 0x16ff;
}

pub fn isCoptic(codepoint: u21) bool {
    // Coptic is split between the Greek block, its dedicated block, and
    // supplementary Coptic Epact Numbers.
    return (codepoint >= 0x03e2 and codepoint <= 0x03ef) or
        (codepoint >= 0x2c80 and codepoint <= 0x2cff) or
        (codepoint >= 0x102e0 and codepoint <= 0x102ff);
}

pub fn isOgham(codepoint: u21) bool {
    return codepoint >= 0x1680 and codepoint <= 0x169c;
}

pub fn isDuployan(codepoint: u21) bool {
    return codepoint >= 0x1bc00 and codepoint <= 0x1bc9f;
}

pub fn isTangut(codepoint: u21) bool {
    return codepoint == 0x16fe0 or
        (codepoint >= 0x17000 and codepoint <= 0x18aff) or
        (codepoint >= 0x18d00 and codepoint <= 0x18d1e) or
        (codepoint >= 0x18d80 and codepoint <= 0x18df2);
}

pub fn isEgyptianHieroglyphs(codepoint: u21) bool {
    return (codepoint >= 0x13000 and codepoint <= 0x13455) or
        (codepoint >= 0x13460 and codepoint <= 0x143fa);
}

pub fn isCuneiform(codepoint: u21) bool {
    return (codepoint >= 0x12000 and codepoint <= 0x12399) or
        (codepoint >= 0x12400 and codepoint <= 0x12474) or
        (codepoint >= 0x12480 and codepoint <= 0x12543);
}

pub fn isSignWriting(codepoint: u21) bool {
    return (codepoint >= 0x1d800 and codepoint <= 0x1da8b) or
        (codepoint >= 0x1da9b and codepoint <= 0x1da9f) or
        (codepoint >= 0x1daa1 and codepoint <= 0x1daaf);
}

pub fn isBamum(codepoint: u21) bool {
    return (codepoint >= 0xa6a0 and codepoint <= 0xa6f7) or
        (codepoint >= 0x16800 and codepoint <= 0x16a38);
}

pub fn isAnatolianHieroglyphs(codepoint: u21) bool {
    return codepoint >= 0x14400 and codepoint <= 0x14646;
}

pub fn isKhitanSmallScript(codepoint: u21) bool {
    return (codepoint >= 0x18b00 and codepoint <= 0x18cd5) or
        codepoint == 0x18cff or
        codepoint == 0x16fe4;
}

pub fn isLinearA(codepoint: u21) bool {
    return (codepoint >= 0x10600 and codepoint <= 0x10736) or
        (codepoint >= 0x10740 and codepoint <= 0x10755) or
        (codepoint >= 0x10760 and codepoint <= 0x10767);
}

pub fn isBraille(codepoint: u21) bool {
    return codepoint >= 0x2800 and codepoint <= 0x28ff;
}

pub fn isMendeKikakui(codepoint: u21) bool {
    return (codepoint >= 0x1e800 and codepoint <= 0x1e8c4) or
        (codepoint >= 0x1e8c7 and codepoint <= 0x1e8d6);
}

pub fn isLinearB(codepoint: u21) bool {
    return (codepoint >= 0x10000 and codepoint <= 0x1000b) or
        (codepoint >= 0x1000d and codepoint <= 0x10026) or
        (codepoint >= 0x10028 and codepoint <= 0x1003a) or
        (codepoint >= 0x1003c and codepoint <= 0x1003d) or
        (codepoint >= 0x1003f and codepoint <= 0x1004d) or
        (codepoint >= 0x10050 and codepoint <= 0x1005d) or
        (codepoint >= 0x10080 and codepoint <= 0x100fa);
}

pub fn isMiao(codepoint: u21) bool {
    return (codepoint >= 0x16f00 and codepoint <= 0x16f4a) or
        (codepoint >= 0x16f4f and codepoint <= 0x16f87) or
        (codepoint >= 0x16f8f and codepoint <= 0x16f9f);
}

pub fn isPahawhHmong(codepoint: u21) bool {
    return (codepoint >= 0x16b00 and codepoint <= 0x16b45) or
        (codepoint >= 0x16b50 and codepoint <= 0x16b61) or
        (codepoint >= 0x16b63 and codepoint <= 0x16b77) or
        (codepoint >= 0x16b7d and codepoint <= 0x16b8f);
}

pub fn isOldHungarian(codepoint: u21) bool {
    return (codepoint >= 0x10c80 and codepoint <= 0x10cb2) or
        (codepoint >= 0x10cc0 and codepoint <= 0x10cf2) or
        (codepoint >= 0x10cfa and codepoint <= 0x10cff);
}

pub fn isCyproMinoan(codepoint: u21) bool {
    return codepoint >= 0x12f90 and codepoint <= 0x12ff2;
}

pub fn isBhaiksuki(codepoint: u21) bool {
    return (codepoint >= 0x11c00 and codepoint <= 0x11c08) or
        (codepoint >= 0x11c0a and codepoint <= 0x11c36) or
        (codepoint >= 0x11c38 and codepoint <= 0x11c45) or
        (codepoint >= 0x11c50 and codepoint <= 0x11c6c);
}

pub fn isSiddham(codepoint: u21) bool {
    return (codepoint >= 0x11580 and codepoint <= 0x115b5) or
        (codepoint >= 0x115b8 and codepoint <= 0x115dd);
}

pub fn isMedefaidrin(codepoint: u21) bool {
    return codepoint >= 0x16e40 and codepoint <= 0x16e9a;
}

pub fn isTangsa(codepoint: u21) bool {
    return (codepoint >= 0x16a70 and codepoint <= 0x16abe) or
        (codepoint >= 0x16ac0 and codepoint <= 0x16ac9);
}

pub fn isKawi(codepoint: u21) bool {
    return (codepoint >= 0x11f00 and codepoint <= 0x11f10) or
        (codepoint >= 0x11f12 and codepoint <= 0x11f3a) or
        (codepoint >= 0x11f3e and codepoint <= 0x11f5a);
}

pub fn isWarangCiti(codepoint: u21) bool {
    return (codepoint >= 0x118a0 and codepoint <= 0x118f2) or
        codepoint == 0x118ff;
}

pub fn isNewTaiLue(codepoint: u21) bool {
    return (codepoint >= 0x1980 and codepoint <= 0x19ab) or
        (codepoint >= 0x19b0 and codepoint <= 0x19da) or
        (codepoint >= 0x19de and codepoint <= 0x19df);
}

pub fn isSoyombo(codepoint: u21) bool {
    return codepoint >= 0x11a50 and codepoint <= 0x11aa2;
}

pub fn isDeseret(codepoint: u21) bool {
    return codepoint >= 0x10400 and codepoint <= 0x1044f;
}

pub fn isTuluTigalari(codepoint: u21) bool {
    return (codepoint >= 0x11380 and codepoint <= 0x11389) or
        codepoint == 0x1138b or codepoint == 0x1138e or
        (codepoint >= 0x11390 and codepoint <= 0x113b5) or
        codepoint == 0x113b7 or
        (codepoint >= 0x113b8 and codepoint <= 0x113c0) or
        codepoint == 0x113c2 or codepoint == 0x113c5 or
        (codepoint >= 0x113c7 and codepoint <= 0x113ca) or
        (codepoint >= 0x113cc and codepoint <= 0x113d8) or
        (codepoint >= 0x113e1 and codepoint <= 0x113e2);
}

pub fn isBopomofo(codepoint: u21) bool {
    return (codepoint >= 0x02ea and codepoint <= 0x02eb) or
        (codepoint >= 0x3105 and codepoint <= 0x312f) or
        (codepoint >= 0x31a0 and codepoint <= 0x31bf);
}

pub fn isMasaramGondi(codepoint: u21) bool {
    return (codepoint >= 0x11d00 and codepoint <= 0x11d06) or
        (codepoint >= 0x11d08 and codepoint <= 0x11d09) or
        (codepoint >= 0x11d0b and codepoint <= 0x11d36) or
        codepoint == 0x11d3a or
        (codepoint >= 0x11d3c and codepoint <= 0x11d47) or
        (codepoint >= 0x11d50 and codepoint <= 0x11d59);
}

pub fn isOldTurkic(codepoint: u21) bool {
    return codepoint >= 0x10c00 and codepoint <= 0x10c48;
}

pub fn isDivesAkuru(codepoint: u21) bool {
    return (codepoint >= 0x11900 and codepoint <= 0x11906) or
        codepoint == 0x11909 or
        (codepoint >= 0x1190c and codepoint <= 0x11913) or
        (codepoint >= 0x11915 and codepoint <= 0x11916) or
        (codepoint >= 0x11918 and codepoint <= 0x11935) or
        (codepoint >= 0x11937 and codepoint <= 0x11938) or
        (codepoint >= 0x1193b and codepoint <= 0x11946) or
        (codepoint >= 0x11950 and codepoint <= 0x11959);
}

pub fn isOsage(codepoint: u21) bool {
    return (codepoint >= 0x104b0 and codepoint <= 0x104d3) or
        (codepoint >= 0x104d8 and codepoint <= 0x104fb);
}

pub fn isTaiViet(codepoint: u21) bool {
    return (codepoint >= 0xaa80 and codepoint <= 0xaac2) or
        (codepoint >= 0xaadb and codepoint <= 0xaadf);
}

pub fn isZanabazarSquare(codepoint: u21) bool {
    return codepoint >= 0x11a00 and codepoint <= 0x11a47;
}

pub fn isNyiakengPuachueHmong(codepoint: u21) bool {
    return (codepoint >= 0x1e100 and codepoint <= 0x1e12c) or
        (codepoint >= 0x1e130 and codepoint <= 0x1e13d) or
        (codepoint >= 0x1e140 and codepoint <= 0x1e149) or
        codepoint == 0x1e14e or codepoint == 0x1e14f;
}

pub fn isVithkuqi(codepoint: u21) bool {
    return (codepoint >= 0x10570 and codepoint <= 0x1057a) or
        (codepoint >= 0x1057c and codepoint <= 0x1058a) or
        (codepoint >= 0x1058c and codepoint <= 0x10592) or
        (codepoint >= 0x10594 and codepoint <= 0x10595) or
        (codepoint >= 0x10597 and codepoint <= 0x105a1) or
        (codepoint >= 0x105a3 and codepoint <= 0x105b1) or
        (codepoint >= 0x105b3 and codepoint <= 0x105b9) or
        (codepoint >= 0x105bb and codepoint <= 0x105bc);
}

pub fn isGaray(codepoint: u21) bool {
    return (codepoint >= 0x10d40 and codepoint <= 0x10d65) or
        (codepoint >= 0x10d69 and codepoint <= 0x10d85) or
        (codepoint >= 0x10d8e and codepoint <= 0x10d8f);
}

pub fn isKharoshthi(codepoint: u21) bool {
    return (codepoint >= 0x10a00 and codepoint <= 0x10a03) or
        (codepoint >= 0x10a05 and codepoint <= 0x10a06) or
        (codepoint >= 0x10a0c and codepoint <= 0x10a13) or
        (codepoint >= 0x10a15 and codepoint <= 0x10a17) or
        (codepoint >= 0x10a19 and codepoint <= 0x10a35) or
        (codepoint >= 0x10a38 and codepoint <= 0x10a3a) or
        codepoint == 0x10a3f or
        (codepoint >= 0x10a40 and codepoint <= 0x10a48) or
        (codepoint >= 0x10a50 and codepoint <= 0x10a58);
}

pub fn isAhom(codepoint: u21) bool {
    return (codepoint >= 0x11700 and codepoint <= 0x1171a) or
        (codepoint >= 0x1171d and codepoint <= 0x1172b) or
        (codepoint >= 0x11730 and codepoint <= 0x11746);
}

pub fn isKhojki(codepoint: u21) bool {
    return (codepoint >= 0x11200 and codepoint <= 0x11211) or
        (codepoint >= 0x11213 and codepoint <= 0x11241);
}

pub fn isNandinagari(codepoint: u21) bool {
    return (codepoint >= 0x119a0 and codepoint <= 0x119a7) or
        (codepoint >= 0x119aa and codepoint <= 0x119d7) or
        (codepoint >= 0x119da and codepoint <= 0x119e4);
}

pub fn isGunjalaGondi(codepoint: u21) bool {
    return (codepoint >= 0x11d60 and codepoint <= 0x11d65) or
        (codepoint >= 0x11d67 and codepoint <= 0x11d68) or
        (codepoint >= 0x11d6a and codepoint <= 0x11d8e) or
        (codepoint >= 0x11d90 and codepoint <= 0x11d91) or
        (codepoint >= 0x11d93 and codepoint <= 0x11d98) or
        (codepoint >= 0x11da0 and codepoint <= 0x11da9);
}

pub fn isDogra(codepoint: u21) bool {
    return codepoint >= 0x11800 and codepoint <= 0x1183b;
}

pub fn isWancho(codepoint: u21) bool {
    return codepoint >= 0x1e2c0 and codepoint <= 0x1e2f9 or
        codepoint == 0x1e2ff;
}

pub fn isGurungKhema(codepoint: u21) bool {
    return codepoint >= 0x16100 and codepoint <= 0x16139;
}

pub fn isKiratRai(codepoint: u21) bool {
    return codepoint >= 0x16d40 and codepoint <= 0x16d79;
}

pub fn isPauCinHau(codepoint: u21) bool {
    return codepoint >= 0x11ac0 and codepoint <= 0x11af8;
}

pub fn isCypriot(codepoint: u21) bool {
    return (codepoint >= 0x10800 and codepoint <= 0x10805) or
        codepoint == 0x10808 or
        (codepoint >= 0x1080a and codepoint <= 0x10835) or
        (codepoint >= 0x10837 and codepoint <= 0x10838) or
        codepoint == 0x1083c or codepoint == 0x1083f;
}

pub fn isTaiYo(codepoint: u21) bool {
    return (codepoint >= 0x1e6c0 and codepoint <= 0x1e6de) or
        (codepoint >= 0x1e6e0 and codepoint <= 0x1e6f5) or
        codepoint == 0x1e6fe or codepoint == 0x1e6ff;
}

pub fn isTolongSiki(codepoint: u21) bool {
    return (codepoint >= 0x11db0 and codepoint <= 0x11ddb) or
        (codepoint >= 0x11de0 and codepoint <= 0x11de9);
}

pub fn isCaucasianAlbanian(codepoint: u21) bool {
    return (codepoint >= 0x10530 and codepoint <= 0x10563) or
        codepoint == 0x1056f;
}

pub fn isPhoenician(codepoint: u21) bool {
    return (codepoint >= 0x10900 and codepoint <= 0x1091b) or
        codepoint == 0x1091f;
}

pub fn isSamaritan(codepoint: u21) bool {
    return codepoint >= 0x0800 and codepoint <= 0x083e;
}

pub fn isMongolian(codepoint: u21) bool {
    return codepoint >= 0x1800 and codepoint <= 0x18af;
}

pub fn isNko(codepoint: u21) bool {
    return (codepoint >= 0x07c0 and codepoint <= 0x07fa) or
        (codepoint >= 0x07fd and codepoint <= 0x07ff);
}

pub fn isAdlam(codepoint: u21) bool {
    return (codepoint >= 0x1e900 and codepoint <= 0x1e94b) or
        (codepoint >= 0x1e950 and codepoint <= 0x1e959) or
        (codepoint >= 0x1e95e and codepoint <= 0x1e95f);
}

pub fn isThaana(codepoint: u21) bool {
    return codepoint >= 0x0780 and codepoint <= 0x07b1;
}

pub fn isThai(codepoint: u21) bool {
    return codepoint >= 0x0e01 and codepoint <= 0x0e5b;
}

pub fn isLao(codepoint: u21) bool {
    return codepoint >= 0x0e81 and codepoint <= 0x0edf;
}

pub fn isTagalog(codepoint: u21) bool {
    // Assigned Baybayin letters and dependent signs. U+1716..U+171E remain
    // reserved and must not silently acquire `tglg` shaping semantics.
    return (codepoint >= 0x1700 and codepoint <= 0x1715) or
        codepoint == 0x171f;
}

pub fn isHanunoo(codepoint: u21) bool {
    // U+1735/U+1736 are shared Philippine punctuation with Script=Common, not
    // Hanunoo. Keeping them out lets script-run inheritance choose the actual
    // neighboring writing system instead of forcing the `hano` ScriptList.
    return codepoint >= 0x1720 and codepoint <= 0x1734;
}

pub fn isBuhid(codepoint: u21) bool {
    return codepoint >= 0x1740 and codepoint <= 0x1753;
}

pub fn isTagbanwa(codepoint: u21) bool {
    // U+176D and U+1771 are reserved holes inside the block. Explicit ranges
    // prevent future assignments from silently changing shaping behavior.
    return (codepoint >= 0x1760 and codepoint <= 0x176c) or
        (codepoint >= 0x176e and codepoint <= 0x1770) or
        (codepoint >= 0x1772 and codepoint <= 0x1773);
}

pub fn isKhmer(codepoint: u21) bool {
    return (codepoint >= 0x1780 and codepoint <= 0x17ff) or
        (codepoint >= 0x19e0 and codepoint <= 0x19ff);
}

pub fn isMyanmar(codepoint: u21) bool {
    return (codepoint >= 0x1000 and codepoint <= 0x109f) or
        (codepoint >= 0xa9e0 and codepoint <= 0xa9fe) or
        (codepoint >= 0xaa60 and codepoint <= 0xaa7f) or
        (codepoint >= 0x116d0 and codepoint <= 0x116e3);
}

pub fn isSyriac(codepoint: u21) bool {
    return (codepoint >= 0x0700 and codepoint <= 0x074f) or
        (codepoint >= 0x0860 and codepoint <= 0x086f);
}

pub fn isMandaic(codepoint: u21) bool {
    return (codepoint >= 0x0840 and codepoint <= 0x085b) or
        codepoint == 0x085e;
}

pub fn isGeorgian(codepoint: u21) bool {
    return (codepoint >= 0x10a0 and codepoint <= 0x10ff) or
        (codepoint >= 0x1c90 and codepoint <= 0x1cbf) or
        (codepoint >= 0x2d00 and codepoint <= 0x2d2f);
}

pub fn isCherokee(codepoint: u21) bool {
    return (codepoint >= 0x13a0 and codepoint <= 0x13ff) or
        (codepoint >= 0xab70 and codepoint <= 0xabbf);
}

pub fn isTifinagh(codepoint: u21) bool {
    return (codepoint >= 0x2d30 and codepoint <= 0x2d67) or
        codepoint == 0x2d6f or
        codepoint == 0x2d70 or
        codepoint == 0x2d7f;
}

pub fn isTibetan(codepoint: u21) bool {
    return codepoint >= 0x0f00 and codepoint <= 0x0fff;
}

pub fn isPhagsPa(codepoint: u21) bool {
    return codepoint >= 0xa840 and codepoint <= 0xa877;
}

pub fn isEthiopic(codepoint: u21) bool {
    return (codepoint >= 0x1200 and codepoint <= 0x139f) or
        (codepoint >= 0x2d80 and codepoint <= 0x2ddf) or
        (codepoint >= 0xab00 and codepoint <= 0xab2f);
}

pub fn isBengali(codepoint: u21) bool {
    return codepoint >= 0x0980 and codepoint <= 0x09ff;
}

pub fn isGurmukhi(codepoint: u21) bool {
    return codepoint >= 0x0a00 and codepoint <= 0x0a7f;
}

pub fn isGujarati(codepoint: u21) bool {
    return codepoint >= 0x0a80 and codepoint <= 0x0aff;
}

pub fn isOdia(codepoint: u21) bool {
    return codepoint >= 0x0b00 and codepoint <= 0x0b7f;
}

pub fn isTelugu(codepoint: u21) bool {
    return codepoint >= 0x0c00 and codepoint <= 0x0c7f;
}

pub fn isKannada(codepoint: u21) bool {
    return codepoint >= 0x0c80 and codepoint <= 0x0cff;
}

pub fn isSinhala(codepoint: u21) bool {
    return codepoint >= 0x0d80 and codepoint <= 0x0dff;
}

pub fn isTamil(codepoint: u21) bool {
    return (codepoint >= 0x0b82 and codepoint <= 0x0bfa) or
        (codepoint >= 0x11fc0 and codepoint <= 0x11fff);
}

pub fn isMalayalam(codepoint: u21) bool {
    return codepoint >= 0x0d00 and codepoint <= 0x0d7f;
}

pub fn isArabic(codepoint: u21) bool {
    // Presentation Forms are compatibility encodings but retain Script=Arabic.
    return (codepoint >= 0x0600 and codepoint <= 0x06ff) or
        (codepoint >= 0x0750 and codepoint <= 0x077f) or
        (codepoint >= 0x0870 and codepoint <= 0x08ff) or
        (codepoint >= 0x10efd and codepoint <= 0x10eff) or
        (codepoint >= 0xfb50 and codepoint <= 0xfdff) or
        (codepoint >= 0xfe70 and codepoint <= 0xfefc);
}

pub fn isLatin(codepoint: u21) bool {
    return (codepoint >= 0x00c0 and codepoint <= 0x024f) or
        (codepoint >= 0x1d00 and codepoint <= 0x1d7f) or
        (codepoint >= 0x1d80 and codepoint <= 0x1dbf) or
        (codepoint >= 0x1e00 and codepoint <= 0x1eff) or
        (codepoint >= 0x2c60 and codepoint <= 0x2c7f) or
        (codepoint >= 0xa720 and codepoint <= 0xa7ff) or
        (codepoint >= 0xab30 and codepoint <= 0xab6f) or
        (codepoint >= 0x1df00 and codepoint <= 0x1dfff);
}

pub fn isGreek(codepoint: u21) bool {
    return (codepoint >= 0x0370 and codepoint <= 0x03ff) or
        (codepoint >= 0x1d200 and codepoint <= 0x1d245) or
        (codepoint >= 0x1f00 and codepoint <= 0x1fff) or
        (codepoint >= 0x10140 and codepoint <= 0x1018f);
}

pub fn isHebrew(codepoint: u21) bool {
    // Hebrew presentation forms are compatibility characters but retain their
    // Script property and must not split legacy shaping runs.
    return (codepoint >= 0x0590 and codepoint <= 0x05ff) or
        (codepoint >= 0xfb1d and codepoint <= 0xfb4f);
}

pub fn isArmenian(codepoint: u21) bool {
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

pub fn isCyrillic(codepoint: u21) bool {
    return (codepoint >= 0x0400 and codepoint <= 0x052f) or
        (codepoint >= 0x1c80 and codepoint <= 0x1c8f) or
        (codepoint >= 0x2de0 and codepoint <= 0x2dff) or
        (codepoint >= 0xa640 and codepoint <= 0xa69f) or
        (codepoint >= 0x1e030 and codepoint <= 0x1e08f);
}

pub fn isGlagolitic(codepoint: u21) bool {
    return (codepoint >= 0x2c00 and codepoint <= 0x2c5f) or
        (codepoint >= 0x1e000 and codepoint <= 0x1e02a);
}

pub fn isOldItalic(codepoint: u21) bool {
    return (codepoint >= 0x10300 and codepoint <= 0x10323) or
        (codepoint >= 0x1032d and codepoint <= 0x1032f);
}

pub fn isUgaritic(codepoint: u21) bool {
    return (codepoint >= 0x10380 and codepoint <= 0x1039d) or
        codepoint == 0x1039f;
}

pub fn isOldPersian(codepoint: u21) bool {
    return (codepoint >= 0x103a0 and codepoint <= 0x103c3) or
        (codepoint >= 0x103c8 and codepoint <= 0x103d5);
}

pub fn isAvestan(codepoint: u21) bool {
    return (codepoint >= 0x10b00 and codepoint <= 0x10b35) or
        (codepoint >= 0x10b39 and codepoint <= 0x10b3f);
}

pub fn isImperialAramaic(codepoint: u21) bool {
    return (codepoint >= 0x10840 and codepoint <= 0x10855) or
        (codepoint >= 0x10857 and codepoint <= 0x1085f);
}

pub fn isOldSouthArabian(codepoint: u21) bool {
    return codepoint >= 0x10a60 and codepoint <= 0x10a7f;
}

pub fn isOldNorthArabian(codepoint: u21) bool {
    return codepoint >= 0x10a80 and codepoint <= 0x10a9f;
}

pub fn isMeroiticHieroglyphs(codepoint: u21) bool {
    return codepoint >= 0x10980 and codepoint <= 0x1099f;
}

pub fn isMeroiticCursive(codepoint: u21) bool {
    return (codepoint >= 0x109a0 and codepoint <= 0x109b7) or
        (codepoint >= 0x109bc and codepoint <= 0x109cf) or
        (codepoint >= 0x109d2 and codepoint <= 0x109ff);
}
