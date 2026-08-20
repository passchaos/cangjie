//! Coverage-region matching for ChainContextPos format 3.

const accelerator = @import("../../../../../accelerator/root.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const table = @import("../../../../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const NativeCoverage = accelerator.coverage.Owned;
pub const View = table.View;

/// Match a visible-glyph index window against parsed or cached coverages.
///
/// Accelerator groups may already prove the first input Coverage. `start`
/// lets that caller skip exactly the proven prefix while retaining one matcher
/// for uncached and partially cached sidecars.
pub fn indices(
    view: View,
    base_offset: usize,
    glyphs: []const GlyphId,
    glyph_indices: []const usize,
    offsets_pos: usize,
    coverages: []const NativeCoverage,
    start: usize,
) Error!bool {
    var index = start;
    while (index < glyph_indices.len) : (index += 1) {
        const glyph = glyphs[glyph_indices[index]];
        if (index < coverages.len) {
            if (coverages[index].index(glyph) == null) return false;
            continue;
        }
        const coverage_offset = try table.offset.required16(
            view,
            base_offset,
            try view.readU16(offsets_pos + index * 2),
        );
        if (!try table.coverage.contains(
            view,
            coverage_offset,
            glyph,
            .membership,
        )) return false;
    }
    return true;
}
