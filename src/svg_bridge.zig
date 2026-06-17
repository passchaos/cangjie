const std = @import("std");
const font_mod = @import("font.zig");
const layout = @import("layout.zig");
const render_bridge = @import("render_bridge.zig");

pub const SvgTextAnchor = enum {
    start,
    middle,
    end,
};

pub const SvgDominantBaseline = enum {
    auto,
    alphabetic,
    middle,
    central,
    hanging,
    text_before_edge,
    text_after_edge,
};

pub const SvgResolvedTextSpan = struct {
    text: []const u8,
    x: f32 = 0,
    y: f32 = 0,
    dx: f32 = 0,
    dy: f32 = 0,
    font_size: f32,
    max_width: ?f32 = null,
    text_anchor: SvgTextAnchor = .start,
    dominant_baseline: SvgDominantBaseline = .alphabetic,
    direction: layout.TextDirection = .ltr,
    language_tag: ?@import("unicode.zig").OpenTypeLanguageTag = null,
};

pub const SvgTextMetrics = struct {
    width: f32,
    height: f32,
    baseline: f32,
    anchor_offset_x: f32,
    baseline_offset_y: f32,
};

pub const SvgTextLayout = struct {
    allocator: std.mem.Allocator,
    layout_buffer: layout.LayoutBuffer,
    paragraph: layout.ParagraphLayout,
    metrics: SvgTextMetrics,

    pub fn deinit(self: *SvgTextLayout) void {
        self.layout_buffer.deinit();
        self.* = undefined;
    }
};

pub fn layoutResolvedSvgText(allocator: std.mem.Allocator, cascade: layout.FontCascade, span: SvgResolvedTextSpan) !SvgTextLayout {
    var layout_buffer = layout.LayoutBuffer.init(allocator);
    errdefer layout_buffer.deinit();

    const paragraph_options = layout.ParagraphOptions{
        .max_width = span.max_width orelse std.math.inf(f32),
        .line_height = null,
        .direction = span.direction,
    };
    const paragraph = try layout.TextShaper.layoutParagraphUtf8WithOptions(cascade, &layout_buffer, span.text, span.font_size, paragraph_options);
    const metrics = svgMetrics(paragraph, span);
    return .{
        .allocator = allocator,
        .layout_buffer = layout_buffer,
        .paragraph = paragraph,
        .metrics = metrics,
    };
}

pub fn buildSvgTextDrawList(allocator: std.mem.Allocator, cascade: layout.FontCascade, span: SvgResolvedTextSpan, options: render_bridge.BridgeOptions) !render_bridge.GlyphDrawList {
    var svg_layout = try layoutResolvedSvgText(allocator, cascade, span);
    defer svg_layout.deinit();

    var bridge_options = options;
    bridge_options.origin_x += span.x + span.dx + svg_layout.metrics.anchor_offset_x;
    bridge_options.origin_y += span.y + span.dy + svg_layout.metrics.baseline_offset_y - svg_layout.metrics.baseline;
    return try render_bridge.buildGlyphDrawList(allocator, svg_layout.paragraph, bridge_options);
}

fn svgMetrics(paragraph: layout.ParagraphLayout, span: SvgResolvedTextSpan) SvgTextMetrics {
    const width = paragraph.width;
    const height = paragraph.height;
    const baseline = firstLineBaseline(paragraph);
    return .{
        .width = width,
        .height = height,
        .baseline = baseline,
        .anchor_offset_x = anchorOffset(width, span.text_anchor, span.direction),
        .baseline_offset_y = baselineOffset(height, baseline, span.dominant_baseline),
    };
}

fn firstLineBaseline(paragraph: layout.ParagraphLayout) f32 {
    if (paragraph.lines.len == 0) return 0;
    return paragraph.lines[0].baseline;
}

fn anchorOffset(width: f32, anchor: SvgTextAnchor, direction: layout.TextDirection) f32 {
    return switch (anchor) {
        .start => if (direction == .rtl) -width else 0,
        .middle => -width / 2,
        .end => if (direction == .rtl) 0 else -width,
    };
}

fn baselineOffset(height: f32, baseline: f32, dominant_baseline: SvgDominantBaseline) f32 {
    return switch (dominant_baseline) {
        .auto, .alphabetic => 0,
        .middle, .central => baseline - height / 2,
        .hanging, .text_before_edge => baseline,
        .text_after_edge => baseline - height,
    };
}

test "svg bridge converts resolved label text to anchored glyph positions" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var draw_list = try buildSvgTextDrawList(allocator, cascade, .{
        .text = "AA",
        .x = 100,
        .y = 50,
        .font_size = 20,
        .text_anchor = .middle,
    }, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 85.0), draw_list.glyphs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), draw_list.glyphs[0].baseline_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 99.0), draw_list.glyphs[1].x, 0.001);
}

test "svg bridge exposes paragraph metrics and baseline adjustment" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var svg_layout = try layoutResolvedSvgText(allocator, cascade, .{
        .text = "A",
        .font_size = 20,
        .dominant_baseline = .middle,
    });
    defer svg_layout.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 16.0), svg_layout.metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), svg_layout.metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), svg_layout.metrics.baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), svg_layout.metrics.baseline_offset_y, 0.001);
}

test "svg bridge handles tspan-like resolved offsets and end anchor" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var draw_list = try buildSvgTextDrawList(allocator, cascade, .{
        .text = "A",
        .x = 20,
        .y = 30,
        .dx = 5,
        .dy = -2,
        .font_size = 20,
        .text_anchor = .end,
    }, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), draw_list.glyphs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), draw_list.glyphs[0].baseline_y, 0.001);
}
