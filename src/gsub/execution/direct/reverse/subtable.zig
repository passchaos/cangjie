//! One ReverseChainSingleSubst subtable over a glyph run or target position.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const mutation = @import("../../../runtime/mutation.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const matching = @import("matching.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Parsed = accelerator.model.ReverseChainingSingleSubtable;
const View = table.View;

pub fn apply(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    const parsed = try accelerator.build.reverse.parse(view, subtable_offset);
    var position = glyphs.items.len;
    while (position > 0) {
        position -= 1;
        _ = try applyParsedAt(
            view,
            parsed,
            glyphs,
            position,
            lookup_flag,
            run,
        );
    }
}

pub fn applyAt(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return applyParsedAt(
        view,
        try accelerator.build.reverse.parse(view, subtable_offset),
        glyphs,
        position,
        lookup_flag,
        run,
    );
}

pub fn applyParsedAt(
    view: View,
    parsed: Parsed,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (position >= glyphs.items.len or
        !filtering.lookupCursorAllowsGlyph(run, position))
    {
        return false;
    }
    const glyph = glyphs.items[position];
    if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;

    const coverage = try table.coverage.index(
        view,
        parsed.coverage_offset,
        glyph,
    ) orelse return false;
    if (coverage >= parsed.glyph_count or
        !try matching.contextsMatch(
            view,
            parsed,
            glyphs.items,
            position,
            lookup_flag,
            run,
        ))
    {
        return false;
    }

    glyphs.items[position] = try view.readU16(
        parsed.substitutes_pos + coverage * 2,
    );
    mutation.markSubstituted(run, position);
    return true;
}
