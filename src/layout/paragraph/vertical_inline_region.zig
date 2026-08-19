//! Resolved positive-down inline regions for vertical paragraph columns.

const std = @import("std");

const exclusions = @import("exclusions.zig");
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

pub const Resolved = struct {
    block_start: f32,
    inline_start: f32,
    inline_size: f32,
    indent: f32,
};

/// Resolve the next vertical column band against physical exclusions.
///
/// Explicit caller regions bypass exclusions and preserve their absolute x/y
/// geometry. Natural columns advance in the writing mode's physical block
/// direction across fully blocked bands; a nonempty band chooses its widest
/// remaining positive-down y fragment.
pub fn resolve(
    allocator: std.mem.Allocator,
    options: paragraph_options.Options,
    visual_index: usize,
    natural_block_start: f32,
    block_size: f32,
    natural_indent: f32,
    wrapping_enabled: bool,
) !Resolved {
    if (visual_index < options.line_regions.len) {
        const region = options.line_regions[visual_index];
        return .{
            .block_start = region.x,
            .inline_start = region.y,
            .inline_size = if (wrapping_enabled)
                region.width
            else
                std.math.inf(f32),
            .indent = 0,
        };
    }
    const normalized_indent = @max(0, natural_indent);
    const container_y = normalized_indent;
    const container_size = if (wrapping_enabled and
        options.max_width > 0 and
        std.math.isFinite(options.max_width))
        @max(0, options.max_width - normalized_indent)
    else if (wrapping_enabled and options.exclusions.len != 0)
        // Match horizontal unbounded exclusion behavior: a finite rectangle can
        // shift the origin but the remaining inline fragment stays unbounded.
        std.math.inf(f32)
    else
        std.math.inf(f32);
    if (!wrapping_enabled or options.exclusions.len == 0) {
        return .{
            .block_start = natural_block_start,
            .inline_start = container_y,
            .inline_size = container_size,
            .indent = normalized_indent,
        };
    }

    var block_start = natural_block_start;
    var attempts: usize = 0;
    while (true) : (attempts += 1) {
        if (attempts > options.exclusions.len) {
            return error.InvalidParagraphOptions;
        }
        switch (try exclusions.resolveVertical(
            allocator,
            options.exclusions,
            container_y,
            container_size,
            block_start,
            block_size,
            if (options.writing_mode == .vertical_lr)
                .left_to_right
            else
                .right_to_left,
        )) {
            .available => |region| return .{
                .block_start = block_start,
                .inline_start = region.x,
                .inline_size = region.width,
                .indent = normalized_indent,
            },
            .blocked_until => |next_x| {
                const advances = if (options.writing_mode == .vertical_lr)
                    next_x > block_start
                else
                    next_x < block_start;
                if (!std.math.isFinite(next_x) or !advances) {
                    return error.InvalidParagraphOptions;
                }
                block_start = next_x;
            },
        }
    }
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
