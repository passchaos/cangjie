//! Line geometry, strut metrics, and spacing helpers for paragraph reflow.
//!
//! These operations are independent from break selection. Keeping them in a
//! separate module makes the greedy reflow state machine about source/output
//! boundaries rather than font metric bookkeeping.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const inline_object = @import("../../inline_object/root.zig");
const run_types = @import("../../types/runs.zig");

pub const BaselineMetrics = struct {
    ascent: f32,
    descent: f32,
    leading: f32,

    pub fn lineHeight(self: BaselineMetrics) f32 {
        return self.ascent + self.descent + self.leading;
    }
};

pub const LineRunInfo = struct {
    run_start: usize,
    run_len: usize,
    metrics: BaselineMetrics,
};

pub const RunRange = struct {
    start: usize,
    len: usize,
};

pub fn defaultBaselineMetrics(
    font: *const Font,
    font_size: f32,
) BaselineMetrics {
    const units = @as(f32, @floatFromInt(font.units_per_em));
    const scale = font_size / units;
    const ascender = @as(f32, @floatFromInt(font.ascender));
    const descender = @as(f32, @floatFromInt(font.descender));
    const line_gap = @as(f32, @floatFromInt(font.line_gap));
    return .{
        .ascent = ascender * scale,
        .descent = -descender * scale,
        .leading = line_gap * scale,
    };
}

pub fn lineRunInfo(
    runs: anytype,
    glyphs: []const GlyphPosition,
    objects: []const inline_object.Object,
    glyph_start: usize,
    glyph_end: usize,
    default_metrics: BaselineMetrics,
    explicit_line_height: ?f32,
) LineRunInfo {
    // The primary font is the paragraph's minimum strut, so empty lines and
    // fallback-only lines retain a stable baseline. Actual runs can enlarge
    // any side of that strut; otherwise a fallback with taller ascenders or
    // deeper descenders would be clipped by primary-font-only geometry.
    var metrics = default_metrics;
    var first_run: ?usize = null;
    var run_end_index: usize = 0;
    for (runs, 0..) |run, run_index| {
        const run_start = run.glyph_start;
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run_start >= glyph_end) continue;
        if (first_run == null) first_run = run_index;
        run_end_index = run_index + 1;
        const run_metrics = defaultBaselineMetrics(
            run_types.fontForBackend(run),
            run.font_size,
        );
        metrics.ascent = @max(metrics.ascent, run_metrics.ascent);
        metrics.descent = @max(metrics.descent, run_metrics.descent);
        metrics.leading = @max(metrics.leading, run_metrics.leading);
    }
    for (glyphs[glyph_start..glyph_end]) |glyph| {
        if (!glyph.isInlineObject()) continue;
        const object = inline_object.find(objects, glyph.cluster) orelse
            continue;
        if (object.kind != .in_flow) continue;
        const object_metrics = inline_object.verticalMetrics(object);
        metrics.ascent = @max(metrics.ascent, object_metrics.ascent);
        metrics.descent = @max(metrics.descent, object_metrics.descent);
    }
    const run_start_index = first_run orelse 0;
    return .{
        .run_start = run_start_index,
        .run_len = run_end_index - run_start_index,
        .metrics = if (explicit_line_height) |line_height|
            metricsForLineHeight(metrics, line_height)
        else
            metrics,
    };
}

pub fn resolvedAlignment(options: anytype) @TypeOf(options.alignment) {
    return switch (options.alignment) {
        .start => if (options.direction == .rtl) .right else .left,
        .end => if (options.direction == .rtl) .left else .right,
        .left, .center, .right, .justify => options.alignment,
    };
}

pub fn lineIndent(line_index: usize, options: anytype) f32 {
    if (line_index == 0) return @max(0, options.first_line_indent);
    return 0;
}

pub fn lineWidthLimit(
    line_index: usize,
    max_width: f32,
    options: anytype,
) f32 {
    return lineWidthLimitForIndent(
        max_width,
        lineIndent(line_index, options),
    );
}

pub fn lineWidthLimitForIndent(max_width: f32, indent: f32) f32 {
    if (!std.math.isFinite(max_width)) return max_width;
    return @max(0, max_width - indent);
}

pub fn appendLine(
    buffer: anytype,
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
    width: f32,
    run_info: LineRunInfo,
    y: f32,
    alignment: anytype,
    max_width: f32,
    indent: f32,
) !void {
    const available_width = lineWidthLimitForIndent(max_width, indent);
    const x = indent + alignedLineX(width, available_width, alignment);
    const metrics = run_info.metrics;
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = run_info.run_start,
        .run_len = run_info.run_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .x = x,
        .y = y,
        .width = width,
        .height = metrics.lineHeight(),
        .baseline = metrics.ascent,
        .ascent = metrics.ascent,
        .descent = metrics.descent,
        .leading = metrics.leading,
    });
}

pub fn alignedLineX(width: f32, max_width: f32, alignment: anytype) f32 {
    if (!std.math.isFinite(max_width)) return 0;
    return switch (alignment) {
        .left, .justify => 0,
        .center => @max(0, (max_width - width) / 2),
        .right => @max(0, max_width - width),
        .start, .end => unreachable, // Resolved at the reflow boundary.
    };
}

pub fn lineWidth(glyphs: []const GlyphPosition) f32 {
    var width: f32 = 0;
    for (glyphs) |glyph| width += glyph.x_advance;
    return width;
}

pub fn defaultSpaceAdvance(glyphs: []const GlyphPosition) f32 {
    for (glyphs) |glyph| {
        if (glyph.codepoint == ' ') return @max(glyph.x_advance, 1);
    }
    for (glyphs) |glyph| {
        if (glyph.codepoint != '\n' and
            glyph.codepoint != '\t' and
            glyph.x_advance > 0)
        {
            return glyph.x_advance;
        }
    }
    return 1;
}

pub fn tabAdvance(
    current_width: f32,
    tab_stop: f32,
    fallback_advance: f32,
) f32 {
    if (tab_stop <= 0) return fallback_advance;
    const stops_passed = @floor(current_width / tab_stop);
    const next_stop = (stops_passed + 1) * tab_stop;
    return @max(fallback_advance, next_stop - current_width);
}

pub fn spacingForGlyph(codepoint: u21, options: anytype) f32 {
    if (codepoint == '\n') return 0;
    if (codepoint == discretionary_hyphen.soft_hyphen) return 0;
    if (codepoint == ' ' or codepoint == '\t') return options.word_spacing;
    return options.letter_spacing;
}

pub fn trimLeadingSoftBreaks(
    glyphs: []const GlyphPosition,
    start: *usize,
) void {
    while (start.* < glyphs.len and
        isDiscardableBreak(glyphs[start.*].codepoint))
    {
        start.* += 1;
    }
}

pub fn isDiscardableBreak(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t';
}

pub fn runRangeForGlyphs(
    runs: anytype,
    glyph_start: usize,
    glyph_end: usize,
) RunRange {
    var start: ?usize = null;
    var end: usize = 0;
    for (runs, 0..) |run, index| {
        const run_start = run.glyph_start;
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run_start >= glyph_end) continue;
        if (start == null) start = index;
        end = index + 1;
    }
    const actual_start = start orelse 0;
    return .{ .start = actual_start, .len = end - actual_start };
}

fn metricsForLineHeight(
    default_metrics: BaselineMetrics,
    line_height: f32,
) BaselineMetrics {
    const natural_height = default_metrics.lineHeight();
    if (natural_height <= 0) {
        return .{ .ascent = line_height, .descent = 0, .leading = 0 };
    }
    const extra_leading = @max(0, line_height - natural_height);
    return .{
        .ascent = default_metrics.ascent + extra_leading / 2,
        .descent = default_metrics.descent,
        .leading = default_metrics.leading + extra_leading / 2,
    };
}
