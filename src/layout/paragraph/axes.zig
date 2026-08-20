//! Physical/flow-axis conversion shared by paragraph geometry consumers.
//!
//! Paragraph records keep ordinary physical `x`, `y`, `width`, and `height`
//! fields. This module is the only place that interprets which physical axis
//! carries inline progression for a writing mode. Keeping that decision out of
//! hit testing, text geometry, and the renderer bridge prevents each consumer
//! from growing a subtly different vertical-layout convention.

const glyph_position = @import("../glyph_position.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");

pub const WritingMode = pipeline_types.WritingMode;

/// Axis-neutral physical rectangle retained by public paragraph records.
///
/// The fields are always physical target-space coordinates. Flow-axis helpers
/// below select from them; the rectangle itself never changes interpretation.
pub const PhysicalRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn rect(
    x: f32,
    y: f32,
    width: f32,
    height: f32,
) PhysicalRect {
    return .{ .x = x, .y = y, .width = width, .height = height };
}

pub fn inlineCoordinate(
    writing_mode: WritingMode,
    x: f32,
    y: f32,
) f32 {
    return if (writing_mode.isVertical()) y else x;
}

pub fn blockCoordinate(
    writing_mode: WritingMode,
    x: f32,
    y: f32,
) f32 {
    return if (writing_mode.isVertical()) x else y;
}

pub fn inlineStart(
    writing_mode: WritingMode,
    bounds: PhysicalRect,
) f32 {
    return inlineCoordinate(writing_mode, bounds.x, bounds.y);
}

pub fn inlineSize(
    writing_mode: WritingMode,
    bounds: PhysicalRect,
) f32 {
    return if (writing_mode.isVertical()) bounds.height else bounds.width;
}

pub fn blockStart(
    writing_mode: WritingMode,
    bounds: PhysicalRect,
) f32 {
    return blockCoordinate(writing_mode, bounds.x, bounds.y);
}

pub fn blockSize(
    writing_mode: WritingMode,
    bounds: PhysicalRect,
) f32 {
    return if (writing_mode.isVertical()) bounds.width else bounds.height;
}

pub fn glyphAdvance(
    writing_mode: WritingMode,
    glyph: glyph_position.GlyphPosition,
) f32 {
    return if (writing_mode.isVertical())
        glyph.y_advance
    else
        glyph.x_advance;
}

/// Construct a physical caret rectangle spanning the line's block axis.
pub fn caretRect(
    writing_mode: WritingMode,
    block_start: f32,
    block_size: f32,
    inline_position: f32,
) PhysicalRect {
    return if (writing_mode.isVertical())
        .{
            .x = block_start,
            .y = inline_position,
            .width = block_size,
            .height = 0,
        }
    else
        .{
            .x = inline_position,
            .y = block_start,
            .width = 0,
            .height = block_size,
        };
}

pub fn selectionRect(
    writing_mode: WritingMode,
    line_bounds: PhysicalRect,
    inline_start: f32,
    inline_end: f32,
) PhysicalRect {
    const start = @min(inline_start, inline_end);
    const size = @max(0, @max(inline_start, inline_end) - start);
    return if (writing_mode.isVertical())
        .{
            .x = line_bounds.x,
            .y = start,
            .width = line_bounds.width,
            .height = size,
        }
    else
        .{
            .x = start,
            .y = line_bounds.y,
            .width = size,
            .height = line_bounds.height,
        };
}

pub fn caretInlinePosition(
    writing_mode: WritingMode,
    bounds: PhysicalRect,
) f32 {
    return inlineCoordinate(writing_mode, bounds.x, bounds.y);
}

test "axis conversion keeps physical rectangle contracts" {
    const std = @import("std");
    const bounds = PhysicalRect{
        .x = 3,
        .y = 5,
        .width = 7,
        .height = 11,
    };
    try std.testing.expectEqual(
        @as(f32, 3),
        inlineStart(.horizontal_tb, bounds),
    );
    try std.testing.expectEqual(
        @as(f32, 11),
        inlineSize(.vertical_rl, bounds),
    );
    try std.testing.expectEqual(
        PhysicalRect{
            .x = 3,
            .y = 13,
            .width = 7,
            .height = 0,
        },
        caretRect(.vertical_rl, 3, 7, 13),
    );
}
