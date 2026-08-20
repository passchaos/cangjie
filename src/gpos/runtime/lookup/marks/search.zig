//! Shared backward-search semantics for mark attachment lookups.

const GlyphId = @import("../../../../glyph.zig").GlyphId;
const accelerator = @import("../../../accelerator/root.zig");
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const table = @import("../../../table/root.zig");
const unicode = @import("../../../../unicode.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
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

pub fn previousUnignoredCoveredGlyphParsed(
    view: View,
    coverage_offset: usize,
    coverage: ?accelerator.coverage.Owned,
    glyphs: []const GlyphId,
    mark_index: usize,
    lookup_flag: u16,
    run: Options,
) Error!?usize {
    var glyph_index = mark_index;
    while (glyph_index > 0) {
        glyph_index -= 1;
        if (matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        const covered = if (coverage) |owned|
            owned.index(glyphs[glyph_index]) != null
        else
            try table.coverage.index(
                view,
                coverage_offset,
                glyphs[glyph_index],
            ) != null;
        return if (covered) glyph_index else null;
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

pub fn previousCoveredLigature(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    mark_position: usize,
    lookup_flag: u16,
    run: Options,
) Error!?usize {
    var glyph_index = mark_position;
    while (glyph_index > 0) {
        glyph_index -= 1;
        if (matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[glyph_index],
        )) continue;
        if (matching.markAttachmentSearchSkipsGlyph(
            run,
            glyph_index,
        )) continue;

        // Earlier marks in the same cluster are transparent. The first
        // participating non-mark is the candidate and later coverage matching
        // decides whether this subtable can attach to it.
        if (try skipsNonCoveredGlyph(
            view,
            mark_coverage_offset,
            glyphs,
            glyph_index,
            run,
        )) continue;
        return glyph_index;
    }
    return null;
}

pub fn ligatureComponentIndex(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    ligature_position: usize,
    mark_position: usize,
    component_count: usize,
    lookup_flag: u16,
    run: Options,
) Error!usize {
    if (component_count <= 1) return 0;

    const metadata = run.run_metadata;
    if (metadata.glyph_source_indices) |sources| {
        if (mark_position < sources.len) {
            if (metadata.ligature_components) |store| {
                if (ligature_position < store.infos.items.len) {
                    const info = store.infos.items[ligature_position];
                    if (baseMarkLigatureActsAsSingleBase(
                        run.script_tag,
                        info.flags.base_mark_ligature,
                    )) return 0;
                    const component_sources =
                        store.logicalComponentSources(info) orelse
                        return error.InvalidShapingInput;
                    if (component_sources.len > 0) {
                        const mark_source = sources[mark_position];
                        var chosen: usize = 0;
                        const available_count =
                            @min(component_sources.len, component_count);
                        for (
                            component_sources[0..available_count],
                            0..,
                        ) |component_source, component_index| {
                            if (component_source > mark_source) break;
                            chosen = component_index;
                        }
                        return chosen;
                    }
                }
            }
        }
    }

    var covered_marks_before_target: usize = 0;
    var glyph_index = ligature_position + 1;
    while (glyph_index < mark_position) : (glyph_index += 1) {
        if (matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[glyph_index],
        )) continue;
        if (matching.markAttachmentSearchSkipsGlyph(
            run,
            glyph_index,
        )) continue;
        if (try table.coverage.index(
            view,
            mark_coverage_offset,
            glyphs[glyph_index],
        ) != null) {
            covered_marks_before_target += 1;
        }
    }
    return @min(covered_marks_before_target, component_count - 1);
}

pub fn shareLigatureComponent(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    first_mark_position: usize,
    second_mark_position: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    const first = try ligatureComponentHint(
        view,
        mark_coverage_offset,
        glyphs,
        first_mark_position,
        lookup_flag,
        run,
    ) orelse return true;
    const second = try ligatureComponentHint(
        view,
        mark_coverage_offset,
        glyphs,
        second_mark_position,
        lookup_flag,
        run,
    ) orelse return true;
    return first.ligature_position == second.ligature_position and
        first.component_index == second.component_index;
}

const LigatureComponentHint = struct {
    ligature_position: usize,
    component_index: usize,
};

fn ligatureComponentHint(
    view: View,
    mark_coverage_offset: usize,
    glyphs: []const GlyphId,
    mark_position: usize,
    lookup_flag: u16,
    run: Options,
) Error!?LigatureComponentHint {
    const ligature_position = try previousCoveredLigature(
        view,
        mark_coverage_offset,
        glyphs,
        mark_position,
        lookup_flag,
        run,
    ) orelse return null;
    const store =
        run.run_metadata.ligature_components orelse return null;
    if (ligature_position >= store.infos.items.len) return null;
    const info = store.infos.items[ligature_position];
    if (baseMarkLigatureActsAsSingleBase(
        run.script_tag,
        info.flags.base_mark_ligature,
    )) return null;
    if (info.component_count <= 1) return null;
    const component_sources =
        store.componentSources(info) orelse return error.InvalidShapingInput;
    const sources =
        run.run_metadata.glyph_source_indices orelse return null;
    if (mark_position >= sources.len) return null;

    const mark_source = sources[mark_position];
    var component_index: usize = 0;
    for (component_sources, 0..) |component_source, index| {
        if (component_source > mark_source) break;
        component_index = index;
    }
    return .{
        .ligature_position = ligature_position,
        .component_index = component_index,
    };
}

fn baseMarkLigatureActsAsSingleBase(
    script_tag: unicode.OpenTypeScriptTag,
    base_mark_ligature: bool,
) bool {
    return base_mark_ligature and script_tag == .hebr;
}
