//! Stable aggregate cache counters exposed by `Engine`.

pub const Counter = struct {
    hits: usize = 0,
    misses: usize = 0,
};

pub const Stats = struct {
    glyph_indices: Counter = .{},
    glyph_metrics: Counter = .{},
    font_fallback: Counter = .{},
    gdef_metadata: Counter = .{},
    gsub_table_proofs: Counter = .{},
    gpos_table_proofs: Counter = .{},
    lookup_selection: Counter = .{},
    kern_lookups: Counter = .{},
    shaped_runs: Counter = .{},
    /// Reusable UAX #9 resolution keyed by exact text and base direction.
    bidi_paragraphs: Counter = .{},
};

pub fn counter(hits: usize, misses: usize) Counter {
    return .{ .hits = hits, .misses = misses };
}
