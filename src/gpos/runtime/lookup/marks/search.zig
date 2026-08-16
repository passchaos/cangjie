//! Shared backward-search semantics for mark attachment lookups.

const GlyphId = @import("../../../../glyph.zig").GlyphId;
const accelerator = @import("../../../accelerator/root.zig");
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const MarkToBase = accelerator.model.MarkToBaseSubtable;
pub const Options = options.Options;
pub const View = table.View;

pub fn previousUnignoredCoveredGlyph(
    view: View,
    coverage_offset: usize,
    glyphs: []const GlyphId,
    mark_index: usize,
    lookup_flag: u16,
    run: Options,
) Error!?usize {
    var glyph_index = mark_index;
    while (glyph_index > 0) {
        glyph_index -= 1;
        // Ignored glyphs are transparent. The first participating glyph either
        // matches the requested coverage or blocks this attachment lookup.
        if (matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        return if (try table.coverage.index(
            view,
            coverage_offset,
            glyphs[glyph_index],
        ) != null)
            glyph_index
        else
            null;
    }
    return null;
}

pub fn markGlyph(
    view: View,
    mark_coverage_offset: usize,
    glyph: GlyphId,
    run: Options,
) Error!bool {
    if (run.glyph_classes) |classes| {
        return glyph < classes.len and classes[glyph] == 3;
    }
    return try table.coverage.index(
        view,
        mark_coverage_offset,
        glyph,
    ) != null;
}

pub fn markGlyphParsed(
    view: View,
    subtable: MarkToBase,
    glyph: GlyphId,
    run: Options,
) Error!bool {
    if (run.glyph_classes) |classes| {
        return glyph < classes.len and classes[glyph] == 3;
    }
    return if (subtable.mark_coverage) |coverage|
        coverage.index(glyph) != null
    else
        try table.coverage.index(
            view,
            subtable.mark_coverage_offset,
            glyph,
        ) != null;
}

pub fn skipsNonCoveredGlyphParsed(
    view: View,
    subtable: MarkToBase,
    glyphs: []const GlyphId,
    glyph_index: usize,
    run: Options,
) Error!bool {
    if (try markGlyphParsed(
        view,
        subtable,
        glyphs[glyph_index],
        run,
    )) return true;
    if (glyph_index == 0) return false;
    const sources =
        run.run_metadata.glyph_source_indices orelse return false;
    if (glyph_index >= sources.len) return false;
    if (sources[glyph_index] != sources[glyph_index - 1]) return false;
    if (try markGlyphParsed(
        view,
        subtable,
        glyphs[glyph_index - 1],
        run,
    )) return false;
    return true;
}

pub fn skipsNonCoveredGlyph(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    glyph_index: usize,
    run: Options,
) Error!bool {
    if (try markGlyph(
        view,
        mark_coverage_offset,
        glyphs[glyph_index],
        run,
    )) return true;
    return isMultipleSubstContinuation(
        view,
        mark_coverage_offset,
        glyphs,
        glyph_index,
        run,
    );
}

pub fn isMultipleSubstContinuation(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    glyph_index: usize,
    run: Options,
) Error!bool {
    if (glyph_index == 0) return false;
    if (run.run_metadata.ligature_components) |store| {
        if (glyph_index < store.infos.items.len) {
            const info = store.infos.items[glyph_index];
            if (info.flags.multiplied) {
                // Only component zero may act as a mark-attachment base.
                return info.flags.multiple_component != 0;
            }
        }
    }

    // Detached GPOS callers may lack GSUB provenance. Preserve the
    // conservative source-adjacency fallback.
    const sources =
        run.run_metadata.glyph_source_indices orelse return false;
    if (glyph_index >= sources.len) return false;
    if (sources[glyph_index] != sources[glyph_index - 1]) return false;
    if (try markGlyph(
        view,
        mark_coverage_offset,
        glyphs[glyph_index - 1],
        run,
    )) return false;
    return true;
}
