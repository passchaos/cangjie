const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
const context_mod = @import("root.zig");

test "engine owns reusable caches and resets them together" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildScriptFeatureGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    const engine = try context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    const face = face_mod.backend.face(&font);
    const first = try engine.shape(face, .{ .text = "AAA", .font_size = 20 });
    try std.testing.expectEqual(@as(usize, 3), first.glyphs.len);
    const first_stats = engine.stats();
    try std.testing.expect(first_stats.glyph_indices.misses > 0);
    // Some fixtures have no GDEF payload, so the context can satisfy that
    // lookup without retaining an owned metadata record.
    try std.testing.expect(first_stats.lookup_selection.misses > 0);

    _ = try engine.shape(face, .{ .text = "AAA", .font_size = 20 });
    const reused = engine.stats();
    try std.testing.expect(
        reused.glyph_indices.hits > first_stats.glyph_indices.hits,
    );
    try std.testing.expect(
        reused.lookup_selection.hits > first_stats.lookup_selection.hits,
    );

    engine.clearCaches();
    try std.testing.expectEqual(context_mod.Engine.Stats{}, engine.stats());
}

test "engine optionally retains complete cascade runs" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&fonts));

    const engine = try context_mod.Engine.init(
        std.testing.allocator,
        .{ .cache_shaped_runs = true },
    );
    defer engine.deinit();

    _ = try engine.shapeText(cascade, .{ .text = "AAA", .font_size = 20 });
    _ = try engine.shapeText(cascade, .{ .text = "AAA", .font_size = 20 });
    const cache_stats = engine.stats().shaped_runs;
    try std.testing.expectEqual(@as(usize, 1), cache_stats.hits);
    try std.testing.expectEqual(@as(usize, 1), cache_stats.misses);
}

test "engine can bypass all font-derived caches" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    const engine = try context_mod.Engine.init(
        std.testing.allocator,
        .{ .cache_font_data = false },
    );
    defer engine.deinit();

    const run = try engine.shape(
        face_mod.backend.face(&font),
        .{ .text = "AA", .font_size = 20 },
    );
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(context_mod.Engine.Stats{}, engine.stats());
}

test "engine owns styled metadata and paragraph measurement" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&fonts));

    const engine = try context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const spans = [_]layout.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = 2,
        .style_index = 7,
        .font_size = 20,
    }};
    const styled = try engine.layoutStyled(
        cascade,
        .{
            .text = "AA",
            .default_font_size = 20,
            .spans = &spans,
            .options = .{ .max_width = 100 },
        },
    );
    try std.testing.expectEqual(styled.layout.glyphs.len, styled.glyph_metadata.len);
    for (styled.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
    }

    const metrics = try engine.measure(
        cascade,
        .{
            .text = "AA",
            .font_size = 20,
            .options = .{ .max_width = 100 },
        },
    );
    try std.testing.expect(metrics.width > 0);
    try std.testing.expect(metrics.height > 0);
}
