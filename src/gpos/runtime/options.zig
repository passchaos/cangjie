//! Concrete source-level options for one GPOS execution run.

const std = @import("std");
const accelerator = @import("../accelerator/root.zig");
const GlyphId = @import("../../glyph.zig").GlyphId;
const positioning = @import("../positioning/root.zig");
const run_metadata = @import("../../shaping/run_metadata.zig");
const shape_profile = @import("../../shape_profile.zig");
const unicode = @import("../../unicode.zig");

pub const Options = struct {
    pub const Direction = enum { ltr, rtl };

    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    direction: Direction = .ltr,
    /// Horizontal positioning snapshots y placement for mark attachment;
    /// vertical positioning snapshots x instead.
    vertical: bool = false,
    features: []const unicode.FeatureOverride = &.{},
    /// Normalized fvar coordinates after avar mapping.
    normalized_variation_coords: []const f32 = &.{},
    gdef_variation_store: ?positioning.VariationStore = null,
    apply_all_if_unselected: bool = true,
    glyph_classes: ?[]const u16 = null,
    mark_attach_classes: ?[]const u16 = null,
    mark_filtering_sets: ?[]const []const GlyphId = null,
    active_mark_filtering_set: ?u16 = null,
    /// Post-GSUB run proof including Unicode marks that GDEF may misclassify.
    run_may_have_mark_attachments: ?bool = null,
    /// A known-false value bypasses default-ignorable source classification.
    run_has_default_ignorables: ?bool = null,
    run_metadata: *const run_metadata.Positioning = &.{},
    visible_variation_selectors: bool = false,
    /// Preselected LookupList indexes owned by a caller-side cache.
    selected_lookups: ?[]const u16 = null,
    /// Additional LookupList indexes enabled by one OpenType JSTF suggestion.
    /// Font validation guarantees ascending, duplicate-free indexes.
    enabled_lookups: []const u16 = &.{},
    /// Ascending LookupList indexes suppressed by one JSTF suggestion.
    disabled_lookups: []const u16 = &.{},
    unsafe_glyphs: ?*run_metadata.UnsafeGlyphs = null,
    /// Borrowed, immutable full slice from `gpos.buildLookupAccelerators`. The
    /// original sidecar allocation and the exact backing font-byte allocation
    /// and table range used to build it must remain alive and unchanged for
    /// this run. Identity checks compare addresses and ranges, not contents,
    /// and therefore cannot make mutated or freed storage safe to use.
    lookup_accelerators: ?[]const accelerator.Lookup = null,
    assume_validated: bool = false,
    shape_profile: ?*shape_profile.ShapeStageProfile = null,
    profile_io: ?std.Io = null,
    /// Number of PosLookupRecord edges enclosing the current lookup.
    /// Top-level lookup execution always starts at zero.
    context_depth: usize = 0,
};
