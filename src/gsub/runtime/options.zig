//! Concrete GSUB execution options shared by OpenType and AAT substitution.
//!
//! This is a source-level value type: callers construct it directly, copy it
//! for one feature/lookup stage, and borrow all sidecars through ordinary
//! pointers and slices. No ABI handle or erased ownership boundary is implied.

const std = @import("std");
const acceleration = @import("../accelerator/root.zig");
const cluster_safety = @import("../../shaping/cluster_safety.zig");
const GlyphId = @import("../../glyph.zig").GlyphId;
const ligature_provenance = @import("../../ligature_provenance.zig");
const shape_profile = @import("../../shape_profile.zig");
const shaping_metadata = @import("../../shaping_metadata.zig");
const unicode = @import("../../unicode.zig");

pub const Direction = enum { ltr, rtl };

pub const UserFeature = struct {
    values: []const u32,
    tag: u32,
    value: u32 = 1,
    include_script_candidates: bool = true,
};

pub const Options = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    text_direction: Direction = .ltr,
    features: []const unicode.FeatureOverride = &.{},
    normalized_variation_coords: []const f32 = &.{},
    vertical: bool = false,
    apply_all_if_unselected: bool = true,
    glyph_classes: ?[]const u16 = null,
    mark_attach_classes: ?[]const u16 = null,
    mark_filtering_sets: ?[]const []const GlyphId = null,
    active_mark_filtering_set: ?u16 = null,
    /// Source ownership parallel to the mutable post-cmap glyph stream.
    glyph_source_indices: ?*std.ArrayList(usize) = null,
    /// Cluster ownership remains distinct from original source ownership.
    glyph_cluster_indices: ?*std.ArrayList(usize) = null,
    cluster_level: shaping_metadata.ClusterLevel = .monotone_graphemes,
    /// Cumulative GSUB substitution state parallel to the glyph stream.
    glyph_substituted: ?*std.ArrayList(bool) = null,
    /// Per-feature-stage substitution state parallel to the glyph stream.
    glyph_stage_substituted: ?*std.ArrayList(bool) = null,
    ligature_components: ?*ligature_provenance.Store = null,
    source_boundaries: ?*cluster_safety.SourceBoundaries = null,
    /// Source-level feature assignment used by ranged and joining features.
    source_features: ?[]const u32 = null,
    /// User feature-range eligibility, kept independent from script-shaper
    /// candidate masks. A staged lookup must satisfy both when both are set.
    user_feature: ?*const UserFeature = null,
    /// Rare staged-range execution chooses the union predicate below at lookup
    /// cursors. Ordinary shaping leaves this false and retains its branch-free
    /// source-only eligibility path.
    use_user_feature_at_cursor: bool = false,
    active_source_feature: ?u32 = null,
    active_source_feature_mask: u32 = 0,
    active_feature_value: u32 = 1,
    active_feature_random: bool = false,
    random_state: ?*u32 = null,
    /// Source-level syllables stop contextual matching at orthographic units.
    source_syllables: ?[]const u8 = null,
    match_source_syllable: bool = false,
    match_source_syllable_lookups: ?[]const u16 = null,
    /// Original scalars indexed by `glyph_source_indices`.
    source_codepoints: ?[]const u21 = null,
    /// Whole-run proof that the source contains no default-ignorable scalar.
    /// Ligature traversal can skip Unicode visibility work while retaining
    /// source codepoints for provenance classification.
    run_has_default_ignorables: ?bool = null,
    visible_variation_selectors: bool = false,
    /// Whether AAT receives a physically source-reversed glyph stream.
    aat_buffer_reversed: bool = false,
    active_auto_zwnj: bool = true,
    active_auto_zwj: bool = true,
    /// Preselected LookupList indexes owned by a caller-side cache.
    selected_lookups: ?[]const u16 = null,
    /// Additional LookupList indexes enabled by one OpenType JSTF suggestion.
    /// Font validation guarantees ascending, duplicate-free indexes.
    enabled_lookups: []const u16 = &.{},
    /// Ascending LookupList indexes suppressed by one JSTF suggestion.
    disabled_lookups: []const u16 = &.{},
    /// Per-lookup sidecars built for the exact validated table range.
    lookup_accelerators: ?[]const acceleration.Lookup = null,
    /// Mutation epoch shared by all lookup stages in one top-level run.
    glyph_mutation_generation: ?*usize = null,
    /// Shared HarfBuzz-compatible resource guards.
    operations_left: ?*usize = null,
    max_glyph_count: ?usize = null,
    assume_validated: bool = false,
    shape_profile: ?*shape_profile.ShapeStageProfile = null,
    profile_fast_path: bool = false,
    profile_io: ?std.Io = null,
    /// Number of SequenceLookupRecord edges enclosing the current lookup.
    /// Top-level lookup execution always starts at zero.
    context_depth: usize = 0,
};
