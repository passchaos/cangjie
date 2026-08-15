//! Stable aggregate cache counters exposed by `TextContext`.

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
    shaped_runs: Counter = .{},
};

pub fn counter(hits: usize, misses: usize) Counter {
    return .{ .hits = hits, .misses = misses };
}
