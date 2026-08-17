//! Unicode joining properties and Arabic-style positional-form resolution.
//!
//! This module owns the data-driven joining state machine but deliberately
//! does not own script classification. Callers provide a comptime policy that
//! decides which scalars actually use Arabic-style positional OpenType forms.
//! Keeping that dependency explicit prevents the low-level joining data from
//! depending on the larger script itemizer.

const std = @import("std");

/// Unicode Joining_Type values used by cursive-script shaping.
///
/// The compact range table below is generated from Unicode 15.1
/// DerivedJoiningType.txt for Arabic/Syriac/N'Ko/Mandaic codepoint blocks plus
/// the Mongolian values currently needed by the Arabic-style shaper and ZWJ.
/// Unlisted codepoints have the normative Non_Joining default.
pub const Type = enum {
    non_joining,
    right,
    left,
    dual,
    join_causing,
    transparent,
};

/// Positional OpenType form selected by the Unicode joining algorithm.
pub const Form = enum {
    none,
    isolated,
    initial,
    medial,
    final,
};

const TypeRange = struct {
    first: u21,
    last: u21,
    kind: Type,
};

const type_ranges = [_]TypeRange{
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

pub fn typeForCodepoint(codepoint: u21) Type {
    var low: usize = 0;
    var high: usize = type_ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = type_ranges[mid];
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
/// `Policy` must expose `pub fn hasForms(codepoint: u21) bool`. The policy is a
/// comptime parameter so script classification remains statically bound and
/// adds neither callback storage nor an indirect call to the shaping path.
///
/// Transparent joining characters do not break the connection between their
/// neighbors and receive no positional feature themselves. Scalars rejected by
/// the policy are left as `.none`, so callers may pass mixed-script runs
/// without accidentally enabling positional features for punctuation or digits.
pub fn resolve(
    comptime Policy: type,
    codepoints: []const u21,
    forms: []Form,
) error{InvalidJoiningInput}!void {
    if (forms.len != codepoints.len) return error.InvalidJoiningInput;
    @memset(forms, .none);

    var previous: ?Type = null;
    var pending_index: ?usize = null;
    var pending_kind: Type = .non_joining;
    var pending_joins_previous = false;

    for (codepoints, 0..) |codepoint, index| {
        const current = typeForCodepoint(codepoint);
        if (current == .transparent) continue;

        // The next non-transparent character resolves the pending character's
        // right connection. This avoids two repeated directional searches per
        // scalar while preserving transparent-character semantics.
        if (pending_index) |pending| {
            const joins_next = joinsLeft(pending_kind) and joinsRight(current);
            forms[pending] = formForConnections(pending_joins_previous, joins_next);
        }
        pending_index = null;

        if (current != .non_joining and Policy.hasForms(codepoint)) {
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
        forms[pending] = formForConnections(pending_joins_previous, false);
    }
}

fn formForConnections(joins_previous: bool, joins_next: bool) Form {
    return if (joins_previous and joins_next)
        .medial
    else if (joins_previous)
        .final
    else if (joins_next)
        .initial
    else
        .isolated;
}

fn joinsRight(kind: Type) bool {
    return kind == .right or kind == .dual or kind == .join_causing;
}

fn joinsLeft(kind: Type) bool {
    return kind == .left or kind == .dual or kind == .join_causing;
}

fn resolveReference(
    comptime Policy: type,
    codepoints: []const u21,
    forms: []Form,
) error{InvalidJoiningInput}!void {
    if (forms.len != codepoints.len) return error.InvalidJoiningInput;
    @memset(forms, .none);

    // Retain the former bidirectional implementation as a test oracle for the
    // streaming state machine. This is intentionally not used by shaping.
    for (codepoints, 0..) |codepoint, index| {
        const current = typeForCodepoint(codepoint);
        if (current == .transparent or current == .non_joining or !Policy.hasForms(codepoint)) continue;

        var previous: ?Type = null;
        var previous_index = index;
        while (previous_index > 0) {
            previous_index -= 1;
            const kind = typeForCodepoint(codepoints[previous_index]);
            if (kind == .transparent) continue;
            previous = kind;
            break;
        }

        var next: ?Type = null;
        var next_index = index + 1;
        while (next_index < codepoints.len) : (next_index += 1) {
            const kind = typeForCodepoint(codepoints[next_index]);
            if (kind == .transparent) continue;
            next = kind;
            break;
        }

        const joins_previous = if (previous) |kind| joinsLeft(kind) and joinsRight(current) else false;
        const joins_next = if (next) |kind| joinsLeft(current) and joinsRight(kind) else false;
        forms[index] = formForConnections(joins_previous, joins_next);
    }
}

const TestPolicy = struct {
    pub fn hasForms(codepoint: u21) bool {
        // Mirror the root module's script policy without exposing its private
        // itemizer predicates solely for this white-box state-machine test.
        return (codepoint >= 0x0600 and codepoint <= 0x06FF) or
            (codepoint >= 0x0750 and codepoint <= 0x077F) or
            (codepoint >= 0x0870 and codepoint <= 0x08FF) or
            (codepoint >= 0x10EFD and codepoint <= 0x10EFF) or
            (codepoint >= 0xFB50 and codepoint <= 0xFDFF) or
            (codepoint >= 0xFE70 and codepoint <= 0xFEFC) or
            (codepoint >= 0x1800 and codepoint <= 0x18AF) or
            (codepoint >= 0x1E900 and codepoint <= 0x1E94B) or
            (codepoint >= 0x1E950 and codepoint <= 0x1E959) or
            (codepoint >= 0x1E95E and codepoint <= 0x1E95F) or
            (codepoint >= 0xA840 and codepoint <= 0xA877);
    }
};

test "streaming Arabic joining forms match bidirectional reference" {
    const alphabet = [_]u21{
        0x0628, // Arabic dual joining.
        0x0627, // Arabic right joining.
        0x0621, // Arabic non-joining.
        0x064E, // Arabic transparent.
        0x200D, // Join-causing ZWJ.
        0x200C, // Non-joining ZWNJ.
        0x0712, // Non-Arabic dual-joining Syriac.
        ' ', // Neutral non-joining separator.
    };
    var codepoints: [4]u21 = undefined;
    var expected: [4]Form = undefined;
    var actual: [4]Form = undefined;

    for (1..codepoints.len + 1) |len| {
        var combination_count: usize = 1;
        for (0..len) |_| combination_count *= alphabet.len;
        for (0..combination_count) |encoded| {
            var remaining = encoded;
            for (codepoints[0..len]) |*codepoint| {
                codepoint.* = alphabet[remaining % alphabet.len];
                remaining /= alphabet.len;
            }
            try resolveReference(TestPolicy, codepoints[0..len], expected[0..len]);
            try resolve(TestPolicy, codepoints[0..len], actual[0..len]);
            try std.testing.expectEqualSlices(Form, expected[0..len], actual[0..len]);
        }
    }
}
