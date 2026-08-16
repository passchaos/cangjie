//! Accelerator-backed LigatureSubst matching.

const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const model = @import("../model.zig");
const traversal = @import("traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Ligature = accelerator.model.LigatureSubstitution;
const LigatureSet = accelerator.model.LigatureSet;

pub fn find(
    ligature: Ligature,
    set: LigatureSet,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) ?model.Match {
    const definition_end = set.definition_start + set.definition_len;
    const anchor_syllable = filtering.ligatureAnchorSyllable(run, glyph_base);
    for (ligature.definitions[set.definition_start..definition_end]) |definition| {
        const count: usize = definition.component_count;
        const expected = ligature.components[definition.component_start .. definition.component_start + count - 1];
        if (traversal.matchSlice(
            expected,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            anchor_syllable,
            component_offsets,
        )) |match_end| {
            return .{
                .ligature = definition.ligature,
                .component_count = count,
                .component_offsets = component_offsets,
                .match_end = match_end,
            };
        }
    }
    return null;
}

pub fn findPrefiltered(
    ligature: Ligature,
    set: LigatureSet,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) ?model.Match {
    const anchor_syllable = filtering.ligatureAnchorSyllable(run, glyph_base);
    const second_offset = traversal.firstVisibleOffset(
        glyphs,
        glyph_base,
        lookup_flag,
        run,
        anchor_syllable,
    );
    component_offsets[0] = 0;
    const definition_end = set.definition_start + set.definition_len;
    for (ligature.definitions[set.definition_start..definition_end]) |definition| {
        const count: usize = definition.component_count;
        const expected = ligature.components[definition.component_start .. definition.component_start + count - 1];
        if (count == 1) {
            return .{
                .ligature = definition.ligature,
                .component_count = 1,
                .component_offsets = component_offsets,
            };
        }
        const second = second_offset orelse continue;
        if (expected[0] != glyphs[second]) continue;
        component_offsets[1] = second;
        if (traversal.matchSliceFrom(
            expected[1..],
            2,
            second + 1,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            anchor_syllable,
            component_offsets,
        )) |match_end| {
            return .{
                .ligature = definition.ligature,
                .component_count = count,
                .component_offsets = component_offsets,
                .match_end = match_end,
            };
        }
    }
    return null;
}
