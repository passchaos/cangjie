//! Vertical paragraph columns.
//!
//! This is intentionally separate from horizontal greedy reflow. Reusing the
//! latter by renaming "width" variables would leave tabs, exclusions,
//! justification, truncation, and rollback checkpoints coupled to physical x.
//! Width-induced selection is delegated to the focused `vertical_wrap`
//! modules. This owner applies resolved metrics and physical RL/LR progression
//! without importing horizontal regions, tabs, justification, or rollback.

const geometry = @import("../line_break/reflow/geometry.zig");
const inline_object = @import("../inline_object/root.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const line_break_opportunity = @import("../line_break/opportunity.zig");
const paragraph_options = @import("options.zig");
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
        if (glyph.isInlineObject()) {
            const object = inline_object.find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            if (object.kind != .in_flow) {
                return error.UnsupportedVerticalParagraphOptions;
            }
            // Retained reflow may change object geometry while preserving the
            // source anchor. Refresh both physical dimensions from the current
            // request rather than trusting the shaping snapshot.
            glyph.x_advance = object.width;
            glyph.y_advance = object.height;
            continue;
        }
        if (!glyph.isTab()) {
            glyph.y_advance += geometry.spacingForGlyph(
                glyph.codepoint,
                options,
            );
        }
    }
    white_space.prepareVertical(
        buffer.glyphs.items,
        options.white_space_collapse,
        white_space.defaultVerticalSpaceAdvance(buffer.glyphs.items),
    );

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
    placeColumns(
        buffer.lines.items,
        ranges,
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
    const line_info = geometry.resolvedLineInfo(
        buffer.runs.items,
        buffer.glyphs.items,
        // Horizontal object baseline extents do not describe a vertical
        // column's block axis. Object width is folded into `block_size` below.
        &.{},
        glyph_start,
        glyph_end,
        default_metrics,
        options.line_height,
        null,
    );
    const metrics = line_info.metrics;
    var block_size = metrics.lineHeight();
    var inline_size: f32 = 0;
    for (buffer.glyphs.items[glyph_start..glyph_end]) |glyph| {
        inline_size += glyph.y_advance;
        if (glyph.isInlineObject()) {
            const object = inline_object.find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            block_size = @max(block_size, object.width);
        }
    }
    const resolved_alignment = if (vertical_tabs.contains(
        buffer.glyphs.items[glyph_start..glyph_end],
    ))
        @import("../types/paragraph.zig").TextAlign.start
    else
        options.alignment;
    const inline_origin = alignedInlineOrigin(
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

fn alignedInlineOrigin(
    max_inline_size: f32,
    indent: f32,
    inline_size: f32,
    alignment: @import("../types/paragraph.zig").TextAlign,
) f32 {
    if (max_inline_size <= 0 or !@import("std").math.isFinite(max_inline_size)) {
        return indent;
    }
    const available = @max(0, max_inline_size - indent);
    const slack = @max(0, available - inline_size);
    return indent + switch (alignment) {
        .start => 0,
        .center => slack / 2,
        .end => slack,
        .left, .right, .justify => unreachable,
    };
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
