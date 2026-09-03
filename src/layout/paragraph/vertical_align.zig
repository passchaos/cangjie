//! Final inline placement inside a resolved paragraph line box.
//!
//! Shaping offsets remain font-layout output. This module adds the style's
//! line-box offset only after wrapping, source-level reshaping, and bidi have
//! finalized glyph/metadata cardinality and visual line ownership.

const std = @import("std");

const inline_object = @import("../inline_object/root.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const styled_buffer = @import("../styled_buffer.zig");

pub fn apply(
    glyphs: []@import("../glyph_position.zig").GlyphPosition,
    runs: []const run_types.CascadeRun,
    lines: []const paragraph_types.ParagraphLine,
    objects: []const inline_object.Object,
    metadata: []const styled_buffer.Metadata,
) !void {
    if (glyphs.len != metadata.len) return error.InvalidStyleSpans;
    for (lines) |line| {
        const line_end = line.glyph_start + line.glyph_len;
        if (line_end > glyphs.len) return error.InvalidParagraphLayout;
        for (
            glyphs[line.glyph_start..line_end],
            metadata[line.glyph_start..line_end],
            line.glyph_start..,
        ) |*glyph, item, glyph_index| {
            if (item.vertical_align == .baseline and
                item.baseline_shift == 0) continue;
            const extents = if (glyph.isInlineObject()) extents: {
                const object = inline_object.find(
                    objects,
                    glyph.cluster,
                ) orelse return error.InvalidInlineObjects;
                const metrics = inline_object.verticalMetrics(object);
                break :extents Extents{
                    .ascent = metrics.ascent,
                    .descent = metrics.descent,
                };
            } else extents: {
                const run = runForGlyph(runs, glyph_index) orelse continue;
                const metrics = @import("../line_break/reflow/geometry.zig")
                    .defaultBaselineMetrics(
                    run_types.fontForBackend(run),
                    run.font_size,
                );
                break :extents Extents{
                    .ascent = metrics.ascent,
                    .descent = metrics.descent,
                };
            };
            // `offset` and public baseline shift use physical y-down block
            // coordinates. GlyphPosition.y_offset is HarfBuzz y-up and is
            // subtracted by renderers, so convert the sign at this boundary.
            glyph.y_offset -= offset(line, extents, item.vertical_align) +
                item.baseline_shift;
        }
    }
}

pub fn fontOffset(
    line: paragraph_types.ParagraphLine,
    run: run_types.CascadeRun,
    alignment: paragraph_types.VerticalAlign,
) f32 {
    const metrics = @import("../line_break/reflow/geometry.zig")
        .defaultBaselineMetrics(
        run_types.fontForBackend(run),
        run.font_size,
    );
    return offset(
        line,
        .{ .ascent = metrics.ascent, .descent = metrics.descent },
        alignment,
    );
}

pub fn fontPhysicalOffset(
    line: paragraph_types.ParagraphLine,
    run: run_types.CascadeRun,
    alignment: paragraph_types.VerticalAlign,
    baseline_shift: f32,
) f32 {
    return fontOffset(line, run, alignment) + baseline_shift;
}

const Extents = struct {
    ascent: f32,
    descent: f32,
};

fn offset(
    line: paragraph_types.ParagraphLine,
    extents: Extents,
    alignment: paragraph_types.VerticalAlign,
) f32 {
    return switch (alignment) {
        .baseline => 0,
        .top => extents.ascent - line.baseline,
        .middle => (line.height - extents.ascent - extents.descent) / 2 +
            extents.ascent - line.baseline,
        .bottom => line.height - line.baseline - extents.descent,
    };
}

fn runForGlyph(
    runs: []const run_types.CascadeRun,
    glyph_index: usize,
) ?run_types.CascadeRun {
    var low: usize = 0;
    var high = runs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const run = runs[mid];
        if (glyph_index < run.glyph_start) {
            high = mid;
        } else if (glyph_index >= run.glyph_start + run.glyph_len) {
            low = mid + 1;
        } else {
            return run;
        }
    }
    return null;
}

test "line box offsets align font extents" {
    const line = paragraph_types.ParagraphLine{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 1,
        .x = 0,
        .y = 0,
        .width = 10,
        .height = 30,
        .baseline = 20,
        .ascent = 20,
        .descent = 10,
        .leading = 0,
    };
    const extents = Extents{ .ascent = 12, .descent = 4 };
    try std.testing.expectEqual(@as(f32, -8), offset(line, extents, .top));
    try std.testing.expectEqual(@as(f32, -1), offset(line, extents, .middle));
    try std.testing.expectEqual(@as(f32, 6), offset(line, extents, .bottom));
}
