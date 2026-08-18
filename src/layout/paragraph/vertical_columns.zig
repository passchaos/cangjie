//! Vertical paragraph columns.
//!
//! This is intentionally separate from horizontal greedy reflow. Reusing the
//! latter by renaming "width" variables would leave tabs, exclusions,
//! justification, truncation, and rollback checkpoints coupled to physical x.
//! Width-induced selection is delegated to the focused `vertical_wrap`
//! modules. This owner applies resolved metrics and physical RL/LR progression
//! without importing horizontal regions, tabs, justification, or rollback.

const axes = @import("axes.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const line_break_opportunity = @import("../line_break/opportunity.zig");
const paragraph_options = @import("options.zig");
const vertical_wrap = @import("vertical_wrap.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const unicode = @import("../../unicode.zig");

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
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

    var owned_graphemes: ?[]unicode.GraphemeCluster = null;
    defer if (owned_graphemes) |items| buffer.allocator.free(items);
    const graphemes = analyzed_graphemes orelse graphemes: {
        owned_graphemes = try unicode.itemizeGraphemeClusters(
            buffer.allocator,
            text,
        );
        break :graphemes owned_graphemes.?;
    };
    var owned_breaks: ?[]line_break_opportunity.Opportunity = null;
    defer if (owned_breaks) |items| buffer.allocator.free(items);
    const breaks = analyzed_line_breaks orelse breaks: {
        const unicode_breaks = try unicode.itemizeLineBreaks(
            buffer.allocator,
            text,
        );
        defer buffer.allocator.free(unicode_breaks);
        owned_breaks = try buffer.allocator.alloc(
            line_break_opportunity.Opportunity,
            unicode_breaks.len,
        );
        for (unicode_breaks, owned_breaks.?) |item, *output| {
            output.* = line_break_opportunity.fromUnicode(item);
        }
        break :breaks owned_breaks.?;
    };
    const ranges = try vertical_wrap.build(
        buffer.allocator,
        text,
        buffer.glyphs.items,
        graphemes,
        breaks,
        options,
    );
    defer buffer.allocator.free(ranges);
    for (ranges) |range| {
        try appendColumn(
            buffer,
            options,
            default_metrics,
            range.glyph_start,
            range.glyph_end,
            range.byte_start,
            range.byte_end,
        );
    }
    placeColumns(buffer.lines.items, options.writing_mode);
}

pub fn contentWidths(
    allocator: @import("std").mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
) !@import("../types/paragraph.zig").ContentWidths {
    return vertical_wrap.intrinsicWidths(
        allocator,
        text,
        glyphs,
        graphemes,
        breaks,
        options,
    );
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
