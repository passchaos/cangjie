//! Universal Shaping Engine syllable stages and post-substitution reordering.

const std = @import("std");

const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const ligature_provenance =
    @import("../../../../ligature_provenance.zig");
const use_shaper = @import("../../../../use_shaper.zig");
const executor = @import("../executor.zig");
const features = @import("../features.zig");
const pipeline_types = @import("../../types.zig");
const unicode = @import("../../../../unicode.zig");
const arabic_joining = @import("arabic/joining.zig");

pub const supports = use_shaper.shouldShape;

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: []const u21,
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    glyph_stage_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_features: *std.ArrayList(u32),
    source_syllables: *std.ArrayList(u8),
    source_rphf_substituted: *std.ArrayList(bool),
    source_pref_substituted: *std.ArrayList(bool),
    base_gsub_options: gsub.LookupOptions,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
    dotted_circle_glyph: GlyphId,
};

pub fn run(input: Input) !void {
    try resizeSourceSidecars(input);
    try use_shaper.markSourceFeatures(
        input.allocator,
        input.source_features.items,
        input.source_syllables.items,
        input.codepoints,
        input.glyph_source_indices.items,
    );
    if (usesArabicJoiningMasks(input.lookup_options.script_tag)) {
        arabic_joining.overlayNativeOrder(
            input.source_features.items,
            input.codepoints,
            input.glyph_source_indices.items,
        );
    }
    var use_options = input.base_gsub_options;
    use_options.source_features = input.source_features.items;
    use_options.source_syllables = input.source_syllables.items;

    try applyDirectionFeatures(input, use_options);
    try executor.apply(
        input.font,
        input.context,
        input.table_proved,
        use_shaper.defaultPreprocessingFeatureApplications(),
        input.glyph_ids,
        use_options,
        input.gdef_metadata,
    );
    try applyObservedStage(
        input,
        use_options,
        use_shaper.rphfFeatureApplications(),
        .rphf,
    );
    try applyObservedStage(
        input,
        use_options,
        use_shaper.prefFeatureApplications(),
        .pref,
    );

    try gsub.validateScriptShaperRunMetadata(
        use_options,
        input.glyph_ids.items.len,
    );
    try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        use_shaper.basicFeatureApplications(),
        input.glyph_ids,
        use_options,
        input.gdef_metadata,
    );
    if (use_shaper.hasBrokenSyllable(input.source_syllables.items)) {
        try use_shaper.insertDottedCirclesForBrokenSyllables(
            input.allocator,
            input.glyph_ids,
            input.glyph_source_indices,
            input.glyph_cluster_indices,
            input.glyph_substituted,
            input.ligature_components,
            input.source_syllables.items,
            input.source_rphf_substituted.items,
            input.source_pref_substituted.items,
            input.codepoints,
            input.dotted_circle_glyph,
        );
    }
    use_shaper.reorderGlyphs(
        input.glyph_ids.items,
        input.glyph_source_indices.items,
        input.glyph_cluster_indices.items,
        input.glyph_substituted.items,
        input.ligature_components.infos.items,
        input.source_syllables.items,
        input.source_rphf_substituted.items,
        input.source_pref_substituted.items,
        input.codepoints,
    );
    try executor.applyAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        use_shaper.topographicalFeatureApplications(),
        input.glyph_ids,
        use_options,
        input.gdef_metadata,
    );
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        use_shaper.finalFeatureApplications(),
        input.glyph_ids,
        use_options,
        input.gdef_metadata,
    );
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        use_shaper.typographicFeatureApplications(),
        input.glyph_ids,
        input.base_gsub_options,
        input.gdef_metadata,
    );
}

const ObservedStage = enum { rphf, pref };

fn resizeSourceSidecars(input: Input) !void {
    const source_len = input.codepoints.len;
    try input.source_features.resize(input.allocator, source_len);
    try input.source_syllables.resize(input.allocator, source_len);
    try input.source_rphf_substituted.resize(input.allocator, source_len);
    try input.source_pref_substituted.resize(input.allocator, source_len);
    @memset(input.source_rphf_substituted.items, false);
    @memset(input.source_pref_substituted.items, false);
}

fn applyObservedStage(
    input: Input,
    use_options: gsub.LookupOptions,
    applications: []const gsub.FeatureApplication,
    stage: ObservedStage,
) !void {
    input.glyph_stage_substituted.clearRetainingCapacity();
    try input.glyph_stage_substituted.resize(
        input.allocator,
        input.glyph_ids.items.len,
    );
    @memset(input.glyph_stage_substituted.items, false);
    var options = use_options;
    options.glyph_stage_substituted = input.glyph_stage_substituted;
    try executor.apply(
        input.font,
        input.context,
        input.table_proved,
        applications,
        input.glyph_ids,
        options,
        input.gdef_metadata,
    );
    switch (stage) {
        .rphf => use_shaper.recordRphfSubstitutions(
            input.glyph_source_indices.items,
            input.glyph_stage_substituted.items,
            input.source_features.items,
            input.source_syllables.items,
            input.source_rphf_substituted.items,
        ),
        .pref => use_shaper.recordPrefSubstitutions(
            input.glyph_source_indices.items,
            input.glyph_stage_substituted.items,
            input.source_pref_substituted.items,
        ),
    }
    input.glyph_stage_substituted.clearRetainingCapacity();
}

fn applyDirectionFeatures(
    input: Input,
    use_options: gsub.LookupOptions,
) !void {
    if (!usesDirectionFeatures(input.lookup_options.script_tag)) return;
    var applications: [2]gsub.FeatureApplication = undefined;
    var count: usize = 0;
    const candidates = if (input.lookup_options.direction == .rtl)
        [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("rtla") },
            .{ .tag = unicode.tag("rtlm") },
        }
    else
        [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("ltra") },
            .{ .tag = unicode.tag("ltrm") },
        };
    for (candidates) |application| {
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        applications[count] = application;
        count += 1;
    }
    try executor.applyMerged(
        input.font,
        input.context,
        input.table_proved,
        applications[0..count],
        input.glyph_ids,
        use_options,
        input.gdef_metadata,
    );
}

fn usesArabicJoiningMasks(
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    return script_tag == .phag;
}

fn usesDirectionFeatures(
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    return script_tag == .phag;
}
