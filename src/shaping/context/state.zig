//! Private cache and output ownership for `Engine`.

const std = @import("std");

const cache = @import("cache/root.zig");
const output_mod = @import("output.zig");
const stats_mod = @import("stats.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");

pub const State = struct {
    allocator: std.mem.Allocator,
    output: output_mod.Buffer,
    styled_output: styled_buffer.Buffer,
    glyph_metrics: cache.GlyphMetricsCache,
    glyph_indices: cache.GlyphIndexCache,
    font_fallback: cache.FontFallbackCache,
    gdef_metadata: cache.GdefMetadataCache,
    gsub_table_proofs: cache.GsubTableProofCache,
    gpos_table_proofs: cache.GposTableProofCache,
    lookup_selection: cache.LookupSelectionCache,
    kern_lookups: cache.KernLookupCache,
    shaped_runs: cache.ShapedRunCache,
    cache_font_data: bool,
    cache_shaped_runs: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        cache_font_data: bool,
        cache_shaped_runs: bool,
    ) State {
        return .{
            .allocator = allocator,
            .output = output_mod.Buffer.init(allocator),
            .styled_output = styled_buffer.Buffer.init(allocator),
            .glyph_metrics = cache.GlyphMetricsCache.init(allocator),
            .glyph_indices = cache.GlyphIndexCache.init(allocator),
            .font_fallback = cache.FontFallbackCache.init(allocator),
            .gdef_metadata = cache.GdefMetadataCache.init(allocator),
            .gsub_table_proofs = cache.GsubTableProofCache.init(allocator),
            .gpos_table_proofs = cache.GposTableProofCache.init(allocator),
            .lookup_selection = cache.LookupSelectionCache.init(allocator),
            .kern_lookups = cache.KernLookupCache.init(allocator),
            .shaped_runs = cache.ShapedRunCache.init(allocator),
            .cache_font_data = cache_font_data,
            .cache_shaped_runs = cache_shaped_runs,
        };
    }

    pub fn deinit(self: *State) void {
        self.detachPlanCaches();
        self.styled_output.deinit();
        self.output.deinit();
        self.shaped_runs.deinit();
        self.kern_lookups.deinit();
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
        // Unlike ordinary output reset, an explicit cache clear must also
        // release text-owned Unicode analyses and reset their counters.
        self.styled_output.analysis.clear();
        self.shaped_runs.clear();
        self.kern_lookups.clear();
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
            .kern_lookups = stats_mod.counter(
                self.kern_lookups.hits,
                self.kern_lookups.misses,
            ),
            .shaped_runs = stats_mod.counter(
                self.shaped_runs.hits,
                self.shaped_runs.misses,
            ),
            .bidi_paragraphs = stats_mod.counter(
                self.styled_output.analysis.bidi_hits,
                self.styled_output.analysis.bidi_misses,
            ),
        };
    }

    pub fn shapedRunCache(
        self: *State,
    ) ?*cache.ShapedRunCache {
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
        self.output.kern_lookup_cache = &self.kern_lookups;
        self.output.glyph_metrics_cache = &self.glyph_metrics;
        self.output.glyph_index_cache = &self.glyph_indices;
    }

    fn detachPlanCaches(self: *State) void {
        self.output.gdef_metadata_cache = null;
        self.output.gsub_table_proof_cache = null;
        self.output.gpos_table_proof_cache = null;
        self.output.lookup_selection_cache = null;
        self.output.kern_lookup_cache = null;
        self.output.glyph_metrics_cache = null;
        self.output.glyph_index_cache = null;
    }
};
