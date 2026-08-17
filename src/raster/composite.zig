//! Premultiplied RGBA and COLR Porter-Duff/HSL compositing.

const std = @import("std");
const CompositeMode = @import("../font.zig").ColorPaint.CompositeMode;
const Rgba = @import("targets.zig").Rgba;

fn floatUnitToByte(value: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(value, 0, 1) * 255.0));
}

pub fn blendPixel(dst: *Rgba, src: Rgba) void {
    if (src.a == 0) return;
    const inverse_alpha = 255 - @as(u32, src.a);
    // Channels are premultiplied, so source color is added directly rather
    // than multiplied by alpha a second time.
    dst.r = @intCast(@min(@as(u32, 255), @as(u32, src.r) + (@as(u32, dst.r) * inverse_alpha) / 255));
    dst.g = @intCast(@min(@as(u32, 255), @as(u32, src.g) + (@as(u32, dst.g) * inverse_alpha) / 255));
    dst.b = @intCast(@min(@as(u32, 255), @as(u32, src.b) + (@as(u32, dst.b) * inverse_alpha) / 255));
    dst.a = @intCast(@min(@as(u32, 255), @as(u32, src.a) + (@as(u32, dst.a) * inverse_alpha) / 255));
}

pub fn blendPixels(target: []Rgba, source: []const Rgba) void {
    for (target[0..@min(target.len, source.len)], source) |*destination, pixel| {
        blendPixel(destination, pixel);
    }
}

pub fn compositePixels(source: []const Rgba, backdrop: []Rgba, mode: CompositeMode) void {
    for (source[0..@min(source.len, backdrop.len)], backdrop) |src, *dst| {
        dst.* = compositePixel(src, dst.*, mode);
    }
}

const PremultipliedColor = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    fn fromRgba(pixel: Rgba) PremultipliedColor {
        return .{
            .r = @as(f32, @floatFromInt(pixel.r)) / 255.0,
            .g = @as(f32, @floatFromInt(pixel.g)) / 255.0,
            .b = @as(f32, @floatFromInt(pixel.b)) / 255.0,
            .a = @as(f32, @floatFromInt(pixel.a)) / 255.0,
        };
    }

    fn toRgba(self: PremultipliedColor) Rgba {
        return .{
            .r = floatUnitToByte(self.r),
            .g = floatUnitToByte(self.g),
            .b = floatUnitToByte(self.b),
            .a = floatUnitToByte(self.a),
        };
    }

    fn scale(self: PremultipliedColor, factor: f32) PremultipliedColor {
        return .{
            .r = self.r * factor,
            .g = self.g * factor,
            .b = self.b * factor,
            .a = self.a * factor,
        };
    }

    fn add(a: PremultipliedColor, b: PremultipliedColor) PremultipliedColor {
        return .{
            .r = a.r + b.r,
            .g = a.g + b.g,
            .b = a.b + b.b,
            .a = a.a + b.a,
        };
    }
};

pub fn compositePixel(src_pixel: Rgba, dst_pixel: Rgba, mode: CompositeMode) Rgba {
    const src = PremultipliedColor.fromRgba(src_pixel);
    const dst = PremultipliedColor.fromRgba(dst_pixel);
    return switch (mode) {
        .clear => Rgba{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .src => src_pixel,
        .dest => dst_pixel,
        // Match HarfBuzz's byte-domain Porter-Duff arithmetic exactly. Its
        // alpha multiplication truncates each term before saturated addition;
        // computing the equivalent expression in floats and rounding at the
        // end differs by one for common semi-transparent inputs.
        .src_over => compositePorterDuffBytes(src_pixel, dst_pixel, 255, 255 - src_pixel.a),
        .dest_over => compositePorterDuffBytes(src_pixel, dst_pixel, 255 - dst_pixel.a, 255),
        .src_in => compositePorterDuffBytes(src_pixel, dst_pixel, dst_pixel.a, 0),
        .dest_in => compositePorterDuffBytes(src_pixel, dst_pixel, 0, src_pixel.a),
        .src_out => compositePorterDuffBytes(src_pixel, dst_pixel, 255 - dst_pixel.a, 0),
        .dest_out => compositePorterDuffBytes(src_pixel, dst_pixel, 0, 255 - src_pixel.a),
        .src_atop => compositePorterDuffBytes(src_pixel, dst_pixel, dst_pixel.a, 255 - src_pixel.a),
        .dest_atop => compositePorterDuffBytes(src_pixel, dst_pixel, 255 - dst_pixel.a, src_pixel.a),
        .xor => compositePorterDuffBytes(src_pixel, dst_pixel, 255 - dst_pixel.a, 255 - src_pixel.a),
        .plus => (PremultipliedColor{
            .r = @min(1, src.r + dst.r),
            .g = @min(1, src.g + dst.g),
            .b = @min(1, src.b + dst.b),
            .a = @min(1, src.a + dst.a),
        }).toRgba(),
        .screen, .overlay, .darken, .lighten, .color_dodge, .color_burn, .hard_light, .soft_light, .difference, .exclusion, .multiply => compositeSeparable(src, dst, mode),
        .hsl_hue, .hsl_saturation, .hsl_color, .hsl_luminosity => compositeHsl(src, dst, mode),
    };
}

fn compositePorterDuffBytes(src: Rgba, dst: Rgba, source_factor: u8, backdrop_factor: u8) Rgba {
    const source = scaleRgbaByte(src, source_factor);
    const backdrop = scaleRgbaByte(dst, backdrop_factor);
    return .{
        .r = saturatingAddByte(source.r, backdrop.r),
        .g = saturatingAddByte(source.g, backdrop.g),
        .b = saturatingAddByte(source.b, backdrop.b),
        .a = saturatingAddByte(source.a, backdrop.a),
    };
}

fn scaleRgbaByte(pixel: Rgba, factor: u8) Rgba {
    return .{
        .r = @intCast((@as(u16, pixel.r) * factor) / 255),
        .g = @intCast((@as(u16, pixel.g) * factor) / 255),
        .b = @intCast((@as(u16, pixel.b) * factor) / 255),
        .a = @intCast((@as(u16, pixel.a) * factor) / 255),
    };
}

fn saturatingAddByte(a: u8, b: u8) u8 {
    return @intCast(@min(@as(u16, 255), @as(u16, a) + b));
}

fn compositeSeparable(src: PremultipliedColor, dst: PremultipliedColor, mode: CompositeMode) Rgba {
    const source = unpremultipliedRgb(src);
    const backdrop = unpremultipliedRgb(dst);
    const blend = [3]f32{
        separableBlend(source[0], backdrop[0], mode),
        separableBlend(source[1], backdrop[1], mode),
        separableBlend(source[2], backdrop[2], mode),
    };
    return compositeBlendResult(src, dst, source, backdrop, blend);
}

fn separableBlend(source: f32, backdrop: f32, mode: CompositeMode) f32 {
    return switch (mode) {
        .multiply => source * backdrop,
        .screen => source + backdrop - source * backdrop,
        .overlay => if (backdrop <= 0.5) 2 * source * backdrop else 1 - 2 * (1 - source) * (1 - backdrop),
        .darken => @min(source, backdrop),
        .lighten => @max(source, backdrop),
        .color_dodge => if (backdrop <= 0) 0 else if (source >= 1) 1 else @min(1, backdrop / (1 - source)),
        .color_burn => if (backdrop >= 1) 1 else if (source <= 0) 0 else 1 - @min(1, (1 - backdrop) / source),
        .hard_light => if (source <= 0.5) 2 * source * backdrop else 1 - 2 * (1 - source) * (1 - backdrop),
        .soft_light => softLight(source, backdrop),
        .difference => @abs(source - backdrop),
        .exclusion => source + backdrop - 2 * source * backdrop,
        else => unreachable,
    };
}

fn softLight(source: f32, backdrop: f32) f32 {
    if (source <= 0.5) return backdrop - (1 - 2 * source) * backdrop * (1 - backdrop);
    const d = if (backdrop <= 0.25)
        ((16 * backdrop - 12) * backdrop + 4) * backdrop
    else
        @sqrt(backdrop);
    return backdrop + (2 * source - 1) * (d - backdrop);
}

fn compositeHsl(src: PremultipliedColor, dst: PremultipliedColor, mode: CompositeMode) Rgba {
    const source = unpremultipliedRgb(src);
    const backdrop = unpremultipliedRgb(dst);
    var blend = backdrop;
    switch (mode) {
        .hsl_hue => {
            blend = source;
            setSaturation(&blend, hslSaturation(backdrop));
            setLuminosity(&blend, luminosity(backdrop));
        },
        .hsl_saturation => {
            setSaturation(&blend, hslSaturation(source));
            setLuminosity(&blend, luminosity(backdrop));
        },
        .hsl_color => {
            blend = source;
            setLuminosity(&blend, luminosity(backdrop));
        },
        .hsl_luminosity => setLuminosity(&blend, luminosity(source)),
        else => unreachable,
    }
    return compositeBlendResult(src, dst, source, backdrop, blend);
}

fn unpremultipliedRgb(color: PremultipliedColor) [3]f32 {
    if (color.a <= 0) return .{ 0, 0, 0 };
    return .{ color.r / color.a, color.g / color.a, color.b / color.a };
}

fn compositeBlendResult(src: PremultipliedColor, dst: PremultipliedColor, source: [3]f32, backdrop: [3]f32, blend: [3]f32) Rgba {
    const overlap = src.a * dst.a;
    return (PremultipliedColor{
        .r = overlap * blend[0] + src.a * (1 - dst.a) * source[0] + (1 - src.a) * dst.a * backdrop[0],
        .g = overlap * blend[1] + src.a * (1 - dst.a) * source[1] + (1 - src.a) * dst.a * backdrop[1],
        .b = overlap * blend[2] + src.a * (1 - dst.a) * source[2] + (1 - src.a) * dst.a * backdrop[2],
        .a = src.a + dst.a - overlap,
    }).toRgba();
}

fn luminosity(color: [3]f32) f32 {
    return 0.299 * color[0] + 0.587 * color[1] + 0.114 * color[2];
}

fn hslSaturation(color: [3]f32) f32 {
    return @max(color[0], @max(color[1], color[2])) - @min(color[0], @min(color[1], color[2]));
}

fn setLuminosity(color: *[3]f32, target: f32) void {
    const delta = target - luminosity(color.*);
    for (color) |*channel| channel.* += delta;
    clipHslColor(color);
}

fn clipHslColor(color: *[3]f32) void {
    const light = luminosity(color.*);
    const minimum = @min(color[0], @min(color[1], color[2]));
    const maximum = @max(color[0], @max(color[1], color[2]));
    if (minimum < 0 and light > minimum) {
        for (color) |*channel| channel.* = light + (channel.* - light) * light / (light - minimum);
    }
    if (maximum > 1 and maximum > light) {
        for (color) |*channel| channel.* = light + (channel.* - light) * (1 - light) / (maximum - light);
    }
}

fn setSaturation(color: *[3]f32, target: f32) void {
    var order = [_]usize{ 0, 1, 2 };
    for (1..order.len) |index| {
        const current = order[index];
        var destination = index;
        while (destination > 0 and color[current] < color[order[destination - 1]]) : (destination -= 1) {
            order[destination] = order[destination - 1];
        }
        order[destination] = current;
    }
    const minimum = order[0];
    const middle = order[1];
    const maximum = order[2];
    if (color[maximum] > color[minimum]) {
        color[middle] = (color[middle] - color[minimum]) * target / (color[maximum] - color[minimum]);
        color[maximum] = target;
    } else {
        color[middle] = 0;
        color[maximum] = 0;
    }
    color[minimum] = 0;
}

test {
    _ = @import("composite_tests.zig");
}
