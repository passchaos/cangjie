//! Predecoded SingleSubst records for chaining coverage execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const direct_single = @import("../../../direct/single/root.zig");
const limits = @import("../../../../runtime/limits.zig");
const lookup_order = @import("../../../../../opentype/lookup_order.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || limits.Error;
const Parsed = accelerator.model.ChainingCoverageSubtable;
const View = table.View;

pub fn apply(
    view: View,
    subtable: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    input_indices: []const usize,
    run: Options,
) Error!bool {
    if (subtable.fast_record_count == 0) return false;
    const records = subtable.fast_records[0..subtable.fast_record_count];

    // This fast path must either own the complete record array or leave it
    // untouched for the generic executor. In particular, discovering a later
    // out-of-range record after an earlier substitution would cause that
    // earlier record to run twice when we fall back.
    for (records) |record| {
        if (record.sequence_index >= input_indices.len) return false;
    }

    for (records) |record| {
        const target = input_indices[record.sequence_index];
        if (target >= glyphs.items.len) continue;
        // Generic nested dispatch skips disabled records before charging the
        // operation budget. Singles preserve cardinality, so doing the same
        // here cannot invalidate any later precomputed target.
        if (lookup_order.contains(run.disabled_lookups, record.lookup_index)) {
            continue;
        }
        try limits.consumeNested(run);
        _ = try direct_single.acceleratedAt(
            view,
            record.accelerator,
            glyphs,
            target,
            run,
        );
    }
    return true;
}
