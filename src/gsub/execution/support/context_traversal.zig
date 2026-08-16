//! LookupFlag- and syllable-aware traversal for contextual GSUB execution.
//!
//! These helpers return physical glyph-buffer indexes. Ignored glyphs remain
//! in the buffer, so callers can match logical OpenType sequences without
//! losing the positions needed by later substitution records.

const filtering = @import("../../runtime/filtering.zig");
const Options = @import("../../runtime/options.zig").Options;
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub fn collectForward(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
    out: []usize,
    context_match: bool,
    anchor_index: usize,
) bool {
    return collectForwardPrefix(
        glyphs,
        start,
        lookup_flag,
        run,
        out,
        context_match,
        anchor_index,
    ) == out.len;
}

pub fn collectForwardPrefix(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
    out: []usize,
    context_match: bool,
    anchor_index: usize,
) usize {
    var out_index: usize = 0;
    var glyph_index = start;
    const anchor_syllable =
        filtering.sourceSyllableForGlyph(run, anchor_index);
    while (glyph_index < glyphs.len and out_index < out.len) : (glyph_index += 1) {
        if (filtering.contextualMaySkipGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
            context_match,
        )) continue;
        if (!filtering.sourceSyllableAllowsGlyph(
            run,
            anchor_syllable,
            glyph_index,
        )) break;
        out[out_index] = glyph_index;
        out_index += 1;
    }
    return out_index;
}

pub fn nextIndex(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
    context_match: bool,
    anchor_index: usize,
) ?usize {
    var glyph_index = start;
    const anchor_syllable =
        filtering.sourceSyllableForGlyph(run, anchor_index);
    while (glyph_index < glyphs.len) : (glyph_index += 1) {
        if (filtering.contextualMaySkipGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
            context_match,
        )) continue;
        if (!filtering.sourceSyllableAllowsGlyph(
            run,
            anchor_syllable,
            glyph_index,
        )) return null;
        return glyph_index;
    }
    return null;
}

pub fn nextGlyph(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
    context_match: bool,
    anchor_index: usize,
) ?GlyphId {
    const index = nextIndex(
        glyphs,
        start,
        lookup_flag,
        run,
        context_match,
        anchor_index,
    ) orelse return null;
    return glyphs[index];
}

pub fn previousGlyph(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    context_match: bool,
    anchor_index: usize,
) ?GlyphId {
    var glyph_index = position;
    const anchor_syllable =
        filtering.sourceSyllableForGlyph(run, anchor_index);
    while (glyph_index > 0) {
        glyph_index -= 1;
        if (filtering.contextualMaySkipGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
            context_match,
        )) continue;
        if (!filtering.sourceSyllableAllowsGlyph(
            run,
            anchor_syllable,
            glyph_index,
        )) return null;
        return glyphs[glyph_index];
    }
    return null;
}

pub fn collectBacktrack(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
    out: []usize,
    context_match: bool,
    anchor_index: usize,
) bool {
    var out_index: usize = 0;
    var glyph_index = position;
    const anchor_syllable =
        filtering.sourceSyllableForGlyph(run, anchor_index);
    while (glyph_index > 0 and out_index < out.len) {
        glyph_index -= 1;
        if (filtering.contextualMaySkipGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
            context_match,
        )) continue;
        if (!filtering.sourceSyllableAllowsGlyph(
            run,
            anchor_syllable,
            glyph_index,
        )) return false;
        out[out_index] = glyph_index;
        out_index += 1;
    }
    return out_index == out.len;
}
