const std = @import("std");
const line_break = @import("unicode/line_break/iterator.zig");
const grapheme_boundary = @import("unicode/grapheme/iterator.zig");
const word_boundary = @import("unicode/word/iterator.zig");
const word_selection = @import("unicode/word/selection.zig");
const sentence_boundary = @import("unicode/sentence/iterator.zig");
const bidi_paragraph = @import("unicode/bidi/paragraph.zig");
const canonical_combining_class = @import("unicode/canonical_combining_class.zig");
const canonical_decomposition = @import("unicode/canonical_decomposition.zig");
const nonspacing_mark = @import("unicode/nonspacing_mark.zig");

/// Lightweight Unicode helpers used by the shaping/layout layers.
/// Boundary segmentation and bidirectional analysis use generated Unicode 17
/// datasets. Script and shaping-specific helper tables remain intentionally
/// focused on the scripts supported by Cangjie's OpenType pipeline.
pub const Script = enum {
    common,
    inherited,
    latin,
    greek,
    cyrillic,
    glagolitic,
    old_italic,
    ugaritic,
    old_persian,
    avestan,
    imperial_aramaic,
    old_south_arabian,
    old_north_arabian,
    meroitic_hieroglyphs,
    meroitic_cursive,
    han,
    yi,
    lisu,
    vai,
    hiragana,
    katakana,
    hangul,
    arabic,
    hebrew,
    phoenician,
    syriac,
    samaritan,
    mandaic,
    armenian,
    thai,
    lao,
    khmer,
    myanmar,
    devanagari,
    bengali,
    odia,
    gurmukhi,
    gujarati,
    telugu,
    kannada,
    sinhala,
    tamil,
    malayalam,
    ethiopic,
    georgian,
    cherokee,
    tifinagh,
    tibetan,
    phags_pa,
    nko,
    thaana,
    adlam,
    mongolian,
    balinese,
    javanese,
    tai_tham,
    marchen,
    newa,
    kayah_li,
    saurashtra,
    rejang,
    grantha,
    limbu,
    sharada,
    lepcha,
    buginese,
    sundanese,
    batak,
    meetei_mayek,
    canadian_aboriginal,
    cham,
    brahmi,
    kaithi,
    chakma,
    khudawadi,
    tirhuta,
    modi,
    takri,
    nushu,
    runic,
    coptic,
    ogham,
    duployan,
    unknown,
};

pub const ScriptRun = struct {
    script: Script,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiClass = enum {
    ltr,
    rtl,
    number,
    neutral,
};

pub const ExactBidiClass = bidi_paragraph.Class;
pub const BidiBaseDirection = bidi_paragraph.BaseDirection;
pub const BidiParagraph = bidi_paragraph.Paragraph;
pub const bidi_unicode_version = bidi_paragraph.unicode_version;

/// Unicode Joining_Type values used by cursive-script shaping.
///
/// The compact range table below is generated from Unicode 15.1
/// DerivedJoiningType.txt for Arabic/Syriac/N'Ko/Mandaic codepoint blocks plus
/// the Mongolian values currently needed by the Arabic-style shaper and ZWJ.
/// Unlisted codepoints have the normative Non_Joining default.
pub const JoiningType = enum {
    non_joining,
    right,
    left,
    dual,
    join_causing,
    transparent,
};

/// Positional OpenType form selected by the Unicode joining algorithm.
pub const JoiningForm = enum {
    none,
    isolated,
    initial,
    medial,
    final,
};

pub const VerticalOrientation = enum {
    upright,
    rotated,
    transformed_upright,
    transformed_rotated,
};

/// Compact UAX #50 classifier for the script families and punctuation used by
/// desktop UI text. The default is Rotated, while ideographic/kana/hangul,
/// fullwidth, emoji, and vertical-form ranges stay upright. Transformable CJK
/// punctuation is separated so `vert`/`vrt2` can select its vertical glyph.
pub fn verticalOrientationForCodepoint(codepoint: u21) VerticalOrientation {
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

    const script = scriptForCodepoint(codepoint);
    if (script == .han or script == .hiragana or script == .katakana or
        script == .hangul or script == .yi or script == .nushu or
        script == .canadian_aboriginal)
    {
        return .upright;
    }
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

pub fn verticalPresentationCodepoint(codepoint: u21) ?u21 {
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

const JoiningTypeRange = struct {
    first: u21,
    last: u21,
    kind: JoiningType,
};

const joining_type_ranges = [_]JoiningTypeRange{
    .{ .first = 0x034F, .last = 0x034F, .kind = .transparent },
    .{ .first = 0x0610, .last = 0x061A, .kind = .transparent },
    .{ .first = 0x061C, .last = 0x061C, .kind = .transparent },
    .{ .first = 0x0620, .last = 0x0620, .kind = .dual },
    .{ .first = 0x0622, .last = 0x0625, .kind = .right },
    .{ .first = 0x0626, .last = 0x0626, .kind = .dual },
    .{ .first = 0x0627, .last = 0x0627, .kind = .right },
    .{ .first = 0x0628, .last = 0x0628, .kind = .dual },
    .{ .first = 0x0629, .last = 0x0629, .kind = .right },
    .{ .first = 0x062A, .last = 0x062E, .kind = .dual },
    .{ .first = 0x062F, .last = 0x0632, .kind = .right },
    .{ .first = 0x0633, .last = 0x063F, .kind = .dual },
    .{ .first = 0x0640, .last = 0x0640, .kind = .join_causing },
    .{ .first = 0x0641, .last = 0x0647, .kind = .dual },
    .{ .first = 0x0648, .last = 0x0648, .kind = .right },
    .{ .first = 0x0649, .last = 0x064A, .kind = .dual },
    .{ .first = 0x064B, .last = 0x065F, .kind = .transparent },
    .{ .first = 0x066E, .last = 0x066F, .kind = .dual },
    .{ .first = 0x0670, .last = 0x0670, .kind = .transparent },
    .{ .first = 0x0671, .last = 0x0673, .kind = .right },
    .{ .first = 0x0675, .last = 0x0677, .kind = .right },
    .{ .first = 0x0678, .last = 0x0687, .kind = .dual },
    .{ .first = 0x0688, .last = 0x0699, .kind = .right },
    .{ .first = 0x069A, .last = 0x06BF, .kind = .dual },
    .{ .first = 0x06C0, .last = 0x06C0, .kind = .right },
    .{ .first = 0x06C1, .last = 0x06C2, .kind = .dual },
    .{ .first = 0x06C3, .last = 0x06CB, .kind = .right },
    .{ .first = 0x06CC, .last = 0x06CC, .kind = .dual },
    .{ .first = 0x06CD, .last = 0x06CD, .kind = .right },
    .{ .first = 0x06CE, .last = 0x06CE, .kind = .dual },
    .{ .first = 0x06CF, .last = 0x06CF, .kind = .right },
    .{ .first = 0x06D0, .last = 0x06D1, .kind = .dual },
    .{ .first = 0x06D2, .last = 0x06D3, .kind = .right },
    .{ .first = 0x06D5, .last = 0x06D5, .kind = .right },
    .{ .first = 0x06D6, .last = 0x06DC, .kind = .transparent },
    .{ .first = 0x06DF, .last = 0x06E4, .kind = .transparent },
    .{ .first = 0x06E7, .last = 0x06E8, .kind = .transparent },
    .{ .first = 0x06EA, .last = 0x06ED, .kind = .transparent },
    .{ .first = 0x06EE, .last = 0x06EF, .kind = .right },
    .{ .first = 0x06FA, .last = 0x06FC, .kind = .dual },
    .{ .first = 0x06FF, .last = 0x06FF, .kind = .dual },
    .{ .first = 0x070F, .last = 0x070F, .kind = .transparent },
    .{ .first = 0x0710, .last = 0x0710, .kind = .right },
    .{ .first = 0x0711, .last = 0x0711, .kind = .transparent },
    .{ .first = 0x0712, .last = 0x0714, .kind = .dual },
    .{ .first = 0x0715, .last = 0x0719, .kind = .right },
    .{ .first = 0x071A, .last = 0x071D, .kind = .dual },
    .{ .first = 0x071E, .last = 0x071E, .kind = .right },
    .{ .first = 0x071F, .last = 0x0727, .kind = .dual },
    .{ .first = 0x0728, .last = 0x0728, .kind = .right },
    .{ .first = 0x0729, .last = 0x0729, .kind = .dual },
    .{ .first = 0x072A, .last = 0x072A, .kind = .right },
    .{ .first = 0x072B, .last = 0x072B, .kind = .dual },
    .{ .first = 0x072C, .last = 0x072C, .kind = .right },
    .{ .first = 0x072D, .last = 0x072E, .kind = .dual },
    .{ .first = 0x072F, .last = 0x072F, .kind = .right },
    .{ .first = 0x0730, .last = 0x074A, .kind = .transparent },
    .{ .first = 0x074D, .last = 0x074D, .kind = .right },
    .{ .first = 0x074E, .last = 0x0758, .kind = .dual },
    .{ .first = 0x0759, .last = 0x075B, .kind = .right },
    .{ .first = 0x075C, .last = 0x076A, .kind = .dual },
    .{ .first = 0x076B, .last = 0x076C, .kind = .right },
    .{ .first = 0x076D, .last = 0x0770, .kind = .dual },
    .{ .first = 0x0771, .last = 0x0771, .kind = .right },
    .{ .first = 0x0772, .last = 0x0772, .kind = .dual },
    .{ .first = 0x0773, .last = 0x0774, .kind = .right },
    .{ .first = 0x0775, .last = 0x0777, .kind = .dual },
    .{ .first = 0x0778, .last = 0x0779, .kind = .right },
    .{ .first = 0x077A, .last = 0x077F, .kind = .dual },
    .{ .first = 0x07A6, .last = 0x07B0, .kind = .transparent },
    .{ .first = 0x07CA, .last = 0x07EA, .kind = .dual },
    .{ .first = 0x07EB, .last = 0x07F3, .kind = .transparent },
    .{ .first = 0x07FA, .last = 0x07FA, .kind = .join_causing },
    .{ .first = 0x07FD, .last = 0x07FD, .kind = .transparent },
    .{ .first = 0x0816, .last = 0x0819, .kind = .transparent },
    .{ .first = 0x081B, .last = 0x0823, .kind = .transparent },
    .{ .first = 0x0825, .last = 0x0827, .kind = .transparent },
    .{ .first = 0x0829, .last = 0x082D, .kind = .transparent },
    .{ .first = 0x0840, .last = 0x0840, .kind = .right },
    .{ .first = 0x0841, .last = 0x0845, .kind = .dual },
    .{ .first = 0x0846, .last = 0x0847, .kind = .right },
    .{ .first = 0x0848, .last = 0x0848, .kind = .dual },
    .{ .first = 0x0849, .last = 0x0849, .kind = .right },
    .{ .first = 0x084A, .last = 0x0853, .kind = .dual },
    .{ .first = 0x0854, .last = 0x0854, .kind = .right },
    .{ .first = 0x0855, .last = 0x0855, .kind = .dual },
    .{ .first = 0x0856, .last = 0x0858, .kind = .right },
    .{ .first = 0x0859, .last = 0x085B, .kind = .transparent },
    .{ .first = 0x0860, .last = 0x0860, .kind = .dual },
    .{ .first = 0x0862, .last = 0x0865, .kind = .dual },
    .{ .first = 0x0867, .last = 0x0867, .kind = .right },
    .{ .first = 0x0868, .last = 0x0868, .kind = .dual },
    .{ .first = 0x0869, .last = 0x086A, .kind = .right },
    .{ .first = 0x0870, .last = 0x0882, .kind = .right },
    .{ .first = 0x0883, .last = 0x0885, .kind = .join_causing },
    .{ .first = 0x0886, .last = 0x0886, .kind = .dual },
    .{ .first = 0x0889, .last = 0x088D, .kind = .dual },
    .{ .first = 0x088E, .last = 0x088E, .kind = .right },
    .{ .first = 0x0898, .last = 0x089F, .kind = .transparent },
    .{ .first = 0x08A0, .last = 0x08A9, .kind = .dual },
    .{ .first = 0x08AA, .last = 0x08AC, .kind = .right },
    .{ .first = 0x08AE, .last = 0x08AE, .kind = .right },
    .{ .first = 0x08AF, .last = 0x08B0, .kind = .dual },
    .{ .first = 0x08B1, .last = 0x08B2, .kind = .right },
    .{ .first = 0x08B3, .last = 0x08B8, .kind = .dual },
    .{ .first = 0x08B9, .last = 0x08B9, .kind = .right },
    .{ .first = 0x08BA, .last = 0x08C8, .kind = .dual },
    .{ .first = 0x08CA, .last = 0x08E1, .kind = .transparent },
    .{ .first = 0x08E3, .last = 0x0902, .kind = .transparent },
    // Mongolian shaping uses the same Unicode joining state machine as Arabic.
    // Keep this complete block fragment in sync with DerivedJoiningType.txt:
    // punctuation such as NIRUGU and the Sibe boundary marker participate in
    // joining even though they are not letters, while FVS/BALUDA/DAGALGA are
    // transparent. Omitting those exceptional scalars silently changes the
    // positional form selected for neighboring Mongolian letters.
    .{ .first = 0x1807, .last = 0x1807, .kind = .dual },
    .{ .first = 0x180A, .last = 0x180A, .kind = .join_causing },
    .{ .first = 0x180B, .last = 0x180D, .kind = .transparent },
    .{ .first = 0x180F, .last = 0x180F, .kind = .transparent },
    .{ .first = 0x1820, .last = 0x1878, .kind = .dual },
    .{ .first = 0x1885, .last = 0x1886, .kind = .transparent },
    .{ .first = 0x1887, .last = 0x18A8, .kind = .dual },
    .{ .first = 0x18A9, .last = 0x18A9, .kind = .transparent },
    .{ .first = 0x18AA, .last = 0x18AA, .kind = .dual },
    .{ .first = 0x200D, .last = 0x200D, .kind = .join_causing },
    .{ .first = 0xA840, .last = 0xA872, .kind = .dual },
    .{ .first = 0x10EFD, .last = 0x10EFF, .kind = .transparent },
    .{ .first = 0x1E900, .last = 0x1E943, .kind = .dual },
    .{ .first = 0x1E944, .last = 0x1E94A, .kind = .transparent },
};

pub fn joiningTypeForCodepoint(codepoint: u21) JoiningType {
    var low: usize = 0;
    var high: usize = joining_type_ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = joining_type_ranges[mid];
        if (codepoint < range.first) {
            high = mid;
        } else if (codepoint > range.last) {
            low = mid + 1;
        } else {
            return range.kind;
        }
    }
    return .non_joining;
}

/// Resolve positional forms in logical text order.
///
/// Transparent joining characters do not break the connection between their
/// neighbors and receive no positional feature themselves. Text outside scripts
/// that use the Arabic-style joining shaper is left as `.none`, so callers can
/// pass mixed-script runs without accidentally enabling positional features for
/// punctuation or digits.
pub noinline fn resolveJoiningForms(codepoints: []const u21, forms: []JoiningForm) error{InvalidJoiningInput}!void {
    if (forms.len != codepoints.len) return error.InvalidJoiningInput;
    @memset(forms, .none);

    var previous: ?JoiningType = null;
    var pending_index: ?usize = null;
    var pending_kind: JoiningType = .non_joining;
    var pending_joins_previous = false;

    for (codepoints, 0..) |codepoint, index| {
        const current = joiningTypeForCodepoint(codepoint);
        if (current == .transparent) continue;

        // The next non-transparent character resolves the pending Arabic
        // character's right connection. This replaces two repeated
        // forward/backward searches per character with one streaming pass and
        // one Joining_Type lookup per scalar.
        if (pending_index) |pending| {
            const joins_next = joinsLeft(pending_kind) and joinsRight(current);
            forms[pending] = joiningFormForConnections(pending_joins_previous, joins_next);
        }
        pending_index = null;

        if (current != .non_joining and hasArabicJoiningForms(codepoint)) {
            pending_index = index;
            pending_kind = current;
            pending_joins_previous = if (previous) |kind|
                joinsLeft(kind) and joinsRight(current)
            else
                false;
        }
        previous = current;
    }

    if (pending_index) |pending| {
        forms[pending] = joiningFormForConnections(pending_joins_previous, false);
    }
}

fn joiningFormForConnections(joins_previous: bool, joins_next: bool) JoiningForm {
    return if (joins_previous and joins_next)
        .medial
    else if (joins_previous)
        .final
    else if (joins_next)
        .initial
    else
        .isolated;
}

fn resolveJoiningFormsReference(codepoints: []const u21, forms: []JoiningForm) error{InvalidJoiningInput}!void {
    if (forms.len != codepoints.len) return error.InvalidJoiningInput;
    @memset(forms, .none);

    // Retain the former bidirectional implementation as a test oracle for the
    // streaming state machine. This is intentionally not used by shaping.
    for (codepoints, 0..) |codepoint, index| {
        const current = joiningTypeForCodepoint(codepoint);
        if (current == .transparent or current == .non_joining or !hasArabicJoiningForms(codepoint)) continue;

        var previous: ?JoiningType = null;
        var previous_index = index;
        while (previous_index > 0) {
            previous_index -= 1;
            const kind = joiningTypeForCodepoint(codepoints[previous_index]);
            if (kind == .transparent) continue;
            previous = kind;
            break;
        }

        var next: ?JoiningType = null;
        var next_index = index + 1;
        while (next_index < codepoints.len) : (next_index += 1) {
            const kind = joiningTypeForCodepoint(codepoints[next_index]);
            if (kind == .transparent) continue;
            next = kind;
            break;
        }

        const joins_previous = if (previous) |kind| joinsLeft(kind) and joinsRight(current) else false;
        const joins_next = if (next) |kind| joinsLeft(current) and joinsRight(kind) else false;
        forms[index] = joiningFormForConnections(joins_previous, joins_next);
    }
}

fn joinsRight(kind: JoiningType) bool {
    return kind == .right or kind == .dual or kind == .join_causing;
}

fn joinsLeft(kind: JoiningType) bool {
    return kind == .left or kind == .dual or kind == .join_causing;
}

fn hasArabicJoiningForms(codepoint: u21) bool {
    return isArabicScriptCodepoint(codepoint) or
        isMongolianScriptCodepoint(codepoint) or
        isAdlamScriptCodepoint(codepoint) or
        isPhagsPaScriptCodepoint(codepoint);
}

pub const BidiRun = struct {
    direction: BidiClass,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiMapItem = struct {
    logical_index: usize,
    visual_index: usize,
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    visual_codepoint: u21,
    direction: BidiClass,
};

pub const BidiMap = struct {
    allocator: std.mem.Allocator,
    items: []BidiMapItem,
    logical_to_visual: []usize,

    pub fn deinit(self: *BidiMap) void {
        self.allocator.free(self.logical_to_visual);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

const BidiCluster = struct {
    scalar_start: usize,
    scalar_end: usize,
    level: u8,
};

pub fn isDefaultIgnorableForShaping(codepoint: u21) bool {
    // SOFT HYPHEN is the lowest default-ignorable scalar Cangjie preserves for
    // shaping. This authoritative lower bound lets the overwhelmingly common
    // ASCII path skip the remaining singleton and range comparisons.
    if (codepoint < 0x00ad) return false;
    return codepoint == 0x00ad or
        codepoint == 0x034f or
        codepoint == 0x061c or
        codepoint == 0x180e or
        (codepoint >= 0x180b and codepoint <= 0x180f) or
        (codepoint >= 0x200b and codepoint <= 0x200f) or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x206f) or
        (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        codepoint == 0xfeff or
        (codepoint >= 0xfff0 and codepoint <= 0xfff8) or
        (codepoint >= 0x1bca0 and codepoint <= 0x1bca3) or
        (codepoint >= 0x1d173 and codepoint <= 0x1d17a) or
        (codepoint >= 0xe0000 and codepoint <= 0xe0fff);
}

fn canonicalCombiningClass(codepoint: u21) u8 {
    return canonical_combining_class.forCodepoint(codepoint);
}

pub fn canonicalDecomposition(codepoint: u21) ?[]const u21 {
    return canonical_decomposition.forCodepoint(codepoint);
}

pub fn modifiedCombiningClassForShaping(codepoint: u21) u8 {
    // U+0300 is the first scalar with a non-zero canonical combining class,
    // and every shaping-specific override below is higher. Avoid searching the
    // generated CCC ranges for ASCII and Latin-1 text.
    if (codepoint < 0x0300) return 0;
    // These script-specific overrides are part of HarfBuzz's normalization
    // contract. SAKOT and PADMA intentionally sort after ordinary tone/vowel
    // marks even though their canonical class is lower.
    return switch (codepoint) {
        0x1a60, 0x0fc6 => 254,
        0x0f39 => 127,
        else => modifiedCombiningClass(canonicalCombiningClass(codepoint)),
    };
}

fn modifiedCombiningClass(class: u8) u8 {
    return switch (class) {
        // Hebrew fixed-position classes follow SBL's practical mark order.
        10 => 22,
        11 => 15,
        12 => 16,
        13 => 17,
        14 => 23,
        15 => 18,
        16 => 19,
        17 => 20,
        18 => 21,
        19 => 14,
        20 => 24,
        21 => 12,
        22 => 25,
        23 => 13,
        24 => 10,
        25 => 11,
        26 => 26,
        // Move Arabic shadda (canonical class 33) before the other marks.
        27 => 28,
        28 => 29,
        29 => 30,
        30 => 31,
        31 => 32,
        32 => 33,
        33 => 27,
        34 => 34,
        35 => 35,
        // Telugu length marks must not reorder around the virama.
        84, 91 => 0,
        // Thai below vowels sort before U+0E3A.
        103 => 3,
        // Tibetan I/AA/U practical order.
        130 => 132,
        132 => 131,
        else => class,
    };
}

pub fn inheritsPreviousClusterInRtlShaping(codepoint: u21) bool {
    if (codepoint == 0x200d) return true;
    // This path runs once per scalar while mapping RTL shaping input. Keep its
    // Unicode 17 Arabic Mn coverage explicit: the generic script classifier
    // and the all-script combining-mark predicate both do substantially more
    // work, while the latter historically missed the newest Arabic marks.
    return isArabicNonspacingMark(codepoint) or isHebrewNonspacingMark(codepoint);
}

pub const GraphemeCluster = grapheme_boundary.Cluster;

/// Zero-allocation Unicode 17.0 extended grapheme cluster iterator.
pub const GraphemeClusterIterator = grapheme_boundary.Iterator;
pub const grapheme_unicode_version = grapheme_boundary.unicode_version;

pub fn graphemeClusters(text: []const u8) error{InvalidUtf8}!GraphemeClusterIterator {
    return grapheme_boundary.clusters(text);
}

pub fn graphemeClustersAssumeValid(text: []const u8) GraphemeClusterIterator {
    return grapheme_boundary.assumeValid(text);
}

pub const WordBoundarySegment = word_boundary.Segment;
/// A selectable word span retained for editor/caret compatibility.
///
/// `wordSegments` exposes every UAX #29 segment and its `is_word` bit. This
/// compact type intentionally keeps the established word-only collector ABI.
pub const WordSegment = struct {
    byte_start: usize,
    byte_len: usize,
};
pub const WordBoundaryIterator = word_boundary.Iterator;
pub const word_unicode_version = word_boundary.unicode_version;

pub fn wordSegments(text: []const u8) word_boundary.Error!WordBoundaryIterator {
    return word_boundary.segments(text);
}

pub const SentenceSegment = sentence_boundary.Segment;
pub const SentenceBoundaryIterator = sentence_boundary.Iterator;
pub const sentence_unicode_version = sentence_boundary.unicode_version;

pub fn sentenceSegments(
    text: []const u8,
) sentence_boundary.Error!SentenceBoundaryIterator {
    return sentence_boundary.segments(text);
}

pub const LineBreakKind = line_break.BreakKind;
pub const LineBreak = line_break.Break;
pub const LineBreakIterator = line_break.Iterator;
pub const LineBreakClass = line_break.BreakClass;
pub const line_break_unicode_version = line_break.unicode_version;

pub fn lineBreaks(text: []const u8) line_break.Error!LineBreakIterator {
    return line_break.breaks(text);
}

pub fn lineBreaksAssumeValid(text: []const u8) LineBreakIterator {
    return line_break.breaksAssumeValid(text);
}

pub fn lineBreakClassForCodepoint(codepoint: u21) LineBreakClass {
    return line_break.classForCodepoint(codepoint);
}

pub const OpenTypeScriptTag = enum(u32) {
    dflt = tag("DFLT"),
    dflt_lower = tag("dflt"),
    latn = tag("latn"),
    grek = tag("grek"),
    cyrl = tag("cyrl"),
    glag = tag("glag"),
    ital = tag("ital"),
    ugar = tag("ugar"),
    xpeo = tag("xpeo"),
    avst = tag("avst"),
    armi = tag("armi"),
    sarb = tag("sarb"),
    narb = tag("narb"),
    mero = tag("mero"),
    merc = tag("merc"),
    hani = tag("hani"),
    yi = tag("yi  "),
    lisu = tag("lisu"),
    vai = tag("vai "),
    hira = tag("hira"),
    kana = tag("kana"),
    hang = tag("hang"),
    arab = tag("arab"),
    hebr = tag("hebr"),
    phnx = tag("phnx"),
    syrc = tag("syrc"),
    samr = tag("samr"),
    mand = tag("mand"),
    armn = tag("armn"),
    thai = tag("thai"),
    lao = tag("lao "),
    khmr = tag("khmr"),
    qaag = tag("Qaag"),
    mym2 = tag("mym2"),
    mymr = tag("mymr"),
    dev3 = tag("dev3"),
    bng3 = tag("bng3"),
    ory3 = tag("ory3"),
    gur3 = tag("gur3"),
    gjr3 = tag("gjr3"),
    tel3 = tag("tel3"),
    knd3 = tag("knd3"),
    mlm3 = tag("mlm3"),
    tml3 = tag("tml3"),
    dev2 = tag("dev2"),
    bng2 = tag("bng2"),
    ory2 = tag("ory2"),
    gur2 = tag("gur2"),
    gjr2 = tag("gjr2"),
    tel2 = tag("tel2"),
    knd2 = tag("knd2"),
    sinh = tag("sinh"),
    taml = tag("taml"),
    mlm2 = tag("mlm2"),
    tml2 = tag("tml2"),
    deva = tag("deva"),
    beng = tag("beng"),
    orya = tag("orya"),
    guru = tag("guru"),
    gujr = tag("gujr"),
    telu = tag("telu"),
    knda = tag("knda"),
    mlym = tag("mlym"),
    ethi = tag("ethi"),
    geor = tag("geor"),
    cher = tag("cher"),
    tfng = tag("tfng"),
    tibt = tag("tibt"),
    phag = tag("phag"),
    nko = tag("nko "),
    thaa = tag("thaa"),
    adlm = tag("adlm"),
    mong = tag("mong"),
    bali = tag("bali"),
    java = tag("java"),
    lana = tag("lana"),
    marc = tag("marc"),
    newa = tag("newa"),
    kali = tag("kali"),
    saur = tag("saur"),
    rjng = tag("rjng"),
    gran = tag("gran"),
    limb = tag("limb"),
    shrd = tag("shrd"),
    lepc = tag("lepc"),
    bugi = tag("bugi"),
    sund = tag("sund"),
    batk = tag("batk"),
    mtei = tag("mtei"),
    cans = tag("cans"),
    cham = tag("cham"),
    brah = tag("brah"),
    kthi = tag("kthi"),
    cakm = tag("cakm"),
    sind = tag("sind"),
    tirh = tag("tirh"),
    modi = tag("modi"),
    takr = tag("takr"),
    nshu = tag("nshu"),
    runr = tag("runr"),
    copt = tag("copt"),
    ogam = tag("ogam"),
    dupl = tag("dupl"),
};

pub const ScriptTagCandidates = struct {
    tags: [3]OpenTypeScriptTag,
    len: u2,

    pub fn slice(self: *const ScriptTagCandidates) []const OpenTypeScriptTag {
        return self.tags[0..self.len];
    }
};

/// Return OpenType ScriptList candidates in HarfBuzz preference order.
///
/// Indic-v3 fonts deliberately select USE, while v2 and legacy tags select the
/// traditional Indic shaper. Keeping all candidates beside the semantic
/// Unicode script lets layout negotiate against each concrete font instead of
/// baking one OpenType generation into script itemization.
pub fn openTypeScriptTagCandidates(script: Script) ScriptTagCandidates {
    const primary = openTypeScriptTag(script);
    return switch (script) {
        .devanagari => .{ .tags = .{ .dev3, .dev2, .deva }, .len = 3 },
        .bengali => .{ .tags = .{ .bng3, .bng2, .beng }, .len = 3 },
        .odia => .{ .tags = .{ .ory3, .ory2, .orya }, .len = 3 },
        .gurmukhi => .{ .tags = .{ .gur3, .gur2, .guru }, .len = 3 },
        .gujarati => .{ .tags = .{ .gjr3, .gjr2, .gujr }, .len = 3 },
        .telugu => .{ .tags = .{ .tel3, .tel2, .telu }, .len = 3 },
        .kannada => .{ .tags = .{ .knd3, .knd2, .knda }, .len = 3 },
        .tamil => .{ .tags = .{ .tml3, .tml2, .taml }, .len = 3 },
        .malayalam => .{ .tags = .{ .mlm3, .mlm2, .mlym }, .len = 3 },
        .myanmar => .{ .tags = .{ .mym2, .mymr, .mymr }, .len = 2 },
        else => .{ .tags = .{ primary, primary, primary }, .len = 1 },
    };
}

pub const OpenTypeLanguageTag = enum(u32) {
    dflt = tag("dflt"),
    ara = tag("ARA "),
    far = tag("FAR "),
    jan = tag("JAN "),
    kor = tag("KOR "),
    zhh = tag("ZHH "),
    zhs = tag("ZHS "),
    zht = tag("ZHT "),
    hin = tag("HIN "),
    dhv = tag("DHV "),
};

pub const FeatureOverride = struct {
    tag: u32,
    enabled: bool,
    value: u32 = 1,

    pub fn effectiveValue(self: FeatureOverride) u32 {
        return if (self.enabled) self.value else 0;
    }
};

/// One OpenType GSUB feature value active for source clusters in
/// `[byte_start, byte_end)`. Offsets are UTF-8 bytes and later overlapping
/// entries with the same tag take precedence.
pub const GsubFeatureRange = @import("shaping/features/ranged_gsub/ranges.zig").Range;

/// Map the internal script enum to the OpenType script tag used for GSUB/GPOS
/// ScriptList selection.
pub fn openTypeScriptTag(script: Script) OpenTypeScriptTag {
    return switch (script) {
        .latin => .latn,
        .greek => .grek,
        .cyrillic => .cyrl,
        .glagolitic => .glag,
        .old_italic => .ital,
        .ugaritic => .ugar,
        .old_persian => .xpeo,
        .avestan => .avst,
        .imperial_aramaic => .armi,
        .old_south_arabian => .sarb,
        .old_north_arabian => .narb,
        .meroitic_hieroglyphs => .mero,
        .meroitic_cursive => .merc,
        .han => .hani,
        .yi => .yi,
        .lisu => .lisu,
        .vai => .vai,
        .hiragana => .hira,
        .katakana => .kana,
        .hangul => .hang,
        .arabic => .arab,
        .hebrew => .hebr,
        .phoenician => .phnx,
        .syriac => .syrc,
        .samaritan => .samr,
        .mandaic => .mand,
        .armenian => .armn,
        .thai => .thai,
        .lao => .lao,
        .khmer => .khmr,
        .myanmar => .mym2,
        .devanagari => .dev2,
        .bengali => .bng2,
        .odia => .ory2,
        .gurmukhi => .gur2,
        .gujarati => .gjr2,
        .telugu => .tel2,
        .kannada => .knd2,
        .sinhala => .sinh,
        .tamil => .taml,
        .malayalam => .mlm2,
        .ethiopic => .ethi,
        .georgian => .geor,
        .cherokee => .cher,
        .tifinagh => .tfng,
        .tibetan => .tibt,
        .phags_pa => .phag,
        .nko => .nko,
        .thaana => .thaa,
        .adlam => .adlm,
        .mongolian => .mong,
        .balinese => .bali,
        .javanese => .java,
        .tai_tham => .lana,
        .marchen => .marc,
        .newa => .newa,
        .kayah_li => .kali,
        .saurashtra => .saur,
        .rejang => .rjng,
        .grantha => .gran,
        .limbu => .limb,
        .sharada => .shrd,
        .lepcha => .lepc,
        .buginese => .bugi,
        .sundanese => .sund,
        .batak => .batk,
        .meetei_mayek => .mtei,
        .canadian_aboriginal => .cans,
        .cham => .cham,
        .brahmi => .brah,
        .kaithi => .kthi,
        .chakma => .cakm,
        .khudawadi => .sind,
        .tirhuta => .tirh,
        .modi => .modi,
        .takri => .takr,
        .nushu => .nshu,
        .runic => .runr,
        .coptic => .copt,
        .ogham => .ogam,
        .duployan => .dupl,
        .common, .inherited, .unknown => .dflt,
    };
}

pub fn openTypeScriptHorizontalDirection(script_tag: OpenTypeScriptTag) ?BidiClass {
    return switch (script_tag) {
        .arab,
        .hebr,
        .phnx,
        .syrc,
        .samr,
        .mand,
        .nko,
        .thaa,
        .adlm,
        .ugar,
        .avst,
        .armi,
        .sarb,
        .narb,
        .mero,
        .merc,
        => .rtl,
        .dflt => null,
        else => .ltr,
    };
}

/// Script and language properties inferred together for OpenType selection.
pub const InferredOpenTypeProperties = struct {
    script: Script,
    language: OpenTypeLanguageTag,
    all_ascii: bool,
};

/// Infer only the first strong script, for callers that already have an
/// explicit language and therefore should not scan the remainder of the text.
pub fn inferOpenTypeScript(text: []const u8) Script {
    var cursor: usize = 0;
    while (cursor < text.len) {
        const decoded = decodeCodepointAt(text, cursor) orelse return .common;
        cursor = decoded.next;
        const script = scriptForCodepoint(decoded.codepoint);
        if (isStrongInferredScript(script)) return script;
    }
    return .common;
}

/// Infer the first strong script and the coarse default language in one scan.
///
/// Script selection needs the first non-Common/Inherited/Unknown script, while
/// language selection may inspect later content (for example Han followed by
/// Hiragana is Japanese). Keeping both decisions in one state machine avoids
/// decoding and classifying the same leading scalar twice during shaping.
pub fn inferOpenTypeProperties(text: []const u8) InferredOpenTypeProperties {
    var text_script: Script = .common;
    var saw_han = false;
    var all_ascii = true;
    var cursor: usize = 0;
    while (cursor < text.len) {
        if (text[cursor] < 0x80) {
            // No inferred non-default language uses an ASCII script. Once a
            // strong script is known, the remaining ASCII bytes therefore
            // require neither UTF-8 decoding nor Unicode Script lookup.
            if (text_script == .common) {
                const script = scriptForCodepoint(@intCast(text[cursor]));
                if (isStrongInferredScript(script)) text_script = script;
            }
            cursor += 1;
            continue;
        }

        all_ascii = false;
        const decoded = decodeCodepointAt(text, cursor) orelse return .{
            .script = text_script,
            .language = .dflt,
            .all_ascii = false,
        };
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
        const script = scriptForCodepoint(codepoint);
        if (text_script == .common and isStrongInferredScript(script)) {
            text_script = script;
        }
        switch (script) {
            .hiragana, .katakana => return .{ .script = text_script, .language = .jan, .all_ascii = false },
            .hangul => return .{ .script = text_script, .language = .kor, .all_ascii = false },
            .arabic => return .{ .script = text_script, .language = .ara, .all_ascii = false },
            .devanagari => return .{ .script = text_script, .language = .hin, .all_ascii = false },
            .bengali, .odia, .gurmukhi, .telugu, .kannada, .tamil, .thai, .lao => return .{ .script = text_script, .language = .dflt, .all_ascii = false },
            .han => saw_han = true,
            else => {},
        }
    }
    return .{
        .script = text_script,
        .language = if (saw_han) .zhs else .dflt,
        .all_ascii = all_ascii,
    };
}

fn isStrongInferredScript(script: Script) bool {
    return script != .common and script != .inherited and script != .unknown;
}

pub fn inferOpenTypeLanguageTag(text: []const u8) OpenTypeLanguageTag {
    return inferOpenTypeProperties(text).language;
}

/// Map a BCP47-ish locale tag to the OpenType language-system tags currently
/// modeled by this module. This is intentionally conservative: unsupported
/// languages return null so callers can fall back to content-based inference.
pub fn openTypeLanguageTagForLocale(locale_tag: []const u8) ?OpenTypeLanguageTag {
    var it = std.mem.tokenizeAny(u8, locale_tag, "-_");
    const language_raw = it.next() orelse return null;
    const language = canonicalLanguageAlias(language_raw);
    var script: ?[]const u8 = null;
    var region: ?[]const u8 = null;
    while (it.next()) |subtag| {
        if (script == null and isScriptSubtag(subtag)) {
            script = subtag;
            continue;
        }
        if (region == null and isRegionSubtag(subtag)) {
            region = subtag;
            continue;
        }
    }

    if (asciiEqlIgnoreCase(language, "ja")) return .jan;
    if (asciiEqlIgnoreCase(language, "ko")) return .kor;
    if (asciiEqlIgnoreCase(language, "ar")) return .ara;
    if (asciiEqlIgnoreCase(language, "fa")) return .far;
    if (asciiEqlIgnoreCase(language, "hi")) return .hin;
    if (asciiEqlIgnoreCase(language, "dv")) return .dhv;
    if (asciiEqlIgnoreCase(language, "zh")) {
        if (script) |script_value| {
            if (asciiEqlIgnoreCase(script_value, "Hant")) {
                if (region) |region_value| {
                    if (asciiEqlIgnoreCase(region_value, "HK") or asciiEqlIgnoreCase(region_value, "MO")) return .zhh;
                }
                return .zht;
            }
            if (asciiEqlIgnoreCase(script_value, "Hans")) return .zhs;
        }
        if (region) |region_value| {
            if (asciiEqlIgnoreCase(region_value, "HK") or asciiEqlIgnoreCase(region_value, "MO")) return .zhh;
            if (asciiEqlIgnoreCase(region_value, "TW")) return .zht;
        }
        return .zhs;
    }
    return null;
}

fn canonicalLanguageAlias(language: []const u8) []const u8 {
    if (asciiEqlIgnoreCase(language, "iw")) return "he";
    if (asciiEqlIgnoreCase(language, "in")) return "id";
    if (asciiEqlIgnoreCase(language, "ji")) return "yi";
    return language;
}

fn isScriptSubtag(subtag: []const u8) bool {
    if (subtag.len != 4) return false;
    for (subtag) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    return true;
}

fn isRegionSubtag(subtag: []const u8) bool {
    if (subtag.len == 2) {
        for (subtag) |byte| {
            if (!std.ascii.isAlphabetic(byte)) return false;
        }
        return true;
    }
    if (subtag.len == 3) {
        for (subtag) |byte| {
            if (!std.ascii.isDigit(byte)) return false;
        }
        return true;
    }
    return false;
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (std.ascii.toLower(lhs) != std.ascii.toLower(rhs)) return false;
    }
    return true;
}

const DecodedCodepoint = struct {
    codepoint: u21,
    next: usize,
};

fn decodeCodepointAt(text: []const u8, cursor: usize) ?DecodedCodepoint {
    if (cursor >= text.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch return null;
    const end = cursor + @as(usize, len);
    if (end > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[cursor..end]) catch return null;
    return .{ .codepoint = codepoint, .next = end };
}

pub fn tag(comptime bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn scriptForCodepoint(codepoint: u21) Script {
    if ((codepoint >= 'A' and codepoint <= 'Z') or (codepoint >= 'a' and codepoint <= 'z')) return .latin;
    if (isLatinScriptCodepoint(codepoint)) return .latin;
    // Unicode variation selectors have Script=Inherited. Classify them before
    // block-specific tests so FE0E/FE0F and supplementary IVS selectors stay
    // attached to the base script run as well as its grapheme cluster.
    if (isVariationSelector(codepoint)) return .inherited;
    if (isCopticScriptCodepoint(codepoint)) return .coptic;
    if (isGreekScriptCodepoint(codepoint)) return .greek;
    if (isCyrillicScriptCodepoint(codepoint)) return .cyrillic;
    if (isGlagoliticScriptCodepoint(codepoint)) return .glagolitic;
    if (isOldItalicScriptCodepoint(codepoint)) return .old_italic;
    if (isUgariticScriptCodepoint(codepoint)) return .ugaritic;
    if (isOldPersianScriptCodepoint(codepoint)) return .old_persian;
    if (isAvestanScriptCodepoint(codepoint)) return .avestan;
    if (isImperialAramaicScriptCodepoint(codepoint)) return .imperial_aramaic;
    if (isOldSouthArabianScriptCodepoint(codepoint)) return .old_south_arabian;
    if (isOldNorthArabianScriptCodepoint(codepoint)) return .old_north_arabian;
    if (isMeroiticHieroglyphsScriptCodepoint(codepoint)) return .meroitic_hieroglyphs;
    if (isMeroiticCursiveScriptCodepoint(codepoint)) return .meroitic_cursive;
    if ((codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        codepoint == 0x1133b)
    {
        return .inherited;
    }
    if (isHebrewScriptCodepoint(codepoint)) return .hebrew;
    if (isPhoenicianScriptCodepoint(codepoint)) return .phoenician;
    if (isSyriacScriptCodepoint(codepoint)) return .syriac;
    if (isSamaritanScriptCodepoint(codepoint)) return .samaritan;
    if (isMandaicScriptCodepoint(codepoint)) return .mandaic;
    if (isArmenianScriptCodepoint(codepoint)) return .armenian;
    if (isArabicScriptCodepoint(codepoint)) return .arabic;
    if (isThaiScriptCodepoint(codepoint)) return .thai;
    if (isLaoScriptCodepoint(codepoint)) return .lao;
    if (isKhmerScriptCodepoint(codepoint)) return .khmer;
    if (isMyanmarScriptCodepoint(codepoint)) return .myanmar;
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .devanagari;
    if (isBengaliScriptCodepoint(codepoint)) return .bengali;
    if (isOdiaScriptCodepoint(codepoint)) return .odia;
    if (isGurmukhiScriptCodepoint(codepoint)) return .gurmukhi;
    if (isGujaratiScriptCodepoint(codepoint)) return .gujarati;
    if (isTeluguScriptCodepoint(codepoint)) return .telugu;
    if (isKannadaScriptCodepoint(codepoint)) return .kannada;
    if (isSinhalaScriptCodepoint(codepoint)) return .sinhala;
    if (isTamilScriptCodepoint(codepoint)) return .tamil;
    if (isMalayalamScriptCodepoint(codepoint)) return .malayalam;
    if (isEthiopicScriptCodepoint(codepoint)) return .ethiopic;
    if (isGeorgianScriptCodepoint(codepoint)) return .georgian;
    if (isCherokeeScriptCodepoint(codepoint)) return .cherokee;
    if (isTifinaghScriptCodepoint(codepoint)) return .tifinagh;
    if (isTibetanScriptCodepoint(codepoint)) return .tibetan;
    if (isPhagsPaScriptCodepoint(codepoint)) return .phags_pa;
    if (isThaanaScriptCodepoint(codepoint)) return .thaana;
    if (isNkoScriptCodepoint(codepoint)) return .nko;
    if (isAdlamScriptCodepoint(codepoint)) return .adlam;
    if (isMongolianScriptCodepoint(codepoint)) return .mongolian;
    if (isBalineseScriptCodepoint(codepoint)) return .balinese;
    if (isJavaneseScriptCodepoint(codepoint)) return .javanese;
    if (isTaiThamScriptCodepoint(codepoint)) return .tai_tham;
    if (isMarchenScriptCodepoint(codepoint)) return .marchen;
    if (isNewaScriptCodepoint(codepoint)) return .newa;
    if (isKayahLiScriptCodepoint(codepoint)) return .kayah_li;
    if (isSaurashtraScriptCodepoint(codepoint)) return .saurashtra;
    if (isRejangScriptCodepoint(codepoint)) return .rejang;
    if (isGranthaScriptCodepoint(codepoint)) return .grantha;
    if (isLimbuScriptCodepoint(codepoint)) return .limbu;
    if (isSharadaScriptCodepoint(codepoint)) return .sharada;
    if (isLepchaScriptCodepoint(codepoint)) return .lepcha;
    if (isBugineseScriptCodepoint(codepoint)) return .buginese;
    if (isSundaneseScriptCodepoint(codepoint)) return .sundanese;
    if (isBatakScriptCodepoint(codepoint)) return .batak;
    if (isMeeteiMayekScriptCodepoint(codepoint)) return .meetei_mayek;
    if (isCanadianAboriginalScriptCodepoint(codepoint)) return .canadian_aboriginal;
    if (isChamScriptCodepoint(codepoint)) return .cham;
    if (isBrahmiScriptCodepoint(codepoint)) return .brahmi;
    if (isKaithiScriptCodepoint(codepoint)) return .kaithi;
    if (isChakmaScriptCodepoint(codepoint)) return .chakma;
    if (isKhudawadiScriptCodepoint(codepoint)) return .khudawadi;
    if (isTirhutaScriptCodepoint(codepoint)) return .tirhuta;
    if (isModiScriptCodepoint(codepoint)) return .modi;
    if (isTakriScriptCodepoint(codepoint)) return .takri;
    if (isNushuScriptCodepoint(codepoint)) return .nushu;
    if (isRunicScriptCodepoint(codepoint)) return .runic;
    if (isOghamScriptCodepoint(codepoint)) return .ogham;
    if (isDuployanScriptCodepoint(codepoint)) return .duployan;
    if (codepoint >= 0x3040 and codepoint <= 0x309f) return .hiragana;
    if (codepoint >= 0x30a0 and codepoint <= 0x30ff) return .katakana;
    // Katakana is also encoded in phonetic-extension and halfwidth forms.
    // These are real script letters used by Japanese fonts; classifying them
    // as unknown would split shaping runs and bypass `kana` OpenType lookups.
    if (codepoint >= 0x31f0 and codepoint <= 0x31ff) return .katakana;
    if (codepoint >= 0xff66 and codepoint <= 0xff9d) return .katakana;
    if (codepoint == 0xff9e or codepoint == 0xff9f) return .inherited;
    // Modern and archaic Hangul Jamo must select the Hangul shaping script even
    // before they are composed into precomposed syllables. Grapheme clustering
    // already treats these ranges as Hangul L/V/T components; keeping script
    // classification in sync ensures conjoining-jamo text reaches `hang`
    // OpenType lookups instead of falling into DFLT/unknown runs.
    if (codepoint >= 0x1100 and codepoint <= 0x11ff) return .hangul;
    if (codepoint >= 0x3130 and codepoint <= 0x318f) return .hangul;
    if (codepoint >= 0xa960 and codepoint <= 0xa97f) return .hangul;
    if (codepoint >= 0xac00 and codepoint <= 0xd7af) return .hangul;
    if (codepoint >= 0xd7b0 and codepoint <= 0xd7ff) return .hangul;
    if (codepoint >= 0x3400 and codepoint <= 0x4dbf) return .han;
    if (codepoint >= 0x4e00 and codepoint <= 0x9fff) return .han;
    if (codepoint >= 0xf900 and codepoint <= 0xfaff) return .han;
    if (codepoint >= 0x20000 and codepoint <= 0x2fffd) return .han;
    if (codepoint >= 0x30000 and codepoint <= 0x3fffd) return .han;
    if (isYiScriptCodepoint(codepoint)) return .yi;
    if (isLisuScriptCodepoint(codepoint)) return .lisu;
    if (isVaiScriptCodepoint(codepoint)) return .vai;
    if (isCommonCodepoint(codepoint)) return .common;
    return .unknown;
}

fn isVaiScriptCodepoint(codepoint: u21) bool {
    // Vai fonts use the `vai ` OpenType ScriptList entry for the syllabary,
    // digits, lengthener, and script punctuation in the A500 block. Keeping the
    // whole block in one run prevents Vai words from falling back to DFLT when
    // they contain native digits or punctuation adjacent to syllables.
    return codepoint >= 0xa500 and codepoint <= 0xa63f;
}

fn isLisuScriptCodepoint(codepoint: u21) bool {
    // Lisu fonts select the `lisu` OpenType ScriptList entry for the Fraser
    // alphabet, tone letters, script punctuation, and the supplementary letter
    // YHA. Keeping the base block and supplement together avoids splitting
    // older or dialectal Lisu text through DFLT/unknown shaping runs.
    return (codepoint >= 0xa4d0 and codepoint <= 0xa4ff) or
        codepoint == 0x11fb0;
}

fn isYiScriptCodepoint(codepoint: u21) bool {
    // Yi fonts use a dedicated OpenType ScriptList entry (`yi  `) for the
    // syllabary and radicals. Keeping both adjacent blocks in one shaping run
    // prevents Nuosu/Yi text from falling through DFLT and also lets line
    // breaking treat Yi syllables like the East Asian ideographic units they
    // are in UAX #14.
    return (codepoint >= 0xa000 and codepoint <= 0xa48f) or
        (codepoint >= 0xa490 and codepoint <= 0xa4cf);
}

fn isBalineseScriptCodepoint(codepoint: u21) bool {
    // Balinese OpenType fonts expose script-specific substitutions and mark
    // positioning under the `bali` ScriptList entry. Keep the complete block in
    // one script run so aksara bases, dependent vowels, adeg-adeg, digits, and
    // Balinese punctuation do not get split through DFLT/unknown before layout.
    return codepoint >= 0x1b00 and codepoint <= 0x1b7f;
}

fn isJavaneseScriptCodepoint(codepoint: u21) bool {
    // Javanese uses script-specific OpenType shaping (`java`) for dependent
    // vowels, final consonant signs, and U+A9C0 PANGKON. Keeping the whole
    // block together avoids splitting aksara syllables through DFLT/unknown
    // runs before GSUB/GPOS lookup selection.
    return codepoint >= 0xa980 and codepoint <= 0xa9df;
}

fn isTaiThamScriptCodepoint(codepoint: u21) bool {
    // Tai Tham letters, medials, sakot, dependent vowels, tone signs, native
    // digits, and punctuation share the registered `lana` OpenType tag.
    return codepoint >= 0x1a20 and codepoint <= 0x1aaf;
}

fn isMarchenScriptCodepoint(codepoint: u21) bool {
    // Marchen letters, subjoined consonants, dependent vowels, and head marks
    // occupy one supplementary block and use the registered `marc` OpenType
    // ScriptList tag. Keep assigned scalars in one USE shaping run.
    return (codepoint >= 0x11c70 and codepoint <= 0x11c8f) or
        (codepoint >= 0x11c92 and codepoint <= 0x11ca7) or
        (codepoint >= 0x11ca9 and codepoint <= 0x11cb6);
}

fn isNewaScriptCodepoint(codepoint: u21) bool {
    // Unicode assigns U+11400..U+11461 to Newa; U+11462..U+1147F remains
    // reserved, as is the single gap U+1145C. Restricting this to assigned
    // scalars avoids routing future additions through the current `newa`
    // shaping model prematurely.
    return codepoint >= 0x11400 and codepoint <= 0x11461 and codepoint != 0x1145c;
}

fn isKayahLiScriptCodepoint(codepoint: u21) bool {
    // Kayah Li fonts use the registered `kali` ScriptList entry for native
    // digits, letters, dependent vowels/tones, and script punctuation in the
    // compact A900 block. Keeping the whole assigned block in one run prevents
    // combining tone marks or native separators from forcing DFLT shaping.
    return codepoint >= 0xa900 and codepoint <= 0xa92f;
}

fn isSaurashtraScriptCodepoint(codepoint: u21) bool {
    // U+A8C6..U+A8CD and U+A8DA..U+A8DF are reserved gaps in the otherwise
    // compact Saurashtra block.
    return (codepoint >= 0xa880 and codepoint <= 0xa8c5) or
        (codepoint >= 0xa8ce and codepoint <= 0xa8d9);
}

fn isRejangScriptCodepoint(codepoint: u21) bool {
    // Rejang has one compact block with letters, dependent vowel/consonant
    // signs, virama, and a native section mark. Keep only assigned scalars in
    // the `rjng` shaping run so the unassigned U+A954..U+A95E gap does not
    // silently inherit Rejang script or LTR bidi behavior.
    return (codepoint >= 0xa930 and codepoint <= 0xa953) or
        codepoint == 0xa95f;
}

fn isGranthaScriptCodepoint(codepoint: u21) bool {
    // Script=Inherited U+1133B COMBINING BINDU BELOW participates in Grantha
    // shaping, but remains inherited for script-run resolution.
    if (codepoint == 0x1133b) return false;
    return (codepoint >= 0x11300 and codepoint <= 0x11303) or
        (codepoint >= 0x11305 and codepoint <= 0x1130c) or
        (codepoint >= 0x1130f and codepoint <= 0x11310) or
        (codepoint >= 0x11313 and codepoint <= 0x11328) or
        (codepoint >= 0x1132a and codepoint <= 0x11330) or
        (codepoint >= 0x11332 and codepoint <= 0x11333) or
        (codepoint >= 0x11335 and codepoint <= 0x11340) or
        (codepoint >= 0x11341 and codepoint <= 0x11344) or
        (codepoint >= 0x11347 and codepoint <= 0x11348) or
        (codepoint >= 0x1134b and codepoint <= 0x1134d) or
        codepoint == 0x11350 or
        codepoint == 0x11357 or
        (codepoint >= 0x1135d and codepoint <= 0x11363) or
        (codepoint >= 0x11366 and codepoint <= 0x1136c) or
        (codepoint >= 0x11370 and codepoint <= 0x11374);
}

fn isLimbuScriptCodepoint(codepoint: u21) bool {
    // Limbu has dependent vowel signs, subjoined letters, final consonant
    // signs, and native digits in one compact block. Fonts can expose these
    // under the `limb` ScriptList entry, so keep the block in one run instead
    // of routing combining pieces through DFLT/unknown before layout.
    return codepoint >= 0x1900 and codepoint <= 0x194f;
}

fn isSharadaScriptCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x11180 and codepoint <= 0x111df) or
        (codepoint >= 0x11b60 and codepoint <= 0x11b67);
}

fn isLepchaScriptCodepoint(codepoint: u21) bool {
    // Lepcha letters, subjoined letters, vowel/consonant signs, digits, and
    // native punctuation select the `lepc` OpenType ScriptList entry. Keep only
    // assigned scalars in the shaping run so the reserved gaps in the block do
    // not silently inherit Lepcha script or LTR bidi behavior.
    return (codepoint >= 0x1c00 and codepoint <= 0x1c37) or
        (codepoint >= 0x1c3b and codepoint <= 0x1c49) or
        (codepoint >= 0x1c4d and codepoint <= 0x1c4f);
}

fn isBugineseScriptCodepoint(codepoint: u21) bool {
    // Buginese dependent vowels are split between nonspacing and spacing
    // marks, but fonts select one `bugi` OpenType script system for the whole
    // syllable. Treat the compact block as one shaping script so lontara text
    // is not split through DFLT/unknown before GSUB/GPOS lookup selection.
    return codepoint >= 0x1a00 and codepoint <= 0x1a1f;
}

fn isSundaneseScriptCodepoint(codepoint: u21) bool {
    // Sundanese fonts select script-specific shaping and mark positioning under
    // the `sund` ScriptList entry. The base block carries letters, dependent
    // marks, digits, and punctuation; the supplement extends punctuation used
    // with the same script, so keep both ranges out of DFLT/unknown runs.
    return (codepoint >= 0x1b80 and codepoint <= 0x1bbf) or
        (codepoint >= 0x1cc0 and codepoint <= 0x1ccf);
}

fn isBatakScriptCodepoint(codepoint: u21) bool {
    // Batak fonts expose script-specific substitutions and mark positioning
    // under `batk`. The compact block has a reserved gap before native
    // punctuation, so keep assigned letters/signs/punctuation in the shaping
    // script while leaving U+1BF4..U+1BFB unknown for malformed data.
    return (codepoint >= 0x1bc0 and codepoint <= 0x1bf3) or
        (codepoint >= 0x1bfc and codepoint <= 0x1bff);
}

fn isMeeteiMayekScriptCodepoint(codepoint: u21) bool {
    // Meetei Mayek letters are split between the main block and an extensions
    // block that also contains dependent vowel signs. Fonts select the `mtei`
    // ScriptList entry for both, so keep letters, lonsum finals, signs, digits,
    // and punctuation in one shaping run instead of routing marks through DFLT.
    return (codepoint >= 0xaae0 and codepoint <= 0xaaff) or
        (codepoint >= 0xabc0 and codepoint <= 0xabff);
}

fn isCanadianAboriginalScriptCodepoint(codepoint: u21) bool {
    // Unified Canadian Aboriginal Syllabics are encoded across the original
    // block plus Extended/Extended-A additions used by Inuktitut, Cree, Ojibwe,
    // Carrier, and related orthographies. Fonts expose their substitutions and
    // mark positioning under `cans`; keeping all three ranges in one script run
    // avoids falling back to DFLT when a word mixes base and extended syllables.
    return (codepoint >= 0x1400 and codepoint <= 0x167f) or
        (codepoint >= 0x18b0 and codepoint <= 0x18ff) or
        (codepoint >= 0x11ab0 and codepoint <= 0x11abf);
}

fn isChamScriptCodepoint(codepoint: u21) bool {
    // Cham uses dependent vowels and final-consonant signs from the same block
    // as its letters, digits, and punctuation. Fonts select one `cham`
    // ScriptList entry for these pieces, so keep them in a single script run
    // instead of routing marks or finals through DFLT/unknown before shaping.
    return codepoint >= 0xaa00 and codepoint <= 0xaa5f;
}

fn isBrahmiScriptCodepoint(codepoint: u21) bool {
    // Brahmi is an historic Indic script with dependent vowel signs, viramas,
    // digits, and punctuation in one supplementary-plane block. Fonts expose
    // Brahmi-specific shaping through the `brah` ScriptList entry, so keep the
    // block together instead of routing marks or numbers through DFLT/unknown.
    return codepoint >= 0x11000 and codepoint <= 0x1107f;
}

fn isKaithiScriptCodepoint(codepoint: u21) bool {
    // Kaithi is an historic Indic script whose dependent vowels, virama,
    // number signs, and native punctuation live in one supplementary-plane
    // block. Fonts select the `kthi` ScriptList entry for the whole cluster,
    // so classify only assigned scalars here and leave the reserved tail as
    // unknown rather than granting malformed data script/bidi semantics.
    return (codepoint >= 0x11080 and codepoint <= 0x110c2) or
        codepoint == 0x110cd;
}

fn isChakmaScriptCodepoint(codepoint: u21) bool {
    // Chakma uses an Indic-style shaping model under the registered `cakm`
    // OpenType ScriptList tag. Keep assigned letters, vowel signs, virama,
    // native digits, and script punctuation in one LTR run while leaving the
    // reserved U+11135 slot and block tail unknown for malformed/private data.
    return (codepoint >= 0x11100 and codepoint <= 0x11134) or
        (codepoint >= 0x11136 and codepoint <= 0x11147);
}

fn isKhudawadiScriptCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x112b0 and codepoint <= 0x112ea) or
        (codepoint >= 0x112f0 and codepoint <= 0x112f9);
}

fn isTirhutaScriptCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x11480 and codepoint <= 0x114c7) or
        (codepoint >= 0x114d0 and codepoint <= 0x114d9);
}

fn isModiScriptCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x11600 and codepoint <= 0x11644) or
        (codepoint >= 0x11650 and codepoint <= 0x11659);
}

fn isTakriScriptCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x11680 and codepoint <= 0x116b9) or
        (codepoint >= 0x116c0 and codepoint <= 0x116c9);
}

fn isNushuScriptCodepoint(codepoint: u21) bool {
    // Nushu is encoded as a supplementary-plane ideographic script and has a
    // dedicated OpenType ScriptList tag (`nshu`). Classify the entire block as
    // one shaping script so Nushu text selects script-specific font lookups
    // instead of falling through DFLT/unknown primitives.
    return codepoint >= 0x1b170 and codepoint <= 0x1b2ff;
}

fn isRunicScriptCodepoint(codepoint: u21) bool {
    // The Runic block includes letters, word/division punctuation, and numeric
    // symbols that fonts expose through the `runr` ScriptList entry. Keeping
    // the whole block in one LTR shaping run prevents inscriptions that use
    // native separators or Golden Number signs from falling back to DFLT in the
    // middle of otherwise Runic text.
    return codepoint >= 0x16a0 and codepoint <= 0x16ff;
}

fn isCopticScriptCodepoint(codepoint: u21) bool {
    // Coptic is encoded partly as Coptic letters in the Greek block, partly in
    // the dedicated Coptic block, and partly as Coptic Epact Numbers in the
    // supplementary plane. Check this before Greek so fonts can select their
    // `copt` ScriptList entry instead of shaping U+03E2..U+03EF as Greek.
    return (codepoint >= 0x03e2 and codepoint <= 0x03ef) or
        (codepoint >= 0x2c80 and codepoint <= 0x2cff) or
        (codepoint >= 0x102e0 and codepoint <= 0x102ff);
}

fn isOghamScriptCodepoint(codepoint: u21) bool {
    // Ogham fonts use the historical `ogam` OpenType script tag for the block's
    // letters, native space mark, and feather punctuation. Keep those assigned
    // scalars in one shaping run while leaving the unassigned tail as unknown.
    return codepoint >= 0x1680 and codepoint <= 0x169c;
}

fn isDuployanScriptCodepoint(codepoint: u21) bool {
    // Duployan shorthand fonts expose script-specific substitutions and
    // positioning under the registered `dupl` ScriptList entry. Keep the
    // shorthand block in one LTR shaping run instead of falling through DFLT.
    return codepoint >= 0x1bc00 and codepoint <= 0x1bc9f;
}

fn isPhoenicianScriptCodepoint(codepoint: u21) bool {
    // Phoenician is an historic right-to-left script with a registered OpenType
    // script tag (`phnx`). Keep the assigned letters, native number signs, and
    // word separator in one script run so inscriptions do not fall back to
    // DFLT/neutral shaping between letters and native punctuation. The
    // unassigned U+1091C..U+1091E gap remains unknown on purpose.
    return (codepoint >= 0x10900 and codepoint <= 0x1091b) or
        codepoint == 0x1091f;
}

fn isSamaritanScriptCodepoint(codepoint: u21) bool {
    // Samaritan letters, vowel signs, reading marks, and punctuation all carry
    // strong RTL behavior and use the registered `samr` OpenType script tag.
    // Keep the assigned block together, while leaving U+083F unknown so
    // malformed/private data does not inherit Samaritan script semantics.
    return codepoint >= 0x0800 and codepoint <= 0x083e;
}

fn isMongolianScriptCodepoint(codepoint: u21) bool {
    // Mongolian fonts expose positional shaping and variation forms under the
    // `mong` ScriptList entry. The block includes letters, Todo/Sibe/Manchu
    // additions, punctuation, digits, and free variation selectors; keeping the
    // assigned block together avoids splitting valid vertical-script words
    // through DFLT/unknown before GSUB/GPOS lookup selection.
    return codepoint >= 0x1800 and codepoint <= 0x18af;
}

fn isNkoScriptCodepoint(codepoint: u21) bool {
    // N'Ko is an RTL script with its own OpenType ScriptList tag (`nko `).
    // Its combining marks, modifier letters, digits, and currency signs live
    // in the same compact block as letters. Keep assigned scalars in one RTL
    // shaping run, but leave the two reserved slots unknown so malformed data
    // does not silently inherit N'Ko script or bidi behavior.
    return (codepoint >= 0x07c0 and codepoint <= 0x07fa) or
        (codepoint >= 0x07fd and codepoint <= 0x07ff);
}

fn isAdlamScriptCodepoint(codepoint: u21) bool {
    // Adlam is a right-to-left script for Fulani with dedicated OpenType
    // shaping under `adlm`. Keep the assigned letters, combining marks,
    // modifier mark, digits, and script punctuation in one RTL run so Adlam
    // text does not fall through DFLT or neutral bidi handling between bases,
    // marks, and native digits.
    return (codepoint >= 0x1e900 and codepoint <= 0x1e94b) or
        (codepoint >= 0x1e950 and codepoint <= 0x1e959) or
        (codepoint >= 0x1e95e and codepoint <= 0x1e95f);
}

fn isThaanaScriptCodepoint(codepoint: u21) bool {
    // Thaana is an RTL abugida used for Dhivehi. Its base letters and fili
    // vowel signs must select the `thaa` OpenType ScriptList entry together;
    // otherwise vowel-mark positioning falls back to DFLT or gets split from
    // the surrounding right-to-left shaping run.
    return codepoint >= 0x0780 and codepoint <= 0x07b1;
}

fn isThaiScriptCodepoint(codepoint: u21) bool {
    // Thai bases, dependent vowels, tone marks, digits, and punctuation select
    // the `thai` OpenType script system. Treat the whole assigned block as one
    // shaping script so marks and bases are not split through DFLT runs before
    // GSUB/GPOS lookup selection.
    return codepoint >= 0x0e01 and codepoint <= 0x0e5b;
}

fn isLaoScriptCodepoint(codepoint: u21) bool {
    // Lao is encoded analogously to Thai and uses its own `lao ` OpenType
    // ScriptList entry. Keeping letters, dependent signs, digits, and Lao
    // punctuation in one run avoids losing script-specific shaping lookups.
    return codepoint >= 0x0e81 and codepoint <= 0x0edf;
}

fn isKhmerScriptCodepoint(codepoint: u21) bool {
    // Khmer shaping depends on `khmr` ScriptList selection for COENG subscript
    // forms and dependent-vowel positioning. The base block also contains
    // script punctuation and digits, while Khmer Symbols carries lunar-date
    // signs that fonts commonly cover with the same Khmer face; keep both
    // ranges in one script run so punctuation/symbols do not force DFLT in the
    // middle of Khmer text.
    return (codepoint >= 0x1780 and codepoint <= 0x17ff) or
        (codepoint >= 0x19e0 and codepoint <= 0x19ff);
}

fn isMyanmarScriptCodepoint(codepoint: u21) bool {
    // Myanmar shaping depends on the modern `mym2` OpenType script system for
    // kinzi, medials, stacked consonants, and dependent vowel/tone placement.
    // Keep the base block and Myanmar Extended-A/B/C additions in one script
    // run so Burmese, Mon, Shan, Karen, Tai Laing, Khamti, Aiton, and related
    // text does not fall through DFLT between bases, signs, or native digits.
    return (codepoint >= 0x1000 and codepoint <= 0x109f) or
        (codepoint >= 0xa9e0 and codepoint <= 0xa9fe) or
        (codepoint >= 0xaa60 and codepoint <= 0xaa7f) or
        (codepoint >= 0x116d0 and codepoint <= 0x116e3);
}

fn isSyriacScriptCodepoint(codepoint: u21) bool {
    // Syriac is a right-to-left cursive script with script-specific OpenType
    // shaping. Its base letters, combining marks, abbreviations, and
    // supplementary letters all need to stay in one `syrc` shaping run rather
    // than being treated as DFLT/neutral text between Arabic/Hebrew support.
    return (codepoint >= 0x0700 and codepoint <= 0x074f) or
        (codepoint >= 0x0860 and codepoint <= 0x086f);
}

fn isMandaicScriptCodepoint(codepoint: u21) bool {
    // Mandaic is an RTL cursive script with script-specific OpenType shaping
    // under `mand`. Only assigned scalars in U+0840..U+085E should enter the
    // shaping run: the unassigned gap at U+085C/U+085D must remain unknown so
    // malformed/private data does not silently inherit Mandaic bidi behavior.
    return (codepoint >= 0x0840 and codepoint <= 0x085b) or
        codepoint == 0x085e;
}

fn isGeorgianScriptCodepoint(codepoint: u21) bool {
    // Georgian has casing split across Mkhedruli, Mtavruli, Nuskhuri, and
    // historic Asomtavruli blocks. Fonts expose substitutions and positioning
    // under the `geor` ScriptList entry, so all Georgian letters must remain in
    // one shaping run instead of falling back to DFLT/unknown.
    return (codepoint >= 0x10a0 and codepoint <= 0x10ff) or
        (codepoint >= 0x1c90 and codepoint <= 0x1cbf) or
        (codepoint >= 0x2d00 and codepoint <= 0x2d2f);
}

fn isCherokeeScriptCodepoint(codepoint: u21) bool {
    // Cherokee has bicameral letters split between the main block and the
    // Cherokee Supplement. Fonts expose script-specific substitutions and
    // positioning through the `cher` ScriptList entry, so upper/lowercase text
    // must remain in one shaping run instead of being routed through DFLT.
    return (codepoint >= 0x13a0 and codepoint <= 0x13ff) or
        (codepoint >= 0xab70 and codepoint <= 0xabbf);
}

fn isTifinaghScriptCodepoint(codepoint: u21) bool {
    // Tifinagh uses a dedicated OpenType ScriptList entry (`tfng`) for Amazigh
    // letters, the labialization modifier, native separator, and consonant
    // joiner. Keep the assigned scalars precise rather than treating the
    // unassigned gaps as script text, so fallback and bidi logic do not assign
    // Tifinagh behavior to malformed/private data in the block.
    return (codepoint >= 0x2d30 and codepoint <= 0x2d67) or
        codepoint == 0x2d6f or
        codepoint == 0x2d70 or
        codepoint == 0x2d7f;
}

fn isTibetanScriptCodepoint(codepoint: u21) bool {
    // Tibetan stacks rely on script-specific OpenType shaping (`tibt`) for
    // subjoined consonants, vowel signs, and marks. Keep the full Tibetan
    // block in one LTR script run so those syllables do not fall through DFLT
    // lookup selection before shaping.
    return codepoint >= 0x0f00 and codepoint <= 0x0fff;
}

fn isPhagsPaScriptCodepoint(codepoint: u21) bool {
    // Phags-Pa uses Arabic-style positional forms in OpenType.
    return codepoint >= 0xa840 and codepoint <= 0xa877;
}

fn isEthiopicScriptCodepoint(codepoint: u21) bool {
    // Ethiopic has no complex OpenType shaper, but fonts still commonly put
    // language and punctuation-sensitive substitutions/positioning under the
    // `ethi` ScriptList entry. Keep the base block, supplement, extended, and
    // extended-A letters/numerals in one LTR script run instead of routing them
    // through DFLT/unknown.
    return (codepoint >= 0x1200 and codepoint <= 0x139f) or
        (codepoint >= 0x2d80 and codepoint <= 0x2ddf) or
        (codepoint >= 0xab00 and codepoint <= 0xab2f);
}

fn isBengaliScriptCodepoint(codepoint: u21) bool {
    // Bengali/Assamese letters, dependent signs, digits, and punctuation select
    // the modern `bng2` OpenType script system. Cangjie already treats Bengali
    // split vowels as grapheme continuations; classifying the full assigned
    // block as Bengali keeps those syllables in the same shaping run instead
    // of routing them through DFLT/unknown.
    return codepoint >= 0x0980 and codepoint <= 0x09ff;
}

fn isGurmukhiScriptCodepoint(codepoint: u21) bool {
    // Gurmukhi text uses the Indic v2 OpenType shaping system (`gur2`). Keep
    // letters, dependent signs, digits, and script punctuation in one run so
    // Punjabi/Sikh-script syllables do not fall back to DFLT between bases,
    // vowel signs, virama forms, and nasalization marks.
    return codepoint >= 0x0a00 and codepoint <= 0x0a7f;
}

fn isGujaratiScriptCodepoint(codepoint: u21) bool {
    // Gujarati uses the Indic v2 shaping model under `gjr2`. Keep the complete
    // block together for script runs so dependent signs, digits, avagraha/OM,
    // and modern combining additions select the same GSUB/GPOS ScriptList as
    // their base consonants instead of falling through DFLT/unknown.
    return codepoint >= 0x0a80 and codepoint <= 0x0aff;
}

fn isOdiaScriptCodepoint(codepoint: u21) bool {
    // Odia/Oriya uses the Indic v2 OpenType shaping system (`ory2`). Its
    // letters, dependent signs, nukta, virama, digits, and script punctuation
    // occupy one Unicode block; keeping that block in one script run lets
    // fonts select Odia-specific GSUB/GPOS features for aksharas instead of
    // routing marks and consonants through DFLT/unknown.
    return codepoint >= 0x0b00 and codepoint <= 0x0b7f;
}

fn isTeluguScriptCodepoint(codepoint: u21) bool {
    // Telugu uses the Indic v2 OpenType shaping system (`tel2`). The block
    // contains independent letters, dependent vowel signs, virama, digits, and
    // length marks; treating the whole block as Telugu keeps aksharas in one
    // shaping run instead of routing marks through DFLT/unknown.
    return codepoint >= 0x0c00 and codepoint <= 0x0c7f;
}

fn isKannadaScriptCodepoint(codepoint: u21) bool {
    // Kannada has the same Indic v2 shaping requirements under `knd2`. Keeping
    // consonants, dependent signs, virama forms, digits, and script-specific
    // additions together avoids splitting Kannada syllables before GSUB/GPOS
    // feature selection.
    return codepoint >= 0x0c80 and codepoint <= 0x0cff;
}

fn isSinhalaScriptCodepoint(codepoint: u21) bool {
    // Sinhala vowels, consonants, dependent signs, punctuation, and numerals
    // live in one Unicode block and are shaped through the `sinh` OpenType
    // script system. Keeping the full block together prevents valid aksharas
    // from being split through DFLT/unknown runs before GSUB/GPOS selection.
    return codepoint >= 0x0d80 and codepoint <= 0x0dff;
}

fn isTamilScriptCodepoint(codepoint: u21) bool {
    // Tamil shaping depends on keeping consonants, dependent vowels, virama,
    // numerals, and historic additions in one `taml` script run. Unicode's
    // Tamil block has unassigned holes, but treating the assigned range as the
    // script is a safer primitive than splitting common Tamil syllables through
    // DFLT/unknown before OpenType lookup selection.
    return (codepoint >= 0x0b82 and codepoint <= 0x0bfa) or
        (codepoint >= 0x11fc0 and codepoint <= 0x11fff);
}

fn isMalayalamScriptCodepoint(codepoint: u21) bool {
    // Malayalam uses the Indic v2 OpenType shaping system (`mlm2`) for
    // reordering and conjunct formation. The base block contains letters,
    // dependent vowels, virama, chillus, digits, and script punctuation; keeping
    // it together avoids sending common Malayalam syllables through DFLT or
    // splitting marks into separate shaping runs.
    return codepoint >= 0x0d00 and codepoint <= 0x0d7f;
}

fn isArabicScriptCodepoint(codepoint: u21) bool {
    // Arabic Presentation Forms are compatibility encodings, but Unicode still
    // assigns them Script=Arabic. Legacy text and normalized-later input should
    // remain in Arabic RTL shaping runs so fonts can select `arab` features
    // instead of falling back to DFLT/neutral handling.
    return (codepoint >= 0x0600 and codepoint <= 0x06ff) or
        (codepoint >= 0x0750 and codepoint <= 0x077f) or
        (codepoint >= 0x0870 and codepoint <= 0x08ff) or
        (codepoint >= 0x10efd and codepoint <= 0x10eff) or
        (codepoint >= 0xfb50 and codepoint <= 0xfdff) or
        (codepoint >= 0xfe70 and codepoint <= 0xfefc);
}

// Keep this compact range chain out of the mixed-direction scalar loop that
// calls inheritsPreviousClusterInRtlShaping(). LTR shaping never needs it, and
// one out-of-line call per RTL scalar is cheaper than inlining the former
// all-script classification path into that shared loop.
noinline fn isArabicNonspacingMark(codepoint: u21) bool {
    return isArabicBaseNonspacingMark(codepoint) or
        (codepoint >= 0x0897 and codepoint <= 0x089f) or
        (codepoint >= 0x08ca and codepoint <= 0x08e1) or
        (codepoint >= 0x08e3 and codepoint <= 0x08ff) or
        (codepoint >= 0x10efd and codepoint <= 0x10eff);
}

inline fn isArabicBaseNonspacingMark(codepoint: u21) bool {
    return (codepoint >= 0x0610 and codepoint <= 0x061a) or
        (codepoint >= 0x064b and codepoint <= 0x065f) or
        codepoint == 0x0670 or
        (codepoint >= 0x06d6 and codepoint <= 0x06dc) or
        (codepoint >= 0x06df and codepoint <= 0x06e4) or
        (codepoint >= 0x06e7 and codepoint <= 0x06e8) or
        (codepoint >= 0x06ea and codepoint <= 0x06ed);
}

fn isHebrewNonspacingMark(codepoint: u21) bool {
    return (codepoint >= 0x0591 and codepoint <= 0x05bd) or
        codepoint == 0x05bf or
        (codepoint >= 0x05c1 and codepoint <= 0x05c2) or
        (codepoint >= 0x05c4 and codepoint <= 0x05c5) or
        codepoint == 0x05c7;
}

fn isLatinScriptCodepoint(codepoint: u21) bool {
    // Keep all encoded Latin extension blocks in the Latin shaping script.
    // Precomposed Vietnamese, phonetic, and medievalist letters are alphabetic
    // bases, not inherited combining marks; splitting them into DFLT/unknown
    // runs prevents fonts from selecting their `latn` GSUB/GPOS features.
    return (codepoint >= 0x00c0 and codepoint <= 0x024f) or
        (codepoint >= 0x1d00 and codepoint <= 0x1d7f) or
        (codepoint >= 0x1d80 and codepoint <= 0x1dbf) or
        (codepoint >= 0x1e00 and codepoint <= 0x1eff) or
        (codepoint >= 0x2c60 and codepoint <= 0x2c7f) or
        (codepoint >= 0xa720 and codepoint <= 0xa7ff) or
        (codepoint >= 0xab30 and codepoint <= 0xab6f) or
        (codepoint >= 0x1df00 and codepoint <= 0x1dfff);
}

fn isGreekScriptCodepoint(codepoint: u21) bool {
    // Greek letters commonly rely on `grek` OpenType lookup selection for
    // mark positioning and localized alternates. Keep the full encoded Greek
    // script repertoire in one shaping script, including Coptic-era additions
    // and ancient Greek notation blocks whose Script property is Greek.
    return (codepoint >= 0x0370 and codepoint <= 0x03ff) or
        (codepoint >= 0x1d200 and codepoint <= 0x1d245) or
        (codepoint >= 0x1f00 and codepoint <= 0x1fff) or
        (codepoint >= 0x10140 and codepoint <= 0x1018f);
}

fn isHebrewScriptCodepoint(codepoint: u21) bool {
    // Hebrew presentation forms are compatibility characters, but they still
    // carry Script=Hebrew in Unicode. Treating them as unknown would split
    // Hebrew script runs and classify them as bidi-neutral, which breaks
    // low-level shaping and visual ordering for legacy or normalized-later text.
    return (codepoint >= 0x0590 and codepoint <= 0x05ff) or
        (codepoint >= 0xfb1d and codepoint <= 0xfb4f);
}

fn isArmenianScriptCodepoint(codepoint: u21) bool {
    // Armenian has dedicated OpenType shaping/script selection (`armn`) for
    // localized forms and mark positioning. Keep alphabetic letters,
    // punctuation, ligature codepoints, and modifier letters in one script run;
    // otherwise Armenian text is split through DFLT/unknown and loses script-
    // specific GSUB/GPOS coverage.
    return (codepoint >= 0x0531 and codepoint <= 0x058f) or
        (codepoint >= 0xfb13 and codepoint <= 0xfb17) or
        codepoint == 0x0559 or
        codepoint == 0x055a or
        codepoint == 0x055b or
        codepoint == 0x055c or
        codepoint == 0x055d or
        codepoint == 0x055e or
        codepoint == 0x055f;
}

fn isCyrillicScriptCodepoint(codepoint: u21) bool {
    // Cyrillic has several extension blocks used by living orthographies.
    // Classifying them as unknown would split runs and route GSUB/GPOS through
    // DFLT instead of the font's `cyrl` script system.
    return (codepoint >= 0x0400 and codepoint <= 0x052f) or
        (codepoint >= 0x1c80 and codepoint <= 0x1c8f) or
        (codepoint >= 0x2de0 and codepoint <= 0x2dff) or
        (codepoint >= 0xa640 and codepoint <= 0xa69f) or
        (codepoint >= 0x1e030 and codepoint <= 0x1e08f);
}

fn isGlagoliticScriptCodepoint(codepoint: u21) bool {
    // Glagolitic combines a BMP alphabet block with supplementary combining
    // letters used in historic manuscripts. Fonts expose both through the
    // `glag` ScriptList entry, so keep base letters and combining letters in a
    // single LTR shaping run instead of treating the supplement as unknown
    // combining data between otherwise Glagolitic bases.
    return (codepoint >= 0x2c00 and codepoint <= 0x2c5f) or
        (codepoint >= 0x1e000 and codepoint <= 0x1e02a);
}

fn isOldItalicScriptCodepoint(codepoint: u21) bool {
    // Old Italic is a supplementary-plane historic script with a registered
    // OpenType ScriptList tag (`ital`). The Unicode block has unassigned gaps,
    // so classify only assigned letters and native numerals; treating the whole
    // block as script text would give private/malformed data LTR/script shaping
    // semantics it should not inherit.
    return (codepoint >= 0x10300 and codepoint <= 0x10323) or
        (codepoint >= 0x1032d and codepoint <= 0x1032f);
}

fn isUgariticScriptCodepoint(codepoint: u21) bool {
    // Ugaritic is a supplementary-plane cuneiform alphabet with registered
    // OpenType tag `ugar`. Keep assigned letters and the native word divider in
    // one RTL script run, while leaving the reserved U+1039E slot unknown so
    // malformed data does not gain Ugaritic shaping or bidi semantics.
    return (codepoint >= 0x10380 and codepoint <= 0x1039d) or
        codepoint == 0x1039f;
}

fn isOldPersianScriptCodepoint(codepoint: u21) bool {
    // Old Persian cuneiform has a registered OpenType ScriptList tag (`xpeo`).
    // Classify only assigned signs, logograms, word divider, and native numbers
    // so reserved gaps do not inherit strong LTR/script shaping semantics from
    // neighbouring valid text.
    return (codepoint >= 0x103a0 and codepoint <= 0x103c3) or
        (codepoint >= 0x103c8 and codepoint <= 0x103d5);
}

fn isAvestanScriptCodepoint(codepoint: u21) bool {
    // Avestan is an RTL historic script with its own OpenType ScriptList tag
    // (`avst`). Include its native punctuation in the script run so separators
    // do not force a neutral/DFLT shaping island between adjacent letters,
    // while preserving the unassigned U+10B36..U+10B38 gap as unknown.
    return (codepoint >= 0x10b00 and codepoint <= 0x10b35) or
        (codepoint >= 0x10b39 and codepoint <= 0x10b3f);
}

fn isImperialAramaicScriptCodepoint(codepoint: u21) bool {
    // Imperial Aramaic is a supplementary-plane RTL script with the registered
    // OpenType tag `armi`. Keep letters, the section sign, and native numbers
    // in one script run, but leave U+10856 unknown so malformed/private data
    // does not silently inherit right-to-left shaping semantics.
    return (codepoint >= 0x10840 and codepoint <= 0x10855) or
        (codepoint >= 0x10857 and codepoint <= 0x1085f);
}

fn isOldSouthArabianScriptCodepoint(codepoint: u21) bool {
    // Old South Arabian is a compact, fully-assigned RTL historic block with
    // registered OpenType tag `sarb`. Keep letters, native number signs, and
    // the numeric indicator in one script/bidi run so mixed inscriptions do not
    // fall back to DFLT shaping in the middle of a valid numeral sequence.
    return codepoint >= 0x10a60 and codepoint <= 0x10a7f;
}

fn isOldNorthArabianScriptCodepoint(codepoint: u21) bool {
    // Old North Arabian is an RTL historic script with registered OpenType tag
    // `narb`. The block is compact and currently fully assigned: letters and
    // native number signs share one shaping/bidi run for inscriptional text.
    return codepoint >= 0x10a80 and codepoint <= 0x10a9f;
}

fn isMeroiticHieroglyphsScriptCodepoint(codepoint: u21) bool {
    // Meroitic Hieroglyphs is a right-to-left historic script with its own
    // registered OpenType tag (`mero`). The block is fully assigned today, so
    // the compact script primitive can keep all letters and VIDJ signs in one
    // RTL shaping run without granting semantics to neighbouring unassigned
    // Meroitic Cursive gaps.
    return codepoint >= 0x10980 and codepoint <= 0x1099f;
}

fn isMeroiticCursiveScriptCodepoint(codepoint: u21) bool {
    // Meroitic Cursive shares the RTL writing direction with the hieroglyphic
    // script but uses a separate OpenType ScriptList tag (`merc`). Classify
    // only assigned letters, logograms, numbers, and fractions; reserved gaps
    // in the block stay unknown instead of inheriting RTL/script semantics.
    return (codepoint >= 0x109a0 and codepoint <= 0x109b7) or
        (codepoint >= 0x109bc and codepoint <= 0x109cf) or
        (codepoint >= 0x109d2 and codepoint <= 0x109ff);
}

/// Classify only strong LTR/RTL scripts and neutral punctuation/spacing. The
/// higher-level bidi functions use this coarse class to build visual runs.
pub fn bidiClassForCodepoint(codepoint: u21) BidiClass {
    if (bidiClassFast(codepoint)) |class| return class;
    return bidiClassForScript(scriptForCodepoint(codepoint));
}

pub fn exactBidiClassForCodepoint(codepoint: u21) ExactBidiClass {
    return bidi_paragraph.classForCodepoint(codepoint);
}

fn bidiClassFast(codepoint: u21) ?BidiClass {
    // This is the legacy four-class compatibility view, not the UAX #9 input
    // classifier. Exact paragraph analysis uses the generated property table.
    if (codepoint <= 0x7f) {
        if (codepoint >= '0' and codepoint <= '9') return .number;
        if ((codepoint >= 'A' and codepoint <= 'Z') or
            (codepoint >= 'a' and codepoint <= 'z'))
        {
            return .ltr;
        }
        return .neutral;
    }
    if ((codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9))
    {
        return .number;
    }
    if (isArabicScriptCodepoint(codepoint) or
        isHebrewScriptCodepoint(codepoint))
    {
        return .rtl;
    }
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .ltr;
    return null;
}

fn bidiClassForScript(script: Script) BidiClass {
    return switch (script) {
        .arabic, .hebrew, .phoenician, .syriac, .samaritan, .mandaic, .nko, .thaana, .adlam, .avestan, .imperial_aramaic, .old_south_arabian, .old_north_arabian, .meroitic_hieroglyphs, .meroitic_cursive => .rtl,
        .latin, .greek, .cyrillic, .glagolitic, .old_italic, .ugaritic, .old_persian, .han, .yi, .lisu, .vai, .hiragana, .katakana, .hangul, .armenian, .thai, .lao, .khmer, .myanmar, .devanagari, .bengali, .odia, .gurmukhi, .gujarati, .telugu, .kannada, .sinhala, .tamil, .malayalam, .ethiopic, .georgian, .cherokee, .tifinagh, .tibetan, .phags_pa, .mongolian, .balinese, .javanese, .tai_tham, .marchen, .newa, .kayah_li, .saurashtra, .rejang, .grantha, .limbu, .sharada, .lepcha, .buginese, .sundanese, .batak, .meetei_mayek, .canadian_aboriginal, .cham, .brahmi, .kaithi, .chakma, .khudawadi, .tirhuta, .modi, .takri, .nushu, .runic, .coptic, .ogham, .duployan => .ltr,
        else => .neutral,
    };
}

/// Resolve a paragraph base direction from the first strong character.
/// Numbers and neutral formatting characters do not decide direction.
pub fn paragraphDirection(text: []const u8) error{InvalidUtf8}!BidiClass {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    var isolate_depth: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        switch (exactBidiClassForCodepoint(codepoint)) {
            .lri, .rli, .fsi => isolate_depth += 1,
            .pdi => if (isolate_depth != 0) {
                isolate_depth -= 1;
            },
            .l => if (isolate_depth == 0) return .ltr,
            .r, .al => if (isolate_depth == 0) return .rtl,
            .b => break,
            else => {},
        }
    }
    return .ltr;
}

pub fn resolveBidiParagraph(
    allocator: std.mem.Allocator,
    text: []const u8,
    base_direction: BidiBaseDirection,
) !BidiParagraph {
    return bidi_paragraph.resolve(allocator, text, base_direction);
}

pub fn itemizeBidiRuns(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]BidiRun {
    var paragraph = try resolveBidiParagraph(
        allocator,
        text,
        if (base_direction == .rtl) .rtl else .ltr,
    );
    defer paragraph.deinit();
    var runs = std.ArrayList(BidiRun).empty;
    errdefer runs.deinit(allocator);
    if (paragraph.scalars.len == 0) return try runs.toOwnedSlice(allocator);

    const cluster_levels = try graphemeClusterLevels(allocator, text, paragraph);
    defer allocator.free(cluster_levels);
    var run_start: usize = 0;
    var run_level = cluster_levels[0].level;
    for (cluster_levels[1..], 1..) |cluster, index| {
        const level = cluster.level;
        if (level == run_level) continue;
        const byte_start = paragraph.scalars[cluster_levels[run_start].scalar_start].byte_start;
        const byte_end = paragraph.scalars[cluster.scalar_start].byte_start;
        try runs.append(allocator, .{
            .direction = directionForLevel(run_level),
            .byte_start = byte_start,
            .byte_len = byte_end - byte_start,
        });
        run_start = index;
        run_level = level;
    }
    const byte_start = paragraph.scalars[cluster_levels[run_start].scalar_start].byte_start;
    try runs.append(allocator, .{
        .direction = directionForLevel(run_level),
        .byte_start = byte_start,
        .byte_len = text.len - byte_start,
    });
    return try runs.toOwnedSlice(allocator);
}

pub fn buildBidiMap(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) !BidiMap {
    // The map keeps both visual order and logical-to-visual lookup, which lets
    // editor code move between byte offsets and rendered caret positions.
    var paragraph = try resolveBidiParagraph(
        allocator,
        text,
        if (base_direction == .rtl) .rtl else .ltr,
    );
    defer paragraph.deinit();
    const cluster_order = try visualGraphemeClusters(allocator, text, paragraph);
    defer allocator.free(cluster_order.clusters);
    const order = cluster_order.order;
    defer allocator.free(order);

    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    const logical_to_visual = try allocator.alloc(usize, paragraph.scalars.len);
    errdefer allocator.free(logical_to_visual);

    for (order) |cluster_index| {
        const cluster = cluster_order.clusters[cluster_index];
        for (cluster.scalar_start..cluster.scalar_end) |logical_index| {
            const scalar = paragraph.scalars[logical_index];
            const visual_index = items.items.len;
            logical_to_visual[logical_index] = visual_index;
            try items.append(allocator, .{
                .logical_index = logical_index,
                .visual_index = visual_index,
                .byte_start = scalar.byte_start,
                .byte_len = scalar.byte_len,
                .codepoint = scalar.codepoint,
                .visual_codepoint = if (cluster.level & 1 != 0)
                    bidi_paragraph.mirroredCodepoint(scalar.codepoint)
                else
                    scalar.codepoint,
                .direction = directionForLevel(cluster.level),
            });
        }
    }

    return .{
        .allocator = allocator,
        .items = try items.toOwnedSlice(allocator),
        .logical_to_visual = logical_to_visual,
    };
}

const VisualClusters = struct {
    clusters: []BidiCluster,
    order: []usize,
};

fn graphemeClusterLevels(
    allocator: std.mem.Allocator,
    text: []const u8,
    paragraph: BidiParagraph,
) ![]BidiCluster {
    const graphemes = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    const result = try allocator.alloc(BidiCluster, graphemes.len);
    for (graphemes, result) |grapheme, *cluster| {
        const scalar_start = paragraph.scalarIndexForByte(grapheme.byte_start) orelse
            return error.InvalidBidiMap;
        const scalar_end = paragraph.scalarIndexForByte(
            grapheme.byte_start + grapheme.byte_len,
        ) orelse return error.InvalidBidiMap;
        var level: u8 = paragraph.base_level;
        for (paragraph.levels[scalar_start..scalar_end]) |candidate| {
            if (candidate == 0xff) continue;
            level = @max(level, candidate);
        }
        cluster.* = .{
            .scalar_start = scalar_start,
            .scalar_end = scalar_end,
            .level = level,
        };
    }
    return result;
}

fn visualGraphemeClusters(
    allocator: std.mem.Allocator,
    text: []const u8,
    paragraph: BidiParagraph,
) !VisualClusters {
    const clusters = try graphemeClusterLevels(allocator, text, paragraph);
    errdefer allocator.free(clusters);
    const order = try allocator.alloc(usize, clusters.len);
    errdefer allocator.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    reorderBidiClusters(clusters, order);
    return .{ .clusters = clusters, .order = order };
}

fn reorderBidiClusters(clusters: []const BidiCluster, order: []usize) void {
    var max_level: u8 = 0;
    var minimum_odd: u8 = 0xff;
    for (clusters) |cluster| {
        max_level = @max(max_level, cluster.level);
        if (cluster.level & 1 != 0) minimum_odd = @min(minimum_odd, cluster.level);
    }
    if (minimum_odd == 0xff) return;
    var level = max_level;
    while (true) : (level -= 1) {
        var cursor: usize = 0;
        while (cursor < order.len) {
            if (clusters[order[cursor]].level < level) {
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < order.len and clusters[order[cursor]].level >= level) {
                cursor += 1;
            }
            std.mem.reverse(usize, order[start..cursor]);
        }
        if (level == minimum_odd) break;
    }
}

pub fn itemizeGraphemeClusters(allocator: std.mem.Allocator, text: []const u8) ![]GraphemeCluster {
    var clusters = std.ArrayList(GraphemeCluster).empty;
    errdefer clusters.deinit(allocator);

    var iterator = try graphemeClusters(text);
    while (iterator.next()) |cluster| try clusters.append(allocator, cluster);
    return try clusters.toOwnedSlice(allocator);
}

pub fn itemizeWordSegments(allocator: std.mem.Allocator, text: []const u8) ![]WordSegment {
    // This collector is intentionally a compatibility tailoring for editor
    // word movement: it omits punctuation/whitespace and retains several
    // script-specific numeric/symbol ranges that users expect to select with
    // their neighboring letters. New code that needs standard UAX #29
    // boundaries, including every non-word segment, should use `wordSegments`.
    var words = std.ArrayList(WordSegment).empty;
    errdefer words.deinit(allocator);

    var current_kind: WordKind = .none;
    var word_start: usize = 0;
    var word_end: usize = 0;
    // Latin-like text forms multi-codepoint words. East Asian scripts are
    // exposed as single-codepoint words because they do not require spaces.
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;
        var kind = wordKindForCodepoint(codepoint);
        if (isAsciiApostrophe(codepoint)) {
            // Keep common contractions such as "don't" as one word without
            // letting leading/trailing quote marks become part of a word span.
            // This intentionally requires a word on the left and an alphanumeric
            // continuation on the right; otherwise the apostrophe behaves like
            // punctuation and closes the current segment.
            const next_kind = if (nextCodepointAt(text, byte_end)) |next_codepoint| wordKindForCodepoint(next_codepoint) else .none;
            kind = if (current_kind == .latin_number and next_kind == .latin_number) .latin_number else .none;
        }
        if (kind == .none) {
            if (isWordExtender(codepoint)) {
                // UAX #29 treats Extend/Format-like codepoints as part of the
                // surrounding word. Preserve their bytes so caret and selection
                // logic does not strand accents, variation selectors, or joiners
                // outside the word segment they visually modify.
                if (current_kind != .none) {
                    word_end = byte_end;
                } else if (words.items.len > 0) {
                    const last = &words.items[words.items.len - 1];
                    const last_end = last.byte_start + last.byte_len;
                    if (last_end == byte_start) last.byte_len = byte_end - last.byte_start;
                }
                continue;
            }
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            continue;
        }
        if (kind == .single) {
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            try words.append(allocator, .{ .byte_start = byte_start, .byte_len = byte_end - byte_start });
            continue;
        }
        if (current_kind == .none) {
            current_kind = kind;
            word_start = byte_start;
            word_end = byte_end;
            continue;
        }
        if (current_kind == kind) {
            word_end = byte_end;
            continue;
        }
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
        current_kind = kind;
        word_start = byte_start;
        word_end = byte_end;
    }

    if (current_kind != .none) {
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
    }
    return try words.toOwnedSlice(allocator);
}

pub fn itemizeLineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]LineBreak {
    var breaks = std.ArrayList(LineBreak).empty;
    errdefer breaks.deinit(allocator);

    var iterator = try lineBreaks(text);
    while (iterator.next()) |opportunity| {
        try breaks.append(allocator, opportunity);
    }

    return try breaks.toOwnedSlice(allocator);
}

pub fn itemizeScriptRuns(allocator: std.mem.Allocator, text: []const u8) ![]ScriptRun {
    var runs = std.ArrayList(ScriptRun).empty;
    errdefer runs.deinit(allocator);

    var current_script: ?Script = null;
    var run_start: usize = 0;
    var run_end: usize = 0;
    // Script runs drive OpenType ScriptList selection. Common/inherited
    // codepoints stay with the surrounding run so punctuation does not split a
    // Latin, Arabic, or CJK shaping segment by itself.
    var cursor: usize = 0;
    while (cursor < text.len) {
        const cluster = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const next_index = decoded.next;
        cursor = next_index;
        const script = scriptForCodepoint(codepoint);
        if (current_script == null) {
            current_script = if (script == .common or script == .inherited) .common else script;
            run_start = cluster;
            run_end = next_index;
            continue;
        }
        if (scriptBelongsToRun(script, current_script.?)) {
            if (current_script.? == .common and script != .common and script != .inherited) {
                current_script = script;
            }
            run_end = next_index;
            continue;
        }
        try runs.append(allocator, .{
            .script = current_script.?,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
        current_script = if (script == .common or script == .inherited) .common else script;
        run_start = cluster;
        run_end = next_index;
    }

    if (current_script) |script| {
        try runs.append(allocator, .{
            .script = script,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
    }
    return try runs.toOwnedSlice(allocator);
}

fn directionForLevel(level: u8) BidiClass {
    return if (level & 1 == 0) .ltr else .rtl;
}

fn firstCodepoint(text: []const u8) ?u21 {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    return it.nextCodepoint();
}

pub fn mirroredCodepoint(codepoint: u21) u21 {
    return bidi_paragraph.mirroredCodepoint(codepoint);
}

test "streaming Arabic joining forms match bidirectional reference" {
    const alphabet = [_]u21{
        0x0628, // Arabic dual joining.
        0x0627, // Arabic right joining.
        0x0621, // Arabic non-joining.
        0x064e, // Arabic transparent.
        0x200d, // Join-causing ZWJ.
        0x200c, // Non-joining ZWNJ.
        0x0712, // Non-Arabic dual-joining Syriac.
        ' ', // Neutral non-joining separator.
    };
    var codepoints: [4]u21 = undefined;
    var expected: [4]JoiningForm = undefined;
    var actual: [4]JoiningForm = undefined;

    for (1..codepoints.len + 1) |len| {
        var combination_count: usize = 1;
        for (0..len) |_| combination_count *= alphabet.len;
        for (0..combination_count) |encoded| {
            var remaining = encoded;
            for (codepoints[0..len]) |*codepoint| {
                codepoint.* = alphabet[remaining % alphabet.len];
                remaining /= alphabet.len;
            }
            try resolveJoiningFormsReference(codepoints[0..len], expected[0..len]);
            try resolveJoiningForms(codepoints[0..len], actual[0..len]);
            try std.testing.expectEqualSlices(JoiningForm, expected[0..len], actual[0..len]);
        }
    }
}

const WordKind = word_selection.Kind;

fn wordKindForCodepoint(codepoint: u21) WordKind {
    const script: word_selection.Script = switch (scriptForCodepoint(codepoint)) {
        .han => .han,
        .yi => .yi,
        .nushu => .nushu,
        .hiragana => .hiragana,
        .katakana => .katakana,
        .hangul => .hangul,
        .arabic => .arabic,
        .hebrew => .hebrew,
        .armenian => .armenian,
        .devanagari => .devanagari,
        .bengali => .bengali,
        .odia => .odia,
        .gurmukhi => .gurmukhi,
        .telugu => .telugu,
        .kannada => .kannada,
        .sinhala => .sinhala,
        .tamil => .tamil,
        .malayalam => .malayalam,
        .balinese => .balinese,
        .javanese => .javanese,
        .tai_tham => .tai_tham,
        .marchen => .marchen,
        .limbu => .limbu,
        .buginese => .buginese,
        .sundanese => .sundanese,
        .meetei_mayek => .meetei_mayek,
        .canadian_aboriginal => .canadian_aboriginal,
        .cham => .cham,
        .brahmi => .brahmi,
        .khudawadi => .khudawadi,
        .tirhuta => .tirhuta,
        .modi => .modi,
        .takri => .takri,
        else => .other,
    };
    return word_selection.kindForCodepoint(codepoint, script);
}

fn nextCodepointAt(text: []const u8, offset: usize) ?u21 {
    return (decodeCodepointAt(text, offset) orelse return null).codepoint;
}

fn isDecimalDigit(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

fn isAsciiApostrophe(codepoint: u21) bool {
    return codepoint == '\'';
}

fn isWordExtender(codepoint: u21) bool {
    return codepoint == 0x200c or
        codepoint == 0x200d or
        isCombiningMark(codepoint) or
        isVariationSelector(codepoint) or
        isEmojiModifier(codepoint) or
        isSpacingMark(codepoint) or
        isWordFormat(codepoint);
}

fn isWordFormat(codepoint: u21) bool {
    return codepoint == 0x00ad or
        codepoint == 0x061c or
        codepoint == 0x180e or
        codepoint == 0x200e or
        codepoint == 0x200f or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x2064) or
        (codepoint >= 0x2066 and codepoint <= 0x206f) or
        codepoint == 0xfeff;
}

fn isCombiningMark(codepoint: u21) bool {
    // U+0300 is Unicode's first combining/mark scalar. Keep the compact
    // script-specific range chain out of ASCII and Latin-1 shaping loops.
    if (codepoint < 0x0300) return false;
    // One shift identifies the complete Devanagari block. It is worth
    // dispatching before the multi-script range chain because ordinary Hindi
    // letters dominate Indic shaping but are not marks; falling through would
    // test every earlier Latin/RTL/Tibetan mark family first.
    if (codepoint >> 7 == 0x12) return isDevanagariNonspacingMark(codepoint);
    // Likewise, Arabic shaping repeatedly asks this predicate while building
    // grapheme and bidi items. Resolve the base U+0600 block with its exact Mn
    // predicate before ordinary Arabic letters walk the complete Latin and
    // Hebrew mark chain. Arabic supplement/extended blocks remain in the
    // general chain because their sparse assignments cross block boundaries.
    if (codepoint >> 8 == 0x06) return isArabicBaseNonspacingMark(codepoint);
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

pub fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

pub fn isMongolianFreeVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0x180b and codepoint <= 0x180d) or codepoint == 0x180f;
}

fn isEmojiModifier(codepoint: u21) bool {
    return codepoint >= 0x1f3fb and codepoint <= 0x1f3ff;
}

fn isRegionalIndicator(codepoint: u21) bool {
    return codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff;
}

pub fn isSpacingMarkCodepoint(codepoint: u21) bool {
    return isSpacingMark(codepoint);
}

/// Return whether Unicode assigns General_Category=Nonspacing_Mark (Mn).
///
/// This is intentionally independent from grapheme Extend. OpenType shapers
/// use Mn to synthesize glyph classes when GDEF lacks a GlyphClassDef, whereas
/// Extend also includes spacing modifier letters and default-ignorables.
pub fn isNonspacingMarkCodepoint(codepoint: u21) bool {
    if (codepoint < 0x0300) return false;
    if (codepoint >> 7 == 0x12) return isDevanagariNonspacingMark(codepoint);
    return nonspacing_mark.contains(codepoint);
}

pub fn isUnicodeMarkCodepoint(codepoint: u21) bool {
    if (codepoint < 0x0300) return false;
    if (codepoint >> 7 == 0x12) {
        return isDevanagariNonspacingMark(codepoint) or
            isDevanagariSpacingMark(codepoint);
    }
    return isCombiningMark(codepoint) or isSpacingMark(codepoint);
}

fn isDevanagariNonspacingMark(codepoint: u21) bool {
    return (codepoint >= 0x0900 and codepoint <= 0x0902) or
        codepoint == 0x093a or
        codepoint == 0x093c or
        (codepoint >= 0x0941 and codepoint <= 0x0948) or
        codepoint == 0x094d or
        (codepoint >= 0x0951 and codepoint <= 0x0957) or
        (codepoint >= 0x0962 and codepoint <= 0x0963);
}

fn isDevanagariSpacingMark(codepoint: u21) bool {
    return codepoint == 0x0903 or
        (codepoint >= 0x093e and codepoint <= 0x0940) or
        (codepoint >= 0x0949 and codepoint <= 0x094c);
}

test "Unicode mark predicates preserve their lowest scalar boundaries" {
    for (0..0x0300) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        try std.testing.expect(!isCombiningMark(scalar));
        try std.testing.expect(!isNonspacingMarkCodepoint(scalar));
        try std.testing.expect(!isUnicodeMarkCodepoint(scalar));
    }
    for (0..0x0903) |codepoint| {
        try std.testing.expect(!isSpacingMarkCodepoint(@intCast(codepoint)));
    }

    try std.testing.expect(isCombiningMark(0x0300));
    try std.testing.expect(isNonspacingMarkCodepoint(0x0300));
    try std.testing.expect(isUnicodeMarkCodepoint(0x0300));
    try std.testing.expect(isSpacingMarkCodepoint(0x0903));
    try std.testing.expect(isUnicodeMarkCodepoint(0x0903));

    // Exhaust the base Arabic block against the generated Unicode Mn set so
    // its early dispatch cannot classify ordinary letters or punctuation as
    // grapheme extenders.
    for (0x0600..0x0700) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        try std.testing.expectEqual(
            nonspacing_mark.contains(scalar),
            isCombiningMark(scalar),
        );
    }

    // Exhaust the complete block so the early block dispatch cannot classify
    // an ordinary letter as a mark or drift from the exact retained ranges.
    for (0x0900..0x0980) |codepoint| {
        const scalar: u21 = @intCast(codepoint);
        const expected_nonspacing =
            (codepoint >= 0x0900 and codepoint <= 0x0902) or
            codepoint == 0x093a or
            codepoint == 0x093c or
            (codepoint >= 0x0941 and codepoint <= 0x0948) or
            codepoint == 0x094d or
            (codepoint >= 0x0951 and codepoint <= 0x0957) or
            (codepoint >= 0x0962 and codepoint <= 0x0963);
        const expected_spacing = codepoint == 0x0903 or
            (codepoint >= 0x093e and codepoint <= 0x0940) or
            (codepoint >= 0x0949 and codepoint <= 0x094c);
        try std.testing.expectEqual(expected_nonspacing, isCombiningMark(scalar));
        try std.testing.expectEqual(expected_nonspacing, isNonspacingMarkCodepoint(scalar));
        try std.testing.expectEqual(expected_spacing, isSpacingMarkCodepoint(scalar));
        try std.testing.expectEqual(expected_nonspacing or expected_spacing, isUnicodeMarkCodepoint(scalar));
    }
}

fn isEmojiTagCodepoint(codepoint: u21) bool {
    // Emoji flag tag sequences (for example subdivision flags such as England)
    // encode their tag letters in Plane 14. Unicode assigns these scalars
    // Grapheme_Cluster_Break=Extend, so they must stay attached to the
    // preceding pictograph instead of creating one caret stop per tag byte.
    return codepoint >= 0xe0020 and codepoint <= 0xe007f;
}

fn isSpacingMark(codepoint: u21) bool {
    // U+0903 DEVANAGARI SIGN VISARGA is the first Unicode spacing mark.
    if (codepoint < 0x0903) return false;
    if (codepoint >> 7 == 0x12) return isDevanagariSpacingMark(codepoint);
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

fn scriptBelongsToRun(script: Script, current: Script) bool {
    // Common and inherited scripts adopt the current run script. If a run starts
    // as common, let the first strong script continue it.
    if (script == current) return true;
    if (script == .common or script == .inherited) return true;
    if (current == .common) return true;
    return false;
}

fn isCommonCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x0040) or
        (codepoint >= 0x005b and codepoint <= 0x0060) or
        (codepoint >= 0x007b and codepoint <= 0x00a9) or
        (codepoint >= 0x2000 and codepoint <= 0x206f) or
        (codepoint >= 0x3000 and codepoint <= 0x303f);
}

test {
    _ = @import("unicode/tests_contracts.zig");
    _ = @import("unicode/tests_rtl_scripts.zig");
    _ = @import("unicode/tests_segmentation.zig");
    _ = @import("unicode/tests_indic_use.zig");
    _ = @import("unicode/tests_scripts_core.zig");
    _ = @import("unicode/tests_scripts_extended.zig");
}
