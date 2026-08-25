//! Shared input and state records for final positioning output.

const std = @import("std");

const aat_kerx = @import("../../../../aat_kerx.zig");
const cluster_safety = @import("../../../cluster_safety.zig");
const cache = @import("../../../context/cache/root.zig");
const scratch_mod = @import("../../../context/scratch.zig");
const Font = @import("../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const GlyphPosition =
    @import("../../../../layout/glyph_position.zig").GlyphPosition;
const gpos = @import("../../../../gpos.zig");
const pipeline_types = @import("../../types.zig");
const run_metadata = @import("../../../run_metadata.zig");
const ShapeStageProfile =
    @import("../../../../shape_profile.zig").ShapeStageProfile;

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    metrics_cache: ?*cache.GlyphMetricsCache,
    glyph_index_cache: ?*cache.GlyphIndexCache,
    source_boundaries: *cluster_safety.SourceBoundaries,
    gdef_metadata: GdefLookupMetadata,
    gpos_adjustments: []const gpos.Adjustment,
    gpos_unsafe_glyphs: run_metadata.UnsafeGlyphs,
    kerx_lookup: ?@import("../../../../font.zig").KerxLookupForShaping,
    kern_lookup: ?@import("../../../../font.zig").KernLookupForShaping,
    kerx_adjustments: []const aat_kerx.Adjustment,
    kerning_enabled: bool,
    has_gpos_attachments: bool,
    has_kerx_state_attachments: bool,
    has_gpos_positioning: bool,
    run_may_have_mark_attachments: bool,
    has_default_ignorable: bool,
    early_zero_mark_shape: bool,
    fallback_mark_enabled: bool,
    invisible_glyph_id: GlyphId,
    arabic_joining_features: ?[]const u32,
    cluster_base: usize,
    font_size: f32,
    scale: f32,
    options: pipeline_types.LookupOptions,
    output: *std.ArrayList(GlyphPosition),
    scratch: *scratch_mod.ShapeScratch,
    profile: ?*ShapeStageProfile,
    profile_io: ?std.Io,
};

pub const Result = struct {
    segment_glyph_start: usize,
};
