//! Font-outline flattening and conservative small-size pixel alignment.

const std = @import("std");
const ColorAffine = @import("../font.zig").ColorAffine;
const glyph_mod = @import("../glyph.zig");
const curves = @import("curves.zig");
const Line = @import("scanline.zig").Line;
const Point = glyph_mod.Point;

pub const Orientation = enum {
    upright,
    clockwise,
};

pub fn alignSmallGlyphToPixelGrid(
    lines: []Line,
    outline: *const glyph_mod.GlyphOutline,
    scale: f32,
    font_size: f32,
    hint_size: f32,
) void {
    if (hint_size > 20.0 or lines.len == 0) return;
    var min_x = std.math.inf(f32);
    var min_y = std.math.inf(f32);
    var max_x = -std.math.inf(f32);
    var max_y = -std.math.inf(f32);
    for (lines) |line| {
        min_x = @min(min_x, @min(line.a.x, line.b.x));
        min_y = @min(min_y, @min(line.a.y, line.b.y));
        max_x = @max(max_x, @max(line.a.x, line.b.x));
        max_y = @max(max_y, @max(line.a.y, line.b.y));
    }
    if (!std.math.isFinite(min_x) or
        !std.math.isFinite(min_y) or
        !std.math.isFinite(max_x) or
        !std.math.isFinite(max_y))
    {
        return;
    }
    const dx = @round(min_x) - min_x;
    const dy = @round(max_y) - max_y;

    // The policy currently translates the complete outline without changing
    // its dimensions. Keep the extra inputs explicit because any future
    // per-contour or scale-sensitive policy must remain centralized here.
    _ = outline;
    _ = scale;
    _ = font_size;
    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) return;
    for (lines) |*line| {
        line.a.x += dx;
        line.b.x += dx;
        line.a.y += dy;
        line.b.y += dy;
    }
}

pub fn flatten(
    lines: *std.ArrayList(Line),
    outline: *const glyph_mod.GlyphOutline,
    scale: f32,
    x: f32,
    baseline_y: f32,
) void {
    flattenOriented(lines, outline, scale, x, baseline_y, .upright);
}

pub fn flattenOriented(
    lines: *std.ArrayList(Line),
    outline: *const glyph_mod.GlyphOutline,
    scale: f32,
    x: f32,
    baseline_y: f32,
    orientation: Orientation,
) void {
    flattenCommandsTransformed(
        lines,
        outline.commands.items,
        .identity,
        scale,
        x,
        baseline_y,
        orientation,
    );
}

/// Flatten commands whose coordinates are already pixels.
///
/// Only caller placement is applied; no units-per-em scale participates.
pub fn flattenPixelCommands(
    lines: *std.ArrayList(Line),
    commands: []const glyph_mod.PathCommand,
    x: f32,
    baseline_y: f32,
) void {
    flattenPixelCommandsOriented(
        lines,
        commands,
        x,
        baseline_y,
        .upright,
    );
}

pub fn flattenPixelCommandsOriented(
    lines: *std.ArrayList(Line),
    commands: []const glyph_mod.PathCommand,
    x: f32,
    baseline_y: f32,
    orientation: Orientation,
) void {
    flattenCommandsTransformed(
        lines,
        commands,
        .identity,
        1,
        x,
        baseline_y,
        orientation,
    );
}

pub fn flattenTransformed(
    lines: *std.ArrayList(Line),
    outline: *const glyph_mod.GlyphOutline,
    transform: ColorAffine,
    scale: f32,
    x: f32,
    baseline_y: f32,
) void {
    flattenCommandsTransformed(
        lines,
        outline.commands.items,
        transform,
        scale,
        x,
        baseline_y,
        .upright,
    );
}

fn flattenCommandsTransformed(
    lines: *std.ArrayList(Line),
    commands: []const glyph_mod.PathCommand,
    transform: ColorAffine,
    scale: f32,
    x: f32,
    baseline_y: f32,
    orientation: Orientation,
) void {
    var start: ?Point = null;
    var current: ?Point = null;
    for (commands) |command| {
        switch (command) {
            .move_to => |point| {
                const pixel = fontToPixel(
                    transform.apply(point),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                start = pixel;
                current = pixel;
            },
            .line_to => |point| {
                const a = current orelse continue;
                const b = fontToPixel(
                    transform.apply(point),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                lines.appendAssumeCapacity(.{ .a = a, .b = b });
                current = b;
            },
            .quad_to => |quad| {
                const a = current orelse continue;
                const control = fontToPixel(
                    transform.apply(quad.control),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                const end = fontToPixel(
                    transform.apply(quad.end),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                const segments = curves.quadSegmentCount(a, control, end);
                curves.appendQuadLines(lines, a, control, end, segments);
                current = end;
            },
            .cubic_to => |cubic| {
                const a = current orelse continue;
                const c0 = fontToPixel(
                    transform.apply(cubic.c0),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                const c1 = fontToPixel(
                    transform.apply(cubic.c1),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                const end = fontToPixel(
                    transform.apply(cubic.end),
                    scale,
                    x,
                    baseline_y,
                    orientation,
                );
                const segments = curves.cubicSegmentCount(a, c0, c1, end);
                curves.appendCubicLines(lines, a, c0, c1, end, segments);
                current = end;
            },
            .close => {
                if (current) |a| {
                    if (start) |b| {
                        lines.appendAssumeCapacity(.{ .a = a, .b = b });
                    }
                }
                current = start;
            },
        }
    }
}

/// Capacity that guarantees all adaptive curve segments fit without growth.
pub fn lineCapacity(commands: []const glyph_mod.PathCommand) usize {
    var result: usize = 0;
    for (commands) |command| {
        result += switch (command) {
            .move_to => 0,
            .line_to => 1,
            .quad_to => curves.max_quad_segments,
            .cubic_to => curves.max_cubic_segments,
            .close => 1,
        };
    }
    return result;
}

fn fontToPixel(
    point: Point,
    scale: f32,
    x: f32,
    baseline_y: f32,
    orientation: Orientation,
) Point {
    const local = Point{
        .x = point.x * scale,
        .y = 0 - point.y * scale,
    };
    return switch (orientation) {
        .upright => .{
            .x = x + local.x,
            .y = baseline_y + local.y,
        },
        // Positive 90 degrees is clockwise in the target's y-down coordinate
        // system. Rotate around the shaped glyph origin, never around its
        // bounds, so upright and sideways glyphs share identical pen geometry.
        .clockwise => .{
            .x = x - local.y,
            .y = baseline_y + local.x,
        },
    };
}

test {
    _ = @import("outline_tests.zig");
}
