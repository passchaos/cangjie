const std = @import("std");
const font_mod = @import("../../font.zig");
const layout = @import("../../layout.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

test "legacy kern marks only active pair boundaries unsafe" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const kerned = try layout.TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), kerned.glyphs.len);
    try std.testing.expect(!kerned.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(kerned.glyphs[1].isUnsafeToBreakBefore());

    const disable_kern = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const unkerned = try layout.TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .features = &disable_kern },
    );
    try std.testing.expectEqual(@as(usize, 2), unkerned.glyphs.len);
    try std.testing.expect(!unkerned.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(!unkerned.glyphs[1].isUnsafeToBreakBefore());
}

test "emergency wrapping does not split an active legacy kern pair" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const kerned = try layout.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AA",
        20,
        .{ .max_width = 20 },
    );
    try std.testing.expectEqual(@as(usize, 1), kerned.lines.len);
    try std.testing.expectEqual(@as(usize, 2), kerned.lines[0].glyph_len);

    const disable_kern = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const unkerned = try layout.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AA",
        20,
        .{
            .max_width = 20,
            .features = &disable_kern,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), unkerned.lines.len);
    try std.testing.expectEqual(@as(usize, 1), unkerned.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), unkerned.lines[1].glyph_len);
}

test "fallback mark positioning marks its source relationship unsafe" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildFallbackMarkTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const run = try layout.TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "X\u{0301}x\u{0301}",
        20,
        .{ .cluster_level = .monotone_characters },
    );
    try std.testing.expectEqual(@as(usize, 4), run.glyphs.len);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
    try std.testing.expect(!run.glyphs[2].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[3].isUnsafeToBreakBefore());
}
