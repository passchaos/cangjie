const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const aat_kerx = @import("aat_kerx.zig");
const cluster_safety = @import("shaping/cluster_safety.zig");
const gpos = @import("gpos.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const unicode = @import("unicode.zig");

pub const ShapeScratch = struct {
    glyph_ids: std.ArrayList(GlyphId) = .empty,
    codepoints: std.ArrayList(u21) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    source_ends: std.ArrayList(usize) = .empty,
    glyph_source_indices: std.ArrayList(usize) = .empty,
    glyph_cluster_indices: std.ArrayList(usize) = .empty,
    glyph_substituted: std.ArrayList(bool) = .empty,
    glyph_stage_substituted: std.ArrayList(bool) = .empty,
    ligature_components: ligature_provenance.Store = .{},
    joining_forms: std.ArrayList(unicode.JoiningForm) = .empty,
    source_features: std.ArrayList(u32) = .empty,
    source_syllables: std.ArrayList(u8) = .empty,
    source_rphf_substituted: std.ArrayList(bool) = .empty,
    source_pref_substituted: std.ArrayList(bool) = .empty,
    glyph_script_positions: std.ArrayList(u8) = .empty,
    glyph_output_indices: std.ArrayList(usize) = .empty,
    stch_actions: std.ArrayList(u8) = .empty,
    source_boundaries: cluster_safety.SourceBoundaries = .{},
    kerx_simple_pair_eligible: std.ArrayList(bool) = .empty,
    kerx_adjustments: std.ArrayList(aat_kerx.Adjustment) = .empty,
    gpos_adjustments: std.ArrayList(gpos.Adjustment) = .empty,
    attachment_links: std.ArrayList(@import("attachment.zig").Link) = .empty,

    pub fn deinit(self: *ShapeScratch, allocator: std.mem.Allocator) void {
        self.attachment_links.deinit(allocator);
        self.gpos_adjustments.deinit(allocator);
        self.kerx_adjustments.deinit(allocator);
        self.kerx_simple_pair_eligible.deinit(allocator);
        self.source_boundaries.deinit(allocator);
        self.stch_actions.deinit(allocator);
        self.glyph_output_indices.deinit(allocator);
        self.glyph_script_positions.deinit(allocator);
        self.source_pref_substituted.deinit(allocator);
        self.source_rphf_substituted.deinit(allocator);
        self.source_syllables.deinit(allocator);
        self.source_features.deinit(allocator);
        self.joining_forms.deinit(allocator);
        self.ligature_components.deinit(allocator);
        self.glyph_stage_substituted.deinit(allocator);
        self.glyph_substituted.deinit(allocator);
        self.glyph_cluster_indices.deinit(allocator);
        self.glyph_source_indices.deinit(allocator);
        self.source_ends.deinit(allocator);
        self.clusters.deinit(allocator);
        self.codepoints.deinit(allocator);
        self.glyph_ids.deinit(allocator);
        self.* = .{};
    }

    pub fn clear(self: *ShapeScratch) void {
        self.glyph_ids.clearRetainingCapacity();
        self.codepoints.clearRetainingCapacity();
        self.clusters.clearRetainingCapacity();
        self.source_ends.clearRetainingCapacity();
        self.glyph_source_indices.clearRetainingCapacity();
        self.glyph_cluster_indices.clearRetainingCapacity();
        self.glyph_substituted.clearRetainingCapacity();
        self.glyph_stage_substituted.clearRetainingCapacity();
        self.ligature_components.clear();
        self.joining_forms.clearRetainingCapacity();
        self.source_features.clearRetainingCapacity();
        self.source_syllables.clearRetainingCapacity();
        self.source_rphf_substituted.clearRetainingCapacity();
        self.source_pref_substituted.clearRetainingCapacity();
        self.glyph_script_positions.clearRetainingCapacity();
        self.glyph_output_indices.clearRetainingCapacity();
        self.stch_actions.clearRetainingCapacity();
        self.kerx_simple_pair_eligible.clearRetainingCapacity();
        self.kerx_adjustments.clearRetainingCapacity();
        self.gpos_adjustments.clearRetainingCapacity();
        self.attachment_links.clearRetainingCapacity();
    }
};
