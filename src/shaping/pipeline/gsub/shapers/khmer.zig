//! Khmer split-matra decomposition, reordering, and feature stages.

const std = @import("std");

const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const khmer = @import("../../../../khmer.zig");
const ligature_provenance =
    @import("../../../../ligature_provenance.zig");
const cluster_safety = @import("../../../cluster_safety.zig");
const executor = @import("../executor.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: *std.ArrayList(u21),
    clusters: *std.ArrayList(usize),
    source_ends: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    source_features: *std.ArrayList(u32),
    source_syllables: *std.ArrayList(u8),
    source_boundaries: *cluster_safety.SourceBoundaries,
    base_gsub_options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
    dotted_circle_glyph: GlyphId,
};

pub const supports = khmer.shouldShape;

pub fn run(input: Input) !void {
    try khmer.decomposeSplitMatraSources(
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
    );
    try input.source_features.resize(
        input.allocator,
        input.codepoints.items.len,
    );
    try input.source_syllables.resize(
        input.allocator,
        input.codepoints.items.len,
    );
    khmer.markSourceFeatures(
        input.source_features.items,
        input.source_syllables.items,
        input.codepoints.items,
    );
    var options = input.base_gsub_options;
    options.source_codepoints = input.codepoints.items;
    input.source_boundaries.bindSourceByteStarts(input.clusters.items);
    options.source_features = input.source_features.items;
    options.source_syllables = input.source_syllables.items;

    try khmer.insertDottedCirclesForBrokenMarks(
        input.allocator,
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.source_syllables.items,
        input.codepoints.items,
        input.dotted_circle_glyph,
    );
    khmer.reorder(
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.source_syllables.items,
        input.codepoints.items,
    );
    khmer.assignJoinerClusterOwners(
        input.glyph_cluster_indices,
        input.glyph_source_indices,
        input.codepoints.items,
    );
    try gsub.validateScriptShaperRunMetadata(
        options,
        input.glyph_ids.items.len,
    );
    inline for (.{ .basic, .final }) |stage| {
        try executor.applyMergedAfterRunProof(
            input.font,
            input.context,
            input.table_proved,
            khmer.featureApplications(stage),
            input.glyph_ids,
            options,
            input.gdef_metadata,
        );
    }
}
