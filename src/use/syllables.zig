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
    source_order: []const usize,
) !void {
    if (source_features.len != codepoints.len) return error.InvalidUseInput;
    if (source_syllables.len != codepoints.len) return error.InvalidUseInput;
    if (source_order.len != codepoints.len) return error.InvalidUseInput;
    @memset(source_features, 0);
    @memset(source_syllables, 0);

    const syllables = try findInSourceOrder(allocator, codepoints, source_order);
    defer allocator.free(syllables);

    for (syllables, 0..) |syllable, syllable_index| {
        const serial: u8 = @intCast((syllable_index % 15) + 1);
        markSyllableSources(source_syllables, source_order[syllable.start..syllable.end], serial, syllable.kind);
        markSourceList(source_features, source_order[syllable.start..syllable.end], per_syllable_mask);
        markRphfSourcesInOrder(source_features, codepoints, source_order, syllable);
    }
    markTopographicalSourcesInOrder(source_features, source_order, syllables);
}

fn findInSourceOrder(allocator: std.mem.Allocator, codepoints: []const u21, source_order: []const usize) ![]Syllable {
    const ordered_codepoints = try allocator.alloc(u21, source_order.len);
    defer allocator.free(ordered_codepoints);
    for (source_order, 0..) |source, index| {
        if (source >= codepoints.len) return error.InvalidUseInput;
        ordered_codepoints[index] = codepoints[source];
    }
    return try find(allocator, ordered_codepoints);
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
    var tail_end = consumeTail(items, index);
    if (matchNumberJoinerTerminatedClusterTail(items, index)) |next| tail_end = @max(tail_end, next);
    if (matchNumeralClusterTail(items, index)) |next| tail_end = @max(tail_end, next);
    // `complex_syllable_tail` is entirely optional in the generated grammar.
    // Ragel's scanner never emits a zero-length token, so mirror that behavior
    // explicitly: an unrelated category such as WORD JOINER must fall through
    // to one non-cluster item instead of stalling `find()` forever.
    return if (tail_end > start) tail_end else null;
}

fn consumeTail(items: []const IncludedCodepoint, start: usize) usize {
    // Ragel resolves these alternatives using the longest accepted token.
    // Selecting the first match is insufficient because complex_syllable_tail
    // is nullable and can be a prefix of the terminated-tail alternatives.
    var end = consumeComplexSyllableTail(items, start);
    if (matchSakotTerminatedClusterTail(items, start)) |next| end = @max(end, next);
    if (matchSymbolClusterTail(items, start)) |next| end = @max(end, next);
    if (matchViramaTerminatedClusterTail(items, start)) |next| end = @max(end, next);
    return end;
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
        // The USE grammar is `(O | GB | SB) tail?`, where `tail` includes the
        // full complex-syllable tail as well as symbol modifiers. Restricting
        // this to symbol modifiers splits punctuation followed by a dependent
        // vowel and incorrectly turns the vowel into a broken cluster.
        .other, .base_other, .hieroglyph_segment_begin => consumeTail(items, start + 1),
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

fn markSourceList(source_features: []u32, sources: []const usize, mask: u32) void {
    for (sources) |source| source_features[source] |= mask;
}

fn markSyllableSources(source_syllables: []u8, sources: []const usize, serial: u8, kind: SyllableType) void {
    // Match HarfBuzz's packed syllable byte: the high nibble is a wrapping
    // serial and the low nibble is the machine's syllable type. Sources may no
    // longer be numerically contiguous after canonical mark reordering.
    const syllable_id = (serial << 4) | @intFromEnum(kind);
    for (sources) |source| source_syllables[source] = syllable_id;
}

fn markRphfSourcesInOrder(source_features: []u32, codepoints: []const u21, source_order: []const usize, syllable: Syllable) void {
    if (syllable.start >= syllable.end) return;
    const first_source = source_order[syllable.start];
    const limit = if (categories.forCodepoint(codepoints[first_source]) == .repha)
        syllable.start + 1
    else
        @min(syllable.start + 3, syllable.end);
    markSourceList(source_features, source_order[syllable.start..limit], rphf_mask);
}

const JoiningForm = enum {
    isolated,
    initial,
    medial,
    terminal,
};

fn markTopographicalSourcesInOrder(source_features: []u32, source_order: []const usize, syllables: []const Syllable) void {
    var last_start: usize = 0;
    var last_end: usize = 0;
    var last_form: ?JoiningForm = null;

    for (syllables) |syllable| {
        if (syllable.kind == .hieroglyph or syllable.kind == .non_cluster) {
            last_form = null;
        } else {
            const form: JoiningForm = if (last_form == .terminal or last_form == .isolated) .terminal else .isolated;
            if (form == .terminal) {
                const fixed_previous: JoiningForm = if (last_form == .terminal) .medial else .initial;
                markTopographicalSourcesRange(source_features, source_order, last_start, last_end, fixed_previous);
            }
            markTopographicalSourcesRange(source_features, source_order, syllable.start, syllable.end, form);
            last_form = form;
        }
        last_start = syllable.start;
        last_end = syllable.end;
    }
}

fn markTopographicalSourcesRange(source_features: []u32, source_order: []const usize, start: usize, end: usize, form: JoiningForm) void {
    const form_mask = switch (form) {
        .isolated => isol_mask,
        .initial => init_mask,
        .medial => medi_mask,
        .terminal => fina_mask,
    };
    for (source_order[start..end]) |source| {
        source_features[source] = (source_features[source] & ~topo_mask) | form_mask;
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

test "USE syllables group a Balinese stacked consonant and modifier" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1b15, 0x1b44, 0x1b16, 0x1b02 };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqualSlices(
        Syllable,
        &.{.{ .start = 0, .end = codepoints.len, .kind = .standard }},
        syllables,
    );
}

test "USE syllables group a Javanese prebase vowel with its base" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0xa9a5, 0xa9ba };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqualSlices(
        Syllable,
        &.{.{ .start = 0, .end = codepoints.len, .kind = .standard }},
        syllables,
    );
}

test "USE syllables attach a dependent vowel to a symbol cluster" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1aad, 0x1a63 };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqualSlices(
        Syllable,
        &.{.{ .start = 0, .end = codepoints.len, .kind = .symbol }},
        syllables,
    );
}

test "USE source features follow canonical mark order" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1a43, 0x1a60, 0x1a7a, 0x1a3c };
    const source_order = [_]usize{ 0, 2, 1, 3 };
    var source_features = [_]u32{0} ** codepoints.len;
    var source_syllables = [_]u8{0} ** codepoints.len;

    try markSourceFeatures(
        allocator,
        &source_features,
        &source_syllables,
        &codepoints,
        &source_order,
    );

    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x12, 0x12, 0x12 }, &source_syllables);
}

test "USE syllables identify Brahmi numeral groups" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x11064, 0x1107f, 0x11052, 0x11065, 0x1107f, 0x11053 };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqualSlices(
        Syllable,
        &.{
            .{ .start = 0, .end = 3, .kind = .numeral },
            .{ .start = 3, .end = 6, .kind = .numeral },
        },
        syllables,
    );
}

test "USE WORD JOINER starts a broken Chakma vowel cluster" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x11124, 0x2060, 0x11127 };
    const syllables = try find(allocator, &codepoints);
    defer allocator.free(syllables);

    try std.testing.expectEqualSlices(
        Syllable,
        &.{
            .{ .start = 0, .end = 1, .kind = .standard },
            .{ .start = 1, .end = 2, .kind = .non_cluster },
            .{ .start = 2, .end = 3, .kind = .broken },
        },
        syllables,
    );
}

test "USE source features assign topographical forms per syllable" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u21{ 0x1bc02, 0x1bc5b, 0x034f, 0x034f, 0x034f, 0x1bc1c, 0x200c, 0x1bc02 };
    var source_features = [_]u32{0} ** codepoints.len;
    var source_syllables = [_]u8{0} ** codepoints.len;
    const source_order = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7 };
    try markSourceFeatures(allocator, &source_features, &source_syllables, &codepoints, &source_order);

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
    try std.testing.expectEqualSlices(
        u8,
        &.{
            0x12,
            0x22,
            0x22,
            0x22,
            0x22,
            0x32,
            0x32,
            0x42,
        },
        &source_syllables,
    );
}
