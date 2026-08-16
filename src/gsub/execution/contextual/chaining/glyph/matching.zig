//! ChainContextSubst format-1 glyph-region matching.

const accelerator = @import("../../../../accelerator/model.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const View = table.View;
const max_region_glyphs = accelerator.max_context_region_glyphs;

pub const Match = struct {
    input: [max_region_glyphs]usize = undefined,
    input_count: usize = 0,
    backtrack: [max_region_glyphs]usize = undefined,
    backtrack_count: usize = 0,
    lookahead: [max_region_glyphs]usize = undefined,
    lookahead_count: usize = 0,
    records_offset: usize = 0,
    record_count: usize = 0,

    pub fn inputSlice(self: *const Match) []const usize {
        return self.input[0..self.input_count];
    }

    pub fn backtrackSlice(self: *const Match) []const usize {
        return self.backtrack[0..self.backtrack_count];
    }

    pub fn lookaheadSlice(self: *const Match) []const usize {
        return self.lookahead[0..self.lookahead_count];
    }

    fn backtrackSliceMut(self: *Match) []usize {
        return self.backtrack[0..self.backtrack_count];
    }

    fn inputSliceMut(self: *Match) []usize {
        return self.input[0..self.input_count];
    }

    fn lookaheadSliceMut(self: *Match) []usize {
        return self.lookahead[0..self.lookahead_count];
    }
};

/// Return the first authored glyph rule matching all three chaining regions.
///
/// OpenType stores backtrack glyphs nearest-first and omits the first input
/// glyph because the parent Coverage has already selected its rule set.
pub fn ruleSet(
    view: View,
    set_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!?Match {
    const rule_count = try view.readU16(set_offset);
    for (0..rule_count) |rule_index| {
        const rule_offset = set_offset +
            try view.readU16(set_offset + 2 + rule_index * 2);
        if (try rule(
            view,
            rule_offset,
            glyphs,
            position,
            lookup_flag,
            run,
        )) |result| return result;
    }
    return null;
}

fn rule(
    view: View,
    rule_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!?Match {
    var cursor = rule_offset;
    var result = Match{};

    result.backtrack_count = try view.readU16(cursor);
    cursor += 2;
    if (result.backtrack_count > max_region_glyphs) {
        return error.UnsupportedGsub;
    }
    if (!traversal.collectBacktrack(
        glyphs,
        position,
        lookup_flag,
        run,
        result.backtrackSliceMut(),
        true,
        position,
    )) return null;
    if (!try glyphsMatch(
        view,
        glyphs,
        result.backtrackSlice(),
        cursor,
        0,
    )) return null;
    cursor += result.backtrack_count * 2;

    result.input_count = try view.readU16(cursor);
    cursor += 2;
    if (result.input_count == 0) return null;
    if (result.input_count > max_region_glyphs) return error.UnsupportedGsub;
    if (!traversal.collectForward(
        glyphs,
        position,
        lookup_flag,
        run,
        result.inputSliceMut(),
        false,
        position,
    )) return null;
    if (!try glyphsMatch(
        view,
        glyphs,
        result.inputSlice(),
        cursor,
        1,
    )) return null;
    cursor += (result.input_count - 1) * 2;

    result.lookahead_count = try view.readU16(cursor);
    cursor += 2;
    if (result.lookahead_count > max_region_glyphs) {
        return error.UnsupportedGsub;
    }
    if (!traversal.collectForward(
        glyphs,
        result.input[result.input_count - 1] + 1,
        lookup_flag,
        run,
        result.lookaheadSliceMut(),
        true,
        position,
    )) return null;
    if (!try glyphsMatch(
        view,
        glyphs,
        result.lookaheadSlice(),
        cursor,
        0,
    )) return null;
    cursor += result.lookahead_count * 2;

    result.record_count = try view.readU16(cursor);
    result.records_offset = cursor + 2;
    return result;
}

fn glyphsMatch(
    view: View,
    glyphs: []const GlyphId,
    indices: []const usize,
    expected_offset: usize,
    skip: usize,
) Error!bool {
    for (indices[skip..], skip..) |glyph_index, expected_index| {
        const expected = try view.readU16(
            expected_offset + (expected_index - skip) * 2,
        );
        if (glyphs[glyph_index] != expected) return false;
    }
    return true;
}
