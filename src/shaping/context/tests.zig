const std = @import("std");

const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
const context_mod = @import("root.zig");

test "text context owns reusable caches and resets them together" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildScriptFeatureGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    const context = try context_mod.TextContext.init(std.testing.allocator, .{});
    defer context.deinit();

    const first = try context.shape(&font, "AAA", 20, .{});
    try std.testing.expectEqual(@as(usize, 3), first.glyphs.len);
    const first_stats = context.stats();
    try std.testing.expect(first_stats.glyph_indices.misses > 0);
    // Some fixtures have no GDEF payload, so the context can satisfy that
    // lookup without retaining an owned metadata record.
    try std.testing.expect(first_stats.lookup_selection.misses > 0);

    _ = try context.shape(&font, "AAA", 20, .{});
    const reused = context.stats();
    try std.testing.expect(
        reused.glyph_indices.hits > first_stats.glyph_indices.hits,
    );
    try std.testing.expect(
        reused.lookup_selection.hits > first_stats.lookup_selection.hits,
    );

    context.clearCaches();
    try std.testing.expectEqual(context_mod.TextContext.Stats{}, context.stats());
}

test "text context optionally retains complete cascade runs" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    const context = try context_mod.TextContext.init(
        std.testing.allocator,
        .{ .cache_shaped_runs = true },
    );
    defer context.deinit();

    _ = try context.shapeCascade(cascade, "AAA", 20, .{});
    _ = try context.shapeCascade(cascade, "AAA", 20, .{});
    const cache_stats = context.stats().shaped_runs;
    try std.testing.expectEqual(@as(usize, 1), cache_stats.hits);
    try std.testing.expectEqual(@as(usize, 1), cache_stats.misses);
}

test "text context can bypass all font-derived caches" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    const context = try context_mod.TextContext.init(
        std.testing.allocator,
        .{ .cache_font_data = false },
    );
    defer context.deinit();

    const run = try context.shape(&font, "AA", 20, .{});
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(context_mod.TextContext.Stats{}, context.stats());
}

test "text context owns styled metadata and paragraph measurement" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    const context = try context_mod.TextContext.init(std.testing.allocator, .{});
    defer context.deinit();
    const spans = [_]layout.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = 2,
        .style_index = 7,
        .font_size = 20,
    }};
    const styled = try context.layoutStyledParagraph(
        cascade,
        "AA",
        20,
        &spans,
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(styled.layout.glyphs.len, styled.glyph_metadata.len);
    for (styled.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
    }

    const metrics = try context.measureParagraph(
        cascade,
        "AA",
        20,
        .{ .max_width = 100 },
    );
    try std.testing.expect(metrics.width > 0);
    try std.testing.expect(metrics.height > 0);
}
