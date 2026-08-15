//! Generic GSUB/AAT execution, including Hangul Jamo feature setup.

const std = @import("std");

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
    options: *gsub.LookupOptions,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
};

pub fn run(input: Input) !void {
    try applyHangul(input);

    const apply_aat_substitution =
        input.font.hasAatSubstitutionForShaping() and
        (!input.lookup_options.writing_mode.isVertical() or
            !input.font.hasGsubTableForShaping());
    if (apply_aat_substitution) {
        return try input.font.applyAatSubstitutionForShaping(
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
            try input.font.applyGsubWithOptionsUsingGdefAfterProof(
                input.glyph_ids,
                input.allocator,
                input.options.*,
                input.gdef_metadata,
            );
        }
    } else {
        try input.font.applyGsubWithOptionsUsingGdefForShaping(
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
            try input.font
                .applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(
                &.{application},
                input.glyph_ids,
                input.allocator,
                input.options.*,
                input.gdef_metadata,
            );
        } else {
            try input.font
                .applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(
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
    if (input.table_proved) {
        try input.font.applyGsubWithOptionsUsingGdefAfterProof(
            input.glyph_ids,
            input.allocator,
            options,
            input.gdef_metadata,
        );
    } else {
        try input.font.applyGsubWithOptionsUsingGdefForShaping(
            input.glyph_ids,
            input.allocator,
            options,
            input.gdef_metadata,
        );
    }
}
