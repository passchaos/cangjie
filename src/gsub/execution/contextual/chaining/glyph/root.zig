//! ChainContextSubst format-1 glyph execution surface.

const std = @import("std");
const accelerated = @import("accelerated.zig");
const shaping_sections = @import("../../../../../shaping_sections.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const commit = @import("commit.zig");
const matching = @import("matching.zig");
const model = @import("../../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;

pub const acceleratedLookup = accelerated.lookup;
pub const acceleratedAt = accelerated.at;
pub const supportsAcceleratedLookup = accelerated.supportsLookup;

pub fn subtable(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
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
        position = if (result.matched)
            @max(position + 1, result.next_pos)
        else
            position + 1;
    }
}

pub noinline fn at(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) linksection(shaping_sections.isolated_hotpaths) Error!model.ApplyResult {
    if (position >= glyphs.items.len or
        !filtering.lookupCursorAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs.items[position],
        ))
    {
        return .{};
    }

    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const coverage = try table.coverage.index(
        view,
        coverage_offset,
        glyphs.items[position],
    ) orelse return .{};
    const set_count = try view.readU16(subtable_offset + 4);
    if (coverage >= set_count) return .{};
    const set_relative = try view.readU16(
        subtable_offset + 6 + coverage * 2,
    );
    if (set_relative == 0) return .{};

    var matched: matching.Match = undefined;
    if (!try matching.ruleSet(
        view,
        subtable_offset + set_relative,
        glyphs.items,
        position,
        lookup_flag,
        run,
        &matched,
    )) return .{};
    return commit.apply(
        Executor,
        view,
        glyphs,
        position,
        &matched,
        allocator,
        run,
    );
}
