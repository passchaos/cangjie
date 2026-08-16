//! Predecoded SingleSubst records for chaining coverage execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const direct_single = @import("../../../direct/single/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
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
    for (subtable.fast_records[0..subtable.fast_record_count]) |record| {
        if (record.sequence_index >= input_indices.len) return false;
        const target = input_indices[record.sequence_index];
        if (target >= glyphs.items.len) continue;
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
