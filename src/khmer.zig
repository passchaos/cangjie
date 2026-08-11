const std = @import("std");

const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

const pref_mask = gsub.sourceFeatureMaskForTag(unicode.tag("pref")).?;
const blwf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("blwf")).?;
const abvf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("abvf")).?;
const pstf_mask = gsub.sourceFeatureMaskForTag(unicode.tag("pstf")).?;
const cfar_mask = gsub.sourceFeatureMaskForTag(unicode.tag("cfar")).?;
const post_base_mask = blwf_mask | abvf_mask | pstf_mask;

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .khmr;
}

pub const FeatureStage = enum {
    basic,
    final,
};

const basic_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("pref"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cfar"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
};

const final_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
    .{ .tag = unicode.tag("clig"), .auto_zwj = false },
    .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
    .{ .tag = unicode.tag("calt"), .auto_zwj = false },
};

pub fn featureApplications(stage: FeatureStage) []const gsub.FeatureApplication {
    return switch (stage) {
        .basic => &basic_applications,
        .final => &final_applications,
    };
}

pub fn decomposeSplitMatraSources(
    allocator: std.mem.Allocator,
    font: *const Font,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: *std.ArrayList(u21),
    clusters: *std.ArrayList(usize),
    source_ends: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
) !void {
    var source_index: usize = 0;
    while (source_index < codepoints.items.len) {
        const components = khmerSplitMatraDecomposition(codepoints.items[source_index]) orelse {
            source_index += 1;
            continue;
        };

        var component_glyphs: [2]GlyphId = undefined;
        var all_present = true;
        for (components, 0..) |component, component_index| {
            const glyph = try font.glyphIndex(component);
            if (glyph == 0) {
                all_present = false;
                break;
            }
            component_glyphs[component_index] = glyph;
        }
        if (!all_present) {
            source_index += 1;
            continue;
        }

        const extra = components.len - 1;
        try codepoints.ensureUnusedCapacity(allocator, extra);
        try clusters.ensureUnusedCapacity(allocator, extra);
        try source_ends.ensureUnusedCapacity(allocator, extra);
        try glyph_ids.ensureUnusedCapacity(allocator, extra);
        try glyph_source_indices.ensureUnusedCapacity(allocator, extra);
        try glyph_cluster_indices.ensureUnusedCapacity(allocator, extra);
        try glyph_substituted.ensureUnusedCapacity(allocator, extra);
        try ligature_components.infos.ensureUnusedCapacity(allocator, extra);

        const source_start = clusters.items[source_index];
        const source_end = source_ends.items[source_index];
        for (glyph_source_indices.items) |*source| {
            if (source.* > source_index) source.* += extra;
        }
        for (glyph_cluster_indices.items) |*owner| {
            if (owner.* > source_index) owner.* += extra;
        }
        ligature_components.shiftSourceIndices(source_index + 1, extra);

        try codepoints.replaceRange(allocator, source_index, 1, components);
        const source_starts = [_]usize{ source_start, source_start };
        const source_end_values = [_]usize{ source_end, source_end };
        try clusters.replaceRange(allocator, source_index, 1, source_starts[0..components.len]);
        try source_ends.replaceRange(allocator, source_index, 1, source_end_values[0..components.len]);

        var glyph_index: usize = 0;
        while (glyph_index < glyph_source_indices.items.len and glyph_source_indices.items[glyph_index] < source_index) : (glyph_index += 1) {}
        if (glyph_index >= glyph_source_indices.items.len or glyph_source_indices.items[glyph_index] != source_index) {
            source_index += components.len;
            continue;
        }

        const sources = [_]usize{ source_index, source_index + 1 };
        const owners = [_]usize{ source_index, source_index + 1 };
        const substituted = [_]bool{ false, false };
        const infos = [_]ligature_provenance.Info{ .{}, .{} };
        try glyph_ids.replaceRange(allocator, glyph_index, 1, component_glyphs[0..components.len]);
        try glyph_source_indices.replaceRange(allocator, glyph_index, 1, sources[0..components.len]);
        try glyph_cluster_indices.replaceRange(allocator, glyph_index, 1, owners[0..components.len]);
        try glyph_substituted.replaceRange(allocator, glyph_index, 1, substituted[0..components.len]);
        try ligature_components.infos.replaceRange(allocator, glyph_index, 1, infos[0..components.len]);
        source_index += components.len;
    }
}

pub fn markSourceFeatures(source_features: []u32, source_syllables: []u8, codepoints: []const u21) void {
    @memset(source_features, 0);
    @memset(source_syllables, 0);

    var source: usize = 0;
    var serial: u8 = 1;
    while (source < codepoints.len) {
        if (!isKhmerSyllableStart(codepoints[source])) {
            source += 1;
            continue;
        }

        const syllable_start = source;
        const syllable_end = khmerSyllableEnd(codepoints, syllable_start);
        const syllable_id = serial << 4;
        @memset(source_syllables[syllable_start..syllable_end], syllable_id);
        markSyllableFeatureMasks(source_features, codepoints, syllable_start, syllable_end);
        serial = if (serial == 15) 1 else serial + 1;
        source = syllable_end;
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
        reorderSyllable(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, glyph_index);
    }
}

pub fn insertDottedCirclesForBrokenMarks(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_syllables: []const u8,
    codepoints: []const u21,
    dotted_circle_glyph: GlyphId,
) !void {
    if (dotted_circle_glyph == 0) return;

    var previous_syllable: u8 = 0;
    var state = KhmerMatraState{};
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= source_syllables.len or source >= codepoints.len or source_syllables[source] == 0) {
            previous_syllable = 0;
            state = .{};
            glyph_index += 1;
            continue;
        }

        const syllable = source_syllables[source];
        if (syllable != previous_syllable) {
            previous_syllable = syllable;
            state = .{};
        }

        const category = khmerMarkOrderCategory(codepoints[source]);
        if (state.breaksBefore(category)) {
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
            state = .{};
        }

        state.accept(category);
        glyph_index += 1;
    }
}

fn markSyllableFeatureMasks(source_features: []u32, codepoints: []const u21, start: usize, end: usize) void {
    if (end <= start + 1) return;

    for (start + 1..end) |source| {
        source_features[source] |= post_base_mask;
    }

    var num_coengs: usize = 0;
    var source = start + 1;
    while (source + 1 < end) : (source += 1) {
        if (khmerCategory(codepoints[source]) != .coeng) continue;
        if (num_coengs > 2) continue;
        num_coengs += 1;
        if (khmerCategory(codepoints[source + 1]) != .ra) continue;

        source_features[source] |= pref_mask;
        source_features[source + 1] |= pref_mask;
        for (source + 2..end) |after_ro| {
            source_features[after_ro] |= cfar_mask;
        }
        break;
    }
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

    var num_coengs: usize = 0;
    var index = start + 1;
    while (index < end) : (index += 1) {
        const source = glyph_source_indices.items[index];
        if (source >= codepoints.len) continue;
        const category = khmerCategory(codepoints[source]);
        if (category == .coeng and num_coengs <= 2 and source + 1 < codepoints.len) {
            num_coengs += 1;
            if (khmerCategory(codepoints[source + 1]) != .ra) continue;

            const range_end = khmerSourceGlyphRangeEnd(glyph_source_indices.items, ligature_components.infos.items, index, source + 1, end);
            moveRangeToStart(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, start, index, range_end);
            num_coengs = 2;
        } else if (category == .vowel_pre) {
            if (!vowelPreMayMoveToSyllableStart(glyph_source_indices.items, start, index, codepoints)) continue;
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, start, index + 1);
            shaping_metadata.move(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, index, start);
        }
    }
}

fn vowelPreMayMoveToSyllableStart(glyph_sources: []const usize, start: usize, index: usize, codepoints: []const u21) bool {
    for (start..index) |glyph_index| {
        const source = glyph_sources[glyph_index];
        if (source >= codepoints.len) continue;
        if (khmerCategory(codepoints[source]).isVowelMark()) return false;
    }
    return true;
}

fn moveRangeToStart(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    start: usize,
    range_start: usize,
    range_end: usize,
) void {
    if (range_start <= start or range_end <= range_start) return;
    shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, start, range_end);
    var moved: usize = 0;
    while (moved < range_end - range_start) : (moved += 1) {
        shaping_metadata.move(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, range_start + moved, start + moved);
    }
}

fn khmerSourceGlyphRangeEnd(glyph_sources: []const usize, ligatures: []const ligature_provenance.Info, first_glyph: usize, last_source: usize, syllable_end: usize) usize {
    var end = first_glyph + 1;
    while (end < syllable_end) : (end += 1) {
        const source = glyph_sources[end];
        if (source > last_source) break;
        if (source == last_source) {
            end += 1;
            break;
        }
    }
    if (first_glyph < ligatures.len and ligatures[first_glyph].component_count > 1) return first_glyph + 1;
    return end;
}

fn khmerSyllableEnd(codepoints: []const u21, start: usize) usize {
    var index = start + 1;
    while (index < codepoints.len) : (index += 1) {
        const category = khmerCategory(codepoints[index]);
        if (category == .other) break;
        if ((category == .consonant or category == .ra or category == .independent_vowel) and
            (index == start or khmerCategory(codepoints[index - 1]) != .coeng))
        {
            break;
        }
    }
    return index;
}

fn isKhmerSyllableStart(codepoint: u21) bool {
    return switch (khmerCategory(codepoint)) {
        .consonant, .ra, .independent_vowel, .placeholder, .dotted_circle => true,
        else => false,
    };
}

const KhmerCategory = enum {
    consonant,
    independent_vowel,
    coeng,
    zwnj,
    zwj,
    placeholder,
    dotted_circle,
    ra,
    robatic,
    vowel_above,
    vowel_below,
    vowel_pre,
    vowel_post,
    xgroup,
    ygroup,
    other,

    fn isVowelMark(self: KhmerCategory) bool {
        return switch (self) {
            .vowel_above, .vowel_below, .vowel_pre, .vowel_post => true,
            else => false,
        };
    }
};

const KhmerMatraState = struct {
    seen_below: bool = false,
    seen_above: bool = false,
    seen_post: bool = false,
    seen_vowel: bool = false,

    fn breaksBefore(self: KhmerMatraState, category: KhmerMarkOrderCategory) bool {
        if (category.split_component and self.seen_vowel) return true;
        return switch (category.kind) {
            .vowel_below => self.seen_below or self.seen_above or self.seen_post,
            .vowel_above => self.seen_above or self.seen_post,
            .vowel_post => self.seen_post,
            else => false,
        };
    }

    fn accept(self: *KhmerMatraState, category: KhmerMarkOrderCategory) void {
        switch (category.kind) {
            .vowel_pre => {},
            .vowel_below => {
                self.seen_below = true;
                self.seen_vowel = true;
            },
            .vowel_above => {
                self.seen_above = true;
                self.seen_vowel = true;
            },
            .vowel_post => {
                self.seen_post = true;
                self.seen_vowel = true;
            },
            else => {},
        }
    }
};

const KhmerMarkOrderCategory = struct {
    kind: KhmerCategory,
    split_component: bool = false,
};

fn khmerMarkOrderCategory(codepoint: u21) KhmerMarkOrderCategory {
    return switch (codepoint) {
        0x17be => .{ .kind = .vowel_above, .split_component = true },
        0x17bf, 0x17c0, 0x17c4, 0x17c5 => .{ .kind = .vowel_post, .split_component = true },
        else => .{ .kind = khmerCategory(codepoint) },
    };
}

fn khmerCategory(codepoint: u21) KhmerCategory {
    return switch (codepoint) {
        0x1780...0x1799, 0x179b...0x17a2 => .consonant,
        0x179a => .ra,
        0x17a3...0x17b3 => .independent_vowel,
        0x17d2 => .coeng,
        0x200c => .zwnj,
        0x200d => .zwj,
        0x25cc => .dotted_circle,
        0x00a0, 0x25fb, 0x25fc, 0x25fd, 0x25fe => .placeholder,
        0x17cc => .robatic,
        0x17b7...0x17ba, 0x17dd => .vowel_above,
        0x17bb...0x17bd => .vowel_below,
        0x17c1...0x17c3 => .vowel_pre,
        0x17b6, 0x17be...0x17c0, 0x17c4, 0x17c5 => .vowel_post,
        0x17c6, 0x17c9, 0x17ca, 0x17cb, 0x17cd...0x17d1, 0x17d3 => .xgroup,
        0x17c7, 0x17c8 => .ygroup,
        else => .other,
    };
}

fn khmerSplitMatraDecomposition(codepoint: u21) ?[]const u21 {
    return switch (codepoint) {
        0x17be => &.{ 0x17c1, 0x17be },
        0x17bf => &.{ 0x17c1, 0x17bf },
        0x17c0 => &.{ 0x17c1, 0x17c0 },
        0x17c4 => &.{ 0x17c1, 0x17c4 },
        0x17c5 => &.{ 0x17c1, 0x17c5 },
        else => null,
    };
}

test "Khmer shaper selects khmr" {
    try std.testing.expect(shouldShape(.khmr));
    try std.testing.expect(!shouldShape(.mym2));
}

test "Khmer source features mark coeng and prebase syllables" {
    const codepoints = [_]u21{ 0x1781, 0x17d2, 0x1798, 0x17c1 };
    var source_features = [_]u32{0} ** codepoints.len;
    var source_syllables = [_]u8{0} ** codepoints.len;

    markSourceFeatures(&source_features, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x10, 0x10, 0x10 }, &source_syllables);
    try std.testing.expectEqual(@as(u32, 0), source_features[0]);
    try std.testing.expect((source_features[1] & blwf_mask) != 0);
    try std.testing.expect((source_features[2] & blwf_mask) != 0);
    try std.testing.expect((source_features[3] & blwf_mask) != 0);
}

test "Khmer reorder moves prebase vowel to syllable start" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 98, 54 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.appendSlice(allocator, &.{ .{}, .{ .component_count = 2 }, .{} });

    const codepoints = [_]u21{ 0x1781, 0x17d2, 0x1798, 0x17c1 };
    const source_syllables = [_]u8{ 0x10, 0x10, 0x10, 0x10 };

    reorder(&glyphs, &sources, &clusters, &substituted, &ligatures, &source_syllables, &codepoints);

    try std.testing.expectEqualSlices(GlyphId, &.{ 54, 3, 98 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 0, 1 }, sources.items);
}
