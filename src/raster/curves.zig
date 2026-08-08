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
