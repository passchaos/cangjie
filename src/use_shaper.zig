const std = @import("std");

const gsub = @import("gsub.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const shaping_metadata = @import("shaping_metadata.zig");
const unicode = @import("unicode.zig");
const shaping_cluster = @import("unicode/grapheme/shaping_cluster.zig");
const categories = @import("use/categories.zig");
const syllables = @import("use/syllables.zig");
const vowel_constraints = @import("use/vowel_constraints.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return @intFromEnum(script_tag) & 0xff == '3' or switch (script_tag) {
        .bali,
        .batk,
        .brah,
        .cakm,
        .cham,
        .dupl,
        .gran,
        .java,
        .lana,
        .lepc,
        .marc,
        .newa,
        .saur,
        .shrd,
        .sind,
        .sinh,
        .tirh,
        .modi,
        .phag,
        .takr,
        => true,
        else => false,
    };
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
    source_order: []const usize,
) !void {
    try syllables.markSourceFeatures(allocator, source_features, source_syllables, codepoints, source_order);
}

pub fn assignShapingClusterOwners(
    allocator: std.mem.Allocator,
    text: []const u8,
    cluster_base: usize,
    source_byte_starts: []const usize,
    codepoints: []const u21,
    glyph_cluster_indices: []usize,
) !void {
    if (source_byte_starts.len == 0 or glyph_cluster_indices.len == 0) return;
    if (source_byte_starts.len != codepoints.len) return error.InvalidUseInput;

    // Source ownership follows the OpenType shaping contract, not public caret
    // boundaries. Unicode-version changes to UAX #29 must not silently merge
    // or split USE provenance before GSUB.
    const graphemes = try shaping_cluster.itemize(allocator, text);
    defer allocator.free(graphemes);
    const owner_by_source = try allocator.alloc(usize, source_byte_starts.len);
    defer allocator.free(owner_by_source);
    for (owner_by_source, 0..) |*owner, source| owner.* = source;

    var source: usize = 0;
    for (graphemes) |grapheme| {
        const grapheme_end = grapheme.byte_start + grapheme.byte_len;
        while (source < source_byte_starts.len and source_byte_starts[source] - cluster_base < grapheme.byte_start) : (source += 1) {}
        if (source >= source_byte_starts.len) break;

        const owner = source;
        while (source < source_byte_starts.len) : (source += 1) {
            const byte_start = source_byte_starts[source] - cluster_base;
            if (byte_start >= grapheme_end) break;
            // UAX #29 classifies ZWNJ as Extend, but HarfBuzz intentionally
            // preserves its input cluster in the shaping buffer. Contextual
            // matching still treats it as a joiner; only cluster ownership
            // remains independent.
            owner_by_source[source] = if (codepoints[source] == 0x200c) source else owner;
        }
    }

    // HarfBuzz's monotone-grapheme initialization keeps WORD JOINER and ZWNJ
    // as independent clusters but assigns immediately following Unicode marks
    // to that cluster. UAX #29 either exposes a break after the control or
    // groups ZWNJ into the preceding grapheme, so this USE-specific adjustment
    // preserves HarfBuzz's shaping-buffer ownership in both cases.
    for (codepoints, 0..) |codepoint, source_index| {
        if (source_index == 0) continue;
        const previous_owner = owner_by_source[source_index - 1];
        if (categories.isUnicodeMarkForUse(codepoint)) {
            const owner_category = categories.forCodepoint(codepoints[previous_owner]);
            if (owner_category == .word_joiner or owner_category == .zwnj) {
                owner_by_source[source_index] = previous_owner;
            }
        }
        // When the preceding SAKOT itself inherited a ZWNJ-owned cluster, its
        // following consonant must continue that adjusted owner. Reusing the
        // original UAX grapheme owner here would incorrectly jump back across
        // the ZWNJ to the earlier base.
        if (codepoints[source_index - 1] == 0x1a60 and
            categories.forCodepoint(codepoints[owner_by_source[source_index - 1]]) == .zwnj and
            codepoint >= 0x1a20 and codepoint <= 0x1a54)
        {
            owner_by_source[source_index] = owner_by_source[source_index - 1];
        }
    }

    // HarfBuzz's default monotone-grapheme cluster level performs this merge
    // before GSUB. Keeping the metadata at that granularity lets later
    // ligatures merge adjacent graphemes only when they actually consume
    // components, rather than collapsing every character in a USE syllable.
    for (glyph_cluster_indices) |*cluster| {
        if (cluster.* < owner_by_source.len) cluster.* = owner_by_source[cluster.*];
    }
}

pub fn hasBrokenSyllable(source_syllables: []const u8) bool {
    for (source_syllables) |syllable_id| {
        if (syllableKindIs(syllable_id, .broken)) return true;
    }
    return false;
}

pub fn insertVowelConstraintDottedCircles(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: *std.ArrayList(u21),
    clusters: *std.ArrayList(usize),
    source_ends: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    dotted_circle_glyph: GlyphId,
    final_owns_dotted_circle_cluster: bool,
) std.mem.Allocator.Error!void {
    if (dotted_circle_glyph == 0) return;

    var source_index: usize = 0;
    while (source_index < codepoints.items.len) {
        const match_len = vowel_constraints.matchLength(codepoints.items, source_index);
        if (match_len == 0) {
            source_index += 1;
            continue;
        }

        const constrained_source = source_index + @as(usize, match_len) - 1;
        const source_start = clusters.items[constrained_source];
        const source_end = source_ends.items[constrained_source];
        // Reserve every parallel list before changing source indexes. Once the
        // first list mutates, an allocation failure must not leave shaping
        // metadata at different cardinalities.
        try codepoints.ensureUnusedCapacity(allocator, 1);
        try clusters.ensureUnusedCapacity(allocator, 1);
        try source_ends.ensureUnusedCapacity(allocator, 1);
        try glyph_ids.ensureUnusedCapacity(allocator, 1);
        try glyph_source_indices.ensureUnusedCapacity(allocator, 1);
        try glyph_cluster_indices.ensureUnusedCapacity(allocator, 1);
        try glyph_substituted.ensureUnusedCapacity(allocator, 1);
        try ligature_components.infos.ensureUnusedCapacity(allocator, 1);

        for (glyph_source_indices.items) |*source| {
            if (source.* >= constrained_source) source.* += 1;
        }
        for (glyph_cluster_indices.items) |*owner| {
            if (owner.* >= constrained_source) owner.* += 1;
        }
        ligature_components.shiftSourceIndices(constrained_source, 1);

        try codepoints.replaceRange(allocator, constrained_source, 0, &.{0x25cc});
        try clusters.replaceRange(allocator, constrained_source, 0, &.{source_start});
        try source_ends.replaceRange(allocator, constrained_source, 0, &.{source_end});

        var glyph_index: usize = 0;
        const shifted_source = constrained_source + 1;
        while (glyph_index < glyph_source_indices.items.len and glyph_source_indices.items[glyph_index] < shifted_source) : (glyph_index += 1) {}
        if (glyph_index >= glyph_source_indices.items.len or glyph_source_indices.items[glyph_index] != shifted_source) {
            source_index = shifted_source + 1;
            continue;
        }

        // Vowel constraints insert immediately before the final scalar and
        // clear its grapheme continuation bit. Model that by giving the circle
        // a distinct synthetic source and making both glyphs own their source
        // starts rather than the preceding independent vowel's grapheme.
        glyph_cluster_indices.items[glyph_index] = if (final_owns_dotted_circle_cluster)
            constrained_source
        else
            shifted_source;
        try shaping_metadata.insert(
            allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_index,
            dotted_circle_glyph,
            constrained_source,
            constrained_source,
        );
        source_index = shifted_source + 1;
    }
}

pub fn decomposeCanonicalSources(
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
    cluster_level: shaping_metadata.ClusterLevel,
) !void {
    var source_index: usize = 0;
    while (source_index < codepoints.items.len) {
        const components = unicode.canonicalDecomposition(codepoints.items[source_index]) orelse {
            source_index += 1;
            continue;
        };
        // The generated table contains only decompositions whose first
        // component is a Unicode mark—the split-matra class USE refuses to
        // recompose. Base+mark mappings are filtered out at generation time.
        if (components.len <= 1) {
            source_index += 1;
            continue;
        }

        // HarfBuzz only decomposes when every emitted component is present in
        // the selected font. Preserve the original scalar otherwise.
        var component_glyphs: [4]GlyphId = undefined;
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
        var source_starts: [4]usize = undefined;
        var source_end_values: [4]usize = undefined;
        @memset(source_starts[0..components.len], source_start);
        @memset(source_end_values[0..components.len], source_end);
        try clusters.replaceRange(allocator, source_index, 1, source_starts[0..components.len]);
        try source_ends.replaceRange(allocator, source_index, 1, source_end_values[0..components.len]);

        var glyph_index: usize = 0;
        while (glyph_index < glyph_source_indices.items.len and glyph_source_indices.items[glyph_index] < source_index) : (glyph_index += 1) {}
        if (glyph_index >= glyph_source_indices.items.len or glyph_source_indices.items[glyph_index] != source_index) {
            source_index += components.len;
            continue;
        }
        const component_cluster_owner = glyph_cluster_indices.items[glyph_index];
        try glyph_ids.replaceRange(allocator, glyph_index, 1, component_glyphs[0..components.len]);
        var sources: [4]usize = undefined;
        var owners: [4]usize = undefined;
        var substituted: [4]bool = .{ false, false, false, false };
        var infos: [4]ligature_provenance.Info = undefined;
        for (0..components.len) |component_index| {
            sources[component_index] = source_index + component_index;
            // Canonical decomposition creates internal shaping sources, not
            // new text clusters. HarfBuzz copies the original scalar's cluster
            // to every component. Grapheme levels retain the already-resolved
            // grapheme owner; character levels must instead recover the
            // original scalar because mark initialization may have inherited
            // the preceding cluster before decomposition.
            owners[component_index] = canonicalDecompositionClusterOwner(
                cluster_level,
                component_cluster_owner,
                source_index,
                component_index,
            );
            infos[component_index] = .{};
        }
        try glyph_source_indices.replaceRange(allocator, glyph_index, 1, sources[0..components.len]);
        try glyph_cluster_indices.replaceRange(allocator, glyph_index, 1, owners[0..components.len]);
        try glyph_substituted.replaceRange(allocator, glyph_index, 1, substituted[0..components.len]);
        try ligature_components.infos.replaceRange(allocator, glyph_index, 1, infos[0..components.len]);
        source_index += components.len;
    }
}

/// Return whether the source may contain one of the split-matra
/// decompositions retained by this shaping stage. The primary Devanagari
/// block has none, but an explicit Devanagari script override may still carry
/// arbitrary mixed-script input, so the proof must inspect every source.
pub fn mayHaveCanonicalDecomposition(
    codepoints: []const u21,
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    if (script_tag != .dev2 and script_tag != .deva) return true;
    for (codepoints) |codepoint| {
        if (codepoint < 0x0900 or codepoint > 0x097f) return true;
    }
    return false;
}

test "Devanagari has no retained canonical source decomposition" {
    try std.testing.expect(!mayHaveCanonicalDecomposition(
        &.{ 0x0915, 0x094d, 0x0937 },
        .dev2,
    ));
    try std.testing.expect(!mayHaveCanonicalDecomposition(&.{0x0958}, .deva));
    // An explicit script override does not prove homogeneous source text.
    try std.testing.expect(mayHaveCanonicalDecomposition(&.{ 0x0915, 0x09cb }, .dev2));
    try std.testing.expect(mayHaveCanonicalDecomposition(&.{0x09cb}, .bng2));
}

fn canonicalDecompositionClusterOwner(
    cluster_level: shaping_metadata.ClusterLevel,
    grapheme_owner: usize,
    source_index: usize,
    component_index: usize,
) usize {
    // Character levels retain one internal owner per component. The source
    // byte starts still remain identical, but the distinct metadata identity
    // allows Indic final reordering to merge only the leading split-matra
    // component while leaving a post-base component at the original byte.
    return if (cluster_level.groupsGraphemes())
        grapheme_owner
    else
        source_index + component_index;
}

pub fn recordPrefSubstitutions(
    glyph_source_indices: []const usize,
    glyph_stage_substituted: []const bool,
    source_pref_substituted: []bool,
) void {
    std.debug.assert(glyph_source_indices.len == glyph_stage_substituted.len);
    for (glyph_source_indices, glyph_stage_substituted) |source, substituted| {
        if (substituted and source < source_pref_substituted.len) {
            source_pref_substituted[source] = true;
        }
    }
}

pub fn recordRphfSubstitutions(
    glyph_source_indices: []const usize,
    glyph_stage_substituted: []const bool,
    source_features: []const u32,
    source_syllables: []const u8,
    source_rphf_substituted: []bool,
) void {
    std.debug.assert(glyph_source_indices.len == glyph_stage_substituted.len);
    const rphf_mask = gsub.feature.sourceMaskForTag(unicode.tag("rphf")).?;
    var previous_syllable: u8 = 0;
    var found_in_syllable = false;
    for (glyph_source_indices, glyph_stage_substituted) |source, substituted| {
        if (source >= source_syllables.len) continue;
        const syllable = source_syllables[source];
        if (syllable != previous_syllable) {
            previous_syllable = syllable;
            found_in_syllable = false;
        }
        if (found_in_syllable or source >= source_features.len) continue;
        if ((source_features[source] & rphf_mask) == 0) continue;
        if (substituted and source < source_rphf_substituted.len) {
            source_rphf_substituted[source] = true;
            found_in_syllable = true;
        }
    }
}

pub fn insertDottedCirclesForBrokenSyllables(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_syllables: []const u8,
    source_rphf_substituted: []const bool,
    source_pref_substituted: []const bool,
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
            const dynamic_repha = candidate_source < source_rphf_substituted.len and
                source_rphf_substituted[candidate_source] and
                (insert_index == glyph_index or glyph_source_indices.items[insert_index - 1] != candidate_source);
            if (!dynamic_repha and categoryForReordering(candidate_source, source_pref_substituted, codepoints) != .repha) break;
        }

        // HarfBuzz inserts before the broken syllable and then reorders a
        // leading VPre ahead of the dotted circle. Insert after that one glyph
        // directly: our source metadata intentionally remains source-level, so
        // the synthetic circle and the source glyph cannot carry distinct USE
        // categories. Consult the post-pref category here because a successful
        // `pref` substitution dynamically turns an MPre (or another category)
        // into VPre before HarfBuzz performs this reorder.
        if (insert_index < glyph_source_indices.items.len) {
            const candidate_source = glyph_source_indices.items[insert_index];
            if (categories.isPrebaseVowel(categoryForReordering(candidate_source, source_pref_substituted, codepoints))) {
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
        ligature_components.infos.items[insert_index].flags.synthetic_base = true;
        if (insert_index <= glyph_index) glyph_index += 1;
    }
}

pub fn reorderGlyphs(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []ligature_provenance.Info,
    source_syllables: []const u8,
    source_rphf_substituted: []const bool,
    source_pref_substituted: []const bool,
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
        reorderRephaGlyphInSyllable(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_rphf_substituted,
            source_pref_substituted,
            codepoints,
            syllable_start,
            syllable_end,
        );
        reorderPrebaseGlyphsInSyllable(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_pref_substituted,
            codepoints,
            syllable_start,
            syllable_end,
        );
        syllable_start = syllable_end;
    }
}

fn reorderRephaGlyphInSyllable(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []ligature_provenance.Info,
    source_rphf_substituted: []const bool,
    source_pref_substituted: []const bool,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    if (end - start <= 1) return;
    const first_source = glyph_source_indices[start];
    const first_is_dynamic_repha = first_source < source_rphf_substituted.len and
        source_rphf_substituted[first_source];
    if (!first_is_dynamic_repha and categoryForReordering(first_source, source_pref_substituted, codepoints) != .repha) return;

    for (start + 1..end) |index| {
        const source = glyph_source_indices[index];
        const category = categoryForReordering(source, source_pref_substituted, codepoints);
        const is_post_base = categories.isPostbase(category) or
            (categories.isHalantLike(category) and ligature_components[index].component_count <= 1);
        if (!is_post_base and index != end - 1) continue;

        // Repha moves before the first post-base glyph, or to the end when the
        // syllable contains no post-base item. This is HarfBuzz's forward
        // reorder and must move all source/cluster/ligature metadata together.
        const destination = if (is_post_base) index - 1 else index;
        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices, start, destination + 1);
        var current = start;
        while (current < destination) : (current += 1) {
            shaping_metadata.swap(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                current,
                current + 1,
            );
        }
        return;
    }
}

fn reorderPrebaseGlyphsInSyllable(
    glyph_ids: []GlyphId,
    glyph_source_indices: []usize,
    glyph_cluster_indices: []usize,
    glyph_substituted: []bool,
    ligature_components: []ligature_provenance.Info,
    source_pref_substituted: []const bool,
    codepoints: []const u21,
    start: usize,
    end: usize,
) void {
    var insertion = start;
    var index = start;
    while (index < end) {
        const source = glyph_source_indices[index];
        const category = categoryForReordering(source, source_pref_substituted, codepoints);
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
            shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices, insertion, index + 1);
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

fn categoryForReordering(source: usize, source_pref_substituted: []const bool, codepoints: []const u21) Category {
    if (source < source_pref_substituted.len and source_pref_substituted[source]) return .vowel_pre;
    return if (source < codepoints.len) categories.forCodepoint(codepoints[source]) else .other;
}

fn syllableKindIs(syllable_id: u8, kind: SyllableType) bool {
    return (syllable_id & 0x0f) == @intFromEnum(kind);
}

const feature_applications = [_]gsub.feature.Application{
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

const default_preprocessing_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true, .auto_zwj = false },
};

const rphf_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("rphf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
};

const pref_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
};

const basic_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true, .auto_zwj = false },
};

const topographical_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("isol"), .source_scoped = true },
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("medi"), .source_scoped = true },
    .{ .tag = unicode.tag("fina"), .source_scoped = true },
};

const final_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
};

const typographic_applications = [_]gsub.feature.Application{
    .{ .tag = unicode.tag("abvm") },
    .{ .tag = unicode.tag("blwm") },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("dist") },
    .{ .tag = unicode.tag("liga") },
    .{ .tag = unicode.tag("rclt") },
};

pub fn featureApplications() []const gsub.feature.Application {
    return &feature_applications;
}

pub fn defaultPreprocessingFeatureApplications() []const gsub.feature.Application {
    return &default_preprocessing_applications;
}

pub fn rphfFeatureApplications() []const gsub.feature.Application {
    return &rphf_applications;
}

pub fn prefFeatureApplications() []const gsub.feature.Application {
    return &pref_applications;
}

pub fn basicFeatureApplications() []const gsub.feature.Application {
    return &basic_applications;
}

pub fn topographicalFeatureApplications() []const gsub.feature.Application {
    return &topographical_applications;
}

pub fn finalFeatureApplications() []const gsub.feature.Application {
    return &final_applications;
}

pub fn typographicFeatureApplications() []const gsub.feature.Application {
    return &typographic_applications;
}

test "USE category covers Duployan sample codepoints" {
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc02));
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc5b));
    try @import("std").testing.expectEqual(Category.cg_joiner, categoryForCodepoint(0x034f));
    try @import("std").testing.expectEqual(Category.zwnj, categoryForCodepoint(0x200c));
    try @import("std").testing.expectEqual(Category.other, categoryForCodepoint(0x002e));
}

test "USE shaping includes Lepcha" {
    try std.testing.expect(shouldShape(.lepc));
}

test "USE vowel constraints insert a distinct synthetic source" {
    const allocator = std.testing.allocator;
    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(allocator);
    try glyph_ids.appendSlice(allocator, &.{ 1, 7 });
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(allocator);
    try codepoints.appendSlice(allocator, &.{ 0x0905, 0x093a });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 3 });
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(allocator);
    try source_ends.appendSlice(allocator, &.{ 3, 6 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var owners = std.ArrayList(usize).empty;
    defer owners.deinit(allocator);
    try owners.appendSlice(allocator, &.{ 0, 0 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false });
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.appendSlice(allocator, &.{ .{}, .{} });

    try insertVowelConstraintDottedCircles(
        allocator,
        &glyph_ids,
        &codepoints,
        &clusters,
        &source_ends,
        &sources,
        &owners,
        &substituted,
        &components,
        87,
        false,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 87, 7 }, glyph_ids.items);
    try std.testing.expectEqualSlices(u21, &.{ 0x0905, 0x25cc, 0x093a }, codepoints.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, owners.items);
}

test "Indic vowel constraints can merge the final scalar with dotted-circle owner" {
    const allocator = std.testing.allocator;
    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(allocator);
    try glyph_ids.appendSlice(allocator, &.{ 17, 30, 5 });
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(allocator);
    try codepoints.appendSlice(allocator, &.{ 0x0930, 0x094d, 0x0907 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 4, 4, 10 });
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(allocator);
    try source_ends.appendSlice(allocator, &.{ 7, 10, 13 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    var owners = std.ArrayList(usize).empty;
    defer owners.deinit(allocator);
    try owners.appendSlice(allocator, &.{ 0, 0, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false, false });
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.appendSlice(allocator, &.{ .{}, .{}, .{} });

    try insertVowelConstraintDottedCircles(
        allocator,
        &glyph_ids,
        &codepoints,
        &clusters,
        &source_ends,
        &sources,
        &owners,
        &substituted,
        &components,
        87,
        true,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 17, 30, 87, 5 }, glyph_ids.items);
    try std.testing.expectEqualSlices(u21, &.{ 0x0930, 0x094d, 0x25cc, 0x0907 }, codepoints.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2 }, owners.items);
}

test "canonical decomposition preserves the original cluster owner" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 0x1b13, 0x1b35, 0x1b3c, 0x1b3d });
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(allocator);
    try glyph_ids.appendSlice(allocator, &.{ 1, 2 });
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(allocator);
    try codepoints.appendSlice(allocator, &.{ 0x1b13, 0x1b3d });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 3 });
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(allocator);
    try source_ends.appendSlice(allocator, &.{ 3, 6 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var owners = std.ArrayList(usize).empty;
    defer owners.deinit(allocator);
    try owners.appendSlice(allocator, &.{ 0, 0 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false });
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.appendSlice(allocator, &.{ .{}, .{} });

    // The synthetic cmap includes both decomposition components so this
    // exercises the successful, cardinality-changing branch without relying
    // on a system or upstream test font.
    try decomposeCanonicalSources(
        allocator,
        &font,
        &glyph_ids,
        &codepoints,
        &clusters,
        &source_ends,
        &sources,
        &owners,
        &substituted,
        &components,
        .monotone_graphemes,
    );
    try std.testing.expectEqualSlices(u21, &.{ 0x1b13, 0x1b3c, 0x1b35 }, codepoints.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, owners.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 3 }, clusters.items);
    try std.testing.expectEqual(
        @as(usize, 1),
        canonicalDecompositionClusterOwner(.monotone_characters, 0, 1, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        canonicalDecompositionClusterOwner(.monotone_characters, 0, 1, 1),
    );
}

test "USE shaping includes Balinese" {
    try @import("std").testing.expect(shouldShape(.bali));
    try @import("std").testing.expect(shouldShape(.batk));
    try @import("std").testing.expect(shouldShape(.brah));
    try @import("std").testing.expect(shouldShape(.cakm));
    try @import("std").testing.expect(shouldShape(.cham));
    try @import("std").testing.expect(shouldShape(.dupl));
    try @import("std").testing.expect(shouldShape(.java));
    try @import("std").testing.expect(shouldShape(.lana));
    try @import("std").testing.expect(shouldShape(.marc));
    try @import("std").testing.expect(shouldShape(.newa));
    try @import("std").testing.expect(shouldShape(.phag));
    try @import("std").testing.expect(shouldShape(.saur));
    try @import("std").testing.expect(shouldShape(.gran));
    try @import("std").testing.expect(shouldShape(.shrd));
    try @import("std").testing.expect(!shouldShape(.latn));
}

test "USE source owners remain independent from public grapheme boundaries" {
    const allocator = std.testing.allocator;
    const text = "ꦟ꧀ꦢꦿ";
    const byte_starts = [_]usize{ 0, 3, 6, 9 };
    const codepoints = [_]u21{ 0xa99f, 0xa9c0, 0xa9a2, 0xa9bf };
    var cluster_owners = [_]usize{ 0, 1, 2, 3 };

    const public_graphemes = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(public_graphemes);
    try std.testing.expectEqual(@as(usize, 1), public_graphemes.len);

    try assignShapingClusterOwners(allocator, text, 0, &byte_starts, &codepoints, &cluster_owners);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2 }, &cluster_owners);
}

test "USE cluster owners preserve ZWNJ identity" {
    const allocator = std.testing.allocator;
    const text = "ꦢ꧀‌ꦔ";
    const byte_starts = [_]usize{ 0, 3, 6, 9 };
    const codepoints = [_]u21{ 0xa9a2, 0xa9c0, 0x200c, 0xa994 };
    var cluster_owners = [_]usize{ 0, 1, 2, 3 };

    try assignShapingClusterOwners(allocator, text, 0, &byte_starts, &codepoints, &cluster_owners);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 3 }, &cluster_owners);
}

test "USE cluster owners propagate ZWNJ through a Tai Tham stack" {
    const allocator = std.testing.allocator;
    const text = "ᨶ᩠ᩅ‌ᩣ᩠ᨿ";
    const byte_starts = [_]usize{ 0, 3, 6, 9, 12, 15, 18 };
    const codepoints = [_]u21{ 0x1a36, 0x1a60, 0x1a45, 0x200c, 0x1a63, 0x1a60, 0x1a3f };
    var cluster_owners = [_]usize{ 0, 1, 2, 3, 4, 5, 6 };

    try assignShapingClusterOwners(allocator, text, 0, &byte_starts, &codepoints, &cluster_owners);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 3, 3, 3, 3 }, &cluster_owners);
}

test "USE cluster owners keep ordinary Tai Tham SAKOT stacks separate" {
    const allocator = std.testing.allocator;
    const text = "ᨽ᩠ᨽᩣ᩠ᨽᩙ";
    const byte_starts = [_]usize{ 0, 3, 6, 9, 12, 15, 18 };
    const codepoints = [_]u21{ 0x1a3d, 0x1a60, 0x1a3d, 0x1a63, 0x1a60, 0x1a3d, 0x1a59 };
    var cluster_owners = [_]usize{ 0, 1, 2, 3, 4, 5, 6 };

    try assignShapingClusterOwners(allocator, text, 0, &byte_starts, &codepoints, &cluster_owners);

    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2, 2, 5, 5 }, &cluster_owners);
}

test "USE cluster owners attach marks after WORD JOINER" {
    const allocator = std.testing.allocator;
    const text = "𑄤⁠𑄧";
    const byte_starts = [_]usize{ 0, 4, 7 };
    const codepoints = [_]u21{ 0x11124, 0x2060, 0x11127 };
    var cluster_owners = [_]usize{ 0, 1, 2 };

    try assignShapingClusterOwners(allocator, text, 0, &byte_starts, &codepoints, &cluster_owners);

    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 1 }, &cluster_owners);
}

test "USE reordering moves only the first split prebase component" {
    var glyph_ids = [_]GlyphId{ 10, 20, 21 };
    var sources = [_]usize{ 0, 1, 1 };
    var cluster_owners = [_]usize{ 0, 1, 1 };
    var substituted = [_]bool{ false, true, true };
    var components = [_]ligature_provenance.Info{ .{}, .{}, .{} };
    const syllable_serials = [_]u8{ 0x12, 0x12 };
    const rphf_substituted = [_]bool{ false, false };
    const pref_substituted = [_]bool{ false, false };
    const codepoints = [_]u21{ 0x1b19, 0x1b40 };

    reorderGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 10, 21 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0, 1 }, &sources);
    // Moving the first component merges through its already-shared source
    // cluster, so the trailing MultipleSubst component inherits the new owner.
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0 }, &cluster_owners);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true }, &substituted);
}

test "USE pref substitutions reorder as prebase glyphs" {
    var glyph_ids = [_]GlyphId{ 10, 20 };
    var sources = [_]usize{ 0, 1 };
    var cluster_owners = [_]usize{ 0, 0 };
    var substituted = [_]bool{ false, true };
    var components = [_]ligature_provenance.Info{ .{}, .{} };
    const syllable_serials = [_]u8{ 0x12, 0x12 };
    const rphf_substituted = [_]bool{ false, false };
    const pref_substituted = [_]bool{ false, true };
    const codepoints = [_]u21{ 0xa99f, 0xa9c0 };

    reorderGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 10 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, &sources);
}

test "USE prebase vowel reorders before synthetic dotted circle" {
    var glyph_ids = [_]GlyphId{ 134, 67 };
    var sources = [_]usize{ 0, 1 };
    var cluster_owners = [_]usize{ 0, 0 };
    var substituted = [_]bool{ false, false };
    var components = [_]ligature_provenance.Info{ .{}, .{} };
    components[0].flags.synthetic_base = true;
    const syllable_serials = [_]u8{ 0x12, 0x12 };
    const rphf_substituted = [_]bool{ false, false };
    const pref_substituted = [_]bool{ false, false };
    const codepoints = [_]u21{ 0x25cc, 0x093f };

    reorderGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 67, 134 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, &sources);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, &cluster_owners);
    try std.testing.expect(components[1].flags.synthetic_base);
}

test "USE records only the first rphf substitution in each syllable" {
    const rphf_mask = gsub.feature.sourceMaskForTag(unicode.tag("rphf")).?;
    const sources = [_]usize{ 0, 0, 2, 3, 4 };
    const stage_substituted = [_]bool{ true, true, false, true, true };
    const source_features = [_]u32{
        rphf_mask,
        rphf_mask,
        rphf_mask,
        rphf_mask,
        rphf_mask,
    };
    const source_syllables = [_]u8{ 0x12, 0x12, 0x12, 0x22, 0x22 };
    var rphf_substituted = [_]bool{false} ** source_features.len;

    recordRphfSubstitutions(
        &sources,
        &stage_substituted,
        &source_features,
        &source_syllables,
        &rphf_substituted,
    );

    // Multiple outputs with source 0 still identify one Repha. The next
    // syllable independently records its first substituted rphf source.
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, true, false }, &rphf_substituted);
}

test "USE rphf substitutions reorder as repha glyphs" {
    var glyph_ids = [_]GlyphId{ 50, 10, 20 };
    var sources = [_]usize{ 0, 2, 3 };
    var cluster_owners = [_]usize{ 0, 2, 3 };
    var substituted = [_]bool{ true, false, false };
    var components = [_]ligature_provenance.Info{ .{}, .{}, .{} };
    const syllable_serials = [_]u8{ 0x12, 0x12, 0x12, 0x12 };
    const rphf_substituted = [_]bool{ true, false, false, false };
    const pref_substituted = [_]bool{ false, false, false, false };
    const codepoints = [_]u21{ 0x1142c, 0x11442, 0x1140e, 0x1145e };

    reorderGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 50, 20 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 3 }, &sources);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 3 }, &cluster_owners);
}

test "USE repha reorder preserves a GSUB-widened trailing cluster" {
    var glyph_ids = [_]GlyphId{ 13, 10, 14, 12 };
    var sources = [_]usize{ 0, 2, 3, 5 };
    // The below-form ligature at index two consumed source four and widened
    // the final virama's cluster owner to the same pre-ligature cluster.
    var cluster_owners = [_]usize{ 0, 2, 2, 2 };
    var substituted = [_]bool{ true, false, true, false };
    var components = [_]ligature_provenance.Info{
        .{},
        .{},
        .{ .component_count = 2 },
        .{},
    };
    const syllable_serials = [_]u8{ 0x12, 0x12, 0x12, 0x12, 0x12, 0x12 };
    const rphf_substituted = [_]bool{ true, false, false, false, false, false };
    const pref_substituted = [_]bool{ false, false, false, false, false, false };
    const codepoints = [_]u21{ 0x1102d, 0x11046, 0x11013, 0x11046, 0x11013, 0x11046 };

    reorderGlyphs(
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 14, 13, 12 }, &glyph_ids);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 0, 0 }, &cluster_owners);
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
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.resize(allocator, sources.items.len);
    @memset(components.infos.items, .{});
    const syllable_serials = [_]u8{ 0x12, 0x12, 0x27 };
    const rphf_substituted = [_]bool{ false, false, false };
    const pref_substituted = [_]bool{ false, false, false };
    const codepoints = [_]u21{ 0x1b13, 0x1b36, 0x1b3e };

    try insertDottedCirclesForBrokenSyllables(
        allocator,
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
        128,
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 23, 58, 66, 128 }, glyph_ids.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 2 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0, 2, 2 }, cluster_owners.items);
    try std.testing.expect(components.infos.items[3].flags.synthetic_base);
}

test "USE dotted circle follows a pref-substituted broken-cluster glyph" {
    const allocator = std.testing.allocator;
    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(allocator);
    try glyph_ids.appendSlice(allocator, &.{ 191, 240, 265 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    var cluster_owners = std.ArrayList(usize).empty;
    defer cluster_owners.deinit(allocator);
    try cluster_owners.appendSlice(allocator, &.{ 0, 1, 1 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, true, false });
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.resize(allocator, sources.items.len);
    @memset(components.infos.items, .{});
    const syllable_serials = [_]u8{ 0x12, 0x27, 0x27 };
    const rphf_substituted = [_]bool{ false, false, false };
    const pref_substituted = [_]bool{ false, true, false };
    const codepoints = [_]u21{ 0x1a2f, 0x1a55, 0x1a63 };

    try insertDottedCirclesForBrokenSyllables(
        allocator,
        &glyph_ids,
        &sources,
        &cluster_owners,
        &substituted,
        &components,
        &syllable_serials,
        &rphf_substituted,
        &pref_substituted,
        &codepoints,
        143,
    );

    // The source-level metadata cannot distinguish the inserted base-category
    // circle from the dynamically reclassified VPre glyph. Insert directly in
    // their final HarfBuzz order rather than letting reorder skip both as one
    // same-source MultipleSubst-like group.
    try std.testing.expectEqualSlices(GlyphId, &.{ 191, 240, 143, 265 }, glyph_ids.items);
}

test {
    std.testing.refAllDecls(@This());
}
