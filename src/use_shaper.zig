const std = @import("std");

const gsub = @import("gsub.zig");
const gpos = @import("gpos.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");
const categories = @import("use/categories.zig");
const syllables = @import("use/syllables.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .bali or script_tag == .dupl;
}

pub const Category = categories.Category;
pub const Syllable = syllables.Syllable;
pub const SyllableType = syllables.SyllableType;

pub fn categoryForCodepoint(codepoint: u21) Category {
    return categories.forCodepoint(codepoint);
}

pub fn findSyllables(allocator: std.mem.Allocator, codepoints: []const u21) ![]Syllable {
    return syllables.find(allocator, codepoints);
}

pub fn markSourceFeatures(
    allocator: std.mem.Allocator,
    source_features: []u32,
    source_syllables: []u8,
    codepoints: []const u21,
) !void {
    try syllables.markSourceFeatures(allocator, source_features, source_syllables, codepoints);
}

pub fn mergeSyllableClusters(
    glyph_source_indices: []const usize,
    glyph_cluster_indices: []usize,
    source_syllables: []const u8,
) void {
    std.debug.assert(glyph_source_indices.len == glyph_cluster_indices.len);
    const glyph_count = glyph_source_indices.len;
    var start: usize = 0;
    while (start < glyph_count) {
        const source = glyph_source_indices[start];
        if (source >= source_syllables.len or source_syllables[source] == 0) {
            start += 1;
            continue;
        }

        const syllable_id = source_syllables[source];
        var end = start + 1;
        while (end < glyph_count) : (end += 1) {
            const next_source = glyph_source_indices[end];
            if (next_source >= source_syllables.len or source_syllables[next_source] != syllable_id) break;
        }

        // USE serials identify orthographic units, while glyph source indices
        // must remain per-character for feature and attachment processing.
        // Merge only the independent cluster-owner metadata so substitutions
        // retain precise source identity but the final glyph run cannot expose
        // a caret or line-break opportunity inside one USE syllable.
        var owner = glyph_cluster_indices[start];
        for (glyph_cluster_indices[start + 1 .. end]) |candidate| {
            owner = @min(owner, candidate);
        }
        @memset(glyph_cluster_indices[start..end], owner);
        start = end;
    }
}

pub fn hasBrokenSyllable(source_syllables: []const u8) bool {
    for (source_syllables) |syllable_id| {
        if (syllableKindIs(syllable_id, .broken)) return true;
    }
    return false;
}

pub fn insertDottedCirclesForBrokenSyllables(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
    source_syllables: []const u8,
    codepoints: []const u21,
    dotted_circle_glyph: GlyphId,
) std.mem.Allocator.Error!void {
    if (dotted_circle_glyph == 0) return;

    var previous_syllable: u8 = 0;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= source_syllables.len) continue;
        const syllable_id = source_syllables[source];
        if (syllable_id == previous_syllable) continue;
        previous_syllable = syllable_id;
        if (!syllableKindIs(syllable_id, .broken)) continue;

        var insert_index = glyph_index;
        while (insert_index < glyph_source_indices.items.len) : (insert_index += 1) {
            const candidate_source = glyph_source_indices.items[insert_index];
            if (candidate_source >= source_syllables.len or source_syllables[candidate_source] != syllable_id) break;
            if (candidate_source >= codepoints.len or categories.forCodepoint(codepoints[candidate_source]) != .repha) break;
        }

        // HarfBuzz inserts before the broken syllable and then reorders a
        // leading VPre ahead of the dotted circle. Insert after that one glyph
        // directly: our source metadata intentionally remains source-level, so
        // all components of a MultipleSubst share the VPre source category.
        if (insert_index < glyph_source_indices.items.len) {
            const candidate_source = glyph_source_indices.items[insert_index];
            if (candidate_source < codepoints.len and categories.isPrebaseVowel(categories.forCodepoint(codepoints[candidate_source]))) {
                insert_index += 1;
            }
        }

        try shaping_metadata.insert(
            allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            insert_index,
            dotted_circle_glyph,
            source,
            glyph_cluster_indices.items[glyph_index],
        );
        if (insert_index <= glyph_index) glyph_index += 1;
    }
}

pub fn reorderPrebaseGlyphs(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []gpos.LigatureComponentInfo,
    source_syllables: []const u8,
    codepoints: []const u21,
) void {
    const glyph_count = glyph_ids.len;
    std.debug.assert(glyph_source_indices.len == glyph_count);
    std.debug.assert(glyph_cluster_indices.len == glyph_count);
    std.debug.assert(glyph_substituted.len == glyph_count);
    std.debug.assert(ligature_components.len == glyph_count);
    var syllable_start: usize = 0;
    while (syllable_start < glyph_count) {
        const source = glyph_source_indices[syllable_start];
        if (source >= source_syllables.len or source_syllables[source] == 0) {
            syllable_start += 1;
            continue;
        }

        const syllable_id = source_syllables[source];
        var syllable_end = syllable_start + 1;
        while (syllable_end < glyph_count) : (syllable_end += 1) {
            const next_source = glyph_source_indices[syllable_end];
            if (next_source >= source_syllables.len or source_syllables[next_source] != syllable_id) break;
        }
        reorderPrebaseGlyphsInSyllable(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            codepoints,
            syllable_start,
            syllable_end,
        );
        syllable_start = syllable_end;
    }
}

fn reorderPrebaseGlyphsInSyllable(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []gpos.LigatureComponentInfo,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    var insertion = start;
    var index = start;
    while (index < end) {
        const source = glyph_source_indices[index];
        const category = if (source < codepoints.len) categories.forCodepoint(codepoints[source]) else .other;
        if (categories.isHalantLike(category) and ligature_components[index].component_count <= 1) {
            insertion = index + 1;
            index += 1;
            continue;
        }
        if (!categories.isPrebaseVowel(category)) {
            index += 1;
            continue;
        }

        // A MultipleSubst expansion gives every output glyph the same source.
        // USE moves only its first component; skipping the entire source group
        // here prevents the trailing split-matra component from being moved on
        // the next loop iteration after the first component changes position.
        var source_group_end = index + 1;
        while (source_group_end < end and glyph_source_indices[source_group_end] == source) : (source_group_end += 1) {}
        if (insertion < index) {
            mergeClusterRange(glyph_cluster_indices, insertion, index + 1);
            var destination = index;
            while (destination > insertion) : (destination -= 1) {
                shaping_metadata.swap(
                    glyph_ids,
                    glyph_source_indices,
                    glyph_cluster_indices,
                    glyph_substituted,
                    ligature_components,
                    destination - 1,
                    destination,
                );
            }
        }
        index = source_group_end;
    }
}

fn mergeClusterRange(clusters: []usize, start: usize, end: usize) void {
    if (start >= end or end > clusters.len) return;
    var owner = clusters[start];
    for (clusters[start + 1 .. end]) |candidate| {
        owner = @min(owner, candidate);
    }
    @memset(clusters[start..end], owner);
}

fn syllableKindIs(syllable_id: u8, kind: SyllableType) bool {
    return (syllable_id & 0x0f) == @intFromEnum(kind);
}

const feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("rphf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("isol"), .source_scoped = true },
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("medi"), .source_scoped = true },
    .{ .tag = unicode.tag("fina"), .source_scoped = true },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvm") },
    .{ .tag = unicode.tag("blwm") },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("dist") },
    .{ .tag = unicode.tag("liga") },
    .{ .tag = unicode.tag("rclt") },
};

const default_preprocessing_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true, .auto_zwj = false },
};

const rphf_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rphf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
};

const pref_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
};

const basic_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true, .auto_zwj = false },
};

const topographical_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("isol"), .source_scoped = true },
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("medi"), .source_scoped = true },
    .{ .tag = unicode.tag("fina"), .source_scoped = true },
};

const final_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
};

const typographic_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvm") },
    .{ .tag = unicode.tag("blwm") },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("dist") },
    .{ .tag = unicode.tag("liga") },
    .{ .tag = unicode.tag("rclt") },
};

pub fn featureApplications() []const gsub.FeatureApplication {
    return &feature_applications;
}

pub fn defaultPreprocessingFeatureApplications() []const gsub.FeatureApplication {
    return &default_preprocessing_applications;
}

pub fn rphfFeatureApplications() []const gsub.FeatureApplication {
    return &rphf_applications;
}

pub fn prefFeatureApplications() []const gsub.FeatureApplication {
    return &pref_applications;
}

pub fn basicFeatureApplications() []const gsub.FeatureApplication {
    return &basic_applications;
}

pub fn topographicalFeatureApplications() []const gsub.FeatureApplication {
    return &topographical_applications;
}

pub fn finalFeatureApplications() []const gsub.FeatureApplication {
    return &final_applications;
}

pub fn typographicFeatureApplications() []const gsub.FeatureApplication {
    return &typographic_applications;
}

test "USE category covers Duployan sample codepoints" {
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc02));
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc5b));
    try @import("std").testing.expectEqual(Category.cg_joiner, categoryForCodepoint(0x034f));
    try @import("std").testing.expectEqual(Category.zwnj, categoryForCodepoint(0x200c));
    try @import("std").testing.expectEqual(Category.other, categoryForCodepoint(0x002e));
}

test "USE shaping includes Balinese" {
    try @import("std").testing.expect(shouldShape(.bali));
    try @import("std").testing.expect(shouldShape(.dupl));
    try @import("std").testing.expect(!shouldShape(.latn));
}

test "USE syllable cluster merging preserves source ownership" {
    const sources = [_]usize{ 0, 1, 2, 3, 4, 5 };
    const syllable_serials = [_]u8{ 0x12, 0x12, 0x12, 0x12, 0x22, 0x22 };
    var cluster_owners = [_]usize{ 0, 1, 2, 3, 4, 5 };

    mergeSyllableClusters(&sources, &cluster_owners, &syllable_serials);

    try @import("std").testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 4, 4 }, &cluster_owners);
    try @import("std").testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4, 5 }, &sources);
}

test "USE reordering moves only the first split prebase component" {
    var glyph_ids = [_]GlyphId{ 10, 20, 21 };
    var sources = [_]usize{ 0, 1, 1 };
    var cluster_owners = [_]usize{ 0, 1, 1 };
    var substituted = [_]bool{ false, true, true };
    var components = [_]gpos.LigatureComponentInfo{
        .{ .component_sources = [_]usize{0} ** gpos.max_ligature_components },
        .{ .component_sources = [_]usize{1} ** gpos.max_ligature_components },
        .{ .component_sources = [_]usize{1} ** gpos.max_ligature_components },
    };
    const syllable_serials = [_]u8{ 0x12, 0x12 };
    const codepoints = [_]u21{ 0x1b19, 0x1b40 };

    reorderPrebaseGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 10, 21 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 1 }, &sources);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1 }, &cluster_owners);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true }, &substituted);
}

test "USE inserts a dotted circle into each broken syllable" {
    const allocator = std.testing.allocator;
    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(allocator);
    try glyph_ids.appendSlice(allocator, &.{ 23, 58, 66 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    var cluster_owners = std.ArrayList(usize).empty;
    defer cluster_owners.deinit(allocator);
    try cluster_owners.appendSlice(allocator, &.{ 0, 0, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false, false });
    var components = std.ArrayList(gpos.LigatureComponentInfo).empty;
    defer components.deinit(allocator);
    for (sources.items) |source| {
        var info = gpos.LigatureComponentInfo{};
        info.component_sources[0] = source;
        try components.append(allocator, info);
    }
    const syllable_serials = [_]u8{ 0x12, 0x12, 0x27 };
    const codepoints = [_]u21{ 0x1b13, 0x1b36, 0x1b3e };

    try insertDottedCirclesForBrokenSyllables(
        allocator,
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &codepoints,
        128,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 23, 58, 66, 128 }, glyph_ids.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2 }, cluster_owners.items);
}

test {
    std.testing.refAllDecls(@This());
}
