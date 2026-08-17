//! Renderer bridge integration tests.

const std = @import("std");
const bridge = @import("root.zig");
const face_mod = @import("../../font/face/root.zig");
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");
const glyph_position = @import("../../layout/glyph_position.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const run_types = @import("../../layout/types/runs.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const test_font = @import("../../test_font.zig");

const BridgeOptions = bridge.BridgeOptions;
const GlyphAtlasContent = bridge.GlyphAtlasContent;
const GlyphAtlasRequest = bridge.GlyphAtlasRequest;
const GlyphRenderMode = bridge.GlyphRenderMode;
const buildGlyphDrawList = bridge.buildGlyphDrawList;

test "render bridge builds glyph draw commands and deduplicated requests" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
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

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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

    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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
    const bytes = try test_font.buildGzipSvgTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect(!font.hasOutlineData());

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
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
    const bytes = try test_font.buildSbixDupePngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
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
    const bytes = try test_font.buildCbdtFormat19PngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 16, .{
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
    const bytes = try test_font.buildBitmapOnlyCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]glyph_position.GlyphPosition{.{
        .glyph_id = 0,
        .codepoint = ' ',
        .cluster = 0,
        .x_advance = 8,
    }};
    const runs = [_]run_types.CascadeRun{.{
        .font = face_mod.backend.face(&font),
        .font_index = 0,
        .font_size = 16,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    }};
    const lines = [_]paragraph_types.ParagraphLine{.{
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
    const paragraph = paragraph_types.ParagraphLayout{
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

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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

    const bytes = try test_font.buildColorV1GlyphTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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

    const bytes = try test_font.buildColorV1LayersTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);

    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
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

    const bytes = try test_font.buildColorV1VariableLinearGradientTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
        .normalized_variation_coords = &.{0.5},
    });

    // Run-owned coordinates are authoritative; callers no longer need to
    // repeat the shaping coordinates in bridge options.
    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{});
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.color_glyphs.len);
    const command = draw_list.color_glyphs[0];
    try std.testing.expectEqual(@as(usize, 0), command.color_stop_start);
    try std.testing.expectEqual(@as(usize, 2), command.color_stop_len);
    const expected_variation_hash = draw_list.atlas_requests[0].variation_hash;
    try std.testing.expect(expected_variation_hash != 0);
    try std.testing.expectEqual(expected_variation_hash, draw_list.atlas_requests[0].variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.path_requests[0].variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.atlas_requests[0].cacheKey().variation_hash);
    try std.testing.expectEqual(expected_variation_hash, draw_list.path_requests[0].cacheKey().variation_hash);
    try std.testing.expectEqual(@as(usize, 1), draw_list.atlas_requests[0].cacheKey().variation_coord_count);
    try std.testing.expectEqual(@as(usize, 1), draw_list.path_requests[0].cacheKey().variation_coord_count);
    try std.testing.expectEqual(@as(f32, 0.5), draw_list.normalized_variation_coords[0]);
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        draw_list.runs[0].normalized_variation_coords,
    );
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

test "render bridge request cache keys preserve variation and content identity" {
    const font_ptr: *const face_mod.Face = @ptrFromInt(4096);
    const a = GlyphAtlasRequest{
        .font = font_ptr,
        .glyph_id = 1,
        .font_size = 20,
        .normalized_variation_coords = &.{0.5},
        .variation_hash = 1,
    };
    var b = a;
    b.normalized_variation_coords = &.{0.25};
    b.variation_hash = 2;
    try std.testing.expect(a.cacheKey().variation_hash != b.cacheKey().variation_hash);
    try std.testing.expectEqual(@as(usize, 1), a.cacheKey().variation_coord_count);

    var rgba = a;
    rgba.content = .premultiplied_rgba;
    try std.testing.expectEqual(GlyphAtlasContent.alpha_mask, a.cacheKey().content);
    try std.testing.expectEqual(GlyphAtlasContent.premultiplied_rgba, rgba.cacheKey().content);
}

test "render bridge rejects invalid variation coordinates" {
    const empty = paragraph_types.ParagraphLayout{
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
    const bytes = try test_font.buildColorV1VariableTransformTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "A",
        20,
        .{
            .max_width = 100,
            .line_height = 24,
            .normalized_variation_coords = &.{0.5},
        },
    );
    var draw_list = try buildGlyphDrawList(allocator, paragraph, .{
        .normalized_variation_coords = &.{0.5},
    });
    defer draw_list.deinit();

    const transform = draw_list.color_glyphs[0].paint.colr_v1_transform;
    try std.testing.expectEqual(@as(f32, 100), transform.affine.dx);
    try std.testing.expectEqual(@as(f32, 50), transform.affine.dy);
}
