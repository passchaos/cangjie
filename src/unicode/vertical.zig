//! UAX #50 vertical orientation policy and compatibility presentation forms.

pub const Orientation = enum {
    upright,
    rotated,
    transformed_upright,
    transformed_rotated,
};

/// Classify one scalar after the caller has resolved script membership.
///
/// `upright_script` is true for script families whose ordinary letters remain
/// upright in vertical text. Accepting that proof keeps this policy independent
/// of the repository's larger script itemizer.
pub fn orientation(codepoint: u21, upright_script: bool) Orientation {
    if (codepoint == 0x3001 or codepoint == 0x3002 or
        codepoint == 0xFF01 or codepoint == 0xFF0C or
        codepoint == 0xFF0E or codepoint == 0xFF1F)
    {
        return .transformed_upright;
    }
    if ((codepoint >= 0x3008 and codepoint <= 0x301F) or
        codepoint == 0x3030 or codepoint == 0x30A0 or
        codepoint == 0x30FC or
        (codepoint >= 0xFE59 and codepoint <= 0xFE5E) or
        codepoint == 0xFF08 or codepoint == 0xFF09 or
        (codepoint >= 0xFF1A and codepoint <= 0xFF1B) or
        codepoint == 0xFF3B or codepoint == 0xFF3D or
        (codepoint >= 0xFF5B and codepoint <= 0xFF60))
    {
        return .transformed_rotated;
    }

    if (upright_script) return .upright;
    if ((codepoint >= 0x2E80 and codepoint <= 0xA4CF) or
        (codepoint >= 0xAC00 and codepoint <= 0xD7FF) or
        (codepoint >= 0xE000 and codepoint <= 0xFAFF) or
        (codepoint >= 0xFE10 and codepoint <= 0xFE48) or
        (codepoint >= 0xFF01 and codepoint <= 0xFF60) or
        (codepoint >= 0xFFE0 and codepoint <= 0xFFE7) or
        (codepoint >= 0x1F000 and codepoint <= 0x1FAFF) or
        (codepoint >= 0x20000 and codepoint <= 0x3FFFD))
    {
        return .upright;
    }
    return .rotated;
}

pub fn presentationCodepoint(codepoint: u21) ?u21 {
    return switch (codepoint) {
        0x2013 => 0xfe32,
        0x2014 => 0xfe31,
        0x2025 => 0xfe30,
        0x2026 => 0xfe19,
        0x3001 => 0xfe11,
        0x3002 => 0xfe12,
        0x3008 => 0xfe3f,
        0x3009 => 0xfe40,
        0x300a => 0xfe3d,
        0x300b => 0xfe3e,
        0x300c => 0xfe41,
        0x300d => 0xfe42,
        0x300e => 0xfe43,
        0x300f => 0xfe44,
        0x3010 => 0xfe3b,
        0x3011 => 0xfe3c,
        0x3014 => 0xfe39,
        0x3015 => 0xfe3a,
        0x3016 => 0xfe17,
        0x3017 => 0xfe18,
        0xfe4f => 0xfe34,
        0xff01 => 0xfe15,
        0xff08 => 0xfe35,
        0xff09 => 0xfe36,
        0xff0c => 0xfe10,
        0xff1a => 0xfe13,
        0xff1b => 0xfe14,
        0xff1f => 0xfe16,
        else => null,
    };
}
