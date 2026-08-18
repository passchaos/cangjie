//! Hard-break vertical paragraph columns.
//!
//! This is intentionally separate from horizontal greedy reflow. Reusing the
//! latter by renaming "width" variables would leave tabs, exclusions,
//! justification, truncation, and rollback checkpoints coupled to physical x.
//! The public validator admits only explicit hard breaks and no width-induced
//! wrapping. That bounded surface lets this module establish correct physical
//! RL/LR column progression while the remaining features migrate to explicit
//! flow axes independently.

const axes = @import("axes.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const paragraph_options = @import("options.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
) !void {
    buffer.lines.clearRetainingCapacity();

    for (buffer.glyphs.items) |*glyph| {
        if (opportunities.isMandatory(glyph.codepoint)) {
            // Separators own source/caret topology but never consume column
            // height or request rendering through a line's glyph range.
            glyph.x_advance = 0;
            glyph.y_advance = 0;
            continue;
        }
        glyph.y_advance += geometry.spacingForGlyph(
            glyph.codepoint,
            options,
        );
    }

    var glyph_start: usize = 0;
    var byte_start: usize = 0;
    var index: usize = 0;
    while (index < buffer.glyphs.items.len) : (index += 1) {
        if (!opportunities.isMandatory(
            buffer.glyphs.items[index].codepoint,
        )) continue;
        const break_end = if (buffer.glyphs.items[index].codepoint == '\r' and
            index + 1 < buffer.glyphs.items.len and
            buffer.glyphs.items[index + 1].codepoint == '\n')
            index + 2
        else
            index + 1;
        try appendColumn(
            buffer,
            options,
            default_metrics,
            glyph_start,
            index,
            byte_start,
            buffer.glyphs.items[break_end - 1].sourceByteEnd(),
        );
        glyph_start = break_end;
        byte_start = buffer.glyphs.items[break_end - 1].sourceByteEnd();
        index = break_end - 1;
    }
    try appendColumn(
        buffer,
        options,
        default_metrics,
        glyph_start,
        buffer.glyphs.items.len,
        byte_start,
        text.len,
    );
    placeColumns(buffer.lines.items, options.writing_mode);
}

pub fn contentWidths(
    glyphs: []const GlyphPosition,
    options: paragraph_options.Options,
) @import("../types/paragraph.zig").ContentWidths {
    var widest: f32 = 0;
    var current: f32 = 0;
    for (glyphs) |glyph| {
        if (opportunities.isMandatory(glyph.codepoint)) {
            widest = @max(widest, current);
            current = 0;
            continue;
        }
        current += glyph.y_advance +
            geometry.spacingForGlyph(glyph.codepoint, options);
    }
    widest = @max(widest, current);
    return .{ .min = widest, .max = widest };
}

fn appendColumn(
    buffer: anytype,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
) !void {
    const line_info = geometry.resolvedLineInfo(
        buffer.runs.items,
        buffer.glyphs.items,
        options.inline_objects,
        glyph_start,
        glyph_end,
        default_metrics,
        options.line_height,
        null,
    );
    const metrics = line_info.metrics;
    const block_size = metrics.lineHeight();
    var inline_size: f32 = 0;
    for (buffer.glyphs.items[glyph_start..glyph_end]) |glyph| {
        inline_size += glyph.y_advance;
    }
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = line_info.run_start,
        .run_len = line_info.run_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .x = 0,
        .y = 0,
        .region_x = 0,
        .region_width = block_size,
        .resolved_alignment = .start,
        .width = block_size,
        .height = inline_size,
        // A vertical glyph's HarfBuzz x offset is relative to the column
        // center, not to a horizontal alphabetic baseline.
        .baseline = block_size / 2,
        .ascent = metrics.ascent,
        .descent = metrics.descent,
        .leading = metrics.leading,
    });
}

fn placeColumns(
    lines: anytype,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    if (writing_mode == .vertical_lr) {
        var x: f32 = 0;
        for (lines) |*line| {
            line.x = x;
            line.region_x = x;
            x += line.width;
        }
        return;
    }

    var total_width: f32 = 0;
    for (lines) |line| total_width += line.width;
    var right = total_width;
    for (lines) |*line| {
        right -= line.width;
        line.x = right;
        line.region_x = right;
    }
}
