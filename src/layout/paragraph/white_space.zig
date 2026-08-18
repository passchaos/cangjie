//! Source-preserving paragraph whitespace normalization.
//!
//! Reflow changes advances rather than deleting glyphs. Every original UTF-8
//! atom therefore remains available to caret, selection, bidi, styled
//! metadata, and accessibility geometry even when its visual width collapses.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const paragraph_types = @import("../types/paragraph.zig");

pub fn prepare(
    glyphs: []GlyphPosition,
    mode: paragraph_types.WhiteSpaceCollapse,
    ordinary_space_advance: f32,
) void {
    prepareAxis(glyphs, mode, ordinary_space_advance, .horizontal);
}

/// Vertical counterpart of `prepare`.
///
/// Public vertical shaping advances are positive-down, so the same collapse
/// state machine can operate directly on `y_advance`; no HarfBuzz sign
/// conversion belongs in paragraph layout.
pub fn prepareVertical(
    glyphs: []GlyphPosition,
    mode: paragraph_types.WhiteSpaceCollapse,
    ordinary_space_advance: f32,
) void {
    prepareAxis(glyphs, mode, ordinary_space_advance, .vertical);
}

pub fn defaultVerticalSpaceAdvance(glyphs: []const GlyphPosition) f32 {
    for (glyphs) |glyph| {
        if (glyph.codepoint == ' ') return @max(glyph.y_advance, 1);
    }
    return 1;
}

const Axis = enum { horizontal, vertical };

fn prepareAxis(
    glyphs: []GlyphPosition,
    mode: paragraph_types.WhiteSpaceCollapse,
    ordinary_space_advance: f32,
    axis: Axis,
) void {
    for (glyphs) |*glyph| {
        glyph.flags.collapsed_whitespace = false;
    }
    if (mode != .collapse) return;

    var at_segment_start = true;
    var visible_blank_in_run = false;
    for (glyphs) |*glyph| {
        if (isMandatory(glyph.codepoint)) {
            at_segment_start = true;
            visible_blank_in_run = false;
            continue;
        }
        if (!isCollapsible(glyph.*)) {
            at_segment_start = false;
            visible_blank_in_run = false;
            continue;
        }

        glyph.flags.collapsed_whitespace = true;
        if (!at_segment_start and !visible_blank_in_run) {
            setAdvance(glyph, axis, @max(
                0,
                if (glyph.isTab())
                    ordinary_space_advance
                else
                    advance(glyph.*, axis),
            ));
            visible_blank_in_run = true;
        } else {
            setAdvance(glyph, axis, 0);
        }
    }
}

pub fn trimLineStart(
    glyphs: []GlyphPosition,
    start: usize,
) void {
    var index = start;
    while (index < glyphs.len and
        glyphs[index].isCollapsedWhitespace())
    {
        glyphs[index].x_advance = 0;
        index += 1;
    }
}

pub fn trimLineEnd(
    glyphs: []GlyphPosition,
    start: usize,
    end: usize,
) void {
    var index = @min(end, glyphs.len);
    while (index > start and
        glyphs[index - 1].isCollapsedWhitespace())
    {
        index -= 1;
        glyphs[index].x_advance = 0;
    }
}

pub fn trimVerticalLineStart(
    glyphs: []GlyphPosition,
    start: usize,
    end: usize,
) void {
    var index = @min(start, glyphs.len);
    const actual_end = @min(end, glyphs.len);
    while (index < actual_end and
        glyphs[index].isCollapsedWhitespace())
    {
        glyphs[index].y_advance = 0;
        index += 1;
    }
}

pub fn trimVerticalLineEnd(
    glyphs: []GlyphPosition,
    start: usize,
    end: usize,
) void {
    const actual_start = @min(start, glyphs.len);
    var index = @min(end, glyphs.len);
    while (index > actual_start and
        glyphs[index - 1].isCollapsedWhitespace())
    {
        index -= 1;
        glyphs[index].y_advance = 0;
    }
}

/// Zero collapsed source atoms omitted between adjacent visible line ranges.
pub fn zeroVerticalCollapsedRange(
    glyphs: []GlyphPosition,
    start: usize,
    end: usize,
) void {
    for (glyphs[@min(start, glyphs.len)..@min(end, glyphs.len)]) |*glyph| {
        if (glyph.isCollapsedWhitespace()) glyph.y_advance = 0;
    }
}

pub fn lineWidth(
    glyphs: []GlyphPosition,
    start: usize,
    end: usize,
) f32 {
    trimLineStart(glyphs, start);
    trimLineEnd(glyphs, start, end);
    var width: f32 = 0;
    for (glyphs[start..@min(end, glyphs.len)]) |glyph| {
        width += glyph.x_advance;
    }
    return width;
}

pub fn measureRange(
    glyphs: []const GlyphPosition,
    start: usize,
    end: usize,
    mode: paragraph_types.WhiteSpaceCollapse,
) f32 {
    const actual_end = @min(end, glyphs.len);
    var visible_start = @min(start, actual_end);
    var visible_end = actual_end;
    if (mode == .collapse) {
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
    var width: f32 = 0;
    for (glyphs[visible_start..visible_end]) |glyph| {
        width += glyph.x_advance;
    }
    return width;
}

pub fn measureVerticalRange(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    end: usize,
    mode: paragraph_types.WhiteSpaceCollapse,
) f32 {
    const actual_end = @min(end, glyphs.len);
    var visible_start = @min(start, actual_end);
    var visible_end = actual_end;
    if (mode == .collapse) {
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
    return prefix[visible_end] - prefix[visible_start];
}

pub fn shouldDiscardAfterSoftWrap(
    mode: paragraph_types.WhiteSpaceCollapse,
) bool {
    return mode != .break_spaces;
}

pub fn isCollapsible(glyph: GlyphPosition) bool {
    return glyph.codepoint == ' ' or glyph.isTab();
}

fn isMandatory(codepoint: u21) bool {
    return switch (@import("../../unicode.zig").lineBreakClassForCodepoint(
        codepoint,
    )) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

fn advance(glyph: GlyphPosition, axis: Axis) f32 {
    return switch (axis) {
        .horizontal => glyph.x_advance,
        .vertical => glyph.y_advance,
    };
}

fn setAdvance(glyph: *GlyphPosition, axis: Axis, value: f32) void {
    switch (axis) {
        .horizontal => glyph.x_advance = value,
        .vertical => glyph.y_advance = value,
    }
}

test "collapse retains source atoms with one visible interior blank" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = ' ', .cluster = 0, .x_advance = 8 },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 1, .x_advance = 16 },
        .{ .glyph_id = 1, .codepoint = ' ', .cluster = 2, .x_advance = 8 },
        .{ .glyph_id = 1, .codepoint = ' ', .cluster = 3, .x_advance = 8 },
        .{
            .glyph_id = 0,
            .codepoint = '\t',
            .cluster = 4,
            .x_advance = 0,
            .flags = .{ .tab = true },
        },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 5, .x_advance = 16 },
        .{ .glyph_id = 1, .codepoint = ' ', .cluster = 6, .x_advance = 8 },
    };
    prepare(&glyphs, .collapse, 8);
    try std.testing.expectEqual(@as(f32, 0), glyphs[0].x_advance);
    try std.testing.expectEqual(@as(f32, 8), glyphs[2].x_advance);
    try std.testing.expectEqual(@as(f32, 0), glyphs[3].x_advance);
    try std.testing.expectEqual(@as(f32, 0), glyphs[4].x_advance);
    try std.testing.expect(glyphs[4].isTab());
    try std.testing.expect(!glyphs[4].isActiveTab());
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        lineWidth(&glyphs, 0, glyphs.len),
        0.001,
    );
    try std.testing.expectEqual(@as(f32, 0), glyphs[6].x_advance);
}
