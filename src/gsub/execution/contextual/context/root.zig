//! OpenType ContextSubst execution surface.

const std = @import("std");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const class = @import("class.zig");
const accelerated_class = @import("class/accelerated.zig");
const coverage = @import("coverage.zig");
const accelerated_coverage = @import("coverage/accelerated.zig");
const glyph = @import("glyph.zig");
const accelerated_class_run = @import("run/accelerated_class.zig");
const lookup_run = @import("run/lookup.zig");
const model = @import("../model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
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
    const format = try view.readU16(subtable_offset);
    if (format < 1 or format > 3) return error.UnsupportedGsub;
    const coverage_input_count = if (format == 3)
        try view.readU16(subtable_offset + 2)
    else
        1;
    var position: usize = 0;
    while (position < glyphs.items.len) {
        const result = try at(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        );
        // Whole-subtable dispatch is used only by the generic mixed Extension
        // path. Preserve its historical traversal: glyph/class formats advance
        // one physical position, while coverage format consumes its matched
        // input width. Position-major whole-lookup dispatch below uses the
        // mutation-adjusted `next_pos` instead.
        position += if (result.matched and format == 3)
            @max(@as(usize, 1), coverage_input_count)
        else
            1;
    }
}

pub fn at(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (position >= glyphs.items.len) return .{};
    return switch (try view.readU16(subtable_offset)) {
        1 => glyph.applyAt(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        2 => class.applyAt(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        3 => coverage.applyAt(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        else => error.UnsupportedGsub,
    };
}

pub fn lookup(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return lookup_run.apply(
        @This(),
        Executor,
        .direct,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn extensionLookup(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return lookup_run.apply(
        @This(),
        Executor,
        .extension,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub const acceleratedClassLookup = accelerated_class_run.apply;
pub const acceleratedCoverageLookup = accelerated_coverage.apply;
pub const acceleratedClassAt = accelerated_class.apply;
