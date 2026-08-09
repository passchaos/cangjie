const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
const gsub = @import("gsub.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

const rphf_feature = unicode.tag("rphf");
const half_feature = unicode.tag("half");
const rphf_source_mask = gsub.sourceFeatureMaskForTag(rphf_feature).?;
const half_source_mask = gsub.sourceFeatureMaskForTag(half_feature).?;

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .dev2 => true,
        else => false,
    };
}

pub fn reorderPreBaseMatras(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
) void {
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) : (index += 1) {
        const source_index = glyph_source_indices.items[index];
        if (source_index >= codepoints.len) continue;
        if (!isPreBaseMatra(codepoints[source_index])) continue;

        const syllable_start = devanagariSyllableStart(codepoints, source_index);
        const target = preBaseMatraTargetGlyphIndex(glyph_source_indices.items, codepoints, syllable_start, source_index, index);
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            index,
            target,
        );
    }
}

pub fn insertDottedCirclesForBrokenClusters(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    dotted_circle_glyph: GlyphId,
) !void {
    if (dotted_circle_glyph == 0) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source_index = glyph_source_indices.items[glyph_index];
        if (source_index >= codepoints.len) continue;
        if (!startsBrokenCluster(codepoints, source_index)) continue;
        const insert_index = if (isPreBaseMatra(codepoints[source_index])) glyph_index + 1 else glyph_index;

        try shaping_metadata.insert(
            allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            insert_index,
            dotted_circle_glyph,
            source_index,
            glyph_cluster_indices.items[glyph_index],
        );
        glyph_index += 1;
    }
}

pub fn markBasicSourceFeatures(source_features: []u32, codepoints: []const u21) bool {
    @memset(source_features, 0);
    var marked = false;

    var index: usize = 0;
    while (index < codepoints.len) {
        if (!isDevanagariSyllableCodepoint(codepoints[index])) {
            index += 1;
            continue;
        }

        const syllable_start = index;
        const syllable_end = devanagariSyllableEnd(codepoints, syllable_start);
        if (hasInitialReph(codepoints, syllable_start, syllable_end)) {
            source_features[syllable_start] |= rphf_source_mask;
            marked = true;
        }
        if (markHalfSources(source_features, codepoints, syllable_start, syllable_end)) {
            marked = true;
        }
        index = syllable_end;
    }

    return marked;
}

pub fn reorderRephs(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
) void {
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) {
        const source_index = glyph_source_indices.items[index];
        if (!isFormedReph(ligature_components, ligature_components.infos.items[index], source_index, codepoints)) {
            index += 1;
            continue;
        }

        const syllable_end = devanagariSyllableEnd(codepoints, source_index);
        const target = rephTargetGlyphIndex(
            glyph_source_indices.items,
            codepoints,
            source_index,
            syllable_end,
            index,
        );
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            index,
            target,
        );
        index = target + 1;
    }
}

const pre_reorder_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("nukt") },
    .{ .tag = unicode.tag("akhn") },
};

const basic_feature_applications_without_reph = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = half_feature, .source_scoped = true },
    .{ .tag = unicode.tag("cjct") },
};

const basic_feature_applications_with_reph = [_]gsub.FeatureApplication{
    .{ .tag = rphf_feature, .source_scoped = true },
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = half_feature, .source_scoped = true },
    .{ .tag = unicode.tag("cjct") },
};

const pre_reph_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pres") },
};

const final_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvs") },
    .{ .tag = unicode.tag("blws") },
    .{ .tag = unicode.tag("psts") },
};

pub fn preReorderFeatureApplications() []const gsub.FeatureApplication {
    return &pre_reorder_feature_applications;
}

pub fn basicFeatureApplications(has_initial_reph: bool) []const gsub.FeatureApplication {
    return if (has_initial_reph)
        &basic_feature_applications_with_reph
    else
        &basic_feature_applications_without_reph;
}

pub fn preRephFeatureApplications() []const gsub.FeatureApplication {
    return &pre_reph_feature_applications;
}

pub fn finalFeatureApplications() []const gsub.FeatureApplication {
    return &final_feature_applications;
}

fn isPreBaseMatra(codepoint: u21) bool {
    return switch (codepoint) {
        0x093f => true,
        else => false,
    };
}

fn startsBrokenCluster(codepoints: []const u21, source_index: usize) bool {
    if (source_index != 0 and isDevanagariSyllableCodepoint(codepoints[source_index - 1])) return false;
    if (isDevanagariConsonant(codepoints[source_index]) or isDevanagariIndependentVowel(codepoints[source_index])) return false;
    const syllable_end = devanagariSyllableEnd(codepoints, source_index);
    if (syllable_end <= source_index) return false;
    if (codepoints[source_index] == 0x094d) return true;
    return !hasConsonant(codepoints[source_index..syllable_end]);
}

fn hasInitialReph(codepoints: []const u21, syllable_start: usize, syllable_end: usize) bool {
    if (syllable_start + 2 >= syllable_end) return false;
    if (codepoints[syllable_start] != 0x0930 or codepoints[syllable_start + 1] != 0x094d) return false;
    if (isJoiner(codepoints[syllable_start + 2])) return false;
    return hasConsonant(codepoints[syllable_start + 2 .. syllable_end]);
}

fn markHalfSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize) bool {
    var marked = false;
    const base_source = halfBaseSource(codepoints, syllable_start, syllable_end);
    var index = syllable_start;
    while (index + 1 < syllable_end) : (index += 1) {
        if (!isDevanagariConsonant(codepoints[index])) continue;
        if (index >= base_source) continue;
        const virama_index = halfViramaIndex(codepoints, index, syllable_end) orelse continue;
        if (!hasConsonant(codepoints[virama_index + 1 .. syllable_end])) continue;

        source_features[index] |= half_source_mask;
        marked = true;
    }
    return marked;
}

fn halfBaseSource(codepoints: []const u21, syllable_start: usize, syllable_end: usize) usize {
    const has_prebase_matra = hasPreBaseMatraInRange(codepoints, syllable_start, syllable_end);
    var base = syllable_start;
    var index = syllable_start;
    while (index < syllable_end) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isDevanagariConsonant(codepoint)) continue;
        if (has_prebase_matra and index > syllable_start and codepoints[index - 1] == 0x094d and isPostBaseRa(codepoint)) {
            return previousConsonantSource(codepoints, syllable_start, index - 1) orelse base;
        }
        base = index;
    }
    return base;
}

fn hasPreBaseMatraInRange(codepoints: []const u21, syllable_start: usize, syllable_end: usize) bool {
    for (codepoints[syllable_start..syllable_end]) |codepoint| {
        if (isPreBaseMatra(codepoint)) return true;
    }
    return false;
}

fn previousConsonantSource(codepoints: []const u21, syllable_start: usize, before: usize) ?usize {
    var index = before;
    while (index > syllable_start) {
        index -= 1;
        if (isDevanagariConsonant(codepoints[index])) return index;
    }
    return null;
}

fn isPostBaseRa(codepoint: u21) bool {
    return codepoint == 0x0930;
}

fn halfViramaIndex(codepoints: []const u21, consonant_index: usize, syllable_end: usize) ?usize {
    if (consonant_index + 1 >= syllable_end) return null;
    if (codepoints[consonant_index + 1] == 0x094d) return consonant_index + 1;
    if (consonant_index + 2 < syllable_end and codepoints[consonant_index + 1] == 0x093c and codepoints[consonant_index + 2] == 0x094d) {
        return consonant_index + 2;
    }
    return null;
}

fn devanagariSyllableEnd(codepoints: []const u21, start: usize) usize {
    var index = start;
    var saw_virama = false;
    while (index < codepoints.len) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isDevanagariSyllableCodepoint(codepoint)) break;
        if (index != start and isDevanagariBase(codepoint) and !saw_virama) break;

        saw_virama = if (codepoint == 0x094d)
            true
        else if (saw_virama and isJoiner(codepoint))
            true
        else
            false;
    }
    return index;
}

fn devanagariSyllableStart(codepoints: []const u21, source_index: usize) usize {
    var index: usize = 0;
    var syllable_start: usize = 0;
    while (index <= source_index and index < codepoints.len) {
        if (!isDevanagariSyllableCodepoint(codepoints[index])) {
            index += 1;
            syllable_start = index;
            continue;
        }
        syllable_start = index;
        const syllable_end = devanagariSyllableEnd(codepoints, index);
        if (source_index < syllable_end) return syllable_start;
        index = syllable_end;
    }
    return source_index;
}

fn isFormedReph(store: *const ligature_provenance.Store, info: ligature_provenance.Info, source_index: usize, codepoints: []const u21) bool {
    if (source_index + 1 >= codepoints.len) return false;
    if (codepoints[source_index] != 0x0930 or codepoints[source_index + 1] != 0x094d) return false;
    if (info.component_count < 2 or info.multiplied) return false;
    const sources = store.componentSources(info) orelse return false;
    return sources[0] == source_index and sources[1] == source_index + 1;
}

fn preBaseMatraTargetGlyphIndex(sources: []const usize, codepoints: []const u21, syllable_start: usize, matra_source: usize, fallback_index: usize) usize {
    var fallback_target = fallback_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        if (source < syllable_start or source >= matra_source) continue;
        if (fallback_target == fallback_index) fallback_target = glyph_index;
        if (source + 1 < codepoints.len and codepoints[source] == 0x094d and codepoints[source + 1] == 0x0935) return @min(glyph_index + 1, fallback_index);
    }
    return fallback_target;
}

fn rephTargetGlyphIndex(
    sources: []const usize,
    codepoints: []const u21,
    syllable_start: usize,
    syllable_end: usize,
    reph_index: usize,
) usize {
    var target = reph_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index == reph_index) continue;
        if (source < syllable_start or source >= syllable_end) continue;
        if (source < codepoints.len and isDevanagariSyllableModifier(codepoints[source])) break;
        if (isPostHalantConsonant(codepoints, source, syllable_start)) {
            if (hasVisibleViramaBeforeSource(sources, glyph_index, source)) break;
        }
        target = glyph_index;
    }
    return target;
}

fn hasVisibleViramaBeforeSource(sources: []const usize, glyph_index: usize, source: usize) bool {
    if (source == 0) return false;
    var index = glyph_index;
    while (index > 0) {
        index -= 1;
        const previous_source = sources[index];
        if (previous_source < source - 1) return false;
        if (previous_source == source - 1) return true;
    }
    return false;
}

fn isPostHalantConsonant(codepoints: []const u21, source: usize, syllable_start: usize) bool {
    return source > syllable_start and
        source < codepoints.len and
        isDevanagariConsonant(codepoints[source]) and
        codepoints[source - 1] == 0x094d;
}

fn isDevanagariSyllableModifier(codepoint: u21) bool {
    return codepoint >= 0x0900 and codepoint <= 0x0903;
}

fn hasConsonant(codepoints: []const u21) bool {
    for (codepoints) |codepoint| {
        if (isDevanagariConsonant(codepoint)) return true;
    }
    return false;
}

fn isDevanagariSyllableCodepoint(codepoint: u21) bool {
    return isDevanagariBase(codepoint) or
        isDevanagariDependentMark(codepoint) or
        codepoint == 0x094d or
        isJoiner(codepoint);
}

fn isDevanagariBase(codepoint: u21) bool {
    return isDevanagariConsonant(codepoint) or isDevanagariIndependentVowel(codepoint);
}

fn isDevanagariConsonant(codepoint: u21) bool {
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        (codepoint >= 0x0958 and codepoint <= 0x095f);
}

fn isDevanagariIndependentVowel(codepoint: u21) bool {
    return (codepoint >= 0x0904 and codepoint <= 0x0914) or
        codepoint == 0x0960 or
        codepoint == 0x0961;
}

fn isDevanagariDependentMark(codepoint: u21) bool {
    return (codepoint >= 0x0900 and codepoint <= 0x0903) or
        (codepoint >= 0x093a and codepoint <= 0x094c) or
        (codepoint >= 0x094e and codepoint <= 0x094f) or
        (codepoint >= 0x0951 and codepoint <= 0x0957);
}

fn isJoiner(codepoint: u21) bool {
    return codepoint == 0x200c or codepoint == 0x200d;
}
