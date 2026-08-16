//! Cheap necessary-condition proofs for GSUB lookup execution.
//!
//! Prefilters may report a possible match that later exact matching rejects,
//! but they must never hide a valid substitution. The cache is scoped to one
//! run and invalidates all summaries whenever the shared mutation epoch moves.

const std = @import("std");
const chaining_coverage = @import("../../accelerator/build/chaining_coverage/parser.zig");
const filtering = @import("../filtering.zig");
const GlyphDigest = @import("../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const table = @import("../../table/root.zig");

const exact_scan_threshold = 64;
const max_cache_entries = 16;

pub const Error = table.coverage.Error;
pub const Options = filtering.Options;
pub const View = table.View;

/// Per-run summaries keyed by every option that changes glyph visibility.
pub const Cache = struct {
    const Entry = struct {
        lookup_flag: u16,
        active_mark_filtering_set: ?u16,
        active_source_feature: ?u32,
        active_source_feature_mask: u32,
        digest: GlyphDigest,
    };

    entries: [max_cache_entries]Entry = undefined,
    len: usize = 0,
    generation: usize = 0,

    pub fn init() Cache {
        // `digestForRun` only reads entries below `len`, and every such entry
        // is assigned before `len` advances. Avoid clearing the digest array
        // for every shaping run.
        var cache: Cache = undefined;
        cache.len = 0;
        cache.generation = 0;
        return cache;
    }

    pub fn digestForRun(
        self: *Cache,
        glyphs: []const GlyphId,
        lookup_flag: u16,
        run: Options,
    ) GlyphDigest {
        const generation = if (run.glyph_mutation_generation) |value|
            value.*
        else
            0;
        if (generation != self.generation) {
            // Cardinality-changing substitutions make incremental maintenance
            // error-prone. The small cache is cheaper and safer to drop whole.
            self.len = 0;
            self.generation = generation;
        }

        for (self.entries[0..self.len]) |entry| {
            if (entry.lookup_flag == lookup_flag and
                entry.active_mark_filtering_set ==
                    run.active_mark_filtering_set and
                entry.active_source_feature == run.active_source_feature and
                entry.active_source_feature_mask ==
                    run.active_source_feature_mask)
            {
                return entry.digest;
            }
        }

        const result = digest(glyphs, lookup_flag, run);
        if (self.len < self.entries.len) {
            self.entries[self.len] = .{
                .lookup_flag = lookup_flag,
                .active_mark_filtering_set = run.active_mark_filtering_set,
                .active_source_feature = run.active_source_feature,
                .active_source_feature_mask = run.active_source_feature_mask,
                .digest = result,
            };
            self.len += 1;
        }
        return result;
    }
};

/// Summarize glyphs visible to one lookup and source-feature scope.
pub fn digest(
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) GlyphDigest {
    var result = GlyphDigest.empty();
    for (glyphs, 0..) |glyph, glyph_index| {
        if (!filtering.sourceFeatureAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        result.add(glyph);
    }
    return result;
}

/// Prove that a coverage-only chaining lookup cannot match this run.
pub fn chainingCoverageLookupMayMatch(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (glyphs.len == 0) return false;
    // Short words cannot amortize digest construction. Scan their first-input
    // coverages exactly and reserve approximate summaries for longer runs.
    if (glyphs.len < exact_scan_threshold) {
        return chainingCoverageLookupMayMatchByScan(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            lookup_flag,
            run,
        );
    }

    const run_digest = digest(glyphs, lookup_flag, run);
    if (run_digest.isEmpty()) return false;
    for (0..subtable_count) |subtable_index| {
        const subtable_offset = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        const coverage_offset =
            try chaining_coverage.firstInputCoverage(
                view,
                subtable_offset,
            ) orelse continue;
        const coverage_digest = try table.coverage.digest(
            view,
            coverage_offset,
        );
        if (coverage_digest.mayIntersect(run_digest)) return true;
    }
    return false;
}

fn chainingCoverageLookupMayMatchByScan(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    for (0..subtable_count) |subtable_index| {
        const subtable_offset = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        const coverage_offset =
            try chaining_coverage.firstInputCoverage(
                view,
                subtable_offset,
            ) orelse continue;
        for (glyphs, 0..) |glyph, glyph_index| {
            if (!filtering.sourceFeatureAllowsGlyph(run, glyph_index)) {
                continue;
            }
            if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
            if (try table.coverage.index(view, coverage_offset, glyph) != null) {
                return true;
            }
        }
    }
    return false;
}

/// Search an exact sorted candidate set without applying lookup filtering.
///
/// This is deliberately a permissive necessary-condition check: filtering a
/// non-leading ligature component here could create a false negative.
pub fn hasAnyGlyph(
    glyphs: []const GlyphId,
    sorted_candidates: []const GlyphId,
) bool {
    for (glyphs) |glyph| {
        if (std.sort.binarySearch(
            GlyphId,
            sorted_candidates,
            glyph,
            glyphIdOrder,
        ) != null) return true;
    }
    return false;
}

fn glyphIdOrder(target: GlyphId, item: GlyphId) std.math.Order {
    return std.math.order(target, item);
}
