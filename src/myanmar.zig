const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const categories = @import("myanmar/categories.zig");
const syllables = @import("myanmar/syllables.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .mym2;
}

pub fn markSourceSyllables(
    source_syllables: []u8,
    glyph_source_indices: []const usize,
    codepoints: []const u21,
) void {
    syllables.mark(source_syllables, glyph_source_indices, codepoints);
}

/// Insert one synthetic U+25CC glyph before every broken Myanmar syllable.
///
/// Syllables are source-level metadata, but this runs after `locl`/`ccmp`, as
/// in HarfBuzz. Searching the current glyph stream lets substitutions widen or
/// collapse a broken cluster without desynchronizing the insertion point.
pub fn insertDottedCirclesForBrokenSyllables(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_syllables: []const u8,
    dotted_circle_glyph: GlyphId,
) std.mem.Allocator.Error!void {
    if (dotted_circle_glyph == 0) return;

    var previous_syllable: u8 = 0;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= source_syllables.len) continue;
        const syllable = source_syllables[source];
        if (syllable == previous_syllable) continue;
        previous_syllable = syllable;
        if (syllables.kindOf(syllable) != .broken) continue;

        try shaping_metadata.insert(
            allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            dotted_circle_glyph,
            source,
            glyph_cluster_indices.items[glyph_index],
        );
        ligature_components.infos.items[glyph_index].flags.synthetic_base = true;
        glyph_index += 1;
    }
}

fn categoryForGlyph(
    sources: []const usize,
    infos: []const ligature_provenance.Info,
    codepoints: []const u21,
    glyph_index: usize,
) categories.Category {
    if (glyph_index >= sources.len or glyph_index >= infos.len) return .other;
    if (infos[glyph_index].flags.synthetic_base) return .dotted_circle;
    const source = sources[glyph_index];
    if (source >= codepoints.len) return .other;
    return categories.forCodepoint(codepoints[source]);
}

fn isConsonantGlyph(
    sources: []const usize,
    infos: []const ligature_provenance.Info,
    codepoints: []const u21,
    glyph_index: usize,
) bool {
    if (glyph_index >= infos.len) return false;
    // HarfBuzz excludes glyphs carrying ligated provenance from base
    // discovery. MultipleSubst deliberately preserves that provenance when it
    // decomposes a ligature, so `isLigature` remains the authoritative test.
    if (infos[glyph_index].isLigature() and
        !infos[glyph_index].flags.synthetic_base)
    {
        return false;
    }
    return categories.isConsonant(categoryForGlyph(sources, infos, codepoints, glyph_index));
}

pub fn reorder(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    glyph_positions: *std.ArrayList(u8),
    source_syllables: []const u8,
    codepoints: []const u21,
) std.mem.Allocator.Error!void {
    try glyph_positions.resize(allocator, glyph_ids.items.len);
    @memset(glyph_positions.items, @intFromEnum(MyanmarPosition.after_main));
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
        const kind = syllables.kindOf(syllable_id);
        if (kind != .consonant and kind != .broken) continue;
        assignSyllablePositions(
            glyph_source_indices.items,
            ligature_components.infos.items,
            glyph_positions.items,
            codepoints,
            start,
            glyph_index,
        );
        reorderSyllable(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_positions.items,
            codepoints,
            start,
            glyph_index,
        );
    }
}

pub const FeatureStage = enum {
    rphf,
    pref,
    blwf,
    pstf,
    final,
};

const rphf_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("rphf"), .match_source_syllable = true, .auto_zwj = false },
};

const pref_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
};

const blwf_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
};

const pstf_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
};

const final_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
};

pub fn featureApplications(stage: FeatureStage) []const gsub.feature.Application {
    return switch (stage) {
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
    glyph_positions: []u8,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    if (end <= start + 1) return;

    var index = start + 1;
    while (index < end) : (index += 1) {
        var current = index;
        while (current > start and
            glyph_positions[current - 1] > glyph_positions[current])
        {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, current - 1, current + 1);
            swapGlyphMetadata(
                glyph_ids.items,
                glyph_source_indices.items,
                glyph_cluster_indices.items,
                glyph_substituted.items,
                ligature_components.infos.items,
                glyph_positions,
                current - 1,
                current,
            );
            current -= 1;
        }
    }

    flipLeftMatraSequence(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        glyph_positions,
        codepoints,
        start,
        end,
    );
}

fn assignSyllablePositions(
    sources: []const usize,
    infos: []const ligature_provenance.Info,
    positions: []u8,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    std.debug.assert(sources.len == infos.len);
    std.debug.assert(sources.len == positions.len);

    var limit = start;
    var base = start;
    const has_reph = start + 3 <= end and
        categoryForGlyph(sources, infos, codepoints, start) == .ra and
        categoryForGlyph(sources, infos, codepoints, start + 1) == .asat and
        categoryForGlyph(sources, infos, codepoints, start + 2) == .halant;
    if (has_reph) {
        limit += 3;
    }

    for (limit..end) |glyph_index| {
        if (isConsonantGlyph(sources, infos, codepoints, glyph_index)) {
            base = glyph_index;
            break;
        }
    }

    var index = start;
    const reph_len: usize = if (has_reph) 3 else 0;
    while (index < start + reph_len) : (index += 1) {
        positions[index] = @intFromEnum(MyanmarPosition.after_main);
    }
    while (index < base) : (index += 1) {
        positions[index] = @intFromEnum(MyanmarPosition.pre_c);
    }
    if (index < end) {
        positions[index] = @intFromEnum(MyanmarPosition.base_c);
        index += 1;
    }

    var position = MyanmarPosition.after_main;
    while (index < end) : (index += 1) {
        const category = categoryForGlyph(sources, infos, codepoints, index);
        if (category == .medial_ra) {
            positions[index] = @intFromEnum(MyanmarPosition.pre_c);
            continue;
        }
        if (category == .vowel_pre) {
            positions[index] = @intFromEnum(MyanmarPosition.pre_m);
            continue;
        }
        if (category == .variation_selector) {
            positions[index] = if (index == start)
                @intFromEnum(MyanmarPosition.after_main)
            else
                positions[index - 1];
            continue;
        }
        if (position == .after_main and category == .vowel_below) {
            position = .below_c;
            positions[index] = @intFromEnum(position);
            continue;
        }
        if (position == .below_c and category == .tone_a) {
            positions[index] = @intFromEnum(MyanmarPosition.before_sub);
            continue;
        }
        if (position == .below_c and category == .vowel_below) {
            positions[index] = @intFromEnum(position);
            continue;
        }
        if (position == .below_c and category != .tone_a) {
            position = .after_sub;
            positions[index] = @intFromEnum(position);
            continue;
        }
        positions[index] = @intFromEnum(position);
    }
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

fn flipLeftMatraSequence(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    glyph_positions: []u8,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    var first = end;
    var last = end;
    for (start..end) |index| {
        if (glyph_positions[index] != @intFromEnum(MyanmarPosition.pre_m)) continue;
        if (first == end) first = index;
        last = index;
    }
    if (first >= last) return;

    reverseGlyphRange(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        glyph_positions,
        first,
        last + 1,
    );

    var group_start = first;
    for (first..last + 1) |index| {
        if (categoryForGlyph(
            glyph_source_indices.items,
            ligature_components.infos.items,
            codepoints,
            index,
        ) != .vowel_pre) continue;
        reverseGlyphRange(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_positions,
            group_start,
            index + 1,
        );
        group_start = index + 1;
    }
}

fn reverseGlyphRange(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    glyph_positions: []u8,
    start: usize,
    end: usize,
) void {
    if (end <= start + 1) return;
    var left = start;
    var right = end - 1;
    while (left < right) {
        swapGlyphMetadata(
            glyph_ids.items,
            glyph_source_indices.items,
            glyph_cluster_indices.items,
            glyph_substituted.items,
            ligature_components.infos.items,
            glyph_positions,
            left,
            right,
        );
        left += 1;
        right -= 1;
    }
}

fn swapGlyphMetadata(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []ligature_provenance.Info,
    glyph_positions: []u8,
    a: usize,
    b: usize,
) void {
    shaping_metadata.swap(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        a,
        b,
    );
    std.mem.swap(u8, &glyph_positions[a], &glyph_positions[b]);
}

test "Myanmar shaper selects only modern mym2 tag" {
    try std.testing.expect(shouldShape(.mym2));
    try std.testing.expect(!shouldShape(.mymr));
}

test "Myanmar inserts one dotted circle per broken syllable" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 4, 5 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 0, 2 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.resize(allocator, 3);
    @memset(ligatures.infos.items, .{});

    const source_syllables = [_]u8{ 0x11, 0x11, 0x21 };
    try insertDottedCirclesForBrokenSyllables(
        allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &source_syllables,
        9,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 3, 4, 9, 5 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1, 2, 2 }, sources.items);
    try std.testing.expect(ligatures.infos.items[0].flags.synthetic_base);
    try std.testing.expect(ligatures.infos.items[3].flags.synthetic_base);
}

test "Myanmar broken prebase vowel remains before synthetic dotted circle" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 3);

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 0);

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.append(allocator, 0);

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.append(allocator, false);

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.append(allocator, .{});

    const source_syllables = [_]u8{0x11};
    const codepoints = [_]u21{0x1031};
    try insertDottedCirclesForBrokenSyllables(
        allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &source_syllables,
        9,
    );

    var positions = std.ArrayList(u8).empty;
    defer positions.deinit(allocator);
    try reorder(
        allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &positions,
        &source_syllables,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 9 }, glyphs.items);
    try std.testing.expect(!ligatures.infos.items[0].flags.synthetic_base);
    try std.testing.expect(ligatures.infos.items[1].flags.synthetic_base);
}

test "Myanmar reorder handles medial and below-mark states" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 4, 5 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 0, 0, 0 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false, false, false });
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.appendSlice(allocator, &.{ .{}, .{}, .{}, .{} });
    var positions = std.ArrayList(u8).empty;
    defer positions.deinit(allocator);

    const codepoints = [_]u21{ 0x100f, 0x103c, 0x102f, 0x1036 };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10, 0x10 };
    try reorder(allocator, &glyphs, &sources, &clusters, &substituted, &ligatures, &positions, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1, 5, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 3, 2 }, sources.items);
}

test "Myanmar reorder keeps kinzi after the main base" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 6, 5, 3, 7, 4 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3, 4, 5 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.resize(allocator, 6);
    @memset(clusters.items, 0);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.resize(allocator, 6);
    @memset(substituted.items, false);
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.resize(allocator, 6);
    @memset(ligatures.infos.items, .{});
    var positions = std.ArrayList(u8).empty;
    defer positions.deinit(allocator);

    const codepoints = [_]u21{ 0x1004, 0x103a, 0x1039, 0x101b, 0x103d, 0x102d };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10 };
    try reorder(allocator, &glyphs, &sources, &clusters, &substituted, &ligatures, &positions, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 1, 6, 5, 7, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 0, 1, 2, 4, 5 }, sources.items);
}

test "Myanmar reorder flips left matras while retaining variation selectors" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 4, 2, 4, 2, 4 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3, 4, 5 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.resize(allocator, 6);
    @memset(clusters.items, 0);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.resize(allocator, 6);
    @memset(substituted.items, false);
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.resize(allocator, 6);
    @memset(ligatures.infos.items, .{});
    var positions = std.ArrayList(u8).empty;
    defer positions.deinit(allocator);

    const codepoints = [_]u21{ 0x101d, 0xfe00, 0x1031, 0xfe00, 0x1031, 0xfe00 };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10, 0x10, 0x10, 0x10 };
    try reorder(allocator, &glyphs, &sources, &clusters, &substituted, &ligatures, &positions, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(usize, &.{ 4, 5, 2, 3, 0, 1 }, sources.items);
}

test {
    std.testing.refAllDecls(@This());
}
