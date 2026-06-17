const std = @import("std");
const font_mod = @import("font.zig");
const glyph_mod = @import("glyph.zig");
const layout = @import("layout.zig");

pub const GlyphRenderMode = enum {
    atlas_mask,
    path_outline,
    slug_analytic,
};

pub const BridgeOptions = struct {
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    palette_index: u16 = 0,
    include_path_requests: bool = true,
    include_color_glyphs: bool = true,
    render_mode: GlyphRenderMode = .atlas_mask,
    cursor_position: ?layout.TextPosition = null,
    selection_start_glyph: ?usize = null,
    selection_end_glyph: ?usize = null,
};

pub const GlyphAtlasCacheKey = struct {
    font_addr: usize,
    glyph_id: glyph_mod.GlyphId,
    font_size_bits: u32,
    palette_index: ?u16 = null,
    render_mode: GlyphRenderMode,
};

pub const GlyphAtlasRequest = struct {
    font: *const font_mod.Font,
    glyph_id: glyph_mod.GlyphId,
    font_size: f32,
    palette_index: ?u16 = null,
    render_mode: GlyphRenderMode = .atlas_mask,

    pub fn cacheKey(self: GlyphAtlasRequest) GlyphAtlasCacheKey {
        return .{
            .font_addr = @intFromPtr(self.font),
            .glyph_id = self.glyph_id,
            .font_size_bits = @bitCast(self.font_size),
            .palette_index = self.palette_index,
            .render_mode = self.render_mode,
        };
    }
};

pub const GlyphPathSource = struct {
    glyph_index: usize,
    codepoint: u21,
    cluster: usize,
    palette_index: ?u16 = null,
};

pub const GlyphPathCacheKey = struct {
    font_addr: usize,
    glyph_id: glyph_mod.GlyphId,
    font_size_bits: u32,
    render_mode: GlyphRenderMode,
};

pub const GlyphPathRequest = struct {
    font: *const font_mod.Font,
    glyph_id: glyph_mod.GlyphId,
    font_size: f32,
    render_mode: GlyphRenderMode = .path_outline,
    source: GlyphPathSource = .{ .glyph_index = 0, .codepoint = 0, .cluster = 0 },

    pub fn cacheKey(self: GlyphPathRequest) GlyphPathCacheKey {
        return .{
            .font_addr = @intFromPtr(self.font),
            .glyph_id = self.glyph_id,
            .font_size_bits = @bitCast(self.font_size),
            .render_mode = self.render_mode,
        };
    }
};

pub const PositionedGlyph = struct {
    font: *const font_mod.Font,
    glyph_id: glyph_mod.GlyphId,
    codepoint: u21,
    cluster: usize,
    x: f32,
    baseline_y: f32,
    x_offset: f32,
    y_offset: f32,
    x_advance: f32,
    render_mode: GlyphRenderMode = .atlas_mask,
    atlas_request_index: ?usize = null,
    path_request_index: ?usize = null,
    color_glyph_index: ?usize = null,
};

pub const GlyphRunDrawCommand = struct {
    font: *const font_mod.Font,
    font_size: f32,
    glyph_start: usize,
    glyph_len: usize,
    x: f32,
    baseline_y: f32,
    line_index: usize,
    render_mode: GlyphRenderMode = .atlas_mask,
};

pub const ColorGlyphLayerCommand = struct {
    glyph_id: glyph_mod.GlyphId,
    palette_index: u16,
    color: ?font_mod.PaletteColor,
    atlas_request_index: usize,
};

pub const ColorGlyphPaint = union(enum) {
    none,
    colr_v0_layers: struct { layer_start: usize, layer_len: usize },
    colr_v1_solid: font_mod.ColorPaint.Solid,
    colr_v1_glyph: font_mod.ColorPaint.Glyph,
    colr_v1_layers: font_mod.ColorPaint.Layers,
    svg_document: []const u8,
};

pub const ColorGlyphDrawCommand = struct {
    glyph_index: usize,
    layer_start: usize,
    layer_len: usize,
    svg_document: ?[]const u8 = null,
    has_colr_v1_paint: bool = false,
    paint: ColorGlyphPaint = .none,
};

pub const TextCursorGeometry = struct {
    rect: layout.TextRect,
    position: layout.TextPosition,
};

pub const TextSelectionGeometry = struct {
    rect: layout.TextRect,
};

pub const GlyphDrawList = struct {
    allocator: std.mem.Allocator,
    glyphs: []PositionedGlyph,
    runs: []GlyphRunDrawCommand,
    atlas_requests: []GlyphAtlasRequest,
    path_requests: []GlyphPathRequest,
    color_glyphs: []ColorGlyphDrawCommand,
    color_layers: []ColorGlyphLayerCommand,
    cursor: ?TextCursorGeometry,
    selection: []TextSelectionGeometry,

    pub fn deinit(self: *GlyphDrawList) void {
        self.allocator.free(self.selection);
        self.allocator.free(self.color_layers);
        self.allocator.free(self.color_glyphs);
        self.allocator.free(self.path_requests);
        self.allocator.free(self.atlas_requests);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub fn buildGlyphDrawList(allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, options: BridgeOptions) !GlyphDrawList {
    var builder = BridgeBuilder.init(allocator, paragraph, options);
    defer builder.deinitScratch();
    try builder.build();
    return try builder.toOwnedList();
}

const BridgeBuilder = struct {
    allocator: std.mem.Allocator,
    paragraph: layout.ParagraphLayout,
    options: BridgeOptions,
    glyphs: std.ArrayList(PositionedGlyph) = .empty,
    runs: std.ArrayList(GlyphRunDrawCommand) = .empty,
    atlas_requests: std.ArrayList(GlyphAtlasRequest) = .empty,
    path_requests: std.ArrayList(GlyphPathRequest) = .empty,
    color_glyphs: std.ArrayList(ColorGlyphDrawCommand) = .empty,
    color_layers: std.ArrayList(ColorGlyphLayerCommand) = .empty,
    selection: std.ArrayList(TextSelectionGeometry) = .empty,
    cursor: ?TextCursorGeometry = null,

    fn init(allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, options: BridgeOptions) BridgeBuilder {
        return .{
            .allocator = allocator,
            .paragraph = paragraph,
            .options = options,
        };
    }

    fn deinitScratch(self: *BridgeBuilder) void {
        self.selection.deinit(self.allocator);
        self.color_layers.deinit(self.allocator);
        self.color_glyphs.deinit(self.allocator);
        self.path_requests.deinit(self.allocator);
        self.atlas_requests.deinit(self.allocator);
        self.runs.deinit(self.allocator);
        self.glyphs.deinit(self.allocator);
    }

    fn build(self: *BridgeBuilder) !void {
        for (self.paragraph.lines, 0..) |line, line_index| {
            try self.appendLine(line, line_index);
        }
        if (self.options.cursor_position) |position| {
            var rect = self.paragraph.caretRect(position);
            rect.x += self.options.origin_x;
            rect.y += self.options.origin_y;
            self.cursor = .{ .rect = rect, .position = position };
        }
        if (self.options.selection_start_glyph != null and self.options.selection_end_glyph != null) {
            const rects = try self.paragraph.selectionRects(self.allocator, self.options.selection_start_glyph.?, self.options.selection_end_glyph.?);
            defer self.allocator.free(rects);
            for (rects) |rect| {
                try self.selection.append(self.allocator, .{
                    .rect = .{
                        .x = rect.x + self.options.origin_x,
                        .y = rect.y + self.options.origin_y,
                        .width = rect.width,
                        .height = rect.height,
                    },
                });
            }
        }
    }

    fn appendLine(self: *BridgeBuilder, line: layout.ParagraphLine, line_index: usize) !void {
        const line_glyph_end = line.glyph_start + line.glyph_len;
        const baseline_y = self.options.origin_y + line.y + line.baseline;
        for (line.runs(self.paragraph)) |run| {
            const start = @max(line.glyph_start, run.glyph_start);
            const end = @min(line_glyph_end, run.glyph_start + run.glyph_len);
            if (start >= end) continue;
            const command_start = self.glyphs.items.len;
            try self.appendGlyphsInRange(run, start, end, line, baseline_y);
            try self.runs.append(self.allocator, .{
                .font = run.font,
                .font_size = run.font_size,
                .glyph_start = command_start,
                .glyph_len = self.glyphs.items.len - command_start,
                .x = self.options.origin_x + line.x + advanceBefore(self.paragraph.glyphs[line.glyph_start..line_glyph_end], start - line.glyph_start),
                .baseline_y = baseline_y,
                .line_index = line_index,
                .render_mode = self.options.render_mode,
            });
        }
    }

    fn appendGlyphsInRange(self: *BridgeBuilder, run: layout.CascadeRun, start: usize, end: usize, line: layout.ParagraphLine, baseline_y: f32) !void {
        const line_glyph_end = line.glyph_start + line.glyph_len;
        var pen_x = self.options.origin_x + line.x + advanceBefore(self.paragraph.glyphs[line.glyph_start..line_glyph_end], start - line.glyph_start);
        for (self.paragraph.glyphs[start..end]) |glyph| {
            const output_index = self.glyphs.items.len;
            const atlas_index = try self.atlasRequestIndex(.{
                .font = run.font,
                .glyph_id = glyph.glyph_id,
                .font_size = run.font_size,
                .render_mode = self.options.render_mode,
            });
            var path_index: ?usize = null;
            if (self.options.include_path_requests) {
                path_index = try self.pathRequestIndex(.{
                    .font = run.font,
                    .glyph_id = glyph.glyph_id,
                    .font_size = run.font_size,
                    .render_mode = pathRequestMode(self.options.render_mode),
                    .source = .{
                        .glyph_index = output_index,
                        .codepoint = glyph.codepoint,
                        .cluster = glyph.cluster,
                    },
                });
            }

            try self.glyphs.append(self.allocator, .{
                .font = run.font,
                .glyph_id = glyph.glyph_id,
                .codepoint = glyph.codepoint,
                .cluster = glyph.cluster,
                .x = pen_x,
                .baseline_y = baseline_y,
                .x_offset = glyph.x_offset,
                .y_offset = glyph.y_offset,
                .x_advance = glyph.x_advance,
                .render_mode = self.options.render_mode,
                .atlas_request_index = atlas_index,
                .path_request_index = path_index,
            });
            if (self.options.include_color_glyphs) {
                if (try self.appendColorGlyph(run.font, run.font_size, glyph.glyph_id, output_index)) |color_index| {
                    self.glyphs.items[output_index].color_glyph_index = color_index;
                }
            }
            pen_x += glyph.x_advance;
        }
    }

    fn appendColorGlyph(self: *BridgeBuilder, font: *const font_mod.Font, font_size: f32, glyph_id: glyph_mod.GlyphId, glyph_index: usize) !?usize {
        const layer_start = self.color_layers.items.len;
        const layers = try font.colorLayers(self.allocator, glyph_id);
        defer self.allocator.free(layers);
        for (layers) |layer| {
            const atlas_index = try self.atlasRequestIndex(.{
                .font = font,
                .glyph_id = layer.glyph_id,
                .font_size = font_size,
                .palette_index = layer.palette_index,
                .render_mode = self.options.render_mode,
            });
            try self.color_layers.append(self.allocator, .{
                .glyph_id = layer.glyph_id,
                .palette_index = layer.palette_index,
                .color = try font.paletteColor(self.options.palette_index, layer.palette_index),
                .atlas_request_index = atlas_index,
            });
        }

        const svg_document = try font.svgDocument(glyph_id);
        const color_paint = try font.colorPaint(glyph_id);
        const layer_len = self.color_layers.items.len - layer_start;
        if (layer_len == 0 and svg_document == null and color_paint == null) return null;

        const color_index = self.color_glyphs.items.len;
        try self.color_glyphs.append(self.allocator, .{
            .glyph_index = glyph_index,
            .layer_start = layer_start,
            .layer_len = layer_len,
            .svg_document = svg_document,
            .has_colr_v1_paint = color_paint != null,
            .paint = colorGlyphPaint(layer_start, layer_len, svg_document, color_paint),
        });
        return color_index;
    }

    fn atlasRequestIndex(self: *BridgeBuilder, request: GlyphAtlasRequest) !usize {
        for (self.atlas_requests.items, 0..) |existing, index| {
            if (sameAtlasRequest(existing, request)) return index;
        }
        try self.atlas_requests.append(self.allocator, request);
        return self.atlas_requests.items.len - 1;
    }

    fn pathRequestIndex(self: *BridgeBuilder, request: GlyphPathRequest) !usize {
        for (self.path_requests.items, 0..) |existing, index| {
            if (existing.font == request.font and existing.glyph_id == request.glyph_id and existing.font_size == request.font_size and existing.render_mode == request.render_mode) return index;
        }
        try self.path_requests.append(self.allocator, request);
        return self.path_requests.items.len - 1;
    }

    fn toOwnedList(self: *BridgeBuilder) !GlyphDrawList {
        return .{
            .allocator = self.allocator,
            .glyphs = try self.glyphs.toOwnedSlice(self.allocator),
            .runs = try self.runs.toOwnedSlice(self.allocator),
            .atlas_requests = try self.atlas_requests.toOwnedSlice(self.allocator),
            .path_requests = try self.path_requests.toOwnedSlice(self.allocator),
            .color_glyphs = try self.color_glyphs.toOwnedSlice(self.allocator),
            .color_layers = try self.color_layers.toOwnedSlice(self.allocator),
            .cursor = self.cursor,
            .selection = try self.selection.toOwnedSlice(self.allocator),
        };
    }
};

fn sameAtlasRequest(a: GlyphAtlasRequest, b: GlyphAtlasRequest) bool {
    return a.font == b.font and
        a.glyph_id == b.glyph_id and
        a.font_size == b.font_size and
        a.palette_index == b.palette_index and
        a.render_mode == b.render_mode;
}

fn pathRequestMode(render_mode: GlyphRenderMode) GlyphRenderMode {
    return switch (render_mode) {
        .atlas_mask => .path_outline,
        .path_outline => .path_outline,
        .slug_analytic => .slug_analytic,
    };
}

fn colorGlyphPaint(layer_start: usize, layer_len: usize, svg_document: ?[]const u8, color_paint: ?font_mod.ColorPaint) ColorGlyphPaint {
    if (color_paint) |paint| {
        return switch (paint) {
            .solid => |solid| .{ .colr_v1_solid = solid },
            .glyph => |glyph| .{ .colr_v1_glyph = glyph },
            .layers => |layers| .{ .colr_v1_layers = layers },
        };
    }
    if (svg_document) |document| return .{ .svg_document = document };
    if (layer_len > 0) return .{ .colr_v0_layers = .{ .layer_start = layer_start, .layer_len = layer_len } };
    return .none;
}

fn advanceBefore(glyphs: []const layout.GlyphPosition, count: usize) f32 {
    var width: f32 = 0;
    for (glyphs[0..@min(count, glyphs.len)]) |glyph| {
        width += glyph.x_advance;
    }
    return width;
}

test "render bridge builds glyph draw commands and deduplicated requests" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{
        .origin_x = 5,
        .origin_y = 7,
        .cursor_position = .{ .glyph_index = 1, .cluster = 1 },
        .selection_start_glyph = 0,
        .selection_end_glyph = 2,
    });
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.runs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.atlas_requests.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.path_requests.len);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), draw_list.atlas_requests[0].glyph_id);
    const atlas_key = draw_list.atlas_requests[0].cacheKey();
    try std.testing.expectEqual(@intFromPtr(&font), atlas_key.font_addr);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), atlas_key.glyph_id);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 20))), atlas_key.font_size_bits);
    try std.testing.expect(atlas_key.palette_index == null);
    try std.testing.expectEqual(GlyphRenderMode.atlas_mask, atlas_key.render_mode);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), draw_list.glyphs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), draw_list.glyphs[0].baseline_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 19.0), draw_list.glyphs[1].x, 0.001);
    try std.testing.expect(draw_list.cursor != null);
    try std.testing.expectEqual(@as(usize, 1), draw_list.selection.len);
}

test "render bridge carries slug analytic render mode metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{
        .render_mode = .slug_analytic,
        .include_path_requests = true,
    });
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectEqual(GlyphRenderMode.slug_analytic, draw_list.glyphs[0].render_mode);
    try std.testing.expect(draw_list.glyphs[0].path_request_index != null);
    try std.testing.expectEqual(GlyphRenderMode.slug_analytic, draw_list.runs[0].render_mode);
    try std.testing.expectEqual(GlyphRenderMode.slug_analytic, draw_list.atlas_requests[0].render_mode);
    try std.testing.expectEqual(GlyphRenderMode.slug_analytic, draw_list.path_requests[0].render_mode);
    try std.testing.expectEqual(@as(usize, 0), draw_list.path_requests[0].source.glyph_index);
    try std.testing.expectEqual(@as(u21, 'A'), draw_list.path_requests[0].source.codepoint);
    try std.testing.expectEqual(@as(usize, 0), draw_list.path_requests[0].source.cluster);
    const key = draw_list.path_requests[0].cacheKey();
    try std.testing.expectEqual(@intFromPtr(&font), key.font_addr);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), key.glyph_id);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 20))), key.font_size_bits);
    try std.testing.expectEqual(GlyphRenderMode.slug_analytic, key.render_mode);
}

test "render bridge emits color glyph layer metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), draw_list.color_layers.len);
    try std.testing.expect(draw_list.glyphs[0].color_glyph_index != null);
    try std.testing.expectEqual(@as(usize, 0), draw_list.color_glyphs[0].paint.colr_v0_layers.layer_start);
    try std.testing.expectEqual(@as(usize, 2), draw_list.color_glyphs[0].paint.colr_v0_layers.layer_len);
    try std.testing.expectEqual(@as(u16, 0), draw_list.color_layers[0].palette_index);
    try std.testing.expectEqual(@as(u8, 255), draw_list.color_layers[0].color.?.red);
    try std.testing.expectEqual(@as(u8, 255), draw_list.color_layers[1].color.?.blue);
}

test "render bridge emits COLR v1 paint metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    try std.testing.expect(draw_list.color_glyphs[0].has_colr_v1_paint);
    try std.testing.expectEqual(@as(u16, 0), draw_list.color_glyphs[0].paint.colr_v1_solid.palette_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), draw_list.color_glyphs[0].paint.colr_v1_solid.alpha, 0.001);
}

test "render bridge emits COLR v1 PaintGlyph metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1GlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    try std.testing.expect(draw_list.color_glyphs[0].has_colr_v1_paint);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), draw_list.color_glyphs[0].paint.colr_v1_glyph.glyph_id);
    try std.testing.expectEqual(@as(u16, 0), draw_list.color_glyphs[0].paint.colr_v1_glyph.solid.palette_index);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), draw_list.color_glyphs[0].paint.colr_v1_glyph.solid.alpha, 0.001);
}

test "render bridge emits COLR v1 PaintColrLayers metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1LayersTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    try std.testing.expect(draw_list.color_glyphs[0].has_colr_v1_paint);
    try std.testing.expectEqual(@as(u8, 2), draw_list.color_glyphs[0].paint.colr_v1_layers.layer_count);
    try std.testing.expectEqual(@as(u32, 0), draw_list.color_glyphs[0].paint.colr_v1_layers.first_layer_index);
}
