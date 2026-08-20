//! ChainContextSubst format-3 direct and accelerated execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const commit = @import("commit.zig");
const matching = @import("matching.zig");
const model = @import("../../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Parsed = accelerator.model.ChainingCoverageSubtable;
const View = table.View;

pub fn subtable(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    const parsed = try accelerator.build.chaining_coverage.parser.parse(
        view,
        subtable_offset,
    ) orelse return;
    var position: usize = 0;
    while (position < glyphs.items.len) {
        const result = try at(
            Executor,
            view,
            parsed,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        );
        position = if (result.matched)
            @max(position + 1, result.next_pos)
        else
            position + 1;
    }
}

pub fn at(
    comptime Executor: type,
    view: View,
    parsed: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    var regions: matching.Regions = undefined;
    if (!try matching.full(
        view,
        parsed,
        glyphs.items,
        position,
        lookup_flag,
        run,
        false,
        &regions,
    )) return .{};
    return commit.apply(
        Executor,
        view,
        parsed,
        glyphs,
        position,
        &regions,
        allocator,
        run,
    );
}

pub fn acceleratedAt(
    comptime Executor: type,
    view: View,
    parsed: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    var regions: matching.Regions = undefined;
    if (!try matching.full(
        view,
        parsed,
        glyphs.items,
        position,
        lookup_flag,
        run,
        true,
        &regions,
    )) return .{};
    return commit.apply(
        Executor,
        view,
        parsed,
        glyphs,
        position,
        &regions,
        allocator,
        run,
    );
}

/// Fast path after lookup-level indexes resolved the first three input glyphs.
pub fn acceleratedNoContextAt(
    comptime Executor: type,
    view: View,
    parsed: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    second: ?usize,
    third: ?usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!model.ApplyResult {
    if (parsed.input_count == 0 or parsed.input_count > 3) return .{};
    var regions = matching.Regions{ .input_count = parsed.input_count };
    regions.input[0] = position;
    if (parsed.input_count > 1) {
        regions.input[1] = second orelse return .{};
        if (!try inputCoverageMatches(
            view,
            parsed,
            glyphs.items[regions.input[1]],
            1,
        )) return .{};
    }
    if (parsed.input_count > 2) {
        regions.input[2] = third orelse return .{};
        if (!try inputCoverageMatches(
            view,
            parsed,
            glyphs.items[regions.input[2]],
            2,
        )) return .{};
    }

    return commit.apply(
        Executor,
        view,
        parsed,
        glyphs,
        position,
        &regions,
        allocator,
        run,
    );
}

fn inputCoverageMatches(
    view: View,
    parsed: Parsed,
    glyph: GlyphId,
    input_index: usize,
) table.coverage.Error!bool {
    const predecoded = switch (input_index) {
        1 => parsed.second_input_coverage_offset,
        2 => parsed.third_input_coverage_offset,
        else => 0,
    };
    const coverage_offset = if (predecoded != 0)
        predecoded
    else
        try table.offset.required16(
            view,
            parsed.subtable_offset,
            try view.readU16(parsed.input_offsets_pos + input_index * 2),
        );
    return try table.coverage.index(view, coverage_offset, glyph) != null;
}
