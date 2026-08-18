//! Vertical paragraph columns.
//!
//! This is intentionally separate from horizontal greedy reflow. Reusing the
//! latter by renaming "width" variables would leave tabs, exclusions,
//! justification, truncation, and rollback checkpoints coupled to physical x.
//! Width-induced selection is delegated to the focused `vertical_wrap`
//! modules. This owner applies resolved metrics and physical RL/LR progression
//! without importing horizontal regions, tabs, justification, or rollback.

const geometry = @import("../line_break/reflow/geometry.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const line_break_opportunity = @import("../line_break/opportunity.zig");
const truncation = @import("../line_break/reflow/truncation.zig");
const paragraph_options = @import("options.zig");
const vertical_advances = @import("vertical_advances.zig");
const vertical_block_metrics = @import("vertical_block_metrics.zig");
const vertical_ellipsis = @import("vertical_ellipsis.zig");
const vertical_inline_alignment = @import("vertical_inline_alignment.zig");
const vertical_wrap = @import("vertical_wrap.zig");
const vertical_tabs = @import("vertical_wrap/tabs.zig");
const white_space = @import("white_space.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const unicode = @import("../../unicode.zig");

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    recipe: anytype,
) !void {
    buffer.lines.clearRetainingCapacity();

    // Retained reflow may change spacing/object geometry while preserving the
    // source anchors. Rebuild every mutable vertical advance from the restored
    // shaping snapshot before white-space and wrap policy consume it.
    try vertical_advances.apply(buffer.glyphs.items, options);
    white_space.prepareVertical(
        buffer.glyphs.items,
        options.white_space_collapse,
        white_space.defaultVerticalSpaceAdvance(buffer.glyphs.items),
    );
    try vertical_advances.validate(buffer.glyphs.items);

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
    if (options.white_space_collapse == .collapse) {
        var previous_end: usize = 0;
        for (ranges) |range| {
            white_space.zeroVerticalCollapsedRange(
                buffer.glyphs.items,
                previous_end,
                range.glyph_start,
            );
            previous_end = range.glyph_end;
        }
        white_space.zeroVerticalCollapsedRange(
            buffer.glyphs.items,
            previous_end,
            buffer.glyphs.items.len,
        );
    }
    for (ranges) |range| {
        if (options.white_space_collapse == .collapse) {
            white_space.trimVerticalLineStart(
                buffer.glyphs.items,
                range.glyph_start,
                range.glyph_end,
            );
            white_space.trimVerticalLineEnd(
                buffer.glyphs.items,
                range.glyph_start,
                range.glyph_end,
            );
        }
        const fallback_advance =
            white_space.defaultVerticalSpaceAdvance(buffer.glyphs.items);
        _ = vertical_tabs.recomputeRange(
            buffer.glyphs.items[range.glyph_start..range.glyph_end],
            options.tab_stops,
            @as(f32, @floatFromInt(@max(1, options.tab_width))) *
                fallback_advance,
            fallback_advance,
        );
        try appendColumn(
            buffer,
            options,
            default_metrics,
            range.glyph_start,
            range.glyph_end,
            range.byte_start,
            range.byte_end,
            range.inline_indent,
        );
    }
    const visible_count = @min(
        options.max_lines orelse ranges.len,
        ranges.len,
    );
    const content_omitted = visible_count < ranges.len;
    if (visible_count < ranges.len) {
        truncation.keepPrefix(buffer, visible_count);
    }
    if (options.ellipsis and content_omitted and visible_count != 0) {
        _ = try vertical_ellipsis.materialize(
            buffer,
            options,
            default_metrics,
            recipe,
        );
    }
    placeColumns(
        buffer.lines.items,
        ranges[0..visible_count],
        options.writing_mode,
        options.paragraph_spacing,
    );
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

/// Repair already-placed columns after styled ellipsis changes only the final
/// source-order column's block width.
///
/// LR progression anchors earlier columns at the left, so no coordinates
/// change. RL progression anchors the terminal source column at x=0; every
/// earlier column shifts by the terminal width delta.
pub fn refreshAfterTerminalWidthChange(
    lines: []@import("../types/paragraph.zig").ParagraphLine,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
    previous_terminal_width: f32,
) void {
    if (writing_mode != .vertical_rl or lines.len < 2) return;
    const delta = lines[lines.len - 1].width - previous_terminal_width;
    if (delta == 0) return;
    for (lines[0 .. lines.len - 1]) |*line| {
        line.x += delta;
        line.region_x += delta;
    }
}

/// Whether a truncated visible prefix omits at least one source-order column.
///
/// A trailing mandatory separator owns the final bytes of its preceding
/// column, while vertical wrapping also creates an empty terminal column at
/// `text.len`. Byte-end comparison alone therefore misses exactly that
/// omitted empty column.
pub fn visiblePrefixOmitsSource(
    text: []const u8,
    lines: []const @import("../types/paragraph.zig").ParagraphLine,
) bool {
    if (lines.len == 0) return false;
    const last = lines[lines.len - 1];
    const byte_end = last.byteEnd();
    if (byte_end < text.len) return true;
    if (byte_end != text.len or last.byte_len == 0) return false;

    var iterator = @import("std").unicode.Utf8Iterator{
        .bytes = text[last.byte_start..byte_end],
        .i = 0,
    };
    var terminal: ?u21 = null;
    while (iterator.nextCodepoint()) |codepoint| terminal = codepoint;
    return if (terminal) |codepoint|
        opportunities.isMandatory(codepoint)
    else
        false;
}

fn appendColumn(
    buffer: anytype,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
    inline_indent: f32,
) !void {
    const block_metrics = try vertical_block_metrics.resolve(
        buffer.runs.items,
        buffer.glyphs.items,
        options,
        default_metrics,
        glyph_start,
        glyph_end,
    );
    const line_info = block_metrics.line_info;
    const metrics = line_info.metrics;
    const block_size = block_metrics.block_size;
    var inline_size: f32 = 0;
    for (buffer.glyphs.items[glyph_start..glyph_end]) |glyph| {
        inline_size += glyph.y_advance;
    }
    const resolved_alignment = if (vertical_tabs.contains(
        buffer.glyphs.items[glyph_start..glyph_end],
    ))
        @import("../types/paragraph.zig").TextAlign.start
    else
        options.alignment;
    const inline_origin = vertical_inline_alignment.origin(
        options.max_width,
        inline_indent,
        inline_size,
        resolved_alignment,
    );
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = line_info.run_start,
        .run_len = line_info.run_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .x = 0,
        .y = inline_origin,
        .indent = inline_indent,
        .region_x = 0,
        .region_width = block_size,
        .resolved_alignment = resolved_alignment,
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
    ranges: []const vertical_wrap.Range,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
    paragraph_spacing: f32,
) void {
    if (writing_mode == .vertical_lr) {
        var x: f32 = 0;
        for (lines, ranges, 0..) |*line, range, index| {
            if (index != 0 and range.starts_segment) {
                x += paragraph_spacing;
            }
            line.x = x;
            line.region_x = x;
            x += line.width;
        }
        return;
    }

    var total_width: f32 = 0;
    for (lines, ranges, 0..) |line, range, index| {
        if (index != 0 and range.starts_segment) {
            total_width += paragraph_spacing;
        }
        total_width += line.width;
    }
    var right = total_width;
    for (lines, ranges, 0..) |*line, range, index| {
        if (index != 0 and range.starts_segment) {
            right -= paragraph_spacing;
        }
        right -= line.width;
        line.x = right;
        line.region_x = right;
    }
}
