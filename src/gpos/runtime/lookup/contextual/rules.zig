//! ContextPos glyph and class rule-set matching.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("matching.zig");
const model = @import("model.zig");
const output = @import("../../output/root.zig");
const positioning = @import("../../../positioning/root.zig");
const table = @import("../../../table/root.zig");

const Adjustment = model.Adjustment;
const ApplyRecordsFn = model.ApplyRecordsFn;
const Error = model.Error;
const Options = model.Options;
const Result = model.Result;
const View = model.View;

pub fn collectGlyphSet(
    view: View,
    rule_set_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!Result {
    const set =
        try positioning.lookup.contextual.parseRuleSet(view, rule_set_offset);
    for (0..set.rule_count) |rule_index| {
        const rule = try positioning.lookup.contextual.parseContextRule(
            view,
            try set.ruleOffset(view, rule_index),
        );
        const glyph_count = rule.input_count;
        if (glyph_count == 0) continue;
        var input_indices_buffer: [64]usize = undefined;
        if (glyph_count > input_indices_buffer.len) {
            return error.UnsupportedGpos;
        }
        const input_indices = input_indices_buffer[0..glyph_count];
        if (!matching.forward(
            glyphs,
            position,
            lookup_flag,
            run,
            input_indices,
        )) continue;
        var matched = true;
        for (input_indices[1..], 0..) |glyph_index, input_index| {
            const expected =
                try view.readU16(rule.input_values_pos + input_index * 2);
            if (glyphs[glyph_index] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        try output.safety.markContext(allocator, &run, input_indices);
        try applyRecords(
            view,
            rule.records.records_pos,
            rule.records.count,
            input_indices,
            glyphs,
            adjustments,
            allocator,
            run,
        );
        return .{
            .matched = true,
            .next_pos = input_indices[glyph_count - 1] + 1,
        };
    }
    return .{};
}

pub fn collectClassSet(
    view: View,
    rule_set_offset: usize,
    class_def_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!Result {
    const set =
        try positioning.lookup.contextual.parseRuleSet(view, rule_set_offset);
    for (0..set.rule_count) |rule_index| {
        const rule = try positioning.lookup.contextual.parseContextRule(
            view,
            try set.ruleOffset(view, rule_index),
        );
        const glyph_count = rule.input_count;
        if (glyph_count == 0) continue;
        var input_indices_buffer: [64]usize = undefined;
        if (glyph_count > input_indices_buffer.len) {
            return error.UnsupportedGpos;
        }
        const input_indices = input_indices_buffer[0..glyph_count];
        if (!matching.forward(
            glyphs,
            position,
            lookup_flag,
            run,
            input_indices,
        )) continue;
        var matched = true;
        for (input_indices[1..], 0..) |glyph_index, input_index| {
            const expected =
                try view.readU16(rule.input_values_pos + input_index * 2);
            const actual = try table.class_def.value(
                view,
                class_def_offset,
                glyphs[glyph_index],
            );
            if (actual != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        try output.safety.markContext(allocator, &run, input_indices);
        try applyRecords(
            view,
            rule.records.records_pos,
            rule.records.count,
            input_indices,
            glyphs,
            adjustments,
            allocator,
            run,
        );
        return .{
            .matched = true,
            .next_pos = input_indices[glyph_count - 1] + 1,
        };
    }
    return .{};
}
