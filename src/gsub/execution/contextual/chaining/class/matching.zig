//! Direct and accelerator-backed ChainContextSubst format-2 matching.
//!
//! These matchers share one lazy physical/class window. Keeping the small
//! family at the class-executor level avoids a deep `matching/*` subtree while
//! preserving the existing direct and prepared entry points.

const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
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
    const group = accelerator.index.class_first.findPrepared(
        parsed.classes,
        parsed.first_index_start,
        parsed.groups,
        glyphs[position],
    ) orelse return false;
    return acceleratedGroup(
        view,
        parsed,
        group,
        glyphs,
        position,
        lookup_flag,
        run,
        result,
    );
}

pub fn acceleratedGroup(
    view: View,
    parsed: Subtable,
    group: *const class_context.RuleGroup,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    result: *match.Match,
) Error!bool {
    if (group.max_input_count == 0 or
        group.max_input_count > window.max_region_glyphs or
        group.max_lookahead_count > window.max_region_glyphs)
    {
        return error.UnsupportedGsub;
    }
    if (lookup_flag == 0 and run.run_has_default_ignorables == false) {
        return acceleratedAdjacentGroup(
            view,
            parsed,
            group,
            glyphs,
            position,
            run,
            result,
        );
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
        .{
            .backtrack = parsed.backtrack_class_values,
            .input = parsed.input_class_values,
            .lookahead = parsed.lookahead_class_values,
        },
        lookup_flag,
        run,
    );
    const rules = parsed.rules[group.start .. group.start + group.len];
    if (group.hash_sorted) {
        var matched_index: ?usize = null;
        var shape_start: usize = 0;
        while (shape_start < rules.len) {
            const first = rules[shape_start];
            var shape_end = shape_start + 1;
            while (shape_end < rules.len and sameShape(
                first,
                rules[shape_end],
            )) : (shape_end += 1) {}
            const hash = (try candidateHash(
                &candidate_window,
                first.backtrack_count,
                first.input_count,
                first.lookahead_count,
            )) orelse {
                shape_start = shape_end;
                continue;
            };
            var low = shape_start;
            var high = shape_end;
            while (low < high) {
                const middle = low + (high - low) / 2;
                if (rules[middle].hash < hash) {
                    low = middle + 1;
                } else {
                    high = middle;
                }
            }
            var index = low;
            while (index < shape_end and rules[index].hash == hash) : (index += 1) {
                if (!try candidateClassesMatch(
                    parsed,
                    rules[index],
                    &candidate_window,
                )) continue;
                if (matched_index == null or
                    rules[index].order < rules[matched_index.?].order)
                {
                    matched_index = index;
                }
            }
            shape_start = shape_end;
        }
        const index = matched_index orelse return false;
        setMatchedRule(rules[index], &candidate_window, result);
        return true;
    }
    for (rules) |rule| {
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

fn candidateHash(
    candidate_window: *window.Window,
    backtrack_count: usize,
    input_count: usize,
    lookahead_count: usize,
) Error!?u64 {
    if (input_count == 0 or
        backtrack_count > window.max_region_glyphs or
        input_count > window.max_region_glyphs or
        lookahead_count > window.max_region_glyphs)
    {
        return null;
    }
    var hash = class_context.sequenceHashEmpty();
    for (0..backtrack_count) |index| {
        hash = class_context.sequenceHashAppend(
            hash,
            (try candidate_window.backtrackClassAt(index)) orelse return null,
        );
    }
    for (1..input_count) |index| {
        hash = class_context.sequenceHashAppend(
            hash,
            (try candidate_window.inputClassAt(index)) orelse return null,
        );
    }
    for (0..lookahead_count) |index| {
        hash = class_context.sequenceHashAppend(
            hash,
            (try candidate_window.lookaheadClassAt(
                input_count,
                index,
            )) orelse return null,
        );
    }
    return hash;
}

fn sameShape(lhs: class_context.Rule, rhs: class_context.Rule) bool {
    return lhs.backtrack_count == rhs.backtrack_count and
        lhs.input_count == rhs.input_count and
        lhs.lookahead_count == rhs.lookahead_count;
}

fn acceleratedAdjacentGroup(
    view: View,
    parsed: Subtable,
    group: *const class_context.RuleGroup,
    glyphs: []const GlyphId,
    position: usize,
    run: Options,
    result: *match.Match,
) Error!bool {
    const anchor_syllable =
        filtering.sourceSyllableForGlyph(run, position);
    for (parsed.rules[group.start .. group.start + group.len]) |rule| {
        const backtrack_count: usize = rule.backtrack_count;
        const input_count: usize = rule.input_count;
        const lookahead_count: usize = rule.lookahead_count;
        if (backtrack_count > position or input_count == 0 or
            input_count > glyphs.len - position or
            lookahead_count > glyphs.len - position - input_count)
        {
            continue;
        }
        var expected_index: usize = rule.classes_start;
        var matches = true;
        for (0..backtrack_count) |index| {
            const glyph_index = position - index - 1;
            if (!filtering.sourceSyllableAllowsGlyph(
                run,
                anchor_syllable,
                glyph_index,
            )) {
                matches = false;
                break;
            }
            const actual = try table.class_def.valueWithDense(
                view,
                parsed.backtrack_class_def,
                parsed.backtrack_class_values,
                glyphs[glyph_index],
            );
            if (parsed.classes[expected_index] != actual) {
                matches = false;
                break;
            }
            expected_index += 1;
        }
        if (!matches) continue;
        for (1..input_count) |index| {
            const glyph_index = position + index;
            if (!filtering.sourceSyllableAllowsGlyph(
                run,
                anchor_syllable,
                glyph_index,
            )) {
                matches = false;
                break;
            }
            const actual = try table.class_def.valueWithDense(
                view,
                parsed.input_class_def,
                parsed.input_class_values,
                glyphs[glyph_index],
            );
            if (parsed.classes[expected_index] != actual) {
                matches = false;
                break;
            }
            expected_index += 1;
        }
        if (!matches) continue;
        for (0..lookahead_count) |index| {
            const relative = input_count + index;
            const glyph_index = position + relative;
            if (!filtering.sourceSyllableAllowsGlyph(
                run,
                anchor_syllable,
                glyph_index,
            )) {
                matches = false;
                break;
            }
            const actual = try table.class_def.valueWithDense(
                view,
                parsed.lookahead_class_def,
                parsed.lookahead_class_values,
                glyphs[glyph_index],
            );
            if (parsed.classes[expected_index] != actual) {
                matches = false;
                break;
            }
            expected_index += 1;
        }
        if (!matches) continue;

        result.input_count = input_count;
        result.backtrack_count = backtrack_count;
        result.lookahead_count = lookahead_count;
        result.action = if (rule.record_list)
            .{ .records = .{
                .offset = rule.records_offset,
                .count = rule.subst_count,
            } }
        else
            .{ .nested_lookup = rule.lookup_index };
        for (0..backtrack_count) |index| {
            result.backtrack[index] = position - index - 1;
        }
        for (0..input_count) |index| {
            result.input[index] = position + index;
        }
        for (0..lookahead_count) |index| {
            result.lookahead[index] = position + input_count + index;
        }
        return true;
    }
    return false;
}

fn acceleratedCandidate(
    parsed: Subtable,
    rule: class_context.Rule,
    candidate_window: *window.Window,
    result: *match.Match,
) Error!bool {
    if (!try candidateClassesMatch(
        parsed,
        rule,
        candidate_window,
    )) return false;
    setMatchedRule(rule, candidate_window, result);
    return true;
}

fn candidateClassesMatch(
    parsed: Subtable,
    rule: class_context.Rule,
    candidate_window: *window.Window,
) Error!bool {
    const backtrack_count: usize = rule.backtrack_count;
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

    return true;
}

fn setMatchedRule(
    rule: class_context.Rule,
    candidate_window: *window.Window,
    result: *match.Match,
) void {
    result.set(
        candidate_window,
        rule.input_count,
        rule.backtrack_count,
        rule.lookahead_count,
        if (rule.record_list)
            .{ .records = .{
                .offset = rule.records_offset,
                .count = rule.subst_count,
            } }
        else
            .{ .nested_lookup = rule.lookup_index },
    );
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
        .{},
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
