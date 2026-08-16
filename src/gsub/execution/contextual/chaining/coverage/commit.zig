//! Apply one matched chaining coverage substitution and safety metadata.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const model = @import("../../model.zig");
const records = @import("../../records/root.zig");
const safety = @import("../../safety.zig");
const fast_single = @import("fast_single.zig");
const matching = @import("matching.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Parsed = accelerator.model.ChainingCoverageSubtable;
const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    subtable: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    regions: *const matching.Regions,
    allocator: std.mem.Allocator,
    run: Options,
) Error!model.ApplyResult {
    const input = regions.inputSlice();
    try safety.markRegions(
        allocator,
        run,
        regions.backtrackSlice(),
        input,
        regions.lookaheadSlice(),
    );
    if (try fast_single.apply(view, subtable, glyphs, input, run)) {
        return .{
            .matched = true,
            .next_pos = input[input.len - 1] + 1,
        };
    }

    const glyph_count_before = glyphs.items.len;
    try records.apply(
        Executor,
        view,
        glyphs,
        subtable.records_pos,
        subtable.subst_count,
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
