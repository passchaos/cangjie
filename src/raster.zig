const std = @import("std");
const font_mod = @import("font.zig");
const glyph_mod = @import("glyph.zig");
const layout = @import("layout.zig");

pub const RenderTarget = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !RenderTarget {
        const pixels = try allocator.alloc(u8, @as(usize, width) * height);
        @memset(pixels, 0);
        return .{ .allocator = allocator, .width = width, .height = height, .pixels = pixels };
    }

    pub fn deinit(self: *RenderTarget) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn clear(self: *RenderTarget, value: u8) void {
        @memset(self.pixels, value);
    }

    pub fn at(self: *const RenderTarget, x: u32, y: u32) u8 {
        return self.pixels[@as(usize, y) * self.width + x];
    }

    fn blend(self: *RenderTarget, x: i32, y: i32, coverage: u8) void {
        if (x < 0 or y < 0) return;
        const ux: u32 = @intCast(x);
        const uy: u32 = @intCast(y);
        if (ux >= self.width or uy >= self.height) return;
        const idx = @as(usize, uy) * self.width + ux;
        self.pixels[idx] = @max(self.pixels[idx], coverage);
    }
};

pub const Rgba = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const SvgPathPaint = struct {
    paint: SvgPaintStyle,
    transform: SvgTransform = .identity,
    clip: ?SvgClipShape = null,
    mask: ?*const SvgMaskDef = null,
    outline: glyph_mod.GlyphOutline,

    fn deinit(self: *SvgPathPaint) void {
        self.outline.deinit();
        self.* = undefined;
    }
};

const SvgPaint = struct {
    view_box: ViewBox,
    paths: []SvgPathPaint,
    gradients: []SvgGradientDef,
    clips: []SvgClipDef,
    masks: []SvgMaskDef,
    styles: []SvgClassStyle,
    allocator: std.mem.Allocator,

    fn deinit(self: *SvgPaint) void {
        for (self.paths) |*path| path.deinit();
        for (self.clips) |*clip| clip.deinit();
        for (self.masks) |*mask| mask.deinit();
        self.allocator.free(self.paths);
        self.allocator.free(self.gradients);
        self.allocator.free(self.clips);
        self.allocator.free(self.masks);
        self.allocator.free(self.styles);
        self.* = undefined;
    }
};

const ViewBox = struct {
    min_x: f32,
    min_y: f32,
    width: f32,
    height: f32,
};

const SvgStrokePaint = struct {
    color: font_mod.PaletteColor,
    width: f32,
    linecap: SvgLineCap = .butt,
    linejoin: SvgLineJoin = .miter,
    miterlimit: f32 = 4,
    dash: ?SvgDashArray = null,
    dash_offset: f32 = 0,
};

const SvgLineCap = enum {
    butt,
    round,
    square,
};

const SvgLineJoin = enum {
    miter,
    round,
    bevel,
};

const SvgDashArray = struct {
    values: [8]f32 = undefined,
    len: u8 = 0,
};

const SvgPaintStyle = union(enum) {
    solid: font_mod.PaletteColor,
    linear_gradient: SvgLinearGradient,
    radial_gradient: SvgRadialGradient,
};

const SvgLinearGradient = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
    spread: SvgGradientSpread = .pad,
    transform: SvgTransform = .identity,
    stops: SvgGradientStops,
};

const SvgRadialGradient = struct {
    cx: f32,
    cy: f32,
    r: f32,
    spread: SvgGradientSpread = .pad,
    transform: SvgTransform = .identity,
    stops: SvgGradientStops,
};

const SvgGradientDef = struct {
    id: []const u8,
    paint: SvgPaintStyle,
};

const SvgClipRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

const SvgClipCircle = struct {
    cx: f32,
    cy: f32,
    r: f32,
};

const SvgClipShape = union(enum) {
    rect: SvgClipRect,
    circle: SvgClipCircle,
    path: glyph_mod.GlyphOutline,
};

const SvgClipDef = struct {
    id: []const u8,
    shape: SvgClipShape,

    fn deinit(self: *SvgClipDef) void {
        switch (self.shape) {
            .path => |*outline| outline.deinit(),
            else => {},
        }
        self.* = undefined;
    }
};

const SvgMaskShape = union(enum) {
    rect: struct { rect: SvgClipRect, alpha: f32 },
    circle: struct { circle: SvgClipCircle, alpha: f32 },
    path: struct { outline: glyph_mod.GlyphOutline, alpha: f32 },
};

const SvgMaskDef = struct {
    id: []const u8,
    shapes: [4]SvgMaskShape = undefined,
    len: u8 = 0,

    fn deinit(self: *SvgMaskDef) void {
        for (self.shapes[0..self.len]) |*shape| {
            switch (shape.*) {
                .path => |*path| path.outline.deinit(),
                else => {},
            }
        }
        self.* = undefined;
    }
};

const SvgStyleSelector = enum {
    class,
    id,
    element,
};

const SvgClassStyle = struct {
    selector: SvgStyleSelector,
    name: []const u8,
    declarations: []const u8,
};

const SvgGradientStop = struct {
    offset: f32,
    color: font_mod.PaletteColor,
};

const SvgGradientStops = struct {
    items: [8]SvgGradientStop = undefined,
    len: u8 = 0,
};

const SvgGradientSpread = enum {
    pad,
    repeat,
    reflect,
};

const SvgTransform = struct {
    xx: f32 = 1,
    yx: f32 = 0,
    xy: f32 = 0,
    yy: f32 = 1,
    dx: f32 = 0,
    dy: f32 = 0,

    const identity: SvgTransform = .{};

    fn apply(self: SvgTransform, point: Point) Point {
        return .{
            .x = point.x * self.xx + point.y * self.xy + self.dx,
            .y = point.x * self.yx + point.y * self.yy + self.dy,
        };
    }

    fn mul(a: SvgTransform, b: SvgTransform) SvgTransform {
        return .{
            .xx = a.xx * b.xx + a.xy * b.yx,
            .yx = a.yx * b.xx + a.yy * b.yx,
            .xy = a.xx * b.xy + a.xy * b.yy,
            .yy = a.yx * b.xy + a.yy * b.yy,
            .dx = a.xx * b.dx + a.xy * b.dy + a.dx,
            .dy = a.yx * b.dx + a.yy * b.dy + a.dy,
        };
    }

    fn inverse(self: SvgTransform) ?SvgTransform {
        const det = self.xx * self.yy - self.xy * self.yx;
        if (@abs(det) <= 0.000001) return null;
        const inv_det = 1.0 / det;
        const xx = self.yy * inv_det;
        const yx = -self.yx * inv_det;
        const xy = -self.xy * inv_det;
        const yy = self.xx * inv_det;
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

pub const ColorRenderTarget = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    pixels: []Rgba,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !ColorRenderTarget {
        const pixels = try allocator.alloc(Rgba, @as(usize, width) * height);
        @memset(pixels, .{ .r = 0, .g = 0, .b = 0, .a = 0 });
        return .{ .allocator = allocator, .width = width, .height = height, .pixels = pixels };
    }

    pub fn deinit(self: *ColorRenderTarget) void {
        self.allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn clear(self: *ColorRenderTarget, color: Rgba) void {
        @memset(self.pixels, color);
    }

    pub fn at(self: *const ColorRenderTarget, x: u32, y: u32) Rgba {
        return self.pixels[@as(usize, y) * self.width + x];
    }

    fn blendMask(self: *ColorRenderTarget, mask: *const RenderTarget, color: font_mod.PaletteColor) void {
        const count = @min(self.pixels.len, mask.pixels.len);
        for (mask.pixels[0..count], 0..) |coverage, index| {
            if (coverage == 0) continue;
            const src_a = (@as(u32, coverage) * color.alpha) / 255;
            if (src_a == 0) continue;
            const dst = &self.pixels[index];
            const inv_a = 255 - src_a;
            dst.r = @intCast((@as(u32, color.red) * src_a + @as(u32, dst.r) * inv_a) / 255);
            dst.g = @intCast((@as(u32, color.green) * src_a + @as(u32, dst.g) * inv_a) / 255);
            dst.b = @intCast((@as(u32, color.blue) * src_a + @as(u32, dst.b) * inv_a) / 255);
            dst.a = @intCast(@min(@as(u32, 255), src_a + (@as(u32, dst.a) * inv_a) / 255));
        }
    }

    fn blendGradientMask(self: *ColorRenderTarget, mask: *const RenderTarget, gradient: SvgLinearGradient, view_box: ViewBox, x: f32, baseline_y: f32, font_size: f32) void {
        const count = @min(self.pixels.len, mask.pixels.len);
        if (view_box.height <= 0) return;
        const scale = font_size / view_box.height;
        if (scale == 0) return;
        const origin_x = x - view_box.min_x * scale;
        const origin_y = baseline_y - font_size - view_box.min_y * scale;
        const dx = gradient.x2 - gradient.x1;
        const dy = gradient.y2 - gradient.y1;
        const denom = dx * dx + dy * dy;
        const inverse_transform = gradient.transform.inverse() orelse SvgTransform.identity;
        for (mask.pixels[0..count], 0..) |coverage, index| {
            if (coverage == 0) continue;
            const px = @as(f32, @floatFromInt(index % self.width)) + 0.5;
            const py = @as(f32, @floatFromInt(index / self.width)) + 0.5;
            const sample = inverse_transform.apply(.{
                .x = (px - origin_x) / scale,
                .y = (py - origin_y) / scale,
            });
            const sx = sample.x;
            const sy = sample.y;
            const raw_t = if (denom > 0) ((sx - gradient.x1) * dx + (sy - gradient.y1) * dy) / denom else 0.0;
            const t = applyGradientSpread(raw_t, gradient.spread);
            const color = gradientColorAt(gradient.stops, t);
            const src_a = (@as(u32, coverage) * color.alpha) / 255;
            if (src_a == 0) continue;
            const dst = &self.pixels[index];
            const inv_a = 255 - src_a;
            dst.r = @intCast((@as(u32, color.red) * src_a + @as(u32, dst.r) * inv_a) / 255);
            dst.g = @intCast((@as(u32, color.green) * src_a + @as(u32, dst.g) * inv_a) / 255);
            dst.b = @intCast((@as(u32, color.blue) * src_a + @as(u32, dst.b) * inv_a) / 255);
            dst.a = @intCast(@min(@as(u32, 255), src_a + (@as(u32, dst.a) * inv_a) / 255));
        }
    }

    fn blendRadialGradientMask(self: *ColorRenderTarget, mask: *const RenderTarget, gradient: SvgRadialGradient, view_box: ViewBox, x: f32, baseline_y: f32, font_size: f32) void {
        const count = @min(self.pixels.len, mask.pixels.len);
        if (view_box.height <= 0 or gradient.r <= 0) return;
        const scale = font_size / view_box.height;
        if (scale == 0) return;
        const origin_x = x - view_box.min_x * scale;
        const origin_y = baseline_y - font_size - view_box.min_y * scale;
        const inverse_transform = gradient.transform.inverse() orelse SvgTransform.identity;
        for (mask.pixels[0..count], 0..) |coverage, index| {
            if (coverage == 0) continue;
            const px = @as(f32, @floatFromInt(index % self.width)) + 0.5;
            const py = @as(f32, @floatFromInt(index / self.width)) + 0.5;
            const sample = inverse_transform.apply(.{
                .x = (px - origin_x) / scale,
                .y = (py - origin_y) / scale,
            });
            const sx = sample.x;
            const sy = sample.y;
            const dx = sx - gradient.cx;
            const dy = sy - gradient.cy;
            const t = applyGradientSpread(@sqrt(dx * dx + dy * dy) / gradient.r, gradient.spread);
            const color = gradientColorAt(gradient.stops, t);
            const src_a = (@as(u32, coverage) * color.alpha) / 255;
            if (src_a == 0) continue;
            const dst = &self.pixels[index];
            const inv_a = 255 - src_a;
            dst.r = @intCast((@as(u32, color.red) * src_a + @as(u32, dst.r) * inv_a) / 255);
            dst.g = @intCast((@as(u32, color.green) * src_a + @as(u32, dst.g) * inv_a) / 255);
            dst.b = @intCast((@as(u32, color.blue) * src_a + @as(u32, dst.b) * inv_a) / 255);
            dst.a = @intCast(@min(@as(u32, 255), src_a + (@as(u32, dst.a) * inv_a) / 255));
        }
    }
};

fn interpolatePaletteColor(a: font_mod.PaletteColor, b: font_mod.PaletteColor, t: f32) font_mod.PaletteColor {
    return .{
        .red = lerpByte(a.red, b.red, t),
        .green = lerpByte(a.green, b.green, t),
        .blue = lerpByte(a.blue, b.blue, t),
        .alpha = lerpByte(a.alpha, b.alpha, t),
    };
}

fn gradientColorAt(stops: SvgGradientStops, t: f32) font_mod.PaletteColor {
    if (stops.len == 0) return .{ .red = 0, .green = 0, .blue = 0, .alpha = 0 };
    const clamped = @max(0.0, @min(1.0, t));
    const first = stops.items[0];
    if (clamped <= first.offset or stops.len == 1) return first.color;
    var previous = first;
    for (stops.items[1..stops.len]) |stop| {
        if (clamped <= stop.offset) {
            const span = stop.offset - previous.offset;
            const local_t = if (span > 0) (clamped - previous.offset) / span else 0.0;
            return interpolatePaletteColor(previous.color, stop.color, local_t);
        }
        previous = stop;
    }
    return previous.color;
}

fn applyGradientSpread(t: f32, spread: SvgGradientSpread) f32 {
    return switch (spread) {
        .pad => @max(0.0, @min(1.0, t)),
        .repeat => t - @floor(t),
        .reflect => blk: {
            const period = t - @floor(t / 2.0) * 2.0;
            break :blk if (period <= 1.0) period else 2.0 - period;
        },
    };
}

fn lerpByte(a: u8, b: u8, t: f32) u8 {
    const value = @as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * t;
    return @intFromFloat(@round(@max(0.0, @min(255.0, value))));
}

pub const Rasterizer = struct {
    allocator: std.mem.Allocator,
    samples_per_axis: u8 = 4,
    hint_size_px: ?f32 = null,

    pub fn init(allocator: std.mem.Allocator) Rasterizer {
        return .{ .allocator = allocator };
    }

    pub fn renderGlyph(self: *Rasterizer, target: *RenderTarget, outline: *const glyph_mod.GlyphOutline, x: f32, baseline_y: f32, font_size: f32, units_per_em: u16) !void {
        var flattened = std.ArrayList(Line).empty;
        defer flattened.deinit(self.allocator);
        const scale = font_size / @as(f32, @floatFromInt(units_per_em));
        try flattenOutline(self.allocator, &flattened, outline, scale, x, baseline_y);
        const hint_size = self.hint_size_px orelse font_size;
        alignSmallGlyphToPixelGrid(flattened.items, outline, scale, font_size, hint_size);
        try self.fillLines(target, flattened.items);
        if (hint_size <= 20.0) {
            try self.emboldenSmallGlyph(target, flattened.items, hint_size);
        }
    }

    pub fn renderRun(self: *Rasterizer, target: *RenderTarget, run: layout.GlyphRun, x: f32, baseline_y: f32) !void {
        var pen_x = x;
        for (run.glyphs) |position| {
            var outline = try run.font.glyphOutline(self.allocator, position.glyph_id);
            defer outline.deinit();
            try self.renderGlyph(target, &outline, pen_x + position.x_offset, baseline_y + position.y_offset, run.font_size, run.font.units_per_em);
            pen_x += position.x_advance;
        }
    }

    pub fn renderShapedText(self: *Rasterizer, target: *RenderTarget, shaped: layout.ShapedText, x: f32, baseline_y: f32) !void {
        for (shaped.runs) |run| {
            try self.renderRun(target, run.glyphRun(shaped), x + run.x_offset, baseline_y);
        }
    }

    pub fn renderColorRun(self: *Rasterizer, target: *ColorRenderTarget, run: layout.GlyphRun, x: f32, baseline_y: f32, palette_index: u16) !void {
        var pen_x = x;
        for (run.glyphs) |position| {
            try self.renderColorGlyph(target, run.font, position.glyph_id, run.font_size, pen_x + position.x_offset, baseline_y + position.y_offset, palette_index);
            pen_x += position.x_advance;
        }
    }

    pub fn renderColorShapedText(self: *Rasterizer, target: *ColorRenderTarget, shaped: layout.ShapedText, x: f32, baseline_y: f32, palette_index: u16) !void {
        for (shaped.runs) |run| {
            try self.renderColorRun(target, run.glyphRun(shaped), x + run.x_offset, baseline_y, palette_index);
        }
    }

    pub fn renderColorGlyph(self: *Rasterizer, target: *ColorRenderTarget, font: *const font_mod.Font, glyph_id: glyph_mod.GlyphId, font_size: f32, x: f32, baseline_y: f32, palette_index: u16) !void {
        const layers = try font.colorLayers(self.allocator, glyph_id);
        defer self.allocator.free(layers);
        if (layers.len == 0) {
            if (try font.colorPaint(glyph_id)) |paint| {
                try self.renderColorPaint(target, font, paint, glyph_id, font_size, x, baseline_y, palette_index);
                return;
            }
            if (try font.svgDocument(glyph_id)) |document| {
                var maybe_svg_paint = try parseSvgPaint(self.allocator, glyph_id, document);
                if (maybe_svg_paint) |*svg_paint| {
                    defer svg_paint.deinit();
                    for (svg_paint.paths) |*path| {
                        var mask = try RenderTarget.init(self.allocator, target.width, target.height);
                        defer mask.deinit();
                        try self.renderSvgGlyphMask(&mask, &path.outline, path.transform, svg_paint.view_box, x, baseline_y, font_size);
                        if (path.clip) |clip| applySvgClipToMask(&mask, clip, svg_paint.view_box, x, baseline_y, font_size);
                        if (path.mask) |svg_mask| applySvgMaskToMask(&mask, svg_mask.*, svg_paint.view_box, x, baseline_y, font_size);
                        switch (path.paint) {
                            .solid => |color| target.blendMask(&mask, color),
                            .linear_gradient => |gradient| target.blendGradientMask(&mask, gradient, svg_paint.view_box, x, baseline_y, font_size),
                            .radial_gradient => |gradient| target.blendRadialGradientMask(&mask, gradient, svg_paint.view_box, x, baseline_y, font_size),
                        }
                    }
                    return;
                }
            }
            var outline = try font.glyphOutline(self.allocator, glyph_id);
            defer outline.deinit();
            var mask = try RenderTarget.init(self.allocator, target.width, target.height);
            defer mask.deinit();
            try self.renderGlyph(&mask, &outline, x, baseline_y, font_size, font.units_per_em);
            target.blendMask(&mask, .{ .red = 255, .green = 255, .blue = 255, .alpha = 255 });
            return;
        }

        for (layers) |layer| {
            const color = (try font.paletteColor(palette_index, layer.palette_index)) orelse continue;
            var outline = try font.glyphOutline(self.allocator, layer.glyph_id);
            defer outline.deinit();
            var mask = try RenderTarget.init(self.allocator, target.width, target.height);
            defer mask.deinit();
            try self.renderGlyph(&mask, &outline, x, baseline_y, font_size, font.units_per_em);
            target.blendMask(&mask, color);
        }
    }

    fn renderColorPaint(self: *Rasterizer, target: *ColorRenderTarget, font: *const font_mod.Font, paint: font_mod.ColorPaint, fallback_glyph_id: glyph_mod.GlyphId, font_size: f32, x: f32, baseline_y: f32, palette_index: u16) !void {
        switch (paint) {
            .solid => |solid| try self.renderSolidPaint(target, font, fallback_glyph_id, solid, font_size, x, baseline_y, palette_index),
            .glyph => |glyph_paint| try self.renderSolidPaint(target, font, glyph_paint.glyph_id, glyph_paint.solid, font_size, x, baseline_y, palette_index),
            .layers => |layers| {
                for (0..layers.layer_count) |offset| {
                    const child = (try font.colorPaintLayer(layers.first_layer_index + @as(u32, @intCast(offset)))) orelse continue;
                    try self.renderColorPaint(target, font, child, fallback_glyph_id, font_size, x, baseline_y, palette_index);
                }
            },
        }
    }

    fn renderSolidPaint(self: *Rasterizer, target: *ColorRenderTarget, font: *const font_mod.Font, glyph_id: glyph_mod.GlyphId, solid: font_mod.ColorPaint.Solid, font_size: f32, x: f32, baseline_y: f32, palette_index: u16) !void {
        const base_color = (try font.paletteColor(palette_index, solid.palette_index)) orelse return;
        var outline = try font.glyphOutline(self.allocator, glyph_id);
        defer outline.deinit();
        var mask = try RenderTarget.init(self.allocator, target.width, target.height);
        defer mask.deinit();
        try self.renderGlyph(&mask, &outline, x, baseline_y, font_size, font.units_per_em);
        target.blendMask(&mask, .{
            .red = base_color.red,
            .green = base_color.green,
            .blue = base_color.blue,
            .alpha = @intCast((@as(u32, base_color.alpha) * @as(u32, @intFromFloat(@round(solid.alpha * 255.0)))) / 255),
        });
    }

    fn renderSvgGlyphMask(self: *Rasterizer, target: *RenderTarget, outline: *const glyph_mod.GlyphOutline, transform: SvgTransform, view_box: ViewBox, x: f32, baseline_y: f32, font_size: f32) !void {
        var flattened = std.ArrayList(Line).empty;
        defer flattened.deinit(self.allocator);
        if (view_box.width <= 0 or view_box.height <= 0) return;
        const scale = font_size / view_box.height;
        const origin_x = x - view_box.min_x * scale;
        const origin_y = baseline_y - font_size - view_box.min_y * scale;
        try flattenSvgOutline(self.allocator, &flattened, outline, transform, scale, origin_x, origin_y);
        try self.fillLines(target, flattened.items);
    }

    fn fillLines(self: *Rasterizer, target: *RenderTarget, lines: []const Line) !void {
        if (lines.len == 0) return;
        var min_x: i32 = std.math.maxInt(i32);
        var min_y: i32 = std.math.maxInt(i32);
        var max_x: i32 = std.math.minInt(i32);
        var max_y: i32 = std.math.minInt(i32);
        for (lines) |line| {
            min_x = @min(min_x, @as(i32, @intFromFloat(@floor(@min(line.a.x, line.b.x)))));
            min_y = @min(min_y, @as(i32, @intFromFloat(@floor(@min(line.a.y, line.b.y)))));
            max_x = @max(max_x, @as(i32, @intFromFloat(@ceil(@max(line.a.x, line.b.x)))));
            max_y = @max(max_y, @as(i32, @intFromFloat(@ceil(@max(line.a.y, line.b.y)))));
        }
        min_x = @max(0, min_x - 1);
        min_y = @max(0, min_y - 1);
        max_x = @min(@as(i32, @intCast(target.width)) - 1, max_x + 1);
        max_y = @min(@as(i32, @intCast(target.height)) - 1, max_y + 1);
        if (max_x < min_x or max_y < min_y) return;

        const sample_axis: i32 = @max(1, @as(i32, self.samples_per_axis));
        const sample_count = sample_axis * sample_axis;
        const row_width_i32 = max_x - min_x + 1;
        if (row_width_i32 <= 0) return;
        const row_width: usize = @intCast(row_width_i32);
        var coverage_counts = try self.allocator.alloc(u8, row_width);
        defer self.allocator.free(coverage_counts);
        var intersections: std.ArrayList(f32) = .empty;
        defer intersections.deinit(self.allocator);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            @memset(coverage_counts, 0);
            var sy: i32 = 0;
            while (sy < sample_axis) : (sy += 1) {
                const py = @as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(sy)) + 0.5) / @as(f32, @floatFromInt(sample_axis));
                intersections.clearRetainingCapacity();
                for (lines) |line| {
                    const ay = line.a.y;
                    const by = line.b.y;
                    if ((ay > py) == (by > py)) continue;
                    const x_intersect = (line.b.x - line.a.x) * (py - ay) / (by - ay) + line.a.x;
                    try intersections.append(self.allocator, x_intersect);
                }
                if (intersections.items.len < 2) continue;
                std.sort.heap(f32, intersections.items, {}, lessThanF32);

                var pair: usize = 0;
                while (pair + 1 < intersections.items.len) : (pair += 2) {
                    const start_f = intersections.items[pair];
                    const end_f = intersections.items[pair + 1];
                    if (end_f <= @as(f32, @floatFromInt(min_x)) or start_f >= @as(f32, @floatFromInt(max_x + 1))) continue;
                    var x = @max(min_x, @as(i32, @intFromFloat(@floor(start_f))));
                    const x_end = @min(max_x, @as(i32, @intFromFloat(@ceil(end_f))));
                    while (x <= x_end) : (x += 1) {
                        var sx: i32 = 0;
                        while (sx < sample_axis) : (sx += 1) {
                            const px = @as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(sx)) + 0.5) / @as(f32, @floatFromInt(sample_axis));
                            if (px >= start_f and px < end_f) {
                                coverage_counts[@intCast(x - min_x)] += 1;
                            }
                        }
                    }
                }
            }
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const inside = coverage_counts[@intCast(x - min_x)];
                if (inside == 0) continue;
                const coverage: u8 = @intCast(@divTrunc(@as(i32, inside) * 255, sample_count));
                target.blend(x, y, coverage);
            }
        }
    }

    fn emboldenSmallGlyph(self: *Rasterizer, target: *RenderTarget, lines: []const Line, font_size: f32) !void {
        if (lines.len == 0 or font_size > 16.0) return;
        var min_x: i32 = std.math.maxInt(i32);
        var min_y: i32 = std.math.maxInt(i32);
        var max_x: i32 = std.math.minInt(i32);
        var max_y: i32 = std.math.minInt(i32);
        for (lines) |line| {
            min_x = @min(min_x, @as(i32, @intFromFloat(@floor(@min(line.a.x, line.b.x)))));
            min_y = @min(min_y, @as(i32, @intFromFloat(@floor(@min(line.a.y, line.b.y)))));
            max_x = @max(max_x, @as(i32, @intFromFloat(@ceil(@max(line.a.x, line.b.x)))));
            max_y = @max(max_y, @as(i32, @intFromFloat(@ceil(@max(line.a.y, line.b.y)))));
        }
        min_x = @max(0, min_x - 1);
        min_y = @max(0, min_y - 1);
        max_x = @min(@as(i32, @intCast(target.width)) - 1, max_x + 1);
        max_y = @min(@as(i32, @intCast(target.height)) - 1, max_y + 1);
        if (max_x < min_x or max_y < min_y) return;

        const width: usize = @intCast(max_x - min_x + 1);
        const height: usize = @intCast(max_y - min_y + 1);
        const original = try self.allocator.alloc(u8, width * height);
        defer self.allocator.free(original);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const src_idx = @as(usize, @intCast(y)) * target.width + @as(usize, @intCast(x));
                const dst_idx = @as(usize, @intCast(y - min_y)) * width + @as(usize, @intCast(x - min_x));
                original[dst_idx] = target.pixels[src_idx];
            }
        }

        y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const local = @as(usize, @intCast(y - min_y)) * width + @as(usize, @intCast(x - min_x));
                const coverage = original[local];
                if (coverage == 0) continue;
                const expanded: u8 = @intCast(@min(@as(u16, 255), @as(u16, coverage) + 24));
                const side: u8 = @intCast(@min(@as(u16, 255), @as(u16, coverage) * 3 / 5));
                const vertical: u8 = @intCast(@min(@as(u16, 255), @as(u16, coverage) * 2 / 3));
                target.blend(x, y, expanded);
                if (x - 1 >= min_x) target.blend(x - 1, y, side);
                if (x + 1 <= max_x) target.blend(x + 1, y, side);
                if (y - 1 >= min_y) target.blend(x, y - 1, vertical);
                if (y + 1 <= max_y) target.blend(x, y + 1, vertical);
            }
        }
    }
};

fn lessThanF32(_: void, lhs: f32, rhs: f32) bool {
    return lhs < rhs;
}

fn applySvgClipToMask(mask: *RenderTarget, clip: SvgClipShape, view_box: ViewBox, x: f32, baseline_y: f32, font_size: f32) void {
    if (view_box.height <= 0) {
        @memset(mask.pixels, 0);
        return;
    }
    const scale = font_size / view_box.height;
    if (scale == 0) {
        @memset(mask.pixels, 0);
        return;
    }
    const origin_x = x - view_box.min_x * scale;
    const origin_y = baseline_y - font_size - view_box.min_y * scale;
    for (mask.pixels, 0..) |*coverage, index| {
        if (coverage.* == 0) continue;
        const px = @as(f32, @floatFromInt(index % mask.width)) + 0.5;
        const py = @as(f32, @floatFromInt(index / mask.width)) + 0.5;
        const inside = switch (clip) {
            .rect => |rect| blk: {
                if (rect.width <= 0 or rect.height <= 0) break :blk false;
                const min_x = origin_x + rect.x * scale;
                const min_y = origin_y + rect.y * scale;
                const max_x = origin_x + (rect.x + rect.width) * scale;
                const max_y = origin_y + (rect.y + rect.height) * scale;
                break :blk px >= min_x and px <= max_x and py >= min_y and py <= max_y;
            },
            .circle => |circle| blk: {
                if (circle.r <= 0) break :blk false;
                const cx = origin_x + circle.cx * scale;
                const cy = origin_y + circle.cy * scale;
                const radius = circle.r * scale;
                const dx = px - cx;
                const dy = py - cy;
                break :blk dx * dx + dy * dy <= radius * radius;
            },
            .path => |outline| blk: {
                break :blk pointInsideSvgClipPath(outline, scale, origin_x, origin_y, .{ .x = px, .y = py });
            },
        };
        if (!inside) coverage.* = 0;
    }
}

fn applySvgMaskToMask(mask: *RenderTarget, svg_mask: SvgMaskDef, view_box: ViewBox, x: f32, baseline_y: f32, font_size: f32) void {
    if (view_box.height <= 0) {
        @memset(mask.pixels, 0);
        return;
    }
    const scale = font_size / view_box.height;
    if (scale == 0) {
        @memset(mask.pixels, 0);
        return;
    }
    const origin_x = x - view_box.min_x * scale;
    const origin_y = baseline_y - font_size - view_box.min_y * scale;
    for (mask.pixels, 0..) |*coverage, index| {
        if (coverage.* == 0) continue;
        const px = @as(f32, @floatFromInt(index % mask.width)) + 0.5;
        const py = @as(f32, @floatFromInt(index / mask.width)) + 0.5;
        var alpha: f32 = 0;
        for (svg_mask.shapes[0..svg_mask.len]) |shape| {
            const shape_alpha = switch (shape) {
                .rect => |rect_mask| maskRectAlpha(px, py, rect_mask.rect, rect_mask.alpha, scale, origin_x, origin_y),
                .circle => |circle_mask| maskCircleAlpha(px, py, circle_mask.circle, circle_mask.alpha, scale, origin_x, origin_y),
                .path => |path_mask| if (pointInsideSvgClipPath(path_mask.outline, scale, origin_x, origin_y, .{ .x = px, .y = py }))
                    @max(0.0, @min(1.0, path_mask.alpha))
                else
                    0.0,
            };
            alpha = @max(alpha, shape_alpha);
        }
        coverage.* = @intFromFloat(@round(@as(f32, @floatFromInt(coverage.*)) * alpha));
    }
}

fn maskRectAlpha(px: f32, py: f32, rect: SvgClipRect, alpha: f32, scale: f32, origin_x: f32, origin_y: f32) f32 {
    if (rect.width <= 0 or rect.height <= 0) return 0;
    const min_x = origin_x + rect.x * scale;
    const min_y = origin_y + rect.y * scale;
    const max_x = origin_x + (rect.x + rect.width) * scale;
    const max_y = origin_y + (rect.y + rect.height) * scale;
    if (px < min_x or px > max_x or py < min_y or py > max_y) return 0;
    return @max(0.0, @min(1.0, alpha));
}

fn maskCircleAlpha(px: f32, py: f32, circle: SvgClipCircle, alpha: f32, scale: f32, origin_x: f32, origin_y: f32) f32 {
    if (circle.r <= 0) return 0;
    const cx = origin_x + circle.cx * scale;
    const cy = origin_y + circle.cy * scale;
    const radius = circle.r * scale;
    const dx = px - cx;
    const dy = py - cy;
    if (dx * dx + dy * dy > radius * radius) return 0;
    return @max(0.0, @min(1.0, alpha));
}

fn pointInsideSvgClipPath(outline: glyph_mod.GlyphOutline, scale: f32, origin_x: f32, origin_y: f32, point: Point) bool {
    var start: ?Point = null;
    var current: ?Point = null;
    var crossings: usize = 0;
    for (outline.commands.items) |command| {
        switch (command) {
            .move_to => |p| {
                const q = svgToPixel(p, scale, origin_x, origin_y);
                start = q;
                current = q;
            },
            .line_to => |p| {
                const a = current orelse continue;
                const b = svgToPixel(p, scale, origin_x, origin_y);
                if (rayCrossesSegment(point, a, b)) crossings += 1;
                current = b;
            },
            .quad_to => |q| {
                const from = current orelse continue;
                var prev = from;
                const control = svgToPixel(q.control, scale, origin_x, origin_y);
                const end = svgToPixel(q.end, scale, origin_x, origin_y);
                for (1..17) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 16.0;
                    const p = quadPoint(from, control, end, t);
                    if (rayCrossesSegment(point, prev, p)) crossings += 1;
                    prev = p;
                }
                current = end;
            },
            .cubic_to => |c| {
                const from = current orelse continue;
                var prev = from;
                const c0 = svgToPixel(c.c0, scale, origin_x, origin_y);
                const c1 = svgToPixel(c.c1, scale, origin_x, origin_y);
                const end = svgToPixel(c.end, scale, origin_x, origin_y);
                for (1..25) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 24.0;
                    const p = cubicPoint(from, c0, c1, end, t);
                    if (rayCrossesSegment(point, prev, p)) crossings += 1;
                    prev = p;
                }
                current = end;
            },
            .close => {
                if (current) |a| {
                    if (start) |b| {
                        if (rayCrossesSegment(point, a, b)) crossings += 1;
                    }
                }
                current = start;
            },
        }
    }
    return crossings % 2 == 1;
}

fn rayCrossesSegment(point: Point, a: Point, b: Point) bool {
    if ((a.y > point.y) == (b.y > point.y)) return false;
    const x_intersect = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x;
    return point.x < x_intersect;
}

const Point = glyph_mod.Point;

const Line = struct {
    a: Point,
    b: Point,
};

fn alignSmallGlyphToPixelGrid(lines: []Line, outline: *const glyph_mod.GlyphOutline, scale: f32, font_size: f32, hint_size: f32) void {
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
    if (!std.math.isFinite(min_x) or !std.math.isFinite(min_y) or !std.math.isFinite(max_x) or !std.math.isFinite(max_y)) return;
    const dx = @round(min_x) - min_x;
    const dy = @round(max_y) - max_y;

    var sy: f32 = 1.0;
    var y_anchor = max_y;
    const glyph_height_units = outline.bounds.y_max - outline.bounds.y_min;
    const glyph_height_px = @as(f32, @floatFromInt(glyph_height_units)) * scale;
    const raster_scale = if (hint_size > 0.0) font_size / hint_size else 1.0;
    if (outlineContourCount(outline) > 1 and glyph_height_px >= 4.0 * raster_scale and glyph_height_px <= 9.5 * raster_scale) {
        const hinted_height = @max(@ceil(glyph_height_px), @round(hint_size * 0.72) * raster_scale);
        if (hinted_height > glyph_height_px) {
            sy = hinted_height / glyph_height_px;
            y_anchor = max_y;
        }
    }

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001 and @abs(sy - 1.0) < 0.001) return;
    for (lines) |*line| {
        line.a.x += dx;
        line.b.x += dx;
        line.a.y += dy;
        line.b.y += dy;
        if (sy != 1.0) {
            line.a.y = y_anchor + (line.a.y - y_anchor) * sy;
            line.b.y = y_anchor + (line.b.y - y_anchor) * sy;
        }
    }
}

fn outlineContourCount(outline: *const glyph_mod.GlyphOutline) usize {
    var count: usize = 0;
    for (outline.commands.items) |command| {
        if (command == .move_to) count += 1;
    }
    return count;
}

fn flattenOutline(allocator: std.mem.Allocator, lines: *std.ArrayList(Line), outline: *const glyph_mod.GlyphOutline, scale: f32, x: f32, baseline_y: f32) !void {
    var start: ?Point = null;
    var current: ?Point = null;
    for (outline.commands.items) |command| {
        switch (command) {
            .move_to => |p| {
                const q = fontToPixel(p, scale, x, baseline_y);
                start = q;
                current = q;
            },
            .line_to => |p| {
                const a = current orelse continue;
                const b = fontToPixel(p, scale, x, baseline_y);
                try lines.append(allocator, .{ .a = a, .b = b });
                current = b;
            },
            .quad_to => |q| {
                const a = current orelse continue;
                var prev = a;
                for (1..17) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 16.0;
                    const p = quadPoint(a, fontToPixel(q.control, scale, x, baseline_y), fontToPixel(q.end, scale, x, baseline_y), t);
                    try lines.append(allocator, .{ .a = prev, .b = p });
                    prev = p;
                }
                current = fontToPixel(q.end, scale, x, baseline_y);
            },
            .cubic_to => |c| {
                const a = current orelse continue;
                var prev = a;
                for (1..25) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 24.0;
                    const p = cubicPoint(a, fontToPixel(c.c0, scale, x, baseline_y), fontToPixel(c.c1, scale, x, baseline_y), fontToPixel(c.end, scale, x, baseline_y), t);
                    try lines.append(allocator, .{ .a = prev, .b = p });
                    prev = p;
                }
                current = fontToPixel(c.end, scale, x, baseline_y);
            },
            .close => {
                if (current) |a| {
                    if (start) |b| {
                        try lines.append(allocator, .{ .a = a, .b = b });
                    }
                }
                current = start;
            },
        }
    }
}

fn fontToPixel(point: Point, scale: f32, x: f32, baseline_y: f32) Point {
    return .{ .x = x + point.x * scale, .y = baseline_y - point.y * scale };
}

fn svgToPixel(point: Point, scale: f32, origin_x: f32, origin_y: f32) Point {
    return .{ .x = origin_x + point.x * scale, .y = origin_y + point.y * scale };
}

fn flattenSvgOutline(allocator: std.mem.Allocator, lines: *std.ArrayList(Line), outline: *const glyph_mod.GlyphOutline, transform: SvgTransform, scale: f32, origin_x: f32, origin_y: f32) !void {
    var start: ?Point = null;
    var current: ?Point = null;
    for (outline.commands.items) |command| {
        switch (command) {
            .move_to => |p| {
                const q = svgToPixel(transform.apply(p), scale, origin_x, origin_y);
                start = q;
                current = q;
            },
            .line_to => |p| {
                const a = current orelse continue;
                const b = svgToPixel(transform.apply(p), scale, origin_x, origin_y);
                try lines.append(allocator, .{ .a = a, .b = b });
                current = b;
            },
            .quad_to => |q| {
                const a = current orelse continue;
                var prev = a;
                for (1..17) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 16.0;
                    const p = quadPoint(a, svgToPixel(transform.apply(q.control), scale, origin_x, origin_y), svgToPixel(transform.apply(q.end), scale, origin_x, origin_y), t);
                    try lines.append(allocator, .{ .a = prev, .b = p });
                    prev = p;
                }
                current = svgToPixel(transform.apply(q.end), scale, origin_x, origin_y);
            },
            .cubic_to => |c| {
                const a = current orelse continue;
                var prev = a;
                for (1..25) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 24.0;
                    const p = cubicPoint(a, svgToPixel(transform.apply(c.c0), scale, origin_x, origin_y), svgToPixel(transform.apply(c.c1), scale, origin_x, origin_y), svgToPixel(transform.apply(c.end), scale, origin_x, origin_y), t);
                    try lines.append(allocator, .{ .a = prev, .b = p });
                    prev = p;
                }
                current = svgToPixel(transform.apply(c.end), scale, origin_x, origin_y);
            },
            .close => {
                if (current) |a| {
                    if (start) |b| {
                        try lines.append(allocator, .{ .a = a, .b = b });
                    }
                }
                current = start;
            },
        }
    }
}

fn quadPoint(a: Point, b: Point, c: Point, t: f32) Point {
    const mt = 1.0 - t;
    return .{
        .x = mt * mt * a.x + 2.0 * mt * t * b.x + t * t * c.x,
        .y = mt * mt * a.y + 2.0 * mt * t * b.y + t * t * c.y,
    };
}

fn cubicPoint(a: Point, b: Point, c: Point, d: Point, t: f32) Point {
    const mt = 1.0 - t;
    return .{
        .x = mt * mt * mt * a.x + 3.0 * mt * mt * t * b.x + 3.0 * mt * t * t * c.x + t * t * t * d.x,
        .y = mt * mt * mt * a.y + 3.0 * mt * mt * t * b.y + 3.0 * mt * t * t * c.y + t * t * t * d.y,
    };
}

fn pointInside(lines: []const Line, point: Point) bool {
    var inside = false;
    for (lines) |line| {
        const ay = line.a.y;
        const by = line.b.y;
        if ((ay > point.y) == (by > point.y)) continue;
        const x_intersect = (line.b.x - line.a.x) * (point.y - ay) / (by - ay) + line.a.x;
        if (point.x < x_intersect) inside = !inside;
    }
    return inside;
}

fn parseSvgPaint(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8) !?SvgPaint {
    const view_box_text = attributeValue(document, "viewBox") orelse return null;
    const view_box = parseViewBox(view_box_text) orelse return null;
    const svg_tag_end = std.mem.indexOfScalar(u8, document, '>') orelse return null;
    const svg_tag = document[0..svg_tag_end];
    const document_context = SvgParseContext{
        .fill = svgAttributeOrStyle(svg_tag, "fill"),
        .stroke = svgAttributeOrStyle(svg_tag, "stroke"),
        .stroke_width = parseSvgLength(svgAttributeOrStyle(svg_tag, "stroke-width")),
        .color = parseSvgColor(svgAttributeOrStyle(svg_tag, "color") orelse "black") orelse .{ .red = 0, .green = 0, .blue = 0, .alpha = 255 },
        .alpha = parseSvgAlpha(svgAttributeOrStyle(svg_tag, "opacity")) orelse 1.0,
        .transform = parseSvgTransform(svgAttributeOrStyle(svg_tag, "transform")) orelse SvgTransform.identity,
        .gradients = &.{},
        .clips = &.{},
        .masks = &.{},
        .styles = &.{},
        .visible = true,
    };

    var paths = std.ArrayList(SvgPathPaint).empty;
    const gradients = try parseSvgLinearGradients(allocator, document);
    const clips = try parseSvgClipPaths(allocator, document);
    const masks = try parseSvgMasks(allocator, document);
    const styles = try parseSvgClassStyles(allocator, document);
    errdefer {
        for (paths.items) |*path| path.deinit();
        paths.deinit(allocator);
        allocator.free(gradients);
        allocator.free(clips);
        allocator.free(masks);
        allocator.free(styles);
    }
    var context = document_context;
    context.gradients = gradients;
    context.clips = clips;
    context.masks = masks;
    context.styles = styles;

    try parseSvgElementsOutsideGroups(allocator, glyph_id, document, context, view_box, &paths);
    try parseSvgGroups(allocator, glyph_id, document, context, view_box, &paths);
    try parseSvgUses(allocator, glyph_id, document, context, view_box, &paths);

    if (paths.items.len == 0) return null;
    return .{
        .view_box = view_box,
        .paths = try paths.toOwnedSlice(allocator),
        .gradients = gradients,
        .clips = clips,
        .masks = masks,
        .styles = styles,
        .allocator = allocator,
    };
}

const SvgParseContext = struct {
    fill: ?[]const u8,
    stroke: ?[]const u8,
    stroke_width: ?f32,
    color: font_mod.PaletteColor,
    alpha: f32,
    transform: SvgTransform,
    gradients: []const SvgGradientDef,
    clips: []const SvgClipDef,
    masks: []const SvgMaskDef,
    styles: []const SvgClassStyle,
    visible: bool,
};

const SvgStyleContext = struct {
    styles: []const SvgClassStyle,
};

fn parseSvgGroups(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, parent_context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<g")) |group_start| {
        if (isInsideDefs(document, group_start)) {
            search_start = group_start + 2;
            continue;
        }
        const group_tag_end = std.mem.indexOfPos(u8, document, group_start, ">") orelse return;
        const group_end = findSvgGroupEnd(document, group_tag_end + 1) orelse return;
        const group_tag = document[group_start..group_tag_end];
        const group_body = document[group_tag_end + 1 .. group_end];
        search_start = group_end + 4;

        const group_context = deriveSvgContext(parent_context, group_tag);
        try parseSvgElementsOutsideGroups(allocator, glyph_id, group_body, group_context, view_box, paths);
        try parseSvgGroups(allocator, glyph_id, group_body, group_context, view_box, paths);
    }
}

fn isInsideDefs(document: []const u8, offset: usize) bool {
    const defs_start = std.mem.lastIndexOf(u8, document[0..offset], "<defs") orelse return false;
    const defs_end = std.mem.lastIndexOf(u8, document[0..offset], "</defs>") orelse return true;
    return defs_start > defs_end;
}

fn parseSvgElementsOutsideGroups(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var cursor: usize = 0;
    while (nextSvgExcludedRange(document, cursor)) |range| {
        try parseSvgElements(allocator, glyph_id, document[cursor..range.start], context, view_box, paths);
        cursor = range.end;
    }
    try parseSvgElements(allocator, glyph_id, document[cursor..], context, view_box, paths);
}

const SvgRange = struct {
    start: usize,
    end: usize,
};

fn nextSvgExcludedRange(document: []const u8, cursor: usize) ?SvgRange {
    const group = std.mem.indexOfPos(u8, document, cursor, "<g");
    const defs = std.mem.indexOfPos(u8, document, cursor, "<defs");
    if (group == null and defs == null) return null;
    if (defs != null and (group == null or defs.? < group.?)) {
        const tag_end = std.mem.indexOfPos(u8, document, defs.?, ">") orelse return null;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</defs>") orelse return null;
        return .{ .start = defs.?, .end = close_start + "</defs>".len };
    }
    const group_start = group.?;
    const group_tag_end = std.mem.indexOfPos(u8, document, group_start, ">") orelse return null;
    const group_end = findSvgGroupEnd(document, group_tag_end + 1) orelse return null;
    return .{ .start = group_start, .end = group_end + 4 };
}

fn findSvgGroupEnd(document: []const u8, body_start: usize) ?usize {
    var cursor = body_start;
    var depth: usize = 1;
    while (cursor < document.len) {
        const next_open = std.mem.indexOfPos(u8, document, cursor, "<g");
        const next_close = std.mem.indexOfPos(u8, document, cursor, "</g>");
        if (next_close == null) return null;
        if (next_open != null and next_open.? < next_close.?) {
            const open_end = std.mem.indexOfPos(u8, document, next_open.?, ">") orelse return null;
            depth += 1;
            cursor = open_end + 1;
            continue;
        }
        depth -= 1;
        if (depth == 0) return next_close.?;
        cursor = next_close.? + 4;
    }
    return null;
}

fn parseSvgElements(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    if (!context.visible) return;
    try parseSvgPaths(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgRects(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgCircles(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgEllipses(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgLines(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgPolylines(allocator, glyph_id, document, context, view_box, paths);
    try parseSvgPolygons(allocator, glyph_id, document, context, view_box, paths);
}

fn parseSvgUses(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var cursor: usize = 0;
    while (nextSvgExcludedRange(document, cursor)) |range| {
        try parseSvgUsesInRange(allocator, glyph_id, document, document[cursor..range.start], context, view_box, paths);
        cursor = range.end;
    }
    try parseSvgUsesInRange(allocator, glyph_id, document, document[cursor..], context, view_box, paths);
}

fn parseSvgUsesInRange(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, full_document: []const u8, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<use")) |use_start| {
        const use_end = std.mem.indexOfPos(u8, document, use_start, ">") orelse return;
        const use_tag = document[use_start..use_end];
        search_start = use_end + 1;

        const href = svgAttribute(use_tag, context, "href") orelse svgAttribute(use_tag, context, "xlink:href") orelse continue;
        if (href.len == 0 or href[0] != '#') continue;
        const referenced = findSvgElementById(full_document, href[1..]) orelse continue;
        const x = parseSvgLength(attributeValue(use_tag, "x")) orelse 0;
        const y = parseSvgLength(attributeValue(use_tag, "y")) orelse 0;
        const use_transform = (SvgTransform{ .dx = x, .dy = y }).mul(parseElementTransform(use_tag, context));
        const use_context = SvgParseContext{
            .fill = svgAttribute(use_tag, context, "fill") orelse context.fill,
            .stroke = svgAttribute(use_tag, context, "stroke") orelse context.stroke,
            .stroke_width = parseSvgLength(svgAttribute(use_tag, context, "stroke-width")) orelse context.stroke_width,
            .color = parseSvgColorWithCurrentColor(svgAttribute(use_tag, context, "color") orelse "currentColor", context.color) orelse context.color,
            .alpha = context.alpha * (parseSvgAlpha(svgAttribute(use_tag, context, "opacity")) orelse 1.0),
            .transform = use_transform,
            .gradients = context.gradients,
            .clips = context.clips,
            .masks = context.masks,
            .styles = context.styles,
            .visible = context.visible and svgTagVisible(use_tag, context),
        };
        try parseSvgElements(allocator, glyph_id, referenced, use_context, view_box, paths);
        try parseSvgGroups(allocator, glyph_id, referenced, use_context, view_box, paths);
    }
}

fn parseSvgPaths(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<path")) |path_start| {
        const path_end = std.mem.indexOfPos(u8, document, path_start, ">") orelse return;
        const path_tag = document[path_start..path_end];
        search_start = path_end + 1;
        if (!svgTagVisible(path_tag, context)) continue;

        const path_text = attributeValue(path_tag, "d") orelse continue;
        const transform = parseElementTransform(path_tag, context);

        if (parseSvgPaintColor(path_tag, context)) |color| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            if (!try parseSvgPathData(&outline, path_text)) {
                outline.deinit();
                continue;
            }
            try paths.append(allocator, svgPathPaint(color, transform, path_tag, context, outline));
        }
        if (parseSvgStrokePaint(path_tag, context)) |stroke| {
            var source = initSvgOutline(allocator, glyph_id, view_box);
            defer source.deinit();
            if (!try parseSvgPathData(&source, path_text)) continue;

            var stroke_outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer stroke_outline.deinit();
            try appendSvgPathStroke(allocator, &stroke_outline, &source, stroke.width, stroke.linecap, stroke.linejoin, stroke.miterlimit, stroke.dash, stroke.dash_offset);
            if (stroke_outline.commands.items.len != 0) {
                try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, path_tag, context, stroke_outline));
            } else {
                stroke_outline.deinit();
            }
        }
    }
}

fn svgPathPaint(paint: SvgPaintStyle, transform: SvgTransform, tag_text: []const u8, context: SvgParseContext, outline: glyph_mod.GlyphOutline) SvgPathPaint {
    return .{
        .paint = paint,
        .transform = transform,
        .clip = parseSvgClipRef(svgAttribute(tag_text, context, "clip-path"), context),
        .mask = parseSvgMaskRef(svgAttribute(tag_text, context, "mask"), context),
        .outline = outline,
    };
}

fn parseSvgClipRef(value: ?[]const u8, context: SvgParseContext) ?SvgClipShape {
    const text = value orelse return null;
    const id = parseSvgPaintUrl(text) orelse return null;
    for (context.clips) |clip| {
        if (std.mem.eql(u8, clip.id, id)) return clip.shape;
    }
    return null;
}

fn parseSvgMaskRef(value: ?[]const u8, context: SvgParseContext) ?*const SvgMaskDef {
    const text = value orelse return null;
    const id = parseSvgPaintUrl(text) orelse return null;
    for (context.masks) |*mask| {
        if (std.mem.eql(u8, mask.id, id)) return mask;
    }
    return null;
}

fn findSvgElementById(document: []const u8, id: []const u8) ?[]const u8 {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "id=")) |id_pos| {
        const tag_start = std.mem.lastIndexOfScalar(u8, document[0..id_pos], '<') orelse return null;
        const tag_end = std.mem.indexOfScalarPos(u8, document, id_pos, '>') orelse return null;
        const tag = document[tag_start .. tag_end + 1];
        search_start = tag_end + 1;
        const value = attributeValue(tag, "id") orelse continue;
        if (std.mem.eql(u8, value, id)) {
            if (std.mem.startsWith(u8, tag, "<g")) {
                const group_end = findSvgGroupEnd(document, tag_end + 1) orelse return tag;
                return document[tag_start .. group_end + 4];
            }
            return tag;
        }
    }
    return null;
}

fn parseSvgRects(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<rect")) |rect_start| {
        const rect_end = std.mem.indexOfPos(u8, document, rect_start, ">") orelse return;
        const rect_tag = document[rect_start..rect_end];
        search_start = rect_end + 1;
        if (!svgTagVisible(rect_tag, context)) continue;

        const width = parseSvgLength(attributeValue(rect_tag, "width")) orelse continue;
        const height = parseSvgLength(attributeValue(rect_tag, "height")) orelse continue;
        if (width <= 0 or height <= 0) continue;
        const x = parseSvgLength(attributeValue(rect_tag, "x")) orelse 0;
        const y = parseSvgLength(attributeValue(rect_tag, "y")) orelse 0;
        const transform = parseElementTransform(rect_tag, context);

        if (parseSvgPaintColor(rect_tag, context)) |color| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgRect(&outline, x, y, width, height);
            try paths.append(allocator, svgPathPaint(color, transform, rect_tag, context, outline));
        }
        if (parseSvgStrokePaint(rect_tag, context)) |stroke| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgRectStroke(&outline, x, y, width, height, stroke.width);
            try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, rect_tag, context, outline));
        }
    }
}

fn parseSvgCircles(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<circle")) |circle_start| {
        const circle_end = std.mem.indexOfPos(u8, document, circle_start, ">") orelse return;
        const circle_tag = document[circle_start..circle_end];
        search_start = circle_end + 1;
        if (!svgTagVisible(circle_tag, context)) continue;

        const radius = parseSvgLength(attributeValue(circle_tag, "r")) orelse continue;
        if (radius <= 0) continue;
        const cx = parseSvgLength(attributeValue(circle_tag, "cx")) orelse 0;
        const cy = parseSvgLength(attributeValue(circle_tag, "cy")) orelse 0;
        const transform = parseElementTransform(circle_tag, context);

        if (parseSvgPaintColor(circle_tag, context)) |color| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgCircle(&outline, cx, cy, radius);
            try paths.append(allocator, svgPathPaint(color, transform, circle_tag, context, outline));
        }
        if (parseSvgStrokePaint(circle_tag, context)) |stroke| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgCircleStroke(&outline, cx, cy, radius, stroke.width);
            try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, circle_tag, context, outline));
        }
    }
}

fn parseSvgEllipses(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<ellipse")) |ellipse_start| {
        const ellipse_end = std.mem.indexOfPos(u8, document, ellipse_start, ">") orelse return;
        const ellipse_tag = document[ellipse_start..ellipse_end];
        search_start = ellipse_end + 1;
        if (!svgTagVisible(ellipse_tag, context)) continue;

        const rx = parseSvgLength(attributeValue(ellipse_tag, "rx")) orelse continue;
        const ry = parseSvgLength(attributeValue(ellipse_tag, "ry")) orelse continue;
        if (rx <= 0 or ry <= 0) continue;
        const cx = parseSvgLength(attributeValue(ellipse_tag, "cx")) orelse 0;
        const cy = parseSvgLength(attributeValue(ellipse_tag, "cy")) orelse 0;
        const transform = parseElementTransform(ellipse_tag, context);

        if (parseSvgPaintColor(ellipse_tag, context)) |color| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgEllipse(&outline, cx, cy, rx, ry);
            try paths.append(allocator, svgPathPaint(color, transform, ellipse_tag, context, outline));
        }
        if (parseSvgStrokePaint(ellipse_tag, context)) |stroke| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgEllipseStroke(&outline, cx, cy, rx, ry, stroke.width);
            try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, ellipse_tag, context, outline));
        }
    }
}

fn parseSvgLines(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<line")) |line_start| {
        const line_end = std.mem.indexOfPos(u8, document, line_start, ">") orelse return;
        const line_tag = document[line_start..line_end];
        search_start = line_end + 1;
        if (!svgTagVisible(line_tag, context)) continue;

        const x1 = parseSvgLength(attributeValue(line_tag, "x1")) orelse 0;
        const y1 = parseSvgLength(attributeValue(line_tag, "y1")) orelse 0;
        const x2 = parseSvgLength(attributeValue(line_tag, "x2")) orelse 0;
        const y2 = parseSvgLength(attributeValue(line_tag, "y2")) orelse 0;
        const transform = parseElementTransform(line_tag, context);
        const stroke = parseSvgStrokePaint(line_tag, context) orelse continue;

        var outline = initSvgOutline(allocator, glyph_id, view_box);
        errdefer outline.deinit();
        try appendMaybeDashedStrokeSegment(&outline, .{ .x = x1, .y = y1 }, .{ .x = x2, .y = y2 }, stroke.width, stroke.linecap, stroke.dash, stroke.dash_offset);
        if (outline.commands.items.len != 0) {
            try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, line_tag, context, outline));
        } else {
            outline.deinit();
        }
    }
}

fn parseSvgPolylines(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<polyline")) |polyline_start| {
        const polyline_end = std.mem.indexOfPos(u8, document, polyline_start, ">") orelse return;
        const polyline_tag = document[polyline_start..polyline_end];
        search_start = polyline_end + 1;
        if (!svgTagVisible(polyline_tag, context)) continue;

        const points_text = attributeValue(polyline_tag, "points") orelse continue;
        const transform = parseElementTransform(polyline_tag, context);
        const stroke = parseSvgStrokePaint(polyline_tag, context) orelse continue;

        var outline = initSvgOutline(allocator, glyph_id, view_box);
        errdefer outline.deinit();
        try appendSvgPolylineStroke(&outline, points_text, stroke.width, false, stroke.linecap, stroke.linejoin, stroke.miterlimit, stroke.dash, stroke.dash_offset);
        if (outline.commands.items.len != 0) {
            try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, polyline_tag, context, outline));
        } else {
            outline.deinit();
        }
    }
}

fn parseSvgPolygons(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, document: []const u8, context: SvgParseContext, view_box: ViewBox, paths: *std.ArrayList(SvgPathPaint)) !void {
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<polygon")) |polygon_start| {
        const polygon_end = std.mem.indexOfPos(u8, document, polygon_start, ">") orelse return;
        const polygon_tag = document[polygon_start..polygon_end];
        search_start = polygon_end + 1;
        if (!svgTagVisible(polygon_tag, context)) continue;

        const points_text = attributeValue(polygon_tag, "points") orelse continue;
        const transform = parseElementTransform(polygon_tag, context);

        if (parseSvgPaintColor(polygon_tag, context)) |color| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            if (try appendSvgPolygon(&outline, points_text)) {
                try paths.append(allocator, svgPathPaint(color, transform, polygon_tag, context, outline));
            } else {
                outline.deinit();
            }
        }
        if (parseSvgStrokePaint(polygon_tag, context)) |stroke| {
            var outline = initSvgOutline(allocator, glyph_id, view_box);
            errdefer outline.deinit();
            try appendSvgPolylineStroke(&outline, points_text, stroke.width, true, .butt, stroke.linejoin, stroke.miterlimit, stroke.dash, stroke.dash_offset);
            if (outline.commands.items.len != 0) {
                try paths.append(allocator, svgPathPaint(.{ .solid = stroke.color }, transform, polygon_tag, context, outline));
            } else {
                outline.deinit();
            }
        }
    }
}

fn deriveSvgContext(parent: SvgParseContext, tag_text: []const u8) SvgParseContext {
    return .{
        .fill = svgAttribute(tag_text, parent, "fill") orelse parent.fill,
        .stroke = svgAttribute(tag_text, parent, "stroke") orelse parent.stroke,
        .stroke_width = parseSvgLength(svgAttribute(tag_text, parent, "stroke-width")) orelse parent.stroke_width,
        .color = parseSvgColorWithCurrentColor(svgAttribute(tag_text, parent, "color") orelse "currentColor", parent.color) orelse parent.color,
        .alpha = parent.alpha * (parseSvgAlpha(svgAttribute(tag_text, parent, "opacity")) orelse 1.0),
        .transform = parent.transform.mul(parseSvgTransform(svgAttribute(tag_text, parent, "transform")) orelse SvgTransform.identity),
        .gradients = parent.gradients,
        .clips = parent.clips,
        .masks = parent.masks,
        .styles = parent.styles,
        .visible = parent.visible and svgTagVisible(tag_text, parent),
    };
}

fn parseElementTransform(tag_text: []const u8, context: SvgParseContext) SvgTransform {
    return context.transform.mul(parseSvgTransform(svgAttribute(tag_text, context, "transform")) orelse SvgTransform.identity);
}

fn initSvgOutline(allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, view_box: ViewBox) glyph_mod.GlyphOutline {
    return glyph_mod.GlyphOutline.init(allocator, glyph_id, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = @intFromFloat(@round(view_box.width)),
        .y_max = @intFromFloat(@round(view_box.height)),
    }, 0, 0);
}

fn appendSvgRect(outline: *glyph_mod.GlyphOutline, x: f32, y: f32, width: f32, height: f32) !void {
    const right = x + width;
    const bottom = y + height;
    try outline.commands.append(outline.allocator, .{ .move_to = .{ .x = x, .y = y } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = right, .y = y } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = right, .y = bottom } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = x, .y = bottom } });
    try outline.commands.append(outline.allocator, .close);
}

fn appendSvgRectStroke(outline: *glyph_mod.GlyphOutline, x: f32, y: f32, width: f32, height: f32, stroke_width: f32) !void {
    if (stroke_width <= 0) return;
    const half = stroke_width * 0.5;
    try appendSvgRect(outline, x - half, y - half, width + stroke_width, height + stroke_width);
    const inner_x = x + half;
    const inner_y = y + half;
    const inner_width = width - stroke_width;
    const inner_height = height - stroke_width;
    if (inner_width > 0 and inner_height > 0) {
        try appendSvgRect(outline, inner_x, inner_y, inner_width, inner_height);
    }
}

fn appendSvgCircle(outline: *glyph_mod.GlyphOutline, cx: f32, cy: f32, radius: f32) !void {
    return appendSvgEllipse(outline, cx, cy, radius, radius);
}

fn appendSvgEllipse(outline: *glyph_mod.GlyphOutline, cx: f32, cy: f32, rx: f32, ry: f32) !void {
    const k = 0.55228475;
    const control_x = rx * k;
    const control_y = ry * k;
    try outline.commands.append(outline.allocator, .{ .move_to = .{ .x = cx + rx, .y = cy } });
    try outline.commands.append(outline.allocator, .{ .cubic_to = .{
        .c0 = .{ .x = cx + rx, .y = cy + control_y },
        .c1 = .{ .x = cx + control_x, .y = cy + ry },
        .end = .{ .x = cx, .y = cy + ry },
    } });
    try outline.commands.append(outline.allocator, .{ .cubic_to = .{
        .c0 = .{ .x = cx - control_x, .y = cy + ry },
        .c1 = .{ .x = cx - rx, .y = cy + control_y },
        .end = .{ .x = cx - rx, .y = cy },
    } });
    try outline.commands.append(outline.allocator, .{ .cubic_to = .{
        .c0 = .{ .x = cx - rx, .y = cy - control_y },
        .c1 = .{ .x = cx - control_x, .y = cy - ry },
        .end = .{ .x = cx, .y = cy - ry },
    } });
    try outline.commands.append(outline.allocator, .{ .cubic_to = .{
        .c0 = .{ .x = cx + control_x, .y = cy - ry },
        .c1 = .{ .x = cx + rx, .y = cy - control_y },
        .end = .{ .x = cx + rx, .y = cy },
    } });
    try outline.commands.append(outline.allocator, .close);
}

fn appendSvgCircleStroke(outline: *glyph_mod.GlyphOutline, cx: f32, cy: f32, radius: f32, stroke_width: f32) !void {
    return appendSvgEllipseStroke(outline, cx, cy, radius, radius, stroke_width);
}

fn appendSvgEllipseStroke(outline: *glyph_mod.GlyphOutline, cx: f32, cy: f32, rx: f32, ry: f32, stroke_width: f32) !void {
    if (stroke_width <= 0) return;
    const half = stroke_width * 0.5;
    const outer_rx = rx + half;
    const outer_ry = ry + half;
    const inner_rx = rx - half;
    const inner_ry = ry - half;
    try appendSvgEllipse(outline, cx, cy, outer_rx, outer_ry);
    if (inner_rx > 0 and inner_ry > 0) try appendSvgEllipse(outline, cx, cy, inner_rx, inner_ry);
}

fn appendSvgPathStroke(allocator: std.mem.Allocator, outline: *glyph_mod.GlyphOutline, source: *const glyph_mod.GlyphOutline, stroke_width: f32, linecap: SvgLineCap, linejoin: SvgLineJoin, miterlimit: f32, dash: ?SvgDashArray, dash_offset: f32) !void {
    if (stroke_width <= 0) return;
    var lines = std.ArrayList(Line).empty;
    defer lines.deinit(allocator);
    try flattenOutlineToSvgLines(allocator, &lines, source);
    for (lines.items) |line| {
        try appendMaybeDashedStrokeSegment(outline, line.a, line.b, stroke_width, linecap, dash, dash_offset);
    }
    if (linejoin == .round) try appendRoundJoins(outline, lines.items, stroke_width);
    if (linejoin == .bevel) try appendBevelJoins(outline, lines.items, stroke_width);
    if (linejoin == .miter) try appendMiterJoins(outline, lines.items, stroke_width, miterlimit);
}

fn appendSvgPolygon(outline: *glyph_mod.GlyphOutline, points_text: []const u8) !bool {
    var scanner = NumberScanner.init(points_text);
    const first_x = scanner.next() orelse return false;
    const first_y = scanner.next() orelse return false;
    try outline.commands.append(outline.allocator, .{ .move_to = .{ .x = first_x, .y = first_y } });
    var count: usize = 1;
    while (true) {
        const x = scanner.next() orelse break;
        const y = scanner.next() orelse return false;
        try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = x, .y = y } });
        count += 1;
    }
    if (count < 3) return false;
    try outline.commands.append(outline.allocator, .close);
    return true;
}

fn appendSvgPolylineStroke(outline: *glyph_mod.GlyphOutline, points_text: []const u8, stroke_width: f32, close: bool, linecap: SvgLineCap, linejoin: SvgLineJoin, miterlimit: f32, dash: ?SvgDashArray, dash_offset: f32) !void {
    if (stroke_width <= 0) return;
    var scanner = NumberScanner.init(points_text);
    const first_x = scanner.next() orelse return;
    const first_y = scanner.next() orelse return;
    const first: Point = .{ .x = first_x, .y = first_y };
    var points: [16]Point = undefined;
    points[0] = first;
    var previous = first;
    var count: usize = 1;
    while (true) {
        const x = scanner.next() orelse break;
        const y = scanner.next() orelse return;
        const current: Point = .{ .x = x, .y = y };
        try appendMaybeDashedStrokeSegment(outline, previous, current, stroke_width, linecap, dash, dash_offset);
        if (count < points.len) points[count] = current;
        previous = current;
        count += 1;
    }
    if (close and count > 2) try appendMaybeDashedStrokeSegment(outline, previous, first, stroke_width, .butt, dash, dash_offset);
    if (linejoin == .round or linejoin == .bevel or linejoin == .miter) {
        const point_count = @min(count, points.len);
        for (1..point_count) |index| {
            if (index + 1 < point_count) {
                if (linejoin == .round) {
                    try appendSvgCircle(outline, points[index].x, points[index].y, stroke_width * 0.5);
                } else if (linejoin == .bevel) {
                    try appendBevelJoin(outline, points[index - 1], points[index], points[index + 1], stroke_width);
                } else {
                    try appendMiterJoin(outline, points[index - 1], points[index], points[index + 1], stroke_width, miterlimit);
                }
            }
        }
        if (close and point_count > 2) {
            if (linejoin == .round) {
                try appendSvgCircle(outline, points[0].x, points[0].y, stroke_width * 0.5);
                try appendSvgCircle(outline, points[point_count - 1].x, points[point_count - 1].y, stroke_width * 0.5);
            } else if (linejoin == .bevel) {
                try appendBevelJoin(outline, points[point_count - 1], points[0], points[1], stroke_width);
                try appendBevelJoin(outline, points[point_count - 2], points[point_count - 1], points[0], stroke_width);
            } else {
                try appendMiterJoin(outline, points[point_count - 1], points[0], points[1], stroke_width, miterlimit);
                try appendMiterJoin(outline, points[point_count - 2], points[point_count - 1], points[0], stroke_width, miterlimit);
            }
        }
    }
}

fn appendMaybeDashedStrokeSegment(outline: *glyph_mod.GlyphOutline, a: Point, b: Point, stroke_width: f32, linecap: SvgLineCap, dash: ?SvgDashArray, dash_offset: f32) !void {
    const dash_array = dash orelse {
        try appendStrokeSegment(outline, a, b, stroke_width, linecap);
        return;
    };
    if (dash_array.len == 0) {
        try appendStrokeSegment(outline, a, b, stroke_width, linecap);
        return;
    }

    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len <= 0.0001) return;
    const ux = dx / len;
    const uy = dy / len;
    const phase = dashPhase(dash_array, dash_offset);
    var distance: f32 = -phase.distance;
    var dash_index = phase.index;
    var draw = dash_index % 2 == 0;
    while (distance < len) {
        const dash_len = dash_array.values[dash_index % dash_array.len];
        const next_distance = @min(len, distance + dash_len);
        if (draw and next_distance > distance) {
            const draw_start = @max(0.0, distance);
            const start = Point{ .x = a.x + ux * draw_start, .y = a.y + uy * draw_start };
            const end = Point{ .x = a.x + ux * next_distance, .y = a.y + uy * next_distance };
            try appendStrokeSegment(outline, start, end, stroke_width, linecap);
        }
        distance = next_distance;
        dash_index += 1;
        draw = !draw;
        if (dash_len <= 0) break;
    }
}

fn appendRoundJoins(outline: *glyph_mod.GlyphOutline, lines: []const Line, stroke_width: f32) !void {
    if (lines.len < 2) return;
    const radius = stroke_width * 0.5;
    for (lines[0 .. lines.len - 1], lines[1..]) |a, b| {
        if (@abs(a.b.x - b.a.x) < 0.001 and @abs(a.b.y - b.a.y) < 0.001) {
            try appendSvgCircle(outline, a.b.x, a.b.y, radius);
        }
    }
}

fn appendBevelJoins(outline: *glyph_mod.GlyphOutline, lines: []const Line, stroke_width: f32) !void {
    if (lines.len < 2) return;
    for (lines[0 .. lines.len - 1], lines[1..]) |a, b| {
        if (@abs(a.b.x - b.a.x) < 0.001 and @abs(a.b.y - b.a.y) < 0.001) {
            try appendBevelJoin(outline, a.a, a.b, b.b, stroke_width);
        }
    }
}

fn appendMiterJoins(outline: *glyph_mod.GlyphOutline, lines: []const Line, stroke_width: f32, miterlimit: f32) !void {
    if (lines.len < 2) return;
    for (lines[0 .. lines.len - 1], lines[1..]) |a, b| {
        if (@abs(a.b.x - b.a.x) < 0.001 and @abs(a.b.y - b.a.y) < 0.001) {
            try appendMiterJoin(outline, a.a, a.b, b.b, stroke_width, miterlimit);
        }
    }
}

fn appendMiterJoin(outline: *glyph_mod.GlyphOutline, before: Point, joint: Point, after: Point, stroke_width: f32, miterlimit: f32) !void {
    const prev_vec = normalizePoint(.{ .x = joint.x - before.x, .y = joint.y - before.y }) orelse return;
    const next_vec = normalizePoint(.{ .x = after.x - joint.x, .y = after.y - joint.y }) orelse return;
    const half = stroke_width * 0.5;
    const cross = prev_vec.x * next_vec.y - prev_vec.y * next_vec.x;
    const sign: f32 = if (cross >= 0) 1.0 else -1.0;
    const prev_outer = Point{ .x = joint.x - prev_vec.y * half * sign, .y = joint.y + prev_vec.x * half * sign };
    const next_outer = Point{ .x = joint.x - next_vec.y * half * sign, .y = joint.y + next_vec.x * half * sign };
    const miter = lineIntersection(prev_outer, prev_vec, next_outer, next_vec) orelse {
        try appendBevelJoin(outline, before, joint, after, stroke_width);
        return;
    };
    const mx = miter.x - joint.x;
    const my = miter.y - joint.y;
    const miter_len = @sqrt(mx * mx + my * my);
    if (miter_len > @max(1.0, miterlimit) * half) {
        try appendBevelJoin(outline, before, joint, after, stroke_width);
        return;
    }
    try outline.commands.append(outline.allocator, .{ .move_to = joint });
    try outline.commands.append(outline.allocator, .{ .line_to = prev_outer });
    try outline.commands.append(outline.allocator, .{ .line_to = miter });
    try outline.commands.append(outline.allocator, .{ .line_to = next_outer });
    try outline.commands.append(outline.allocator, .close);
}

fn appendBevelJoin(outline: *glyph_mod.GlyphOutline, before: Point, joint: Point, after: Point, stroke_width: f32) !void {
    const prev_vec = normalizePoint(.{ .x = joint.x - before.x, .y = joint.y - before.y }) orelse return;
    const next_vec = normalizePoint(.{ .x = after.x - joint.x, .y = after.y - joint.y }) orelse return;
    const half = stroke_width * 0.5;
    const cross = prev_vec.x * next_vec.y - prev_vec.y * next_vec.x;
    const sign: f32 = if (cross >= 0) 1.0 else -1.0;
    const prev_outer = Point{ .x = joint.x - prev_vec.y * half * sign, .y = joint.y + prev_vec.x * half * sign };
    const next_outer = Point{ .x = joint.x - next_vec.y * half * sign, .y = joint.y + next_vec.x * half * sign };
    try outline.commands.append(outline.allocator, .{ .move_to = joint });
    try outline.commands.append(outline.allocator, .{ .line_to = prev_outer });
    try outline.commands.append(outline.allocator, .{ .line_to = next_outer });
    try outline.commands.append(outline.allocator, .close);
}

fn lineIntersection(a: Point, da: Point, b: Point, db: Point) ?Point {
    const denom = da.x * db.y - da.y * db.x;
    if (@abs(denom) <= 0.000001) return null;
    const bx = b.x - a.x;
    const by = b.y - a.y;
    const t = (bx * db.y - by * db.x) / denom;
    return .{ .x = a.x + da.x * t, .y = a.y + da.y * t };
}

fn normalizePoint(point: Point) ?Point {
    const len = @sqrt(point.x * point.x + point.y * point.y);
    if (len <= 0.0001) return null;
    return .{ .x = point.x / len, .y = point.y / len };
}

fn dashPhase(dash: SvgDashArray, offset: f32) struct { index: usize, distance: f32 } {
    var total: f32 = 0;
    for (dash.values[0..dash.len]) |value| total += value;
    if (total <= 0) return .{ .index = 0, .distance = 0 };
    var remaining = offset - @floor(offset / total) * total;
    var index: usize = 0;
    while (index < dash.len) : (index += 1) {
        const value = dash.values[index];
        if (remaining < value) return .{ .index = index, .distance = remaining };
        remaining -= value;
    }
    return .{ .index = 0, .distance = 0 };
}

fn flattenOutlineToSvgLines(allocator: std.mem.Allocator, lines: *std.ArrayList(Line), outline: *const glyph_mod.GlyphOutline) !void {
    var start: ?Point = null;
    var current: ?Point = null;
    for (outline.commands.items) |command| {
        switch (command) {
            .move_to => |point| {
                start = point;
                current = point;
            },
            .line_to => |point| {
                const from = current orelse continue;
                try lines.append(allocator, .{ .a = from, .b = point });
                current = point;
            },
            .quad_to => |quad| {
                const from = current orelse continue;
                var prev = from;
                for (1..17) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 16.0;
                    const point = quadPoint(from, quad.control, quad.end, t);
                    try lines.append(allocator, .{ .a = prev, .b = point });
                    prev = point;
                }
                current = quad.end;
            },
            .cubic_to => |cubic| {
                const from = current orelse continue;
                var prev = from;
                for (1..25) |i| {
                    const t = @as(f32, @floatFromInt(i)) / 24.0;
                    const point = cubicPoint(from, cubic.c0, cubic.c1, cubic.end, t);
                    try lines.append(allocator, .{ .a = prev, .b = point });
                    prev = point;
                }
                current = cubic.end;
            },
            .close => {
                if (current) |from| {
                    if (start) |to| {
                        try lines.append(allocator, .{ .a = from, .b = to });
                    }
                }
                current = start;
            },
        }
    }
}

fn appendStrokeSegment(outline: *glyph_mod.GlyphOutline, a: Point, b: Point, stroke_width: f32, linecap: SvgLineCap) !void {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len <= 0.0001) return;
    const half = stroke_width * 0.5;
    const ux = dx / len;
    const uy = dy / len;
    const nx = -uy * half;
    const ny = ux * half;
    const extend = if (linecap == .square) half else 0.0;
    const start = Point{ .x = a.x - ux * extend, .y = a.y - uy * extend };
    const end = Point{ .x = b.x + ux * extend, .y = b.y + uy * extend };
    try outline.commands.append(outline.allocator, .{ .move_to = .{ .x = start.x + nx, .y = start.y + ny } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = end.x + nx, .y = end.y + ny } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = end.x - nx, .y = end.y - ny } });
    try outline.commands.append(outline.allocator, .{ .line_to = .{ .x = start.x - nx, .y = start.y - ny } });
    try outline.commands.append(outline.allocator, .close);
    if (linecap == .round) {
        try appendSvgCircle(outline, a.x, a.y, half);
        try appendSvgCircle(outline, b.x, b.y, half);
    }
}

fn attributeValue(text: []const u8, name: []const u8) ?[]const u8 {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, text, offset, name)) |name_start| {
        const after_name = name_start + name.len;
        if (name_start > 0 and isNameByte(text[name_start - 1])) {
            offset = after_name;
            continue;
        }
        var cursor = skipAsciiSpaces(text, after_name);
        if (cursor >= text.len or text[cursor] != '=') {
            offset = after_name;
            continue;
        }
        cursor = skipAsciiSpaces(text, cursor + 1);
        if (cursor >= text.len or (text[cursor] != '"' and text[cursor] != '\'')) return null;
        const quote = text[cursor];
        const value_start = cursor + 1;
        const value_end = std.mem.indexOfScalarPos(u8, text, value_start, quote) orelse return null;
        return text[value_start..value_end];
    }
    return null;
}

fn svgAttributeOrStyle(tag_text: []const u8, name: []const u8) ?[]const u8 {
    if (attributeValue(tag_text, name)) |value| return value;
    return svgStyleProperty(tag_text, name);
}

fn svgAttribute(tag_text: []const u8, context: anytype, name: []const u8) ?[]const u8 {
    if (attributeValue(tag_text, name)) |value| return value;
    if (svgStyleProperty(tag_text, name)) |value| return value;
    return svgClassStyleProperty(tag_text, context.styles, name);
}

fn svgStyleProperty(tag_text: []const u8, name: []const u8) ?[]const u8 {
    const style = attributeValue(tag_text, "style") orelse return null;
    return svgDeclarationProperty(style, name);
}

fn svgClassStyleProperty(tag_text: []const u8, styles: []const SvgClassStyle, name: []const u8) ?[]const u8 {
    var best_value: ?[]const u8 = null;
    var best_specificity: u8 = 0;
    if (attributeValue(tag_text, "id")) |id| {
        for (styles) |style| {
            if (style.selector == .id and std.mem.eql(u8, style.name, id)) {
                if (svgDeclarationProperty(style.declarations, name)) |value| {
                    best_value = value;
                    best_specificity = 3;
                }
            }
        }
    }
    if (attributeValue(tag_text, "class")) |classes| {
        var cursor: usize = 0;
        while (cursor < classes.len) {
            cursor = skipAsciiSpaces(classes, cursor);
            if (cursor >= classes.len) break;
            const start = cursor;
            while (cursor < classes.len and !std.ascii.isWhitespace(classes[cursor])) : (cursor += 1) {}
            const class_name = classes[start..cursor];
            for (styles) |style| {
                if (style.selector == .class and std.mem.eql(u8, style.name, class_name)) {
                    if (svgDeclarationProperty(style.declarations, name)) |value| {
                        if (best_specificity <= 2) {
                            best_value = value;
                            best_specificity = 2;
                        }
                    }
                }
            }
        }
    }
    if (svgElementName(tag_text)) |element_name| {
        for (styles) |style| {
            if (style.selector == .element and std.mem.eql(u8, style.name, element_name)) {
                if (svgDeclarationProperty(style.declarations, name)) |value| {
                    if (best_specificity <= 1) {
                        best_value = value;
                        best_specificity = 1;
                    }
                }
            }
        }
    }
    return best_value;
}

fn svgElementName(tag_text: []const u8) ?[]const u8 {
    if (tag_text.len < 2 or tag_text[0] != '<') return null;
    var cursor: usize = 1;
    if (cursor < tag_text.len and tag_text[cursor] == '/') cursor += 1;
    const start = cursor;
    while (cursor < tag_text.len and (std.ascii.isAlphanumeric(tag_text[cursor]) or tag_text[cursor] == '_' or tag_text[cursor] == '-' or tag_text[cursor] == ':')) : (cursor += 1) {}
    return if (cursor > start) tag_text[start..cursor] else null;
}

fn svgDeclarationProperty(declarations: []const u8, name: []const u8) ?[]const u8 {
    var cursor: usize = 0;
    while (cursor < declarations.len) {
        const declaration_end = std.mem.indexOfScalarPos(u8, declarations, cursor, ';') orelse declarations.len;
        const declaration = std.mem.trim(u8, declarations[cursor..declaration_end], " \t\r\n");
        if (std.mem.indexOfScalar(u8, declaration, ':')) |colon| {
            const key = std.mem.trim(u8, declaration[0..colon], " \t\r\n");
            const value = std.mem.trim(u8, declaration[colon + 1 ..], " \t\r\n");
            if (std.mem.eql(u8, key, name)) return value;
        }
        cursor = declaration_end + @intFromBool(declaration_end < declarations.len);
    }
    return null;
}

fn svgTagVisible(tag_text: []const u8, context: SvgParseContext) bool {
    if (svgAttribute(tag_text, context, "display")) |display| {
        if (std.mem.eql(u8, display, "none")) return false;
    }
    if (svgAttribute(tag_text, context, "visibility")) |visibility| {
        if (std.mem.eql(u8, visibility, "hidden") or std.mem.eql(u8, visibility, "collapse")) return false;
    }
    return true;
}

fn parseViewBox(text: []const u8) ?ViewBox {
    var scanner = NumberScanner.init(text);
    const min_x = scanner.next() orelse return null;
    const min_y = scanner.next() orelse return null;
    const width = scanner.next() orelse return null;
    const height = scanner.next() orelse return null;
    return .{ .min_x = min_x, .min_y = min_y, .width = width, .height = height };
}

fn parseSvgPathData(outline: *glyph_mod.GlyphOutline, text: []const u8) !bool {
    var scanner = PathScanner.init(text);
    var current: Point = .{ .x = 0, .y = 0 };
    var start: Point = current;
    var last_quad_control: ?Point = null;
    var last_cubic_control: ?Point = null;
    var command: u8 = 0;
    var saw_command = false;
    while (true) {
        scanner.skipSeparators();
        if (scanner.done()) break;
        if (scanner.peekCommand()) |next_command| {
            command = next_command;
            _ = scanner.readByte();
            saw_command = true;
        } else if (!saw_command) {
            return false;
        }
        switch (command) {
            'M', 'm' => {
                const relative = command == 'm';
                const x = scanner.nextNumber() orelse return scanner.done();
                const y = scanner.nextNumber() orelse return false;
                current = applyPathPoint(current, relative, x, y);
                start = current;
                try outline.commands.append(outline.allocator, .{ .move_to = current });
                command = if (relative) 'l' else 'L';
                last_quad_control = null;
                last_cubic_control = null;
            },
            'L', 'l' => {
                const relative = command == 'l';
                const x = scanner.nextNumber() orelse return scanner.done();
                const y = scanner.nextNumber() orelse return false;
                current = applyPathPoint(current, relative, x, y);
                try outline.commands.append(outline.allocator, .{ .line_to = current });
                last_quad_control = null;
                last_cubic_control = null;
            },
            'H', 'h' => {
                const relative = command == 'h';
                const x_value = scanner.nextNumber() orelse return scanner.done();
                current.x = if (relative) current.x + x_value else x_value;
                try outline.commands.append(outline.allocator, .{ .line_to = current });
                last_quad_control = null;
                last_cubic_control = null;
            },
            'V', 'v' => {
                const relative = command == 'v';
                const y_value = scanner.nextNumber() orelse return scanner.done();
                current.y = if (relative) current.y + y_value else y_value;
                try outline.commands.append(outline.allocator, .{ .line_to = current });
                last_quad_control = null;
                last_cubic_control = null;
            },
            'Q', 'q' => {
                const relative = command == 'q';
                const control_x = scanner.nextNumber() orelse return scanner.done();
                const control_y = scanner.nextNumber() orelse return false;
                const end_x = scanner.nextNumber() orelse return scanner.done();
                const end_y = scanner.nextNumber() orelse return false;
                const control = applyPathPoint(current, relative, control_x, control_y);
                current = applyPathPoint(current, relative, end_x, end_y);
                try outline.commands.append(outline.allocator, .{ .quad_to = .{ .control = control, .end = current } });
                last_quad_control = control;
                last_cubic_control = null;
            },
            'T', 't' => {
                const relative = command == 't';
                const end_x = scanner.nextNumber() orelse return false;
                const end_y = scanner.nextNumber() orelse return false;
                const control = if (last_quad_control) |previous|
                    reflectPoint(current, previous)
                else
                    current;
                current = applyPathPoint(current, relative, end_x, end_y);
                try outline.commands.append(outline.allocator, .{ .quad_to = .{ .control = control, .end = current } });
                last_quad_control = control;
                last_cubic_control = null;
            },
            'C', 'c' => {
                const relative = command == 'c';
                const c0_x = scanner.nextNumber() orelse return scanner.done();
                const c0_y = scanner.nextNumber() orelse return false;
                const c1_x = scanner.nextNumber() orelse return scanner.done();
                const c1_y = scanner.nextNumber() orelse return false;
                const end_x = scanner.nextNumber() orelse return false;
                const end_y = scanner.nextNumber() orelse return false;
                const c0 = applyPathPoint(current, relative, c0_x, c0_y);
                const c1 = applyPathPoint(current, relative, c1_x, c1_y);
                current = applyPathPoint(current, relative, end_x, end_y);
                try outline.commands.append(outline.allocator, .{ .cubic_to = .{ .c0 = c0, .c1 = c1, .end = current } });
                last_quad_control = null;
                last_cubic_control = c1;
            },
            'S', 's' => {
                const relative = command == 's';
                const c1_x = scanner.nextNumber() orelse return false;
                const c1_y = scanner.nextNumber() orelse return false;
                const end_x = scanner.nextNumber() orelse return false;
                const end_y = scanner.nextNumber() orelse return false;
                const c0 = if (last_cubic_control) |previous|
                    reflectPoint(current, previous)
                else
                    current;
                const c1 = applyPathPoint(current, relative, c1_x, c1_y);
                current = applyPathPoint(current, relative, end_x, end_y);
                try outline.commands.append(outline.allocator, .{ .cubic_to = .{ .c0 = c0, .c1 = c1, .end = current } });
                last_quad_control = null;
                last_cubic_control = c1;
            },
            'A', 'a' => {
                const relative = command == 'a';
                const rx = scanner.nextNumber() orelse return scanner.done();
                const ry = scanner.nextNumber() orelse return false;
                const x_axis_rotation = scanner.nextNumber() orelse return false;
                const large_arc_flag = scanner.nextNumber() orelse return false;
                const sweep_flag = scanner.nextNumber() orelse return false;
                const end_x = scanner.nextNumber() orelse return false;
                const end_y = scanner.nextNumber() orelse return false;
                const end = applyPathPoint(current, relative, end_x, end_y);
                try appendSvgArc(outline, current, rx, ry, x_axis_rotation, large_arc_flag != 0, sweep_flag != 0, end);
                current = end;
                last_quad_control = null;
                last_cubic_control = null;
            },
            'Z', 'z' => {
                current = start;
                try outline.commands.append(outline.allocator, .close);
                saw_command = false;
                last_quad_control = null;
                last_cubic_control = null;
            },
            else => return false,
        }
    }
    return outline.commands.items.len != 0;
}

fn applyPathPoint(current: Point, relative: bool, x: f32, y: f32) Point {
    if (relative) return .{ .x = current.x + x, .y = current.y + y };
    return .{ .x = x, .y = y };
}

fn reflectPoint(origin: Point, point: Point) Point {
    return .{ .x = origin.x * 2 - point.x, .y = origin.y * 2 - point.y };
}

fn appendSvgArc(outline: *glyph_mod.GlyphOutline, start: Point, rx_value: f32, ry_value: f32, x_axis_rotation: f32, large_arc: bool, sweep: bool, end: Point) !void {
    var rx = @abs(rx_value);
    var ry = @abs(ry_value);
    if (rx == 0 or ry == 0 or (@abs(start.x - end.x) < 0.0001 and @abs(start.y - end.y) < 0.0001)) {
        try outline.commands.append(outline.allocator, .{ .line_to = end });
        return;
    }

    const phi = x_axis_rotation * std.math.pi / 180.0;
    const cos_phi = @cos(phi);
    const sin_phi = @sin(phi);
    const dx2 = (start.x - end.x) * 0.5;
    const dy2 = (start.y - end.y) * 0.5;
    const x1p = cos_phi * dx2 + sin_phi * dy2;
    const y1p = -sin_phi * dx2 + cos_phi * dy2;

    const radii_check = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
    if (radii_check > 1.0) {
        const scale = @sqrt(radii_check);
        rx *= scale;
        ry *= scale;
    }

    const rx2 = rx * rx;
    const ry2 = ry * ry;
    const x1p2 = x1p * x1p;
    const y1p2 = y1p * y1p;
    const numerator = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2;
    const denominator = rx2 * y1p2 + ry2 * x1p2;
    const factor_sign: f32 = if (large_arc == sweep) -1.0 else 1.0;
    const factor = factor_sign * @sqrt(@max(0.0, numerator / denominator));
    const cxp = factor * rx * y1p / ry;
    const cyp = factor * -ry * x1p / rx;
    const cx = cos_phi * cxp - sin_phi * cyp + (start.x + end.x) * 0.5;
    const cy = sin_phi * cxp + cos_phi * cyp + (start.y + end.y) * 0.5;

    const start_angle = std.math.atan2((y1p - cyp) / ry, (x1p - cxp) / rx);
    var delta = std.math.atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - start_angle;
    if (sweep and delta < 0) delta += std.math.tau;
    if (!sweep and delta > 0) delta -= std.math.tau;

    const segments_float = @ceil(@abs(delta) / (std.math.pi / 8.0));
    const segments: usize = @max(1, @as(usize, @intFromFloat(segments_float)));
    for (1..segments + 1) |index| {
        const t = @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(segments));
        const theta = start_angle + delta * t;
        const xp = rx * @cos(theta);
        const yp = ry * @sin(theta);
        try outline.commands.append(outline.allocator, .{ .line_to = .{
            .x = cos_phi * xp - sin_phi * yp + cx,
            .y = sin_phi * xp + cos_phi * yp + cy,
        } });
    }
}

fn parseSvgColor(text: []const u8) ?font_mod.PaletteColor {
    if (std.mem.eql(u8, text, "none")) return null;
    if (std.mem.eql(u8, text, "black")) return .{ .red = 0, .green = 0, .blue = 0, .alpha = 255 };
    if (std.mem.eql(u8, text, "white")) return .{ .red = 255, .green = 255, .blue = 255, .alpha = 255 };
    if (std.mem.eql(u8, text, "red")) return .{ .red = 255, .green = 0, .blue = 0, .alpha = 255 };
    if (std.mem.eql(u8, text, "green")) return .{ .red = 0, .green = 128, .blue = 0, .alpha = 255 };
    if (std.mem.eql(u8, text, "blue")) return .{ .red = 0, .green = 0, .blue = 255, .alpha = 255 };
    if (std.mem.eql(u8, text, "yellow")) return .{ .red = 255, .green = 255, .blue = 0, .alpha = 255 };
    if (std.mem.eql(u8, text, "cyan") or std.mem.eql(u8, text, "aqua")) return .{ .red = 0, .green = 255, .blue = 255, .alpha = 255 };
    if (std.mem.eql(u8, text, "magenta") or std.mem.eql(u8, text, "fuchsia")) return .{ .red = 255, .green = 0, .blue = 255, .alpha = 255 };
    if (std.mem.eql(u8, text, "gray") or std.mem.eql(u8, text, "grey")) return .{ .red = 128, .green = 128, .blue = 128, .alpha = 255 };
    if (std.mem.eql(u8, text, "transparent")) return .{ .red = 0, .green = 0, .blue = 0, .alpha = 0 };
    if (text.len == 7 and text[0] == '#') {
        return .{
            .red = parseHexByte(text[1..3]) orelse return null,
            .green = parseHexByte(text[3..5]) orelse return null,
            .blue = parseHexByte(text[5..7]) orelse return null,
            .alpha = 255,
        };
    }
    if (text.len == 4 and text[0] == '#') {
        return .{
            .red = parseHexNibble(text[1]) orelse return null,
            .green = parseHexNibble(text[2]) orelse return null,
            .blue = parseHexNibble(text[3]) orelse return null,
            .alpha = 255,
        };
    }
    if (std.mem.startsWith(u8, text, "rgb(") and std.mem.endsWith(u8, text, ")")) {
        var scanner = ColorFunctionScanner.init(text[4 .. text.len - 1]);
        const red = scanner.nextComponent() orelse return null;
        const green = scanner.nextComponent() orelse return null;
        const blue = scanner.nextComponent() orelse return null;
        return .{
            .red = red,
            .green = green,
            .blue = blue,
            .alpha = 255,
        };
    }
    if (std.mem.startsWith(u8, text, "rgba(") and std.mem.endsWith(u8, text, ")")) {
        var scanner = ColorFunctionScanner.init(text[5 .. text.len - 1]);
        const red = scanner.nextComponent() orelse return null;
        const green = scanner.nextComponent() orelse return null;
        const blue = scanner.nextComponent() orelse return null;
        const alpha = scanner.nextAlpha() orelse return null;
        return .{
            .red = red,
            .green = green,
            .blue = blue,
            .alpha = alpha,
        };
    }
    if (std.mem.startsWith(u8, text, "hsl(") and std.mem.endsWith(u8, text, ")")) {
        var scanner = ColorFunctionScanner.init(text[4 .. text.len - 1]);
        const hue = scanner.nextRawNumber() orelse return null;
        const saturation = scanner.nextUnitInterval() orelse return null;
        const lightness = scanner.nextUnitInterval() orelse return null;
        var color = hslToRgb(hue, saturation, lightness);
        color.alpha = 255;
        return color;
    }
    if (std.mem.startsWith(u8, text, "hsla(") and std.mem.endsWith(u8, text, ")")) {
        var scanner = ColorFunctionScanner.init(text[5 .. text.len - 1]);
        const hue = scanner.nextRawNumber() orelse return null;
        const saturation = scanner.nextUnitInterval() orelse return null;
        const lightness = scanner.nextUnitInterval() orelse return null;
        const alpha = scanner.nextAlpha() orelse return null;
        var color = hslToRgb(hue, saturation, lightness);
        color.alpha = alpha;
        return color;
    }
    return null;
}

fn parseSvgColorWithCurrentColor(text: []const u8, current_color: font_mod.PaletteColor) ?font_mod.PaletteColor {
    if (std.mem.eql(u8, text, "currentColor")) return current_color;
    return parseSvgColor(text);
}

fn parseSvgPaintColor(tag_text: []const u8, context: SvgParseContext) ?SvgPaintStyle {
    const fill_text = svgAttribute(tag_text, context, "fill") orelse context.fill orelse "black";
    const fill_alpha = parseSvgAlpha(svgAttribute(tag_text, context, "fill-opacity")) orelse 1.0;
    const element_alpha = parseSvgAlpha(svgAttribute(tag_text, context, "opacity")) orelse 1.0;
    const alpha = @max(0.0, @min(1.0, context.alpha * element_alpha * fill_alpha));
    if (parseSvgPaintUrl(fill_text)) |id| {
        if (findSvgGradient(context.gradients, id)) |paint| {
            return applyAlphaToPaint(paint, alpha);
        }
        return null;
    }
    var color = parseSvgColorWithCurrentColor(fill_text, context.color) orelse return null;
    color.alpha = scaledAlpha(color.alpha, alpha);
    return .{ .solid = color };
}

fn parseSvgStrokePaint(tag_text: []const u8, context: SvgParseContext) ?SvgStrokePaint {
    const stroke_text = svgAttribute(tag_text, context, "stroke") orelse context.stroke orelse return null;
    var color = parseSvgColorWithCurrentColor(stroke_text, context.color) orelse return null;
    const stroke_width = parseSvgLength(svgAttribute(tag_text, context, "stroke-width")) orelse context.stroke_width orelse 1.0;
    if (stroke_width <= 0) return null;
    const stroke_alpha = parseSvgAlpha(svgAttribute(tag_text, context, "stroke-opacity")) orelse 1.0;
    const element_alpha = parseSvgAlpha(svgAttribute(tag_text, context, "opacity")) orelse 1.0;
    const alpha = @max(0.0, @min(1.0, context.alpha * element_alpha * stroke_alpha));
    color.alpha = @intFromFloat(@round(@as(f32, @floatFromInt(color.alpha)) * alpha));
    return .{
        .color = color,
        .width = stroke_width,
        .linecap = parseSvgLineCap(svgAttribute(tag_text, context, "stroke-linecap")),
        .linejoin = parseSvgLineJoin(svgAttribute(tag_text, context, "stroke-linejoin")),
        .miterlimit = parseSvgLength(svgAttribute(tag_text, context, "stroke-miterlimit")) orelse 4,
        .dash = parseSvgDashArray(svgAttribute(tag_text, context, "stroke-dasharray")),
        .dash_offset = parseSvgLength(svgAttribute(tag_text, context, "stroke-dashoffset")) orelse 0,
    };
}

fn parseSvgLineCap(value: ?[]const u8) SvgLineCap {
    const text = value orelse return .butt;
    if (std.mem.eql(u8, text, "round")) return .round;
    if (std.mem.eql(u8, text, "square")) return .square;
    return .butt;
}

fn parseSvgLineJoin(value: ?[]const u8) SvgLineJoin {
    const text = value orelse return .miter;
    if (std.mem.eql(u8, text, "round")) return .round;
    if (std.mem.eql(u8, text, "bevel")) return .bevel;
    return .miter;
}

fn parseSvgDashArray(value: ?[]const u8) ?SvgDashArray {
    const text = value orelse return null;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "none")) return null;
    var scanner = NumberScanner.init(trimmed);
    var result = SvgDashArray{};
    while (result.len < result.values.len) {
        const dash = scanner.next() orelse break;
        if (dash < 0) return null;
        result.values[result.len] = dash;
        result.len += 1;
    }
    if (result.len == 0) return null;
    if (result.len % 2 == 1 and result.len * 2 <= result.values.len) {
        const original_len = result.len;
        for (0..original_len) |index| {
            result.values[result.len] = result.values[index];
            result.len += 1;
        }
    }
    return result;
}

fn scaledAlpha(base_alpha: u8, alpha: f32) u8 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(base_alpha)) * @max(0.0, @min(1.0, alpha))));
}

fn applyAlphaToPaint(paint: SvgPaintStyle, alpha: f32) SvgPaintStyle {
    return switch (paint) {
        .solid => |color| blk: {
            var result = color;
            result.alpha = scaledAlpha(result.alpha, alpha);
            break :blk .{ .solid = result };
        },
        .linear_gradient => |gradient| blk: {
            var result = gradient;
            applyAlphaToGradientStops(&result.stops, alpha);
            break :blk .{ .linear_gradient = result };
        },
        .radial_gradient => |gradient| blk: {
            var result = gradient;
            applyAlphaToGradientStops(&result.stops, alpha);
            break :blk .{ .radial_gradient = result };
        },
    };
}

fn applyAlphaToGradientStops(stops: *SvgGradientStops, alpha: f32) void {
    for (stops.items[0..stops.len]) |*stop| {
        stop.color.alpha = scaledAlpha(stop.color.alpha, alpha);
    }
}

fn parseSvgPaintUrl(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, "url(") or !std.mem.endsWith(u8, trimmed, ")")) return null;
    var inner = std.mem.trim(u8, trimmed[4 .. trimmed.len - 1], " \t\r\n'\"");
    if (inner.len == 0 or inner[0] != '#') return null;
    inner = inner[1..];
    return if (inner.len == 0) null else inner;
}

fn findSvgGradient(gradients: []const SvgGradientDef, id: []const u8) ?SvgPaintStyle {
    for (gradients) |entry| {
        if (std.mem.eql(u8, entry.id, id)) return entry.paint;
    }
    return null;
}

fn parseSvgLinearGradients(allocator: std.mem.Allocator, document: []const u8) ![]SvgGradientDef {
    var gradients = std.ArrayList(SvgGradientDef).empty;
    errdefer gradients.deinit(allocator);

    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<linearGradient")) |gradient_start| {
        const tag_end = std.mem.indexOfPos(u8, document, gradient_start, ">") orelse break;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</linearGradient>") orelse break;
        const tag = document[gradient_start..tag_end];
        const body = document[tag_end + 1 .. close_start];
        search_start = close_start + "</linearGradient>".len;

        const id = attributeValue(tag, "id") orelse continue;
        const stops = parseSvgGradientStops(body) orelse continue;
        try gradients.append(allocator, .{
            .id = id,
            .paint = .{ .linear_gradient = .{
                .x1 = parseSvgLength(attributeValue(tag, "x1")) orelse 0,
                .y1 = parseSvgLength(attributeValue(tag, "y1")) orelse 0,
                .x2 = parseSvgLength(attributeValue(tag, "x2")) orelse 100,
                .y2 = parseSvgLength(attributeValue(tag, "y2")) orelse 0,
                .spread = parseSvgGradientSpread(attributeValue(tag, "spreadMethod")),
                .transform = parseSvgTransform(attributeValue(tag, "gradientTransform")) orelse SvgTransform.identity,
                .stops = stops,
            } },
        });
    }
    search_start = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<radialGradient")) |gradient_start| {
        const tag_end = std.mem.indexOfPos(u8, document, gradient_start, ">") orelse break;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</radialGradient>") orelse break;
        const tag = document[gradient_start..tag_end];
        const body = document[tag_end + 1 .. close_start];
        search_start = close_start + "</radialGradient>".len;

        const id = attributeValue(tag, "id") orelse continue;
        const stops = parseSvgGradientStops(body) orelse continue;
        try gradients.append(allocator, .{
            .id = id,
            .paint = .{ .radial_gradient = .{
                .cx = parseSvgLength(attributeValue(tag, "cx")) orelse 50,
                .cy = parseSvgLength(attributeValue(tag, "cy")) orelse 50,
                .r = parseSvgLength(attributeValue(tag, "r")) orelse 50,
                .spread = parseSvgGradientSpread(attributeValue(tag, "spreadMethod")),
                .transform = parseSvgTransform(attributeValue(tag, "gradientTransform")) orelse SvgTransform.identity,
                .stops = stops,
            } },
        });
    }
    return try gradients.toOwnedSlice(allocator);
}

fn parseSvgClassStyles(allocator: std.mem.Allocator, document: []const u8) ![]SvgClassStyle {
    var styles = std.ArrayList(SvgClassStyle).empty;
    errdefer styles.deinit(allocator);

    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<style")) |style_start| {
        const tag_end = std.mem.indexOfPos(u8, document, style_start, ">") orelse break;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</style>") orelse break;
        const body = document[tag_end + 1 .. close_start];
        search_start = close_start + "</style>".len;

        var cursor: usize = 0;
        while (cursor < body.len) {
            cursor = skipAsciiSpaces(body, cursor);
            if (cursor >= body.len) break;
            const brace_start = std.mem.indexOfScalarPos(u8, body, cursor, '{') orelse break;
            const brace_end = std.mem.indexOfScalarPos(u8, body, brace_start + 1, '}') orelse break;
            const selector_list = body[cursor..brace_start];
            var selector_cursor: usize = 0;
            while (selector_cursor < selector_list.len) {
                const selector_end = std.mem.indexOfScalarPos(u8, selector_list, selector_cursor, ',') orelse selector_list.len;
                const selector_text = std.mem.trim(u8, selector_list[selector_cursor..selector_end], " \t\r\n");
                if (parseSvgSimpleSelector(selector_text)) |parsed| {
                    try styles.append(allocator, .{
                        .selector = parsed.selector,
                        .name = parsed.name,
                        .declarations = body[brace_start + 1 .. brace_end],
                    });
                }
                selector_cursor = selector_end + @intFromBool(selector_end < selector_list.len);
            }
            cursor = brace_end + 1;
        }
    }
    return try styles.toOwnedSlice(allocator);
}

fn parseSvgSimpleSelector(text: []const u8) ?struct { selector: SvgStyleSelector, name: []const u8 } {
    if (text.len == 0) return null;
    const selector: SvgStyleSelector = switch (text[0]) {
        '.' => .class,
        '#' => .id,
        else => .element,
    };
    const start: usize = if (text[0] == '.' or text[0] == '#') 1 else 0;
    var end = start;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '-')) : (end += 1) {}
    if (end == start or end != text.len) return null;
    return .{ .selector = selector, .name = text[start..end] };
}

fn parseSvgClipPaths(allocator: std.mem.Allocator, document: []const u8) ![]SvgClipDef {
    var clips = std.ArrayList(SvgClipDef).empty;
    errdefer {
        for (clips.items) |*clip| clip.deinit();
        clips.deinit(allocator);
    }

    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<clipPath")) |clip_start| {
        const tag_end = std.mem.indexOfPos(u8, document, clip_start, ">") orelse break;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</clipPath>") orelse break;
        const tag = document[clip_start..tag_end];
        const body = document[tag_end + 1 .. close_start];
        search_start = close_start + "</clipPath>".len;

        const id = attributeValue(tag, "id") orelse continue;
        if (std.mem.indexOf(u8, body, "<rect")) |rect_start| {
            const rect_end = std.mem.indexOfPos(u8, body, rect_start, ">") orelse continue;
            const rect_tag = body[rect_start..rect_end];
            const width = parseSvgLength(attributeValue(rect_tag, "width")) orelse continue;
            const height = parseSvgLength(attributeValue(rect_tag, "height")) orelse continue;
            if (width <= 0 or height <= 0) continue;
            try clips.append(allocator, .{
                .id = id,
                .shape = .{ .rect = .{
                    .x = parseSvgLength(attributeValue(rect_tag, "x")) orelse 0,
                    .y = parseSvgLength(attributeValue(rect_tag, "y")) orelse 0,
                    .width = width,
                    .height = height,
                } },
            });
            continue;
        }
        if (std.mem.indexOf(u8, body, "<circle")) |circle_start| {
            const circle_end = std.mem.indexOfPos(u8, body, circle_start, ">") orelse continue;
            const circle_tag = body[circle_start..circle_end];
            const radius = parseSvgLength(attributeValue(circle_tag, "r")) orelse continue;
            if (radius <= 0) continue;
            try clips.append(allocator, .{
                .id = id,
                .shape = .{ .circle = .{
                    .cx = parseSvgLength(attributeValue(circle_tag, "cx")) orelse 0,
                    .cy = parseSvgLength(attributeValue(circle_tag, "cy")) orelse 0,
                    .r = radius,
                } },
            });
            continue;
        }
        if (std.mem.indexOf(u8, body, "<path")) |path_start| {
            const path_end = std.mem.indexOfPos(u8, body, path_start, ">") orelse continue;
            const path_tag = body[path_start..path_end];
            const path_text = attributeValue(path_tag, "d") orelse continue;
            var outline = glyph_mod.GlyphOutline.init(allocator, 0, .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 }, 0, 0);
            errdefer outline.deinit();
            if (!try parseSvgPathData(&outline, path_text)) {
                outline.deinit();
                continue;
            }
            try clips.append(allocator, .{
                .id = id,
                .shape = .{ .path = outline },
            });
        }
    }
    return try clips.toOwnedSlice(allocator);
}

fn parseSvgMasks(allocator: std.mem.Allocator, document: []const u8) ![]SvgMaskDef {
    var masks = std.ArrayList(SvgMaskDef).empty;
    errdefer {
        for (masks.items) |*mask| mask.deinit();
        masks.deinit(allocator);
    }

    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, document, search_start, "<mask")) |mask_start| {
        const tag_end = std.mem.indexOfPos(u8, document, mask_start, ">") orelse break;
        const close_start = std.mem.indexOfPos(u8, document, tag_end, "</mask>") orelse break;
        const tag = document[mask_start..tag_end];
        const body = document[tag_end + 1 .. close_start];
        search_start = close_start + "</mask>".len;

        const id = attributeValue(tag, "id") orelse continue;
        var mask_def = SvgMaskDef{ .id = id };
        if (std.mem.indexOf(u8, body, "<rect")) |rect_start| {
            const rect_end = std.mem.indexOfPos(u8, body, rect_start, ">") orelse continue;
            const rect_tag = body[rect_start..rect_end];
            const width = parseSvgLength(attributeValue(rect_tag, "width")) orelse continue;
            const height = parseSvgLength(attributeValue(rect_tag, "height")) orelse continue;
            if (width <= 0 or height <= 0) continue;
            try appendMaskShape(&mask_def, .{ .rect = .{
                .rect = .{
                    .x = parseSvgLength(attributeValue(rect_tag, "x")) orelse 0,
                    .y = parseSvgLength(attributeValue(rect_tag, "y")) orelse 0,
                    .width = width,
                    .height = height,
                },
                .alpha = parseSvgMaskAlpha(rect_tag, .{ .styles = &.{} }),
            } });
        }
        if (std.mem.indexOf(u8, body, "<circle")) |circle_start| {
            const circle_end = std.mem.indexOfPos(u8, body, circle_start, ">") orelse continue;
            const circle_tag = body[circle_start..circle_end];
            const radius = parseSvgLength(attributeValue(circle_tag, "r")) orelse continue;
            if (radius <= 0) continue;
            try appendMaskShape(&mask_def, .{ .circle = .{
                .circle = .{
                    .cx = parseSvgLength(attributeValue(circle_tag, "cx")) orelse 0,
                    .cy = parseSvgLength(attributeValue(circle_tag, "cy")) orelse 0,
                    .r = radius,
                },
                .alpha = parseSvgMaskAlpha(circle_tag, .{ .styles = &.{} }),
            } });
        }
        if (std.mem.indexOf(u8, body, "<path")) |path_start| {
            const path_end = std.mem.indexOfPos(u8, body, path_start, ">") orelse continue;
            const path_tag = body[path_start..path_end];
            const path_text = attributeValue(path_tag, "d") orelse continue;
            var outline = glyph_mod.GlyphOutline.init(allocator, 0, .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 }, 0, 0);
            errdefer outline.deinit();
            if (try parseSvgPathData(&outline, path_text)) {
                try appendMaskShape(&mask_def, .{ .path = .{
                    .outline = outline,
                    .alpha = parseSvgMaskAlpha(path_tag, .{ .styles = &.{} }),
                } });
            } else {
                outline.deinit();
            }
        }
        if (mask_def.len != 0) {
            try masks.append(allocator, mask_def);
        }
    }
    return try masks.toOwnedSlice(allocator);
}

fn appendMaskShape(mask: *SvgMaskDef, shape: SvgMaskShape) !void {
    if (mask.len >= mask.shapes.len) return error.NoSpaceLeft;
    mask.shapes[mask.len] = shape;
    mask.len += 1;
}

fn parseSvgMaskAlpha(tag_text: []const u8, context: SvgStyleContext) f32 {
    const opacity = parseSvgAlpha(svgAttribute(tag_text, context, "opacity")) orelse 1.0;
    const fill_text = svgAttribute(tag_text, context, "fill") orelse "white";
    const color = parseSvgColor(fill_text) orelse return 0.0;
    return @max(0.0, @min(1.0, opacity * colorLuminance(color)));
}

fn colorLuminance(color: font_mod.PaletteColor) f32 {
    const red = @as(f32, @floatFromInt(color.red)) / 255.0;
    const green = @as(f32, @floatFromInt(color.green)) / 255.0;
    const blue = @as(f32, @floatFromInt(color.blue)) / 255.0;
    const alpha = @as(f32, @floatFromInt(color.alpha)) / 255.0;
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha;
}

fn parseSvgGradientStops(body: []const u8) ?SvgGradientStops {
    var stops = SvgGradientStops{};
    var search_start: usize = 0;
    while (std.mem.indexOfPos(u8, body, search_start, "<stop")) |stop_start| {
        const stop_end = std.mem.indexOfPos(u8, body, stop_start, ">") orelse break;
        const stop_tag = body[stop_start..stop_end];
        search_start = stop_end + 1;
        if (stops.len >= stops.items.len) break;
        var color = parseSvgColor(svgAttributeOrStyle(stop_tag, "stop-color") orelse continue) orelse continue;
        const stop_alpha = parseSvgAlpha(svgAttributeOrStyle(stop_tag, "stop-opacity")) orelse 1.0;
        color.alpha = scaledAlpha(color.alpha, stop_alpha);
        const default_offset: f32 = if (stops.len == 0) 0.0 else 1.0;
        const offset = parseSvgStopOffset(svgAttributeOrStyle(stop_tag, "offset")) orelse default_offset;
        stops.items[stops.len] = .{ .offset = @max(0.0, @min(1.0, offset)), .color = color };
        stops.len += 1;
    }
    if (stops.len == 0) return null;
    return stops;
}

fn parseSvgStopOffset(value: ?[]const u8) ?f32 {
    const text = value orelse return null;
    var scanner = NumberScanner.init(text);
    const number = scanner.next() orelse return null;
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.endsWith(u8, trimmed, "%")) return number / 100.0;
    return number;
}

fn parseSvgGradientSpread(value: ?[]const u8) SvgGradientSpread {
    const text = value orelse return .pad;
    if (std.mem.eql(u8, text, "repeat")) return .repeat;
    if (std.mem.eql(u8, text, "reflect")) return .reflect;
    return .pad;
}

fn parseSvgLength(value: ?[]const u8) ?f32 {
    const text = value orelse return null;
    var scanner = NumberScanner.init(text);
    return scanner.next();
}

fn parseSvgAlpha(value: ?[]const u8) ?f32 {
    const text = value orelse return null;
    var scanner = NumberScanner.init(text);
    const alpha = scanner.next() orelse return null;
    return @max(0.0, @min(1.0, alpha));
}

fn parseSvgTransform(value: ?[]const u8) ?SvgTransform {
    const text = value orelse return null;
    var offset: usize = 0;
    var result: SvgTransform = .identity;
    var parsed = false;
    while (true) {
        offset = skipAsciiSeparators(text, offset);
        if (offset >= text.len) break;
        const name_start = offset;
        while (offset < text.len and std.ascii.isAlphabetic(text[offset])) : (offset += 1) {}
        if (offset == name_start) return null;
        const name = text[name_start..offset];
        offset = skipAsciiSpaces(text, offset);
        if (offset >= text.len or text[offset] != '(') return null;
        const args_start = offset + 1;
        const args_end = std.mem.indexOfScalarPos(u8, text, args_start, ')') orelse return null;
        const args = text[args_start..args_end];
        offset = args_end + 1;

        const next_transform = parseSvgTransformItem(name, args) orelse return null;
        result = result.mul(next_transform);
        parsed = true;
    }
    return if (parsed) result else null;
}

fn parseSvgTransformItem(name: []const u8, args: []const u8) ?SvgTransform {
    var scanner = NumberScanner.init(args);
    if (std.mem.eql(u8, name, "translate")) {
        const tx = scanner.next() orelse return null;
        const ty = scanner.next() orelse 0;
        return .{ .dx = tx, .dy = ty };
    }
    if (std.mem.eql(u8, name, "scale")) {
        const sx = scanner.next() orelse return null;
        const sy = scanner.next() orelse sx;
        return .{ .xx = sx, .yy = sy };
    }
    if (std.mem.eql(u8, name, "rotate")) {
        const degrees = scanner.next() orelse return null;
        const radians = degrees * std.math.pi / 180.0;
        const cos = @cos(radians);
        const sin = @sin(radians);
        const rotation = SvgTransform{ .xx = cos, .yx = sin, .xy = -sin, .yy = cos };
        const cx = scanner.next() orelse return rotation;
        const cy = scanner.next() orelse return null;
        return (SvgTransform{ .dx = cx, .dy = cy }).mul(rotation).mul(.{ .dx = -cx, .dy = -cy });
    }
    if (std.mem.eql(u8, name, "skewX")) {
        const degrees = scanner.next() orelse return null;
        const radians = degrees * std.math.pi / 180.0;
        return .{ .xy = @tan(radians) };
    }
    if (std.mem.eql(u8, name, "skewY")) {
        const degrees = scanner.next() orelse return null;
        const radians = degrees * std.math.pi / 180.0;
        return .{ .yx = @tan(radians) };
    }
    if (std.mem.eql(u8, name, "matrix")) {
        const a = scanner.next() orelse return null;
        const b = scanner.next() orelse return null;
        const c = scanner.next() orelse return null;
        const d = scanner.next() orelse return null;
        const e = scanner.next() orelse return null;
        const f = scanner.next() orelse return null;
        return .{ .xx = a, .yx = b, .xy = c, .yy = d, .dx = e, .dy = f };
    }
    return null;
}

fn parseHexByte(text: []const u8) ?u8 {
    if (text.len != 2) return null;
    const high = std.fmt.charToDigit(text[0], 16) catch return null;
    const low = std.fmt.charToDigit(text[1], 16) catch return null;
    return @intCast(high * 16 + low);
}

fn parseHexNibble(byte: u8) ?u8 {
    const value = std.fmt.charToDigit(byte, 16) catch return null;
    return @intCast(value * 17);
}

fn colorComponentToByte(value: f32) u8 {
    return @intFromFloat(@round(@max(0.0, @min(255.0, value))));
}

fn hslToRgb(hue_degrees: f32, saturation: f32, lightness: f32) font_mod.PaletteColor {
    const h = positiveModulo(hue_degrees, 360.0) / 360.0;
    const s = @max(0.0, @min(1.0, saturation));
    const l = @max(0.0, @min(1.0, lightness));
    if (s == 0) {
        const gray = colorComponentToByte(l * 255.0);
        return .{ .red = gray, .green = gray, .blue = gray, .alpha = 255 };
    }
    const q = if (l < 0.5) l * (1.0 + s) else l + s - l * s;
    const p = 2.0 * l - q;
    return .{
        .red = colorComponentToByte(hueToRgb(p, q, h + 1.0 / 3.0) * 255.0),
        .green = colorComponentToByte(hueToRgb(p, q, h) * 255.0),
        .blue = colorComponentToByte(hueToRgb(p, q, h - 1.0 / 3.0) * 255.0),
        .alpha = 255,
    };
}

fn hueToRgb(p: f32, q: f32, t_value: f32) f32 {
    var t = t_value;
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

fn positiveModulo(value: f32, modulus: f32) f32 {
    return value - @floor(value / modulus) * modulus;
}

const ColorFunctionScanner = struct {
    text: []const u8,
    offset: usize = 0,

    fn init(text: []const u8) ColorFunctionScanner {
        return .{ .text = text };
    }

    fn nextComponent(self: *ColorFunctionScanner) ?u8 {
        const parsed = self.nextNumberWithPercent() orelse return null;
        if (parsed.percent) return colorComponentToByte(parsed.value * 255.0 / 100.0);
        return colorComponentToByte(parsed.value);
    }

    fn nextAlpha(self: *ColorFunctionScanner) ?u8 {
        const parsed = self.nextNumberWithPercent() orelse return null;
        if (parsed.percent) return colorComponentToByte(parsed.value * 255.0 / 100.0);
        return colorComponentToByte(parsed.value * 255.0);
    }

    fn nextUnitInterval(self: *ColorFunctionScanner) ?f32 {
        const parsed = self.nextNumberWithPercent() orelse return null;
        const value = if (parsed.percent) parsed.value / 100.0 else parsed.value;
        return @max(0.0, @min(1.0, value));
    }

    fn nextRawNumber(self: *ColorFunctionScanner) ?f32 {
        const parsed = self.nextNumberWithPercent() orelse return null;
        return parsed.value;
    }

    fn nextNumberWithPercent(self: *ColorFunctionScanner) ?struct { value: f32, percent: bool } {
        self.offset = skipColorSeparators(self.text, self.offset);
        if (self.offset >= self.text.len) return null;
        var scanner = NumberScanner{ .text = self.text, .offset = self.offset };
        const value = scanner.next() orelse return null;
        self.offset = scanner.offset;
        var percent = false;
        if (self.offset < self.text.len and self.text[self.offset] == '%') {
            percent = true;
            self.offset += 1;
        }
        return .{ .value = value, .percent = percent };
    }
};

fn skipColorSeparators(text: []const u8, offset: usize) usize {
    var cursor = offset;
    while (cursor < text.len and (std.ascii.isWhitespace(text[cursor]) or text[cursor] == ',' or text[cursor] == '/')) : (cursor += 1) {}
    return cursor;
}

const NumberScanner = struct {
    text: []const u8,
    offset: usize = 0,

    fn init(text: []const u8) NumberScanner {
        return .{ .text = text };
    }

    fn next(self: *NumberScanner) ?f32 {
        self.offset = skipAsciiSeparators(self.text, self.offset);
        if (self.offset >= self.text.len) return null;
        const start = self.offset;
        if (self.text[self.offset] == '+' or self.text[self.offset] == '-') self.offset += 1;
        var has_digit = false;
        while (self.offset < self.text.len and std.ascii.isDigit(self.text[self.offset])) : (self.offset += 1) has_digit = true;
        if (self.offset < self.text.len and self.text[self.offset] == '.') {
            self.offset += 1;
            while (self.offset < self.text.len and std.ascii.isDigit(self.text[self.offset])) : (self.offset += 1) has_digit = true;
        }
        if (!has_digit) return null;
        if (self.offset < self.text.len and (self.text[self.offset] == 'e' or self.text[self.offset] == 'E')) {
            const exponent_start = self.offset;
            self.offset += 1;
            if (self.offset < self.text.len and (self.text[self.offset] == '+' or self.text[self.offset] == '-')) self.offset += 1;
            var exponent_digit = false;
            while (self.offset < self.text.len and std.ascii.isDigit(self.text[self.offset])) : (self.offset += 1) exponent_digit = true;
            if (!exponent_digit) self.offset = exponent_start;
        }
        return std.fmt.parseFloat(f32, self.text[start..self.offset]) catch null;
    }
};

const PathScanner = struct {
    text: []const u8,
    offset: usize = 0,

    fn init(text: []const u8) PathScanner {
        return .{ .text = text };
    }

    fn done(self: *const PathScanner) bool {
        return self.offset >= self.text.len;
    }

    fn skipSeparators(self: *PathScanner) void {
        self.offset = skipAsciiSeparators(self.text, self.offset);
    }

    fn readByte(self: *PathScanner) u8 {
        const byte = self.text[self.offset];
        self.offset += 1;
        return byte;
    }

    fn peekCommand(self: *const PathScanner) ?u8 {
        if (self.offset >= self.text.len) return null;
        const byte = self.text[self.offset];
        return switch (byte) {
            'M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'Q', 'q', 'T', 't', 'C', 'c', 'S', 's', 'A', 'a', 'Z', 'z' => byte,
            else => null,
        };
    }

    fn nextNumber(self: *PathScanner) ?f32 {
        var numbers = NumberScanner{ .text = self.text, .offset = self.offset };
        const value = numbers.next() orelse return null;
        self.offset = numbers.offset;
        return value;
    }
};

fn skipAsciiSpaces(text: []const u8, offset: usize) usize {
    var cursor = offset;
    while (cursor < text.len and std.ascii.isWhitespace(text[cursor])) : (cursor += 1) {}
    return cursor;
}

fn skipAsciiSeparators(text: []const u8, offset: usize) usize {
    var cursor = offset;
    while (cursor < text.len and (std.ascii.isWhitespace(text[cursor]) or text[cursor] == ',')) : (cursor += 1) {}
    return cursor;
}

fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == ':';
}

test "small glyph alignment translates outline to pixel grid" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 4.2 } },
        .{ .a = .{ .x = 7.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    const outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 }, 500, 0);
    alignSmallGlyphToPixelGrid(&lines, &outline, 12.0 / 1000.0, 12, 12);
    try std.testing.expect(@abs(lines[0].a.x - 2.0) < 0.001);
    try std.testing.expect(@abs(lines[0].a.y - 4.5) < 0.001);
    try std.testing.expect(@abs(lines[1].b.y - 10.0) < 0.001);
}

test "small multi-contour glyph alignment snaps x-height" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 4.2 } },
        .{ .a = .{ .x = 7.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 }, 500, 0);
    defer outline.deinit();
    try outline.commands.append(std.testing.allocator, .{ .move_to = .{ .x = 0, .y = 0 } });
    try outline.commands.append(std.testing.allocator, .{ .move_to = .{ .x = 1, .y = 1 } });
    alignSmallGlyphToPixelGrid(&lines, &outline, 12.0 / 1000.0, 12, 12);
    try std.testing.expect(@abs(lines[0].a.x - 2.0) < 0.001);
    try std.testing.expect(lines[0].a.y < 4.0);
    try std.testing.expect(lines[1].b.y > 10.0);
}

test "large glyph alignment leaves outline unchanged" {
    var lines = [_]Line{
        .{ .a = .{ .x = 2.3, .y = 4.2 }, .b = .{ .x = 7.3, .y = 9.7 } },
    };
    const outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{ .x_min = 0, .y_min = 0, .x_max = 500, .y_max = 500 }, 500, 0);
    alignSmallGlyphToPixelGrid(&lines, &outline, 24.0 / 1000.0, 24, 24);
    try std.testing.expect(@abs(lines[0].a.x - 2.3) < 0.001);
    try std.testing.expect(@abs(lines[0].b.y - 9.7) < 0.001);
}
