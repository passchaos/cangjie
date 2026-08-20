//! Commit one matched ChainContextSubst format-1 glyph rule.

const std = @import("std");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const matching = @import("matching.zig");
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
    matched: *const matching.Match,
    allocator: std.mem.Allocator,
    run: Options,
) Error!model.ApplyResult {
    const input = matched.inputSlice();
    try safety.markRegions(
        allocator,
        run,
        matched.backtrackSlice(),
        input,
        matched.lookaheadSlice(),
    );

    const glyph_count_before = glyphs.items.len;
    try records.apply(
        Executor,
        view,
        glyphs,
        matched.records_offset,
        matched.record_count,
        input,
        allocator,
        run,
    );
    return .{
        .matched = true,
        .next_pos = model.nextPositionAfterMutation(
            input[input.len - 1] + 1,
            position,
            glyph_count_before,
            glyphs.items.len,
        ),
    };
}
