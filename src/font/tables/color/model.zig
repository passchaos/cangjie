//! Renderer-facing records shared by COLR parsing and public color APIs.

const std = @import("std");

const glyph = @import("../../../glyph.zig");

pub const ClipBox = struct {
    x_min: f32,
    y_min: f32,
    x_max: f32,
    y_max: f32,
};

pub const Affine = struct {
    xx: f32 = 1,
    yx: f32 = 0,
    xy: f32 = 0,
    yy: f32 = 1,
    dx: f32 = 0,
    dy: f32 = 0,

    pub const identity: Affine = .{};

    pub fn apply(self: Affine, point: glyph.Point) glyph.Point {
        return .{
            .x = point.x * self.xx + point.y * self.xy + self.dx,
            .y = point.x * self.yx + point.y * self.yy + self.dy,
        };
    }

    pub fn mul(a: Affine, b: Affine) Affine {
        return .{
            .xx = a.xx * b.xx + a.xy * b.yx,
            .yx = a.yx * b.xx + a.yy * b.yx,
            .xy = a.xx * b.xy + a.xy * b.yy,
            .yy = a.yx * b.xy + a.yy * b.yy,
            .dx = a.xx * b.dx + a.xy * b.dy + a.dx,
            .dy = a.yx * b.dx + a.yy * b.dy + a.dy,
        };
    }

    pub fn inverse(self: Affine) ?Affine {
        const determinant = self.xx * self.yy - self.xy * self.yx;
        // F2Dot14 scale paints can encode very small but still invertible
        // matrices. An arbitrary epsilon would discard legal thin gradients.
        if (determinant == 0 or !std.math.isFinite(determinant)) return null;
        const inverse_determinant = 1.0 / determinant;
        const xx = self.yy * inverse_determinant;
        const yx = -self.yx * inverse_determinant;
        const xy = -self.xy * inverse_determinant;
        const yy = self.xx * inverse_determinant;
        return .{
            .xx = xx,
            .yx = yx,
            .xy = xy,
            .yy = yy,
            .dx = -(xx * self.dx + xy * self.dy),
            .dy = -(yx * self.dx + yy * self.dy),
        };
    }
};

pub const Paint = union(enum) {
    solid: Solid,
    linear_gradient: LinearGradient,
    radial_gradient: RadialGradient,
    sweep_gradient: SweepGradient,
    glyph: Glyph,
    clip_glyph: ClipGlyph,
    colr_glyph: ColrGlyph,
    layers: Layers,
    transform: TransformPaint,
    composite: Composite,

    pub const Solid = struct {
        palette_index: u16,
        alpha: f32,
    };

    pub const Glyph = struct {
        glyph_id: glyph.GlyphId,
        brush: Brush,
    };

    pub const ClipGlyph = struct {
        glyph_id: glyph.GlyphId,
        child: ChildRef,
    };

    pub const ColrGlyph = struct {
        glyph_id: glyph.GlyphId,
    };

    pub const Layers = struct {
        first_layer_index: u32,
        layer_count: u8,
    };

    pub const TransformPaint = struct {
        affine: Affine,
        child: ChildRef,
    };

    pub const Composite = struct {
        source: ChildRef,
        backdrop: ChildRef,
        mode: CompositeMode,
    };

    pub const CompositeMode = enum(u8) {
        clear = 0,
        src = 1,
        dest = 2,
        src_over = 3,
        dest_over = 4,
        src_in = 5,
        dest_in = 6,
        src_out = 7,
        dest_out = 8,
        src_atop = 9,
        dest_atop = 10,
        xor = 11,
        plus = 12,
        screen = 13,
        overlay = 14,
        darken = 15,
        lighten = 16,
        color_dodge = 17,
        color_burn = 18,
        hard_light = 19,
        soft_light = 20,
        difference = 21,
        exclusion = 22,
        multiply = 23,
        hsl_hue = 24,
        hsl_saturation = 25,
        hsl_color = 26,
        hsl_luminosity = 27,
    };

    /// Opaque reference to a validated child Paint in the same COLR table.
    pub const ChildRef = struct {
        offset: usize,
    };

    pub const Brush = union(enum) {
        solid: Solid,
        linear_gradient: LinearGradient,
        radial_gradient: RadialGradient,
        sweep_gradient: SweepGradient,
    };

    pub const Extend = enum(u8) {
        pad = 0,
        repeat = 1,
        reflect = 2,
    };

    pub const LinearGradient = struct {
        p0: glyph.Point,
        p1: glyph.Point,
        p2: glyph.Point,
        color_line: ColorLine,
    };

    pub const RadialGradient = struct {
        c0: glyph.Point,
        r0: f32,
        c1: glyph.Point,
        r1: f32,
        color_line: ColorLine,
    };

    pub const SweepGradient = struct {
        center: glyph.Point,
        start_angle: f32,
        end_angle: f32,
        color_line: ColorLine,
    };

    pub const ColorLine = struct {
        extend: Extend,
        stop_count: u16,
        stops_data: []const u8,
        variable: bool = false,

        pub fn stop(self: ColorLine, index: usize) ?ColorStop {
            if (index >= self.stop_count) return null;
            const stop_size: usize = if (self.variable) 10 else 6;
            const start = index * stop_size;
            if (start + stop_size > self.stops_data.len) return null;
            return .{
                .offset = f2dot14(std.mem.readInt(
                    i16,
                    self.stops_data[start..][0..2],
                    .big,
                )),
                .palette_index = std.mem.readInt(
                    u16,
                    self.stops_data[start + 2 ..][0..2],
                    .big,
                ),
                .alpha = f2dot14(std.mem.readInt(
                    i16,
                    self.stops_data[start + 4 ..][0..2],
                    .big,
                )),
            };
        }
    };

    pub const ColorStop = struct {
        offset: f32,
        palette_index: u16,
        alpha: f32,
    };
};

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

test "affine inversion retains tiny legal scales" {
    const tiny = Affine{ .xx = 1.0 / 16384.0, .yy = 1.0 / 16384.0 };
    const inverse = tiny.inverse().?;
    try std.testing.expectEqual(@as(f32, 16384), inverse.xx);
    try std.testing.expectEqual(@as(f32, 16384), inverse.yy);
    try std.testing.expect((Affine{ .xx = 0 }).inverse() == null);
}

test "color line decodes fixed and variable stop records" {
    var fixed: [6]u8 = undefined;
    std.mem.writeInt(i16, fixed[0..2], 0x2000, .big);
    std.mem.writeInt(u16, fixed[2..4], 7, .big);
    std.mem.writeInt(i16, fixed[4..6], 0x4000, .big);
    const stop = (Paint.ColorLine{
        .extend = .pad,
        .stop_count = 1,
        .stops_data = &fixed,
    }).stop(0).?;
    try std.testing.expectEqual(@as(f32, 0.5), stop.offset);
    try std.testing.expectEqual(@as(u16, 7), stop.palette_index);
    try std.testing.expectEqual(@as(f32, 1), stop.alpha);

    var variable: [10]u8 = .{0} ** 10;
    @memcpy(variable[0..6], &fixed);
    const variable_line = Paint.ColorLine{
        .extend = .reflect,
        .stop_count = 1,
        .stops_data = &variable,
        .variable = true,
    };
    try std.testing.expectEqual(@as(u16, 7), variable_line.stop(0).?.palette_index);
    try std.testing.expect(variable_line.stop(1) == null);
}
