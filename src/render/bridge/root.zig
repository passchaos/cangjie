//! Renderer-facing glyph draw-list construction.

const std = @import("std");
const face_mod = @import("../../font/face/root.zig");
const font_raster = @import("../../font.zig").raster_backend;
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");
const glyph_position = @import("../../layout/glyph_position.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const run_types = @import("../../layout/types/runs.zig");

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
    cursor_position: ?paragraph_types.TextPosition = null,
    selection_start_glyph: ?usize = null,
    selection_end_glyph: ?usize = null,
    /// Optional attributed decoration geometry in paragraph coordinates.
    decorations: []const TextDecorationDrawCommand = &.{},
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
    font: *const face_mod.Face,
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
    font: *const face_mod.Face,
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
    font: *const face_mod.Face,
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
    font: *const face_mod.Face,
    font_size: f32,
    normalized_variation_coords: []const f32 = &.{},
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
    rect: paragraph_types.TextRect,
    position: paragraph_types.TextPosition,
};

pub const TextSelectionGeometry = struct {
    rect: paragraph_types.TextRect,
};

pub const InlineObjectDrawCommand = inline_object.Positioned;
pub const TextDecorationDrawCommand =
    @import("../../text/attributed/decorations.zig").Segment;

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
    inline_objects: []InlineObjectDrawCommand,
    decorations: []TextDecorationDrawCommand,

    pub fn deinit(self: *GlyphDrawList) void {
        self.allocator.free(self.decorations);
        self.allocator.free(self.inline_objects);
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

pub fn buildGlyphDrawList(allocator: std.mem.Allocator, paragraph: paragraph_types.ParagraphLayout, options: BridgeOptions) !GlyphDrawList {
    if (!std.math.isFinite(options.origin_x) or
        !std.math.isFinite(options.origin_y))
    {
        return error.InvalidRenderOrigin;
    }
    for (options.normalized_variation_coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) return error.BadSfnt;
    }
    for (options.decorations) |decoration| {
        if (decoration.line_index >= paragraph.lines.len or
            decoration.font_run_index >= paragraph.runs.len or
            !std.math.isFinite(decoration.rect.x) or
            !std.math.isFinite(decoration.rect.y) or
            !std.math.isFinite(decoration.rect.width) or
            !std.math.isFinite(decoration.rect.height) or
            decoration.rect.width < 0 or decoration.rect.height < 0)
        {
            return error.InvalidDecorationGeometry;
        }
    }
    var builder = BridgeBuilder.init(allocator, paragraph, options);
    defer builder.deinitScratch();
    try builder.build();
    return try builder.toOwnedList();
}

const BridgeBuilder = struct {
    allocator: std.mem.Allocator,
    paragraph: paragraph_types.ParagraphLayout,
    options: BridgeOptions,
    glyphs: std.ArrayList(PositionedGlyph) = .empty,
    runs: std.ArrayList(GlyphRunDrawCommand) = .empty,
    atlas_requests: std.ArrayList(GlyphAtlasRequest) = .empty,
    path_requests: std.ArrayList(GlyphPathRequest) = .empty,
    color_glyphs: std.ArrayList(ColorGlyphDrawCommand) = .empty,
    color_layers: std.ArrayList(ColorGlyphLayerCommand) = .empty,
    color_stops: std.ArrayList(font_mod.ColorPaint.ColorStop) = .empty,
    selection: std.ArrayList(TextSelectionGeometry) = .empty,
    inline_objects: std.ArrayList(InlineObjectDrawCommand) = .empty,
    decorations: std.ArrayList(TextDecorationDrawCommand) = .empty,
    cursor: ?TextCursorGeometry = null,

    fn init(allocator: std.mem.Allocator, paragraph: paragraph_types.ParagraphLayout, options: BridgeOptions) BridgeBuilder {
        return .{
            .allocator = allocator,
            .paragraph = paragraph,
            .options = options,
        };
    }

    fn deinitScratch(self: *BridgeBuilder) void {
        self.decorations.deinit(self.allocator);
        self.inline_objects.deinit(self.allocator);
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
        try self.decorations.ensureTotalCapacity(
            self.allocator,
            self.options.decorations.len,
        );
        for (self.options.decorations) |decoration| {
            var positioned = decoration;
            positioned.rect.x += self.options.origin_x;
            positioned.rect.y += self.options.origin_y;
            self.decorations.appendAssumeCapacity(positioned);
        }
        try self.inline_objects.ensureTotalCapacity(
            self.allocator,
            self.paragraph.inline_objects.len,
        );
        for (self.paragraph.inline_objects) |object| {
            var positioned = object;
            positioned.x += self.options.origin_x;
            positioned.y += self.options.origin_y;
            positioned.anchor_x += self.options.origin_x;
            positioned.anchor_y += self.options.origin_y;
            self.inline_objects.appendAssumeCapacity(positioned);
        }
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

    fn appendLine(self: *BridgeBuilder, line: paragraph_types.ParagraphLine, line_index: usize) !void {
        const line_glyph_end = line.glyph_start + line.glyph_len;
        for (line.runs(self.paragraph)) |run| {
            const start = @max(line.glyph_start, run.glyph_start);
            const end = @min(line_glyph_end, run.glyph_start + run.glyph_len);
            if (start >= end) continue;
            const command_start = self.glyphs.items.len;
            try self.appendGlyphsInRange(run, start, end, line);
            if (self.glyphs.items.len == command_start) continue;
            try self.runs.append(self.allocator, .{
                .font = run.font,
                .font_size = run.font_size,
                .normalized_variation_coords = runVariationCoords(
                    self.paragraph,
                    run,
                    self.options.normalized_variation_coords,
                ),
                .glyph_start = command_start,
                .glyph_len = self.glyphs.items.len - command_start,
                .x = self.glyphs.items[command_start].x,
                // One style-aligned glyph can have a different baseline from
                // its neighbor inside the same shaping run. The run command's
                // baseline remains the line baseline; each glyph carries the
                // final vertical offset explicitly.
                .baseline_y = self.options.origin_y + line.y + line.baseline,
                .line_index = line_index,
                .render_mode = self.options.render_mode,
            });
        }
    }

    fn appendGlyphsInRange(self: *BridgeBuilder, run: run_types.CascadeRun, start: usize, end: usize, line: paragraph_types.ParagraphLine) !void {
        const font = face_mod.backend.font(run.font);
        const run_variation_coords = runVariationCoords(
            self.paragraph,
            run,
            self.options.normalized_variation_coords,
        );
        const run_variation_hash =
            normalizedVariationHash(run_variation_coords);
        const line_glyph_end = line.glyph_start + line.glyph_len;
        var pen_x = self.options.origin_x + line.x + advanceBefore(self.paragraph.glyphs[line.glyph_start..line_glyph_end], start - line.glyph_start);
        for (self.paragraph.glyphs[start..end]) |glyph| {
            if (glyph.isTab()) {
                // Tabs are source/caret atoms whose advance positions the next
                // field. They do not request a font glyph, even if the active
                // cmap happens to map U+0009 to a visible outline.
                pen_x += glyph.x_advance;
                continue;
            }
            const output_index = self.glyphs.items.len;
            const color_index: ?usize = if (self.options.include_color_glyphs)
                try self.appendColorGlyph(
                    font,
                    run.font_size,
                    glyph.glyph_id,
                    output_index,
                    run_variation_coords,
                    run_variation_hash,
                )
            else
                null;
            const embedded_png = if (color_index) |index| self.color_glyphs.items[index].embedded_png else null;
            const atlas_content: GlyphAtlasContent = if (embedded_png != null) .premultiplied_rgba else .alpha_mask;
            const atlas_index: ?usize = if (font.hasOutlineData() or embedded_png != null)
                try self.atlasRequestIndex(.{
                    .font = run.font,
                    .glyph_id = glyph.glyph_id,
                    .font_size = run.font_size,
                    .normalized_variation_coords = run_variation_coords,
                    .variation_hash = run_variation_hash,
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
            if (self.options.include_path_requests and font.hasOutlineData()) {
                path_index = try self.pathRequestIndex(.{
                    .font = run.font,
                    .glyph_id = glyph.glyph_id,
                    .font_size = run.font_size,
                    .normalized_variation_coords = run_variation_coords,
                    .variation_hash = run_variation_hash,
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
                .baseline_y = self.options.origin_y + line.y + line.baseline,
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

    fn appendColorGlyph(
        self: *BridgeBuilder,
        font: *const font_mod.Font,
        font_size: f32,
        glyph_id: glyph_mod.GlyphId,
        glyph_index: usize,
        variation_coords: []const f32,
        variation_hash: u64,
    ) !?usize {
        const layer_start = self.color_layers.items.len;
        const layers = try font.colorLayers(self.allocator, glyph_id);
        defer self.allocator.free(layers);
        for (layers) |layer| {
            const atlas_index = try self.atlasRequestIndex(.{
                .font = face_mod.backend.face(font),
                .glyph_id = layer.glyph_id,
                .font_size = font_size,
                .palette_index = layer.palette_index,
                .normalized_variation_coords = variation_coords,
                .variation_hash = variation_hash,
                .render_mode = self.options.render_mode,
            });
            try self.color_layers.append(self.allocator, .{
                .glyph_id = layer.glyph_id,
                .palette_index = layer.palette_index,
                .color = try font.paletteColor(self.options.palette_index, layer.palette_index),
                .atlas_request_index = atlas_index,
            });
        }

        const color_paint = try font.colorPaintAtCoords(
            glyph_id,
            variation_coords,
        );
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
                const resolved = try font.colorStopsAtCoords(
                    self.allocator,
                    color_line,
                    variation_coords,
                );
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
        var coord_pool = std.ArrayList(f32).empty;
        defer coord_pool.deinit(self.allocator);
        var atlas_coord_ranges = std.ArrayList(CoordRange).empty;
        defer atlas_coord_ranges.deinit(self.allocator);
        var path_coord_ranges = std.ArrayList(CoordRange).empty;
        defer path_coord_ranges.deinit(self.allocator);
        var run_coord_ranges = std.ArrayList(CoordRange).empty;
        defer run_coord_ranges.deinit(self.allocator);
        try run_coord_ranges.ensureTotalCapacity(
            self.allocator,
            self.runs.items.len,
        );
        for (self.runs.items) |run| {
            run_coord_ranges.appendAssumeCapacity(
                try internCoordRange(
                    &coord_pool,
                    self.allocator,
                    run.normalized_variation_coords,
                ),
            );
        }
        try atlas_coord_ranges.ensureTotalCapacity(
            self.allocator,
            self.atlas_requests.items.len,
        );
        for (self.atlas_requests.items) |request| {
            atlas_coord_ranges.appendAssumeCapacity(
                try internCoordRange(
                    &coord_pool,
                    self.allocator,
                    request.normalized_variation_coords,
                ),
            );
        }
        try path_coord_ranges.ensureTotalCapacity(
            self.allocator,
            self.path_requests.items.len,
        );
        for (self.path_requests.items) |request| {
            path_coord_ranges.appendAssumeCapacity(
                try internCoordRange(
                    &coord_pool,
                    self.allocator,
                    request.normalized_variation_coords,
                ),
            );
        }
        const normalized_variation_coords =
            try coord_pool.toOwnedSlice(self.allocator);
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
        const inline_objects =
            try self.inline_objects.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(inline_objects);
        const decorations =
            try self.decorations.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(decorations);
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
            .inline_objects = inline_objects,
            .decorations = decorations,
        };
        // Requests live as long as the draw list, not as long as paragraph or
        // BridgeOptions storage. Rebind each request to its interned range.
        for (result.atlas_requests, atlas_coord_ranges.items) |*request, range| {
            request.normalized_variation_coords =
                range.slice(normalized_variation_coords);
        }
        for (result.path_requests, path_coord_ranges.items) |*request, range| {
            request.normalized_variation_coords =
                range.slice(normalized_variation_coords);
        }
        for (result.runs, run_coord_ranges.items) |*run, range| {
            run.normalized_variation_coords =
                range.slice(normalized_variation_coords);
        }
        return result;
    }
};

const CoordRange = struct {
    start: usize,
    len: usize,

    fn slice(self: CoordRange, pool: []const f32) []const f32 {
        return pool[self.start .. self.start + self.len];
    }
};

fn internCoordRange(
    pool: *std.ArrayList(f32),
    allocator: std.mem.Allocator,
    coords: []const f32,
) !CoordRange {
    if (coords.len == 0) return .{ .start = 0, .len = 0 };
    var start: usize = 0;
    while (start + coords.len <= pool.items.len) : (start += 1) {
        if (variationCoordinatesEqual(
            pool.items[start..][0..coords.len],
            coords,
        )) {
            return .{ .start = start, .len = coords.len };
        }
    }
    const range_start = pool.items.len;
    try pool.appendSlice(allocator, coords);
    return .{ .start = range_start, .len = coords.len };
}

fn runVariationCoords(
    paragraph: paragraph_types.ParagraphLayout,
    run: run_types.CascadeRun,
    fallback: []const f32,
) []const f32 {
    if (run.variation_coord_len == 0) return fallback;
    const end = run.variation_coord_start + run.variation_coord_len;
    std.debug.assert(end <= paragraph.normalized_variation_coords.len);
    return paragraph.normalized_variation_coords[run.variation_coord_start..end];
}

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

fn advanceBefore(glyphs: []const glyph_position.GlyphPosition, count: usize) f32 {
    var width: f32 = 0;
    for (glyphs[0..@min(count, glyphs.len)]) |glyph| {
        width += glyph.x_advance;
    }
    return width;
}

test {
    _ = @import("tests.zig");
}
