const std = @import("std");
const font_raster = @import("font.zig").raster_backend;
const font_mod = @import("font.zig");
const glyph_mod = @import("glyph.zig");
const layout = @import("layout.zig");

pub const GlyphRenderMode = enum {
    atlas_mask,
    path_outline,
    slug_analytic,
};

/// Pixel contract for a glyph atlas entry.
///
/// Outline and COLR layer requests produce one-channel coverage. Embedded PNG
/// glyphs already contain color and alpha, so consumers must allocate and cache
/// them separately as premultiplied RGBA instead of interpreting their bytes as
/// an alpha mask.
pub const GlyphAtlasContent = enum {
    alpha_mask,
    premultiplied_rgba,
};

pub const BridgeOptions = struct {
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    palette_index: u16 = 0,
    normalized_variation_coords: []const f32 = &.{},
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
    variation_hash: u64 = 0,
    variation_coord_count: usize = 0,
    render_mode: GlyphRenderMode,
    content: GlyphAtlasContent = .alpha_mask,
};

pub const GlyphAtlasRequest = struct {
    font: *const font_mod.Font,
    glyph_id: glyph_mod.GlyphId,
    font_size: f32,
    palette_index: ?u16 = null,
    normalized_variation_coords: []const f32 = &.{},
    variation_hash: u64 = 0,
    render_mode: GlyphRenderMode = .atlas_mask,
    content: GlyphAtlasContent = .alpha_mask,

    pub fn cacheKey(self: GlyphAtlasRequest) GlyphAtlasCacheKey {
        return .{
            .font_addr = @intFromPtr(self.font),
            .glyph_id = self.glyph_id,
            .font_size_bits = @bitCast(self.font_size),
            .palette_index = self.palette_index,
            .variation_hash = self.variation_hash,
            .variation_coord_count = self.normalized_variation_coords.len,
            .render_mode = self.render_mode,
            .content = self.content,
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
    variation_hash: u64 = 0,
    variation_coord_count: usize = 0,
    render_mode: GlyphRenderMode,
};

pub const GlyphPathRequest = struct {
    font: *const font_mod.Font,
    glyph_id: glyph_mod.GlyphId,
    font_size: f32,
    normalized_variation_coords: []const f32 = &.{},
    variation_hash: u64 = 0,
    render_mode: GlyphRenderMode = .path_outline,
    source: GlyphPathSource = .{ .glyph_index = 0, .codepoint = 0, .cluster = 0 },

    pub fn cacheKey(self: GlyphPathRequest) GlyphPathCacheKey {
        return .{
            .font_addr = @intFromPtr(self.font),
            .glyph_id = self.glyph_id,
            .font_size_bits = @bitCast(self.font_size),
            .variation_hash = self.variation_hash,
            .variation_coord_count = self.normalized_variation_coords.len,
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
    colr_v1_colr_glyph: font_mod.ColorPaint.ColrGlyph,
    colr_v1_layers: font_mod.ColorPaint.Layers,
    colr_v1_linear_gradient: font_mod.ColorPaint.LinearGradient,
    colr_v1_radial_gradient: font_mod.ColorPaint.RadialGradient,
    colr_v1_sweep_gradient: font_mod.ColorPaint.SweepGradient,
    colr_v1_transform: font_mod.ColorPaint.TransformPaint,
    colr_v1_composite: font_mod.ColorPaint.Composite,
    svg_document: []const u8,
    embedded_png: font_mod.BitmapGlyphPng,
};

pub const ColorGlyphDrawCommand = struct {
    glyph_index: usize,
    layer_start: usize,
    layer_len: usize,
    color_stop_start: usize = 0,
    color_stop_len: usize = 0,
    svg_document: ?[]const u8 = null,
    owns_svg_document: bool = false,
    embedded_png: ?font_mod.BitmapGlyphPng = null,
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
    color_stops: []font_mod.ColorPaint.ColorStop,
    normalized_variation_coords: []f32,
    cursor: ?TextCursorGeometry,
    selection: []TextSelectionGeometry,

    pub fn deinit(self: *GlyphDrawList) void {
        self.allocator.free(self.selection);
        self.allocator.free(self.normalized_variation_coords);
        self.allocator.free(self.color_stops);
        self.allocator.free(self.color_layers);
        for (self.color_glyphs) |command| {
            if (command.owns_svg_document) self.allocator.free(command.svg_document.?);
        }
        self.allocator.free(self.color_glyphs);
        self.allocator.free(self.path_requests);
        self.allocator.free(self.atlas_requests);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        self.* = undefined;
    }
};

pub fn buildGlyphDrawList(allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, options: BridgeOptions) !GlyphDrawList {
    for (options.normalized_variation_coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) return error.BadSfnt;
    }
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
    color_stops: std.ArrayList(font_mod.ColorPaint.ColorStop) = .empty,
    selection: std.ArrayList(TextSelectionGeometry) = .empty,
    cursor: ?TextCursorGeometry = null,
    variation_hash: u64,

    fn init(allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, options: BridgeOptions) BridgeBuilder {
        return .{
            .allocator = allocator,
            .paragraph = paragraph,
            .options = options,
            .variation_hash = normalizedVariationHash(options.normalized_variation_coords),
        };
    }

    fn deinitScratch(self: *BridgeBuilder) void {
        self.selection.deinit(self.allocator);
        self.color_stops.deinit(self.allocator);
        self.color_layers.deinit(self.allocator);
        for (self.color_glyphs.items) |command| {
            if (command.owns_svg_document) self.allocator.free(command.svg_document.?);
        }
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
            const color_index: ?usize = if (self.options.include_color_glyphs)
                try self.appendColorGlyph(run.font, run.font_size, glyph.glyph_id, output_index)
            else
                null;
            const embedded_png = if (color_index) |index| self.color_glyphs.items[index].embedded_png else null;
            const atlas_content: GlyphAtlasContent = if (embedded_png != null) .premultiplied_rgba else .alpha_mask;
            const atlas_index: ?usize = if (run.font.hasOutlineData() or embedded_png != null)
                try self.atlasRequestIndex(.{
                    .font = run.font,
                    .glyph_id = glyph.glyph_id,
                    .font_size = run.font_size,
                    .normalized_variation_coords = self.options.normalized_variation_coords,
                    .variation_hash = self.variation_hash,
                    .render_mode = self.options.render_mode,
                    .content = atlas_content,
                })
            else
                null;
            var path_index: ?usize = null;
            // A bitmap-only face has no path source. Suppress path requests for
            // both its color images and intentionally empty spacing glyphs so a
            // backend cannot accidentally turn a valid draw list into a
            // MissingTable error while preparing optional vector fallbacks.
            if (self.options.include_path_requests and run.font.hasOutlineData()) {
                path_index = try self.pathRequestIndex(.{
                    .font = run.font,
                    .glyph_id = glyph.glyph_id,
                    .font_size = run.font_size,
                    .normalized_variation_coords = self.options.normalized_variation_coords,
                    .variation_hash = self.variation_hash,
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
                .color_glyph_index = color_index,
            });
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
                .normalized_variation_coords = self.options.normalized_variation_coords,
                .variation_hash = self.variation_hash,
                .render_mode = self.options.render_mode,
            });
            try self.color_layers.append(self.allocator, .{
                .glyph_id = layer.glyph_id,
                .palette_index = layer.palette_index,
                .color = try font.paletteColor(self.options.palette_index, layer.palette_index),
                .atlas_request_index = atlas_index,
            });
        }

        const color_paint = try font.colorPaintAtCoords(glyph_id, self.options.normalized_variation_coords);
        // COLR has priority over SVG. Avoid decoding a lower-priority gzip SVG
        // document when the same glyph already selected a COLR source.
        var resolved_svg = if (layer_start == self.color_layers.items.len and color_paint == null)
            try font_raster.resolvedSvgGlyphDocument(font, self.allocator, glyph_id)
        else
            null;
        defer if (resolved_svg) |*document| document.deinit();
        const svg_document = if (resolved_svg) |document| document.data else null;
        const color_stop_start = self.color_stops.items.len;
        if (color_paint) |paint| {
            if (colorPaintLine(paint)) |color_line| {
                const resolved = try font.colorStopsAtCoords(self.allocator, color_line, self.options.normalized_variation_coords);
                defer self.allocator.free(resolved);
                try self.color_stops.appendSlice(self.allocator, resolved);
            }
        }
        const layer_len = self.color_layers.items.len - layer_start;
        // Match Rasterizer precedence. A font may carry several color
        // representations, but the command identifies exactly the source a
        // renderer should consume rather than exposing a lower-priority PNG as
        // if it were additional paint.
        const selected_svg = if (layer_len == 0 and color_paint == null) svg_document else null;
        const selected_png = if (layer_len == 0 and color_paint == null and selected_svg == null)
            try font.bitmapGlyphPng(glyph_id, font_size)
        else
            null;
        if (layer_len == 0 and selected_svg == null and color_paint == null and selected_png == null) return null;

        const color_index = self.color_glyphs.items.len;
        try self.color_glyphs.append(self.allocator, .{
            .glyph_index = glyph_index,
            .layer_start = layer_start,
            .layer_len = layer_len,
            .color_stop_start = color_stop_start,
            .color_stop_len = self.color_stops.items.len - color_stop_start,
            .svg_document = selected_svg,
            .embedded_png = selected_png,
            .has_colr_v1_paint = color_paint != null,
            .paint = colorGlyphPaint(layer_start, layer_len, selected_svg, color_paint, selected_png),
        });
        // Appending the command is the only fallible operation after selecting
        // the document. Transfer gzip ownership only after that succeeds so an
        // allocation failure still leaves the resolved handle responsible for
        // freeing its decoded buffer.
        if (selected_svg != null) {
            if (resolved_svg) |*document| {
                if (document.takeOwnedData() != null) {
                    self.color_glyphs.items[color_index].owns_svg_document = true;
                }
            }
        }
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
            if (existing.font == request.font and
                existing.glyph_id == request.glyph_id and
                existing.font_size == request.font_size and
                existing.variation_hash == request.variation_hash and
                variationCoordinatesEqual(existing.normalized_variation_coords, request.normalized_variation_coords) and
                existing.render_mode == request.render_mode)
            {
                return index;
            }
        }
        try self.path_requests.append(self.allocator, request);
        return self.path_requests.items.len - 1;
    }

    fn toOwnedList(self: *BridgeBuilder) !GlyphDrawList {
        const normalized_variation_coords = try self.allocator.dupe(f32, self.options.normalized_variation_coords);
        errdefer self.allocator.free(normalized_variation_coords);
        const glyphs = try self.glyphs.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(glyphs);
        const runs = try self.runs.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(runs);
        const atlas_requests = try self.atlas_requests.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(atlas_requests);
        const path_requests = try self.path_requests.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(path_requests);
        const color_glyphs = try self.color_glyphs.toOwnedSlice(self.allocator);
        errdefer {
            for (color_glyphs) |command| {
                if (command.owns_svg_document) self.allocator.free(command.svg_document.?);
            }
            self.allocator.free(color_glyphs);
        }
        const color_layers = try self.color_layers.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(color_layers);
        const color_stops = try self.color_stops.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(color_stops);
        const selection = try self.selection.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(selection);
        const result = GlyphDrawList{
            .allocator = self.allocator,
            .glyphs = glyphs,
            .runs = runs,
            .atlas_requests = atlas_requests,
            .path_requests = path_requests,
            .color_glyphs = color_glyphs,
            .color_layers = color_layers,
            .color_stops = color_stops,
            .normalized_variation_coords = normalized_variation_coords,
            .cursor = self.cursor,
            .selection = selection,
        };
        // Requests live as long as the draw list, not as long as the caller's
        // BridgeOptions. Rebind every borrowed location to the single owned
        // coordinate copy after all request slices have reached stable storage.
        for (result.atlas_requests) |*request| request.normalized_variation_coords = normalized_variation_coords;
        for (result.path_requests) |*request| request.normalized_variation_coords = normalized_variation_coords;
        return result;
    }
};

fn colorPaintLine(paint: font_mod.ColorPaint) ?font_mod.ColorPaint.ColorLine {
    return switch (paint) {
        .linear_gradient => |gradient| gradient.color_line,
        .radial_gradient => |gradient| gradient.color_line,
        .sweep_gradient => |gradient| gradient.color_line,
        .glyph => |glyph_paint| switch (glyph_paint.brush) {
            .linear_gradient => |gradient| gradient.color_line,
            .radial_gradient => |gradient| gradient.color_line,
            .sweep_gradient => |gradient| gradient.color_line,
            .solid => null,
        },
        .solid, .clip_glyph, .colr_glyph, .layers, .transform, .composite => null,
    };
}

fn colorPaintTransform(paint: font_mod.ColorPaint) ?font_mod.ColorAffine {
    return switch (paint) {
        .transform => |transform| transform.affine,
        else => null,
    };
}

fn sameAtlasRequest(a: GlyphAtlasRequest, b: GlyphAtlasRequest) bool {
    return a.font == b.font and
        a.glyph_id == b.glyph_id and
        a.font_size == b.font_size and
        a.palette_index == b.palette_index and
        a.variation_hash == b.variation_hash and
        variationCoordinatesEqual(a.normalized_variation_coords, b.normalized_variation_coords) and
        a.render_mode == b.render_mode and
        a.content == b.content;
}

fn variationCoordinatesEqual(a: []const f32, b: []const f32) bool {
    return a.len == b.len and std.mem.eql(u8, std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));
}

fn normalizedVariationHash(coords: []const f32) u64 {
    var has_non_default = false;
    for (coords) |coord| {
        if (coord != 0) {
            has_non_default = true;
            break;
        }
    }
    if (!has_non_default) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&coords.len));
    for (coords) |coord| {
        const bits: u32 = @bitCast(coord);
        hasher.update(std.mem.asBytes(&bits));
    }
    return hasher.final();
}

fn pathRequestMode(render_mode: GlyphRenderMode) GlyphRenderMode {
    return switch (render_mode) {
        .atlas_mask => .path_outline,
        .path_outline => .path_outline,
        .slug_analytic => .slug_analytic,
    };
}

fn colorGlyphPaint(
    layer_start: usize,
    layer_len: usize,
    svg_document: ?[]const u8,
    color_paint: ?font_mod.ColorPaint,
    embedded_png: ?font_mod.BitmapGlyphPng,
) ColorGlyphPaint {
    if (color_paint) |paint| {
        return switch (paint) {
            .solid => |solid| .{ .colr_v1_solid = solid },
            .glyph => |glyph| .{ .colr_v1_glyph = glyph },
            .clip_glyph => .none,
            .colr_glyph => |glyph| .{ .colr_v1_colr_glyph = glyph },
            .layers => |layers| .{ .colr_v1_layers = layers },
            .linear_gradient => |gradient| .{ .colr_v1_linear_gradient = gradient },
            .radial_gradient => |gradient| .{ .colr_v1_radial_gradient = gradient },
            .sweep_gradient => |gradient| .{ .colr_v1_sweep_gradient = gradient },
            .transform => |transform| .{ .colr_v1_transform = transform },
            .composite => |composite| .{ .colr_v1_composite = composite },
        };
    }
    if (layer_len > 0) return .{ .colr_v0_layers = .{ .layer_start = layer_start, .layer_len = layer_len } };
    if (svg_document) |document| return .{ .svg_document = document };
    if (embedded_png) |png| return .{ .embedded_png = png };
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
    try std.testing.expectEqual(GlyphAtlasContent.alpha_mask, atlas_key.content);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), draw_list.glyphs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), draw_list.glyphs[0].baseline_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), draw_list.glyphs[1].x, 0.001);
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

test "render bridge owns decoded gzip SVG documents" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildGzipSvgTtf(allocator);
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
    const command = draw_list.color_glyphs[0];
    try std.testing.expect(command.owns_svg_document);
    try std.testing.expect(std.mem.startsWith(u8, command.svg_document.?, "<svg"));
    try std.testing.expect(std.mem.indexOf(u8, command.svg_document.?, "<rect") != null);
    try std.testing.expectEqualSlices(u8, command.svg_document.?, command.paint.svg_document);
}

test "render bridge emits embedded PNG color atlas metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect(!font.hasOutlineData());

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
        .max_width = 100,
        .line_height = 20,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.atlas_requests.len);
    try std.testing.expectEqual(@as(usize, 0), draw_list.path_requests.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    try std.testing.expectEqual(@as(?usize, 0), draw_list.glyphs[0].atlas_request_index);
    try std.testing.expectEqual(@as(?usize, null), draw_list.glyphs[0].path_request_index);
    try std.testing.expectEqual(@as(?usize, 0), draw_list.glyphs[0].color_glyph_index);

    const atlas_request = draw_list.atlas_requests[0];
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, atlas_request.content);
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, atlas_request.cacheKey().content);
    const command = draw_list.color_glyphs[0];
    const bitmap = command.embedded_png orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(font_mod.BitmapStrikeSource.cblc_cbdt, bitmap.source);
    try std.testing.expectEqual(@as(u16, 16), bitmap.ppem);
    try std.testing.expectEqual(@as(u32, 1), bitmap.width);
    try std.testing.expectEqual(@as(u32, 1), bitmap.height);
    try std.testing.expect(command.svg_document == null);
    try std.testing.expect(!command.has_colr_v1_paint);
    try std.testing.expectEqual(bitmap, command.paint.embedded_png);
}

test "render bridge resolves sbix dupe records before atlas emission" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildSbixDupePngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
        .max_width = 100,
        .line_height = 20,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    const bitmap = draw_list.color_glyphs[0].paint.embedded_png;
    try std.testing.expectEqual(font_mod.BitmapStrikeSource.sbix, bitmap.source);
    try std.testing.expectEqual(@as(i16, 3), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, -2), bitmap.origin_offset_y);
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, draw_list.atlas_requests[0].content);
}

test "render bridge preserves CBDT format 19 shared metrics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCbdtFormat19PngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
        .max_width = 100,
        .line_height = 20,
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    const bitmap = draw_list.color_glyphs[0].paint.embedded_png;
    try std.testing.expectEqual(font_mod.BitmapStrikeSource.cblc_cbdt, bitmap.source);
    try std.testing.expectEqual(@as(i16, 4), bitmap.origin_offset_x);
    try std.testing.expectEqual(@as(i16, 11), bitmap.origin_offset_y);
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, draw_list.atlas_requests[0].content);
}

test "render bridge skips atlas and path work for empty bitmap-only glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]layout.GlyphPosition{.{
        .glyph_id = 0,
        .codepoint = ' ',
        .cluster = 0,
        .x_advance = 8,
    }};
    const runs = [_]layout.CascadeRun{.{
        .font = &font,
        .font_index = 0,
        .font_size = 16,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    }};
    const lines = [_]layout.ParagraphLine{.{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 1,
        .x = 0,
        .y = 0,
        .width = 8,
        .height = 20,
        .baseline = 16,
        .ascent = 16,
        .descent = 4,
        .leading = 0,
    }};
    const paragraph = layout.ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &runs,
        .lines = &lines,
        .width = 8,
        .height = 20,
    };

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), draw_list.atlas_requests.len);
    try std.testing.expectEqual(@as(usize, 0), draw_list.path_requests.len);
    try std.testing.expectEqual(@as(usize, 0), draw_list.color_glyphs.len);
    try std.testing.expect(draw_list.glyphs[0].atlas_request_index == null);
    try std.testing.expect(draw_list.glyphs[0].path_request_index == null);
    try std.testing.expect(draw_list.glyphs[0].color_glyph_index == null);
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
    const glyph_paint = draw_list.color_glyphs[0].paint.colr_v1_glyph;
    switch (glyph_paint.brush) {
        .solid => |solid| {
            try std.testing.expectEqual(@as(u16, 0), solid.palette_index);
            try std.testing.expectApproxEqAbs(@as(f32, 1.0), solid.alpha, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }
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

test "render bridge resolves variable COLR paint and color stops" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1VariableLinearGradientTtf(allocator);
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
        .normalized_variation_coords = &.{0.5},
    });

    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{
        .normalized_variation_coords = &.{0.5},
    });
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    const command = draw_list.color_glyphs[0];
    try std.testing.expectEqual(@as(usize, 0), command.color_stop_start);
    try std.testing.expectEqual(@as(usize, 2), command.color_stop_len);
    const expected_variation_hash = normalizedVariationHash(&.{0.5});
    try std.testing.expectEqual(expected_variation_hash, draw_list.atlas_requests[0].variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.path_requests[0].variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.atlas_requests[0].cacheKey().variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.path_requests[0].cacheKey().variation_hash);
    try std.testing.expectEqual(@as(usize, 1), draw_list.atlas_requests[0].cacheKey().variation_coord_count);
    try std.testing.expectEqual(@as(usize, 1), draw_list.path_requests[0].cacheKey().variation_coord_count);
    try std.testing.expectEqual(@as(f32, 0.5), draw_list.normalized_variation_coords[0]);
    try std.testing.expectEqual(draw_list.normalized_variation_coords.ptr, draw_list.atlas_requests[0].normalized_variation_coords.ptr);
    try std.testing.expectEqual(draw_list.normalized_variation_coords.ptr, draw_list.path_requests[0].normalized_variation_coords.ptr);
    const gradient = command.paint.colr_v1_glyph.brush.linear_gradient;
    try std.testing.expectEqual(@as(f32, 100), gradient.p0.x);
    try std.testing.expectEqual(@as(f32, 600), gradient.p1.x);
    try std.testing.expectEqual(@as(f32, 0.25), draw_list.color_stops[0].offset);
    try std.testing.expectEqual(@as(u16, 1), draw_list.color_stops[0].palette_index);
    try std.testing.expectEqual(@as(f32, 0.75), draw_list.color_stops[1].offset);
    try std.testing.expectEqual(@as(u16, 0), draw_list.color_stops[1].palette_index);
    try std.testing.expectEqual(@as(f32, 0.5), draw_list.color_stops[1].alpha);
}

test "render bridge variation cache identity preserves coordinates" {
    try std.testing.expectEqual(@as(u64, 0), normalizedVariationHash(&.{}));
    try std.testing.expectEqual(@as(u64, 0), normalizedVariationHash(&.{ 0, 0 }));
    try std.testing.expect(normalizedVariationHash(&.{0.5}) != 0);
    try std.testing.expect(normalizedVariationHash(&.{0.5}) != normalizedVariationHash(&.{0.25}));

    const font_ptr: *const font_mod.Font = @ptrFromInt(4096);
    const a = GlyphAtlasRequest{
        .font = font_ptr,
        .glyph_id = 1,
        .font_size = 20,
        .normalized_variation_coords = &.{0.5},
        .variation_hash = normalizedVariationHash(&.{0.5}),
    };
    var b = a;
    b.normalized_variation_coords = &.{0.25};
    b.variation_hash = normalizedVariationHash(&.{0.25});
    try std.testing.expect(!sameAtlasRequest(a, b));
    try std.testing.expect(a.cacheKey().variation_hash != b.cacheKey().variation_hash);

    var rgba = a;
    rgba.content = .premultiplied_rgba;
    try std.testing.expect(!sameAtlasRequest(a, rgba));
    try std.testing.expectEqual(GlyphAtlasContent.alpha_mask, a.cacheKey().content);
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, rgba.cacheKey().content);
}

test "render bridge rejects invalid variation coordinates" {
    const empty = layout.ParagraphLayout{
        .glyphs = &.{},
        .runs = &.{},
        .lines = &.{},
        .width = 0,
        .height = 0,
    };
    try std.testing.expectError(error.BadSfnt, buildGlyphDrawList(std.testing.allocator, empty, .{
        .normalized_variation_coords = &.{1.01},
    }));
}

test "render bridge exposes variable COLR transform metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildColorV1VariableTransformTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const paint = (try font.colorPaintAtCoords(1, &.{0.5})).?;
    const affine = colorPaintTransform(paint).?;
    try std.testing.expectEqual(@as(f32, 100), affine.dx);
    try std.testing.expectEqual(@as(f32, 50), affine.dy);
    const bridge_paint = colorGlyphPaint(0, 0, null, paint, null);
    try std.testing.expectEqual(@as(f32, 100), bridge_paint.colr_v1_transform.affine.dx);
}
