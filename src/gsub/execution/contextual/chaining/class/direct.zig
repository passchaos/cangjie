//! Direct ChainContextSubst format-2 parsing and execution.

const std = @import("std");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const commit = @import("commit.zig");
const match = @import("match.zig");
const matching = @import("matching.zig");
const window = matching.window;
const model = @import("../../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;

const Parsed = struct {
    subtable_offset: usize,
    coverage_offset: usize,
    class_defs: window.ClassDefs,
    set_count: u16,
};

pub fn subtable(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    const parsed = try parse(view, subtable_offset);
    var position: usize = 0;
    while (position < glyphs.items.len) {
        const result = try parsedAt(
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
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    // Nested contextual dispatch may probe a subtable at a source-filtered
    // position. Preserve the no-match contract without parsing irrelevant
    // payloads; whole-subtable execution still parses once before scanning.
    if (!eligible(glyphs.items, position, lookup_flag, run)) return .{};
    return parsedAt(
        Executor,
        view,
        try parse(view, subtable_offset),
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    );
}

fn parsedAt(
    comptime Executor: type,
    view: View,
    parsed: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (!eligible(glyphs.items, position, lookup_flag, run)) return .{};
    if (try table.coverage.index(
        view,
        parsed.coverage_offset,
        glyphs.items[position],
    ) == null) return .{};
    const input_class = try table.class_def.value(
        view,
        parsed.class_defs.input,
        glyphs.items[position],
    );
    if (input_class >= parsed.set_count) return .{};
    const set_relative = try view.readU16(
        parsed.subtable_offset + 12 + @as(usize, input_class) * 2,
    );
    if (set_relative == 0) return .{};

    var matched: match.Match = undefined;
    if (!try matching.directRuleSet(
        view,
        parsed.subtable_offset + set_relative,
        parsed.class_defs,
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

fn parse(view: View, subtable_offset: usize) Error!Parsed {
    return .{
        .subtable_offset = subtable_offset,
        .coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .class_defs = .{
            .backtrack = (try table.offset.optional16(
                view,
                subtable_offset,
                try view.readU16(subtable_offset + 4),
            )) orelse table.class_def.empty_offset,
            .input = try table.offset.required16(
                view,
                subtable_offset,
                try view.readU16(subtable_offset + 6),
            ),
            .lookahead = (try table.offset.optional16(
                view,
                subtable_offset,
                try view.readU16(subtable_offset + 8),
            )) orelse table.class_def.empty_offset,
        },
        .set_count = try view.readU16(subtable_offset + 10),
    };
}

fn eligible(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) bool {
    return position < glyphs.len and
        filtering.lookupCursorAllowsGlyph(run, position) and
        !filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        );
}
