//! Legacy mark/extender tailoring used by word and shaping boundaries.
//!
//! This is deliberately not the Unicode General_Category=Mn set. It retains
//! Cangjie's established script coverage for source ownership and word
//! selection, including a few grapheme extenders that are not Mn.

pub fn contains(codepoint: u21) bool {
    // U+0300 is Unicode's first combining/mark scalar. Keep the compact
    // script-specific range chain out of ASCII and Latin-1 shaping loops.
    if (codepoint < 0x0300) return false;
    // One shift identifies the complete Devanagari block. It is worth
    // dispatching before the multi-script range chain because ordinary Hindi
    // letters dominate Indic shaping but are not marks; falling through would
    // test every earlier Latin/RTL/Tibetan mark family first.
    if (codepoint >> 7 == 0x12) return isDevanagariNonspacing(codepoint);
    // Likewise, Arabic shaping repeatedly asks this predicate while building
    // grapheme and bidi items. Resolve the base U+0600 block with its exact Mn
    // predicate before ordinary Arabic letters walk the complete Latin and
    // Hebrew mark chain. Arabic supplement/extended blocks remain in the
    // general chain because their sparse assignments cross block boundaries.
    if (codepoint >> 8 == 0x06) return isArabicBaseNonspacing(codepoint);
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
        // Syriac superscript alaph plus pointing/vowel marks are nonspacing
        // signs typed after right-to-left bases. Treat them as Extend so
        // grapheme, word, and shaping boundaries preserve one Syriac syllable
        // instead of separating a base letter from its diacritics.
        codepoint == 0x0711 or
        (codepoint >= 0x0730 and codepoint <= 0x074a) or
        // Samaritan vowels, reading marks, and epenthetic signs are nonspacing
        // marks in an RTL script. Treat them as Extend so caret, word, and
        // shaping primitives keep marked Samaritan letters under one `samr`
        // lookup boundary.
        (codepoint >= 0x0816 and codepoint <= 0x0819) or
        (codepoint >= 0x081b and codepoint <= 0x0823) or
        (codepoint >= 0x0825 and codepoint <= 0x0827) or
        (codepoint >= 0x0829 and codepoint <= 0x082d) or
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
        // N'Ko tone, nasalization, double-dot, and dantayalan signs are
        // nonspacing marks in an RTL cursive script. Keep them attached to the
        // preceding base so grapheme, word, and shaping boundaries preserve one
        // N'Ko syllable before OpenType `nko ` lookup selection.
        (codepoint >= 0x07eb and codepoint <= 0x07f3) or
        codepoint == 0x07fd or
        // Combining Glagolitic letters are encoded in the supplementary plane
        // and stack with BMP Glagolitic bases. Treat them as Extend so
        // manuscript-style abbreviations stay one grapheme, word, and shaping
        // unit under the `glag` OpenType script selection.
        (codepoint >= 0x1e000 and codepoint <= 0x1e02a) or
        // Ethiopic gemination/vowel-length marks are the script's only
        // nonspacing combining marks. They have GCB=Extend and must inherit
        // the preceding Ethiopic syllable's caret and shaping cluster.
        (codepoint >= 0x135d and codepoint <= 0x135f) or
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
        // Marchen subjoined consonants, nonspacing vowels, and nasal signs are
        // Extend characters in one orthographic stack.
        (codepoint >= 0x11c92 and codepoint <= 0x11ca7) or
        (codepoint >= 0x11caa and codepoint <= 0x11cb0) or
        (codepoint >= 0x11cb2 and codepoint <= 0x11cb3) or
        (codepoint >= 0x11cb5 and codepoint <= 0x11cb6) or
        // Newa dependent vowels, virama/anusvara, nukta, and sandhi mark use
        // Grapheme_Cluster_Break=Extend and remain with the preceding akshara.
        (codepoint >= 0x11438 and codepoint <= 0x1143f) or
        (codepoint >= 0x11442 and codepoint <= 0x11444) or
        codepoint == 0x11446 or
        codepoint == 0x1145e or
        // Saurashtra virama and candrabindu are nonspacing extenders.
        (codepoint >= 0xa8c4 and codepoint <= 0xa8c5) or
        // Grantha nonspacing marks plus its combining digit/letter additions
        // remain attached to the preceding base.
        (codepoint >= 0x11300 and codepoint <= 0x11301) or
        (codepoint >= 0x1133b and codepoint <= 0x1133c) or
        codepoint == 0x1133e or
        codepoint == 0x11340 or
        codepoint == 0x11357 or
        (codepoint >= 0x11366 and codepoint <= 0x1136c) or
        (codepoint >= 0x11370 and codepoint <= 0x11374) or
        // Sharada nonspacing vowels, sandhi/nukta, extra-short marks, and
        // Unicode 17 dependent-vowel additions use Grapheme_Cluster_Break=Extend.
        (codepoint >= 0x11180 and codepoint <= 0x11181) or
        (codepoint >= 0x111b6 and codepoint <= 0x111be) or
        (codepoint >= 0x111c9 and codepoint <= 0x111cc) or
        codepoint == 0x111cf or
        codepoint == 0x11b60 or
        (codepoint >= 0x11b62 and codepoint <= 0x11b64) or
        codepoint == 0x11b66 or
        // Khudawadi, Tirhuta, Modi, and Takri dependent signs use GCB=Extend.
        codepoint == 0x112df or
        (codepoint >= 0x112e3 and codepoint <= 0x112ea) or
        codepoint == 0x114b0 or
        (codepoint >= 0x114b3 and codepoint <= 0x114b8) or
        codepoint == 0x114ba or
        codepoint == 0x114bd or
        (codepoint >= 0x114bf and codepoint <= 0x114c0) or
        (codepoint >= 0x114c2 and codepoint <= 0x114c3) or
        (codepoint >= 0x11633 and codepoint <= 0x1163a) or
        codepoint == 0x1163d or
        (codepoint >= 0x1163f and codepoint <= 0x11640) or
        codepoint == 0x116ab or
        codepoint == 0x116ad or
        (codepoint >= 0x116b0 and codepoint <= 0x116b7) or
        // Common Vedic tone/cantillation marks inherit the surrounding
        // Brahmic script and remain in its grapheme/shaping cluster.
        (codepoint >= 0x1cd0 and codepoint <= 0x1cd2) or
        (codepoint >= 0x1cd4 and codepoint <= 0x1ce0) or
        (codepoint >= 0x1ce2 and codepoint <= 0x1ce8) or
        codepoint == 0x1ced or
        codepoint == 0x1cf4 or
        (codepoint >= 0x1cf8 and codepoint <= 0x1cf9) or
        (codepoint >= 0xa9bc and codepoint <= 0xa9bd) or
        // Kayah Li dependent vowels and tones are nonspacing marks. Keeping
        // them attached preserves one caret/word/shaping unit for syllables
        // such as ꤊꤦ and prevents tone marks from becoming standalone words.
        (codepoint >= 0xa926 and codepoint <= 0xa92d) or
        // Rejang dependent vowel/consonant signs are nonspacing signs typed
        // after a base letter. Keep them attached so caret, word, and shaping
        // primitives do not split one Rejang orthographic syllable.
        (codepoint >= 0xa947 and codepoint <= 0xa951) or
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
        // Tai Tham nonspacing medials, sakot, dependent vowels, and tone
        // marks form one orthographic stack with the preceding letter.
        codepoint == 0x1a56 or
        (codepoint >= 0x1a58 and codepoint <= 0x1a60) or
        codepoint == 0x1a62 or
        (codepoint >= 0x1a65 and codepoint <= 0x1a6c) or
        (codepoint >= 0x1a73 and codepoint <= 0x1a7c) or
        codepoint == 0x1a7f or
        // Sundanese nonspacing dependent signs and pamaeh are typed after the
        // base aksara but shape as one orthographic syllable. Treating them as
        // Extend preserves caret, word, and shaping boundaries for text such as
        // ᮊᮥ and final-consonant forms like ᮔ᮪.
        (codepoint >= 0x1ba2 and codepoint <= 0x1ba5) or
        (codepoint >= 0x1ba8 and codepoint <= 0x1ba9) or
        codepoint == 0x1bab or
        // Batak nonspacing vowel/consonant signs and tompi are typed after
        // base letters but form one aksara unit. Keep them as Extend so
        // caret, word, and shaping boundaries preserve Batak syllables.
        codepoint == 0x1be6 or
        (codepoint >= 0x1be8 and codepoint <= 0x1be9) or
        codepoint == 0x1bed or
        (codepoint >= 0x1bef and codepoint <= 0x1bf1) or
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
        // Kaithi vowel signs, virama, nukta, and initial nasalization signs are
        // combining marks. Treat them as Extend so caret and word primitives do
        // not split a Kaithi akshara before the `kthi` shaping pass sees it.
        (codepoint >= 0x11080 and codepoint <= 0x11081) or
        (codepoint >= 0x110b3 and codepoint <= 0x110b6) or
        (codepoint >= 0x110b9 and codepoint <= 0x110ba) or
        codepoint == 0x110c2 or
        // Chakma nonspacing vowel signs, virama, and nasal/visarga signs are
        // typed after the base but shape as one Indic-style orthographic unit
        // under `cakm`. Keeping them as Extend avoids caret/word boundaries
        // between a Chakma consonant and its dependent signs.
        (codepoint >= 0x11100 and codepoint <= 0x11102) or
        (codepoint >= 0x11127 and codepoint <= 0x1112b) or
        (codepoint >= 0x1112d and codepoint <= 0x11134) or
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

pub fn isDevanagariNonspacing(codepoint: u21) bool {
    return (codepoint >= 0x0900 and codepoint <= 0x0902) or
        codepoint == 0x093a or
        codepoint == 0x093c or
        (codepoint >= 0x0941 and codepoint <= 0x0948) or
        codepoint == 0x094d or
        (codepoint >= 0x0951 and codepoint <= 0x0957) or
        (codepoint >= 0x0962 and codepoint <= 0x0963);
}

pub fn isArabicBaseNonspacing(codepoint: u21) bool {
    return (codepoint >= 0x0610 and codepoint <= 0x061a) or
        (codepoint >= 0x064b and codepoint <= 0x065f) or
        codepoint == 0x0670 or
        (codepoint >= 0x06d6 and codepoint <= 0x06dc) or
        (codepoint >= 0x06df and codepoint <= 0x06e4) or
        (codepoint >= 0x06e7 and codepoint <= 0x06e8) or
        (codepoint >= 0x06ea and codepoint <= 0x06ed);
}
