//! Single-column vertical paragraph geometry.
//!
//! This is intentionally separate from horizontal greedy reflow. Reusing the
//! latter by renaming "width" variables would leave tabs, exclusions,
//! justification, truncation, and rollback checkpoints coupled to physical x.
//! The public validator admits only the subset implemented here, so this module
//! can establish correct end-to-end vertical geometry while those features are
//! migrated to explicit flow axes independently.

const axes = @import("axes.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const paragraph_options = @import("options.zig");

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
) !void {
    buffer.lines.clearRetainingCapacity();

    var inline_size: f32 = 0;
    for (buffer.glyphs.items) |*glyph| {
        const spacing = geometry.spacingForGlyph(glyph.codepoint, options);
        glyph.y_advance += spacing;
        inline_size += axes.glyphAdvance(options.writing_mode, glyph.*);
    }

    const line_info = geometry.resolvedLineInfo(
        buffer.runs.items,
        buffer.glyphs.items,
        options.inline_objects,
        0,
        buffer.glyphs.items.len,
        default_metrics,
        options.line_height,
        null,
    );
    const metrics = line_info.metrics;
    const block_size = metrics.lineHeight();
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = 0,
        .glyph_len = buffer.glyphs.items.len,
        .run_start = line_info.run_start,
        .run_len = line_info.run_len,
        .byte_start = 0,
        .byte_len = text.len,
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
