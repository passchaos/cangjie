//! Accelerator-backed chaining class-rule matching.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const class_context = @import("../../../../../../opentype/class_context.zig");
const table = @import("../../../../../table/root.zig");
const match = @import("../match.zig");
const window = @import("window.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;

const Error = table.class_def.Error;
const Subtable = accelerator.model.ChainingClassSubtable;
const View = table.View;

pub fn subtable(
    view: View,
    parsed: Subtable,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    result: *match.Match,
) Error!bool {
    const group = accelerator.index.class_first.find(
        parsed.classes,
        parsed.first_index_start,
        parsed.groups,
        glyphs[position],
    ) orelse return false;
    if (group.max_input_count == 0 or
        group.max_input_count > window.max_region_glyphs or
        group.max_lookahead_count > window.max_region_glyphs)
    {
        return error.UnsupportedGsub;
    }

    var candidate_window = window.Window.init(
        view,
        glyphs,
        position,
        .{
            .backtrack = parsed.backtrack_class_def,
            .input = parsed.input_class_def,
            .lookahead = parsed.lookahead_class_def,
        },
        lookup_flag,
        run,
    );
    for (parsed.rules[group.start .. group.start + group.len]) |rule| {
        if (rule.input_count > group.max_input_count or
            rule.lookahead_count > group.max_lookahead_count)
        {
            continue;
        }
        if (try candidate(
            parsed,
            rule,
            &candidate_window,
            result,
        )) return true;
    }
    return false;
}

fn candidate(
    parsed: Subtable,
    rule: class_context.Rule,
    candidate_window: *window.Window,
    result: *match.Match,
) Error!bool {
    const backtrack_count: usize = @intCast(rule.records_offset);
    if (backtrack_count > window.max_region_glyphs or
        rule.input_count == 0 or
        rule.lookahead_count > window.max_region_glyphs)
    {
        return false;
    }

    if ((try candidate_window.backtrackIndices(
        backtrack_count,
    )) == null) return false;
    const input = (try candidate_window.inputIndices(
        rule.input_count,
    )) orelse return false;
    _ = input;
    if ((try candidate_window.lookaheadIndices(
        rule.input_count,
        rule.lookahead_count,
    )) == null) return false;

    var actual: [window.max_region_glyphs * 3]u16 = undefined;
    var actual_count: usize = 0;
    for (0..backtrack_count) |index| {
        actual[actual_count] =
            (try candidate_window.backtrackClassAt(index)) orelse return false;
        actual_count += 1;
    }
    for (1..rule.input_count) |index| {
        actual[actual_count] =
            (try candidate_window.inputClassAt(index)) orelse return false;
        actual_count += 1;
    }
    for (0..rule.lookahead_count) |index| {
        actual[actual_count] = (try candidate_window.lookaheadClassAt(
            rule.input_count,
            index,
        )) orelse return false;
        actual_count += 1;
    }

    const actual_classes = actual[0..actual_count];
    if (rule.hash != class_context.sequenceHash(actual_classes)) return false;
    const expected = parsed.classes[rule.classes_start .. rule.classes_start + actual_count];
    if (!std.mem.eql(u16, expected, actual_classes)) return false;

    result.set(
        candidate_window,
        rule.input_count,
        backtrack_count,
        rule.lookahead_count,
        .{ .nested_lookup = rule.lookup_index },
    );
    return true;
}
