const std = @import("std");

const categories = @import("categories.zig");
const gsub = @import("../gsub.zig");
const unicode = @import("../unicode.zig");

pub const SyllableType = enum(u4) {
    virama_terminated,
    sakot_terminated,
    standard,
    number_joiner_terminated,
    numeral,
    symbol,
    hieroglyph,
    broken,
    non_cluster,
};

pub const Syllable = struct {
    start: usize,
    end: usize,
    kind: SyllableType,
};

const IncludedCodepoint = struct {
    source_index: usize,
    category: categories.Category,
};

const locl_mask = gsub.sourceFeatureMaskForTag(unicode.tag("locl")).?;
const ccmp_mask = gsub.sourceFeatureMaskForTag(unicode.tag("ccmp")).?;
const nukt_mask = gsub.sourceFeatureMaskForTag(unicode.tag("nukt")).?;
const akhn_mask = gsub.sourceFeatureMaskForTag(unicode.tag("akhn")).?;
const rphf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("rphf")).?;
const pref_mask = gsub.sourceFeatureMaskForTag(unicode.tag("pref")).?;
const rkrf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("rkrf")).?;
const abvf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("abvf")).?;
const blwf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("blwf")).?;
const half_mask = gsub.sourceFeatureMaskForTag(unicode.tag("half")).?;
const pstf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("pstf")).?;
const vatu_mask = gsub.sourceFeatureMaskForTag(unicode.tag("vatu")).?;
const cjct_mask = gsub.sourceFeatureMaskForTag(unicode.tag("cjct")).?;
const isol_mask = gsub.sourceFeatureMaskForTag(unicode.tag("isol")).?;
const init_mask = gsub.sourceFeatureMaskForTag(unicode.tag("init")).?;
const medi_mask = gsub.sourceFeatureMaskForTag(unicode.tag("medi")).?;
const fina_mask = gsub.sourceFeatureMaskForTag(unicode.tag("fina")).?;
const topo_mask = isol_mask | init_mask | medi_mask | fina_mask;

const per_syllable_mask =
    locl_mask |
    ccmp_mask |
    nukt_mask |
    akhn_mask |
    pref_mask |
    rkrf_mask |
    abvf_mask |
    blwf_mask |
    half_mask |
    pstf_mask |
    vatu_mask |
    cjct_mask;

pub fn find(allocator: std.mem.Allocator, codepoints: []const u21) ![]Syllable {
    var included = std.ArrayList(IncludedCodepoint).empty;
    defer included.deinit(allocator);
    try appendIncludedCodepoints(&included, allocator, codepoints);

    var syllables = std.ArrayList(Syllable).empty;
    errdefer syllables.deinit(allocator);

    var index: usize = 0;
    while (index < included.items.len) {
        const match = matchSyllable(included.items, index);
        const start = included.items[index].source_index;
        const end = originalEndForIncludedMatch(included.items, codepoints.len, match.next_index);
        try syllables.append(allocator, .{
            .start = start,
            .end = end,
            .kind = match.kind,
        });
        index = match.next_index;
    }

    return try syllables.toOwnedSlice(allocator);
}

pub fn markSourceFeatures(
    allocator: std.mem.Allocator,
    source_features: []u32,
    source_syllables: []u8,
    codepoints: []const u21,
) !void {
    if (source_features.len != codepoints.len) return error.InvalidUseInput;
    if (source_syllables.len != codepoints.len) return error.InvalidUseInput;
    @memset(source_features, 0);
    @memset(source_syllables, 0);

    const syllables = try find(allocator, codepoints);
    defer allocator.free(syllables);

    for (syllables, 0..) |syllable, syllable_index| {
        const serial: u8 = @intCast((syllable_index % 15) + 1);
        markSyllableRange(source_syllables, syllable.start, syllable.end, serial);
        markRange(source_features, syllable.start, syllable.end, per_syllable_mask);
        markRphfSources(source_features, codepoints, syllable);
    }
    markTopographicalSources(source_features, syllables);
}

fn appendIncludedCodepoints(
    included: *std.ArrayList(IncludedCodepoint),
    allocator: std.mem.Allocator,
    codepoints: []const u21,
) !void {
    for (codepoints, 0..) |codepoint, index| {
        const category = categories.forCodepoint(codepoint);
        if (!isIncluded(codepoints, index, category)) continue;
        try included.append(allocator, .{ .source_index = index, .category = category });
    }
}

fn isIncluded(codepoints: []const u21, index: usize, category: categories.Category) bool {
    if (category == .cg_joiner) return false;
    if (category != .zwnj) return true;

    var next = index + 1;
    while (next < codepoints.len) : (next += 1) {
        const next_category = categories.forCodepoint(codepoints[next]);
        if (next_category == .cg_joiner) continue;
        return !categories.isUnicodeMarkForUse(codepoints[next]);
    }
    return true;
}

const SyllableMatch = struct {
    next_index: usize,
    kind: SyllableType,
};

fn matchSyllable(items: []const IncludedCodepoint, start: usize) SyllableMatch {
    if (items[start].category == .final_mod_post) {
        return .{ .next_index = start + 1, .kind = .non_cluster };
    }
    if (matchHieroglyphCluster(items, start)) |next| {
        return .{ .next_index = next, .kind = .hieroglyph };
    }
    if (matchNumberJoinerTerminatedCluster(items, start)) |next| {
        return .{ .next_index = next, .kind = .number_joiner_terminated };
    }
    if (matchNumeralCluster(items, start)) |next| {
        return .{ .next_index = next, .kind = .numeral };
    }
    if (matchViramaTerminatedCluster(items, start)) |next| {
        return withOptionalZwnj(items, next, .virama_terminated);
    }
    if (matchSakotTerminatedCluster(items, start)) |next| {
        return withOptionalZwnj(items, next, .sakot_terminated);
    }
    if (matchStandardCluster(items, start)) |next| {
        return withOptionalZwnj(items, next, .standard);
    }
    if (matchSymbolCluster(items, start)) |next| {
        return withOptionalZwnj(items, next, .symbol);
    }
    if (matchBrokenCluster(items, start)) |next| {
        return withOptionalZwnj(items, next, .broken);
    }
    return .{ .next_index = start + 1, .kind = .non_cluster };
}

fn withOptionalZwnj(items: []const IncludedCodepoint, next: usize, kind: SyllableType) SyllableMatch {
    const adjusted_next = if (next < items.len and items[next].category == .zwnj) next + 1 else next;
    return .{ .next_index = adjusted_next, .kind = kind };
}

fn originalEndForIncludedMatch(items: []const IncludedCodepoint, codepoint_len: usize, next_index: usize) usize {
    if (next_index < items.len) return items[next_index].source_index;
    return codepoint_len;
}

fn matchStandardCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = matchComplexSyllableStart(items, start) orelse return null;
    index = consumeComplexSyllableTail(items, index);
    return index;
}

fn matchViramaTerminatedCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = matchComplexSyllableStart(items, start) orelse return null;
    index = consumeConsonantModifiers(items, index);
    if (index >= items.len) return null;
    return switch (items[index].category) {
        .invisible_stacker, .reordering_killer => index + 1,
        else => null,
    };
}

fn matchSakotTerminatedCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = matchComplexSyllableStart(items, start) orelse return null;
    index = consumeComplexSyllableMiddle(items, index);
    if (index < items.len and items[index].category == .sakot) return index + 1;
    return null;
}

fn matchBrokenCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    if (items[index].category == .repha) index += 1;
    const tail_end = matchTail(items, index) orelse
        matchNumberJoinerTerminatedClusterTail(items, index) orelse
        matchNumeralClusterTail(items, index) orelse
        return null;
    return tail_end;
}

fn matchTail(items: []const IncludedCodepoint, start: usize) ?usize {
    if (matchSakotTerminatedClusterTail(items, start)) |next| return next;
    if (matchSymbolClusterTail(items, start)) |next| return next;
    if (matchViramaTerminatedClusterTail(items, start)) |next| return next;
    return consumeComplexSyllableTail(items, start);
}

fn matchSakotTerminatedClusterTail(items: []const IncludedCodepoint, start: usize) ?usize {
    const next = consumeComplexSyllableMiddle(items, start);
    if (next < items.len and items[next].category == .sakot) return next + 1;
    return null;
}

fn matchViramaTerminatedClusterTail(items: []const IncludedCodepoint, start: usize) ?usize {
    const next = consumeConsonantModifiers(items, start);
    if (next < items.len and (items[next].category == .invisible_stacker or items[next].category == .reordering_killer)) {
        return next + 1;
    }
    return null;
}

fn matchComplexSyllableStart(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    if (items[index].category == .repha or items[index].category == .cons_with_stacker) index += 1;
    if (index >= items.len) return null;
    return if (isBase(items[index].category)) index + 1 else null;
}

fn consumeComplexSyllableTail(items: []const IncludedCodepoint, start: usize) usize {
    var index = consumeComplexSyllableMiddle(items, start);
    while (index < items.len and isFinalConsonant(items[index].category)) : (index += 1) {}
    while (index < items.len and (items[index].category == .final_mod_above or items[index].category == .final_mod_below)) : (index += 1) {}
    if (index < items.len and items[index].category == .final_mod_post) index += 1;
    return index;
}

fn consumeComplexSyllableMiddle(items: []const IncludedCodepoint, start: usize) usize {
    var index = consumeConsonantModifiers(items, start);
    index = consumeMedialConsonants(items, index);
    index = consumeDependentVowels(items, index);
    index = consumeVowelModifiers(items, index);
    while (index + 1 < items.len and items[index].category == .sakot and isBase(items[index + 1].category)) : (index += 2) {}
    return index;
}

fn consumeConsonantModifiers(items: []const IncludedCodepoint, start: usize) usize {
    var index = start;
    while (index < items.len and items[index].category == .consonant_mod_above) : (index += 1) {}
    while (index < items.len and items[index].category == .consonant_mod_below) : (index += 1) {}
    while (index < items.len) {
        if (index + 1 < items.len and isHalantGroup(items[index].category) and isBase(items[index + 1].category)) {
            index += 2;
        } else if (items[index].category == .cons_sub) {
            index += 1;
        } else {
            break;
        }
        while (index < items.len and items[index].category == .consonant_mod_above) : (index += 1) {}
        while (index < items.len and items[index].category == .consonant_mod_below) : (index += 1) {}
    }
    return index;
}

fn consumeMedialConsonants(items: []const IncludedCodepoint, start: usize) usize {
    var index = start;
    if (index < items.len and items[index].category == .medial_pre) index += 1;
    if (index < items.len and items[index].category == .medial_above) index += 1;
    if (index < items.len and items[index].category == .medial_below) index += 1;
    if (index < items.len and items[index].category == .medial_post) index += 1;
    return index;
}

fn consumeDependentVowels(items: []const IncludedCodepoint, start: usize) usize {
    var index = start;
    if (index < items.len and items[index].category == .halant) return index + 1;
    while (index < items.len and items[index].category == .vowel_pre) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_above) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_below) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_post) : (index += 1) {}
    return index;
}

fn consumeVowelModifiers(items: []const IncludedCodepoint, start: usize) usize {
    var index = start;
    if (index < items.len and items[index].category == .halant_or_vowel_mod) index += 1;
    while (index < items.len and items[index].category == .vowel_mod_pre) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_mod_above) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_mod_below) : (index += 1) {}
    while (index < items.len and items[index].category == .vowel_mod_post) : (index += 1) {}
    return index;
}

fn matchNumberJoinerTerminatedCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    if (items[start].category != .base_num) return null;
    return matchNumberJoinerTerminatedClusterTail(items, start + 1);
}

fn matchNumberJoinerTerminatedClusterTail(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    while (index + 1 < items.len and items[index].category == .halant_num and items[index + 1].category == .base_num) : (index += 2) {}
    if (index < items.len and items[index].category == .halant_num) return index + 1;
    return null;
}

fn matchNumeralCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    if (items[start].category != .base_num) return null;
    const tail = matchNumeralClusterTail(items, start + 1) orelse start + 1;
    return tail;
}

fn matchNumeralClusterTail(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    var consumed = false;
    while (index + 1 < items.len and items[index].category == .halant_num and items[index + 1].category == .base_num) : (index += 2) {
        consumed = true;
    }
    return if (consumed) index else null;
}

fn matchSymbolCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    return switch (items[start].category) {
        .other, .base_other, .hieroglyph_segment_begin => matchSymbolClusterTail(items, start + 1) orelse start + 1,
        else => null,
    };
}

fn matchSymbolClusterTail(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    var consumed_above = false;
    while (index < items.len and items[index].category == .symbol_mod_above) : (index += 1) {
        consumed_above = true;
    }
    if (consumed_above) {
        while (index < items.len and items[index].category == .symbol_mod_below) : (index += 1) {}
        return index;
    }

    var consumed_below = false;
    while (index < items.len and items[index].category == .symbol_mod_below) : (index += 1) {
        consumed_below = true;
    }
    return if (consumed_below) index else null;
}

fn matchHieroglyphCluster(items: []const IncludedCodepoint, start: usize) ?usize {
    var index = start;
    while (index < items.len and items[index].category == .hieroglyph_segment_begin) : (index += 1) {}
    if (index >= items.len or items[index].category != .hieroglyph) return null;
    index += 1;
    if (index < items.len and items[index].category == .hieroglyph_mirror) index += 1;
    if (index < items.len and items[index].category == .hieroglyph_mod) index += 1;
    while (index < items.len and items[index].category == .hieroglyph_segment_end) : (index += 1) {}

    while (index < items.len and items[index].category == .hieroglyph_joiner) {
        index += 1;
        while (index < items.len and items[index].category == .hieroglyph_segment_begin) : (index += 1) {}
        if (index < items.len and items[index].category == .hieroglyph) {
            index += 1;
            if (index < items.len and items[index].category == .hieroglyph_mirror) index += 1;
            if (index < items.len and items[index].category == .hieroglyph_mod) index += 1;
            while (index < items.len and items[index].category == .hieroglyph_segment_end) : (index += 1) {}
        }
    }
    return index;
}

fn isBase(category: categories.Category) bool {
    return category == .base or category == .base_other;
}

fn isHalantGroup(category: categories.Category) bool {
    return category == .halant or category == .halant_or_vowel_mod or category == .invisible_stacker or category == .sakot;
}

fn isFinalConsonant(category: categories.Category) bool {
    return category == .final_above or category == .final_below or category == .final_post;
}

fn markRange(source_features: []u32, start: usize, end: usize, mask: u32) void {
    for (source_features[start..end]) |*feature| {
        feature.* |= mask;
    }
}

fn markSyllableRange(source_syllables: []u8, start: usize, end: usize, serial: u8) void {
    for (source_syllables[start..end]) |*syllable| {
        syllable.* = serial;
    }
}

fn markRphfSources(source_features: []u32, codepoints: []const u21, syllable: Syllable) void {
    if (syllable.start >= syllable.end) return;
    const first_category = categories.forCodepoint(codepoints[syllable.start]);
    const limit = if (first_category == .repha) syllable.start + 1 else @min(syllable.start + 3, syllable.end);
    markRange(source_features, syllable.start, limit, rphf_mask);
}

const JoiningForm = enum {
    isolated,
    initial,
    medial,
    terminal,
};

fn markTopographicalSources(source_features: []u32, syllables: []const Syllable) void {
    var last_start: usize = 0;
    var last_end: usize = 0;
    var last_form: ?JoiningForm = null;

    for (syllables) |syllable| {
        if (syllable.kind == .hieroglyph or syllable.kind == .non_cluster) {
            last_form = null;
        } else {
            const join = last_form == .terminal or last_form == .isolated;
            if (join) {
                const replacement: JoiningForm = if (last_form == .terminal) .medial else .initial;
                markTopographicalRange(source_features, last_start, last_end, replacement);
            }

            const form: JoiningForm = if (join) .terminal else .isolated;
            markTopographicalRange(source_features, syllable.start, syllable.end, form);
            last_form = form;
        }

        last_start = syllable.start;
        last_end = syllable.end;
    }
}

fn markTopographicalRange(source_features: []u32, start: usize, end: usize, form: JoiningForm) void {
    const form_mask = switch (form) {
        .isolated => isol_mask,
        .initial => init_mask,
        .medial => medi_mask,
        .terminal => fina_mask,
    };
    for (source_features[start..end]) |*feature| {
        feature.* = (feature.* & ~topo_mask) | form_mask;
    }
}

test "USE syllables keep CGJ with surrounding Duployan source range" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1bc02, 0x1bc5b, 0x034f, 0x034f, 0x034f, 0x1bc1c, 0x200c, 0x1bc02 };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqual(@as(usize, 4), syllables.len);
    try std.testing.expectEqual(Syllable{ .start = 0, .end = 1, .kind = .standard }, syllables[0]);
    try std.testing.expectEqual(Syllable{ .start = 1, .end = 5, .kind = .standard }, syllables[1]);
    try std.testing.expectEqual(Syllable{ .start = 5, .end = 7, .kind = .standard }, syllables[2]);
    try std.testing.expectEqual(Syllable{ .start = 7, .end = 8, .kind = .standard }, syllables[3]);
}

test "USE source features assign topographical forms per syllable" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1bc02, 0x1bc5b, 0x034f, 0x034f, 0x034f, 0x1bc1c, 0x200c, 0x1bc02 };
    var source_features = [_]u32{0} ** codepoints.len;
    var source_syllables = [_]u8{0} ** codepoints.len;
    try markSourceFeatures(allocator, &source_features, &source_syllables, &codepoints);

    try std.testing.expect((source_features[0] & init_mask) == init_mask);
    for (source_features[1..5]) |feature| {
        try std.testing.expect((feature & medi_mask) == medi_mask);
    }
    try std.testing.expect((source_features[5] & medi_mask) == medi_mask);
    try std.testing.expect((source_features[6] & medi_mask) == medi_mask);
    try std.testing.expect((source_features[7] & fina_mask) == fina_mask);
    for (source_features) |feature| {
        try std.testing.expect((feature & locl_mask) == locl_mask);
        try std.testing.expect((feature & cjct_mask) == cjct_mask);
    }
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 2, 2, 2, 3, 3, 4 }, &source_syllables);
}
