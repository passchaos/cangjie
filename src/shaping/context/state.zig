//! Private cache and output ownership for `TextContext`.

const std = @import("std");

const layout = @import("../../layout.zig");
const stats_mod = @import("stats.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    output: layout.LayoutBuffer,
    styled_output: layout.StyledParagraphBuffer,
    glyph_metrics: layout.GlyphMetricsCache,
    glyph_indices: layout.GlyphIndexCache,
    font_fallback: layout.FontFallbackCache,
    gdef_metadata: layout.GdefMetadataCache,
    gsub_table_proofs: layout.GsubTableProofCache,
    gpos_table_proofs: layout.GposTableProofCache,
    lookup_selection: layout.LookupSelectionCache,
    shaped_runs: layout.ShapedRunCache,
    cache_font_data: bool,
    cache_shaped_runs: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        cache_font_data: bool,
        cache_shaped_runs: bool,
    ) State {
        return .{
            .allocator = allocator,
            .output = layout.LayoutBuffer.init(allocator),
            .styled_output = layout.StyledParagraphBuffer.init(allocator),
            .glyph_metrics = layout.GlyphMetricsCache.init(allocator),
            .glyph_indices = layout.GlyphIndexCache.init(allocator),
            .font_fallback = layout.FontFallbackCache.init(allocator),
            .gdef_metadata = layout.GdefMetadataCache.init(allocator),
            .gsub_table_proofs = layout.GsubTableProofCache.init(allocator),
            .gpos_table_proofs = layout.GposTableProofCache.init(allocator),
            .lookup_selection = layout.LookupSelectionCache.init(allocator),
            .shaped_runs = layout.ShapedRunCache.init(allocator),
            .cache_font_data = cache_font_data,
            .cache_shaped_runs = cache_shaped_runs,
        };
    }

    pub fn deinit(self: *State) void {
        self.detachPlanCaches();
        self.styled_output.deinit();
        self.output.deinit();
        self.shaped_runs.deinit();
        self.lookup_selection.deinit();
        self.gpos_table_proofs.deinit();
        self.gsub_table_proofs.deinit();
        self.gdef_metadata.deinit();
        self.font_fallback.deinit();
        self.glyph_indices.deinit();
        self.glyph_metrics.deinit();
        self.* = undefined;
    }

    pub fn clearCaches(self: *State) void {
        self.shaped_runs.clear();
        self.lookup_selection.clear();
        self.gpos_table_proofs.clear();
        self.gsub_table_proofs.clear();
        self.gdef_metadata.clear();
        self.font_fallback.clear();
        self.glyph_indices.clear();
        self.glyph_metrics.clear();
    }

    pub fn stats(self: *const State) stats_mod.Stats {
        return .{
            .glyph_indices = stats_mod.counter(
                self.glyph_indices.hits,
                self.glyph_indices.misses,
            ),
            .glyph_metrics = stats_mod.counter(
                self.glyph_metrics.hits,
                self.glyph_metrics.misses,
            ),
            .font_fallback = stats_mod.counter(
                self.font_fallback.hits,
                self.font_fallback.misses,
            ),
            .gdef_metadata = stats_mod.counter(
                self.gdef_metadata.hits,
                self.gdef_metadata.misses,
            ),
            .gsub_table_proofs = stats_mod.counter(
                self.gsub_table_proofs.hits,
                self.gsub_table_proofs.misses,
            ),
            .gpos_table_proofs = stats_mod.counter(
                self.gpos_table_proofs.hits,
                self.gpos_table_proofs.misses,
            ),
            .lookup_selection = stats_mod.counter(
                self.lookup_selection.hits,
                self.lookup_selection.misses,
            ),
            .shaped_runs = stats_mod.counter(
                self.shaped_runs.hits,
                self.shaped_runs.misses,
            ),
        };
    }

    pub fn shapedRunCache(
        self: *State,
    ) ?*layout.ShapedRunCache {
        return if (self.cache_shaped_runs) &self.shaped_runs else null;
    }

    pub fn bindPlanCaches(self: *State) void {
        if (!self.cache_font_data) {
            self.detachPlanCaches();
            return;
        }
        self.output.gdef_metadata_cache = &self.gdef_metadata;
        self.output.gsub_table_proof_cache = &self.gsub_table_proofs;
        self.output.gpos_table_proof_cache = &self.gpos_table_proofs;
        self.output.lookup_selection_cache = &self.lookup_selection;
    }

    fn detachPlanCaches(self: *State) void {
        self.output.gdef_metadata_cache = null;
        self.output.gsub_table_proof_cache = null;
        self.output.gpos_table_proof_cache = null;
        self.output.lookup_selection_cache = null;
    }
};
