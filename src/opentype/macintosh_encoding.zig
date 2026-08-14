const std = @import("std");

/// Macintosh cmap format 0/2/4/6 language values store the Script Manager
/// language ID plus one. Turkish is language ID 17, therefore a cmap carrying
/// value 18 uses the Mac Turkish variant of the Roman encoding.
pub const turkish_cmap_language: u32 = 18;

/// Convert a Unicode scalar to the byte consumed by a Macintosh platform-1,
/// encoding-0 cmap.
///
/// OpenType calls this encoding "Roman", but its legacy `language` field can
/// select regional variants. The Turkish variant differs at seven byte slots;
/// all other language values retain the MacRoman behavior used by HarfBuzz and
/// HarfRust. A linear reverse scan is intentional: this path is only selected
/// for legacy one-byte fonts, keeps one authoritative byte-to-Unicode table,
/// and avoids another permanently duplicated sorted mapping.
pub fn unicodeToRomanByte(codepoint: u21, cmap_language: u32) ?u8 {
    if (codepoint < 0x80) return @intCast(codepoint);
    for (0x80..0x100) |byte| {
        if (romanByteToUnicode(@intCast(byte), cmap_language) == codepoint) {
            return @intCast(byte);
        }
    }
    return null;
}

/// Decode one platform-1, encoding-0 cmap character code to Unicode.
pub fn romanByteToUnicode(byte: u8, cmap_language: u32) u21 {
    if (byte < 0x80) return byte;
    if (cmap_language == turkish_cmap_language) {
        return switch (byte) {
            0xda => 0x011e, // LATIN CAPITAL LETTER G WITH BREVE
            0xdb => 0x011f, // LATIN SMALL LETTER G WITH BREVE
            0xdc => 0x0130, // LATIN CAPITAL LETTER I WITH DOT ABOVE
            0xdd => 0x0131, // LATIN SMALL LETTER DOTLESS I
            0xde => 0x015e, // LATIN CAPITAL LETTER S WITH CEDILLA
            0xdf => 0x015f, // LATIN SMALL LETTER S WITH CEDILLA
            0xf5 => 0xf8a0, // legacy Apple private-use logo slot
            else => mac_roman_high[byte - 0x80],
        };
    }
    return mac_roman_high[byte - 0x80];
}

// Classic Macintosh Roman, indexed by byte minus 0x80. Keeping the forward
// table in byte order also makes translated charmap enumeration deterministic.
const mac_roman_high = [_]u21{
    0x00c4, 0x00c5, 0x00c7, 0x00c9, 0x00d1, 0x00d6, 0x00dc, 0x00e1,
    0x00e0, 0x00e2, 0x00e4, 0x00e3, 0x00e5, 0x00e7, 0x00e9, 0x00e8,
    0x00ea, 0x00eb, 0x00ed, 0x00ec, 0x00ee, 0x00ef, 0x00f1, 0x00f3,
    0x00f2, 0x00f4, 0x00f6, 0x00f5, 0x00fa, 0x00f9, 0x00fb, 0x00fc,
    0x2020, 0x00b0, 0x00a2, 0x00a3, 0x00a7, 0x2022, 0x00b6, 0x00df,
    0x00ae, 0x00a9, 0x2122, 0x00b4, 0x00a8, 0x2260, 0x00c6, 0x00d8,
    0x221e, 0x00b1, 0x2264, 0x2265, 0x00a5, 0x00b5, 0x2202, 0x2211,
    0x220f, 0x03c0, 0x222b, 0x00aa, 0x00ba, 0x03a9, 0x00e6, 0x00f8,
    0x00bf, 0x00a1, 0x00ac, 0x221a, 0x0192, 0x2248, 0x2206, 0x00ab,
    0x00bb, 0x2026, 0x00a0, 0x00c0, 0x00c3, 0x00d5, 0x0152, 0x0153,
    0x2013, 0x2014, 0x201c, 0x201d, 0x2018, 0x2019, 0x00f7, 0x25ca,
    0x00ff, 0x0178, 0x2044, 0x20ac, 0x2039, 0x203a, 0xfb01, 0xfb02,
    0x2021, 0x00b7, 0x201a, 0x201e, 0x2030, 0x00c2, 0x00ca, 0x00c1,
    0x00cb, 0x00c8, 0x00cd, 0x00ce, 0x00cf, 0x00cc, 0x00d3, 0x00d4,
    0xf8ff, 0x00d2, 0x00da, 0x00db, 0x00d9, 0x0131, 0x02c6, 0x02dc,
    0x00af, 0x02d8, 0x02d9, 0x02da, 0x00b8, 0x02dd, 0x02db, 0x02c7,
};

test "Macintosh Turkish overrides only its seven Roman slots" {
    try std.testing.expectEqual(@as(?u8, 0xd2), unicodeToRomanByte(0x201c, turkish_cmap_language));
    try std.testing.expectEqual(@as(?u8, 0xda), unicodeToRomanByte(0x011e, turkish_cmap_language));
    try std.testing.expectEqual(@as(?u8, 0xdd), unicodeToRomanByte(0x0131, turkish_cmap_language));
    try std.testing.expectEqual(@as(?u8, 0xdf), unicodeToRomanByte(0x015f, turkish_cmap_language));
    try std.testing.expectEqual(@as(?u8, null), unicodeToRomanByte(0x2044, turkish_cmap_language));
    try std.testing.expectEqual(@as(?u8, 0xda), unicodeToRomanByte(0x2044, 0));

    for (0..0x100) |byte| {
        const encoded: u8 = @intCast(byte);
        const codepoint = romanByteToUnicode(encoded, turkish_cmap_language);
        try std.testing.expectEqual(encoded, unicodeToRomanByte(codepoint, turkish_cmap_language).?);
    }
}
