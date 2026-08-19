//! Inline-size helpers for vertical wrapping and whitespace edge policy.

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_options = @import("../options.zig");
const punctuation_hanging = @import("../../punctuation/hanging.zig");
const tabs = @import("../tabs.zig");
const vertical_tabs = @import("tabs.zig");
const white_space = @import("../white_space.zig");

pub fn fillPrefix(prefix: []f32, glyphs: []const GlyphPosition) void {
    prefix[0] = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        prefix[glyph_index + 1] = prefix[glyph_index] + glyph.y_advance;
    }
}

pub fn inlineSize(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    options: paragraph_options.Options,
) f32 {
    const actual_end = @min(end, glyphs.len);
    var visible_start = @min(start, actual_end);
    var visible_end = actual_end;
    if (options.white_space_collapse == .collapse) {
        while (visible_start < visible_end and
            glyphs[visible_start].isCollapsedWhitespace())
        {
            visible_start += 1;
        }
        while (visible_end > visible_start and
            glyphs[visible_end - 1].isCollapsedWhitespace())
        {
            visible_end -= 1;
        }
    }
    const visible = glyphs[visible_start..visible_end];
    if (vertical_tabs.contains(visible)) {
        const fallback_advance =
            white_space.defaultVerticalSpaceAdvance(glyphs);
        const fallback_interval =
            @as(f32, @floatFromInt(@max(1, options.tab_width))) *
            fallback_advance;
        return vertical_tabs.measureRange(
            visible,
            options.tab_stops,
            fallback_interval,
            fallback_advance,
        );
    }
    return white_space.measureVerticalRange(
        glyphs,
        prefix,
        visible_start,
        visible_end,
        options.white_space_collapse,
    );
}

/// Occupied inline measure used by line fitting.
///
/// The full glyph advance remains in `inlineSize`; an eligible logical-end
/// punctuation glyph may protrude below the requested column measure.
pub fn occupiedInlineSize(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    options: paragraph_options.Options,
) f32 {
    const full = inlineSize(glyphs, prefix, start, end, options);
    return @max(
        0,
        full - punctuation_hanging.verticalLogicalEndAmount(
            glyphs,
            start,
            @min(end, glyphs.len),
            options.punctuation.end_hanging_fraction,
        ),
    );
}

/// Measure a growing column prefix with complete tab-field lookahead.
///
/// Exact candidate and committed-column measurement intentionally truncates a
/// tab field at the selected boundary. Prospective overflow scanning instead
/// matches horizontal greedy behavior and inspects the complete following
/// field before deciding whether the tab can remain in this column.
pub fn prospectiveInlineSize(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    segment_end: usize,
    options: paragraph_options.Options,
) f32 {
    const actual_end = @min(end, glyphs.len);
    const actual_segment_end = @min(segment_end, glyphs.len);
    var visible_start = @min(start, actual_end);
    var visible_end = actual_end;
    if (options.white_space_collapse == .collapse) {
        while (visible_start < visible_end and
            glyphs[visible_start].isCollapsedWhitespace())
        {
            visible_start += 1;
        }
        while (visible_end > visible_start and
            glyphs[visible_end - 1].isCollapsedWhitespace())
        {
            visible_end -= 1;
        }
    }
    if (vertical_tabs.contains(glyphs[visible_start..visible_end])) {
        const fallback_advance =
            white_space.defaultVerticalSpaceAdvance(glyphs);
        const fallback_interval =
            @as(f32, @floatFromInt(@max(1, options.tab_width))) *
            fallback_advance;
        return vertical_tabs.measurePrefix(
            glyphs[visible_start..actual_segment_end],
            visible_end - visible_start,
            options.tab_stops,
            fallback_interval,
            fallback_advance,
        );
    }
    return white_space.measureVerticalRange(
        glyphs,
        prefix,
        visible_start,
        visible_end,
        options.white_space_collapse,
    );
}

pub fn firstOverflow(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    glyph_start: usize,
    glyph_end: usize,
    segment_end: usize,
    limit: f32,
    options: paragraph_options.Options,
) usize {
    var index = glyph_start + 1;
    while (index <= glyph_end and
        occupiedProspectiveInlineSize(
            glyphs,
            prefix,
            glyph_start,
            index,
            segment_end,
            options,
        ) <= limit)
    {
        index += 1;
    }
    return @min(index, glyph_end);
}

fn occupiedProspectiveInlineSize(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    segment_end: usize,
    options: paragraph_options.Options,
) f32 {
    const full = prospectiveInlineSize(
        glyphs,
        prefix,
        start,
        end,
        segment_end,
        options,
    );
    return @max(
        0,
        full - punctuation_hanging.verticalLogicalEndAmount(
            glyphs,
            start,
            @min(end, glyphs.len),
            options.punctuation.end_hanging_fraction,
        ),
    );
}
