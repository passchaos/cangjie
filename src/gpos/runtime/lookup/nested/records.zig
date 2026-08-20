//! PosLookupRecord preflight and matched-input mapping.

const std = @import("std");
const contextual_model = @import("../contextual/model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const validation = @import("../../../validation/root.zig");

const Adjustment = contextual_model.Adjustment;
const ApplyNestedFn = contextual_model.ApplyNestedFn;
const Error = contextual_model.Error;
const Options = contextual_model.Options;
const View = contextual_model.View;

pub fn apply(
    view: View,
    records_pos: usize,
    record_count: usize,
    input_indices: []const usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
    comptime applyLookup: ApplyNestedFn,
) Error!void {
    if (!view.assume_validated) {
        try validation.lookup.records(
            view,
            records_pos,
            record_count,
            input_indices.len,
        );
        try validation.lookup.recordMarkFilteringSets(
            view,
            records_pos,
            record_count,
            run,
        );
    }

    for (0..record_count) |record_index| {
        const record = records_pos + record_index * 4;
        const sequence_index = try view.readU16(record);
        if (sequence_index >= input_indices.len) return error.BadGpos;
        try applyLookup(
            view,
            glyphs,
            input_indices[sequence_index],
            try view.readU16(record + 2),
            adjustments,
            allocator,
            run,
        );
    }
}
