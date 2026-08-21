//! Direct and accelerator-backed ChainContextSubst format-2 matching.
//!
//! These matchers share one lazy physical/class window. Keeping the small
//! family at the class-executor level avoids a deep `matching/*` subtree while
//! preserving the existing direct and prepared entry points.

const accelerator = @import("../../../../accelerator/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const class_context = @import("../../../../../opentype/class_context.zig");
const table = @import("../../../../table/root.zig");
const match = @import("match.zig");
pub const window = @import("window.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Subtable = accelerator.model.ChainingClassSubtable;
const View = table.View;

pub fn acceleratedSubtable(
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
        if (try acceleratedCandidate(
            parsed,
            rule,
            &candidate_window,
            result,
        )) return true;
    }
    return false;
}

fn acceleratedCandidate(
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
    if ((try candidate_window.inputIndices(
        rule.input_count,
    )) == null) return false;
    if ((try candidate_window.lookaheadIndices(
        rule.input_count,
        rule.lookahead_count,
    )) == null) return false;

    // Classes are already decoded lazily by `Window`. Compare them directly
    // in authored sequence order instead of materializing a 192-entry stack
    // vector, hashing it, then walking it again with `mem.eql`.
    var expected_index: usize = rule.classes_start;
    for (0..backtrack_count) |index| {
        const actual =
            (try candidate_window.backtrackClassAt(index)) orelse return false;
        if (parsed.classes[expected_index] != actual) return false;
        expected_index += 1;
    }
    for (1..rule.input_count) |index| {
        const actual =
            (try candidate_window.inputClassAt(index)) orelse return false;
        if (parsed.classes[expected_index] != actual) return false;
        expected_index += 1;
    }
    for (0..rule.lookahead_count) |index| {
        const actual = (try candidate_window.lookaheadClassAt(
            rule.input_count,
            index,
        )) orelse return false;
        if (parsed.classes[expected_index] != actual) return false;
        expected_index += 1;
    }

    result.set(
        candidate_window,
        rule.input_count,
        backtrack_count,
        rule.lookahead_count,
        .{ .nested_lookup = rule.lookup_index },
    );
    return true;
}

pub fn directRuleSet(
    view: View,
    set_offset: usize,
    class_defs: window.ClassDefs,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    result: *match.Match,
) Error!bool {
    const rule_count = try view.readU16(set_offset);
    var candidate_window = window.Window.init(
        view,
        glyphs,
        position,
        class_defs,
        lookup_flag,
        run,
    );
    for (0..rule_count) |rule_index| {
        const rule_offset = set_offset +
            try view.readU16(set_offset + 2 + rule_index * 2);
        if (try directRule(
            view,
            rule_offset,
            &candidate_window,
            result,
        )) return true;
    }
    return false;
}

fn directRule(
    view: View,
    rule_offset: usize,
    candidate_window: *window.Window,
    result: *match.Match,
) Error!bool {
    var cursor = rule_offset;

    const backtrack_count = try view.readU16(cursor);
    cursor += 2;
    if (backtrack_count > window.max_region_glyphs) {
        return error.UnsupportedGsub;
    }
    if ((try candidate_window.backtrackIndices(
        backtrack_count,
    )) == null) return false;
    if (!try classesMatch(
        view,
        cursor,
        backtrack_count,
        candidate_window,
        .backtrack,
    )) return false;
    cursor += backtrack_count * 2;

    const input_count = try view.readU16(cursor);
    cursor += 2;
    if (input_count == 0) return false;
    if (input_count > window.max_region_glyphs) return error.UnsupportedGsub;
    if ((try candidate_window.inputIndices(input_count)) == null) return false;
    if (!try classesMatch(
        view,
        cursor,
        input_count - 1,
        candidate_window,
        .input,
    )) return false;
    cursor += (input_count - 1) * 2;

    const lookahead_count = try view.readU16(cursor);
    cursor += 2;
    if (lookahead_count > window.max_region_glyphs) {
        return error.UnsupportedGsub;
    }
    if ((try candidate_window.lookaheadIndices(
        input_count,
        lookahead_count,
    )) == null) return false;
    if (!try lookaheadClassesMatch(
        view,
        cursor,
        input_count,
        lookahead_count,
        candidate_window,
    )) return false;
    cursor += lookahead_count * 2;

    const record_count = try view.readU16(cursor);
    result.set(
        candidate_window,
        input_count,
        backtrack_count,
        lookahead_count,
        .{ .records = .{
            .offset = cursor + 2,
            .count = record_count,
        } },
    );
    return true;
}

const Region = enum { backtrack, input };

fn classesMatch(
    view: View,
    expected_offset: usize,
    count: usize,
    candidate_window: *window.Window,
    region: Region,
) Error!bool {
    for (0..count) |index| {
        const expected = try view.readU16(expected_offset + index * 2);
        const actual = switch (region) {
            .backtrack => (try candidate_window.backtrackClassAt(index)) orelse return false,
            .input => (try candidate_window.inputClassAt(index + 1)) orelse return false,
        };
        if (actual != expected) return false;
    }
    return true;
}

fn lookaheadClassesMatch(
    view: View,
    expected_offset: usize,
    input_count: usize,
    count: usize,
    candidate_window: *window.Window,
) Error!bool {
    for (0..count) |index| {
        const expected = try view.readU16(expected_offset + index * 2);
        const actual = (try candidate_window.lookaheadClassAt(
            input_count,
            index,
        )) orelse return false;
        if (actual != expected) return false;
    }
    return true;
}
