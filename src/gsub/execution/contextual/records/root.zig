//! OpenType SequenceLookupRecord execution over a mutable matched input map.

const std = @import("std");
const model = @import("../model.zig");
const fast_single = @import("fast_single.zig");
const mapping = @import("mapping.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const validation = @import("validation.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;

pub const Change = model.Change;

/// Apply records in authored order through a concrete nested lookup executor.
///
/// `Executor.applyNested` and `Executor.validateNested` are resolved at
/// comptime. This preserves ordinary source-level types while breaking the
/// dependency cycle between record bookkeeping and recursive GSUB dispatch.
pub fn apply(
    comptime Executor: type,
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    records_offset: usize,
    record_count: usize,
    input_indices: []const usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    if (!view.assume_validated) {
        try validation.validate(
            Executor,
            view,
            records_offset,
            record_count,
            run,
        );
    }
    if (try fast_single.apply(
        view,
        glyphs,
        records_offset,
        record_count,
        input_indices,
        run,
    )) return;

    var map = try mapping.Map.init(input_indices);
    for (0..record_count) |record_index| {
        const record = records_offset + record_index * 4;
        const sequence_index = try view.readU16(record);
        const lookup_index = try view.readU16(record + 2);
        const target_index = map.target(sequence_index) orelse continue;
        if (target_index >= glyphs.items.len) continue;

        const change = try Executor.applyNested(
            view,
            glyphs,
            target_index,
            lookup_index,
            allocator,
            run,
        );
        try map.applyChange(sequence_index, target_index, change);
    }
}

pub const validateReferences = validation.validateReferences;
