//! Spacing-mark and visible dependent-sign classification.
//!
//! The ranges preserve Cangjie's established caret, word, and shaping cluster
//! ownership. They intentionally include supported visible dependent signs, so
//! this policy is not presented as a complete generated General_Category=Mc
//! table.

pub fn contains(codepoint: u21) bool {
    // U+0903 DEVANAGARI SIGN VISARGA is the first Unicode spacing mark.
    if (codepoint < 0x0903) return false;
    if (codepoint >> 7 == 0x12) return isDevanagari(codepoint);
    return (codepoint >= 0x0982 and codepoint <= 0x0983) or
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
        // Miao / Pollard script vowel and tone signs are encoded after the base
        // letter but HarfBuzz's USE data keeps them in one shaping cluster.
        (codepoint >= 0x16f51 and codepoint <= 0x16f87) or
        (codepoint >= 0x16f8f and codepoint <= 0x16f92) or
        // Javanese spacing signs include dependent vowels, consonant signs,
        // and U+A9C0 PANGKON. These visible signs still belong to the base
        // aksara for grapheme, word, and shaping-boundary purposes.
        codepoint == 0xa983 or
        (codepoint >= 0xa9b4 and codepoint <= 0xa9b5) or
        (codepoint >= 0xa9ba and codepoint <= 0xa9bb) or
        (codepoint >= 0xa9be and codepoint <= 0xa9c0) or
        // Marchen subjoined YA and spacing vowels I/O share the preceding
        // letter's grapheme and shaping cluster.
        codepoint == 0x11ca9 or
        codepoint == 0x11cb1 or
        codepoint == 0x11cb4 or
        // Newa's visible dependent vowels and visarga are spacing marks within
        // the same grapheme and shaping cluster as their base.
        (codepoint >= 0x11435 and codepoint <= 0x11437) or
        (codepoint >= 0x11440 and codepoint <= 0x11441) or
        codepoint == 0x11445 or
        // Saurashtra anusvara/visarga, HAARU, and dependent vowels are visible
        // spacing marks in the same akshara as their base.
        (codepoint >= 0xa880 and codepoint <= 0xa881) or
        (codepoint >= 0xa8b4 and codepoint <= 0xa8c3) or
        // Grantha spacing vowels, anusvara/visarga, and virama share their
        // base's grapheme and shaping cluster.
        (codepoint >= 0x11302 and codepoint <= 0x11303) or
        codepoint == 0x1133f or
        (codepoint >= 0x11341 and codepoint <= 0x11344) or
        (codepoint >= 0x11347 and codepoint <= 0x11348) or
        (codepoint >= 0x1134b and codepoint <= 0x1134d) or
        (codepoint >= 0x11362 and codepoint <= 0x11363) or
        // Sharada visarga, spacing vowels, virama, prishthamatra E, and
        // Unicode 17 spacing vowel additions remain in their base's cluster.
        codepoint == 0x11182 or
        (codepoint >= 0x111b3 and codepoint <= 0x111b5) or
        (codepoint >= 0x111bf and codepoint <= 0x111c0) or
        codepoint == 0x111ce or
        codepoint == 0x11b61 or
        codepoint == 0x11b65 or
        codepoint == 0x11b67 or
        // Visible dependent signs for Khudawadi, Tirhuta, Modi, and Takri.
        (codepoint >= 0x112e0 and codepoint <= 0x112e2) or
        (codepoint >= 0x114b1 and codepoint <= 0x114b2) or
        codepoint == 0x114b9 or
        (codepoint >= 0x114bb and codepoint <= 0x114bc) or
        codepoint == 0x114be or
        codepoint == 0x114c1 or
        (codepoint >= 0x11630 and codepoint <= 0x11632) or
        (codepoint >= 0x1163b and codepoint <= 0x1163c) or
        codepoint == 0x1163e or
        codepoint == 0x116ac or
        (codepoint >= 0x116ae and codepoint <= 0x116af) or
        codepoint == 0x1ce1 or
        codepoint == 0x1cf7 or
        // Rejang final H and virama are visible spacing signs but still belong
        // to the previous base for grapheme, word, and shaping boundaries.
        (codepoint >= 0xa952 and codepoint <= 0xa953) or
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
        // Tai Tham spacing medials and vowels remain in the preceding base's
        // grapheme and shaping cluster.
        codepoint == 0x1a55 or
        codepoint == 0x1a57 or
        (codepoint >= 0x1a61 and codepoint <= 0x1a64) or
        (codepoint >= 0x1a6d and codepoint <= 0x1a72) or
        // Sundanese spacing signs include pangwisad/visarga-like signs and
        // visible dependent vowels. They are part of the same aksara syllable
        // even though they occupy spacing glyph cells, so do not expose a
        // grapheme or word boundary before them.
        codepoint == 0x1b82 or
        codepoint == 0x1ba1 or
        (codepoint >= 0x1ba6 and codepoint <= 0x1ba7) or
        codepoint == 0x1baa or
        // Batak spacing vowels and pangolat/panongonan are visible signs, but
        // they still belong to the previous base for grapheme, word, and
        // shaping-boundary purposes just like the nonspacing signs above.
        codepoint == 0x1be7 or
        (codepoint >= 0x1bea and codepoint <= 0x1bec) or
        codepoint == 0x1bee or
        (codepoint >= 0x1bf2 and codepoint <= 0x1bf3) or
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
        codepoint == 0x11002 or
        // Kaithi spacing vowel signs and visarga render as visible glyph cells
        // but still belong to the preceding base for grapheme/word/shaping
        // boundaries, matching the nonspacing Kaithi marks above.
        codepoint == 0x11082 or
        (codepoint >= 0x110b0 and codepoint <= 0x110b2) or
        (codepoint >= 0x110b7 and codepoint <= 0x110b8) or
        // Chakma spacing vowels are visible dependent signs. They still share
        // the previous Chakma base's caret and shaping unit, so include them in
        // the compact SpacingMark table beside the nonspacing Chakma signs.
        codepoint == 0x1112c or
        (codepoint >= 0x11145 and codepoint <= 0x11146);
}

pub fn isDevanagari(codepoint: u21) bool {
    return codepoint == 0x0903 or
        (codepoint >= 0x093e and codepoint <= 0x0940) or
        (codepoint >= 0x0949 and codepoint <= 0x094c);
}
