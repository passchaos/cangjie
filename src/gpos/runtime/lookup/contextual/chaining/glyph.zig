//! ChainContextPos format 1 glyph-rule execution.

const std = @import("std");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const matching = @import("../matching.zig");
const model = @import("../model.zig");
const output = @import("../../../output/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const run_matching = @import("../../../matching.zig");
const table = @import("../../../../table/root.zig");

const Adjustment = model.Adjustment;
const ApplyRecordsFn = model.ApplyRecordsFn;
const Error = model.Error;
const Options = model.Options;
const Result = model.Result;
const View = model.View;

pub fn collect(
    view: View,
    subtable: positioning.lookup.contextual.ChainingGlyph,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        var next_position = position + 1;
        defer position = next_position;
        if (run_matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        )) continue;
        const coverage = try table.coverage.index(
            view,
            subtable.coverage_offset,
            glyphs[position],
        ) orelse continue;
        if (coverage >= subtable.sets.count) continue;
        const set =
            try subtable.sets.resolve(view, coverage) orelse continue;
        const result = try collectRuleSet(
            view,
            set,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        );
        if (result.matched) {
            next_position = @max(next_position, result.next_pos);
        }
    }
}

pub fn collectAt(
    view: View,
    subtable: positioning.lookup.contextual.ChainingGlyph,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!bool {
    if (position >= glyphs.len) return false;
    if (run_matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[position],
    )) return false;
    const coverage = try table.coverage.index(
        view,
        subtable.coverage_offset,
        glyphs[position],
    ) orelse return false;
    if (coverage >= subtable.sets.count) return false;
    const set =
        try subtable.sets.resolve(view, coverage) orelse return false;
    return (try collectRuleSet(
        view,
        set,
        glyphs,
        position,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    )).matched;
}

fn collectRuleSet(
    view: View,
    set_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!Result {
    const set =
        try positioning.lookup.contextual.parseRuleSet(view, set_offset);
    for (0..set.rule_count) |rule_index| {
        const rule = try positioning.lookup.contextual.parseChainingRule(
            view,
            try set.ruleOffset(view, rule_index),
        );

        var backtrack_indices_buffer: [64]usize = undefined;
        if (rule.backtrack_count > backtrack_indices_buffer.len) {
            return error.UnsupportedGpos;
        }
        const backtrack = backtrack_indices_buffer[0..rule.backtrack_count];
        if (!matching.backtrack(
            glyphs,
            position,
            lookup_flag,
            run,
            backtrack,
        )) continue;
        if (!try glyphSequenceMatches(
            view,
            glyphs,
            backtrack,
            rule.backtrack_values_pos,
        )) continue;

        if (rule.input_count == 0) continue;
        var input_indices_buffer: [64]usize = undefined;
        if (rule.input_count > input_indices_buffer.len) {
            return error.UnsupportedGpos;
        }
        const input = input_indices_buffer[0..rule.input_count];
        if (!matching.forward(
            glyphs,
            position,
            lookup_flag,
            run,
            input,
        )) continue;
        if (!try glyphSequenceMatches(
            view,
            glyphs,
            input[1..],
            rule.input_values_pos,
        )) continue;

        var lookahead_indices_buffer: [64]usize = undefined;
        if (rule.lookahead_count > lookahead_indices_buffer.len) {
            return error.UnsupportedGpos;
        }
        const lookahead = lookahead_indices_buffer[0..rule.lookahead_count];
        if (!matching.forward(
            glyphs,
            input[rule.input_count - 1] + 1,
            lookup_flag,
            run,
            lookahead,
        )) continue;
        if (!try glyphSequenceMatches(
            view,
            glyphs,
            lookahead,
            rule.lookahead_values_pos,
        )) continue;

        try output.safety.markChainingContext(
            allocator,
            &run,
            backtrack,
            input,
            lookahead,
        );
        try applyRecords(
            view,
            rule.records.records_pos,
            rule.records.count,
            input,
            glyphs,
            adjustments,
            allocator,
            run,
        );
        return .{
            .matched = true,
            .next_pos = input[rule.input_count - 1] + 1,
        };
    }
    return .{};
}

fn glyphSequenceMatches(
    view: View,
    glyphs: []const GlyphId,
    indices: []const usize,
    values_pos: usize,
) Error!bool {
    for (indices, 0..) |glyph_index, value_index| {
        if (glyphs[glyph_index] !=
            try view.readU16(values_pos + value_index * 2))
        {
            return false;
        }
    }
    return true;
}
