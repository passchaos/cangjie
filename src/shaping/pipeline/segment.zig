//! One-font shaping segment pipeline from source mapping through final output.
//!
//! This is the execution boundary below paragraph, fallback-run, and bidi
//! orchestration. It consumes a concrete reusable output owner and resolved
//! lookup properties; no layout policy or runtime callback crosses the API.

const std = @import("std");

const font_shaping = @import("../../font.zig").shaping;
const Font = @import("../../font.zig").Font;
const GdefLookupMetadata = @import("../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../glyph.zig").GlyphId;
const gpos = @import("../../gpos.zig");
const gsub = @import("../../gsub.zig");
const ligature_provenance = @import("../../ligature_provenance.zig");
const cache = @import("../context/cache/root.zig");
const context_output = @import("../context/output.zig");
const shaping_metadata = @import("../../shaping_metadata.zig");
const normalization = @import("normalization/root.zig");
const normalize_marks = normalization.marks;
const normalize_native = normalization.native;
const normalize_decompose = normalization.decompose;
const source_pipeline = @import("source/root.zig");
const gsub_pipeline = @import("gsub/root.zig");
const gsub_executor = gsub_pipeline.executor;
const gsub_features = gsub_pipeline.features;
const gsub_fraction = gsub_pipeline.fraction;
const gsub_hangul = gsub_pipeline.hangul;
const gsub_arabic = gsub_pipeline.shapers.arabic;
const gsub_generic = gsub_pipeline.shapers.generic;
const gsub_indic = gsub_pipeline.shapers.indic;
const gsub_khmer = gsub_pipeline.shapers.khmer;
const gsub_myanmar = gsub_pipeline.shapers.myanmar;
const gsub_use = gsub_pipeline.shapers.use;
const positioning = @import("positioning/root.zig");
const position_adjustments = positioning.adjustments;
const position_attachments = positioning.attachments;
const position_collect = positioning.collect;
const position_engine = positioning.engine;
const position_output = positioning.output;
const position_policy = positioning.policy;
const stch_feature = @import("../features/stch/root.zig");
const pipeline_types = @import("types.zig");
const use_shaper = @import("../../use_shaper.zig");
const unicode = @import("../../unicode.zig");
const GlyphPosition = @import("../../layout/glyph_position.zig").GlyphPosition;
const shape_profile_mod = @import("../../shape_profile.zig");

const GlyphIndexCache = cache.GlyphIndexCache;
const GlyphMetricsCache = cache.GlyphMetricsCache;
const ResolvedLookupOptions = pipeline_types.ResolvedLookupOptions;
const glyphIndexWithOptionalCache = source_pipeline.glyphIndex;

pub const Input = struct {
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    buffer: *context_output.Buffer,
    text: []const u8,
    font_size: f32,
    cluster_base: usize,
    lookup_options: ResolvedLookupOptions,
};

fn gdefMetadataForShaping(
    font: *const Font,
    allocator: std.mem.Allocator,
    metadata_cache: ?*cache.GdefMetadataCache,
    out_owned: *?GdefLookupMetadata,
) !*const GdefLookupMetadata {
    if (metadata_cache) |stored| return try stored.metadata(font);
    out_owned.* = try font_shaping.gdefLookupMetadataForShaping(
        font,
        allocator,
    );
    return &out_owned.*.?;
}

pub fn run(input: Input) !void {
    const font = input.font;
    const metrics_cache = input.metrics_cache;
    const glyph_index_cache = input.glyph_index_cache;
    const buffer = input.buffer;
    const text = input.text;
    const font_size = input.font_size;
    const cluster_base = input.cluster_base;
    const resolved_lookup_options = input.lookup_options;
    const scale = font_size / @as(f32, @floatFromInt(font.units_per_em));
    var selected_lookup_options = resolved_lookup_options.lookup;
    const explicit_script_tag = if (resolved_lookup_options.lookup.script_tag_explicit) resolved_lookup_options.lookup.script_tag else null;
    const layout_scripts: cache.LayoutScriptSelections = if (buffer.lookup_selection_cache) |selection_cache|
        try selection_cache.layoutScripts(font, resolved_lookup_options.lookup.script, explicit_script_tag)
    else
        .{
            .gsub = try font_shaping.selectGsubScriptForShaping(font, resolved_lookup_options.lookup.script, explicit_script_tag),
            .gpos = try font_shaping.selectGposScriptForShaping(font, resolved_lookup_options.lookup.script, explicit_script_tag),
        };
    const gsub_script = layout_scripts.gsub;
    const gpos_script = layout_scripts.gpos;
    if (gsub_script.tag) |selected_tag| {
        selected_lookup_options.script_tag = selected_tag;
    }
    const gpos_script_tag = gpos_script.tag orelse selected_lookup_options.script_tag;
    const scratch = &buffer.shape_scratch;
    const glyph_ids = &scratch.glyph_ids;
    const codepoints = &scratch.codepoints;
    const clusters = &scratch.clusters;
    const source_ends = &scratch.source_ends;
    const glyph_source_indices = &scratch.glyph_source_indices;
    const glyph_cluster_indices = &scratch.glyph_cluster_indices;
    const glyph_substituted = &scratch.glyph_substituted;
    const glyph_stage_substituted = &scratch.glyph_stage_substituted;
    const ligature_components = &scratch.ligature_components;
    const joining_forms = &scratch.joining_forms;
    const source_features = &scratch.source_features;
    const user_feature_values = &scratch.user_feature_values;
    const source_syllables = &scratch.source_syllables;
    const source_rphf_substituted = &scratch.source_rphf_substituted;
    const source_pref_substituted = &scratch.source_pref_substituted;
    const glyph_script_positions = &scratch.glyph_script_positions;
    const stch_actions = &scratch.stch_actions;
    const source_boundaries = &scratch.source_boundaries;

    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const cmap_start = shape_profile_mod.now(shape_profile, profile_io);
    const source_result = try source_pipeline.populate(
        buffer.allocator,
        font,
        glyph_index_cache,
        scratch,
        text,
        cluster_base,
        resolved_lookup_options.all_ascii,
        selected_lookup_options,
    );
    if (!resolved_lookup_options.all_ascii) {
        try normalize_decompose.missingPrecomposed(
            buffer.allocator,
            font,
            glyph_index_cache,
            scratch,
        );
    }
    const has_default_ignorable = source_result.has_default_ignorable;
    var default_ignorable_invisible_glyph_id =
        source_result.default_ignorable_invisible_glyph_id;
    if (shape_profile) |p| {
        p.cmap_ns += shape_profile_mod.elapsed(cmap_start, profile_io);
        p.glyph_count += glyph_ids.items.len;
    }
    source_boundaries.reset(cluster_base, text.len, clusters.items);

    selected_lookup_options.run_has_decimal_number = source_result.run_has_decimal_number;
    selected_lookup_options.run_has_letter = source_result.run_has_letter;
    const lookup_options = selected_lookup_options;

    const shape_in_native_direction = lookup_options.shouldShapeInNativeDirection();
    const shaping_direction = if (shape_in_native_direction)
        if (lookup_options.nativeHorizontalDirection()) |native|
            if (native == .rtl)
                pipeline_types.TextDirection.rtl
            else
                pipeline_types.TextDirection.ltr
        else
            lookup_options.direction
    else
        lookup_options.direction;
    if (shape_in_native_direction) {
        normalize_native.reverse(scratch);
    }

    const gdef_start = shape_profile_mod.now(shape_profile, profile_io);
    var owned_gdef_metadata: ?GdefLookupMetadata = null;
    const gdef_metadata = try gdefMetadataForShaping(font, buffer.allocator, buffer.gdef_metadata_cache, &owned_gdef_metadata);
    if (shape_profile) |p| p.gdef_ns += shape_profile_mod.elapsed(gdef_start, profile_io);
    defer if (owned_gdef_metadata) |*metadata| metadata.deinit(buffer.allocator);

    var hangul_feature_overrides_buf: [17]unicode.FeatureOverride = undefined;
    const gsub_feature_overrides = if (gsub_hangul.needsDefaultDisabledCalt(codepoints.items))
        gsub_features.withDefaultDisabledCalt(hangul_feature_overrides_buf[0..], lookup_options.features) orelse lookup_options.features
    else
        lookup_options.features;

    var gsub_random_state: u32 = 1;
    var gsub_run_limits = try gsub.runtime.Limits.init(glyph_ids.items.len);
    // Keep source metadata parallel to glyph ids through GSUB. GPOS MarkLigPos
    // needs the original component sources for a ligature glyph; otherwise a
    // mark after a ligature can only guess a component from post-substitution
    // mark order.
    var gsub_options = gsub.runtime.Options{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        // GSUB consumes the buffer after optional native-direction reversal.
        // Using the paragraph base direction here would select the wrong
        // directional and contextual features for an RTL script item embedded
        // in an LTR paragraph.
        .text_direction = gsubDirection(shaping_direction),
        .features = gsub_feature_overrides,
        .normalized_variation_coords = lookup_options.normalized_variation_coords,
        .vertical = lookup_options.writing_mode.isVertical(),
        .apply_all_if_unselected = false,
        .glyph_source_indices = glyph_source_indices,
        .glyph_cluster_indices = glyph_cluster_indices,
        .cluster_level = lookup_options.cluster_level orelse .monotone_characters,
        .glyph_substituted = glyph_substituted,
        .ligature_components = ligature_components,
        .source_boundaries = source_boundaries,
        // The LTR ASCII cmap fast path proves there is no CGJ, joiner, or
        // default-ignorable scalar for contextual/ligature skipping. Omit the
        // source slice so generic Latin GSUB avoids scanning the identity
        // source map merely to re-prove those codepoint bounds.
        .source_codepoints = if (resolved_lookup_options.all_ascii and lookup_options.direction == .ltr)
            null
        else
            codepoints.items,
        .run_has_default_ignorables = has_default_ignorable,
        .shape_profile = shape_profile,
        .profile_fast_path = buffer.profile_fast_path,
        .profile_io = profile_io,
        .visible_variation_selectors = lookup_options.not_found_variation_selector_glyph != null,
        .random_state = &gsub_random_state,
        .aat_buffer_reversed = shape_in_native_direction,
        .enabled_lookups = if (lookup_options.jstf_modifications) |mods|
            mods.gsub_enable
        else
            &.{},
        .disabled_lookups = if (lookup_options.jstf_modifications) |mods|
            mods.gsub_disable
        else
            &.{},
    };
    // Script shapers split one logical GSUB pass into several feature stages.
    // Keep HarfBuzz-style operation and growth limits shared across every
    // stage, including nested contextual lookups, rather than resetting the
    // safety envelope for each feature.
    gsub_run_limits.applyTo(&gsub_options);
    const gsub_start = shape_profile_mod.now(shape_profile, profile_io);
    const gsub_after_proof = if (buffer.gsub_table_proof_cache) |proof_cache| proof: {
        try proof_cache.prove(font);
        break :proof true;
    } else false;
    if (buffer.lookup_selection_cache) |selection_cache| {
        gsub_options.lookup_accelerators = try selection_cache.gsubLookupAccelerators(font);
    }
    if (gsub_after_proof) {
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
    }
    const gsub_context = gsub_executor.Context{
        .allocator = buffer.allocator,
        .lookup_selection_cache = buffer.lookup_selection_cache,
        .feature_ranges = lookup_options.feature_ranges,
        .feature_overrides = lookup_options.features,
        .source_byte_starts = clusters.items,
        .user_feature_values = if (lookup_options.feature_ranges.len != 0)
            user_feature_values
        else
            null,
    };
    if (lookup_options.beginning_of_text and
        !(if (lookup_options.logical_context) |context|
            context.hasBefore()
        else
            lookup_options.context_before.len != 0) and
        codepoints.items.len != 0 and
        unicode.isUnicodeMarkCodepoint(codepoints.items[0]) and
        lookup_options.script_tag != .mym2)
    {
        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try insertBeginningDottedCircle(
            buffer.allocator,
            glyph_ids,
            codepoints,
            clusters,
            source_ends,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            dotted_circle_glyph,
        );
        gsub_options.source_codepoints = codepoints.items;
        source_boundaries.bindSourceByteStarts(clusters.items);
    }
    const use_shape =
        gsub_use.supports(lookup_options.script_tag) and
        codepoints.items.len != 0;
    const myanmar_shape =
        gsub_myanmar.supports(lookup_options.script_tag) and
        codepoints.items.len != 0;
    const khmer_shape =
        gsub_khmer.supports(lookup_options.script_tag) and
        codepoints.items.len != 0;
    const early_zero_mark_shape = use_shape or myanmar_shape;
    var ran_generic_gsub = false;
    if (use_shape or myanmar_shape) {
        // Cluster ownership for source text must be established before vowel
        // constraints inject synthetic U+25CC sources that do not exist in the
        // original UTF-8 byte stream.
        try use_shaper.assignShapingClusterOwners(
            buffer.allocator,
            text,
            cluster_base,
            clusters.items,
            codepoints.items,
            glyph_cluster_indices.items,
        );
        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        if (use_shape) {
            try use_shaper.insertVowelConstraintDottedCircles(
                buffer.allocator,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                dotted_circle_glyph,
                false,
            );
            try use_shaper.decomposeCanonicalSources(
                buffer.allocator,
                font,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                lookup_options.cluster_level orelse .monotone_graphemes,
            );
        }
        gsub_options.source_codepoints = codepoints.items;
        source_boundaries.bindSourceByteStarts(clusters.items);
    }
    // HarfBuzz normalizes every shaping buffer before script-specific GSUB.
    // Keep immutable source codepoints in logical order, but reorder the glyph
    // stream and its parallel metadata by modified combining class. USE then
    // runs its syllable machine over this canonicalized source permutation.
    const mark_normalization_input = normalize_marks.Input{
        .glyph_ids = glyph_ids,
        .glyph_source_indices = glyph_source_indices,
        .glyph_cluster_indices = glyph_cluster_indices,
        .glyph_substituted = glyph_substituted,
        .ligature_components = ligature_components,
        .codepoints = codepoints.items,
    };
    normalize_marks.reorder(
        mark_normalization_input,
        lookup_options.cluster_level,
    );
    var arabic_joining_features: ?[]const u32 = null;
    if (lookup_options.script_tag == .arab) {
        normalize_marks.reorderArabicModifiers(mark_normalization_input);
    }
    if (gsub_arabic.supports(lookup_options.script_tag) and
        codepoints.items.len != 0)
    {
        const arabic_result = try gsub_arabic.run(.{
            .allocator = buffer.allocator,
            .font = font,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .codepoints = codepoints.items,
            .glyph_source_indices = glyph_source_indices.items,
            .ligature_components = ligature_components,
            .source_boundaries = source_boundaries,
            .source_features = source_features,
            .joining_forms = joining_forms,
            .base_gsub_options = gsub_options,
            .lookup_options = lookup_options,
            .gdef_metadata = gdef_metadata.*,
            .shape_in_native_direction = shape_in_native_direction,
            .profile = shape_profile,
            .profile_io = profile_io,
        });
        arabic_joining_features = arabic_result.joining_features;
    } else if (myanmar_shape) {
        const dotted_circle_glyph =
            try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try gsub_myanmar.run(.{
            .allocator = buffer.allocator,
            .font = font,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .glyph_source_indices = glyph_source_indices,
            .glyph_cluster_indices = glyph_cluster_indices,
            .glyph_substituted = glyph_substituted,
            .ligature_components = ligature_components,
            .glyph_script_positions = glyph_script_positions,
            .source_syllables = source_syllables,
            .codepoints = codepoints.items,
            .base_gsub_options = gsub_options,
            .lookup_options = lookup_options,
            .gdef_metadata = gdef_metadata.*,
            .dotted_circle_glyph = dotted_circle_glyph,
        });
    } else if (khmer_shape) {
        const dotted_circle_glyph =
            try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try gsub_khmer.run(.{
            .allocator = buffer.allocator,
            .font = font,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .codepoints = codepoints,
            .clusters = clusters,
            .source_ends = source_ends,
            .glyph_source_indices = glyph_source_indices,
            .glyph_cluster_indices = glyph_cluster_indices,
            .glyph_substituted = glyph_substituted,
            .ligature_components = ligature_components,
            .source_features = source_features,
            .source_syllables = source_syllables,
            .source_boundaries = source_boundaries,
            .base_gsub_options = gsub_options,
            .gdef_metadata = gdef_metadata.*,
            .dotted_circle_glyph = dotted_circle_glyph,
        });
    } else if (use_shape) {
        try gsub_use.run(.{
            .allocator = buffer.allocator,
            .font = font,
            .glyph_index_cache = glyph_index_cache,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .codepoints = codepoints.items,
            .glyph_source_indices = glyph_source_indices,
            .glyph_cluster_indices = glyph_cluster_indices,
            .glyph_substituted = glyph_substituted,
            .glyph_stage_substituted = glyph_stage_substituted,
            .ligature_components = ligature_components,
            .source_features = source_features,
            .source_syllables = source_syllables,
            .source_rphf_substituted = source_rphf_substituted,
            .source_pref_substituted = source_pref_substituted,
            .base_gsub_options = gsub_options,
            .lookup_options = lookup_options,
            .gdef_metadata = gdef_metadata.*,
        });
    } else {
        const indic_shape =
            gsub_indic.supports(lookup_options.script_tag) and
            codepoints.items.len != 0;
        const indic_input = gsub_indic.Input{
            .allocator = buffer.allocator,
            .font = font,
            .glyph_index_cache = glyph_index_cache,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .codepoints = codepoints,
            .clusters = clusters,
            .source_ends = source_ends,
            .glyph_source_indices = glyph_source_indices,
            .glyph_cluster_indices = glyph_cluster_indices,
            .glyph_substituted = glyph_substituted,
            .glyph_stage_substituted = glyph_stage_substituted,
            .ligature_components = ligature_components,
            .source_features = source_features,
            .source_syllables = source_syllables,
            .source_pref_substituted = source_pref_substituted,
            .source_boundaries = source_boundaries,
            .options = &gsub_options,
            .lookup_options = lookup_options,
            .gdef_metadata = gdef_metadata.*,
        };
        const indic_prepared = if (indic_shape)
            try gsub_indic.prepare(indic_input)
        else
            undefined;
        ran_generic_gsub = true;
        try gsub_generic.run(.{
            .allocator = buffer.allocator,
            .font = font,
            .context = gsub_context,
            .table_proved = gsub_after_proof,
            .glyph_ids = glyph_ids,
            .codepoints = codepoints.items,
            .glyph_source_indices = glyph_source_indices,
            .glyph_cluster_indices = glyph_cluster_indices,
            .source_features = source_features,
            .ligature_components = ligature_components,
            .options = &gsub_options,
            .lookup_options = lookup_options,
            .gdef_metadata = gdef_metadata.*,
        });
        if (indic_shape) try gsub_indic.finish(indic_input, indic_prepared);
    }
    // Generic shaping merges JSTF enable indexes into its selected plan before
    // execution. Script shapers own several source-sensitive stages instead;
    // enabled lookups that do not belong to one of those feature maps still
    // need one execution after the script has established joining/syllable
    // state. Disabled indexes remain suppressed in every staged dispatcher.
    if (!ran_generic_gsub) {
        if (lookup_options.jstf_modifications) |mods| {
            if (mods.gsub_enable.len != 0) {
                var enabled_options = gsub_options;
                enabled_options.selected_lookups = mods.gsub_enable;
                enabled_options.enabled_lookups = &.{};
                try font_shaping.applyGsubWithOptionsUsingGdefAfterProof(
                    font,
                    glyph_ids,
                    buffer.allocator,
                    enabled_options,
                    gdef_metadata.*,
                );
            }
        }
    }
    if (gsub_fraction.hasRunnable(codepoints.items)) {
        try source_features.resize(buffer.allocator, codepoints.items.len);
        var fraction_options = gsub_options;
        fraction_options.source_features = source_features.items;
        if (gsub_fraction.mark(source_features.items, codepoints.items, .numerator)) {
            try gsub_executor.applyAfterRunProof(font, gsub_context, gsub_after_proof, &.{.{ .tag = unicode.tag("numr"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
        if (gsub_fraction.mark(source_features.items, codepoints.items, .fraction)) {
            try gsub_executor.applyAfterRunProof(font, gsub_context, gsub_after_proof, &.{.{ .tag = unicode.tag("frac"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
        if (gsub_fraction.mark(source_features.items, codepoints.items, .denominator)) {
            try gsub_executor.applyAfterRunProof(font, gsub_context, gsub_after_proof, &.{.{ .tag = unicode.tag("dnom"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
    }

    // OpenType SingleSubst format 1 is a modulo-16-bit graph. Individual
    // lookups may use IDs above maxp as internal states, but no such transient
    // value may escape the complete GSUB stage into GPOS, metrics, or outlines.
    try font_shaping.validateShapedGlyphRunForShaping(font, glyph_ids.items);

    if (shape_profile) |p| p.gsub_ns += shape_profile_mod.elapsed(gsub_start, profile_io);

    const gpos_adjustments = &scratch.gpos_adjustments;
    const gpos_start = shape_profile_mod.now(shape_profile, profile_io);
    const run_may_have_mark_attachments =
        position_policy.runMayHaveMarkAttachments(
            glyph_ids.items,
            codepoints.items,
            glyph_source_indices.items,
            gdef_metadata.*,
            resolved_lookup_options.all_ascii,
        );
    const position_collection = try position_collect.run(.{
        .allocator = buffer.allocator,
        .font = font,
        .lookup_selection_cache = buffer.lookup_selection_cache,
        .gpos_table_proof_cache = buffer.gpos_table_proof_cache,
        .glyph_ids = glyph_ids.items,
        .glyph_source_indices = glyph_source_indices.items,
        .codepoints = codepoints.items,
        .glyph_substituted = glyph_substituted.items,
        .ligature_components = ligature_components,
        .source_boundaries = source_boundaries,
        .gdef_metadata = gdef_metadata.*,
        .gpos_script_tag = gpos_script_tag,
        .options = lookup_options,
        .has_default_ignorable = has_default_ignorable,
        .run_may_have_mark_attachments = run_may_have_mark_attachments,
        .adjustments = gpos_adjustments,
        .profile = shape_profile,
        .profile_io = profile_io,
    });
    const gpos_unsafe_glyphs = position_collection.unsafe_glyphs;
    const use_kerx_positioning = position_collection.use_kerx_positioning;
    if (lookup_options.jstf_max) |jstf_max| {
        if (!use_kerx_positioning and jstf_max.lookup_offsets.len != 0) {
            const jstf_options = gpos.LookupOptions{
                .script_tag = gpos_script_tag,
                .language_tag = lookup_options.language_tag,
                .direction = if (shaping_direction == .rtl)
                    .rtl
                else
                    .ltr,
                .vertical = lookup_options.writing_mode.isVertical(),
                .normalized_variation_coords = lookup_options.normalized_variation_coords,
                .apply_all_if_unselected = false,
                .run_may_have_mark_attachments = run_may_have_mark_attachments,
                .run_has_default_ignorables = has_default_ignorable,
                .visible_variation_selectors = lookup_options.not_found_variation_selector_glyph != null,
            };
            try font_shaping.collectJstfMaxAdjustmentsForShaping(
                font,
                jstf_max.lookup_offsets,
                glyph_ids.items,
                gpos_adjustments,
                buffer.allocator,
                jstf_options,
                gdef_metadata.*,
            );
        }
    }
    if (shape_profile) |p| p.gpos_ns += shape_profile_mod.elapsed(gpos_start, profile_io);

    const position_start = shape_profile_mod.now(shape_profile, profile_io);
    const position_sort_start = shape_profile_mod.now(shape_profile, profile_io);
    position_adjustments.sortIfNeeded(gpos_adjustments.items);
    if (shape_profile) |p| p.position_sort_ns += shape_profile_mod.elapsed(position_sort_start, profile_io);
    const has_gpos_attachments = position_attachments.hasGpos(gpos_adjustments.items);
    const kerx_adjustments = &scratch.kerx_adjustments;
    const kerx_simple_pair_eligible = &scratch.kerx_simple_pair_eligible;
    const position_engine_plan = try position_engine.prepare(.{
        .allocator = buffer.allocator,
        .font = font,
        .glyph_ids = glyph_ids.items,
        .codepoints = codepoints.items,
        .glyph_source_indices = glyph_source_indices.items,
        .glyph_substituted = glyph_substituted.items,
        .gdef_metadata = gdef_metadata.*,
        .use_kerx_positioning = use_kerx_positioning,
        .has_gpos_attachments = has_gpos_attachments,
        .early_zero_mark_shape = early_zero_mark_shape,
        .options = lookup_options,
        .simple_pair_eligible = kerx_simple_pair_eligible,
        .kerx_adjustments = kerx_adjustments,
    });
    const invisible_glyph_id = if (has_default_ignorable)
        if (default_ignorable_invisible_glyph_id) |glyph|
            glyph
        else resolve: {
            const glyph =
                try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
            default_ignorable_invisible_glyph_id = glyph;
            break :resolve glyph;
        }
    else
        0;
    const output_result = try position_output.emit(.{
        .allocator = buffer.allocator,
        .font = font,
        .metrics_cache = metrics_cache,
        .glyph_index_cache = glyph_index_cache,
        .source_boundaries = source_boundaries,
        .gdef_metadata = gdef_metadata.*,
        .gpos_adjustments = gpos_adjustments.items,
        .gpos_unsafe_glyphs = gpos_unsafe_glyphs,
        .kerx_lookup = position_engine_plan.kerx_lookup,
        .kern_lookup = position_engine_plan.kern_lookup,
        .kerx_adjustments = kerx_adjustments.items,
        .kerning_enabled = position_engine_plan.kerning_enabled,
        .has_gpos_attachments = has_gpos_attachments,
        .has_kerx_state_attachments = position_engine_plan.has_state_attachments,
        .has_gpos_positioning = position_engine_plan.has_gpos_positioning,
        .run_may_have_mark_attachments = run_may_have_mark_attachments,
        .has_default_ignorable = has_default_ignorable,
        .early_zero_mark_shape = early_zero_mark_shape,
        .fallback_mark_enabled = position_engine_plan.fallback_mark_enabled,
        .invisible_glyph_id = invisible_glyph_id,
        .arabic_joining_features = arabic_joining_features,
        .cluster_base = cluster_base,
        .ascii_source = resolved_lookup_options.all_ascii,
        .primary_devanagari_source = source_result.primary_devanagari_block,
        .font_size = font_size,
        .scale = scale,
        .options = lookup_options,
        .output = &buffer.glyphs,
        .scratch = scratch,
        .profile = shape_profile,
        .profile_io = profile_io,
    });
    const segment_glyph_start = output_result.segment_glyph_start;
    // `emit` may resize this list. Reacquire the field after that mutation
    // instead of retaining an interior pointer across a call that receives the
    // complete scratch owner; this also keeps Zig's pointer provenance exact.
    const glyph_output_indices = &scratch.glyph_output_indices;
    const attachment_links = &scratch.attachment_links;
    const has_kerx_attachments = (position_engine_plan.has_state_attachments and
        position_engine_plan.summary.has_cross_stream_adjustment) or
        position_attachments.hasKerxMarks(kerx_adjustments.items);
    if (has_gpos_attachments or has_kerx_attachments) {
        const attachment_start = shape_profile_mod.now(shape_profile, profile_io);
        position_attachments.compact(
            attachment_links.items,
            glyph_output_indices.items,
            buffer.glyphs.items.len - segment_glyph_start,
        );
        position_attachments.propagate(
            buffer.glyphs.items[segment_glyph_start..],
            attachment_links.items[0 .. buffer.glyphs.items.len - segment_glyph_start],
            lookup_options,
        );
        if (shape_profile) |p| p.position_attachment_ns += shape_profile_mod.elapsed(attachment_start, profile_io);
    }
    if (stch_actions.items.len != 0) {
        const stch_start = shape_profile_mod.now(shape_profile, profile_io);
        try stch_feature.apply(
            buffer.allocator,
            &buffer.glyphs,
            stch_actions.items,
            segment_glyph_start,
            lookup_options.direction == .rtl,
            shape_in_native_direction and shaping_direction == .rtl,
            scale,
            font,
            metrics_cache,
            lookup_options.normalized_variation_coords,
        );
        if (shape_profile) |p| p.position_stch_ns += shape_profile_mod.elapsed(stch_start, profile_io);
    }
    if (!lookup_options.writing_mode.isVertical() and
        font_shaping.hasHorizontalTrackingForShaping(font))
    {
        const tracking_start = shape_profile_mod.now(shape_profile, profile_io);
        if (try font_shaping.horizontalTrackingForShaping(font, buffer.allocator, font_size)) |tracking| {
            if (tracking != 0) {
                const tracking_advance = tracking * scale;
                for (buffer.glyphs.items[segment_glyph_start..]) |*glyph| {
                    glyph.x_advance += tracking_advance;
                }
            }
        }
        if (shape_profile) |p| p.position_tracking_ns += shape_profile_mod.elapsed(tracking_start, profile_io);
    }
    if (shape_in_native_direction and shaping_direction == .rtl) {
        const reverse_start = shape_profile_mod.now(shape_profile, profile_io);
        std.mem.reverse(GlyphPosition, buffer.glyphs.items[segment_glyph_start..]);
        if (shape_profile) |p| p.position_reverse_ns += shape_profile_mod.elapsed(reverse_start, profile_io);
    }
    if (shape_profile) |p| p.position_ns += shape_profile_mod.elapsed(position_start, profile_io);
    scratch.may_need_bidi_reorder = source_result.may_need_bidi_reorder;
}

fn gsubDirection(direction: pipeline_types.TextDirection) gsub.runtime.options.Direction {
    return if (direction == .rtl) .rtl else .ltr;
}

fn insertBeginningDottedCircle(
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
) !void {
    if (dotted_circle_glyph == 0 or codepoints.items.len == 0 or glyph_ids.items.len == 0) return;
    const source_start = clusters.items[0];
    const source_end = source_ends.items[0];

    try codepoints.replaceRange(allocator, 0, 0, &.{0x25cc});
    errdefer _ = codepoints.orderedRemove(0);
    try clusters.replaceRange(allocator, 0, 0, &.{source_start});
    errdefer _ = clusters.orderedRemove(0);
    try source_ends.replaceRange(allocator, 0, 0, &.{source_end});
    errdefer _ = source_ends.orderedRemove(0);

    for (glyph_source_indices.items) |*source| source.* += 1;
    for (glyph_cluster_indices.items) |*owner| owner.* += 1;
    ligature_components.shiftSourceIndices(0, 1);

    try shaping_metadata.insert(
        allocator,
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        0,
        dotted_circle_glyph,
        0,
        0,
    );
}

test "beginning item dotted circle creates a synthetic base source" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 3);
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(allocator);
    try codepoints.append(allocator, 0x064e);
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.append(allocator, 0);
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(allocator);
    try source_ends.append(allocator, 2);
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 0);
    var cluster_owners = std.ArrayList(usize).empty;
    defer cluster_owners.deinit(allocator);
    try cluster_owners.append(allocator, 0);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.append(allocator, false);
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.append(allocator, .{});

    try insertBeginningDottedCircle(allocator, &glyphs, &codepoints, &clusters, &source_ends, &sources, &cluster_owners, &substituted, &ligatures, 4);

    try std.testing.expectEqualSlices(GlyphId, &.{ 4, 3 }, glyphs.items);
    try std.testing.expectEqualSlices(u21, &.{ 0x25cc, 0x064e }, codepoints.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, cluster_owners.items);
}

test "GSUB follows the effective native buffer direction" {
    const embedded_arabic = pipeline_types.LookupOptions{
        .script = .arabic,
        .direction = .ltr,
        .reorder_bidi = false,
        .native_direction_shaping = true,
        .run_has_letter = true,
    };
    try std.testing.expectEqual(
        gsub.runtime.options.Direction.rtl,
        gsubDirection(embedded_arabic.shapingDirection()),
    );

    // A numeric-only Arabic-script run deliberately remains in logical LTR
    // order, so its directional GSUB features must remain LTR as well.
    var arabic_number = embedded_arabic;
    arabic_number.run_has_decimal_number = true;
    arabic_number.run_has_letter = false;
    try std.testing.expectEqual(
        gsub.runtime.options.Direction.ltr,
        gsubDirection(arabic_number.shapingDirection()),
    );
}
