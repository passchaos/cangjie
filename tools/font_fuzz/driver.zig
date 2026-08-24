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
    var outline = glyphs.outline(allocator, glyph_id) catch return;
    defer outline.deinit();

    var target = try cangjie.render.GrayTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setSampling(4);
    rasterizer.drawOutline(
        &target,
        &outline,
        0,
        24,
        24,
        face.properties().units_per_em,
    ) catch {};
}
