//! UAX #14 source boundaries mapped to reusable shaped output boundaries.

const std = @import("std");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const shaped_boundary = @import("../../line_break/shaped_boundary.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");

pub fn collect(
    output: *std.ArrayList(shared.SoftCandidate),
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    segment_start: usize,
    segment_end: usize,
    segment_byte_start: usize,
    segment_byte_end: usize,
) !void {
    for (breaks) |item| {
        if (item.kind != .soft or
            item.automatic_hyphen or
            item.byte_offset <= segment_byte_start or
            item.byte_offset >= segment_byte_end)
        {
            continue;
        }
        const boundary = forSourceBoundary(
            glyphs,
            graphemes,
            segment_start,
            segment_end,
            item.byte_offset,
        ) orelse continue;
        try output.append(allocator, boundary);
    }
}

pub fn lastFitting(
    items: []const shared.SoftCandidate,
    prefix: []const f32,
    glyph_start: usize,
    overflow: usize,
    limit: f32,
) ?shared.SoftCandidate {
    var selected: ?shared.SoftCandidate = null;
    for (items) |candidate| {
        if (candidate.next_glyph_start <= glyph_start or
            candidate.next_glyph_start > overflow or
            candidate.glyph_end <= glyph_start or
            shared.advance(prefix, glyph_start, candidate.glyph_end) > limit)
        {
            continue;
        }
        selected = candidate;
    }
    return selected;
}

pub fn emergency(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    glyph_start: usize,
    segment_end: usize,
    segment_byte_end: usize,
    overflow: usize,
    limit: f32,
) shared.SoftCandidate {
    var last_fitting: ?usize = null;
    var candidate = glyph_start + 1;
    while (candidate <= @min(overflow, segment_end)) : (candidate += 1) {
        if (shared.advance(prefix, glyph_start, candidate) <= limit and
            shaped_boundary.outputBoundaryIsReusable(
                glyphs,
                graphemes,
                candidate,
            ))
        {
            last_fitting = candidate;
        }
    }
    const break_index = last_fitting orelse firstSafe: {
        var next = glyph_start + 1;
        while (next < segment_end and
            !shaped_boundary.outputBoundaryIsReusable(
                glyphs,
                graphemes,
                next,
            ))
        {
            next += 1;
        }
        break :firstSafe next;
    };
    return .{
        .glyph_end = break_index,
        .next_glyph_start = break_index,
        .byte_end = if (break_index < segment_end)
            glyphs[break_index].cluster
        else
            segment_byte_end,
    };
}

fn forSourceBoundary(
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    segment_start: usize,
    segment_end: usize,
    byte_offset: usize,
) ?shared.SoftCandidate {
    var current = segment_start;
    while (current < segment_end and
        glyphs[current].sourceByteEnd() < byte_offset)
    {
        current += 1;
    }
    if (current >= segment_end) return null;
    if (byte_offset > glyphs[current].cluster and
        byte_offset < glyphs[current].sourceByteEnd())
    {
        return null;
    }

    var break_index = if (glyphs[current].sourceByteEnd() == byte_offset)
        current + 1
    else
        shaped_boundary.glyphIndexForSourceBoundary(
            glyphs,
            byte_offset,
            segment_start,
            current + 1,
        ) orelse return null;
    while (break_index < segment_end and
        glyphs[break_index].cluster == glyphs[break_index - 1].cluster)
    {
        break_index += 1;
    }
    if (break_index <= segment_start or
        !shaped_boundary.outputBoundaryIsReusable(
            glyphs,
            graphemes,
            break_index,
        ))
    {
        return null;
    }

    var visible_end = break_index;
    while (visible_end > segment_start and
        glyphs[visible_end - 1].codepoint == ' ')
    {
        visible_end -= 1;
    }
    if (visible_end <= segment_start) return null;
    return .{
        .glyph_end = visible_end,
        .next_glyph_start = break_index,
        .byte_end = byte_offset,
    };
}
