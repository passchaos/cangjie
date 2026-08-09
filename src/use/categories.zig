const unicode = @import("../unicode.zig");
const category_data = @import("category_data.zig");

pub const Category = enum(u8) {
    other = 0,
    base = 1,
    base_num = 4,
    base_other = 5,
    cg_joiner = 6,
    cons_sub = 11,
    halant = 12,
    halant_num = 13,
    zwnj = 14,
    word_joiner = 16,
    repha = 18,
    vowel_pre = 22,
    vowel_mod_pre = 23,
    final_above = 24,
    final_below = 25,
    final_post = 26,
    medial_above = 27,
    medial_below = 28,
    medial_post = 29,
    medial_pre = 30,
    consonant_mod_above = 31,
    consonant_mod_below = 32,
    vowel_above = 33,
    vowel_below = 34,
    vowel_post = 35,
    vowel_mod_above = 37,
    vowel_mod_below = 38,
    vowel_mod_post = 39,
    symbol_mod_above = 41,
    symbol_mod_below = 42,
    cons_with_stacker = 43,
    invisible_stacker = 44,
    final_mod_above = 45,
    final_mod_below = 46,
    final_mod_post = 47,
    sakot = 48,
    hieroglyph = 49,
    hieroglyph_joiner = 50,
    hieroglyph_segment_begin = 51,
    hieroglyph_segment_end = 52,
    halant_or_vowel_mod = 53,
    hieroglyph_mod = 54,
    hieroglyph_mirror = 55,
    reordering_killer = 56,
};

pub fn forCodepoint(codepoint: u21) Category {
    return @enumFromInt(category_data.forCodepoint(codepoint));
}

pub fn isClusterBase(category: Category) bool {
    return switch (category) {
        .base, .base_other, .cons_with_stacker, .repha => true,
        else => false,
    };
}

pub fn isHalantLike(category: Category) bool {
    return switch (category) {
        .halant, .halant_or_vowel_mod, .invisible_stacker => true,
        else => false,
    };
}

pub fn isPrebaseVowel(category: Category) bool {
    return category == .vowel_pre or category == .vowel_mod_pre;
}

pub fn isPostbase(category: Category) bool {
    return switch (category) {
        .final_above,
        .final_below,
        .final_post,
        .final_mod_above,
        .final_mod_below,
        .final_mod_post,
        .medial_above,
        .medial_below,
        .medial_post,
        .medial_pre,
        .vowel_above,
        .vowel_below,
        .vowel_post,
        .vowel_pre,
        .vowel_mod_above,
        .vowel_mod_below,
        .vowel_mod_post,
        .vowel_mod_pre,
        => true,
        else => false,
    };
}

pub fn isUnicodeMarkForUse(codepoint: u21) bool {
    return unicode.isUnicodeMarkCodepoint(codepoint);
}

test "USE category covers Duployan sample codepoints" {
    try @import("std").testing.expectEqual(Category.base, forCodepoint(0x1bc02));
    try @import("std").testing.expectEqual(Category.base, forCodepoint(0x1bc5b));
    try @import("std").testing.expectEqual(Category.cg_joiner, forCodepoint(0x034f));
    try @import("std").testing.expectEqual(Category.zwnj, forCodepoint(0x200c));
    try @import("std").testing.expectEqual(Category.other, forCodepoint(0x002e));
}

test "Duployan affixes use HarfBuzz consonant category" {
    try @import("std").testing.expectEqual(Category.base, forCodepoint(0x1bc70));
    try @import("std").testing.expectEqual(Category.base, forCodepoint(0x1bc88));
    try @import("std").testing.expectEqual(Category.base, forCodepoint(0x1bc99));
}

test "Balinese USE categories distinguish a stacked consonant syllable" {
    const codepoints = [_]u21{ 0x1b15, 0x1b44, 0x1b16, 0x1b02 };
    const expected = [_]Category{ .base, .halant, .base, .vowel_mod_above };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Javanese USE categories distinguish prebase and medial signs" {
    const codepoints = [_]u21{ 0xa9a5, 0xa9ba, 0xa9c0, 0xa9bd, 0xa9be, 0xa980 };
    const expected = [_]Category{ .base, .vowel_pre, .halant, .medial_below, .medial_post, .vowel_mod_above };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Marchen USE categories distinguish subjoined letters and vowels" {
    const codepoints = [_]u21{ 0x11c72, 0x11c92, 0x11ca9, 0x11cb0, 0x11cb1, 0x11cb3, 0x11cb4, 0x11cb5 };
    const expected = [_]Category{ .base, .cons_sub, .cons_sub, .vowel_below, .vowel_pre, .vowel_above, .vowel_post, .vowel_mod_above };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Cham USE categories distinguish medial positions" {
    const codepoints = [_]u21{ 0xaa00, 0xaa29, 0xaa2d, 0xaa34, 0xaa35, 0xaa36, 0xaa43, 0xaa4d };
    const expected = [_]Category{ .base, .vowel_mod_above, .vowel_below, .medial_pre, .medial_above, .medial_below, .final_above, .final_post };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Batak USE categories distinguish vowels and reordering killers" {
    const codepoints = [_]u21{ 0x1bc7, 0x1be6, 0x1bea, 0x1bed, 0x1bf0, 0x1bf3 };
    const expected = [_]Category{ .base, .consonant_mod_above, .vowel_post, .vowel_above, .final_above, .reordering_killer };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Brahmi USE categories distinguish numbers and joiners" {
    const codepoints = [_]u21{ 0x11003, 0x11013, 0x1103c, 0x11046, 0x11052, 0x1107f };
    const expected = [_]Category{ .cons_with_stacker, .base, .vowel_below, .halant, .base_num, .halant_num };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Chakma USE categories distinguish stacker and vowels" {
    const codepoints = [_]u21{ 0x11103, 0x11127, 0x1112a, 0x1112c, 0x11133, 0x11134, 0x11145 };
    const expected = [_]Category{ .base, .vowel_below, .vowel_above, .vowel_pre, .invisible_stacker, .consonant_mod_above, .vowel_post };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Tai Tham USE categories distinguish sakot and medials" {
    const codepoints = [_]u21{ 0x1a20, 0x1a55, 0x1a56, 0x1a57, 0x1a60, 0x1a6e, 0x1a74, 0x1a7f };
    const expected = [_]Category{ .base, .medial_pre, .medial_below, .cons_sub, .sakot, .vowel_pre, .vowel_mod_above, .vowel_mod_below };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Newa USE categories distinguish virama and dependent signs" {
    const codepoints = [_]u21{ 0x1140e, 0x11436, 0x11438, 0x1143e, 0x11442, 0x11443, 0x11445, 0x11446, 0x1145e, 0x11460 };
    const expected = [_]Category{ .base, .vowel_pre, .vowel_below, .vowel_above, .halant, .vowel_mod_above, .vowel_mod_post, .consonant_mod_below, .final_mod_above, .cons_with_stacker };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Saurashtra USE categories distinguish haaru and virama" {
    const codepoints = [_]u21{ 0xa880, 0xa882, 0xa8b4, 0xa8b5, 0xa8c4, 0xa8c5, 0xa8d0 };
    const expected = [_]Category{ .vowel_mod_post, .base, .medial_post, .vowel_post, .halant, .vowel_mod_above, .base };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Grantha USE categories distinguish vowels and virama" {
    const codepoints = [_]u21{ 0x00b2, 0x11320, 0x1133b, 0x1133e, 0x11340, 0x11347, 0x1134d, 0x11367, 0x20f0 };
    const expected = [_]Category{ .final_mod_post, .base, .consonant_mod_below, .vowel_post, .vowel_above, .vowel_pre, .halant, .vowel_mod_above, .vowel_mod_above };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}

test "Sharada USE categories distinguish separator and sandhi mark" {
    const codepoints = [_]u21{ 0x11183, 0x111b4, 0x111b6, 0x111bc, 0x111c0, 0x111c2, 0x111c8, 0x111c9, 0x11b60, 0x11b61, 0x11b62 };
    const expected = [_]Category{ .base, .vowel_pre, .vowel_below, .vowel_above, .halant, .repha, .other, .final_mod_below, .vowel_above, .vowel_post, .vowel_below };

    for (codepoints, expected) |codepoint, category| {
        try @import("std").testing.expectEqual(category, forCodepoint(codepoint));
    }
}
