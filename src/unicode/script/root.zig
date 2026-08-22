//! Unicode script classification used by shaping and text itemization.
//!
//! Exact Script values come from the generated Unicode 17 page table. Focused
//! range predicates remain for hot-path shaping traits such as Arabic joining,
//! while unassigned scalar values resolve to `.unknown`.

const data = @import("data.zig");

pub const Script = @import("types.zig").Script;

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

/// Exact script proof used by the coarse compatibility bidi classifier.
pub inline fn isArabic(codepoint: u21) bool {
    return forCodepoint(codepoint) == .arabic;
}

/// Exact script proof used by the coarse compatibility bidi classifier.
pub inline fn isHebrew(codepoint: u21) bool {
    return forCodepoint(codepoint) == .hebrew;
}

/// Exact script proof used by the coarse compatibility bidi classifier.
pub inline fn isDevanagari(codepoint: u21) bool {
    return forCodepoint(codepoint) == .devanagari;
}

pub fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}
