const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
const gsub = @import("gsub.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

const rphf_feature = unicode.tag("rphf");
const pref_feature = unicode.tag("pref");
const blwf_feature = unicode.tag("blwf");
const half_feature = unicode.tag("half");
const pstf_feature = unicode.tag("pstf");
const rphf_source_mask = gsub.sourceFeatureMaskForTag(rphf_feature).?;
const pref_source_mask = gsub.sourceFeatureMaskForTag(pref_feature).?;
const blwf_source_mask = gsub.sourceFeatureMaskForTag(blwf_feature).?;
const half_source_mask = gsub.sourceFeatureMaskForTag(half_feature).?;
const pstf_source_mask = gsub.sourceFeatureMaskForTag(pstf_feature).?;

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .dev2, .bng2, .beng, .gur2, .guru, .tel2, .telu, .knd2, .knda, .tml2, .taml, .mlm2, .mlym => true,
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
    script_tag: unicode.OpenTypeScriptTag,
) void {
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) : (index += 1) {
        const source_index = glyph_source_indices.items[index];
        if (source_index >= codepoints.len) continue;
        if (!isPreBaseMatra(codepoints[source_index], script_tag)) continue;

        const syllable_start = indicSyllableStart(codepoints, source_index, script_tag);
        const target_info = preBaseMatraTargetGlyphIndex(glyph_source_indices.items, ligature_components, codepoints, syllable_start, source_index, index, script_tag);
        if (target_info.merge_from_syllable_start) {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, syllable_start, index + 1);
        } else {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, target_info.index, index + 1);
        }
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            index,
            target_info.index,
        );
    }
}

pub fn reorderPrefGlyphs(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_pref_substituted: []const bool,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (!usesPrefSources(script_tag)) return;

    var index: usize = 0;
    while (index < glyph_source_indices.items.len) {
        const source_index = glyph_source_indices.items[index];
        if (!isFormedPref(ligature_components, ligature_components.infos.items[index], source_index, source_pref_substituted, codepoints, script_tag)) {
            index += 1;
            continue;
        }

        const syllable_start = indicSyllableStart(codepoints, source_index, script_tag);
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        const base_source = baseSource(codepoints, syllable_start, syllable_end, script_tag);
        const target = prefTargetGlyphIndex(glyph_source_indices.items, ligature_components, codepoints, syllable_start, base_source, index, script_tag);
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, target, index + 1);
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

pub fn markInitialMatraGlyphSources(source_features: []u32, glyph_source_indices: []const usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    var marked = false;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.len) {
        const source = glyph_source_indices[glyph_index];
        if (source >= codepoints.len or !isIndicSyllableCodepoint(codepoints[source], script_tag)) {
            glyph_index += 1;
            continue;
        }
        const start = glyph_index;
        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        while (glyph_index < glyph_source_indices.len) : (glyph_index += 1) {
            const next_source = glyph_source_indices[glyph_index];
            if (next_source < syllable_start or next_source >= syllable_end) break;
        }
        const first_source = glyph_source_indices[start];
        if (first_source < codepoints.len and isPreBaseMatra(codepoints[first_source], script_tag) and
            matraStartsIndicWord(glyph_source_indices, start, codepoints, script_tag))
        {
            source_features[first_source] |= gsub.sourceFeatureMaskForTag(unicode.tag("init")).?;
            marked = true;
        }
    }
    return marked;
}

fn matraStartsIndicWord(glyph_source_indices: []const usize, glyph_index: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (glyph_index == 0) return true;
    const previous_source = glyph_source_indices[glyph_index - 1];
    if (previous_source >= codepoints.len) return true;
    const previous = codepoints[previous_source];
    return !isIndicSyllableCodepoint(previous, script_tag) and !isIndicFormatOrNonspacingMark(previous);
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
    script_tag: unicode.OpenTypeScriptTag,
) !void {
    if (dotted_circle_glyph == 0) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source_index = glyph_source_indices.items[glyph_index];
        if (source_index >= codepoints.len) continue;
        if (!startsBrokenCluster(codepoints, source_index, script_tag)) continue;
        const insert_index = if (isPreBaseMatra(codepoints[source_index], script_tag)) glyph_index + 1 else glyph_index;

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

pub fn mergePlaceholderDependentMarks(glyph_cluster_indices: *std.ArrayList(usize), glyph_source_indices: *std.ArrayList(usize), codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source == 0 or source >= codepoints.len) continue;
        if (!isIndicDependentMark(codepoints[source], script_tag)) continue;
        const previous = source - 1;
        if (!isIndicPlaceholderBase(codepoints[previous], script_tag)) continue;
        const previous_glyph = glyphIndexForSource(glyph_source_indices.items, previous) orelse continue;
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, @min(previous_glyph, glyph_index), @max(previous_glyph, glyph_index) + 1);
    }
}

pub fn markBasicSourceFeatures(source_features: []u32, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    @memset(source_features, 0);
    var marked = false;

    var index: usize = 0;
    while (index < codepoints.len) {
        if (!isIndicSyllableCodepoint(codepoints[index], script_tag)) {
            index += 1;
            continue;
        }

        const syllable_start = index;
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        if (hasInitialReph(codepoints, syllable_start, syllable_end, script_tag)) {
            source_features[syllable_start] |= rphf_source_mask;
            marked = true;
        }
        if (markHalfSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
            marked = true;
        }
        if (markPrefSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
            marked = true;
        }
        index = syllable_end;
    }

    return marked;
}

pub fn recordPrefSubstitutions(glyph_source_indices: []const usize, glyph_stage_substituted: []const bool, source_pref_substituted: []bool) void {
    std.debug.assert(glyph_source_indices.len == glyph_stage_substituted.len);
    for (glyph_source_indices, glyph_stage_substituted) |source, substituted| {
        if (!substituted) continue;
        if (source < source_pref_substituted.len) source_pref_substituted[source] = true;
    }
}

pub fn reorderRephs(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) {
        const source_index = glyph_source_indices.items[index];
        if (!isFormedReph(ligature_components, ligature_components.infos.items[index], source_index, codepoints, script_tag)) {
            index += 1;
            continue;
        }

        const syllable_end = indicSyllableEnd(codepoints, source_index, script_tag);
        const target = rephTargetGlyphIndex(
            glyph_source_indices.items,
            codepoints,
            source_index,
            syllable_end,
            index,
            script_tag,
        );
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, @min(index, target), @max(index, target) + 1);
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

pub fn reorderBeforeSubscriptVowels(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .tel2 and script_tag != .telu) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= codepoints.len or !isBeforeSubscriptVowel(codepoints[source], script_tag)) continue;

        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        const target = beforeSubscriptVowelTargetGlyph(glyph_source_indices.items, codepoints, syllable_start, source, glyph_index, script_tag) orelse continue;
        if (target >= glyph_index) continue;
        const merge_start = firstGlyphInSourceRange(glyph_source_indices.items, syllable_start, source) orelse target;
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, merge_start, glyph_index + 1);
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            target,
        );
        glyph_index = target + 1;
    }
}

fn beforeSubscriptVowelTargetGlyph(sources: []const usize, codepoints: []const u21, syllable_start: usize, vowel_source: usize, fallback_index: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    var target: ?usize = null;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        if (source < syllable_start or source >= vowel_source) continue;
        if (source + 1 >= codepoints.len) continue;
        if (codepoints[source] != viramaCodepoint(script_tag)) continue;
        if (!isIndicConsonant(codepoints[source + 1], script_tag)) continue;
        target = glyph_index;
    }
    return target;
}

fn firstGlyphInSourceRange(sources: []const usize, start_source: usize, end_source: usize) ?usize {
    for (sources, 0..) |source, glyph_index| {
        if (source >= start_source and source <= end_source) return glyph_index;
    }
    return null;
}

const pre_reorder_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("nukt") },
    .{ .tag = unicode.tag("akhn") },
};

const basic_feature_applications_without_reph = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = blwf_feature, .source_scoped = true },
    .{ .tag = half_feature, .source_scoped = true },
    .{ .tag = pstf_feature, .source_scoped = true },
    .{ .tag = unicode.tag("cjct") },
};

const basic_feature_applications_with_reph = [_]gsub.FeatureApplication{
    .{ .tag = rphf_feature, .source_scoped = true },
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = blwf_feature, .source_scoped = true },
    .{ .tag = half_feature, .source_scoped = true },
    .{ .tag = pstf_feature, .source_scoped = true },
    .{ .tag = unicode.tag("cjct") },
};

const pre_reph_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pres") },
};

const pref_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = pref_feature, .source_scoped = true },
};

const final_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("abvs") },
    .{ .tag = unicode.tag("blws") },
    .{ .tag = unicode.tag("psts") },
    .{ .tag = unicode.tag("haln") },
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

pub fn prefFeatureApplications() []const gsub.FeatureApplication {
    return &pref_feature_applications;
}

pub fn finalFeatureApplications() []const gsub.FeatureApplication {
    return &final_feature_applications;
}

fn isPreBaseMatra(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => codepoint == 0x09c7 or codepoint == 0x09c8,
        .gur2, .guru => codepoint == 0x0a3f,
        .tel2, .telu => codepoint == 0x0c46 or codepoint == 0x0c47 or codepoint == 0x0c48,
        .knd2, .knda => codepoint == 0x0cbf,
        .tml2, .taml => codepoint == 0x0bc6 or codepoint == 0x0bc7 or codepoint == 0x0bc8,
        .mlm2, .mlym => codepoint == 0x0d46 or codepoint == 0x0d47 or codepoint == 0x0d48,
        else => codepoint == 0x093f,
    };
}

pub fn normalizeInitialConsonantSyllableOrder(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .knd2 and script_tag != .knda) return;
    if (codepoints.len < 3) return;
    if (codepoints[0] != rephRaCodepoint(script_tag) or
        codepoints[1] != viramaCodepoint(script_tag) or
        codepoints[2] != 0x200d)
    {
        return;
    }

    const halant_glyph = glyphIndexForSource(glyph_source_indices.items, 1) orelse return;
    const zwj_glyph = glyphIndexForSource(glyph_source_indices.items, 2) orelse return;
    if (zwj_glyph <= halant_glyph) return;
    shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, halant_glyph, zwj_glyph + 1);
    shaping_metadata.move(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        zwj_glyph,
        halant_glyph,
    );
}

fn glyphIndexForSource(sources: []const usize, target_source: usize) ?usize {
    for (sources, 0..) |source, glyph_index| {
        if (source == target_source) return glyph_index;
    }
    return null;
}

fn startsBrokenCluster(codepoints: []const u21, source_index: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (source_index != 0 and isIndicSyllableCodepoint(codepoints[source_index - 1], script_tag)) return false;
    if (source_index != 0 and codepoints[source_index - 1] == 0x25cc) return false;
    if (isIndicConsonant(codepoints[source_index], script_tag) or isIndicIndependentVowel(codepoints[source_index], script_tag)) return false;
    const syllable_end = indicSyllableEnd(codepoints, source_index, script_tag);
    if (syllable_end <= source_index) return false;
    if (codepoints[source_index] == viramaCodepoint(script_tag)) return true;
    return !hasConsonant(codepoints[source_index..syllable_end], script_tag);
}

fn hasInitialReph(codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (syllable_start + 2 >= syllable_end) return false;
    if (codepoints[syllable_start] != rephRaCodepoint(script_tag) or codepoints[syllable_start + 1] != viramaCodepoint(script_tag)) return false;
    if (isJoiner(codepoints[syllable_start + 2])) return false;
    return hasConsonant(codepoints[syllable_start + 2 .. syllable_end], script_tag);
}

fn markHalfSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    var marked = false;
    if (script_tag == .tel2 or script_tag == .telu) {
        if (markPostBaseViramaConsonantSources(source_features, codepoints, syllable_start, syllable_end, script_tag, blwf_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .mlm2 or script_tag == .mlym) {
        if (markPostBaseViramaConsonantSources(source_features, codepoints, syllable_start, syllable_end, script_tag, pstf_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .tml2 or script_tag == .taml) {
        if (markPreBaseConsonantViramaSources(source_features, codepoints, syllable_start, syllable_end, script_tag, half_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .knd2 or script_tag == .knda) {
        if (markKannadaRaHalfSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag != .dev2) return false;
    const base_source = halfBaseSource(codepoints, syllable_start, syllable_end, script_tag);
    var index = syllable_start;
    while (index + 1 < syllable_end) : (index += 1) {
        if (!isIndicConsonant(codepoints[index], script_tag)) continue;
        if (index >= base_source) continue;
        const virama_index = halfViramaIndex(codepoints, index, syllable_end, script_tag) orelse continue;
        if (!hasConsonant(codepoints[virama_index + 1 .. syllable_end], script_tag)) continue;

        source_features[index] |= half_source_mask;
        marked = true;
    }
    return marked;
}

fn markPreBaseConsonantViramaSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag, source_mask: u32) bool {
    var marked = false;
    var index = syllable_start;
    while (index + 1 < syllable_end) : (index += 1) {
        if (!isIndicConsonant(codepoints[index], script_tag)) continue;
        if (codepoints[index + 1] != viramaCodepoint(script_tag)) continue;
        source_features[index] |= source_mask;
        marked = true;
    }
    return marked;
}

fn markPostBaseViramaConsonantSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag, source_mask: u32) bool {
    var marked = false;
    var index = syllable_start;
    while (index + 1 < syllable_end) : (index += 1) {
        if (codepoints[index] != viramaCodepoint(script_tag)) continue;
        if (!isIndicConsonant(codepoints[index + 1], script_tag)) continue;
        source_features[index] |= source_mask;
        marked = true;
    }
    return marked;
}

fn markKannadaRaHalfSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (syllable_start + 2 >= syllable_end) return false;
    if (codepoints[syllable_start] != rephRaCodepoint(script_tag)) return false;

    const virama_source: usize = if (codepoints[syllable_start + 1] == viramaCodepoint(script_tag))
        syllable_start + 1
    else if (codepoints[syllable_start + 1] == 0x200d and
        syllable_start + 2 < syllable_end and
        codepoints[syllable_start + 2] == viramaCodepoint(script_tag))
        syllable_start + 2
    else
        return false;
    const consonant_source = nextConsonantSource(codepoints, virama_source + 1, syllable_end, script_tag) orelse return false;
    source_features[syllable_start] |= half_source_mask;
    source_features[virama_source] |= blwf_source_mask;
    source_features[virama_source] |= half_source_mask;
    source_features[consonant_source] |= half_source_mask;
    return true;
}

fn nextConsonantSource(codepoints: []const u21, start: usize, end: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    var index = start;
    while (index < end) : (index += 1) {
        if (isIndicConsonant(codepoints[index], script_tag)) return index;
    }
    return null;
}

fn markPrefSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (!usesPrefSources(script_tag)) return false;
    const base_source = baseSource(codepoints, syllable_start, syllable_end, script_tag);
    if (base_source + 2 >= syllable_end) return false;

    var index = base_source + 1;
    while (index + 1 < syllable_end) : (index += 1) {
        if (codepoints[index] != viramaCodepoint(script_tag)) continue;
        if (!isPrefRa(codepoints[index + 1], script_tag)) continue;
        source_features[index] |= pref_source_mask;
        source_features[index + 1] |= pref_source_mask;
        return true;
    }
    return false;
}

fn usesPrefSources(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .mlm2, .mlym => true,
        else => false,
    };
}

fn baseSource(codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    if (usesPrefSources(script_tag)) {
        var index = syllable_start;
        while (index < syllable_end) : (index += 1) {
            if (isIndicConsonant(codepoints[index], script_tag)) return index;
        }
        return syllable_start;
    }
    return halfBaseSource(codepoints, syllable_start, syllable_end, script_tag);
}

fn halfBaseSource(codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    const has_prebase_matra = hasPreBaseMatraInRange(codepoints, syllable_start, syllable_end, script_tag);
    var base = syllable_start;
    var index = syllable_start;
    while (index < syllable_end) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isIndicConsonant(codepoint, script_tag)) continue;
        if (script_tag == .dev2 and has_prebase_matra and index > syllable_start and codepoints[index - 1] == 0x094d and isPostBaseRa(codepoint, script_tag)) {
            return previousConsonantSource(codepoints, syllable_start, index - 1, script_tag) orelse base;
        }
        base = index;
    }
    return base;
}

fn hasPreBaseMatraInRange(codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    for (codepoints[syllable_start..syllable_end]) |codepoint| {
        if (isPreBaseMatra(codepoint, script_tag)) return true;
    }
    return false;
}

fn previousConsonantSource(codepoints: []const u21, syllable_start: usize, before: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    var index = before;
    while (index > syllable_start) {
        index -= 1;
        if (isIndicConsonant(codepoints[index], script_tag)) return index;
    }
    return null;
}

fn isPostBaseRa(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dev2 and codepoint == 0x0930;
}

fn isPrefRa(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .mlm2, .mlym => codepoint == 0x0d30,
        else => false,
    };
}

fn halfViramaIndex(codepoints: []const u21, consonant_index: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    const virama = viramaCodepoint(script_tag);
    if (consonant_index + 1 >= syllable_end) return null;
    if (codepoints[consonant_index + 1] == virama) return consonant_index + 1;
    if (script_tag == .dev2 and consonant_index + 2 < syllable_end and codepoints[consonant_index + 1] == 0x093c and codepoints[consonant_index + 2] == virama) {
        return consonant_index + 2;
    }
    return null;
}

fn indicSyllableEnd(codepoints: []const u21, start: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    var index = start;
    var saw_virama = false;
    while (index < codepoints.len) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isIndicSyllableCodepoint(codepoint, script_tag)) break;
        if (index != start and isIndicBase(codepoint, script_tag) and !saw_virama) break;

        saw_virama = if (codepoint == viramaCodepoint(script_tag))
            true
        else if (saw_virama and isJoiner(codepoint))
            true
        else if (isIndicDependentMark(codepoint, script_tag))
            saw_virama
        else
            false;
    }
    return index;
}

fn indicSyllableStart(codepoints: []const u21, source_index: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    var index: usize = 0;
    var syllable_start: usize = 0;
    while (index <= source_index and index < codepoints.len) {
        if (!isIndicSyllableCodepoint(codepoints[index], script_tag)) {
            index += 1;
            syllable_start = index;
            continue;
        }
        syllable_start = index;
        const syllable_end = indicSyllableEnd(codepoints, index, script_tag);
        if (source_index < syllable_end) return syllable_start;
        index = syllable_end;
    }
    return source_index;
}

fn isFormedReph(store: *const ligature_provenance.Store, info: ligature_provenance.Info, source_index: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (source_index + 1 >= codepoints.len) return false;
    if (codepoints[source_index] != rephRaCodepoint(script_tag) or codepoints[source_index + 1] != viramaCodepoint(script_tag)) return false;
    if (info.component_count < 2 or info.flags.multiplied) return false;
    const sources = store.componentSources(info) orelse return false;
    return sources[0] == source_index and sources[1] == source_index + 1;
}

const PreBaseMatraTarget = struct {
    index: usize,
    merge_from_syllable_start: bool = false,
};

fn preBaseMatraTargetGlyphIndex(sources: []const usize, ligature_components: *const ligature_provenance.Store, codepoints: []const u21, syllable_start: usize, matra_source: usize, fallback_index: usize, script_tag: unicode.OpenTypeScriptTag) PreBaseMatraTarget {
    var fallback_target = fallback_index;
    var blocked_pref_target: ?usize = null;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        const effective_source = effectiveIndicSource(ligature_components, glyph_index, source, codepoints, script_tag);
        if (effective_source < syllable_start or effective_source >= matra_source) continue;
        if (fallback_target == fallback_index) fallback_target = glyph_index;
        if (!isFormedPrefLigature(ligature_components, glyph_index, source, codepoints, script_tag) and
            usesPrefSources(script_tag) and
            effective_source + 1 < codepoints.len and
            codepoints[effective_source] == viramaCodepoint(script_tag) and
            isPrefRa(codepoints[effective_source + 1], script_tag))
        {
            blocked_pref_target = @min(glyph_index + 1, fallback_index);
        }
        if (script_tag == .dev2 and effective_source + 1 < codepoints.len and codepoints[effective_source] == 0x094d and codepoints[effective_source + 1] == 0x0935) return .{ .index = @min(glyph_index + 1, fallback_index) };
    }
    if (blocked_pref_target) |target| return .{ .index = target, .merge_from_syllable_start = true };
    return .{ .index = fallback_target };
}

fn prefTargetGlyphIndex(sources: []const usize, ligature_components: *const ligature_provenance.Store, codepoints: []const u21, syllable_start: usize, base_source: usize, fallback_index: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    var target = fallback_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        const effective_source = effectiveIndicSource(ligature_components, glyph_index, source, codepoints, script_tag);
        if (effective_source < syllable_start or effective_source > base_source) continue;
        target = glyph_index;
        if (source < codepoints.len and isPreBaseMatra(codepoints[source], script_tag)) {
            return @min(glyph_index + 1, fallback_index);
        }
    }
    return target;
}

fn effectiveIndicSource(ligature_components: *const ligature_provenance.Store, glyph_index: usize, fallback_source: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) usize {
    if (glyph_index >= ligature_components.infos.items.len) return fallback_source;
    const info = ligature_components.infos.items[glyph_index];
    if (!info.isLigature() or !info.flags.multiplied) return fallback_source;
    const sources = ligature_components.componentSources(info) orelse return fallback_source;
    const component = @as(usize, info.flags.multiple_component);
    if (component >= sources.len) return fallback_source;
    return repairedPrefComponentSource(sources, component, codepoints, script_tag);
}

fn isFormedPref(store: *const ligature_provenance.Store, info: ligature_provenance.Info, source_index: usize, source_pref_substituted: []const bool, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (!usesPrefSources(script_tag)) return false;
    if (!formedPrefLigatureMatches(store, info, source_index, codepoints, script_tag)) return false;
    return source_index >= source_pref_substituted.len or source_pref_substituted[source_index];
}

fn isFormedPrefLigature(ligature_components: *const ligature_provenance.Store, glyph_index: usize, fallback_source: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (glyph_index >= ligature_components.infos.items.len) return false;
    return formedPrefLigatureMatches(ligature_components, ligature_components.infos.items[glyph_index], fallback_source, codepoints, script_tag);
}

fn formedPrefLigatureMatches(store: *const ligature_provenance.Store, info: ligature_provenance.Info, source_index: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (!usesPrefSources(script_tag)) return false;
    if (!info.isLigature() or info.flags.multiplied) return false;
    const sources = store.componentSources(info) orelse return false;
    if (sources.len != 2) return false;
    const first_source = repairedPrefComponentSource(sources, 0, codepoints, script_tag);
    const second_source = repairedPrefComponentSource(sources, 1, codepoints, script_tag);
    if (source_index != first_source and source_index != second_source) return false;
    if (first_source >= codepoints.len or second_source >= codepoints.len) return false;
    if (codepoints[first_source] != viramaCodepoint(script_tag) or !isPrefRa(codepoints[second_source], script_tag)) return false;
    return true;
}

fn repairedPrefComponentSource(sources: []const usize, component: usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) usize {
    if (component >= sources.len) return 0;
    const source = sources[component];
    if (usesPrefSources(script_tag) and
        component == 1 and
        sources.len == 2 and
        sources[0] == source and
        source + 1 < codepoints.len and
        codepoints[source] == viramaCodepoint(script_tag) and
        isPrefRa(codepoints[source + 1], script_tag))
    {
        return source + 1;
    }
    return source;
}

fn rephTargetGlyphIndex(
    sources: []const usize,
    codepoints: []const u21,
    syllable_start: usize,
    syllable_end: usize,
    reph_index: usize,
    script_tag: unicode.OpenTypeScriptTag,
) usize {
    var target = reph_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index == reph_index) continue;
        if (source < syllable_start or source >= syllable_end) continue;
        if (source < codepoints.len and isIndicSyllableModifier(codepoints[source], script_tag)) break;
        if (isPostHalantConsonant(codepoints, source, syllable_start, script_tag)) {
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

fn isPostHalantConsonant(codepoints: []const u21, source: usize, syllable_start: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    return source > syllable_start and
        source < codepoints.len and
        isIndicConsonant(codepoints[source], script_tag) and
        codepoints[source - 1] == viramaCodepoint(script_tag);
}

fn isIndicSyllableModifier(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => codepoint >= 0x0981 and codepoint <= 0x0983,
        .gur2, .guru => codepoint >= 0x0a01 and codepoint <= 0x0a03,
        .tel2, .telu => codepoint >= 0x0c00 and codepoint <= 0x0c03,
        .knd2, .knda => codepoint >= 0x0c82 and codepoint <= 0x0c83,
        .tml2, .taml => codepoint == 0x0b82 or codepoint == 0x0b83,
        else => codepoint >= 0x0900 and codepoint <= 0x0903,
    };
}

fn hasConsonant(codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    for (codepoints) |codepoint| {
        if (isIndicConsonant(codepoint, script_tag)) return true;
    }
    return false;
}

fn isIndicSyllableCodepoint(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return isIndicBase(codepoint, script_tag) or
        isIndicDependentMark(codepoint, script_tag) or
        codepoint == viramaCodepoint(script_tag) or
        isJoiner(codepoint);
}

fn isIndicBase(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return isIndicConsonant(codepoint, script_tag) or isIndicIndependentVowel(codepoint, script_tag);
}

fn isIndicPlaceholderBase(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .knd2, .knda => codepoint == 0x0c80,
        else => false,
    };
}

fn isIndicConsonant(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => (codepoint >= 0x0995 and codepoint <= 0x09b9) or
            (codepoint >= 0x09dc and codepoint <= 0x09df),
        .gur2, .guru => (codepoint >= 0x0a15 and codepoint <= 0x0a39) or
            (codepoint >= 0x0a59 and codepoint <= 0x0a5e) or
            (codepoint >= 0x0a72 and codepoint <= 0x0a74),
        .tel2, .telu => (codepoint >= 0x0c15 and codepoint <= 0x0c39) or
            codepoint == 0x0c58 or
            codepoint == 0x0c59,
        .knd2, .knda => codepoint == 0x0c80 or
            (codepoint >= 0x0c95 and codepoint <= 0x0cb9) or
            codepoint == 0x0cde,
        .tml2, .taml => (codepoint >= 0x0b95 and codepoint <= 0x0bb9) or
            (codepoint >= 0x0bd0 and codepoint <= 0x0bd7) or
            (codepoint >= 0x11fc0 and codepoint <= 0x11ff1),
        .mlm2, .mlym => (codepoint >= 0x0d15 and codepoint <= 0x0d39) or
            (codepoint >= 0x0d54 and codepoint <= 0x0d56) or
            (codepoint >= 0x0d7a and codepoint <= 0x0d7f),
        else => (codepoint >= 0x0915 and codepoint <= 0x0939) or
            (codepoint >= 0x0958 and codepoint <= 0x095f),
    };
}

fn isIndicIndependentVowel(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => (codepoint >= 0x0985 and codepoint <= 0x0994) or
            codepoint == 0x09e0 or
            codepoint == 0x09e1,
        .gur2, .guru => (codepoint >= 0x0a05 and codepoint <= 0x0a0a) or
            (codepoint >= 0x0a0f and codepoint <= 0x0a10) or
            (codepoint >= 0x0a13 and codepoint <= 0x0a14),
        .tel2, .telu => (codepoint >= 0x0c05 and codepoint <= 0x0c0c) or
            (codepoint >= 0x0c0e and codepoint <= 0x0c10) or
            (codepoint >= 0x0c12 and codepoint <= 0x0c14) or
            codepoint == 0x0c60 or
            codepoint == 0x0c61,
        .knd2, .knda => (codepoint >= 0x0c85 and codepoint <= 0x0c8c) or
            (codepoint >= 0x0c8e and codepoint <= 0x0c90) or
            (codepoint >= 0x0c92 and codepoint <= 0x0c94) or
            codepoint == 0x0ce0 or
            codepoint == 0x0ce1,
        .tml2, .taml => (codepoint >= 0x0b85 and codepoint <= 0x0b94) or
            codepoint >= 0x11fc0 and codepoint <= 0x11fd4,
        .mlm2, .mlym => (codepoint >= 0x0d05 and codepoint <= 0x0d14) or
            codepoint == 0x0d60 or
            codepoint == 0x0d61,
        else => (codepoint >= 0x0904 and codepoint <= 0x0914) or
            codepoint == 0x0960 or
            codepoint == 0x0961,
    };
}

fn isIndicDependentMark(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => (codepoint >= 0x0981 and codepoint <= 0x0983) or
            (codepoint >= 0x09be and codepoint <= 0x09cc) or
            codepoint == 0x09d7,
        .gur2, .guru => (codepoint >= 0x0a01 and codepoint <= 0x0a03) or
            codepoint == 0x0a3c or
            (codepoint >= 0x0a3e and codepoint <= 0x0a42) or
            (codepoint >= 0x0a47 and codepoint <= 0x0a48) or
            (codepoint >= 0x0a4b and codepoint <= 0x0a4d) or
            codepoint == 0x0a51 or
            (codepoint >= 0x0a70 and codepoint <= 0x0a71) or
            codepoint == 0x0a75,
        .tel2, .telu => (codepoint >= 0x0c00 and codepoint <= 0x0c04) or
            codepoint == 0x0c3c or
            (codepoint >= 0x0c3e and codepoint <= 0x0c44) or
            (codepoint >= 0x0c46 and codepoint <= 0x0c48) or
            (codepoint >= 0x0c4a and codepoint <= 0x0c4d) or
            codepoint == 0x0c55 or
            codepoint == 0x0c56 or
            (codepoint >= 0x0c62 and codepoint <= 0x0c63),
        .knd2, .knda => codepoint == 0x0c81 or
            (codepoint >= 0x0c82 and codepoint <= 0x0c83) or
            codepoint == 0x0cbc or
            (codepoint >= 0x0cbe and codepoint <= 0x0cc4) or
            (codepoint >= 0x0cc6 and codepoint <= 0x0cc8) or
            (codepoint >= 0x0cca and codepoint <= 0x0ccd) or
            (codepoint >= 0x0cd5 and codepoint <= 0x0cd6) or
            (codepoint >= 0x0ce2 and codepoint <= 0x0ce3),
        .tml2, .taml => codepoint == 0x0b82 or
            codepoint == 0x0b83 or
            (codepoint >= 0x0bbe and codepoint <= 0x0bc2) or
            (codepoint >= 0x0bc6 and codepoint <= 0x0bc8) or
            (codepoint >= 0x0bca and codepoint <= 0x0bcd) or
            codepoint == 0x0bd7,
        .mlm2, .mlym => (codepoint >= 0x0d00 and codepoint <= 0x0d03) or
            (codepoint >= 0x0d3b and codepoint <= 0x0d4c) or
            codepoint == 0x0d57,
        else => (codepoint >= 0x0900 and codepoint <= 0x0903) or
            (codepoint >= 0x093a and codepoint <= 0x094c) or
            (codepoint >= 0x094e and codepoint <= 0x094f) or
            (codepoint >= 0x0951 and codepoint <= 0x0957),
    };
}

fn isBeforeSubscriptVowel(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .tel2, .telu => codepoint >= 0x0c3e and codepoint <= 0x0c42,
        else => false,
    };
}

fn viramaCodepoint(script_tag: unicode.OpenTypeScriptTag) u21 {
    return switch (script_tag) {
        .bng2, .beng => 0x09cd,
        .gur2, .guru => 0x0a4d,
        .tel2, .telu => 0x0c4d,
        .knd2, .knda => 0x0ccd,
        .tml2, .taml => 0x0bcd,
        .mlm2, .mlym => 0x0d4d,
        else => 0x094d,
    };
}

fn rephRaCodepoint(script_tag: unicode.OpenTypeScriptTag) u21 {
    return switch (script_tag) {
        .bng2, .beng => 0x09b0,
        .gur2, .guru => 0x0a30,
        .tel2, .telu => 0x0c30,
        .knd2, .knda => 0x0cb0,
        .tml2, .taml => 0x0bb0,
        .mlm2, .mlym => 0x0d30,
        else => 0x0930,
    };
}

fn isIndicFormatOrNonspacingMark(codepoint: u21) bool {
    return unicode.isDefaultIgnorableForShaping(codepoint) or unicode.isNonspacingMarkCodepoint(codepoint);
}

fn isJoiner(codepoint: u21) bool {
    return codepoint == 0x200c or codepoint == 0x200d;
}

test "Gurmukhi standalone udaat inserts dotted circle" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 0);

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.append(std.testing.allocator, 0);

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.append(std.testing.allocator, false);

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.append(std.testing.allocator, .{});

    const codepoints = [_]u21{0x0a51};
    try insertDottedCirclesForBrokenClusters(
        std.testing.allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        2,
        .gur2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Gurmukhi udaat after explicit dotted circle stays attached" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 1 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{} });

    const codepoints = [_]u21{ 0x25cc, 0x0a51 };
    try insertDottedCirclesForBrokenClusters(
        std.testing.allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        2,
        .gur2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Kannada initial ra virama ZWJ normalizes for legacy half form" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 3, 4 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 3 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0cb0, 0x0ccd, 0x200d, 0x0c95 };
    normalizeInitialConsonantSyllableOrder(
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        .knd2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 2, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 3 }, clusters.items);
}

test "Indic reph reorder merges Kannada syllable clusters" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 5, 1 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 6 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.append(std.testing.allocator, try ligatures.addLigature(std.testing.allocator, &.{ 0, 1 }));
    try ligatures.infos.append(std.testing.allocator, .{});

    const codepoints = [_]u21{ 0x0cb0, 0x0ccd, 0x0c95 };
    reorderRephs(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .knd2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 5 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Kannada placeholder prevents broken mark dotted circle" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{} });

    const codepoints = [_]u21{ 0x0c80, 0x0c82 };
    try insertDottedCirclesForBrokenClusters(
        std.testing.allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        3,
        .knd2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Kannada placeholder merges dependent mark cluster" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3 });

    const codepoints = [_]u21{ 0x0c80, 0x0c82 };
    mergePlaceholderDependentMarks(&clusters, &sources, &codepoints, .knd2);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Telugu post-base virama consonant marks blwf source" {
    var features = [_]u32{0} ** 8;
    const codepoints = [_]u21{ 0x0c1a, 0x0c3f, 0x0c32, 0x0c4d, 0x0c15, 0x0c42, 0x0c30, 0x0c4d };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .tel2));
    try std.testing.expectEqual(blwf_source_mask, features[3]);
    try std.testing.expectEqual(@as(u32, 0), features[4]);
}

test "Telugu before-subscript vowel reorders before subscript glyph" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 13, 4, 16, 6 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 2, 3, 5 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 6, 9, 15 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ true, false, true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0c1a, 0x0c3f, 0x0c32, 0x0c4d, 0x0c15, 0x0c42 };
    reorderBeforeSubscriptVowels(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .tel2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 13, 4, 6, 16 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 5, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 6, 6, 6 }, clusters.items);
}

test "Malayalam post-base virama consonant marks pstf source" {
    var features = [_]u32{0} ** 3;
    const codepoints = [_]u21{ 0x0d15, 0x0d4d, 0x0d2f };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .mlm2));
    try std.testing.expectEqual(pstf_source_mask, features[1]);
    try std.testing.expectEqual(@as(u32, 0), features[2]);
}

test "Tamil consonant virama marks half source" {
    var features = [_]u32{0} ** 3;
    const codepoints = [_]u21{ 0x0ba4, 0x0bcd, 0x00b3 };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .tml2));
    try std.testing.expectEqual(half_source_mask, features[0]);
    try std.testing.expectEqual(@as(u32, 0), features[1]);
}

test "Bengali pre-base matras move before bases and mark init only at word start" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 1, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 2, 2 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x09ac, 0x09c7, 0x09ac, 0x09c7 };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .bng2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1, 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 3, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2 }, clusters.items);

    var source_features = [_]u32{0} ** 4;
    try std.testing.expect(markInitialMatraGlyphSources(&source_features, sources.items, &codepoints, .bng2));
    const init_mask = gsub.sourceFeatureMaskForTag(unicode.tag("init")).?;
    try std.testing.expectEqual(init_mask, source_features[1]);
    try std.testing.expectEqual(@as(u32, 0), source_features[3]);
}

test "Malayalam pref ligature reorders after pre-base matra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 8, 3 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 3 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.append(std.testing.allocator, .{});
    try ligatures.infos.append(std.testing.allocator, try ligatures.addLigature(std.testing.allocator, &.{ 1, 2 }));
    try ligatures.infos.append(std.testing.allocator, .{});

    const codepoints = [_]u21{ 0x0d2f, 0x0d4d, 0x0d30, 0x0d46 };
    const pref_substituted = [_]bool{ false, true, false, false };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .mlm2);
    reorderPrefGlyphs(&glyphs, &sources, &clusters, &substituted, &ligatures, &pref_substituted, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 8, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, clusters.items);
}

test "Malayalam blocked pref keeps decomposed ra after pre-base matra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 4, 3, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 3, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 3, 3 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false, true });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    const pref = try ligatures.addLigature(std.testing.allocator, &.{ 1, 2 });
    var first_component = pref;
    first_component.flags.multiplied = true;
    first_component.flags.multiple_component = 0;
    var second_component = pref;
    second_component.flags.multiplied = true;
    second_component.flags.multiple_component = 1;
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, first_component, .{}, second_component });

    const codepoints = [_]u21{ 0x0d2f, 0x0d4d, 0x0d30, 0x0d46 };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 4, 3, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
}
