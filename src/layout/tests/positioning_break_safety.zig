const std = @import("std");
const font_mod = @import("../../font.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

test "legacy kern marks only active pair boundaries unsafe" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const kerned = try shaping_orchestrator.TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), kerned.glyphs.len);
    try std.testing.expect(!kerned.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(kerned.glyphs[1].isUnsafeToBreakBefore());

    const disable_kern = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const unkerned = try shaping_orchestrator.TextShaper.shapeUtf8WithOptions(
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
    const cascade = font_fallback.Cascade.init(&fonts);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const kerned = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
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
    const unkerned = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
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
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const run = try shaping_orchestrator.TextShaper.shapeUtf8WithOptions(
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
