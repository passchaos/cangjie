//! Commit a matched ContextSubst coverage input sequence.

const std = @import("std");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const model = @import("../../model.zig");
const records = @import("../../records/root.zig");
const safety = @import("../../safety.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    input_indices: []const usize,
    records_offset: usize,
    record_count: usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!model.ApplyResult {
    try safety.markInput(allocator, run, input_indices);
    const glyph_count_before = glyphs.items.len;
    try records.apply(
        Executor,
        view,
        glyphs,
        records_offset,
        record_count,
        input_indices,
        allocator,
        run,
    );
    return .{
        .matched = true,
        .next_pos = model.nextPositionAfterMutation(
            input_indices[input_indices.len - 1] + 1,
            position,
            glyph_count_before,
            glyphs.items.len,
        ),
    };
}
