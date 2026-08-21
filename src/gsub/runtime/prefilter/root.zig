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
pub const Error = table.coverage.Error;
pub const Options = filtering.Options;
pub const View = table.View;

/// Per-run unfiltered superset summary used only for necessary-condition
/// rejection. Lookup flags and source feature masks can remove candidates,
/// never add a glyph that is absent from this digest, so one summary per
/// mutation epoch is sufficient and avoids rescanning long runs for each
/// feature stage. False positives remain authoritative exact-matcher work.
pub const Cache = struct {
    cached: GlyphDigest = undefined,
    valid: bool = false,
    generation: usize = 0,

    pub fn init() Cache {
        return .{};
    }

    pub fn digestForRun(
        self: *Cache,
        glyphs: []const GlyphId,
        lookup_flag: u16,
        run: Options,
    ) GlyphDigest {
        _ = lookup_flag;
        const generation = if (run.glyph_mutation_generation) |value|
            value.*
        else
            0;
        if (generation != self.generation) {
            // Cardinality-changing substitutions may introduce glyphs not in
            // the prior superset, so start a new epoch rather than risking a
            // false-negative rejection.
            self.valid = false;
            self.generation = generation;
        }
        if (self.valid) return self.cached;
        var result = GlyphDigest.empty();
        for (glyphs) |glyph| result.add(glyph);
        self.cached = result;
        self.valid = true;
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
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
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
            if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) {
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
