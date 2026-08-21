//! LookupFlag- and syllable-aware component traversal shared by matchers.

const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const model = @import("../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn matchSlice(
    expected: []const GlyphId,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    anchor_syllable: ?u8,
    component_offsets: *[model.max_components]usize,
) ?usize {
    component_offsets[0] = 0;
    return matchSliceFrom(
        expected,
        1,
        1,
        glyphs,
        glyph_base,
        lookup_flag,
        run,
        anchor_syllable,
        component_offsets,
    );
}

pub fn matchSliceFrom(
    expected: []const GlyphId,
    first_component: usize,
    start: usize,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    anchor_syllable: ?u8,
    component_offsets: *[model.max_components]usize,
) ?usize {
    // With no LookupFlag filtering and no default-ignorables, the next
    // physical glyph is also the next visible glyph. Syllable scoping remains
    // authoritative for Indic stages.
    if (lookup_flag == 0 and run.run_has_default_ignorables == false) {
        const match_end = start + expected.len;
        if (match_end > glyphs.len) return null;
        for (expected, first_component..) |wanted, component_index| {
            const cursor = start + component_index - first_component;
            if (!filtering.ligatureAllowsRelativeGlyph(
                run,
                anchor_syllable,
                glyph_base,
                cursor,
            ) or glyphs[cursor] != wanted) return null;
            component_offsets[component_index] = cursor;
        }
        return match_end;
    }
    var cursor = start;
    for (expected, first_component..) |wanted, component_index| {
        cursor = nextVisibleOffset(
            glyphs,
            glyph_base,
            cursor,
            lookup_flag,
            run,
            anchor_syllable,
        ) orelse return null;
        if (glyphs[cursor] != wanted) return null;
        component_offsets[component_index] = cursor;
        cursor += 1;
    }
    return cursor;
}

pub fn firstVisibleOffset(
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    anchor_syllable: ?u8,
) ?usize {
    if (glyphs.len <= 1) return null;
    return nextVisibleOffset(
        glyphs,
        glyph_base,
        1,
        lookup_flag,
        run,
        anchor_syllable,
    );
}

pub fn nextVisibleOffset(
    glyphs: []const GlyphId,
    glyph_base: usize,
    start: usize,
    lookup_flag: u16,
    run: Options,
    anchor_syllable: ?u8,
) ?usize {
    var cursor = start;
    while (cursor < glyphs.len and
        filtering.ligatureAllowsRelativeGlyph(
            run,
            anchor_syllable,
            glyph_base,
            cursor,
        ) and
        filtering.ligatureMaySkipGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_base,
            cursor,
        )) : (cursor += 1)
    {}
    if (cursor >= glyphs.len or
        !filtering.ligatureAllowsRelativeGlyph(
            run,
            anchor_syllable,
            glyph_base,
            cursor,
        ))
    {
        return null;
    }
    return cursor;
}
