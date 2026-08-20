//! Generic GSUB/AAT execution, including Hangul Jamo feature setup.

const std = @import("std");
const font_shaping = @import("../../../../font.zig").shaping;

const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const ligature_provenance =
    @import("../../../../ligature_provenance.zig");
const executor = @import("../executor.zig");
const features = @import("../features.zig");
const hangul = @import("../hangul.zig");
const pipeline_types = @import("../../types.zig");
const unicode = @import("../../../../unicode.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: []const u21,
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    source_features: *std.ArrayList(u32),
    ligature_components: *ligature_provenance.Store,
    options: *gsub.runtime.Options,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
};

pub fn run(input: Input) !void {
    try applyHangul(input);

    const apply_aat_substitution =
        font_shaping.hasAatSubstitutionForShaping(
            input.font,
        ) and
        (!input.lookup_options.writing_mode.isVertical() or
            !font_shaping.hasGsubTableForShaping(
                input.font,
            ));
    if (apply_aat_substitution) {
        return try font_shaping.applyAatSubstitutionForShaping(
            input.font,
            input.glyph_ids,
            input.allocator,
            input.options.*,
        );
    }

    const needs_value_selection = features.needsValueAwareSelection(
        input.font,
        input.options.features,
        input.options.lookup_accelerators,
        input.table_proved,
    );
    if (input.lookup_options.normalized_variation_coords.len == 0 and
        !needs_value_selection)
    {
        if (input.context.lookup_selection_cache) |selection_cache| {
            input.options.selected_lookups =
                try selection_cache.gsubLookups(
                    input.font,
                    input.options.*,
                    input.gdef_metadata,
                );
        }
    }
    if (input.table_proved) {
        const has_cached_selection =
            if (input.options.selected_lookups) |lookups|
                lookups.len != 0
            else
                false;
        if (has_cached_selection and
            input.context.lookup_selection_cache != null)
        {
            try executor.applyGenericAfterTableProof(
                input.font,
                input.context,
                input.glyph_ids,
                input.options.*,
                input.gdef_metadata,
            );
        } else {
            try font_shaping.applyGsubWithOptionsUsingGdefAfterProof(
                input.font,
                input.glyph_ids,
                input.allocator,
                input.options.*,
                input.gdef_metadata,
            );
        }
    } else {
        try font_shaping.applyGsubWithOptionsUsingGdefForShaping(
            input.font,
            input.glyph_ids,
            input.allocator,
            input.options.*,
            input.gdef_metadata,
        );
    }
    if (features.scriptPositionApplication(
        input.lookup_options.script_position,
    )) |application| {
        if (input.table_proved) {
            try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(
                input.font,
                &.{application},
                input.glyph_ids,
                input.allocator,
                input.options.*,
                input.gdef_metadata,
            );
        } else {
            try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(
                input.font,
                &.{application},
                input.glyph_ids,
                input.allocator,
                input.options.*,
                input.gdef_metadata,
            );
        }
    }
}

fn applyHangul(input: Input) !void {
    if (input.lookup_options.script_tag != .hang or
        !hangul.hasJamo(input.codepoints))
    {
        return;
    }
    try input.source_features.resize(input.allocator, input.codepoints.len);
    if (!hangul.markSourceFeatures(
        input.source_features.items,
        input.codepoints,
    ) or !hangul.featuresCoverAll(
        input.source_features.items,
        input.codepoints,
    )) return;

    hangul.mergeClusters(
        input.glyph_cluster_indices.items,
        input.glyph_source_indices.items,
        input.codepoints,
    );
    var overrides_buf: [32]unicode.FeatureOverride = undefined;
    const overrides = hangul.withJamoFeatures(
        overrides_buf[0..],
        input.options.features,
    ) orelse input.options.features;
    var options = input.options.*;
    options.features = overrides;
    // This preliminary source-scoped pass exists only to apply ljmo/vjmo/tjmo.
    // JSTF enable indexes belong to the complete generic plan below and must
    // not run once here and then a second time in that final plan.
    options.enabled_lookups = &.{};
    if (input.table_proved) {
        try font_shaping.applyGsubWithOptionsUsingGdefAfterProof(
            input.font,
            input.glyph_ids,
            input.allocator,
            options,
            input.gdef_metadata,
        );
    } else {
        try font_shaping.applyGsubWithOptionsUsingGdefForShaping(
            input.font,
            input.glyph_ids,
            input.allocator,
            options,
            input.gdef_metadata,
        );
    }
}
