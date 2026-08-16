//! Infallible glyph and parallel-sidecar commit for a prepared ligature.

const std = @import("std");
const ligature_provenance = @import("../../../../ligature_provenance.zig");
const mutation = @import("../../../runtime/mutation.zig");
const Options = @import("../../../runtime/options.zig").Options;
const model = @import("model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn apply(
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    match: model.Match,
    info: ligature_provenance.Info,
    run: Options,
) model.Change {
    glyphs.items[glyph_index] = match.ligature;
    mutation.markSubstituted(run, glyph_index);
    if (run.ligature_components) |store| {
        if (glyph_index < store.infos.items.len) {
            store.infos.items[glyph_index] = info;
        }
    }

    // Remove matched components from right to left. LookupFlag-ignored glyphs
    // between them remain in the run and preserve their own metadata.
    var component_index = match.component_count;
    while (component_index > 1) {
        component_index -= 1;
        const removed_index =
            glyph_index + match.component_offsets[component_index];
        _ = glyphs.orderedRemove(removed_index);
        mutation.removeMetadata(run, removed_index, 1);
    }
    return .{
        .removed_len = match.component_count,
        .component_offsets = match.component_offsets.*,
        .component_count = match.component_count,
    };
}
