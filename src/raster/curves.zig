const std = @import("std");
const glyph_mod = @import("../glyph.zig");

pub const Point = glyph_mod.Point;

pub const max_quad_segments: usize = 16;
pub const max_cubic_segments: usize = 24;

const flatten_tolerance_px: f32 = 0.25;

pub fn quadPoint(a: Point, b: Point, c: Point, t: f32) Point {
    const mt = 1.0 - t;
    return .{
        .x = mt * mt * a.x + 2.0 * mt * t * b.x + t * t * c.x,
        .y = mt * mt * a.y + 2.0 * mt * t * b.y + t * t * c.y,
    };
}

pub fn cubicPoint(a: Point, b: Point, c: Point, d: Point, t: f32) Point {
    const mt = 1.0 - t;
    return .{
        .x = mt * mt * mt * a.x + 3.0 * mt * mt * t * b.x + 3.0 * mt * t * t * c.x + t * t * t * d.x,
        .y = mt * mt * mt * a.y + 3.0 * mt * mt * t * b.y + 3.0 * mt * t * t * c.y + t * t * t * d.y,
    };
}

/// Emit equally spaced quadratic samples using forward differences.
///
/// Segment counts are chosen before this call. Incremental evaluation avoids
/// rebuilding the Bernstein basis for every interior point, while assigning
/// the authored endpoint exactly prevents accumulated drift at contour joins.
pub fn appendQuadLines(
    lines: *std.ArrayList(@import("scanline.zig").Line),
    a: Point,
    b: Point,
    c: Point,
    segments: usize,
) void {
    std.debug.assert(segments >= 1);
    const h = 1.0 / @as(f32, @floatFromInt(segments));
    const h2 = h * h;
    var point = a;
    var delta = Point{
        .x = (2.0 * (b.x - a.x)) * h + (a.x - 2.0 * b.x + c.x) * h2,
        .y = (2.0 * (b.y - a.y)) * h + (a.y - 2.0 * b.y + c.y) * h2,
    };
    const delta2 = Point{
        .x = 2.0 * (a.x - 2.0 * b.x + c.x) * h2,
        .y = 2.0 * (a.y - 2.0 * b.y + c.y) * h2,
    };
    for (1..segments + 1) |index| {
        const next = if (index == segments) c else Point{
            .x = point.x + delta.x,
            .y = point.y + delta.y,
        };
        lines.appendAssumeCapacity(.{ .a = point, .b = next });
        point = next;
        delta.x += delta2.x;
        delta.y += delta2.y;
    }
}

pub fn appendCubicLines(
    lines: *std.ArrayList(@import("scanline.zig").Line),
    a: Point,
    b: Point,
    c: Point,
    d: Point,
    segments: usize,
) void {
    std.debug.assert(segments >= 1);
    const h = 1.0 / @as(f32, @floatFromInt(segments));
    const h2 = h * h;
    const h3 = h2 * h;
    const ax = d.x - 3.0 * c.x + 3.0 * b.x - a.x;
    const ay = d.y - 3.0 * c.y + 3.0 * b.y - a.y;
    const bx = 3.0 * (c.x - 2.0 * b.x + a.x);
    const by = 3.0 * (c.y - 2.0 * b.y + a.y);
    const cx = 3.0 * (b.x - a.x);
    const cy = 3.0 * (b.y - a.y);
    var point = a;
    var delta = Point{
        .x = ax * h3 + bx * h2 + cx * h,
        .y = ay * h3 + by * h2 + cy * h,
    };
    var delta2 = Point{
        .x = 6.0 * ax * h3 + 2.0 * bx * h2,
        .y = 6.0 * ay * h3 + 2.0 * by * h2,
    };
    const delta3 = Point{
        .x = 6.0 * ax * h3,
        .y = 6.0 * ay * h3,
    };
    for (1..segments + 1) |index| {
        const next = if (index == segments) d else Point{
            .x = point.x + delta.x,
            .y = point.y + delta.y,
        };
        lines.appendAssumeCapacity(.{ .a = point, .b = next });
        point = next;
        delta.x += delta2.x;
        delta.y += delta2.y;
        delta2.x += delta3.x;
        delta2.y += delta3.y;
    }
}

pub fn quadSegmentCount(a: Point, b: Point, c: Point) usize {
    return segmentCountFromFlatness(pointLineDistance(b, a, c), max_quad_segments);
}

pub fn cubicSegmentCount(a: Point, b: Point, c: Point, d: Point) usize {
    const flatness = @max(pointLineDistance(b, a, d), pointLineDistance(c, a, d));
    return segmentCountFromFlatness(flatness, max_cubic_segments);
}

fn segmentCountFromFlatness(flatness: f32, comptime max_segments: usize) usize {
    if (!std.math.isFinite(flatness) or flatness <= flatten_tolerance_px) return 1;
    const raw = @ceil(@sqrt(flatness / flatten_tolerance_px));
    if (raw <= 1) return 1;
    if (raw >= @as(f32, @floatFromInt(max_segments))) return max_segments;
    return @intFromFloat(raw);
}

fn pointLineDistance(point: Point, line_start: Point, line_end: Point) f32 {
    const dx = line_end.x - line_start.x;
    const dy = line_end.y - line_start.y;
    const len_sq = dx * dx + dy * dy;
    if (!std.math.isFinite(len_sq) or len_sq <= 0.000001) {
        const px = point.x - line_start.x;
        const py = point.y - line_start.y;
        return @sqrt(px * px + py * py);
    }
    return @abs((point.x - line_start.x) * dy - (point.y - line_start.y) * dx) / @sqrt(len_sq);
}

test "adaptive curve flattening preserves configured segment bounds" {
    const flat = Point{ .x = 50, .y = 0 };
    try std.testing.expectEqual(@as(usize, 1), quadSegmentCount(.{ .x = 0, .y = 0 }, flat, .{ .x = 100, .y = 0 }));

    const curved = quadSegmentCount(.{ .x = 0, .y = 0 }, .{ .x = 50, .y = 100 }, .{ .x = 100, .y = 0 });
    try std.testing.expect(curved > 1);
    try std.testing.expect(curved <= max_quad_segments);

    const cubic = cubicSegmentCount(
        .{ .x = 0, .y = 0 },
        .{ .x = 0, .y = 100 },
        .{ .x = 100, .y = 100 },
        .{ .x = 100, .y = 0 },
    );
    try std.testing.expect(cubic > 1);
    try std.testing.expect(cubic <= max_cubic_segments);
}

test "forward differences stay close to Bernstein samples and keep endpoints" {
    const Line = @import("scanline.zig").Line;
    const a = Point{ .x = -3.25, .y = 4.5 };
    const b = Point{ .x = 7.0, .y = -9.5 };
    const c = Point{ .x = 12.25, .y = 8.75 };
    const d = Point{ .x = 20.0, .y = -2.0 };

    var quad_storage: [max_quad_segments]Line = undefined;
    var quad_lines = std.ArrayList(Line).initBuffer(&quad_storage);
    appendQuadLines(&quad_lines, a, b, c, max_quad_segments);
    try std.testing.expectEqual(c, quad_lines.items[quad_lines.items.len - 1].b);
    for (quad_lines.items, 1..) |line, index| {
        const t = @as(f32, @floatFromInt(index)) / max_quad_segments;
        const expected = quadPoint(a, b, c, t);
        try std.testing.expect(@abs(line.b.x - expected.x) < 0.0001);
        try std.testing.expect(@abs(line.b.y - expected.y) < 0.0001);
    }

    var cubic_storage: [max_cubic_segments]Line = undefined;
    var cubic_lines = std.ArrayList(Line).initBuffer(&cubic_storage);
    appendCubicLines(&cubic_lines, a, b, c, d, max_cubic_segments);
    try std.testing.expectEqual(d, cubic_lines.items[cubic_lines.items.len - 1].b);
    for (cubic_lines.items, 1..) |line, index| {
        const t = @as(f32, @floatFromInt(index)) / max_cubic_segments;
        const expected = cubicPoint(a, b, c, d, t);
        try std.testing.expect(@abs(line.b.x - expected.x) < 0.0002);
        try std.testing.expect(@abs(line.b.y - expected.y) < 0.0002);
    }
}
