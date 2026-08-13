const category_data = @import("category_data.zig");

/// Low-byte categories shared with HarfBuzz's Myanmar syllable machine.
///
/// Explicit integer values are part of the generated-table contract. Keep
/// additions synchronized with `hb-ot-shaper-myanmar-machine.rl`.
pub const Category = enum(u8) {
    other = 0,
    consonant = 1,
    independent_vowel = 2,
    dot_below = 3,
    halant = 4,
    zwnj = 5,
    zwj = 6,
    dependent_vowel = 7,
    syllable_modifier = 8,
    tone_a = 9,
    generic_base = 10,
    dotted_circle = 11,
    matra_post = 13,
    repha = 14,
    ra = 15,
    consonant_medial = 16,
    symbol = 17,
    consonant_with_stacker = 18,
    vowel_above = 20,
    vowel_below = 21,
    vowel_pre = 22,
    vowel_post = 23,
    robatic = 25,
    x_group = 26,
    y_group = 27,
    asat = 32,
    medial_ha = 35,
    medial_ra = 36,
    medial_wa = 37,
    medial_ya = 38,
    pwo_tone = 39,
    variation_selector = 40,
    medial_la = 41,
    syllable_modifier_post = 57,
};

pub fn forCodepoint(codepoint: u21) Category {
    return @enumFromInt(category_data.forCodepoint(codepoint));
}

pub fn isConsonant(category: Category) bool {
    return switch (category) {
        .consonant, .consonant_with_stacker, .ra, .independent_vowel, .generic_base, .dotted_circle => true,
        else => false,
    };
}

pub fn isJoiner(category: Category) bool {
    return category == .zwj or category == .zwnj;
}

test "Myanmar category helpers follow shaper consonant contract" {
    const testing = @import("std").testing;

    try testing.expect(isConsonant(forCodepoint(0x1000)));
    try testing.expect(isConsonant(forCodepoint(0x1021)));
    try testing.expect(!isConsonant(forCodepoint(0x1031)));
    try testing.expect(isJoiner(forCodepoint(0x200c)));
    try testing.expect(isJoiner(forCodepoint(0x200d)));
}

test {
    @import("std").testing.refAllDecls(@This());
}
