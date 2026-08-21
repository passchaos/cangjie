//! AlternateSubst format-1 execution and HarfBuzz-compatible `rand` choice.

const std = @import("std");
const feature = @import("../../../feature/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const mutation = @import("../../../runtime/mutation.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || error{InvalidShapingInput};
const Options = filtering.Options;
const View = table.View;

pub fn apply(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyWithMatched(
        view,
        subtable_offset,
        glyphs,
        lookup_flag,
        run,
        null,
    );
}

pub fn applyWithMatched(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
    matched: ?[]bool,
) Error!void {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const alternate_set_count = try view.readU16(subtable_offset + 4);
    const configured_index = run.active_feature_value;
    if (configured_index == 0) return;

    for (glyphs.items, 0..) |*glyph, glyph_index| {
        if (matched) |items| {
            if (items[glyph_index]) continue;
        }
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph.*)) continue;
        const coverage = try table.coverage.index(
            view,
            coverage_offset,
            glyph.*,
        ) orelse continue;
        if (coverage >= alternate_set_count) continue;

        const alternate_set_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(
                subtable_offset + 6 + coverage * 2,
            ),
        );
        const alternate_count = try view.readU16(alternate_set_offset);
        if (alternate_count == 0) continue;
        const alternate_index =
            if (run.active_feature_random and
            configured_index == feature.random_value)
                randomIndex(
                    run.random_state orelse
                        return error.InvalidShapingInput,
                    alternate_count,
                )
            else
                configured_index;
        if (alternate_index > alternate_count) continue;

        glyph.* = try view.readU16(
            alternate_set_offset +
                2 +
                @as(usize, alternate_index - 1) * 2,
        );
        mutation.markSubstituted(run, glyph_index);
        if (matched) |items| items[glyph_index] = true;
    }
}

/// Advance the same wrapping minimal-standard generator used by HarfBuzz.
pub fn randomIndex(state: *u32, alternate_count: u16) u32 {
    state.* = state.* *% 48271 % 2147483647;
    return state.* % @as(u32, alternate_count) + 1;
}
