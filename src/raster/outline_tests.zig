//! Font-outline pixel-alignment tests.

const std = @import("std");
const glyph_mod = @import("../glyph.zig");
const outline_raster = @import("outline.zig");
const Line = @import("scanline.zig").Line;

test "small glyph alignment translates outline to pixel grid" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 4.2 } },
        .{ .a = .{ .x = 7.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    const outline = glyph_mod.GlyphOutline.init(
        std.testing.allocator,
        1,
        .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 },
        500,
        0,
    );
    outline_raster.alignSmallGlyphToPixelGrid(
        &lines,
        &outline,
        12.0 / 1000.0,
        12,
        12,
    );
    try std.testing.expect(@abs(lines[0].a.x - 2.0) < 0.001);
    try std.testing.expect(@abs(lines[0].a.y - 4.5) < 0.001);
    try std.testing.expect(@abs(lines[1].b.y - 10.0) < 0.001);
}

test "small multi-contour glyph alignment preserves outline height" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 4.2 } },
        .{ .a = .{ .x = 7.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    var outline = glyph_mod.GlyphOutline.init(
        std.testing.allocator,
        1,
        .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 },
        500,
        0,
    );
    defer outline.deinit();
    try outline.commands.append(
        std.testing.allocator,
        .{ .move_to = .{ .x = 0, .y = 0 } },
    );
    try outline.commands.append(
        std.testing.allocator,
        .{ .move_to = .{ .x = 1, .y = 1 } },
    );
    outline_raster.alignSmallGlyphToPixelGrid(
        &lines,
        &outline,
        12.0 / 1000.0,
        12,
        12,
    );
    try std.testing.expect(@abs(lines[0].a.x - 2.0) < 0.001);
    try std.testing.expect(@abs(lines[0].a.y - 4.5) < 0.001);
    try std.testing.expect(@abs(lines[1].b.y - 10.0) < 0.001);
    try std.testing.expect(
        @abs((lines[1].b.y - lines[0].a.y) - 5.5) < 0.001,
    );
}

test "large glyph alignment leaves outline unchanged" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    const outline = glyph_mod.GlyphOutline.init(
        std.testing.allocator,
        1,
        .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 },
        500,
        0,
    );
    outline_raster.alignSmallGlyphToPixelGrid(
        &lines,
        &outline,
        24.0 / 1000.0,
        24,
        24,
    );
    try std.testing.expect(@abs(lines[0].a.x - 2.3) < 0.001);
    try std.testing.expect(@abs(lines[0].b.y - 9.7) < 0.001);
}
