//! ContextSubst format-3 direct coverage execution.

const std = @import("std");
const filtering = @import("../../../runtime/filtering.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const model = @import("../model.zig");
const matched = @import("coverage/matched.zig");
const traversal = @import("../../support/context_traversal.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const max_input_glyphs = 64;
const View = table.View;

pub fn applyAt(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (position >= glyphs.items.len or
        !filtering.sourceFeatureAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs.items[position],
        ))
    {
        return .{};
    }
    const input_count = try view.readU16(subtable_offset + 2);
    if (input_count == 0) return .{};
    var input_indices: [max_input_glyphs]usize = undefined;
    if (input_count > input_indices.len) return error.UnsupportedGsub;
    if (!traversal.collectForward(
        glyphs.items,
        position,
        lookup_flag,
        run,
        input_indices[0..input_count],
        false,
        position,
    )) return .{};

    const coverage_positions = subtable_offset + 6;
    for (0..input_count) |input_index| {
        const coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(coverage_positions + input_index * 2),
        );
        if (try table.coverage.index(
            view,
            coverage_offset,
            glyphs.items[input_indices[input_index]],
        ) == null) return .{};
    }
    const record_count = try view.readU16(subtable_offset + 4);
    const records_offset =
        coverage_positions + @as(usize, input_count) * 2;
    return matched.apply(
        Executor,
        view,
        glyphs,
        position,
        input_indices[0..input_count],
        records_offset,
        record_count,
        allocator,
        run,
    );
}
