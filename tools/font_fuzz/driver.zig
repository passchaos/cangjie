//! Shared malformed-font parser and renderer exercise path.

const std = @import("std");
const cangjie = @import("cangjie");

/// Drive one caller-owned byte slice through the public font APIs. Invalid
/// inputs are expected to return an error; memory-safety failures must escape
/// as test failures or process crashes.
pub fn exerciseCase(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var face = cangjie.font.Face.parse(allocator, bytes) catch return;
    defer face.deinit();

    const glyphs = face.glyphs();
    // Prefer a cmap-derived glyph so successful mutations exercise the link
    // between cmap and outline tables. Fonts without U+0041 still exercise
    // the required .notdef geometry.
    const glyph_id = glyphs.index('A') catch 0;
    _ = glyphs.extents(glyph_id) catch {};
    var outline_buffer = cangjie.font.OutlineBuffer.init(allocator);
    defer outline_buffer.deinit();
    _ = glyphs.session().outlineInto(&outline_buffer, glyph_id) catch {};
    var outline = glyphs.outline(allocator, glyph_id) catch null;
    defer if (outline) |*value| value.deinit();

    // Exercise variation-aware outline decoding whenever the mutated face
    // still exposes axes. Default and non-default coordinates take different
    // gvar/CFF2/VARC paths and the reusable variant owns additional cache-key
    // storage that must remain transactional on malformed input.
    const variation_summary = face.variations().summary() catch null;
    const axis_count = if (variation_summary) |summary| summary.axis_count else 0;
    if (axis_count != 0) {
        const coords = try allocator.alloc(f32, axis_count);
        defer allocator.free(coords);
        @memset(coords, 0.5);
        var varied = glyphs.outlineAt(allocator, glyph_id, coords) catch null;
        if (varied) |*value| value.deinit();
        _ = glyphs.session().outlineAtInto(
            &outline_buffer,
            glyph_id,
            coords,
        ) catch {};
    }

    // Parsed metadata and bitmap/color accessors share the same table graph
    // but not the outline decoder, so keep them live in malformed-font fuzzing.
    const palettes = face.color().palettes(allocator) catch null;
    if (palettes) |values| allocator.free(values);
    const bitmap_strikes = face.color().bitmapStrikes(allocator) catch null;
    if (bitmap_strikes) |values| allocator.free(values);

    // Bitmap-only and color-only faces need not have a conventional outline.
    // Keep their metadata paths reachable, and raster only when the selected
    // glyph did produce geometry.
    if (outline) |*value| {
        var target = try cangjie.render.GrayTarget.init(allocator, 32, 32);
        defer target.deinit();
        var rasterizer = cangjie.render.Rasterizer.init(allocator);
        defer rasterizer.deinit();
        rasterizer.setSampling(4);
        rasterizer.drawOutline(
            &target,
            value,
            0,
            24,
            24,
            face.properties().units_per_em,
        ) catch {};
    }
}
