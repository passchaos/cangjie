//! Font-outline flattening and conservative small-size pixel alignment.

const std = @import("std");
const ColorAffine = @import("../font.zig").ColorAffine;
const glyph_mod = @import("../glyph.zig");
const curves = @import("curves.zig");
const Line = @import("scanline.zig").Line;
const Point = glyph_mod.Point;

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
    flattenTransformed(lines, outline, .identity, scale, x, baseline_y);
}

pub fn flattenTransformed(
    lines: *std.ArrayList(Line),
    outline: *const glyph_mod.GlyphOutline,
    transform: ColorAffine,
    scale: f32,
    x: f32,
    baseline_y: f32,
) void {
    var start: ?Point = null;
    var current: ?Point = null;
    for (outline.commands.items) |command| {
        switch (command) {
            .move_to => |point| {
                const pixel = fontToPixel(
                    transform.apply(point),
                    scale,
                    x,
                    baseline_y,
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
                );
                const end = fontToPixel(
                    transform.apply(quad.end),
                    scale,
                    x,
                    baseline_y,
                );
                const segments = curves.quadSegmentCount(a, control, end);
                var previous = a;
                for (1..segments + 1) |index| {
                    const t = @as(f32, @floatFromInt(index)) /
                        @as(f32, @floatFromInt(segments));
                    const point = curves.quadPoint(a, control, end, t);
                    lines.appendAssumeCapacity(.{
                        .a = previous,
                        .b = point,
                    });
                    previous = point;
                }
                current = end;
            },
            .cubic_to => |cubic| {
                const a = current orelse continue;
                const c0 = fontToPixel(
                    transform.apply(cubic.c0),
                    scale,
                    x,
                    baseline_y,
                );
                const c1 = fontToPixel(
                    transform.apply(cubic.c1),
                    scale,
                    x,
                    baseline_y,
                );
                const end = fontToPixel(
                    transform.apply(cubic.end),
                    scale,
                    x,
                    baseline_y,
                );
                const segments = curves.cubicSegmentCount(a, c0, c1, end);
                var previous = a;
                for (1..segments + 1) |index| {
                    const t = @as(f32, @floatFromInt(index)) /
                        @as(f32, @floatFromInt(segments));
                    const point = curves.cubicPoint(a, c0, c1, end, t);
                    lines.appendAssumeCapacity(.{
                        .a = previous,
                        .b = point,
                    });
                    previous = point;
                }
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
) Point {
    return .{
        .x = x + point.x * scale,
        .y = baseline_y - point.y * scale,
    };
}

test {
    _ = @import("outline_tests.zig");
}
