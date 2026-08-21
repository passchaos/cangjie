//! Indic source preparation and staged post-GSUB reordering.

const std = @import("std");

const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const indic = @import("../../../../indic.zig");
const ligature_provenance =
    @import("../../../../ligature_provenance.zig");
const cluster_safety = @import("../../../cluster_safety.zig");
const cache = @import("../../../context/cache/root.zig");
const executor = @import("../executor.zig");
const pipeline_types = @import("../../types.zig");
const source_pipeline = @import("../../source/root.zig");
const use = @import("use.zig");

pub const supports = indic.shouldShape;

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    glyph_index_cache: ?*cache.GlyphIndexCache,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: *std.ArrayList(u21),
    clusters: *std.ArrayList(usize),
    source_ends: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    glyph_stage_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_features: *std.ArrayList(u32),
    source_syllables: *std.ArrayList(u8),
    source_pref_substituted: *std.ArrayList(bool),
    source_boundaries: *cluster_safety.SourceBoundaries,
    options: *gsub.runtime.Options,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
};

pub fn prepare(input: Input) !void {
    const dotted_circle_glyph = try source_pipeline.glyphIndex(
        input.font,
        input.glyph_index_cache,
        0x25cc,
    );
    try use.insertVowelConstraintDottedCircles(
        input.allocator,
        input.glyph_ids,
        input.codepoints,
        input.clusters,
        input.source_ends,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        dotted_circle_glyph,
        true,
    );
    try use.decomposeCanonicalSources(
        input.allocator,
        input.font,
        input.glyph_ids,
        input.codepoints,
        input.clusters,
        input.source_ends,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.lookup_options.cluster_level orelse .monotone_graphemes,
    );
    input.options.source_codepoints = input.codepoints.items;
    input.source_boundaries.bindSourceByteStarts(input.clusters.items);
}

pub fn finish(input: Input) !void {
    // Preserve the historical two-query contract. With a context cache this
    // is a hit; without one it retains defensive borrowed-font validation at
    // each distinct shaper phase.
    const dotted_circle_glyph = try source_pipeline.glyphIndex(
        input.font,
        input.glyph_index_cache,
        0x25cc,
    );
    try indic.insertDottedCirclesForBrokenClusters(
        input.allocator,
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        dotted_circle_glyph,
        input.lookup_options.script_tag,
    );
    normalizeInitialOrder(input);

    try input.source_features.resize(
        input.allocator,
        input.codepoints.items.len,
    );
    try input.source_syllables.resize(
        input.allocator,
        input.codepoints.items.len,
    );
    const has_basic_source_features =
        indic.markSourceSyllablesAndBasicFeatures(
            input.source_syllables.items,
            input.source_features.items,
            input.codepoints.items,
            input.lookup_options.script_tag,
        );
    try input.source_pref_substituted.resize(
        input.allocator,
        input.codepoints.items.len,
    );
    @memset(input.source_pref_substituted.items, false);
    input.options.source_features = input.source_features.items;
    input.options.source_syllables = input.source_syllables.items;
    const applications = [_][]const gsub.feature.Application{
        indic.preReorderFeatureApplications(),
        indic.basicFeatureApplications(has_basic_source_features),
        indic.prefFeatureApplications(),
        indic.preRephFeatureApplications(),
        indic.finalFeatureApplications(),
    };
    var plans: [applications.len]gsub.feature.LookupPlan = undefined;
    const cached_plans = input.table_proved and
        input.context.lookup_selection_cache != null;
    if (cached_plans) try input.context.lookup_selection_cache.?
        .gsubFeatureLookupPlans(
        input.font,
        &applications,
        input.options.*,
        input.gdef_metadata,
        &plans,
    );

    try gsub.runtime.validateScriptShaperMetadata(
        input.options.*,
        input.glyph_ids.items.len,
    );
    if (cached_plans) try executor.applyPlanAfterRunProof(
        input.font,
        input.context,
        plans[0],
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    ) else try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        indic.preReorderFeatureApplications(),
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    );
    indic.reorderInitialKannadaVowels(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    if (cached_plans) try executor.applyPlanAfterRunProof(
        input.font,
        input.context,
        plans[1],
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    ) else try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        indic.basicFeatureApplications(has_basic_source_features),
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    );
    try applyPref(input, if (cached_plans) plans[2] else null);
    reorderAfterPref(input);
    if (cached_plans) try executor.applyPlanAfterRunProof(
        input.font,
        input.context,
        plans[3],
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    ) else try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        indic.preRephFeatureApplications(),
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    );
    reorderAfterReph(input);
    if (cached_plans) try executor.applyPlanAfterRunProof(
        input.font,
        input.context,
        plans[4],
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    ) else try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        indic.finalFeatureApplications(),
        input.glyph_ids,
        input.options.*,
        input.gdef_metadata,
    );
    indic.mergeMalayalamOldSpecTrailingViramaClusters(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.reorderGujaratiSplitMatraComponents(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
}

fn normalizeInitialOrder(input: Input) void {
    indic.mergeMalayalamDotRephBrokenCluster(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.mergePlaceholderDependentMarks(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.mergeTrailingDependentMarks(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.mergeKannadaOldSpecTrailingBlwf(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.normalizeOldSpecPostBaseHalantOrder(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.normalizeInitialConsonantSyllableOrder(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.normalizeOldSpecBengaliRaViramaOrder(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
}

fn applyPref(input: Input, plan: ?gsub.feature.LookupPlan) !void {
    input.glyph_stage_substituted.clearRetainingCapacity();
    try input.glyph_stage_substituted.resize(
        input.allocator,
        input.glyph_ids.items.len,
    );
    @memset(input.glyph_stage_substituted.items, false);
    var options = input.options.*;
    options.glyph_stage_substituted = input.glyph_stage_substituted;
    if (plan) |cached| try executor.applyPlanAfterRunProof(
        input.font,
        input.context,
        cached,
        input.glyph_ids,
        options,
        input.gdef_metadata,
    ) else try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        indic.prefFeatureApplications(),
        input.glyph_ids,
        options,
        input.gdef_metadata,
    );
    indic.recordPrefSubstitutions(
        input.glyph_source_indices.items,
        input.glyph_stage_substituted.items,
        input.source_pref_substituted.items,
    );
    input.glyph_stage_substituted.clearRetainingCapacity();
}

fn reorderAfterPref(input: Input) void {
    indic.reorderPreBaseMatras(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.reorderPrefGlyphs(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.source_pref_substituted.items,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    _ = indic.markInitialMatraGlyphSources(
        input.source_features.items,
        input.glyph_source_indices.items,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
}

fn reorderAfterReph(input: Input) void {
    indic.reorderRephs(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.reorderLogicalRepha(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.reorderBeforeSubscriptVowels(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
    indic.reorderBengaliBelowVowelsAfterBase(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.codepoints.items,
        input.lookup_options.script_tag,
    );
}
