//! Accelerator-backed ChainContextSubst format-2 execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const shaping_sections = @import("../../../../../shaping_sections.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const commit = @import("commit.zig");
const match = @import("match.zig");
const matching = @import("matching.zig");
const model = @import("../../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Lookup = accelerator.Lookup;
const Subtable = accelerator.model.ChainingClassSubtable;
const View = table.View;

pub fn lookup(
    comptime Executor: type,
    view: View,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    lookup_accelerator: *const Lookup,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;
        if (!eligible(glyphs.items, position, lookup_flag, run)) continue;

        var subtable_index: usize = 0;
        while (subtable_index < subtable_count and
            subtable_index <
                lookup_accelerator.chaining_class_subtables.len) : (subtable_index += 1)
        {
            const parsed =
                lookup_accelerator.chaining_class_subtables[subtable_index];
            if (parsed.rules.len == 0) continue;
            const result = try applyEligibleAt(
                Executor,
                view,
                parsed,
                glyphs,
                position,
                allocator,
                lookup_flag,
                run,
            );
            if (!result.matched) continue;
            next_position = @max(next_position, result.next_pos);
            break;
        }
    }
}

pub fn at(
    comptime Executor: type,
    view: View,
    parsed: Subtable,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (!eligible(glyphs.items, position, lookup_flag, run)) return .{};
    return applyEligibleAt(
        Executor,
        view,
        parsed,
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    );
}

noinline fn applyEligibleAt(
    comptime Executor: type,
    view: View,
    parsed: Subtable,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) linksection(shaping_sections.isolated_hotpaths) Error!model.ApplyResult {
    var matched: match.Match = undefined;
    if (!try matching.acceleratedSubtable(
        view,
        parsed,
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

fn eligible(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) bool {
    return position < glyphs.len and
        filtering.sourceFeatureAllowsGlyph(run, position) and
        !filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        );
}
