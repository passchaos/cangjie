//! Commit one direct or accelerator-backed chaining class match.

const std = @import("std");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const match = @import("match.zig");
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
    matched: *const match.Match,
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
    switch (matched.action) {
        .records => |record_list| try records.apply(
            Executor,
            view,
            glyphs,
            record_list.offset,
            record_list.count,
            input,
            allocator,
            run,
        ),
        .nested_lookup => |lookup_index| {
            _ = try Executor.applyNested(
                view,
                glyphs,
                input[0],
                lookup_index,
                allocator,
                run,
            );
        },
    }
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
