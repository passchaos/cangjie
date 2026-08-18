//! Intrinsic inline-size measurement for vertical paragraphs.

const std = @import("std");
const candidates = @import("candidates.zig");
const geometry = @import("../../line_break/reflow/geometry.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const paragraph_options = @import("../options.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const policy = @import("policy.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");

pub fn measure(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
) !paragraph_types.ContentWidths {
    var effective_breaks = try policy.resolve(
        allocator,
        text,
        graphemes,
        breaks,
        options,
    );
    defer effective_breaks.deinit();
    const prefix = try allocator.alloc(f32, glyphs.len + 1);
    defer allocator.free(prefix);
    prefix[0] = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        prefix[glyph_index + 1] = prefix[glyph_index] +
            if (isMandatory(glyph.codepoint))
                0
            else
                glyph.y_advance + geometry.spacingForGlyph(
                    glyph.codepoint,
                    options,
                );
    }

    var result = paragraph_types.ContentWidths{ .min = 0, .max = 0 };
    var segment_start: usize = 0;
    var segment_byte_start: usize = 0;
    var index: usize = 0;
    while (index < glyphs.len) : (index += 1) {
        if (!isMandatory(glyphs[index].codepoint)) continue;
        try segment(
            allocator,
            &result,
            glyphs,
            prefix,
            graphemes,
            effective_breaks.items,
            options,
            segment_start,
            index,
            segment_byte_start,
            glyphs[index].cluster,
        );
        const break_end = if (glyphs[index].codepoint == '\r' and
            index + 1 < glyphs.len and
            glyphs[index + 1].codepoint == '\n')
            index + 2
        else
            index + 1;
        segment_start = break_end;
        segment_byte_start = glyphs[break_end - 1].sourceByteEnd();
        index = break_end - 1;
    }
    try segment(
        allocator,
        &result,
        glyphs,
        prefix,
        graphemes,
        effective_breaks.items,
        options,
        segment_start,
        glyphs.len,
        segment_byte_start,
        text.len,
    );
    result.min = @min(result.min, result.max);
    return result;
}

fn segment(
    allocator: std.mem.Allocator,
    result: *paragraph_types.ContentWidths,
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
    segment_start: usize,
    segment_end: usize,
    segment_byte_start: usize,
    segment_byte_end: usize,
) !void {
    result.max = @max(
        result.max,
        shared.advance(prefix, segment_start, segment_end),
    );
    if (options.wrap_mode == .no_wrap or segment_start >= segment_end) {
        result.min = @max(
            result.min,
            shared.advance(prefix, segment_start, segment_end),
        );
        return;
    }

    var items = std.ArrayList(shared.SoftCandidate).empty;
    defer items.deinit(allocator);
    try candidates.collect(
        &items,
        allocator,
        glyphs,
        graphemes,
        breaks,
        segment_start,
        segment_end,
        segment_byte_start,
        segment_byte_end,
    );
    var fragment_start = segment_start;
    for (items.items) |candidate| {
        if (candidate.next_glyph_start <= fragment_start) continue;
        result.min = @max(
            result.min,
            shared.advance(prefix, fragment_start, candidate.glyph_end),
        );
        fragment_start = candidate.next_glyph_start;
    }
    result.min = @max(
        result.min,
        shared.advance(prefix, fragment_start, segment_end),
    );
}

fn isMandatory(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}
