//! ChainContextSubst format-3 coverage-region matching.

const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Parsed = accelerator.model.ChainingCoverageSubtable;
const View = table.View;

pub const max_region_glyphs = accelerator.model.max_context_region_glyphs;

pub const Regions = struct {
    input: [max_region_glyphs]usize = undefined,
    input_count: usize = 0,
    backtrack: [max_region_glyphs]usize = undefined,
    backtrack_count: usize = 0,
    lookahead: [max_region_glyphs]usize = undefined,
    lookahead_count: usize = 0,

    pub fn inputSlice(self: *const Regions) []const usize {
        return self.input[0..self.input_count];
    }

    pub fn backtrackSlice(self: *const Regions) []const usize {
        return self.backtrack[0..self.backtrack_count];
    }

    pub fn lookaheadSlice(self: *const Regions) []const usize {
        return self.lookahead[0..self.lookahead_count];
    }
};

/// Match every format-3 region. `skip_first_input_coverage` consumes the proof
/// supplied by the lookup's exact first-input group index.
pub fn full(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    skip_first_input_coverage: bool,
    result: *Regions,
) Error!bool {
    if (position >= glyphs.len or
        !filtering.lookupCursorAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(lookup_flag, run, glyphs[position]))
    {
        return false;
    }
    if (subtable.input_count == 0 or
        subtable.input_count > max_region_glyphs or
        subtable.backtrack_count > max_region_glyphs or
        subtable.lookahead_count > max_region_glyphs)
    {
        return error.UnsupportedGsub;
    }

    result.* = Regions{
        .input_count = subtable.input_count,
        .backtrack_count = subtable.backtrack_count,
        .lookahead_count = subtable.lookahead_count,
    };
    if (!traversal.collectForward(
        glyphs,
        position,
        lookup_flag,
        run,
        result.input[0..result.input_count],
        false,
        position,
    )) return false;
    if (skip_first_input_coverage and result.input[0] != position) return false;
    if (!try coveragesMatch(
        view,
        subtable,
        glyphs,
        result.inputSlice(),
        subtable.input_offsets_pos,
        if (skip_first_input_coverage) 1 else 0,
    )) return false;

    if (!traversal.collectBacktrack(
        glyphs,
        position,
        lookup_flag,
        run,
        result.backtrack[0..result.backtrack_count],
        true,
        position,
    )) return false;
    const lookahead_start = result.input[result.input_count - 1] + 1;
    if (!traversal.collectForward(
        glyphs,
        lookahead_start,
        lookup_flag,
        run,
        result.lookahead[0..result.lookahead_count],
        true,
        position,
    )) return false;
    if (!try coveragesMatch(
        view,
        subtable,
        glyphs,
        result.backtrackSlice(),
        subtable.backtrack_offsets_pos,
        0,
    )) return false;
    if (!try coveragesMatch(
        view,
        subtable,
        glyphs,
        result.lookaheadSlice(),
        subtable.lookahead_offsets_pos,
        0,
    )) return false;
    return true;
}

fn coveragesMatch(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    indices: []const usize,
    offsets_pos: usize,
    start: usize,
) Error!bool {
    for (indices[start..], start..) |glyph_index, coverage_index| {
        const coverage_offset = try table.offset.required16(
            view,
            subtable.subtable_offset,
            try view.readU16(offsets_pos + coverage_index * 2),
        );
        if (try table.coverage.index(
            view,
            coverage_offset,
            glyphs[glyph_index],
        ) == null) return false;
    }
    return true;
}
