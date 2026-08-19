//! Resolved positive-down inline regions for vertical paragraph columns.

const std = @import("std");

const paragraph_options = @import("options.zig");
const paragraph_types = @import("../types/paragraph.zig");
const vertical_inline_alignment = @import("vertical_inline_alignment.zig");

pub fn indent(
    options: paragraph_options.Options,
    visual_index: usize,
    natural_indent: f32,
) f32 {
    return if (visual_index < options.line_regions.len) 0 else natural_indent;
}

pub fn limit(
    options: paragraph_options.Options,
    visual_index: usize,
    natural_indent: f32,
    wrapping_enabled: bool,
) f32 {
    if (!wrapping_enabled) return std.math.inf(f32);
    if (visual_index < options.line_regions.len) {
        return options.line_regions[visual_index].width;
    }
    if (options.max_width <= 0 or !std.math.isFinite(options.max_width)) {
        return std.math.inf(f32);
    }
    return @max(0, options.max_width - natural_indent);
}

pub fn start(
    options: paragraph_options.Options,
    visual_index: usize,
    natural_indent: f32,
) f32 {
    if (visual_index < options.line_regions.len) {
        return options.line_regions[visual_index].y;
    }
    return natural_indent;
}

pub fn available(
    options: paragraph_options.Options,
    visual_index: usize,
    natural_indent: f32,
) f32 {
    if (visual_index < options.line_regions.len) {
        return options.line_regions[visual_index].width;
    }
    if (options.max_width <= 0 or !std.math.isFinite(options.max_width)) {
        return std.math.inf(f32);
    }
    return @max(0, options.max_width - natural_indent);
}

pub fn origin(
    line: paragraph_types.ParagraphLine,
    options: paragraph_options.Options,
    inline_size: f32,
) f32 {
    if (line.region_inline_size > 0 or
        std.math.isInf(line.region_inline_size))
    {
        return vertical_inline_alignment.originInRegion(
            line.region_inline_start,
            line.region_inline_size,
            inline_size,
            line.resolved_alignment orelse options.alignment,
        );
    }
    return vertical_inline_alignment.origin(
        options.max_width,
        line.indent,
        inline_size,
        line.resolved_alignment orelse options.alignment,
    );
}
