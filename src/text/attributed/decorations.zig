//! Final attributed text-decoration geometry.
//!
//! Decoration ownership is the intersection of a visual line, paint style,
//! and final font run. This keeps fallback metrics, bidi order, wrapping, and
//! post-reflow advances in one paragraph-space output rather than asking a
//! renderer to reconstruct those boundaries.

const std = @import("std");

const glyph_position = @import("../../layout/glyph_position.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const raster = @import("../../raster.zig");
const run_types = @import("../../layout/types/runs.zig");
const vertical_align = @import("../../layout/paragraph/vertical_align.zig");

pub const Kind = enum {
    underline,
    strikethrough,
};

/// One physically contiguous decoration rectangle.
pub const Segment = struct {
    kind: Kind,
    style_index: u32,
    font_run_index: usize,
    line_index: usize,
    rect: paragraph_types.TextRect,
    color: raster.Rgba,
};

pub fn build(
    allocator: std.mem.Allocator,
    paragraph: paragraph_types.ParagraphLayout,
    style_runs: anytype,
) ![]Segment {
    var output = std.ArrayList(Segment).empty;
    errdefer output.deinit(allocator);

    for (paragraph.lines, 0..) |line, line_index| {
        const line_end = line.glyph_start + line.glyph_len;
        for (style_runs) |style_run| {
            if (!style_run.style.decoration.underline and
                !style_run.style.decoration.strikethrough)
            {
                continue;
            }
            const style_end = style_run.glyph_start + style_run.glyph_len;
            const styled_start = @max(line.glyph_start, style_run.glyph_start);
            const styled_end = @min(line_end, style_end);
            if (styled_start >= styled_end) continue;

            var fragment_start = styled_start;
            var fragment_owner = decorationOwner(
                paragraph,
                styled_start,
                styled_start,
                styled_end,
            );
            var index = styled_start + 1;
            while (index <= styled_end) : (index += 1) {
                const owner = if (index < styled_end)
                    decorationOwner(
                        paragraph,
                        index,
                        styled_start,
                        styled_end,
                    )
                else
                    null;
                if (owner == fragment_owner and index < styled_end) continue;
                if (fragment_owner) |font_run_index| {
                    try appendFragment(
                        &output,
                        allocator,
                        paragraph,
                        line,
                        line_index,
                        style_run,
                        font_run_index,
                        fragment_start,
                        index,
                    );
                }
                fragment_start = index;
                fragment_owner = owner;
            }
        }
    }
    return output.toOwnedSlice(allocator);
}

fn decorationOwner(
    paragraph: paragraph_types.ParagraphLayout,
    glyph_index: usize,
    range_start: usize,
    range_end: usize,
) ?usize {
    if (fontRunIndex(paragraph.runs, glyph_index)) |owner| return owner;
    const glyph = paragraph.glyphs[glyph_index];
    if (!glyph.isTab()) return null;

    var previous_owner: ?usize = null;
    var previous_distance: usize = 0;
    var previous = glyph_index;
    while (previous > range_start) {
        previous -= 1;
        if (paragraph.glyphs[previous].isInlineObject()) break;
        if (fontRunIndex(paragraph.runs, previous)) |owner| {
            previous_owner = owner;
            previous_distance = glyph_index - previous;
            break;
        }
    }

    var next_owner: ?usize = null;
    var next_distance: usize = 0;
    var next = glyph_index + 1;
    while (next < range_end) : (next += 1) {
        if (paragraph.glyphs[next].isInlineObject()) break;
        if (fontRunIndex(paragraph.runs, next)) |owner| {
            next_owner = owner;
            next_distance = next - glyph_index;
            break;
        }
    }

    // A run of adjacent tabs can sit between two fallback fonts. Split that
    // run at its nearest owner instead of assigning every tab to the font on
    // one side; ties prefer the preceding glyph for stable text progression.
    if (previous_owner != null and
        (next_owner == null or previous_distance <= next_distance))
    {
        return previous_owner;
    }
    return next_owner;
}

fn appendFragment(
    output: *std.ArrayList(Segment),
    allocator: std.mem.Allocator,
    paragraph: paragraph_types.ParagraphLayout,
    line: paragraph_types.ParagraphLine,
    line_index: usize,
    style_run: anytype,
    font_run_index: usize,
    glyph_start: usize,
    glyph_end: usize,
) !void {
    const line_end = line.glyph_start + line.glyph_len;
    const x = line.x + advanceBefore(
        paragraph.glyphs[line.glyph_start..line_end],
        glyph_start - line.glyph_start,
    );
    const width = advanceRange(paragraph.glyphs[glyph_start..glyph_end]);
    if (width <= 0) return;
    if (font_run_index >= paragraph.runs.len) {
        return error.InvalidParagraphLayout;
    }
    const font_run = paragraph.runs[font_run_index];
    const font = run_types.fontForBackend(font_run);
    const metrics = try font.scaledDecorationMetrics(font_run.font_size);
    const aligned_baseline =
        line.y + line.baseline + vertical_align.fontPhysicalOffset(
            line,
            font_run,
            style_run.style.vertical_align,
            style_run.style.baseline_shift,
        );
    if (style_run.style.decoration.underline) {
        try output.append(allocator, .{
            .kind = .underline,
            .style_index = style_run.style_index,
            .font_run_index = font_run_index,
            .line_index = line_index,
            .rect = .{
                .x = x,
                // OpenType/FreeType decoration positions describe the stroke
                // centerline; the public record is a fill rectangle.
                .y = aligned_baseline -
                    metrics.underline_position -
                    metrics.underline_thickness / 2,
                .width = width,
                .height = metrics.underline_thickness,
            },
            .color = style_run.style.color,
        });
    }
    if (style_run.style.decoration.strikethrough) {
        try output.append(allocator, .{
            .kind = .strikethrough,
            .style_index = style_run.style_index,
            .font_run_index = font_run_index,
            .line_index = line_index,
            .rect = .{
                .x = x,
                .y = aligned_baseline -
                    metrics.strikeout_position -
                    metrics.strikeout_thickness / 2,
                .width = width,
                .height = metrics.strikeout_thickness,
            },
            .color = style_run.style.color,
        });
    }
}

fn fontRunIndex(
    runs: []const run_types.CascadeRun,
    glyph_index: usize,
) ?usize {
    var low: usize = 0;
    var high: usize = runs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const run = runs[mid];
        if (glyph_index < run.glyph_start) {
            high = mid;
        } else if (glyph_index >= run.glyph_start + run.glyph_len) {
            low = mid + 1;
        } else {
            return mid;
        }
    }
    return null;
}

fn advanceBefore(
    glyphs: []const glyph_position.GlyphPosition,
    count: usize,
) f32 {
    return advanceRange(glyphs[0..@min(count, glyphs.len)]);
}

fn advanceRange(glyphs: []const glyph_position.GlyphPosition) f32 {
    var width: f32 = 0;
    for (glyphs) |glyph| width += glyph.x_advance;
    return width;
}

test "decoration kind remains a compact explicit contract" {
    try std.testing.expectEqual(@as(usize, 2), std.enums.values(Kind).len);
}
