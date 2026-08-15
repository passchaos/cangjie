//! Myanmar syllable preparation, reordering, and staged GSUB application.

const std = @import("std");

const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../gsub.zig");
const ligature_provenance =
    @import("../../../../ligature_provenance.zig");
const myanmar = @import("../../../../myanmar.zig");
const executor = @import("../executor.zig");
const features = @import("../features.zig");
const pipeline_types = @import("../../types.zig");
const unicode = @import("../../../../unicode.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    glyph_script_positions: *std.ArrayList(u8),
    source_syllables: *std.ArrayList(u8),
    codepoints: []const u21,
    base_gsub_options: gsub.LookupOptions,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
    dotted_circle_glyph: GlyphId,
};

pub const supports = myanmar.shouldShape;

pub fn run(input: Input) !void {
    try input.source_syllables.resize(
        input.allocator,
        input.codepoints.len,
    );
    myanmar.markSourceSyllables(
        input.source_syllables.items,
        input.glyph_source_indices.items,
        input.codepoints,
    );
    var myanmar_options = input.base_gsub_options;
    myanmar_options.source_syllables = input.source_syllables.items;

    // Myanmar marks syllables before `locl`/`ccmp`, but those features run
    // before dotted-circle insertion and script reordering.
    try executor.apply(
        input.font,
        input.context,
        input.table_proved,
        &.{ .{ .tag = unicode.tag("locl") }, .{
            .tag = unicode.tag("ccmp"),
        } },
        input.glyph_ids,
        input.base_gsub_options,
        input.gdef_metadata,
    );
    try myanmar.insertDottedCirclesForBrokenSyllables(
        input.allocator,
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.source_syllables.items,
        input.dotted_circle_glyph,
    );
    try myanmar.reorder(
        input.allocator,
        input.glyph_ids,
        input.glyph_source_indices,
        input.glyph_cluster_indices,
        input.glyph_substituted,
        input.ligature_components,
        input.glyph_script_positions,
        input.source_syllables.items,
        input.codepoints,
    );
    try gsub.validateScriptShaperRunMetadata(
        myanmar_options,
        input.glyph_ids.items.len,
    );
    inline for (.{ .rphf, .pref, .blwf, .pstf }) |stage| {
        try executor.applyAfterRunProof(
            input.font,
            input.context,
            input.table_proved,
            myanmar.featureApplications(stage),
            input.glyph_ids,
            myanmar_options,
            input.gdef_metadata,
        );
    }

    var final_buf: [20]gsub.FeatureApplication = undefined;
    var final_count: usize = 0;
    for (myanmar.featureApplications(.final)) |application| {
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        final_buf[final_count] = application;
        final_count += 1;
    }
    for ([_]gsub.FeatureApplication{
        .{ .tag = unicode.tag("rlig") },
        .{ .tag = unicode.tag("calt") },
        .{ .tag = unicode.tag("clig") },
        .{ .tag = unicode.tag("liga") },
    }) |application| {
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        final_buf[final_count] = application;
        final_count += 1;
    }
    final_count += features.appendExplicitOptional(
        final_buf[final_count..],
        input.lookup_options.features,
    );
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        final_buf[0..final_count],
        input.glyph_ids,
        input.base_gsub_options,
        input.gdef_metadata,
    );
}
