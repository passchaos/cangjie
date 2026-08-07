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
        0x200c => .zwnj,
        0x2060 => .word_joiner,
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
    return unicode.isSpacingMarkCodepoint(codepoint) or
        (codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x1bc9d and codepoint <= 0x1bc9e);
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
