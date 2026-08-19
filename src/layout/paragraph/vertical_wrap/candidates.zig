//! UAX #14 source boundaries mapped to reusable shaped output boundaries.

const std = @import("std");
const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const measure = @import("measure.zig");
const paragraph_options = @import("../options.zig");
const policy = @import("policy.zig");
const run_types = @import("../../types/runs.zig");
const shaped_boundary = @import("../../line_break/shaped_boundary.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");
const vertical_tabs = @import("tabs.zig");
const white_space = @import("../white_space.zig");

pub fn collect(
    output: *std.ArrayList(shared.SoftCandidate),
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    segment_start: usize,
    segment_end: usize,
    segment_byte_start: usize,
    segment_byte_end: usize,
    options: paragraph_options.Options,
) !void {
    for (breaks) |item| {
        if (item.kind != .soft or
            item.automatic_hyphen or
            item.byte_offset <= segment_byte_start or
            item.byte_offset >= segment_byte_end)
        {
            continue;
        }
        var boundary = forSourceBoundary(
            glyphs,
            graphemes,
            segment_start,
            segment_end,
            item.byte_offset,
            true,
        ) orelse continue;
        const hyphen_index = boundary.glyph_end - 1;
        if (discretionary_hyphen.isCandidate(
            glyphs[hyphen_index].codepoint,
        )) {
            boundary.hyphen =
                try discretionary_hyphen.resolveVerticalForGlyph(
                    runs,
                    variation_coords,
                    hyphen_index,
                    options.writing_mode,
                    options.text_orientation,
                    options.hyphenation.character,
                ) orelse continue;
        } else if (softHyphenEndingAt(text, item.byte_offset)) |source| {
            boundary.hyphen =
                try discretionary_hyphen.resolveVerticalAtBoundary(
                    runs,
                    variation_coords,
                    glyphs,
                    boundary.glyph_end,
                    source.start,
                    source.len,
                    options.writing_mode,
                    options.text_orientation,
                    options.hyphenation.character,
                ) orelse continue;
        }
        try output.append(allocator, boundary);
    }
}

pub fn appendBreakSpaces(
    output: *std.ArrayList(shared.SoftCandidate),
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    segment_start: usize,
    segment_end: usize,
    segment_byte_start: usize,
    segment_byte_end: usize,
    options: paragraph_options.Options,
) !void {
    if (options.white_space_collapse != .break_spaces) return;
    var index = segment_start;
    while (index < segment_end) : (index += 1) {
        if (glyphs[index].codepoint != ' ' and !glyphs[index].isTab()) {
            continue;
        }
        const byte_offset = glyphs[index].sourceByteEnd();
        if (byte_offset <= segment_byte_start or
            byte_offset >= segment_byte_end or
            !policy.wrappingAllowedBefore(options, byte_offset))
        {
            continue;
        }
        const boundary = forSourceBoundary(
            glyphs,
            graphemes,
            segment_start,
            segment_end,
            byte_offset,
            false,
        ) orelse continue;
        try insertSortedUnique(output, allocator, boundary);
    }
}

pub fn lastFitting(
    items: []const shared.SoftCandidate,
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    glyph_start: usize,
    overflow: usize,
    limit: f32,
    options: paragraph_options.Options,
) ?shared.SoftCandidate {
    var selected: ?shared.SoftCandidate = null;
    for (items) |candidate| {
        if (candidate.next_glyph_start <= glyph_start or
            candidate.next_glyph_start > overflow or
            candidate.glyph_end <= glyph_start or
            candidateInlineSize(
                candidate,
                glyphs,
                prefix,
                glyph_start,
                options,
            ) > limit)
        {
            continue;
        }
        selected = candidate;
    }
    return selected;
}

pub fn candidateInlineSize(
    candidate: shared.SoftCandidate,
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    glyph_start: usize,
    options: paragraph_options.Options,
) f32 {
    const terminal_advance = if (candidate.hyphen) |hyphen|
        hyphen.resolved.y_advance
    else
        0;
    const visible_end = @min(candidate.glyph_end, glyphs.len);
    const visible_start = @min(glyph_start, visible_end);
    const visible = glyphs[visible_start..visible_end];
    if (terminal_advance != 0 and vertical_tabs.contains(visible)) {
        const fallback_advance =
            white_space.defaultVerticalSpaceAdvance(glyphs);
        const fallback_interval =
            @as(f32, @floatFromInt(@max(1, options.tab_width))) *
            fallback_advance;
        return vertical_tabs.measureRangeWithTerminal(
            visible,
            options.tab_stops,
            fallback_interval,
            fallback_advance,
            terminal_advance,
        );
    }
    return measure.inlineSize(
        glyphs,
        prefix,
        glyph_start,
        candidate.glyph_end,
        options,
    ) + terminal_advance;
}

/// Return the first ordinary boundary after an overfull indivisible fragment.
///
/// `overflow-wrap: normal` must not manufacture a grapheme edge merely to
/// satisfy the measure. It instead keeps consuming the current word/CJK
/// fragment until the next policy-approved UAX boundary, even when that makes
/// the column taller than its requested inline size.
pub fn firstUsable(
    items: []const shared.SoftCandidate,
    glyph_start: usize,
) ?shared.SoftCandidate {
    for (items) |candidate| {
        if (candidate.glyph_end > glyph_start and
            candidate.next_glyph_start > glyph_start)
        {
            return candidate;
        }
    }
    return null;
}

fn forSourceBoundary(
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    segment_start: usize,
    segment_end: usize,
    byte_offset: usize,
    trim_trailing_spaces: bool,
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
    if (trim_trailing_spaces) {
        while (visible_end > segment_start and
            isDiscardable(glyphs[visible_end - 1]))
        {
            visible_end -= 1;
        }
    }
    if (visible_end <= segment_start) return null;
    return .{
        .glyph_end = visible_end,
        .next_glyph_start = break_index,
        .byte_end = byte_offset,
    };
}

fn insertSortedUnique(
    output: *std.ArrayList(shared.SoftCandidate),
    allocator: std.mem.Allocator,
    candidate: shared.SoftCandidate,
) !void {
    var index: usize = 0;
    while (index < output.items.len and
        output.items[index].next_glyph_start <
            candidate.next_glyph_start) : (index += 1)
    {}
    if (index < output.items.len and
        output.items[index].next_glyph_start ==
            candidate.next_glyph_start)
    {
        // break-spaces owns the authored blank, unlike ordinary UAX SP
        // candidates which omit it from the visible prefix.
        if (candidate.glyph_end > output.items[index].glyph_end) {
            output.items[index] = candidate;
        }
        return;
    }
    try output.insert(allocator, index, candidate);
}

fn isDiscardable(glyph: GlyphPosition) bool {
    return glyph.codepoint == ' ' or glyph.isTab();
}

const SourceRange = struct {
    start: usize,
    len: usize,
};

fn softHyphenEndingAt(text: []const u8, byte_offset: usize) ?SourceRange {
    const encoded = "\u{00ad}";
    if (byte_offset < encoded.len or byte_offset > text.len) return null;
    const start = byte_offset - encoded.len;
    if (!std.mem.eql(u8, text[start..byte_offset], encoded)) return null;
    return .{ .start = start, .len = encoded.len };
}
