const std = @import("std");

const categories = @import("categories.zig");
const Category = categories.Category;

pub const Kind = enum(u4) {
    consonant = 0,
    broken = 1,
    non_myanmar = 2,
};

pub fn kindOf(syllable: u8) Kind {
    return @enumFromInt(syllable & 0x0f);
}

/// Mark Myanmar syllables in current glyph order.
///
/// HarfBuzz runs the Myanmar machine after canonical mark reordering but
/// before `locl`/`ccmp`. `glyph_source_indices` therefore supplies the order
/// seen by the grammar while `source_syllables` keeps the stable source-level
/// identity needed by Cangjie's GSUB dispatcher.
pub fn mark(
    source_syllables: []u8,
    glyph_source_indices: []const usize,
    codepoints: []const u21,
) void {
    @memset(source_syllables, 0);

    var glyph_index: usize = 0;
    var serial: u8 = 1;
    while (glyph_index < glyph_source_indices.len) {
        const match = matchAt(glyph_source_indices, codepoints, glyph_index);
        const end = @max(match.end, glyph_index + 1);
        const syllable = (serial << 4) | @intFromEnum(match.kind);
        for (glyph_source_indices[glyph_index..end]) |source| {
            if (source < source_syllables.len) source_syllables[source] = syllable;
        }
        serial = if (serial == 15) 1 else serial + 1;
        glyph_index = end;
    }
}

const Match = struct {
    end: usize,
    kind: Kind,
};

fn matchAt(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) Match {
    const first = categoryAt(glyph_source_indices, codepoints, start);
    const consonant_end = matchConsonantSyllable(glyph_source_indices, codepoints, start);
    const broken_end = matchBrokenCluster(glyph_source_indices, codepoints, start);
    const explicit_non_myanmar_end = if (categories.isJoiner(first) or
        first == .syllable_modifier_post) start + 1 else start;

    // Ragel's scanner uses maximal munch, then resolves equal-length matches
    // by source order: consonant, explicit joiner/SMPst, broken, other.
    const longest = @max(consonant_end, @max(explicit_non_myanmar_end, broken_end));
    if (consonant_end == longest and longest > start) {
        return .{ .end = longest, .kind = .consonant };
    }
    if (explicit_non_myanmar_end == longest and longest > start) {
        return .{ .end = longest, .kind = .non_myanmar };
    }
    if (broken_end == longest and longest > start) {
        return .{ .end = longest, .kind = .broken };
    }
    return .{ .end = start + 1, .kind = .non_myanmar };
}

fn matchConsonantSyllable(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var best = start;
    if (isMyanmarBase(categoryAt(glyph_source_indices, codepoints, start))) {
        best = matchConsonantAfterPrefix(glyph_source_indices, codepoints, start);
    }

    const kinzi_end = matchKinzi(glyph_source_indices, codepoints, start);
    if (kinzi_end > start and isMyanmarBase(categoryAt(glyph_source_indices, codepoints, kinzi_end))) {
        best = @max(best, matchConsonantAfterPrefix(glyph_source_indices, codepoints, kinzi_end));
    }
    if (categoryAt(glyph_source_indices, codepoints, start) == .consonant_with_stacker and
        isMyanmarBase(categoryAt(glyph_source_indices, codepoints, start + 1)))
    {
        best = @max(best, matchConsonantAfterPrefix(glyph_source_indices, codepoints, start + 1));
    }
    return best;
}

fn matchConsonantAfterPrefix(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    const category = categoryAt(glyph_source_indices, codepoints, start);
    if (!isMyanmarBase(category)) return start;

    var cursor = start + 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .variation_selector) cursor += 1;
    return matchSyllableTail(glyph_source_indices, codepoints, cursor);
}

fn matchBrokenCluster(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var best = matchBrokenAfterKinzi(glyph_source_indices, codepoints, start);
    const kinzi_end = matchKinzi(glyph_source_indices, codepoints, start);
    if (kinzi_end > start) {
        best = @max(best, matchBrokenAfterKinzi(glyph_source_indices, codepoints, kinzi_end));
    }
    return best;
}

fn matchBrokenAfterKinzi(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .variation_selector) cursor += 1;
    const end = matchSyllableTail(glyph_source_indices, codepoints, cursor);
    // The grammar can accept an empty complex tail, but a scanner token must
    // consume at least one glyph. Callers use a one-glyph non-Myanmar fallback.
    return if (end > start) end else start;
}

fn matchKinzi(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    if (categoryAt(glyph_source_indices, codepoints, start) != .ra or
        categoryAt(glyph_source_indices, codepoints, start + 1) != .asat or
        categoryAt(glyph_source_indices, codepoints, start + 2) != .halant)
    {
        return start;
    }
    return start + 3;
}

fn matchSyllableTail(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .halant and
        isStackedBase(categoryAt(glyph_source_indices, codepoints, cursor + 1)))
    {
        cursor += 2;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .variation_selector) cursor += 1;
    }
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .halant) return cursor + 1;
    return matchComplexTail(glyph_source_indices, codepoints, cursor);
}

fn matchComplexTail(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    cursor = matchMedialGroup(glyph_source_indices, codepoints, cursor);
    cursor = matchMainVowelGroup(glyph_source_indices, codepoints, cursor);
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .vowel_post) {
        cursor = matchPostVowelGroup(glyph_source_indices, codepoints, cursor);
    }
    while (isToneStart(categoryAt(glyph_source_indices, codepoints, cursor))) {
        cursor = matchToneGroup(glyph_source_indices, codepoints, cursor);
    }
    if (categories.isJoiner(categoryAt(glyph_source_indices, codepoints, cursor))) cursor += 1;
    return cursor;
}

fn matchMedialGroup(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_ya) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_ra) cursor += 1;

    const category = categoryAt(glyph_source_indices, codepoints, cursor);
    if (category == .medial_wa) {
        cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_ha) cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_la) cursor += 1;
    } else if (category == .medial_ha) {
        cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_la) cursor += 1;
    } else if (category == .medial_la) {
        cursor += 1;
    } else {
        return cursor;
    }
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    return cursor;
}

fn matchMainVowelGroup(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .vowel_pre) {
        cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .variation_selector) cursor += 1;
    }
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .vowel_above) cursor += 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .vowel_below) cursor += 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .tone_a) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .dot_below) {
        cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    }
    return cursor;
}

fn matchPostVowelGroup(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    var cursor = start + 1; // caller proves VPst
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_ha) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .medial_la) cursor += 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .vowel_above) cursor += 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .tone_a) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .dot_below) {
        cursor += 1;
        if (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    }
    return cursor;
}

fn matchToneGroup(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    start: usize,
) usize {
    const category = categoryAt(glyph_source_indices, codepoints, start);
    if (category == .syllable_modifier or category == .syllable_modifier_post) return start + 1;

    std.debug.assert(category == .pwo_tone);
    var cursor = start + 1;
    while (categoryAt(glyph_source_indices, codepoints, cursor) == .tone_a) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .dot_below) cursor += 1;
    if (categoryAt(glyph_source_indices, codepoints, cursor) == .asat) cursor += 1;
    return cursor;
}

fn categoryAt(
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    glyph_index: usize,
) Category {
    if (glyph_index >= glyph_source_indices.len) return .other;
    const source = glyph_source_indices[glyph_index];
    if (source >= codepoints.len) return .other;
    return categories.forCodepoint(codepoints[source]);
}

fn isMyanmarBase(category: Category) bool {
    return switch (category) {
        .consonant, .ra, .independent_vowel, .generic_base, .dotted_circle => true,
        else => false,
    };
}

fn isStackedBase(category: Category) bool {
    return category == .consonant or category == .ra or category == .independent_vowel;
}

fn isToneStart(category: Category) bool {
    return category == .syllable_modifier or
        category == .syllable_modifier_post or
        category == .pwo_tone;
}

test "Myanmar grammar handles adjacency and kinzi boundaries" {
    const adjacent_codepoints = [_]u21{ 0x1000, 0x1001, 0x1031 };
    const adjacent_sources = [_]usize{ 0, 1, 2 };
    var adjacent_syllables = [_]u8{0} ** adjacent_codepoints.len;
    mark(&adjacent_syllables, &adjacent_sources, &adjacent_codepoints);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x20, 0x20 }, &adjacent_syllables);

    const kinzi_codepoints = [_]u21{ 0x1004, 0x103a, 0x1039, 0x101b, 0x103d, 0x102d };
    const kinzi_sources = [_]usize{ 0, 1, 2, 3, 4, 5 };
    var kinzi_syllables = [_]u8{0} ** kinzi_codepoints.len;
    mark(&kinzi_syllables, &kinzi_sources, &kinzi_codepoints);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10 }, &kinzi_syllables);
}

test "Myanmar scanner preserves maximal-munch edge cases" {
    const cases = [_]struct {
        codepoints: []const u21,
        expected: []const u8,
    }{
        .{ .codepoints = &.{0x0cf1}, .expected = &.{0x12} },
        .{ .codepoints = &.{ 0x00b2, 0x200c }, .expected = &.{ 0x11, 0x11 } },
        .{ .codepoints = &.{ 0x1004, 0x103a, 0x1039 }, .expected = &.{ 0x11, 0x11, 0x11 } },
        .{ .codepoints = &.{ 0x200c, 0x1031 }, .expected = &.{ 0x12, 0x21 } },
    };
    for (cases) |case| {
        var sources_buf: [3]usize = undefined;
        var syllables_buf: [3]u8 = undefined;
        const sources = sources_buf[0..case.codepoints.len];
        const syllables_out = syllables_buf[0..case.codepoints.len];
        for (sources, 0..) |*source, index| source.* = index;
        mark(syllables_out, sources, case.codepoints);
        try std.testing.expectEqualSlices(u8, case.expected, syllables_out);
    }
}

test {
    std.testing.refAllDecls(@This());
}
