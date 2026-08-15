//! GPOS collection and OpenType-versus-AAT engine selection.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const cache = @import("../../context/cache/root.zig");
const cluster_safety = @import("../../cluster_safety.zig");
const gpos = @import("../../../gpos.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const pipeline_types = @import("../types.zig");
const run_metadata = @import("../../run_metadata.zig");
const ShapeStageProfile = @import("../../../shape_profile.zig").ShapeStageProfile;

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    lookup_selection_cache: ?*cache.LookupSelectionCache,
    gpos_table_proof_cache: ?*cache.GposTableProofCache,
    glyph_ids: []const GlyphId,
    glyph_source_indices: []const usize,
    codepoints: []const u21,
    glyph_substituted: []const bool,
    ligature_components: *const ligature_provenance.Store,
    source_boundaries: *cluster_safety.SourceBoundaries,
    gdef_metadata: GdefLookupMetadata,
    gpos_script_tag: @import("../../../unicode.zig").OpenTypeScriptTag,
    options: pipeline_types.LookupOptions,
    has_default_ignorable: bool,
    run_may_have_mark_attachments: bool,
    adjustments: *std.ArrayList(gpos.Adjustment),
    profile: ?*ShapeStageProfile,
    profile_io: ?std.Io,
};

pub const Result = struct {
    unsafe_glyphs: run_metadata.UnsafeGlyphs,
    use_kerx_positioning: bool,
};

/// Collect sparse GPOS adjustments unless AAT kerx owns positioning.
///
/// HarfBuzz prefers GPOS when GSUB and GPOS are the active OpenType engines.
/// Horizontal morx deliberately removes GSUB from that pair, allowing kerx to
/// own positioning instead. Keeping this table-level choice beside collection
/// prevents the final glyph loop from rediscovering engine precedence.
pub fn run(input: Input) !Result {
    var unsafe_glyphs = run_metadata.UnsafeGlyphs{};
    const metadata = run_metadata.Positioning{
        .glyph_source_indices = input.glyph_source_indices,
        .source_codepoints = input.codepoints,
        .glyph_substituted = input.glyph_substituted,
        .ligature_components = input.ligature_components,
        .source_boundaries = input.source_boundaries,
    };
    var gpos_options = gpos.LookupOptions{
        .script_tag = input.gpos_script_tag,
        .language_tag = input.options.language_tag,
        .direction = if (input.options.shapingDirection() == .rtl) .rtl else .ltr,
        .vertical = input.options.writing_mode.isVertical(),
        .features = input.options.features,
        .normalized_variation_coords = input.options.normalized_variation_coords,
        .apply_all_if_unselected = false,
        .run_may_have_mark_attachments = input.run_may_have_mark_attachments,
        .run_has_default_ignorables = input.has_default_ignorable,
        .run_metadata = &metadata,
        .unsafe_glyphs = &unsafe_glyphs,
        .shape_profile = input.profile,
        .profile_io = input.profile_io,
        .visible_variation_selectors = input.options.not_found_variation_selector_glyph != null,
    };
    const apply_aat_substitution =
        input.font.hasAatSubstitutionForShaping() and
        (!input.options.writing_mode.isVertical() or
            !input.font.hasGsubTableForShaping());
    const use_kerx_positioning = input.font.hasKerxTableForShaping() and
        (apply_aat_substitution or
            !(input.font.hasGsubTableForShaping() and
                input.font.hasGposTableForShaping()));

    if (!use_kerx_positioning) {
        if (input.lookup_selection_cache) |selection_cache| {
            gpos_options.lookup_accelerators =
                try selection_cache.gposLookupAccelerators(input.font);
            gpos_options.selected_lookups = try selection_cache.gposLookups(
                input.font,
                gpos_options,
                input.gdef_metadata,
            );
        }
        if (input.gpos_table_proof_cache) |proof_cache| {
            try proof_cache.prove(input.font);
            try input.font.collectGposAdjustmentsWithOptionsUsingGdefAfterProof(
                input.glyph_ids,
                input.adjustments,
                input.allocator,
                gpos_options,
                input.gdef_metadata,
            );
        } else {
            try input.font.collectGposAdjustmentsWithOptionsUsingGdefForShaping(
                input.glyph_ids,
                input.adjustments,
                input.allocator,
                gpos_options,
                input.gdef_metadata,
            );
        }
    }
    return .{
        .unsafe_glyphs = unsafe_glyphs,
        .use_kerx_positioning = use_kerx_positioning,
    };
}
