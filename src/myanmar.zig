const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .mym2;
}

pub fn markSourceSyllables(source_syllables: []u8, codepoints: []const u21) void {
    @memset(source_syllables, 0);
    var index: usize = 0;
    var serial: u8 = 1;
    while (index < codepoints.len) {
        if (!isMyanmarSyllableCodepoint(codepoints[index])) {
            index += 1;
            continue;
        }
        const start = index;
        while (index < codepoints.len and isMyanmarSyllableCodepoint(codepoints[index])) : (index += 1) {}
        const syllable_id = serial << 4;
        @memset(source_syllables[start..index], syllable_id);
        serial = if (serial == 15) 1 else serial + 1;
    }
}

pub fn reorder(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_syllables: []const u8,
    codepoints: []const u21,
) void {
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= source_syllables.len or source_syllables[source] == 0) {
            glyph_index += 1;
            continue;
        }

        const syllable_id = source_syllables[source];
        const start = glyph_index;
        while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
            const next_source = glyph_source_indices.items[glyph_index];
            if (next_source >= source_syllables.len or source_syllables[next_source] != syllable_id) break;
        }
        reorderSyllable(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            codepoints,
            start,
            glyph_index,
        );
    }
}

pub const FeatureStage = enum {
    preprocessing,
    rphf,
    pref,
    blwf,
    pstf,
    final,
};

const preprocessing_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
};

const rphf_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rphf"), .match_source_syllable = true, .auto_zwj = false },
};

const pref_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
};

const blwf_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
};

const pstf_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
};

const final_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("liga") },
};

pub fn featureApplications(stage: FeatureStage) []const gsub.FeatureApplication {
    return switch (stage) {
        .preprocessing => &preprocessing_applications,
        .rphf => &rphf_applications,
        .pref => &pref_applications,
        .blwf => &blwf_applications,
        .pstf => &pstf_applications,
        .final => &final_applications,
    };
}

fn reorderSyllable(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    if (end <= start + 1) return;
    const base = baseSourceInGlyphRange(glyph_source_indices.items[start..end], codepoints) orelse return;

    var index = start + 1;
    while (index < end) : (index += 1) {
        var current = index;
        while (current > start and
            @intFromEnum(positionForGlyph(glyph_source_indices.items[current - 1], base, codepoints)) >
                @intFromEnum(positionForGlyph(glyph_source_indices.items[current], base, codepoints)))
        {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, current - 1, current + 1);
            shaping_metadata.swap(
                glyph_ids.items,
                glyph_source_indices.items,
                glyph_cluster_indices.items,
                glyph_substituted.items,
                ligature_components.infos.items,
                current - 1,
                current,
            );
            current -= 1;
        }
    }

    flipLeftMatraSequence(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, end);
}

fn baseSourceInGlyphRange(sources: []const usize, codepoints: []const u21) ?usize {
    for (sources) |source| {
        if (source < codepoints.len and isMyanmarConsonant(codepoints[source])) return source;
    }
    return null;
}

const MyanmarPosition = enum(u8) {
    pre_m = 2,
    pre_c = 3,
    base_c = 4,
    after_main = 5,
    before_sub = 7,
    below_c = 8,
    after_sub = 9,
};

fn myanmarPosition(codepoint: u21, is_base: bool) MyanmarPosition {
    if (is_base) return .base_c;
    return switch (myanmarCategory(codepoint)) {
        .medial_ra => .pre_c,
        .vowel_pre => .pre_m,
        .vowel_below => .below_c,
        .asat => .before_sub,
        else => .after_main,
    };
}

fn positionForGlyph(source: usize, base: usize, codepoints: []const u21) MyanmarPosition {
    if (source >= codepoints.len) return .after_main;
    return myanmarPosition(codepoints[source], source == base);
}

const MyanmarCategory = enum {
    consonant,
    medial_ra,
    vowel_below,
    vowel_pre,
    asat,
    other,
};

fn myanmarCategory(codepoint: u21) MyanmarCategory {
    return switch (codepoint) {
        0x1000...0x102a, 0x103f, 0x1050...0x1055, 0x105a...0x105d, 0x1061, 0x1065, 0x1066, 0x106e...0x1070, 0x1075...0x1081, 0x108e, 0xa9e0...0xa9e4, 0xa9e7...0xa9ef, 0xaa60...0xaa6f, 0xaa71...0xaa76, 0xaa7a, 0xaa7e...0xaa7f => .consonant,
        0x103c => .medial_ra,
        0x102f, 0x1030, 0x1058, 0x1059 => .vowel_below,
        0x1031, 0x1084 => .vowel_pre,
        0x103a, 0x1039 => .asat,
        else => .other,
    };
}

fn flipLeftMatraSequence(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    var first = end;
    var last = end;
    for (start..end) |index| {
        const source = glyph_source_indices.items[index];
        if (source >= codepoints.len or myanmarPosition(codepoints[source], false) != .pre_m) continue;
        if (first == end) first = index;
        last = index;
    }
    if (first >= last) return;

    var left = first;
    var right = last;
    while (left < right) {
        shaping_metadata.swap(
            glyph_ids.items,
            glyph_source_indices.items,
            glyph_cluster_indices.items,
            glyph_substituted.items,
            ligature_components.infos.items,
            left,
            right,
        );
        left += 1;
        right -= 1;
    }
}

fn isMyanmarConsonant(codepoint: u21) bool {
    return myanmarCategory(codepoint) == .consonant;
}

fn isMyanmarSyllableCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1000 and codepoint <= 0x109f) or
        (codepoint >= 0xa9e0 and codepoint <= 0xa9ff) or
        (codepoint >= 0xaa60 and codepoint <= 0xaa7f) or
        (codepoint >= 0x116d0 and codepoint <= 0x116ff);
}

test "Myanmar shaper selects only modern mym2 tag" {
    try std.testing.expect(shouldShape(.mym2));
    try std.testing.expect(!shouldShape(.mymr));
}

test "Myanmar reorder moves medial ra before base" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 4, 5 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x100f, 0x103c, 0x102f, 0x1036 };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10, 0x10 };

    reorder(&glyphs, &sources, &clusters, &substituted, &ligatures, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1, 5, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 3, 2 }, sources.items);
}

test "Myanmar reorder flips consecutive left matras" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 3, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x1000, 0x1031, 0x1084 };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10 };

    reorder(&glyphs, &sources, &clusters, &substituted, &ligatures, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 3, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, sources.items);
}
