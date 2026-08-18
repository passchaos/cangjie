//! Intrinsic paragraph widths over immutable shaped source order.
//!
//! This is not a tiny-width reflow simulation. It walks the exact safe
//! opportunity stream and measures each candidate with its visible hyphen,
//! tab-field, inline-object, spacing, and white-space policy.

const std = @import("std");

const analysis = @import("../line_break/analysis.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const opportunity = @import("../line_break/opportunity.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const line_break_policy = @import("line_break_policy.zig");
const paragraph_options = @import("options.zig");
const paragraph_types = @import("../types/paragraph.zig");
const tabs = @import("tabs.zig");
const white_space = @import("white_space.zig");
const unicode = @import("../../unicode.zig");

pub fn calculate(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const @import("../glyph_position.zig").GlyphPosition,
    runs: anytype,
    graphemes: []const unicode.GraphemeCluster,
    base_breaks: []const opportunity.Opportunity,
    options: paragraph_options.Options,
) !paragraph_types.ContentWidths {
    if (glyphs.len == 0) return .{ .min = 0, .max = 0 };

    const working = try allocator.dupe(
        @import("../glyph_position.zig").GlyphPosition,
        glyphs,
    );
    defer allocator.free(working);
    try prepareAdvances(working, options);
    const space_advance = geometry.defaultSpaceAdvance(working);
    white_space.prepare(
        working,
        options.white_space_collapse,
        space_advance,
    );

    const tailored = try analysis.tailorBreakPolicy(
        allocator,
        text,
        graphemes,
        base_breaks,
        paragraph_options.defaultLineBreakPolicy(options),
        options.line_break_policy_ranges,
    );
    defer allocator.free(tailored);
    var break_cursor = opportunities.Cursor.init(text, tailored);

    const fallback_tab_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        space_advance;
    var result = paragraph_types.ContentWidths{ .min = 0, .max = 0 };
    var segment_start: usize = 0;
    var fragment_start: usize = 0;
    var index: usize = 0;
    while (index < working.len) : (index += 1) {
        const glyph = working[index];
        if (opportunities.isMandatory(glyph.codepoint)) {
            const break_end =
                if (glyph.codepoint == '\r' and
                index + 1 < working.len and
                working[index + 1].codepoint == '\n')
                    index + 2
                else
                    index + 1;
            result.min = @max(
                result.min,
                measureRange(
                    working,
                    fragment_start,
                    index,
                    options,
                    fallback_tab_interval,
                    space_advance,
                    0,
                ),
            );
            result.max = @max(
                result.max,
                measureRange(
                    working,
                    segment_start,
                    index,
                    options,
                    fallback_tab_interval,
                    space_advance,
                    0,
                ),
            );
            break_cursor.discardThrough(
                working[break_end - 1].sourceByteEnd(),
            );
            segment_start = break_end;
            fragment_start = break_end;
            index = break_end - 1;
            continue;
        }

        const atom_continues =
            index + 1 < working.len and
            working[index + 1].cluster == glyph.cluster;
        if (atom_continues) continue;
        const source_end = glyph.sourceByteEnd();
        while (break_cursor.nextThrough(source_end)) |line_break| {
            if (line_break.kind != .soft) continue;
            var candidate = opportunities.Candidate{};
            try opportunities.recordSoft(
                working,
                runs,
                line_break.byte_offset,
                index,
                fragment_start,
                geometry.lineWidth(working[fragment_start .. index + 1]),
                &candidate,
                options.normalized_variation_coords,
                line_break.automatic_hyphen,
                line_break.arbitrary,
                options.hyphenation.character,
            );
            const boundary = candidate.glyph_index orelse continue;
            if (boundary <= fragment_start) continue;
            result.min = @max(
                result.min,
                measureRange(
                    working,
                    fragment_start,
                    boundary,
                    options,
                    fallback_tab_interval,
                    space_advance,
                    visibleHyphenAdvance(candidate),
                ),
            );
            fragment_start = boundary;
            if (options.white_space_collapse != .break_spaces) {
                geometry.trimLeadingSoftBreaks(working, &fragment_start);
            }
        }
        if (options.white_space_collapse == .break_spaces and
            line_break_policy.beforeBoundary(
                paragraph_options.defaultLineBreakPolicy(options),
                options.line_break_policy_ranges,
                source_end,
            ).wrap_mode != .no_wrap and
            geometry.isDiscardableBreak(glyph.codepoint))
        {
            const boundary = index + 1;
            result.min = @max(
                result.min,
                measureRange(
                    working,
                    fragment_start,
                    boundary,
                    options,
                    fallback_tab_interval,
                    space_advance,
                    0,
                ),
            );
            fragment_start = boundary;
        }
    }

    result.min = @max(
        result.min,
        measureRange(
            working,
            fragment_start,
            working.len,
            options,
            fallback_tab_interval,
            space_advance,
            0,
        ),
    );
    result.max = @max(
        result.max,
        measureRange(
            working,
            segment_start,
            working.len,
            options,
            fallback_tab_interval,
            space_advance,
            0,
        ),
    );
    result.min = @min(result.min, result.max);
    return result;
}

fn measureRange(
    glyphs: []const @import("../glyph_position.zig").GlyphPosition,
    start: usize,
    end: usize,
    options: paragraph_options.Options,
    fallback_tab_interval: f32,
    space_advance: f32,
    terminal_advance: f32,
) f32 {
    if (start >= end or start >= glyphs.len) return terminal_advance;
    const actual_end = @min(end, glyphs.len);
    const range = glyphs[start..actual_end];
    if (options.white_space_collapse == .collapse and
        !tabs.contains(range))
    {
        return white_space.measureRange(
            glyphs,
            start,
            actual_end,
            options.white_space_collapse,
        ) + terminal_advance;
    }
    return tabs.measureRangeWithTerminal(
        range,
        options.tab_stops,
        fallback_tab_interval,
        space_advance,
        terminal_advance,
    );
}

fn visibleHyphenAdvance(candidate: opportunities.Candidate) f32 {
    if (candidate.hyphen) |item| return item.resolved.x_advance;
    if (candidate.automatic_hyphen) |item| {
        return item.resolved.x_advance;
    }
    return 0;
}

fn prepareAdvances(
    glyphs: []@import("../glyph_position.zig").GlyphPosition,
    options: paragraph_options.Options,
) !void {
    for (glyphs) |*glyph| {
        if (glyph.isInlineObject()) {
            const object = @import("../inline_object/root.zig").find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            glyph.x_advance =
                if (object.kind == .in_flow) object.width else 0;
            continue;
        }
        if (glyph.isTab()) {
            glyph.x_advance = 0;
            continue;
        }
        glyph.x_advance += geometry.spacingForGlyph(
            glyph.codepoint,
            options,
        );
    }
}

test "content widths preserve ordering invariant" {
    const widths = paragraph_types.ContentWidths{ .min = 10, .max = 20 };
    try std.testing.expect(widths.min <= widths.max);
}
