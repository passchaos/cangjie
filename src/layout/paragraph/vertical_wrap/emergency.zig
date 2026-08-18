//! Grapheme-safe vertical emergency selection under ranged policy.
//!
//! Ordinary UAX candidates are collected separately. This module is used only
//! when no such boundary fits: it either finds a fitting reusable grapheme
//! edge whose preceding scalar permits emergency wrapping, or advances across
//! a disabled range until ordinary or emergency wrapping becomes legal again.

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_options = @import("../options.zig");
const policy = @import("policy.zig");
const shaped_boundary = @import("../../line_break/shaped_boundary.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");

pub fn fittingOrNext(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    glyph_start: usize,
    segment_end: usize,
    segment_byte_end: usize,
    overflow: usize,
    limit: f32,
    options: paragraph_options.Options,
) shared.SoftCandidate {
    var last_fitting: ?usize = null;
    var candidate = glyph_start + 1;
    while (candidate <= @min(overflow, segment_end)) : (candidate += 1) {
        if (shared.advance(prefix, glyph_start, candidate) <= limit and
            reusableAndAllowed(
                glyphs,
                graphemes,
                candidate,
                segment_end,
                segment_byte_end,
                options,
            ))
        {
            last_fitting = candidate;
        }
    }
    const break_index = last_fitting orelse firstAllowedFrom(
        glyphs,
        graphemes,
        glyph_start + 1,
        segment_end,
        segment_byte_end,
        options,
    ) orelse segment_end;
    return candidateForBoundary(
        glyphs,
        break_index,
        segment_end,
        segment_byte_end,
    );
}

/// Select the first break reached after overflow while emergency wrapping is
/// disabled at the offending source atom.
///
/// An ordinary UAX/policy candidate always remains usable, even when overfull.
/// A later range may also re-enable emergency wrapping. Choose whichever
/// source boundary comes first so a local `.no_wrap`/`.normal` span cannot
/// suppress wrapping for the rest of the paragraph.
pub fn afterDisabled(
    ordinary: ?shared.SoftCandidate,
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    segment_end: usize,
    segment_byte_end: usize,
    overflow: usize,
    options: paragraph_options.Options,
) shared.SoftCandidate {
    const ranged_emergency_index = firstAllowedFrom(
        glyphs,
        graphemes,
        overflow,
        segment_end,
        segment_byte_end,
        options,
    );
    if (ordinary) |candidate| {
        if (ranged_emergency_index) |break_index| {
            if (break_index < candidate.next_glyph_start) {
                return candidateForBoundary(
                    glyphs,
                    break_index,
                    segment_end,
                    segment_byte_end,
                );
            }
        }
        return candidate;
    }
    if (ranged_emergency_index) |break_index| {
        return candidateForBoundary(
            glyphs,
            break_index,
            segment_end,
            segment_byte_end,
        );
    }
    return candidateForBoundary(
        glyphs,
        segment_end,
        segment_end,
        segment_byte_end,
    );
}

fn firstAllowedFrom(
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    start: usize,
    segment_end: usize,
    segment_byte_end: usize,
    options: paragraph_options.Options,
) ?usize {
    var candidate = @max(start, 1);
    while (candidate < segment_end) : (candidate += 1) {
        if (reusableAndAllowed(
            glyphs,
            graphemes,
            candidate,
            segment_end,
            segment_byte_end,
            options,
        )) {
            return candidate;
        }
    }
    return null;
}

fn reusableAndAllowed(
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    break_index: usize,
    segment_end: usize,
    segment_byte_end: usize,
    options: paragraph_options.Options,
) bool {
    return shaped_boundary.outputBoundaryIsReusable(
        glyphs,
        graphemes,
        break_index,
    ) and policy.emergencyAllowedBefore(
        options,
        byteOffsetForBoundary(
            glyphs,
            break_index,
            segment_end,
            segment_byte_end,
        ),
    );
}

fn candidateForBoundary(
    glyphs: []const GlyphPosition,
    break_index: usize,
    segment_end: usize,
    segment_byte_end: usize,
) shared.SoftCandidate {
    return .{
        .glyph_end = break_index,
        .next_glyph_start = break_index,
        .byte_end = byteOffsetForBoundary(
            glyphs,
            break_index,
            segment_end,
            segment_byte_end,
        ),
    };
}

fn byteOffsetForBoundary(
    glyphs: []const GlyphPosition,
    break_index: usize,
    segment_end: usize,
    segment_byte_end: usize,
) usize {
    return if (break_index < segment_end)
        glyphs[break_index].cluster
    else
        segment_byte_end;
}
