//! Paragraph-space line-region resolution for greedy reflow.
//!
//! A line owns one contiguous horizontal fragment. Rectangular exclusions can
//! move the line downward or narrow that fragment, while indentation remains
//! a property of the paragraph segment rather than of the chosen fragment.

const std = @import("std");

const exclusions = @import("../../paragraph/exclusions.zig");
const paragraph_options = @import("../../paragraph/options.zig");
const ParagraphLine = @import("../../types/paragraph.zig").ParagraphLine;

pub const LineRegion = struct {
    x: f32,
    width: f32,
    indent: f32,
};

pub fn lineIndent(
    line_index: usize,
    options: paragraph_options.Options,
) f32 {
    if (line_index == 0) return @max(0, options.first_line_indent);
    return 0;
}

pub fn widthLimit(
    line_index: usize,
    max_width: f32,
    options: paragraph_options.Options,
) f32 {
    return widthLimitForIndent(
        max_width,
        lineIndent(line_index, options),
    );
}

pub fn widthLimitForIndent(max_width: f32, indent: f32) f32 {
    if (!std.math.isFinite(max_width)) return max_width;
    return @max(0, max_width - indent);
}

/// Resolve and commit a line's vertical position.
///
/// A completely blocked band advances `y` to exclusion bottoms until a
/// fragment is available. No empty source line is created for those skipped
/// bands.
pub fn resolve(
    allocator: std.mem.Allocator,
    options: paragraph_options.Options,
    paragraph_line_index: usize,
    visual_line_index: usize,
    y: *f32,
    line_height: f32,
    max_width: f32,
) !LineRegion {
    if (explicitSource(options, visual_line_index)) |source| {
        y.* = source.y;
        return fromExplicit(source);
    }
    if (options.wrap_mode == .no_wrap or options.exclusions.len == 0) {
        return default(paragraph_line_index, max_width, options);
    }
    return resolveAtY(
        allocator,
        options,
        paragraph_line_index,
        y,
        line_height,
        max_width,
    );
}

/// Resolve a prospective line without committing a downward move.
///
/// Greedy selection uses this to measure a growing source prefix. Once a break
/// is chosen, `resolve` repeats the same deterministic operation with the
/// selected prefix's exact height and commits the resulting `y`.
pub fn preview(
    allocator: std.mem.Allocator,
    options: paragraph_options.Options,
    paragraph_line_index: usize,
    visual_line_index: usize,
    y: f32,
    line_height: f32,
    max_width: f32,
) !LineRegion {
    if (explicitSource(options, visual_line_index)) |source| {
        return fromExplicit(source);
    }
    if (options.wrap_mode == .no_wrap or options.exclusions.len == 0) {
        return default(paragraph_line_index, max_width, options);
    }
    var preview_y = y;
    return resolveAtY(
        allocator,
        options,
        paragraph_line_index,
        &preview_y,
        line_height,
        max_width,
    );
}

fn explicitSource(
    options: paragraph_options.Options,
    visual_line_index: usize,
) ?paragraph_options.LineRegion {
    if (visual_line_index >= options.line_regions.len) return null;
    return options.line_regions[visual_line_index];
}

fn fromExplicit(region: paragraph_options.LineRegion) LineRegion {
    return .{
        .x = region.x,
        .width = region.width,
        .indent = 0,
    };
}

/// Recover the final measure persisted on a line.
///
/// Zero remains the compatibility sentinel for manually constructed legacy
/// `ParagraphLine` values. Reflow-generated lines persist a positive or
/// infinite measure whenever their container has one.
pub fn stored(line: ParagraphLine, max_width: f32) LineRegion {
    if (line.region_width > 0 or std.math.isInf(line.region_width)) {
        return .{
            .x = line.region_x,
            .width = line.region_width,
            .indent = line.indent,
        };
    }
    return .{
        .x = line.indent,
        .width = widthLimitForIndent(max_width, line.indent),
        .indent = line.indent,
    };
}

fn default(
    line_index: usize,
    max_width: f32,
    options: paragraph_options.Options,
) LineRegion {
    const indent = lineIndent(line_index, options);
    return .{
        .x = indent,
        .width = widthLimitForIndent(max_width, indent),
        .indent = indent,
    };
}

fn resolveAtY(
    allocator: std.mem.Allocator,
    options: paragraph_options.Options,
    line_index: usize,
    y: *f32,
    line_height: f32,
    max_width: f32,
) !LineRegion {
    var attempts: usize = 0;
    while (true) : (attempts += 1) {
        // Each blocked result advances to the bottom of at least one currently
        // intersecting rectangle, so more transitions than rectangles signals
        // invalid or non-progressing geometry.
        if (attempts > options.exclusions.len) {
            return error.InvalidParagraphOptions;
        }
        switch (try candidate(
            allocator,
            options,
            line_index,
            y.*,
            line_height,
            max_width,
        )) {
            .available => |region| return .{
                .x = region.x,
                .width = region.width,
                .indent = lineIndent(line_index, options),
            },
            .blocked_until => |next_y| {
                if (!std.math.isFinite(next_y) or next_y <= y.*) {
                    return error.InvalidParagraphOptions;
                }
                y.* = next_y;
            },
        }
    }
}

fn candidate(
    allocator: std.mem.Allocator,
    options: paragraph_options.Options,
    line_index: usize,
    line_top: f32,
    line_height: f32,
    max_width: f32,
) !exclusions.Resolution {
    const indent = lineIndent(line_index, options);
    return exclusions.resolve(
        allocator,
        options.exclusions,
        indent,
        widthLimitForIndent(max_width, indent),
        line_top,
        line_height,
        options.direction == .rtl,
    );
}
