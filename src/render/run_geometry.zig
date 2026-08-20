//! Coordinate conversion shared by every positioned-glyph renderer.
//!
//! Shaping geometry follows the HarfBuzz convention: X grows right and Y
//! grows up. CPU render targets grow down, so a positive shaping `y_offset`
//! subtracts from the target-space baseline. Advances describe the next pen
//! in target user space; Cangjie's vertical shaping emits positive
//! `y_advance`, which therefore moves subsequent glyphs down the column.

const GlyphPosition =
    @import("../layout/glyph_position.zig").GlyphPosition;
pub const RasterOrientation =
    @import("../raster/outline.zig").Orientation;

pub const Origin = struct {
    x: f32,
    baseline_y: f32,
};

pub const Pen = struct {
    x: f32,
    baseline_y: f32,

    pub fn init(x: f32, baseline_y: f32) Pen {
        return .{ .x = x, .baseline_y = baseline_y };
    }

    pub fn glyphOrigin(self: Pen, glyph: GlyphPosition) Origin {
        return .{
            .x = self.x + glyph.x_offset,
            .baseline_y = self.baseline_y - glyph.y_offset,
        };
    }

    /// Advance after every source atom, including non-rendering inline
    /// objects. Their geometry still positions the next visible glyph.
    pub fn advance(self: *Pen, glyph: GlyphPosition) void {
        self.x += glyph.x_advance;
        self.baseline_y += glyph.y_advance;
    }
};

/// Apply a cascade run's already-accumulated two-dimensional pen.
///
/// Per-glyph shaping offsets are not involved here: unlike `y_offset` on a
/// glyph, this run offset is an absolute user-space pen delta and grows down
/// with Cangjie's positive vertical advances.
pub fn offsetOrigin(
    x: f32,
    baseline_y: f32,
    x_offset: f32,
    y_offset: f32,
) Origin {
    return .{
        .x = x + x_offset,
        .baseline_y = baseline_y + y_offset,
    };
}

pub fn rasterOrientation(glyph: GlyphPosition) RasterOrientation {
    return if (glyph.isSideways()) .clockwise else .upright;
}

test "run pen converts shaping offsets and advances both axes" {
    const std = @import("std");

    var pen = Pen.init(10, 40);
    const first = GlyphPosition{
        .glyph_id = 1,
        .codepoint = 'A',
        .cluster = 0,
        .x_advance = 11,
        .y_advance = 13,
        .x_offset = 2,
        .y_offset = 3,
    };
    try std.testing.expectEqual(
        Origin{ .x = 12, .baseline_y = 37 },
        pen.glyphOrigin(first),
    );
    pen.advance(first);

    const second = GlyphPosition{
        .glyph_id = 1,
        .codepoint = 'B',
        .cluster = 1,
        .x_advance = 0,
        .y_advance = 0,
        .x_offset = -1,
        .y_offset = -2,
    };
    try std.testing.expectEqual(
        Origin{ .x = 20, .baseline_y = 55 },
        pen.glyphOrigin(second),
    );
    try std.testing.expectEqual(
        Origin{ .x = 17, .baseline_y = 63 },
        offsetOrigin(10, 40, 7, 23),
    );
    try std.testing.expectEqual(
        RasterOrientation.clockwise,
        rasterOrientation(.{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .x_advance = 0,
            .orientation = .sideways,
        }),
    );
}
