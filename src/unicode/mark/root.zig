//! Unicode mark classification and Cangjie shaping-boundary tailoring.
//!
//! `nonspacing.zig` is generated from General_Category=Mn. `spacing.zig` and
//! `extender.zig` retain the visible-sign and historical source-boundary policy
//! used by Cangjie's supported shaping scripts. Keeping these notions distinct
//! prevents Grapheme_Cluster_Break-like tailoring from being mistaken for the
//! exact Mn property used to synthesize OpenType glyph classes.

const std = @import("std");
const extender = @import("extender.zig");
const nonspacing = @import("nonspacing.zig");
const spacing = @import("spacing.zig");

/// Return whether the scalar participates in Cangjie's retained mark/extender
/// policy for word and shaping-source boundaries.
pub const isExtender = extender.contains;

/// Return whether the scalar is a supported spacing mark or visible dependent
/// sign that remains attached to its preceding shaping unit.
pub const isSpacing = spacing.contains;

/// Return whether Unicode 17 assigns General_Category=Nonspacing_Mark (Mn).
///
/// This exact category is independent from grapheme/extender policy. OpenType
/// shapers use Mn to synthesize glyph classes when GDEF lacks GlyphClassDef.
pub fn isNonspacing(codepoint: u21) bool {
    if (codepoint < 0x0300) return false;
    // Preserve the hot Devanagari block dispatch used by Indic shaping.
    if (codepoint >> 7 == 0x12) {
        return extender.isDevanagariNonspacing(codepoint);
    }
    return nonspacing.contains(codepoint);
}

/// Return Cangjie's supported Unicode mark classification (Mn or retained Mc).
///
/// The spacing side deliberately tracks the shaping/caret repertoire supported
/// by this library rather than claiming to be a complete generated Mc table.
pub fn isUnicodeMark(codepoint: u21) bool {
    if (codepoint < 0x0300) return false;
    if (codepoint >> 7 == 0x12) {
        return extender.isDevanagariNonspacing(codepoint) or
            spacing.isDevanagari(codepoint);
    }
    return extender.contains(codepoint) or spacing.contains(codepoint);
}

/// Whether an RTL shaping scalar inherits the preceding source cluster.
///
/// Keep the Arabic range chain out of the mixed-direction scalar loop in the
/// caller: this path needs exact Arabic/Hebrew Mn coverage rather than the
/// broader all-script extender policy.
pub fn inheritsPreviousRtlCluster(codepoint: u21) bool {
    if (codepoint == 0x200d) return true;
    return isArabicNonspacing(codepoint) or isHebrewNonspacing(codepoint);
}

noinline fn isArabicNonspacing(codepoint: u21) bool {
    return extender.isArabicBaseNonspacing(codepoint) or
        (codepoint >= 0x0897 and codepoint <= 0x089f) or
        (codepoint >= 0x08ca and codepoint <= 0x08e1) or
        (codepoint >= 0x08e3 and codepoint <= 0x08ff) or
        (codepoint >= 0x10efd and codepoint <= 0x10eff);
}

fn isHebrewNonspacing(codepoint: u21) bool {
    return (codepoint >= 0x0591 and codepoint <= 0x05bd) or
        codepoint == 0x05bf or
        (codepoint >= 0x05c1 and codepoint <= 0x05c2) or
        (codepoint >= 0x05c4 and codepoint <= 0x05c5) or
        codepoint == 0x05c7;
}

test "mark predicates preserve lower boundaries and fast block dispatch" {
    for (0..0x0300) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        try std.testing.expect(!isExtender(scalar));
        try std.testing.expect(!isNonspacing(scalar));
        try std.testing.expect(!isUnicodeMark(scalar));
    }
    for (0..0x0903) |codepoint| {
        try std.testing.expect(!isSpacing(@intCast(codepoint)));
    }

    try std.testing.expect(isExtender(0x0300));
    try std.testing.expect(isNonspacing(0x0300));
    try std.testing.expect(isUnicodeMark(0x0300));
    try std.testing.expect(isSpacing(0x0903));
    try std.testing.expect(isUnicodeMark(0x0903));

    // Exhaust the Arabic block against generated Mn data so its fast extender
    // dispatch cannot classify ordinary letters or punctuation as marks.
    for (0x0600..0x0700) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        try std.testing.expectEqual(
            nonspacing.contains(scalar),
            extender.contains(scalar),
        );
    }

    // Exhaust Devanagari so both fast paths remain exact at every scalar.
    for (0x0900..0x0980) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        const expected_nonspacing = extender.isDevanagariNonspacing(scalar);
        const expected_spacing = spacing.isDevanagari(scalar);
        try std.testing.expectEqual(expected_nonspacing, isExtender(scalar));
        try std.testing.expectEqual(expected_nonspacing, isNonspacing(scalar));
        try std.testing.expectEqual(expected_spacing, isSpacing(scalar));
        try std.testing.expectEqual(
            expected_nonspacing or expected_spacing,
            isUnicodeMark(scalar),
        );
    }
}
