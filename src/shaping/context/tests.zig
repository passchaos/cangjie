const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const Font = @import("../../font.zig").Font;
const styled_paragraph = @import("../../layout/styled_paragraph.zig");
const context_mod = @import("root.zig");

test "engine owns reusable caches and resets them together" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildScriptFeatureGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    var engine = context_mod.Engine.init(std.testing.allocator, .{});
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

test "cached GSUB plans retain detailed lookup profiling" {
    const test_font = @import("../../test_font.zig");
    const ShapeStageProfile = @import("../../shape_profile.zig")
        .ShapeStageProfile;
    const bytes = try test_font.buildScriptFeatureGsubTtf(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    var engine = context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var profile = ShapeStageProfile{};
    engine.enableProfiling(&profile, std.testing.io, false);
    const feature_ranges = [_]@import(
        "../../unicode.zig",
    ).GsubFeatureRange{.{
        .tag = @import("../../unicode.zig").tag("sups"),
        .value = 1,
        .byte_start = 0,
        .byte_end = 3,
    }};

    const shaped = try engine.shape(
        face_mod.backend.face(&font),
        .{
            .text = "AAA",
            .font_size = 20,
            .feature_ranges = &feature_ranges,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectEqualSlices(
        @import("../../glyph.zig").GlyphId,
        &.{ 2, 2, 2 },
        &.{
            shaped.glyphs[0].glyph_id,
            shaped.glyphs[1].glyph_id,
            shaped.glyphs[2].glyph_id,
        },
    );
    try std.testing.expect(profile.gsub_lookup_count != 0);
    try std.testing.expect(profile.gsub_lookup_entry_count != 0);
}

test "engine releases partial GSUB cache construction on allocation failure" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator, font_bytes: []const u8) !void {
                var face = try face_mod.Face.parse(allocator, font_bytes);
                defer face.deinit();
                var engine = context_mod.Engine.init(allocator, .{});
                defer engine.deinit();
                const shaped = try engine.shape(
                    &face,
                    .{ .text = "AA", .font_size = 20 },
                );
                // Cache-enabled and cache-bypassed paths must both complete
                // without retaining partially built lookup sidecars. The
                // exact fixture feature selection is tested independently.
                try std.testing.expect(shaped.glyphs.len > 0);
            }
        }.run,
        .{bytes},
    );
}

test "engine optionally retains complete cascade runs" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&fonts));

    var engine = context_mod.Engine.init(
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

test "engine fallback cache separates reordered cascades" {
    const test_font = @import("../../test_font.zig");
    const allocator = std.testing.allocator;
    const primary_bytes =
        try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const complete_bytes =
        try test_font.buildCodepointSetTtf(allocator, &.{ 'A', 0x0301 });
    defer allocator.free(complete_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var complete = try Font.parse(allocator, complete_bytes);
    defer complete.deinit();

    const primary_first_fonts = [_]*const Font{ &primary, &complete };
    const complete_first_fonts = [_]*const Font{ &complete, &primary };
    const primary_first = face_mod.Cascade.init(
        face_mod.backend.faces(&primary_first_fonts),
    );
    const complete_first = face_mod.Cascade.init(
        face_mod.backend.faces(&complete_first_fonts),
    );
    var engine = context_mod.Engine.init(allocator, .{});
    defer engine.deinit();

    const first = try engine.shapeText(primary_first, .{
        .text = "A\u{0301}",
        .font_size = 20,
    });
    try std.testing.expectEqual(@as(usize, 1), first.runs.len);
    try std.testing.expectEqual(@as(usize, 1), first.runs[0].font_index);
    for (first.glyphs) |glyph| try std.testing.expect(glyph.glyph_id != 0);

    const second = try engine.shapeText(complete_first, .{
        .text = "A\u{0301}",
        .font_size = 20,
    });
    try std.testing.expectEqual(@as(usize, 1), second.runs.len);
    try std.testing.expectEqual(@as(usize, 0), second.runs[0].font_index);
    for (second.glyphs) |glyph| try std.testing.expect(glyph.glyph_id != 0);

    const fallback_stats = engine.stats().font_fallback;
    try std.testing.expectEqual(@as(usize, 0), fallback_stats.hits);
    try std.testing.expectEqual(@as(usize, 2), fallback_stats.misses);
}

test "engine can bypass all font-derived caches" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    var engine = context_mod.Engine.init(
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

    var engine = context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const spans = [_]styled_paragraph.Span{.{
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

test "styled layout can omit intrinsic widths without changing output" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const spans = [_]styled_paragraph.Span{.{
        .byte_start = 0,
        .byte_len = 3,
        .style_index = 4,
        .font_size = 20,
        .letter_spacing = 0.5,
    }};
    var engine = context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const complete = try engine.layoutStyled(cascade, .{
        .text = "A A",
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 30 },
    });
    const Glyph = @import("../../layout/glyph_position.zig").GlyphPosition;
    const Line = @import("../../layout/types/paragraph.zig").ParagraphLine;
    const expected_glyphs = try std.testing.allocator.dupe(
        Glyph,
        complete.layout.glyphs,
    );
    defer std.testing.allocator.free(expected_glyphs);
    const expected_lines = try std.testing.allocator.dupe(
        Line,
        complete.layout.lines,
    );
    defer std.testing.allocator.free(expected_lines);

    const layout_only = try engine.layoutStyledWithoutContentWidths(
        cascade,
        .{
            .text = "A A",
            .default_font_size = 20,
            .spans = &spans,
            .options = .{ .max_width = 30 },
        },
    );
    try std.testing.expectEqualSlices(
        Glyph,
        expected_glyphs,
        layout_only.layout.glyphs,
    );
    try std.testing.expectEqualSlices(
        Line,
        expected_lines,
        layout_only.layout.lines,
    );
    try std.testing.expectEqual(
        layout_only.layout.glyphs.len,
        layout_only.glyph_metadata.len,
    );
}

test "styled layout reuses face-derived glyph caches" {
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&fonts));
    const spans = [_]styled_paragraph.Span{.{
        .byte_start = 0,
        .byte_len = 3,
        .style_index = 1,
        .font_size = 16,
        .letter_spacing = 0.75,
        .word_spacing = 2,
    }};

    var engine = context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    _ = try engine.layoutStyled(cascade, .{
        .text = "A A",
        .default_font_size = 16,
        .spans = &spans,
        .options = .{ .max_width = 200 },
    });
    const first = engine.stats();
    _ = try engine.layoutStyled(cascade, .{
        .text = "A A",
        .default_font_size = 16,
        .spans = &spans,
        .options = .{ .max_width = 200 },
    });
    const reused = engine.stats();
    try std.testing.expect(
        reused.glyph_indices.hits > first.glyph_indices.hits,
    );
    try std.testing.expect(
        reused.glyph_metrics.hits > first.glyph_metrics.hits,
    );
}
