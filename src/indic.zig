const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
const gsub = @import("gsub.zig");
const shaping_sections = @import("shaping_sections.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");

const rphf_feature = unicode.tag("rphf");
const pref_feature = unicode.tag("pref");
const blwf_feature = unicode.tag("blwf");
const half_feature = unicode.tag("half");
const pstf_feature = unicode.tag("pstf");
const vatu_feature = unicode.tag("vatu");
const rphf_source_mask = gsub.feature.sourceMaskForTag(rphf_feature).?;
const pref_source_mask = gsub.feature.sourceMaskForTag(pref_feature).?;
const blwf_source_mask = gsub.feature.sourceMaskForTag(blwf_feature).?;
const half_source_mask = gsub.feature.sourceMaskForTag(half_feature).?;
const pstf_source_mask = gsub.feature.sourceMaskForTag(pstf_feature).?;
const scanner_text_section = shaping_sections.isolated_hotpaths;

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .dev2, .deva, .bng2, .beng, .ory2, .orya, .gur2, .guru, .gjr3, .gjr2, .gujr, .tel2, .telu, .knd2, .knda, .tml2, .taml, .mlm2, .mlym => true,
        else => false,
    };
}

pub fn markSourceSyllables(source_syllables: []u8, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    @memset(source_syllables, 0);

    var source: usize = 0;
    var serial: u8 = 1;
    while (source < codepoints.len) {
        if (!isIndicSyllableCodepoint(codepoints[source], script_tag)) {
            source += 1;
            continue;
        }

        const syllable_start = source;
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        @memset(source_syllables[syllable_start..syllable_end], serial);
        serial +%= 1;
        if (serial == 0) serial = 1;
        source = syllable_end;
    }
}

/// Build the two source-parallel Indic maps in one syllable walk.
///
/// Both maps use identical syllable boundaries. Keeping the legacy functions
/// above as focused public helpers preserves their test surface, while the
/// production shaper avoids decoding every boundary twice.
pub fn markSourceSyllablesAndBasicFeatures(
    source_syllables: []u8,
    source_features: []u32,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    if (script_tag == .dev2) {
        return markDev2SourceSyllablesAndBasicFeatures(
            source_syllables,
            source_features,
            codepoints,
        );
    }
    return markGenericSourceSyllablesAndBasicFeatures(
        source_syllables,
        source_features,
        codepoints,
        script_tag,
    );
}

fn markGenericSourceSyllablesAndBasicFeatures(
    source_syllables: []u8,
    source_features: []u32,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    @memset(source_syllables, 0);
    @memset(source_features, 0);

    var marked = false;
    var source: usize = 0;
    var serial: u8 = 1;
    while (source < codepoints.len) {
        if (!isIndicSyllableCodepoint(codepoints[source], script_tag)) {
            source += 1;
            continue;
        }
        const syllable_start = source;
        const syllable_end = indicSyllableEnd(
            codepoints,
            syllable_start,
            script_tag,
        );
        @memset(source_syllables[syllable_start..syllable_end], serial);
        serial +%= 1;
        if (serial == 0) serial = 1;

        if (hasInitialReph(
            codepoints,
            syllable_start,
            syllable_end,
            script_tag,
        )) {
            source_features[syllable_start] |= rphf_source_mask;
            marked = true;
        }
        if (markHalfSources(
            source_features,
            codepoints,
            syllable_start,
            syllable_end,
            script_tag,
        )) marked = true;
        if (markPrefSources(
            source_features,
            codepoints,
            syllable_start,
            syllable_end,
            script_tag,
        )) marked = true;
        source = syllable_end;
    }
    return marked;
}

/// Current-generation Devanagari has a fixed category map and does not use
/// `pref` source masks. Keep its dominant source-marking pass free of the
/// all-Indic script switches while preserving the generic implementation for
/// legacy Devanagari and the other Indic shaping models.
fn markDev2SourceSyllablesAndBasicFeatures(
    source_syllables: []u8,
    source_features: []u32,
    codepoints: []const u21,
) bool {
    @memset(source_syllables, 0);
    @memset(source_features, 0);

    var marked = false;
    var source: usize = 0;
    var serial: u8 = 1;
    while (source < codepoints.len) {
        if (!isDev2SyllableCodepoint(codepoints[source])) {
            source += 1;
            continue;
        }
        const syllable_start = source;
        const syllable_end = devanagariSyllableEnd(codepoints, source);
        @memset(source_syllables[syllable_start..syllable_end], serial);
        serial +%= 1;
        if (serial == 0) serial = 1;

        if (hasDev2InitialReph(codepoints, syllable_start, syllable_end)) {
            source_features[syllable_start] |= rphf_source_mask;
            marked = true;
        }
        if (markDev2HalfSources(
            source_features,
            codepoints,
            syllable_start,
            syllable_end,
        )) marked = true;
        source = syllable_end;
    }
    return marked;
}

fn hasDev2InitialReph(
    codepoints: []const u21,
    start: usize,
    end: usize,
) bool {
    if (start + 2 >= end or
        codepoints[start] != 0x0930 or
        codepoints[start + 1] != 0x094d or
        isJoiner(codepoints[start + 2]))
    {
        return false;
    }
    for (codepoints[start + 2 .. end]) |codepoint| {
        if (isDev2Base(codepoint)) return true;
    }
    return false;
}

fn markDev2HalfSources(
    source_features: []u32,
    codepoints: []const u21,
    start: usize,
    end: usize,
) bool {
    const base = dev2HalfBaseSource(codepoints, start, end);
    var marked = false;
    var index = start;
    while (index + 1 < end) : (index += 1) {
        if (index >= base or !isDev2Consonant(codepoints[index])) continue;
        const virama = if (codepoints[index + 1] == 0x094d)
            index + 1
        else if (index + 2 < end and
            codepoints[index + 1] == 0x093c and
            codepoints[index + 2] == 0x094d)
            index + 2
        else
            continue;
        for (codepoints[virama + 1 .. end]) |codepoint| {
            if (!isDev2Consonant(codepoint)) continue;
            source_features[index] |= half_source_mask;
            marked = true;
            break;
        }
    }
    return marked;
}

fn dev2HalfBaseSource(
    codepoints: []const u21,
    start: usize,
    end: usize,
) usize {
    var has_prebase_matra = false;
    for (codepoints[start..end]) |codepoint| {
        has_prebase_matra = has_prebase_matra or codepoint == 0x093f;
    }
    var base = start;
    var index = start;
    while (index < end) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isDev2Consonant(codepoint)) continue;
        if (has_prebase_matra and index > start and
            codepoints[index - 1] == 0x094d and codepoint == 0x0930)
        {
            var previous = index - 1;
            while (previous > start) {
                previous -= 1;
                if (isDev2Consonant(codepoints[previous])) return previous;
            }
            return base;
        }
        base = index;
    }
    return base;
}

inline fn isDev2SyllableCodepoint(codepoint: u21) bool {
    const value: u32 = codepoint;
    return (value -% 0x0900 <= 0x61 and value != 0x0950) or
        value == 0x1cf5 or value == 0x25cc or value -% 0x200c <= 1;
}

inline fn isDev2Consonant(codepoint: u21) bool {
    const value: u32 = codepoint;
    return value -% 0x0915 <= 0x24 or
        value -% 0x0958 <= 0x07 or value == 0x1cf5;
}

inline fn isDev2Base(codepoint: u21) bool {
    const value: u32 = codepoint;
    return isDev2Consonant(codepoint) or
        value -% 0x0904 <= 0x10 or value -% 0x0960 <= 1 or
        value == 0x25cc;
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
    return reorderPreBaseMatrasImpl(
        false,
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        codepoints,
        &.{},
        script_tag,
    );
}

/// Modern Devanagari can reuse the syllable serials already required by GSUB
/// matching instead of rescanning all preceding source scalars for each matra.
pub noinline fn reorderDev2PreBaseMatras(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    source_syllables: []const u8,
) linksection(scanner_text_section) void {
    std.debug.assert(source_syllables.len == codepoints.len);
    return reorderPreBaseMatrasImpl(
        true,
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        codepoints,
        source_syllables,
        .dev2,
    );
}

fn reorderPreBaseMatrasImpl(
    comptime dev2: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    source_syllables: []const u8,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    var processed_source: ?usize = null;
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) : (index += 1) {
        const source_index = glyph_source_indices.items[index];
        if (source_index >= codepoints.len) continue;
        if (if (dev2)
            codepoints[source_index] != 0x093f
        else
            !isPreBaseMatra(codepoints[source_index], script_tag)) continue;
        if ((dev2 or keepsBrokenPreBaseMatraBeforeDottedCircle(script_tag)) and
            processed_source != null and processed_source.? == source_index) continue;
        processed_source = source_index;

        const following_mark_sources = followingMatraMarkSources(glyph_source_indices.items, codepoints, index, source_index, script_tag);
        const syllable_start = if (dev2)
            sourceSyllableStart(source_syllables, source_index)
        else
            indicSyllableStart(codepoints, source_index, script_tag);
        const target_info = if (dev2)
            dev2PreBaseMatraTargetGlyphIndex(
                glyph_source_indices.items,
                ligature_components,
                codepoints,
                syllable_start,
                source_index,
                index,
            )
        else
            preBaseMatraTargetGlyphIndex(glyph_source_indices.items, ligature_components, codepoints, syllable_start, source_index, index, script_tag);
        const leading_mark_start = leadingPreBaseMatraMarkStart(following_mark_sources, codepoints, script_tag);
        if (target_info.merge_from_syllable_start) {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, syllable_start, index + 1);
        } else {
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, target_info.index, index + 1);
        }
        var leading_marks_moved: usize = 0;
        if (leading_mark_start) |start| {
            var mark_slot = start;
            while (mark_slot < following_mark_sources.len) : (mark_slot += 1) {
                const mark_source = following_mark_sources[mark_slot] orelse break;
                const mark_index = glyphIndexForSource(glyph_source_indices.items, mark_source) orelse continue;
                shaping_metadata.move(
                    glyph_ids,
                    glyph_source_indices,
                    glyph_cluster_indices,
                    glyph_substituted,
                    ligature_components,
                    mark_index,
                    target_info.index + leading_marks_moved,
                );
                leading_marks_moved += 1;
            }
        }
        const matra_index = glyphIndexForSource(glyph_source_indices.items, source_index) orelse continue;
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            matra_index,
            target_info.index + leading_marks_moved,
        );
        var moved_marks: usize = 0;
        for (following_mark_sources, 0..) |maybe_mark_source, mark_slot| {
            if (leading_mark_start) |start| {
                if (mark_slot >= start) break;
            }
            const mark_source = maybe_mark_source orelse break;
            const mark_index = glyphIndexForSource(glyph_source_indices.items, mark_source) orelse continue;
            const mark_target = @min(target_info.index + leading_marks_moved + 1 + moved_marks, glyph_source_indices.items.len - 1);
            shaping_metadata.move(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                mark_index,
                mark_target,
            );
            moved_marks += 1;
        }
    }
}

fn leadingPreBaseMatraMarkStart(mark_sources: [4]?usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) ?usize {
    for (mark_sources, 0..) |maybe_source, index| {
        const source = maybe_source orelse return null;
        if (source >= codepoints.len) return null;
        if (isLeadingPreBaseMatraMark(codepoints[source], script_tag)) return index;
    }
    return null;
}

fn isLeadingPreBaseMatraMark(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dev2 and codepoint == 0x094e;
}

fn followingMatraMarkSources(glyph_sources: []const usize, codepoints: []const u21, matra_glyph_index: usize, matra_source: usize, script_tag: unicode.OpenTypeScriptTag) [4]?usize {
    var result: [4]?usize = .{ null, null, null, null };
    var count: usize = 0;
    var glyph_index = matra_glyph_index + 1;
    while (glyph_index < glyph_sources.len and count < result.len) : (glyph_index += 1) {
        const source = glyph_sources[glyph_index];
        if (source <= matra_source or source >= codepoints.len) break;
        if (!isPreBaseMatraCompanionMark(codepoints[source], script_tag)) break;
        result[count] = source;
        count += 1;
    }
    return result;
}

fn isPreBaseMatraCompanionMark(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (isLeadingPreBaseMatraMark(codepoint, script_tag)) return true;
    if (!unicode.isNonspacingMarkCodepoint(codepoint)) return false;
    return unicode.modifiedCombiningClassForShaping(codepoint) != 0;
}

fn keepsBrokenPreBaseMatraBeforeDottedCircle(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dev2 or script_tag == .deva;
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
            source_features[first_source] |= gsub.feature.sourceMaskForTag(unicode.tag("init")).?;
            marked = true;
        }
    }
    return marked;
}

/// Mark `init` candidates for modern Devanagari from the source-syllable map
/// already retained by the shaper. The first visible glyph of each serial is
/// enough to identify the moved U+093F candidate; unlike the generic routine,
/// this does not repeatedly rescan source text to recover both boundaries.
pub noinline fn markDev2InitialMatraGlyphSources(
    source_features: []u32,
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    source_syllables: []const u8,
) linksection(scanner_text_section) bool {
    std.debug.assert(source_syllables.len == codepoints.len);
    const init_mask =
        gsub.feature.sourceMaskForTag(unicode.tag("init")).?;
    var marked = false;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.len) {
        const source = glyph_source_indices[glyph_index];
        if (source >= codepoints.len) {
            glyph_index += 1;
            continue;
        }
        const syllable = source_syllables[source];
        if (syllable == 0) {
            glyph_index += 1;
            continue;
        }

        const first_glyph = glyph_index;
        glyph_index += 1;
        while (glyph_index < glyph_source_indices.len) : (glyph_index += 1) {
            const next_source = glyph_source_indices[glyph_index];
            if (next_source >= source_syllables.len or
                source_syllables[next_source] != syllable) break;
        }
        const first_source = glyph_source_indices[first_glyph];
        if (codepoints[first_source] != 0x093f) continue;
        if (first_glyph != 0) {
            const previous_source = glyph_source_indices[first_glyph - 1];
            if (previous_source < source_syllables.len and
                source_syllables[previous_source] != 0) continue;
            if (previous_source < codepoints.len and
                isIndicFormatOrNonspacingMark(codepoints[previous_source]))
            {
                continue;
            }
        }
        source_features[first_source] |= init_mask;
        marked = true;
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

/// Insert dotted circles for modern Devanagari using its fixed category map.
/// The generic routine remains the authority for every other Indic model.
pub noinline fn insertDev2DottedCirclesForBrokenClusters(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    dotted_circle_glyph: GlyphId,
) linksection(scanner_text_section) !void {
    if (dotted_circle_glyph == 0) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source_index = glyph_source_indices.items[glyph_index];
        if (source_index >= codepoints.len or
            !startsDev2BrokenCluster(codepoints, source_index)) continue;
        const insert_index = if (codepoints[source_index] == 0x093f)
            glyph_index + 1
        else
            glyph_index;
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

fn startsDev2BrokenCluster(codepoints: []const u21, source_index: usize) bool {
    if (source_index != 0 and
        isDev2SyllableCodepoint(codepoints[source_index - 1])) return false;
    if (source_index != 0 and codepoints[source_index - 1] == 0x25cc) {
        return false;
    }
    if (isDev2Base(codepoints[source_index])) return false;
    const syllable_end = devanagariSyllableEnd(codepoints, source_index);
    if (syllable_end <= source_index) return false;
    if (codepoints[source_index] == 0x094d) return true;
    for (codepoints[source_index..syllable_end]) |codepoint| {
        if (isDev2Consonant(codepoint)) return false;
    }
    return true;
}

/// Modern Devanagari has only U+25CC as an Indic placeholder base.
pub noinline fn mergeDev2PlaceholderDependentMarks(
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    codepoints: []const u21,
) linksection(scanner_text_section) void {
    for (glyph_source_indices.items, 0..) |source, glyph_index| {
        if (source == 0 or source >= codepoints.len) continue;
        const codepoint: u32 = codepoints[source];
        if (!(codepoint -% 0x0900 <= 3 or
            codepoint == 0x093c or
            codepoint -% 0x093e <= 0x11 or
            codepoint -% 0x0951 <= 6 or
            codepoint -% 0x0962 <= 1)) continue;
        const previous = source - 1;
        if (codepoints[previous] != 0x25cc) continue;
        const previous_glyph =
            glyphIndexForSource(glyph_source_indices.items, previous) orelse
            continue;
        shaping_metadata.mergeMonotoneClusters(
            glyph_cluster_indices.items,
            @min(previous_glyph, glyph_index),
            @max(previous_glyph, glyph_index) + 1,
        );
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

pub fn mergeMalayalamDotRephBrokenCluster(glyph_cluster_indices: *std.ArrayList(usize), glyph_source_indices: *std.ArrayList(usize), codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    if (script_tag != .mlm2 and script_tag != .mlym) return;
    if (codepoints.len < 3 or codepoints[0] != 0x0d4e or codepoints[1] != viramaCodepoint(script_tag) or codepoints[2] != 0x200d) return;

    const first_glyph = glyphIndexForSource(glyph_source_indices.items, 0) orelse return;
    const last_glyph = glyphIndexForSource(glyph_source_indices.items, 2) orelse return;
    shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, @min(first_glyph, last_glyph), @max(first_glyph, last_glyph) + 1);
}

test "Malayalam dot reph broken cluster merges inserted dotted circle" {
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 3, 6 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 1, 2 });
    const codepoints = [_]u21{ 0x0d4e, 0x0d4d, 0x200d };

    mergeMalayalamDotRephBrokenCluster(&clusters, &sources, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
}

pub fn mergeTrailingDependentMarks(glyph_cluster_indices: *std.ArrayList(usize), glyph_source_indices: *std.ArrayList(usize), codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    if (script_tag != .ory2 and script_tag != .orya and
        script_tag != .gur2 and script_tag != .guru and
        script_tag != .knd2 and script_tag != .knda and
        script_tag != .mlm2 and script_tag != .mlym) return;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source == 0 or source >= codepoints.len) continue;
        if (!isIndicDependentMark(codepoints[source], script_tag)) continue;
        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        if (syllable_start >= source) continue;
        const first_source = if ((script_tag == .ory2 or script_tag == .orya) and codepoints[source - 1] == 0x200c)
            source - 1
        else
            syllable_start;
        const first_glyph = firstGlyphInSourceRange(glyph_source_indices.items, first_source, source) orelse continue;
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, first_glyph, glyph_index + 1);
    }
}

pub fn mergeKannadaOldSpecTrailingBlwf(glyph_cluster_indices: *std.ArrayList(usize), glyph_source_indices: *std.ArrayList(usize), codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    if (script_tag != .knda) return;
    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source < 2 or source >= codepoints.len) continue;
        if (!isIndicConsonant(codepoints[source], script_tag)) continue;
        if (source + 1 >= codepoints.len or codepoints[source + 1] != viramaCodepoint(script_tag)) continue;
        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        if (syllable_start >= source) continue;
        const first_glyph = firstGlyphInSourceRange(glyph_source_indices.items, syllable_start, source) orelse continue;
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, first_glyph, glyph_index + 1);
    }
}

pub fn normalizeOldSpecDevanagariHalantOrder(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .deva) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source == 0 or source >= codepoints.len) continue;
        if (codepoints[source] != viramaCodepoint(script_tag)) continue;
        if (!isIndicConsonant(codepoints[source - 1], script_tag)) continue;
        if (codepoints[source - 1] == rephRaCodepoint(script_tag)) continue;

        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        if (source < syllable_start or source >= syllable_end) continue;

        var target_source: ?usize = null;
        var cursor = source + 1;
        while (cursor < syllable_end) : (cursor += 1) {
            if (isIndicConsonant(codepoints[cursor], script_tag)) target_source = cursor;
        }
        const target = target_source orelse continue;
        const target_glyph = glyphIndexForSource(glyph_source_indices.items, target) orelse continue;
        if (target_glyph <= glyph_index) continue;

        mergeOldSpecPostBaseHalantCluster(glyph_cluster_indices.items, glyph_source_indices.items, codepoints, syllable_start, target, script_tag);
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, glyph_index, target_glyph + 1);
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            target_glyph,
        );
        glyph_index = target_glyph;
    }
}

pub fn normalizeOldSpecPostBaseHalantOrder(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (!usesOldSpecPostBaseHalantMove(script_tag)) return;

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source == 0 or source >= codepoints.len) continue;
        if (codepoints[source] != viramaCodepoint(script_tag)) continue;
        if (!isIndicConsonant(codepoints[source - 1], script_tag)) continue;

        const syllable_start = indicSyllableStart(codepoints, source, script_tag);
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        if (source < syllable_start or source >= syllable_end) continue;

        var target_source: ?usize = null;
        var cursor = source + 1;
        while (cursor < syllable_end) : (cursor += 1) {
            if (isOldSpecPostBaseHalantMoveTarget(codepoints[cursor], script_tag)) target_source = cursor;
        }
        const target = target_source orelse continue;
        const target_glyph = glyphIndexForSource(glyph_source_indices.items, target) orelse continue;
        if (target_glyph <= glyph_index) continue;

        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, glyph_index, target_glyph + 1);
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            target_glyph,
        );
        glyph_index = target_glyph;
        break;
    }
}

pub fn mergeMalayalamOldSpecTrailingViramaClusters(glyph_cluster_indices: *std.ArrayList(usize), glyph_source_indices: *std.ArrayList(usize), ligature_components: *const ligature_provenance.Store, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    if (script_tag != .mlm2 and script_tag != .mlym) return;
    var glyph_index: usize = 1;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= codepoints.len or codepoints[source] != viramaCodepoint(script_tag)) continue;
        const previous = glyph_index - 1;
        if (previous >= ligature_components.infos.items.len) continue;
        const info = ligature_components.infos.items[previous];
        if (!info.isLigature()) continue;
        const sources = ligature_components.componentSources(info) orelse continue;
        if (sources.len == 0) continue;
        const syllable_start = indicSyllableStart(codepoints, sources[0], script_tag);
        const syllable_end = indicSyllableEnd(codepoints, syllable_start, script_tag);
        if (source < syllable_start or source >= syllable_end) continue;
        if (previous < glyph_cluster_indices.items.len and glyph_index < glyph_cluster_indices.items.len) {
            glyph_cluster_indices.items[glyph_index] = glyph_cluster_indices.items[previous];
        }
    }
}

fn mergeOldSpecPostBaseHalantCluster(clusters: []usize, sources: []const usize, codepoints: []const u21, syllable_start: usize, target_source: usize, script_tag: unicode.OpenTypeScriptTag) void {
    var source_end = target_source + 1;
    while (source_end < codepoints.len and codepoints[source_end] == viramaCodepoint(script_tag)) {
        source_end += 1;
    }
    const first_glyph = firstGlyphInSourceRange(sources, syllable_start, source_end) orelse return;
    var last_glyph = first_glyph;
    for (sources, 0..) |source, glyph_index| {
        if (source < syllable_start or source >= source_end) continue;
        last_glyph = @max(last_glyph, glyph_index);
    }
    shaping_metadata.mergeMonotoneClusters(clusters, first_glyph, last_glyph + 1);
}

fn usesOldSpecPostBaseHalantMove(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .mlym, .beng, .deva => true,
        else => false,
    };
}

fn isOldSpecPostBaseHalantMoveTarget(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .deva => codepoint == 0x0930,
        .beng => codepoint == 0x09af,
        .mlym, .mlm2 => isIndicConsonant(codepoint, script_tag),
        else => false,
    };
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

test "combined Indic source maps match independent builders" {
    const codepoints = [_]u21{
        0x0915, 0x094d, 0x0937, 0x093f, ' ',
        0x0930, 0x094d, 0x0915, 0x093e,
    };
    var expected_syllables: [codepoints.len]u8 = undefined;
    markSourceSyllables(&expected_syllables, &codepoints, .dev2);
    var expected_features: [codepoints.len]u32 = undefined;
    const expected_marked = markBasicSourceFeatures(
        &expected_features,
        &codepoints,
        .dev2,
    );

    var syllables: [codepoints.len]u8 = undefined;
    var features: [codepoints.len]u32 = undefined;
    const marked = markSourceSyllablesAndBasicFeatures(
        &syllables,
        &features,
        &codepoints,
        .dev2,
    );
    try std.testing.expectEqual(expected_marked, marked);
    try std.testing.expectEqualSlices(u8, &expected_syllables, &syllables);
    try std.testing.expectEqualSlices(u32, &expected_features, &features);
}

test "specialized dev2 source maps match generic marking" {
    const representatives = [_]u21{
        0x0915, 0x0930, 0x093f, 0x094d, 0x093c, 0x0958,
        0x0960, 0x1cf5, 0x200c, 0x200d, 0x25cc, ' ',
    };
    for (representatives) |first| {
        for (representatives) |second| {
            for (representatives) |third| {
                const codepoints = [_]u21{ first, second, third };
                var expected_syllables: [codepoints.len]u8 = undefined;
                var expected_features: [codepoints.len]u32 = undefined;
                const expected_marked = markGenericSourceSyllablesAndBasicFeatures(
                    &expected_syllables,
                    &expected_features,
                    &codepoints,
                    .dev2,
                );
                var actual_syllables: [codepoints.len]u8 = undefined;
                var actual_features: [codepoints.len]u32 = undefined;
                const actual_marked = markDev2SourceSyllablesAndBasicFeatures(
                    &actual_syllables,
                    &actual_features,
                    &codepoints,
                );
                try std.testing.expectEqual(expected_marked, actual_marked);
                try std.testing.expectEqualSlices(u8, &expected_syllables, &actual_syllables);
                try std.testing.expectEqualSlices(u32, &expected_features, &actual_features);
            }
        }
    }
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

/// Reorder modern Devanagari rephs using the source-syllable map already built
/// for staged GSUB. The generic path has to rediscover syllable boundaries and
/// dispatch character categories across every supported Indic script; `dev2`
/// has fixed scalar ranges and a stable non-zero syllable serial.
pub noinline fn reorderDev2Rephs(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    source_syllables: []const u8,
) linksection(scanner_text_section) void {
    std.debug.assert(source_syllables.len == codepoints.len);
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) {
        const source_index = glyph_source_indices.items[index];
        if (!isFormedReph(
            ligature_components,
            ligature_components.infos.items[index],
            source_index,
            codepoints,
            .dev2,
        )) {
            index += 1;
            continue;
        }

        const syllable = source_syllables[source_index];
        if (syllable == 0) {
            index += 1;
            continue;
        }
        var syllable_end = source_index + 1;
        while (syllable_end < source_syllables.len and
            source_syllables[syllable_end] == syllable)
        {
            syllable_end += 1;
        }
        const target = dev2RephTargetGlyphIndex(
            glyph_source_indices.items,
            codepoints,
            source_index,
            syllable_end,
            index,
        );
        shaping_metadata.mergeMonotoneClusters(
            glyph_cluster_indices.items,
            @min(index, target),
            @max(index, target) + 1,
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

pub fn reorderLogicalRepha(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .mlm2 and script_tag != .mlym) return;
    if (codepoints.len < 2 or codepoints[0] != 0x0d4e) return;

    const repha_glyph = glyphIndexForSource(glyph_source_indices.items, 0) orelse return;
    const syllable_end = if (codepoints.len > 1)
        indicSyllableEnd(codepoints, 1, script_tag)
    else
        1;
    const target = logicalRephaTargetGlyph(glyph_source_indices.items, codepoints, syllable_end, script_tag) orelse return;
    if (target <= repha_glyph) return;
    shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, repha_glyph, target + 1);
    shaping_metadata.move(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        repha_glyph,
        target,
    );
}

fn logicalRephaTargetGlyph(sources: []const usize, codepoints: []const u21, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    var target: ?usize = null;
    for (sources, 0..) |source, glyph_index| {
        if (source == 0 or source >= syllable_end or source >= codepoints.len) continue;
        if (isIndicBase(codepoints[source], script_tag)) target = glyph_index;
        if (codepoints[source] == viramaCodepoint(script_tag) and
            source > 0 and
            isIndicConsonant(codepoints[source - 1], script_tag) and
            target != null)
        {
            target = glyph_index;
        }
    }
    return target;
}

/// Performs the Kannada part of Indic's initial positional sort.
///
/// Kannada assigns several dependent vowels, including U+0CBE, the
/// `BEFORE_SUB` position. They therefore have to move in front of a below-base
/// `virama + consonant` pair before `blwf` runs. Moving the same glyph after
/// basic GSUB is too late: the intervening vowel can participate in contextual
/// lookup filtering, and the unformed consonant will subsequently fall through
/// to `haln`.
pub fn reorderInitialKannadaVowels(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .knd2 and script_tag != .knda) return;
    reorderBeforeSubscriptVowelsImpl(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        codepoints,
        script_tag,
    );
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
    reorderBeforeSubscriptVowelsImpl(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        codepoints,
        script_tag,
    );
}

fn reorderBeforeSubscriptVowelsImpl(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
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
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        if (source < syllable_start or source >= vowel_source) continue;
        if (source + 1 >= codepoints.len) continue;
        if (codepoints[source] != viramaCodepoint(script_tag)) continue;
        if (!isIndicConsonant(codepoints[source + 1], script_tag)) continue;
        // BEFORE_SUB precedes the whole run of below-base consonants, not
        // merely the final pair. Returning the first pair also mirrors the
        // stable positional sort when a syllable has several conjunct links.
        return glyph_index;
    }
    return null;
}

fn firstGlyphInSourceRange(sources: []const usize, start_source: usize, end_source: usize) ?usize {
    for (sources, 0..) |source, glyph_index| {
        if (source >= start_source and source <= end_source) return glyph_index;
    }
    return null;
}

pub fn reorderGujaratiSplitMatraComponents(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .gjr3 and script_tag != .gjr2 and script_tag != .gujr) return;

    var glyph_index: usize = 0;
    while (glyph_index + 1 < glyph_source_indices.items.len) : (glyph_index += 1) {
        const first_source = glyph_source_indices.items[glyph_index];
        const second_source = glyph_source_indices.items[glyph_index + 1];
        if (first_source >= codepoints.len or second_source >= codepoints.len) continue;
        if (codepoints[first_source] != 0x0abe) continue;
        if (codepoints[second_source] != 0x0ac5 and codepoints[second_source] != 0x0ac8) continue;
        if (indicSyllableStart(codepoints, first_source, script_tag) != indicSyllableStart(codepoints, second_source, script_tag)) continue;

        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, glyph_index, glyph_index + 2);
        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            glyph_index + 1,
        );
        glyph_index += 1;
    }
}

pub fn reorderBengaliBelowVowelsAfterBase(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .bng2 and script_tag != .beng) return;

    mergeBengaliSplitMatraBelowVowelClusters(glyph_cluster_indices, glyph_source_indices.items, codepoints, script_tag);

    var glyph_index: usize = 0;
    while (glyph_index < glyph_source_indices.items.len) : (glyph_index += 1) {
        const source = glyph_source_indices.items[glyph_index];
        if (source >= codepoints.len or !isBengaliBelowVowel(codepoints[source])) continue;
        const base_source = previousBengaliBaseSource(codepoints, source, script_tag) orelse continue;
        const matra_source = previousBengaliSplitPreBaseMatraSource(codepoints, base_source, source) orelse continue;
        const base_glyph = glyphIndexForSource(glyph_source_indices.items, base_source) orelse continue;
        {
            const target_cluster = if (hasBengaliSplitPostMatraAfter(codepoints, source, bengaliMatraClusterSearchEnd(codepoints, source + 1, script_tag)))
                base_source
            else
                matra_source;
            if (glyph_index < glyph_cluster_indices.items.len) glyph_cluster_indices.items[glyph_index] = target_cluster;
            if (bengaliSplitPostMatraGlyph(glyph_source_indices.items, base_glyph, matra_source)) |post_glyph| {
                if (post_glyph < glyph_cluster_indices.items.len) glyph_cluster_indices.items[post_glyph] = target_cluster;
            }
        }
        const target = if (glyph_index < base_glyph) base_glyph else @min(base_glyph + 1, glyph_source_indices.items.len - 1);
        if (target == glyph_index) continue;

        shaping_metadata.move(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            target,
        );
        glyph_index = @min(target, glyph_source_indices.items.len - 1);
    }
}

fn mergeBengaliSplitMatraBelowVowelClusters(glyph_cluster_indices: *std.ArrayList(usize), sources: []const usize, codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) void {
    var base_source: usize = 0;
    while (base_source < codepoints.len) : (base_source += 1) {
        if (!isIndicBase(codepoints[base_source], script_tag)) continue;
        const base_glyph = glyphIndexForSource(sources, base_source) orelse continue;
        const search_end = bengaliMatraClusterSearchEnd(codepoints, base_source + 1, script_tag);
        var matra_source = base_source + 1;
        while (matra_source < search_end) : (matra_source += 1) {
            if (!isBengaliSplitPreBaseMatra(codepoints[matra_source])) continue;
            const below_source = firstBengaliBelowVowelAfter(codepoints, matra_source, search_end) orelse continue;
            if (!hasBengaliSplitPostMatraAfter(codepoints, below_source, search_end)) continue;
            mergeBengaliSourceGlyphClustersAfterBase(glyph_cluster_indices, sources, base_glyph, matra_source, base_source);
            mergeBengaliSourceGlyphClustersAfterBase(glyph_cluster_indices, sources, base_glyph, below_source, base_source);
        }
    }
}

fn mergeBengaliSourceGlyphClustersAfterBase(glyph_cluster_indices: *std.ArrayList(usize), sources: []const usize, base_glyph: usize, source: usize, cluster_source: usize) void {
    var glyph_index = base_glyph + 1;
    while (glyph_index < sources.len and glyph_index < glyph_cluster_indices.items.len) : (glyph_index += 1) {
        if (sources[glyph_index] == source) glyph_cluster_indices.items[glyph_index] = cluster_source;
    }
}

fn firstBengaliBelowVowelAfter(codepoints: []const u21, source: usize, search_end: usize) ?usize {
    var index = source + 1;
    while (index < search_end and index < codepoints.len) : (index += 1) {
        if (isBengaliBelowVowel(codepoints[index])) return index;
    }
    return null;
}

fn previousBengaliBaseSource(codepoints: []const u21, before_source: usize, script_tag: unicode.OpenTypeScriptTag) ?usize {
    var source = before_source;
    while (source > 0) {
        source -= 1;
        if (isIndicBase(codepoints[source], script_tag)) return source;
    }
    return null;
}

fn previousBengaliSplitPreBaseMatraSource(codepoints: []const u21, base_source: usize, before_source: usize) ?usize {
    var source = before_source;
    while (source > base_source + 1) {
        source -= 1;
        if (isBengaliSplitPreBaseMatra(codepoints[source])) return source;
    }
    return null;
}

fn bengaliSplitPostMatraGlyph(sources: []const usize, base_glyph: usize, matra_source: usize) ?usize {
    var glyph_index = base_glyph + 1;
    while (glyph_index < sources.len) : (glyph_index += 1) {
        if (sources[glyph_index] == matra_source) return glyph_index;
    }
    return null;
}

fn hasBengaliSplitPostMatraAfter(codepoints: []const u21, source: usize, syllable_end: usize) bool {
    var index = source + 1;
    while (index < syllable_end and index < codepoints.len) : (index += 1) {
        if (isBengaliSplitPostMatraComponent(codepoints[index])) return true;
    }
    return false;
}

fn bengaliMatraClusterSearchEnd(codepoints: []const u21, start: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    var index = start;
    while (index < codepoints.len) : (index += 1) {
        if (isIndicBase(codepoints[index], script_tag)) return index;
    }
    return codepoints.len;
}

fn isBengaliBelowVowel(codepoint: u21) bool {
    return codepoint >= 0x09c1 and codepoint <= 0x09c4;
}

fn isBengaliSplitPreBaseMatra(codepoint: u21) bool {
    return codepoint == 0x09c7 or codepoint == 0x09c8 or codepoint == 0x09cb or codepoint == 0x09cc;
}

fn isBengaliSplitPostMatraComponent(codepoint: u21) bool {
    return codepoint == 0x09be or codepoint == 0x09d7;
}

test "Bengali below vowel after split matra reorders after base" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 9, 2, 4, 5 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 1, 0, 1, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 3, 6 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x099b, 0x09cb, 0x09c2 };
    reorderBengaliBelowVowelsAfterBase(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .bng2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 2, 5, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 2, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1, 1 }, clusters.items);
}

test "Bengali below vowel before split post component inherits base cluster" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 9, 2, 4, 5, 4 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 1, 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 3, 6, 9 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x099b, 0x09c7, 0x09c2, 0x09cb };
    reorderBengaliBelowVowelsAfterBase(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .bng2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 2, 5, 4, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 2, 1, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 1, 1, 9 }, clusters.items);
}

test "Old-spec Bengali half-form virama stays before base consonant" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 5, 2 });

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

    const codepoints = [_]u21{ 0x0995, 0x09cd, 0x0995 };
    normalizeOldSpecPostBaseHalantOrder(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .beng);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 5, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, sources.items);
}

test "Old-spec Devanagari post-base ra target moves preceding virama" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 7, 4, 6, 4 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 6, 6 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x091f, 0x094d, 0x0930, 0x094d };
    normalizeOldSpecPostBaseHalantOrder(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .deva);

    try std.testing.expectEqualSlices(GlyphId, &.{ 7, 6, 4, 4 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1, 3 }, sources.items);
}

test "Modern Malayalam keeps virama before stacker consonant" {
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

    const codepoints = [_]u21{ 0x0d15, 0x0d4d, 0x0d2f };
    normalizeOldSpecPostBaseHalantOrder(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, sources.items);
}

const pre_reorder_feature_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true },
};

const basic_feature_applications_without_reph = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true },
    .{ .tag = blwf_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = half_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = pstf_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = vatu_feature, .match_source_syllable = true },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true },
};

const basic_feature_applications_with_reph = [_]gsub.feature.Application{
    .{ .tag = rphf_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true },
    .{ .tag = blwf_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = half_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = pstf_feature, .source_scoped = true, .match_source_syllable = true },
    .{ .tag = vatu_feature, .match_source_syllable = true },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true },
};

const pre_reph_feature_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("pres"), .match_source_syllable = true },
};

const pref_feature_applications = [_]gsub.feature.Application{
    .{ .tag = pref_feature, .source_scoped = true, .match_source_syllable = true },
};

const final_feature_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("init"), .source_scoped = true, .match_source_syllable = true },
    .{ .tag = unicode.tag("abvs"), .match_source_syllable = true },
    .{ .tag = unicode.tag("blws"), .match_source_syllable = true },
    .{ .tag = unicode.tag("psts"), .match_source_syllable = true },
    .{ .tag = unicode.tag("haln"), .match_source_syllable = true },
};

pub fn preReorderFeatureApplications() []const gsub.feature.Application {
    return &pre_reorder_feature_applications;
}

pub fn basicFeatureApplications(has_initial_reph: bool) []const gsub.feature.Application {
    return if (has_initial_reph)
        &basic_feature_applications_with_reph
    else
        &basic_feature_applications_without_reph;
}

pub fn preRephFeatureApplications() []const gsub.feature.Application {
    return &pre_reph_feature_applications;
}

pub fn prefFeatureApplications() []const gsub.feature.Application {
    return &pref_feature_applications;
}

pub fn finalFeatureApplications() []const gsub.feature.Application {
    return &final_feature_applications;
}

fn isPreBaseMatra(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => codepoint == 0x09bf or codepoint == 0x09c7 or codepoint == 0x09c8,
        .ory2, .orya => codepoint == 0x0b47 or codepoint == 0x0b48,
        .gur2, .guru => codepoint == 0x0a3f,
        .gjr3, .gjr2, .gujr => codepoint == 0x0abf,
        .tel2, .telu => codepoint == 0x0c46 or codepoint == 0x0c47 or codepoint == 0x0c48,
        // Kannada U+0CBF is BEFORE_SUB, not PRE_M. It remains after a
        // standalone base so `abvs` can consume base+matra, but the initial
        // Kannada reorder moves it ahead of a following below-base pair.
        .knd2, .knda => false,
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

pub fn normalizeOldSpecBengaliRaViramaOrder(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) void {
    if (script_tag != .beng) return;

    var glyph_index: usize = 0;
    while (glyph_index + 1 < glyph_source_indices.items.len) : (glyph_index += 1) {
        const first_source = glyph_source_indices.items[glyph_index];
        const second_source = glyph_source_indices.items[glyph_index + 1];
        if (first_source >= codepoints.len or second_source >= codepoints.len) continue;
        if (codepoints[first_source] != viramaCodepoint(script_tag)) continue;
        if (codepoints[second_source] != rephRaCodepoint(script_tag)) continue;
        if (indicSyllableStart(codepoints, first_source, script_tag) != indicSyllableStart(codepoints, second_source, script_tag)) continue;

        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, glyph_index, glyph_index + 2);
        shaping_metadata.swap(
            glyph_ids.items,
            glyph_source_indices.items,
            glyph_cluster_indices.items,
            glyph_substituted.items,
            ligature_components.infos.items,
            glyph_index,
            glyph_index + 1,
        );
        glyph_index += 1;
    }
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
    if (isIndicBase(codepoints[source_index], script_tag)) return false;
    const syllable_end = indicSyllableEnd(codepoints, source_index, script_tag);
    if (syllable_end <= source_index) return false;
    if (codepoints[source_index] == viramaCodepoint(script_tag)) return true;
    return !hasConsonant(codepoints[source_index..syllable_end], script_tag);
}

fn hasInitialReph(codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (syllable_start + 2 >= syllable_end) return false;
    if (codepoints[syllable_start] != rephRaCodepoint(script_tag) or codepoints[syllable_start + 1] != viramaCodepoint(script_tag)) return false;
    if (isJoiner(codepoints[syllable_start + 2])) return false;
    return hasConsonantLikeBase(codepoints[syllable_start + 2 .. syllable_end], script_tag);
}

fn markHalfSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    var marked = false;
    if (script_tag == .tel2 or script_tag == .telu) {
        if (markPostBaseViramaConsonantSources(source_features, codepoints, syllable_start, syllable_end, script_tag, blwf_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .gur2 or script_tag == .guru) {
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
    if (script_tag == .bng2 or script_tag == .beng) {
        if (script_tag == .beng) {
            if (markPreBaseConsonantViramaSources(source_features, codepoints, syllable_start, syllable_end, script_tag, half_source_mask)) {
                marked = true;
            }
            if (markOldSpecBengaliPostBaseRaSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
                marked = true;
            }
        } else {
            if (markPostBaseViramaConsonantSources(source_features, codepoints, syllable_start, syllable_end, script_tag, pstf_source_mask)) {
                marked = true;
            }
        }
        return marked;
    }
    if (script_tag == .tml2 or script_tag == .taml) {
        if (markPreBaseConsonantViramaSources(source_features, codepoints, syllable_start, syllable_end, script_tag, half_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .gjr3 or script_tag == .gjr2 or script_tag == .gujr) {
        if (markPreBaseConsonantViramaSources(source_features, codepoints, syllable_start, syllable_end, script_tag, half_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .knd2 or script_tag == .knda) {
        if (markKannadaRaHalfSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
            marked = true;
        }
        // Kannada exposes below-base forms only to post-base sources. The
        // virama is still the logical lookup start after initial reordering,
        // even when a BEFORE_SUB vowel moves between the base and this pair.
        if (markPostBaseViramaConsonantSources(source_features, codepoints, syllable_start, syllable_end, script_tag, blwf_source_mask)) {
            marked = true;
        }
        if (script_tag == .knda and markPreBaseConsonantViramaSources(source_features, codepoints, syllable_start + 1, syllable_end, script_tag, blwf_source_mask)) {
            marked = true;
        }
        return marked;
    }
    if (script_tag == .deva) {
        if (markOldSpecDevanagariRaViramaSources(source_features, codepoints, syllable_start, syllable_end, script_tag)) {
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

fn markOldSpecBengaliPostBaseRaSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (script_tag != .beng) return false;
    var marked = false;
    var index = syllable_start;
    while (index + 1 < syllable_end) : (index += 1) {
        if (codepoints[index] != viramaCodepoint(script_tag)) continue;
        if (codepoints[index + 1] != rephRaCodepoint(script_tag)) continue;
        source_features[index + 1] |= blwf_source_mask;
        marked = true;
    }
    return marked;
}

fn markOldSpecDevanagariRaViramaSources(source_features: []u32, codepoints: []const u21, syllable_start: usize, syllable_end: usize, script_tag: unicode.OpenTypeScriptTag) bool {
    if (script_tag != .deva) return false;
    var marked = false;
    var index = syllable_start + 1;
    while (index < syllable_end) : (index += 1) {
        if (codepoints[index] != rephRaCodepoint(script_tag)) continue;
        if (codepoints[index - 1] != viramaCodepoint(script_tag)) continue;
        if (index + 2 < syllable_end and
            codepoints[index + 1] == viramaCodepoint(script_tag) and
            codepoints[index + 2] == 0x200d) continue;
        source_features[index] |= blwf_source_mask;
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

/// Whether the Indic shaper must remember exactly which source was substituted
/// by the `pref` stage for subsequent glyph reordering. Modern and legacy
/// Malayalam need that provenance; other Indic scripts execute `pref` but do
/// not consume its per-source result.
pub fn tracksPrefSubstitutions(
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    return usesPrefSources(script_tag);
}

test "only Malayalam tracks pref substitution provenance" {
    try std.testing.expect(tracksPrefSubstitutions(.mlm2));
    try std.testing.expect(tracksPrefSubstitutions(.mlym));
    try std.testing.expect(!tracksPrefSubstitutions(.dev2));
    try std.testing.expect(!tracksPrefSubstitutions(.bng2));
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

// This scanner is shared by source marking and several reorder stages. Keep
// one out-of-line copy: duplicating the script-dependent property dispatch in
// each caller increases the already-large shaping frame and instruction-cache
// footprint, while the call boundary is amortized across a complete syllable.
noinline fn indicSyllableEnd(codepoints: []const u21, start: usize, script_tag: unicode.OpenTypeScriptTag) linksection(scanner_text_section) usize {
    if (script_tag == .dev2 or script_tag == .deva) {
        return devanagariSyllableEnd(codepoints, start);
    }
    return genericIndicSyllableEnd(codepoints, start, script_tag);
}

// Keep the all-script implementation as a distinct copy with the same body as
// the former scanner. The dispatcher and Devanagari specialization live in a
// separate section, so adding the fast path does not shift unrelated `.text`
// functions used by Latin and Arabic shaping.
noinline fn genericIndicSyllableEnd(codepoints: []const u21, start: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    const virama = viramaCodepoint(script_tag);
    var index = start;
    var saw_virama = false;
    while (index < codepoints.len) : (index += 1) {
        const codepoint = codepoints[index];
        const is_base = isIndicBase(codepoint, script_tag);
        const is_dependent_mark = isIndicDependentMark(codepoint, script_tag);
        const is_joiner = codepoint == 0x200c or codepoint == 0x200d;
        if (!(is_base or is_dependent_mark or codepoint == virama or is_joiner)) break;
        if (index != start and is_base and !saw_virama and !isConsonantWithStacker(codepoints[index - 1], script_tag)) break;
        if (saw_virama and codepoint == 0x200c) return index + 1;

        saw_virama = if (codepoint == virama)
            true
        else if (saw_virama and is_joiner)
            true
        else if (is_dependent_mark)
            saw_virama
        else
            false;
    }
    return index;
}

noinline fn devanagariSyllableEnd(codepoints: []const u21, start: usize) linksection(scanner_text_section) usize {
    if (start >= codepoints.len) return start;

    // The first accepted scalar always starts a syllable; only later bases
    // need the virama/stacker continuation test. Seed the two state bits once
    // here so the main loop does not carry `index != start` as a counter.
    const first: u32 = codepoints[start];
    var saw_virama = false;
    var previous_was_stacker = false;
    if (first -% 0x0900 <= 0x61) {
        if (first == 0x0950) return start;
        saw_virama = first == 0x094d;
    } else if (first == 0x1cf5) {
        previous_was_stacker = true;
    } else if (first != 0x25cc and first -% 0x200c > 1) {
        return start;
    }

    var index = start + 1;
    while (index < codepoints.len) : (index += 1) {
        const codepoint: u32 = codepoints[index];
        if (codepoint -% 0x0900 <= 0x61) {
            // U+0900..U+0961 is contiguous shaping input except U+0950.
            // The primary base range carries virtually every consonant and
            // independent vowel. Exit through it before testing the virama or
            // rare U+0958..U+0961 bases, so ordinary syllable boundaries and
            // conjunct continuations do not materialize all three predicates.
            if (codepoint == 0x0950) break;
            if (codepoint -% 0x0904 <= 0x35) {
                if (!saw_virama and !previous_was_stacker) break;
                saw_virama = false;
                previous_was_stacker = false;
                continue;
            }
            if (codepoint == 0x094d) {
                saw_virama = true;
                previous_was_stacker = false;
                continue;
            }
            if (codepoint -% 0x0958 <= 0x09) {
                if (!saw_virama and !previous_was_stacker) break;
                saw_virama = false;
                previous_was_stacker = false;
                continue;
            }
            // Dependent marks preserve virama continuation but are no longer
            // immediately after a consonant-with-stacker source.
            previous_was_stacker = false;
            continue;
        }
        if (codepoint == 0x1cf5) {
            if (!saw_virama and !previous_was_stacker) break;
            saw_virama = false;
            previous_was_stacker = true;
            continue;
        }
        if (codepoint == 0x25cc) {
            if (!saw_virama and !previous_was_stacker) break;
            saw_virama = false;
            previous_was_stacker = false;
            continue;
        }
        if (codepoint -% 0x200c <= 1) {
            if (saw_virama and codepoint == 0x200c) return index + 1;
            previous_was_stacker = false;
            continue;
        }
        break;
    }
    return index;
}

test "specialized Devanagari scanner properties match generic predicates for every Unicode scalar" {
    // Compare the compact arithmetic itself, not only a one-scalar scan:
    // several accepted categories have the same end position in isolation.
    // The multi-scalar differential below separately exercises state
    // transitions such as virama+joiner and stacker handling.
    for (0..0x110000) |value| {
        const codepoint: u21 = @intCast(value);
        const widened: u32 = codepoint;
        const specialized_base = widened -% 0x0904 <= 0x35 or
            widened -% 0x0958 <= 0x09 or
            widened == 0x1cf5 or
            widened == 0x25cc;
        const specialized_virama = widened == 0x094d;
        const specialized_mark = widened -% 0x0900 <= 0x61 and
            widened != 0x0950 and
            !specialized_base and
            !specialized_virama;
        const specialized_joiner = widened -% 0x200c <= 1;

        try std.testing.expectEqual(isIndicBase(codepoint, .dev2), specialized_base);
        try std.testing.expectEqual(isIndicBase(codepoint, .deva), specialized_base);
        try std.testing.expectEqual(isIndicDependentMark(codepoint, .dev2), specialized_mark);
        try std.testing.expectEqual(isIndicDependentMark(codepoint, .deva), specialized_mark);
        try std.testing.expectEqual(codepoint == viramaCodepoint(.dev2), specialized_virama);
        try std.testing.expectEqual(isJoiner(codepoint), specialized_joiner);
    }
}

test "one-pass Indic syllable scan matches former property traversal" {
    const scripts = [_]unicode.OpenTypeScriptTag{
        .dev2, .deva,
        .bng2, .beng,
        .ory2, .orya,
        .gur2, .guru,
        .gjr3, .gjr2,
        .gujr, .tel2,
        .telu, .knd2,
        .knda, .tml2,
        .taml, .mlm2,
        .mlym,
    };
    const representatives = [_]u21{
        0x0915, 0x094d, 0x093e, 0x1cf5, // Devanagari base/virama/mark/stacker.
        0x0995, 0x09cd, 0x09be, // Bengali.
        0x0a15, 0x0a4d, 0x0a3e, // Gurmukhi.
        0x0a95, 0x0acd, 0x0abe, // Gujarati.
        0x0b15, 0x0b4d, 0x0b3e, // Odia.
        0x0b95, 0x0bcd, 0x0bbe, // Tamil.
        0x0c15, 0x0c4d, 0x0c3e, // Telugu.
        0x0c95, 0x0ccd, 0x0cbe, 0x0cf1, // Kannada, including stacker.
        0x0d15, 0x0d4d, 0x0d3e, // Malayalam.
        0x200c, 0x200d, 0x25cc, ' ', // Joiners, placeholder, and boundary.
    };

    for (scripts) |script_tag| {
        for (representatives) |first| {
            for (representatives) |second| {
                for (representatives) |third| {
                    const codepoints = [_]u21{ first, second, third };
                    for (0..codepoints.len + 1) |start| {
                        try std.testing.expectEqual(
                            indicSyllableEndReference(&codepoints, start, script_tag),
                            indicSyllableEnd(&codepoints, start, script_tag),
                        );
                    }
                }
            }
        }
    }
}

fn indicSyllableEndReference(codepoints: []const u21, start: usize, script_tag: unicode.OpenTypeScriptTag) usize {
    var index = start;
    var saw_virama = false;
    while (index < codepoints.len) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isIndicSyllableCodepoint(codepoint, script_tag)) break;
        if (index != start and isIndicBase(codepoint, script_tag) and !saw_virama and !isConsonantWithStacker(codepoints[index - 1], script_tag)) break;
        if (saw_virama and codepoint == 0x200c) return index + 1;

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

fn dev2PreBaseMatraTargetGlyphIndex(
    sources: []const usize,
    ligature_components: *const ligature_provenance.Store,
    codepoints: []const u21,
    syllable_start: usize,
    matra_source: usize,
    fallback_index: usize,
) PreBaseMatraTarget {
    var fallback_target = fallback_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index >= fallback_index) break;
        const effective_source = effectiveIndicSource(
            ligature_components,
            glyph_index,
            source,
            codepoints,
            .dev2,
        );
        if (effective_source < syllable_start or
            effective_source >= matra_source) continue;
        if (fallback_target == fallback_index) fallback_target = glyph_index;
        if (effective_source + 1 < codepoints.len and
            codepoints[effective_source] == 0x094d and
            codepoints[effective_source + 1] == 0x0935)
        {
            return .{ .index = @min(glyph_index + 1, fallback_index) };
        }
    }
    return .{ .index = fallback_target };
}

fn sourceSyllableStart(source_syllables: []const u8, source: usize) usize {
    const syllable = source_syllables[source];
    if (syllable == 0) return source;
    var start = source;
    while (start > 0 and source_syllables[start - 1] == syllable) start -= 1;
    return start;
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
            if (script_tag == .bng2 or script_tag == .beng) return glyph_index;
            if (hasVisibleViramaBeforeSource(sources, glyph_index, source)) break;
        }
        target = glyph_index;
    }
    return target;
}

fn dev2RephTargetGlyphIndex(
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
        if (source < codepoints.len and codepoints[source] -% 0x0900 <= 3) {
            break;
        }
        if (source > syllable_start and source < codepoints.len and
            isDev2Consonant(codepoints[source]) and
            codepoints[source - 1] == 0x094d and
            hasVisibleViramaBeforeSource(sources, glyph_index, source))
        {
            break;
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
        .ory2, .orya => codepoint >= 0x0b01 and codepoint <= 0x0b03,
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

fn hasConsonantLikeBase(codepoints: []const u21, script_tag: unicode.OpenTypeScriptTag) bool {
    for (codepoints) |codepoint| {
        if (isIndicBase(codepoint, script_tag)) return true;
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
    return isIndicConsonant(codepoint, script_tag) or
        isIndicIndependentVowel(codepoint, script_tag) or
        isIndicPlaceholderBase(codepoint, script_tag);
}

fn isIndicPlaceholderBase(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    if (codepoint == 0x25cc) return true;
    return switch (script_tag) {
        .bng2, .beng => codepoint == 0x0980,
        .knd2, .knda => codepoint == 0x0c80,
        else => false,
    };
}

fn isIndicConsonant(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => (codepoint >= 0x0995 and codepoint <= 0x09b9) or
            (codepoint >= 0x09dc and codepoint <= 0x09df),
        .ory2, .orya => (codepoint >= 0x0b15 and codepoint <= 0x0b39) or
            codepoint == 0x0b5c or
            codepoint == 0x0b5d or
            codepoint == 0x0b5f,
        .gur2, .guru => (codepoint >= 0x0a15 and codepoint <= 0x0a39) or
            (codepoint >= 0x0a59 and codepoint <= 0x0a5e) or
            (codepoint >= 0x0a72 and codepoint <= 0x0a74),
        .gjr3, .gjr2, .gujr => (codepoint >= 0x0a95 and codepoint <= 0x0aa8) or
            (codepoint >= 0x0aaa and codepoint <= 0x0ab0) or
            (codepoint >= 0x0ab2 and codepoint <= 0x0ab3) or
            (codepoint >= 0x0ab5 and codepoint <= 0x0ab9) or
            codepoint == 0x0ad0,
        .tel2, .telu => (codepoint >= 0x0c15 and codepoint <= 0x0c39) or
            codepoint == 0x0c58 or
            codepoint == 0x0c59,
        .knd2, .knda => codepoint == 0x0c80 or
            (codepoint >= 0x0c95 and codepoint <= 0x0cb9) or
            codepoint == 0x0cde or
            codepoint == 0x0cf1 or
            codepoint == 0x0cf2,
        .tml2, .taml => (codepoint >= 0x0b95 and codepoint <= 0x0bb9) or
            (codepoint >= 0x0bd0 and codepoint <= 0x0bd7) or
            (codepoint >= 0x11fc0 and codepoint <= 0x11ff1),
        .mlm2, .mlym => (codepoint >= 0x0d15 and codepoint <= 0x0d39) or
            (codepoint >= 0x0d54 and codepoint <= 0x0d56) or
            (codepoint >= 0x0d7a and codepoint <= 0x0d7f),
        else => (codepoint >= 0x0915 and codepoint <= 0x0939) or
            (codepoint >= 0x0958 and codepoint <= 0x095f) or
            codepoint == 0x1cf5,
    };
}

fn isIndicIndependentVowel(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .bng2, .beng => (codepoint >= 0x0985 and codepoint <= 0x0994) or
            codepoint == 0x09e0 or
            codepoint == 0x09e1,
        .ory2, .orya => (codepoint >= 0x0b05 and codepoint <= 0x0b14) or
            codepoint == 0x0b60 or
            codepoint == 0x0b61,
        .gur2, .guru => (codepoint >= 0x0a05 and codepoint <= 0x0a0a) or
            (codepoint >= 0x0a0f and codepoint <= 0x0a10) or
            (codepoint >= 0x0a13 and codepoint <= 0x0a14),
        .gjr3, .gjr2, .gujr => (codepoint >= 0x0a85 and codepoint <= 0x0a8d) or
            (codepoint >= 0x0a8f and codepoint <= 0x0a91) or
            (codepoint >= 0x0a93 and codepoint <= 0x0a94) or
            (codepoint >= 0x0ae0 and codepoint <= 0x0ae1),
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
        .ory2, .orya => (codepoint >= 0x0b01 and codepoint <= 0x0b03) or
            codepoint == 0x0b3c or
            (codepoint >= 0x0b3e and codepoint <= 0x0b44) or
            (codepoint >= 0x0b47 and codepoint <= 0x0b48) or
            (codepoint >= 0x0b4b and codepoint <= 0x0b4d) or
            codepoint == 0x0b55 or
            codepoint == 0x0b56 or
            codepoint == 0x0b57 or
            (codepoint >= 0x0b62 and codepoint <= 0x0b63),
        .gur2, .guru => (codepoint >= 0x0a01 and codepoint <= 0x0a03) or
            codepoint == 0x0a3c or
            (codepoint >= 0x0a3e and codepoint <= 0x0a42) or
            (codepoint >= 0x0a47 and codepoint <= 0x0a48) or
            (codepoint >= 0x0a4b and codepoint <= 0x0a4d) or
            codepoint == 0x0a51 or
            (codepoint >= 0x0a70 and codepoint <= 0x0a71) or
            codepoint == 0x0a75,
        .gjr3, .gjr2, .gujr => (codepoint >= 0x0a81 and codepoint <= 0x0a83) or
            codepoint == 0x0abc or
            (codepoint >= 0x0abe and codepoint <= 0x0ac5) or
            (codepoint >= 0x0ac7 and codepoint <= 0x0ac9) or
            (codepoint >= 0x0acb and codepoint <= 0x0acd) or
            (codepoint >= 0x0ae2 and codepoint <= 0x0ae3),
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
            codepoint == 0x0bd7 or
            codepoint == 0x1133c,
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
        // These are exactly the Kannada dependent vowels classified
        // BEFORE_SUB by the generated Indic positional table. Adjacent signs
        // such as U+0CC3 and U+0CC7 are AFTER_SUB and must retain their order.
        .knd2, .knda => codepoint == 0x0cbe or
            codepoint == 0x0cbf or
            codepoint == 0x0cc0 or
            codepoint == 0x0cc1 or
            codepoint == 0x0cc2 or
            codepoint == 0x0cc6 or
            codepoint == 0x0ccc or
            codepoint == 0x0ce2 or
            codepoint == 0x0ce3,
        else => false,
    };
}

fn isConsonantWithStacker(codepoint: u21, script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .knd2, .knda => codepoint == 0x0cf1 or codepoint == 0x0cf2,
        .dev2, .deva => codepoint == 0x1cf5,
        else => false,
    };
}

fn viramaCodepoint(script_tag: unicode.OpenTypeScriptTag) u21 {
    return switch (script_tag) {
        .bng2, .beng => 0x09cd,
        .ory2, .orya => 0x0b4d,
        .gur2, .guru => 0x0a4d,
        .gjr3, .gjr2, .gujr => 0x0acd,
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
        .ory2, .orya => 0x0b30,
        .gur2, .guru => 0x0a30,
        .gjr3, .gjr2, .gujr => 0x0ab0,
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

test "Gurmukhi virama ra marks blwf and trailing vowel cluster" {
    var features = [_]u32{0} ** 4;
    const codepoints = [_]u21{ 0x0a2d, 0x0a4d, 0x0a30, 0x0a42 };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .gur2));
    try std.testing.expectEqual(blwf_source_mask, features[1]);

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 9 });

    mergeTrailingDependentMarks(&clusters, &sources, &codepoints, .gur2);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, clusters.items);
}

test "Gujarati consonant virama marks half source" {
    var features = [_]u32{0} ** 6;
    const codepoints = [_]u21{ 0x0abe, 0x0aa8, 0x0acd, 0x200d, 0x0aa4, 0x0abf };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .gjr2));
    try std.testing.expectEqual(@as(u32, 0), features[0]);
    try std.testing.expect((features[1] & half_source_mask) != 0);
    try std.testing.expectEqual(@as(u32, 0), features[2]);
}

test "Gujarati i-matra is pre-base" {
    try std.testing.expect(isPreBaseMatra(0x0abf, .gjr2));
    try std.testing.expect(!isPreBaseMatra(0x0abe, .gjr2));
}

test "Devanagari prishthamatra stays before moved pre-base matra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 3, 4 });

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

    const codepoints = [_]u21{ 0x0915, 0x093f, 0x094e, 0x093c };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 4, 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 1, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
}

test "Devanagari prishthamatra skips earlier nukta before moved pre-base matra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 3, 4 });

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

    const codepoints = [_]u21{ 0x0915, 0x093f, 0x093c, 0x094e };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 4, 2, 3, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1, 2, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
}

test "Devanagari pre-base matra leaves following anusvara after base" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 60, 67, 6, 61 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 9 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0938, 0x093f, 0x0902, 0x0939 };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 67, 60, 6, 61 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 2, 3 }, sources.items);
}

test "Devanagari standalone pre-base matra moves before dotted circle" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 134, 67 });

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

    const codepoints = [_]u21{ 0x25cc, 0x093f };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 67, 134 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Devanagari broken pre-base matra remains before inserted dotted circle" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 67);

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

    const codepoints = [_]u21{0x093f};
    try insertDottedCirclesForBrokenClusters(
        std.testing.allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        134,
        .dev2,
    );
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 67, 134 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Telugu broken pre-base matra reorders after inserted dotted circle" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 8);

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

    const codepoints = [_]u21{0x0c47};
    try insertDottedCirclesForBrokenClusters(
        std.testing.allocator,
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        13,
        .tel2,
    );
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .tel2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 13, 8 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, sources.items);
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

test "Bengali reph reorders before post-base consonant forms" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 8, 1, 13, 6 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 2, 3, 5 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 0 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false, true });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.append(std.testing.allocator, try ligatures.addLigature(std.testing.allocator, &.{ 0, 1 }));
    try ligatures.infos.append(std.testing.allocator, .{});
    try ligatures.infos.append(std.testing.allocator, try ligatures.addLigature(std.testing.allocator, &.{ 3, 4 }));
    try ligatures.infos.append(std.testing.allocator, .{});

    const codepoints = [_]u21{ 0x09b0, 0x09cd, 0x09a5, 0x09cd, 0x09af, 0x09c0 };
    reorderRephs(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .bng2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 8, 13, 6 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 3, 5 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
}

test "Old-spec Bengali ra virama normalizes for blwf vatu" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 5, 3 });

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

    const codepoints = [_]u21{ 0x0995, 0x09cd, 0x09b0 };
    normalizeOldSpecBengaliRaViramaOrder(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .beng);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 3, 5 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1 }, sources.items);

    var features = [_]u32{0} ** 3;
    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .beng));
    try std.testing.expect((features[0] & half_source_mask) != 0);
    try std.testing.expect((features[2] & blwf_source_mask) != 0);
    try std.testing.expect((features[2] & (rphf_source_mask & ~gsub.feature.source_mask_marker)) == 0);
}

test "Old-spec Devanagari ra virama marks blwf vattu" {
    var features = [_]u32{0} ** 5;
    const codepoints = [_]u21{ 0x091f, 0x094d, 0x0930, 0x094d, 0x0020 };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .deva));
    try std.testing.expectEqual(@as(u32, 0), features[0]);
    try std.testing.expectEqual(@as(u32, 0), features[1]);
    try std.testing.expect((features[2] & blwf_source_mask) != 0);
    try std.testing.expectEqual(@as(u32, 0), features[3]);
}

test "Old-spec Devanagari post-base ra before vowel marks blwf vattu" {
    var features = [_]u32{0} ** 4;
    const codepoints = [_]u21{ 0x091f, 0x094d, 0x0930, 0x0942 };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .deva));
    try std.testing.expectEqual(@as(u32, 0), features[0]);
    try std.testing.expectEqual(@as(u32, 0), features[1]);
    try std.testing.expect((features[2] & blwf_source_mask) != 0);
    try std.testing.expectEqual(@as(u32, 0), features[3]);
}

test "Old-spec Devanagari ra virama zwj skips blwf vattu" {
    var features = [_]u32{0} ** 6;
    const codepoints = [_]u21{ 0x091f, 0x094d, 0x0930, 0x094d, 0x200d, 0x0915 };

    try std.testing.expect(!markBasicSourceFeatures(&features, &codepoints, .deva));
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0, 0, 0 }, &features);
}

test "Old-spec Devanagari moves halant after post-base ra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 7, 4, 6, 4, 1 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 6, 6, 12 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x091f, 0x094d, 0x0930, 0x094d, 0x0020 };
    normalizeOldSpecDevanagariHalantOrder(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .deva);

    try std.testing.expectEqualSlices(GlyphId, &.{ 7, 6, 4, 4, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1, 3, 4 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 12 }, clusters.items);
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

test "Bengali placeholder merges dependent mark cluster" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3 });

    const codepoints = [_]u21{ 0x0980, 0x0981 };
    mergePlaceholderDependentMarks(&clusters, &sources, &codepoints, .bng2);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Kannada consonant-with-stacker keeps following consonant in syllable" {
    var syllables = [_]u8{0} ** 2;
    const codepoints = [_]u21{ 0x0cf1, 0x0c95 };

    markSourceSyllables(&syllables, &codepoints, .knd2);

    try std.testing.expectEqualSlices(u8, &.{ 1, 1 }, &syllables);
}

test "Devanagari consonant-with-stacker keeps following consonant in syllable" {
    var syllables = [_]u8{0} ** 2;
    const codepoints = [_]u21{ 0x1cf5, 0x0915 };

    markSourceSyllables(&syllables, &codepoints, .dev2);

    try std.testing.expectEqualSlices(u8, &.{ 1, 1 }, &syllables);
}

test "Kannada old-spec trailing consonant virama uses blwf cluster" {
    var features = [_]u32{0} ** 4;
    const codepoints = [_]u21{ 0x0c9a, 0x0ccd, 0x0c9a, 0x0ccd };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .knda));
    try std.testing.expectEqual(blwf_source_mask, features[2]);

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 6 });

    mergeKannadaOldSpecTrailingBlwf(&clusters, &sources, &codepoints, .knda);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Kannada initial reorder moves before-sub vowel ahead of blwf pair" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 39, 70, 39, 57 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 6, 9 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false, true });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{
        .{},
        .{ .flags = .{ .synthetic_base = true } },
        .{},
        .{ .flags = .{ .base_mark_ligature = true } },
    });

    const codepoints = [_]u21{ 0x0ca8, 0x0ccd, 0x0ca8, 0x0cbe };
    reorderInitialKannadaVowels(
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        .knd2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 39, 57, 70, 39 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 1, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, clusters.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true, true, false }, substituted.items);
    try std.testing.expect(ligatures.infos.items[1].flags.base_mark_ligature);
    try std.testing.expect(ligatures.infos.items[2].flags.synthetic_base);

    var features = [_]u32{0} ** 4;
    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .knd2));
    try std.testing.expectEqual(blwf_source_mask, features[1]);
    try std.testing.expectEqual(@as(u32, 0), features[2]);
}

test "Kannada initial reorder leaves after-sub vowel after blwf pair" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 39, 70, 39, 59 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 6, 9 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0ca8, 0x0ccd, 0x0ca8, 0x0cc3 };
    reorderInitialKannadaVowels(
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        .knd2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 39, 70, 39, 59 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 6, 9 }, clusters.items);
}

test "Kannada before-sub vowel precedes every below-base pair" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 39, 70, 41, 70, 48, 64 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4, 5 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 6, 9, 12, 15 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0ca8, 0x0ccd, 0x0cab, 0x0ccd, 0x0cb2, 0x0cc6 };
    reorderInitialKannadaVowels(
        &glyphs,
        &sources,
        &clusters,
        &substituted,
        &ligatures,
        &codepoints,
        .knd2,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 39, 64, 70, 41, 70, 48 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 5, 1, 2, 3, 4 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 0, 0 }, clusters.items);
}

test "Odia joiner candrabindu uses Indic shaping cluster" {
    const codepoints = [_]u21{ 0x0b13, 0x200c, 0x0b01 };
    var features = [_]u32{0} ** 3;
    try std.testing.expect(!markBasicSourceFeatures(&features, &codepoints, .ory2));

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 6 });

    mergeTrailingDependentMarks(&clusters, &sources, &codepoints, .ory2);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 3 }, clusters.items);
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

test "Gujarati split matra components keep candra or ai before aa length mark" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 17, 10, 11, 2, 17, 10, 13 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 0, 1, 2, 4, 4, 5, 6 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 0, 0, 4, 4, 4, 4 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false, false, false, true, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0a85, 0x0abe, 0x0ac5, 0x0020, 0x0a85, 0x0abe, 0x0ac8 };
    reorderGujaratiSplitMatraComponents(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .gjr2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 17, 11, 10, 2, 17, 13, 10 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 1, 4, 4, 6, 5 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 4, 4, 4, 4 }, clusters.items);
}

test "Malayalam post-base virama consonant marks pstf source" {
    var features = [_]u32{0} ** 3;
    const codepoints = [_]u21{ 0x0d15, 0x0d4d, 0x0d2f };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .mlm2));
    try std.testing.expectEqual(pstf_source_mask, features[1]);
    try std.testing.expectEqual(@as(u32, 0), features[2]);
}

test "Malayalam logical repha reorders after base" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 12, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{} });

    const codepoints = [_]u21{ 0x0d4e, 0x0d15 };
    reorderLogicalRepha(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 12 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

test "Malayalam split matra canonical decomposition is available to Indic" {
    try std.testing.expectEqualSlices(u21, &.{ 0x0d47, 0x0d3e }, unicode.canonicalDecomposition(0x0d4b).?);
}

test "Malayalam split matra components merge with conjunct syllable" {
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 3, 6, 9, 9 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4 });

    const codepoints = [_]u21{ 0x0d17, 0x0d4d, 0x0d17, 0x0d47, 0x0d3e };
    mergeTrailingDependentMarks(&clusters, &sources, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0, 0 }, clusters.items);
}

test "Malayalam logical repha follows visible final virama" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 12, 22, 11 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 4 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 12 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x0d4e, 0x0d1a, 0x0d4d, 0x0d1a, 0x0d4d };
    reorderLogicalRepha(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .mlm2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 22, 11, 12 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 4, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, clusters.items);
}

test "Tamil consonant virama marks half source" {
    var features = [_]u32{0} ** 3;
    const codepoints = [_]u21{ 0x0ba4, 0x0bcd, 0x00b3 };

    try std.testing.expect(markBasicSourceFeatures(&features, &codepoints, .tml2));
    try std.testing.expectEqual(half_source_mask, features[0]);
    try std.testing.expectEqual(@as(u32, 0), features[1]);
}

test "Tamil script-extension nukta follows moved pre-base matra" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 3, 4 });

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

    const codepoints = [_]u21{ 0x0ba4, 0x0bc6, 0x1133c };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .tml2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 4, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, clusters.items);
}

test "Bengali source syllables split adjacent matra syllables" {
    var syllables = [_]u8{0} ** 6;
    const codepoints = [_]u21{ 0x0995, 0x09be, 0x09b9, 0x09bf, 0x09a8, 0x09c0 };

    markSourceSyllables(&syllables, &codepoints, .bng2);

    try std.testing.expectEqualSlices(u8, &.{ 1, 1, 2, 2, 3, 3 }, &syllables);
}

test "Bengali pre-base matras move before bases and mark init only at word start" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2, 1, 2, 1, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4, 5 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 2, 2, 4, 4 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x09ac, 0x09c7, 0x09ac, 0x09c7, 0x09b9, 0x09bf };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .bng2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1, 2, 1, 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 3, 2, 5, 4 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2, 4, 4 }, clusters.items);

    var source_features = [_]u32{0} ** 6;
    try std.testing.expect(markInitialMatraGlyphSources(&source_features, sources.items, &codepoints, .bng2));
    const init_mask = gsub.feature.sourceMaskForTag(unicode.tag("init")).?;
    try std.testing.expectEqual(init_mask, source_features[1]);
    try std.testing.expectEqual(@as(u32, 0), source_features[3]);
    try std.testing.expectEqual(@as(u32, 0), source_features[5]);
}

test "Devanagari ZWNJ after virama terminates pre-base matra target" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 9, 1, 3, 4 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 0, 6, 9, 9 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false, false, false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{}, .{}, .{}, .{} });

    const codepoints = [_]u21{ 0x091f, 0x094d, 0x200c, 0x092f, 0x093f };
    reorderPreBaseMatras(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, .dev2);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 9, 1, 4, 3 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 4, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 6, 9, 9 }, clusters.items);
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
