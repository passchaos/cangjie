//! Direct ChainContextSubst format-2 class-rule matching.

const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");
const match = @import("../match.zig");
const window = @import("window.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const View = table.View;

pub fn ruleSet(
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
        if (try rule(view, rule_offset, &candidate_window, result)) return true;
    }
    return false;
}

fn rule(
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
