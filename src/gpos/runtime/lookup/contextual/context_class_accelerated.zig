//! Accelerated two-input ContextPos format-2 execution.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const class_context = @import("../../../../opentype/class_context.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("matching.zig");
const model = @import("model.zig");
const output = @import("../../output/root.zig");
const run_matching = @import("../../matching.zig");
const table = @import("../../../table/root.zig");

const Adjustment = model.Adjustment;
const ApplyNestedFn = model.ApplyNestedFn;
const Error = model.Error;
const Options = model.Options;
const Result = model.Result;
const Subtable = accelerator.model.ContextClassSubtable;
const View = model.View;

pub fn collectLookup(
    view: View,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    subtables: []const Subtable,
    comptime applyNested: ApplyNestedFn,
) Error!void {
    // Keep the established GPOS lookup semantics: each subtable traverses
    // the run before the next ordered alternative is considered.
    for (subtables) |subtable| {
        try collectSubtable(
            view,
            subtable,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyNested,
        );
    }
}

pub fn collectSubtable(
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyNested: ApplyNestedFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        var next_position = position + 1;
        defer position = next_position;
        if (run_matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            position,
        )) continue;
        const result = try collectAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyNested,
        );
        if (result.matched) {
            next_position = @max(next_position, result.next_pos);
        }
    }
}

pub fn collectNestedAt(
    view: View,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    subtables: []const Subtable,
    comptime applyNested: ApplyNestedFn,
) Error!bool {
    if (position >= glyphs.len or run_matching.matchSkipsGlyph(
        lookup_flag,
        run,
        glyphs,
        position,
    )) return false;
    for (subtables) |subtable| {
        if ((try collectAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyNested,
        )).matched) return true;
    }
    return false;
}

fn collectAt(
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyNested: ApplyNestedFn,
) Error!Result {
    const coverage = subtable.coverage orelse return .{};
    if (coverage.index(glyphs[position]) == null) return .{};
    const first_class = try table.class_def.value(
        view,
        subtable.class_def_offset,
        glyphs[position],
    );
    const group = class_context.groupForClass(
        subtable.groups,
        first_class,
    ) orelse return .{};
    var indices: [2]usize = undefined;
    if (lookup_flag == 0 and run.run_has_default_ignorables == false) {
        if (position + 1 >= glyphs.len) return .{};
        indices = .{ position, position + 1 };
    } else if (!matching.forward(
        glyphs,
        position,
        lookup_flag,
        run,
        &indices,
    )) return .{};
    const second_class = try table.class_def.value(
        view,
        subtable.class_def_offset,
        glyphs[indices[1]],
    );
    for (subtable.rules[group.start .. group.start + group.len]) |rule| {
        if (rule.second_class != second_class) continue;
        try output.safety.markContext(allocator, &run, &indices);
        const sequence_index = rule.sequence_index;
        if (sequence_index >= indices.len) return error.BadGpos;
        try applyNested(
            view,
            glyphs,
            indices[sequence_index],
            rule.lookup_index,
            adjustments,
            allocator,
            run,
        );
        return .{ .matched = true, .next_pos = indices[1] + 1 };
    }
    return .{};
}
