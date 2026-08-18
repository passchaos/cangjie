//! HarfBuzz oracle and compositing edge-invariant tests.

const std = @import("std");
const composite = @import("composite.zig");
const CompositeMode = @import("../font.zig").ColorPaint.CompositeMode;
const Rgba = @import("targets.zig").Rgba;

test "COLR composite modes match HarfBuzz premultiplied raster oracle" {
    // Expected ARGB words come from HarfBuzz's current hb-raster-image.cc
    // `composite_pixel` for these same premultiplied source/backdrop pixels.
    const source = Rgba{ .r = 100, .g = 70, .b = 40, .a = 170 };
    const backdrop = Rgba{ .r = 30, .g = 60, .b = 90, .a = 140 };
    const expected = [_]u32{
        0x00000000, 0xaa644628, 0x8c1e3c5a, 0xd86e5a46,
        0xd84b5b6c, 0x5d362615, 0x5d14283c, 0x4c2d1f12,
        0x2e0a141e, 0x8b403a33, 0xa941474e, 0x7a373330,
        0xff828282, 0xd9767274, 0xd94f555a, 0xd94b5a46,
        0xd96e5c6c, 0xd968787f, 0xd9373430, 0xd958554c,
        0xd94f5861, 0xd95a3556, 0xd96a6166, 0xd943443e,
        0xd96c543d, 0xd94e5b68, 0xd9695541, 0xd9506171,
    };
    for (expected, 0..) |expected_pixel, raw_mode| {
        const mode: CompositeMode = @enumFromInt(raw_mode);
        const actual = composite.compositePixel(source, backdrop, mode);
        const actual_packed = (@as(u32, actual.a) << 24) |
            (@as(u32, actual.r) << 16) |
            (@as(u32, actual.g) << 8) |
            actual.b;
        try std.testing.expectEqual(expected_pixel, actual_packed);
    }
}

test "COLR composite operator invariants cover transparent and opaque edges" {
    const transparent = Rgba{ .r = 0, .g = 0, .b = 0, .a = 0 };
    const red = Rgba{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = Rgba{ .r = 0, .g = 0, .b = 255, .a = 255 };

    try std.testing.expectEqual(red, composite.compositePixel(red, transparent, .src_over));
    try std.testing.expectEqual(blue, composite.compositePixel(transparent, blue, .src_over));
    try std.testing.expectEqual(red, composite.compositePixel(red, blue, .src));
    try std.testing.expectEqual(blue, composite.compositePixel(red, blue, .dest));
    try std.testing.expectEqual(transparent, composite.compositePixel(red, blue, .xor));
    try std.testing.expectEqual(Rgba{ .r = 255, .g = 0, .b = 255, .a = 255 }, composite.compositePixel(red, blue, .plus));

    // W3C's degenerate dodge/burn branches are backdrop-dominant. The order
    // matters at exactly (source=1, backdrop=0) and (source=0, backdrop=1).
    try std.testing.expectEqual(Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 }, composite.compositePixel(red, Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 }, .color_dodge));
    try std.testing.expectEqual(Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 }, composite.compositePixel(Rgba{ .r = 0, .g = 0, .b = 0, .a = 255 }, Rgba{ .r = 255, .g = 255, .b = 255, .a = 255 }, .color_burn));
}

test "clockwise color-layer rotation is an exact pixel transpose" {
    const source = [_]Rgba{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .{ .r = 0, .g = 255, .b = 0, .a = 255 },
        .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        .{ .r = 255, .g = 255, .b = 0, .a = 255 },
        .{ .r = 255, .g = 0, .b = 255, .a = 255 },
        .{ .r = 0, .g = 255, .b = 255, .a = 255 },
    };
    var target = [_]Rgba{.{ .r = 0, .g = 0, .b = 0, .a = 0 }} ** 6;
    composite.blendClockwise(
        &target,
        3,
        2,
        &source,
        2,
        3,
    );
    try std.testing.expectEqualSlices(
        Rgba,
        &.{
            source[4],
            source[2],
            source[0],
            source[5],
            source[3],
            source[1],
        },
        &target,
    );
}
