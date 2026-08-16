//! ChainContextPos format 2 class-rule execution.

const std = @import("std");
const class_context = @import("../../../../../opentype/class_context.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
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

const max_region_glyphs = 64;

const MatchContext = struct {
    view: View,
    backtrack_class_def: usize,
    input_class_def: usize,
    lookahead_class_def: usize,
    lookup_flag: u16,
    run: Options,

    fn classValue(
        self: *MatchContext,
        role: class_context.ClassRole,
        glyph: GlyphId,
    ) Error!u16 {
        const class_def = switch (role) {
            .backtrack => self.backtrack_class_def,
            .input => self.input_class_def,
            .lookahead => self.lookahead_class_def,
        };
        return table.class_def.value(self.view, class_def, glyph);
    }

    fn skipsGlyph(
        self: *MatchContext,
        glyphs: []const GlyphId,
        glyph_index: usize,
    ) bool {
        return run_matching.matchSkipsGlyph(
            self.lookup_flag,
            self.run,
            glyphs,
            glyph_index,
        );
    }
};

const MatchWindow = class_context.MatchWindow(
    MatchContext,
    Error,
    error.UnsupportedGpos,
    max_region_glyphs,
    MatchContext.classValue,
    MatchContext.skipsGlyph,
);

pub fn collect(
    view: View,
    subtable: positioning.lookup.contextual.ChainingClass,
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
        const result = try collectAtResult(
            view,
            subtable,
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
    subtable: positioning.lookup.contextual.ChainingClass,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!bool {
    return (try collectAtResult(
        view,
        subtable,
        glyphs,
        position,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    )).matched;
}

fn collectAtResult(
    view: View,
    subtable: positioning.lookup.contextual.ChainingClass,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!Result {
    if (position >= glyphs.len) return .{};
    if (run_matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[position],
    )) return .{};
    if (try table.coverage.index(
        view,
        subtable.coverage_offset,
        glyphs[position],
    ) == null) return .{};
    const input_class = try table.class_def.value(
        view,
        subtable.input_class_def,
        glyphs[position],
    );
    if (input_class >= subtable.sets.count) return .{};
    const set =
        try subtable.sets.resolve(view, input_class) orelse return .{};
    return collectRuleSet(
        view,
        set,
        subtable,
        glyphs,
        position,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    );
}

fn collectRuleSet(
    view: View,
    set_offset: usize,
    subtable: positioning.lookup.contextual.ChainingClass,
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
    var context = MatchContext{
        .view = view,
        .backtrack_class_def = subtable.backtrack_class_def,
        .input_class_def = subtable.input_class_def,
        .lookahead_class_def = subtable.lookahead_class_def,
        .lookup_flag = lookup_flag,
        .run = run,
    };
    var window = MatchWindow.init(&context, glyphs, position);
    for (0..set.rule_count) |rule_index| {
        const rule = try positioning.lookup.contextual.parseChainingRule(
            view,
            try set.ruleOffset(view, rule_index),
        );
        if (rule.backtrack_count > max_region_glyphs) {
            return error.UnsupportedGpos;
        }

        var matched = true;
        for (0..rule.backtrack_count) |index| {
            const expected =
                try view.readU16(rule.backtrack_values_pos + index * 2);
            const actual = (try window.backtrackClassAt(index)) orelse {
                matched = false;
                break;
            };
            if (actual != expected) {
                matched = false;
                break;
            }
        }
        if (!matched or rule.input_count == 0) continue;
        if (rule.input_count > max_region_glyphs) {
            return error.UnsupportedGpos;
        }

        const input = (try window.inputIndices(
            rule.input_count,
        )) orelse continue;
        for (1..rule.input_count) |index| {
            const expected =
                try view.readU16(rule.input_values_pos + (index - 1) * 2);
            const actual = (try window.inputClassAt(index)) orelse {
                matched = false;
                break;
            };
            if (actual != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;

        if (rule.lookahead_count > max_region_glyphs) {
            return error.UnsupportedGpos;
        }
        const lookahead_start: usize = rule.input_count;
        const lookahead_end =
            lookahead_start + @as(usize, rule.lookahead_count);
        if (!try window.ensureForwardCount(lookahead_end)) continue;
        for (0..rule.lookahead_count) |index| {
            const expected =
                try view.readU16(rule.lookahead_values_pos + index * 2);
            const actual =
                (try window.lookaheadClassAt(lookahead_start + index)) orelse {
                    matched = false;
                    break;
                };
            if (actual != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;

        try output.safety.markChainingContext(
            allocator,
            &run,
            window.backtrack_indices[0..rule.backtrack_count],
            input,
            window.forward_indices[lookahead_start..lookahead_end],
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
