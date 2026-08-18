//! Paragraph overlay records and geometry construction.

const std = @import("std");
const glyph_position = @import("../layout/glyph_position.zig");
const axes = @import("../layout/paragraph/axes.zig");
const paragraph_types = @import("../layout/types/paragraph.zig");
const run_geometry = @import("../render/run_geometry.zig");
const unicode = @import("../unicode.zig");

pub const OverlayKind = enum {
    baseline,
    line_box,
    glyph_box,
    cluster_boundary,
    cursor_rect,
    selection_rect,
    fallback_font_region,
    bidi_run,
};

pub const DebugOverlay = struct {
    kind: OverlayKind,
    rect: paragraph_types.TextRect,
    line_start_x: f32 = 0,
    line_start_y: f32 = 0,
    line_end_x: f32 = 0,
    line_end_y: f32 = 0,
    byte_start: usize = 0,
    byte_end: usize = 0,
    label_index: usize = 0,
};

pub const DebugOverlayList = struct {
    allocator: std.mem.Allocator,
    items: []DebugOverlay,

    pub fn deinit(self: *DebugOverlayList) void {
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OverlayOptions = struct {
    cursor: ?paragraph_types.TextPosition = null,
    selection_start_glyph: ?usize = null,
    selection_end_glyph: ?usize = null,
    bidi_text: ?[]const u8 = null,
    bidi_base_direction: unicode.BidiClass = .ltr,
};
pub fn buildDebugOverlays(allocator: std.mem.Allocator, paragraph: paragraph_types.ParagraphLayout, options: OverlayOptions) !DebugOverlayList {
    var overlays = std.ArrayList(DebugOverlay).empty;
    errdefer overlays.deinit(allocator);

    for (paragraph.lines, 0..) |line, index| {
        try overlays.append(allocator, .{
            .kind = .line_box,
            .rect = .{ .x = line.x, .y = line.y, .width = line.width, .height = line.height },
            .label_index = index,
        });
        const baseline = if (paragraph.writing_mode.isVertical())
            paragraph_types.TextRect{
                .x = line.x + line.baseline,
                .y = line.y,
                .width = 0,
                .height = line.height,
            }
        else
            paragraph_types.TextRect{
                .x = line.x,
                .y = line.y + line.baseline,
                .width = line.width,
                .height = 0,
            };
        try overlays.append(allocator, .{
            .kind = .baseline,
            .rect = baseline,
            .line_start_x = baseline.x,
            .line_start_y = baseline.y,
            .line_end_x = baseline.x + baseline.width,
            .line_end_y = baseline.y + baseline.height,
            .label_index = index,
        });
        try appendGlyphAndClusterOverlays(allocator, &overlays, paragraph, line, index);
        try appendFallbackRegionOverlays(allocator, &overlays, paragraph, line, index);
    }

    if (options.cursor) |position| {
        try overlays.append(allocator, .{
            .kind = .cursor_rect,
            .rect = paragraph.caretRect(position),
        });
    }

    if (options.selection_start_glyph != null and options.selection_end_glyph != null) {
        const rects = try paragraph.selectionRects(allocator, options.selection_start_glyph.?, options.selection_end_glyph.?);
        defer allocator.free(rects);
        for (rects, 0..) |rect, index| {
            try overlays.append(allocator, .{
                .kind = .selection_rect,
                .rect = rect,
                .label_index = index,
            });
        }
    }

    if (options.bidi_text) |text| {
        const runs = try unicode.itemizeBidiRuns(allocator, text, options.bidi_base_direction);
        defer allocator.free(runs);
        for (runs, 0..) |run, index| {
            try overlays.append(allocator, .{
                .kind = .bidi_run,
                .rect = .{ .x = 0, .y = @floatFromInt(index), .width = @floatFromInt(run.byte_len), .height = 1 },
                .byte_start = run.byte_start,
                .byte_end = run.byte_start + run.byte_len,
                .label_index = index,
            });
        }
    }

    return .{
        .allocator = allocator,
        .items = try overlays.toOwnedSlice(allocator),
    };
}

fn appendGlyphAndClusterOverlays(allocator: std.mem.Allocator, overlays: *std.ArrayList(DebugOverlay), paragraph: paragraph_types.ParagraphLayout, line: paragraph_types.ParagraphLine, line_index: usize) !void {
    var pen = if (paragraph.writing_mode.isVertical())
        run_geometry.Pen.init(line.x + line.baseline, line.y)
    else
        run_geometry.Pen.init(line.x, line.y + line.baseline);
    const glyph_end = line.glyph_start + line.glyph_len;
    var previous_cluster: ?usize = null;
    for (paragraph.glyphs[line.glyph_start..glyph_end], line.glyph_start..) |glyph, glyph_index| {
        if (previous_cluster == null or previous_cluster.? != glyph.cluster) {
            const boundary = axes.caretRect(
                paragraph.writing_mode,
                axes.blockStart(paragraph.writing_mode, axes.rect(line.x, line.y, line.width, line.height)),
                axes.blockSize(paragraph.writing_mode, axes.rect(line.x, line.y, line.width, line.height)),
                axes.inlineCoordinate(
                    paragraph.writing_mode,
                    pen.x,
                    pen.baseline_y,
                ),
            );
            try overlays.append(allocator, .{
                .kind = .cluster_boundary,
                .rect = boundary,
                .line_start_x = boundary.x,
                .line_start_y = boundary.y,
                .line_end_x = boundary.x + boundary.width,
                .line_end_y = boundary.y + boundary.height,
                .byte_start = glyph.cluster,
                .byte_end = glyph.cluster,
                .label_index = glyph_index,
            });
            previous_cluster = glyph.cluster;
        }
        const origin = pen.glyphOrigin(glyph);
        try overlays.append(allocator, .{
            .kind = .glyph_box,
            .rect = if (paragraph.writing_mode.isVertical())
                .{
                    .x = line.x,
                    .y = pen.baseline_y,
                    .width = line.width,
                    .height = glyph.y_advance,
                }
            else
                .{
                    .x = origin.x,
                    .y = line.y + line.baseline - line.ascent +
                        glyph.y_offset,
                    .width = glyph.x_advance,
                    .height = line.ascent + line.descent,
                },
            .byte_start = glyph.cluster,
            .byte_end = glyph.cluster,
            .label_index = glyph_index,
        });
        pen.advance(glyph);
    }
    const inline_end = axes.inlineCoordinate(
        paragraph.writing_mode,
        pen.x,
        pen.baseline_y,
    );
    const boundary = axes.caretRect(
        paragraph.writing_mode,
        axes.blockStart(paragraph.writing_mode, axes.rect(line.x, line.y, line.width, line.height)),
        axes.blockSize(paragraph.writing_mode, axes.rect(line.x, line.y, line.width, line.height)),
        inline_end,
    );
    try overlays.append(allocator, .{
        .kind = .cluster_boundary,
        .rect = boundary,
        .line_start_x = boundary.x,
        .line_start_y = boundary.y,
        .line_end_x = boundary.x + boundary.width,
        .line_end_y = boundary.y + boundary.height,
        .byte_start = if (glyph_end > line.glyph_start) paragraph.glyphs[glyph_end - 1].cluster else 0,
        .byte_end = if (glyph_end > line.glyph_start) paragraph.glyphs[glyph_end - 1].cluster else 0,
        .label_index = line_index,
    });
}

fn appendFallbackRegionOverlays(allocator: std.mem.Allocator, overlays: *std.ArrayList(DebugOverlay), paragraph: paragraph_types.ParagraphLayout, line: paragraph_types.ParagraphLine, line_index: usize) !void {
    const line_glyph_end = line.glyph_start + line.glyph_len;
    for (line.runs(paragraph)) |run| {
        const start = @max(line.glyph_start, run.glyph_start);
        const end = @min(line_glyph_end, run.glyph_start + run.glyph_len);
        if (start >= end) continue;
        const line_bounds = axes.rect(line.x, line.y, line.width, line.height);
        const start_inline =
            axes.inlineStart(paragraph.writing_mode, line_bounds) +
            advanceBefore(
                paragraph.writing_mode,
                paragraph.glyphs[line.glyph_start..line_glyph_end],
                start - line.glyph_start,
            );
        const end_inline =
            axes.inlineStart(paragraph.writing_mode, line_bounds) +
            advanceBefore(
                paragraph.writing_mode,
                paragraph.glyphs[line.glyph_start..line_glyph_end],
                end - line.glyph_start,
            );
        try overlays.append(allocator, .{
            .kind = .fallback_font_region,
            .rect = axes.selectionRect(
                paragraph.writing_mode,
                line_bounds,
                start_inline,
                end_inline,
            ),
            .byte_start = if (start < paragraph.glyphs.len) paragraph.glyphs[start].cluster else 0,
            .byte_end = if (end > start and end - 1 < paragraph.glyphs.len) paragraph.glyphs[end - 1].cluster else 0,
            .label_index = run.font_index + line_index * 1000,
        });
    }
}

fn advanceBefore(
    writing_mode: @import("../shaping/pipeline/types.zig").WritingMode,
    glyphs: []const glyph_position.GlyphPosition,
    count: usize,
) f32 {
    var result: f32 = 0;
    for (glyphs[0..@min(count, glyphs.len)]) |glyph| {
        result += axes.glyphAdvance(writing_mode, glyph);
    }
    return result;
}
