//! Shared visible-glyph windows for ContextPos and ChainContextPos matching.

const GlyphId = @import("../../../../glyph.zig").GlyphId;
const run_matching = @import("../../matching.zig");
const Options = @import("../../options.zig").Options;

/// Find the next glyph visible under lookup flags and source metadata.
pub fn next(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
) ?usize {
    var glyph_index = start;
    while (glyph_index < glyphs.len) : (glyph_index += 1) {
        if (!run_matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) return glyph_index;
    }
    return null;
}

/// Collect a forward contextual-match window without allocating.
///
/// `out` receives source indices rather than glyph ids because positioning
/// records address the matched input sequence and map it back to the post-GSUB
/// run.
pub fn forward(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
    out: []usize,
) bool {
    var output_index: usize = 0;
    var glyph_index = start;
    while (glyph_index < glyphs.len and output_index < out.len) : (glyph_index += 1) {
        if (run_matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        out[output_index] = glyph_index;
        output_index += 1;
    }
    return output_index == out.len;
}

/// Collect a reverse contextual-match window immediately before `position`.
pub fn backtrack(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    out: []usize,
) bool {
    var output_index: usize = 0;
    var glyph_index = position;
    while (glyph_index > 0 and output_index < out.len) {
        glyph_index -= 1;
        if (run_matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        out[output_index] = glyph_index;
        output_index += 1;
    }
    return output_index == out.len;
}
