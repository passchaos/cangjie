const unicode = @import("../unicode.zig");

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
    return switch (codepoint) {
        0x034f => .cg_joiner,
        // Keep these ranges in sync with the generated Unicode USE table.
        // Unlike general categories, USE categories encode the grammatical
        // role of each sign in the syllable state machine and reordering pass.
        0x1b00...0x1b02 => .vowel_mod_above,
        0x1b03 => .final_above,
        0x1b04 => .vowel_mod_post,
        0x1b05...0x1b33,
        0x1b45...0x1b4c,
        0x1b50...0x1b59,
        => .base,
        0x1b34 => .consonant_mod_above,
        0x1b35 => .vowel_post,
        0x1b36...0x1b37,
        0x1b3c...0x1b3d,
        0x1b42...0x1b43,
        => .vowel_above,
        0x1b38...0x1b3b => .vowel_below,
        0x1b3e...0x1b41 => .vowel_pre,
        0x1b44 => .halant,
        0x1b6b...0x1b73 => .symbol_mod_above,
        0x1bc0...0x1be5 => .base,
        0x1be6 => .consonant_mod_above,
        0x1be7,
        0x1bea...0x1bec,
        0x1bee,
        => .vowel_post,
        0x1be8...0x1be9,
        0x1bed,
        0x1bef,
        => .vowel_above,
        0x1bf0...0x1bf1 => .final_above,
        0x1bf2...0x1bf3 => .reordering_killer,
        0x1a20...0x1a54,
        0x1a80...0x1a89,
        0x1a90...0x1a99,
        => .base,
        0x1a55 => .medial_pre,
        0x1a56 => .medial_below,
        0x1a57,
        0x1a5b...0x1a5e,
        => .cons_sub,
        0x1a58...0x1a59 => .final_above,
        0x1a5a => .medial_above,
        0x1a60 => .sakot,
        0x1a61,
        0x1a63...0x1a64,
        0x1a6d,
        => .vowel_post,
        0x1a62,
        0x1a65...0x1a68,
        0x1a6b,
        0x1a73,
        0x1a7a,
        => .vowel_above,
        0x1a69...0x1a6a,
        0x1a6c,
        => .vowel_below,
        0x1a6e...0x1a72 => .vowel_pre,
        0x1a74...0x1a79,
        0x1a7b...0x1a7c,
        => .vowel_mod_above,
        0x1a7f => .vowel_mod_below,
        0x200b => .word_joiner,
        0x200c => .zwnj,
        // USE treats ZWJ like CGJ for syllable segmentation: both are filtered
        // out of the machine input while remaining visible to GSUB context.
        0x200d => .cg_joiner,
        0x2060 => .word_joiner,
        0xa980...0xa981 => .vowel_mod_above,
        0xa982 => .final_above,
        0xa983 => .vowel_mod_post,
        0xa984...0xa9b2,
        0xa9d0...0xa9d9,
        => .base,
        0xa9b3 => .consonant_mod_above,
        0xa9b4...0xa9b5 => .vowel_post,
        0xa9b6...0xa9b7,
        0xa9bc,
        => .vowel_above,
        0xa9b8...0xa9b9 => .vowel_below,
        0xa9ba...0xa9bb => .vowel_pre,
        0xa9bd,
        0xa9bf,
        => .medial_below,
        0xa9be => .medial_post,
        0xa9c0 => .halant,
        0xaa00...0xaa28,
        0xaa40...0xaa42,
        0xaa44...0xaa4b,
        0xaa50...0xaa59,
        => .base,
        0xaa29 => .vowel_mod_above,
        0xaa2a...0xaa2c,
        0xaa2e,
        0xaa31,
        => .vowel_above,
        0xaa2d,
        0xaa32,
        => .vowel_below,
        0xaa2f...0xaa30 => .vowel_pre,
        0xaa33 => .medial_post,
        0xaa34 => .medial_pre,
        0xaa35 => .medial_above,
        0xaa36 => .medial_below,
        0xaa43,
        0xaa4c,
        => .final_above,
        0xaa4d => .final_post,
        0x11000,
        0x11002,
        => .vowel_mod_post,
        0x11001 => .vowel_mod_above,
        0x11003...0x11004 => .cons_with_stacker,
        0x11005...0x11037,
        0x11066...0x1106f,
        0x11071...0x11072,
        0x11075,
        => .base,
        0x11038...0x1103b,
        0x11042...0x11045,
        0x11070,
        0x11073...0x11074,
        => .vowel_above,
        0x1103c...0x11041 => .vowel_below,
        0x11046 => .halant,
        0x11052...0x11065 => .base_num,
        0x1107f => .halant_num,
        0x11100...0x11102 => .vowel_mod_above,
        0x11103...0x11126,
        0x11136...0x1113f,
        0x11144,
        0x11147,
        => .base,
        0x11127...0x11129,
        0x1112d,
        0x11130,
        => .vowel_below,
        0x1112a...0x1112b,
        0x1112e...0x1112f,
        0x11131...0x11132,
        => .vowel_above,
        0x1112c => .vowel_pre,
        0x11133 => .invisible_stacker,
        0x11134 => .consonant_mod_above,
        0x11145...0x11146 => .vowel_post,
        0x11c72...0x11c8f => .base,
        0x11c92...0x11ca7,
        0x11ca9...0x11caf,
        => .cons_sub,
        0x11cb0,
        0x11cb2,
        => .vowel_below,
        0x11cb1 => .vowel_pre,
        0x11cb3 => .vowel_above,
        0x11cb4 => .vowel_post,
        0x11cb5...0x11cb6 => .vowel_mod_above,
        0x1bc00...0x1bc6a,
        0x1bc70...0x1bc7c,
        0x1bc80...0x1bc88,
        0x1bc90...0x1bc99,
        => .base,
        0x1bc9d...0x1bc9e => .consonant_mod_above,
        else => .other,
    };
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
