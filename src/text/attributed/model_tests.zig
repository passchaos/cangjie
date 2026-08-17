//! Attributed model, measurement, and run-layout tests.

const std = @import("std");
const attributed_model = @import("root.zig");
const style = @import("../style/root.zig");
const Font = @import("../../font.zig").Font;
const GlyphId = @import("../../glyph.zig").GlyphId;
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

const StyleSpan = style.StyleSpan;
const AttributedText = attributed_model.AttributedText;
const measureAttributedTextUtf8 = attributed_model.measureAttributedTextUtf8;
const measureAttributedRunsUtf8 = attributed_model.measureAttributedRunsUtf8;
const layoutAttributedRunsUtf8 = attributed_model.layoutAttributedRunsUtf8;
const layoutAttributedGlyphRunsUtf8 = attributed_model.layoutAttributedGlyphRunsUtf8;
const layoutAttributedParagraphUtf8 =
    attributed_model.layoutAttributedParagraphUtf8;

test "core ranges and attributed text validate byte units" {
    const text = "A一B";
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 12 } },
        .{ .byte_range = .{ .start = 1, .len = 3 }, .style = .{ .font_size = 16, .script = .han } },
        .{ .byte_range = .{ .start = 4, .len = 1 }, .style = .{ .font_size = 12 } },
    };
    const attributed = AttributedText{ .text = text, .spans = &spans };

    try attributed.validate();
    try std.testing.expectEqual(@as(usize, 4), spans[1].byte_range.end());
    try std.testing.expectEqual(@as(f32, 16), attributed.styleAtByte(2).?.font_size);
    try std.testing.expect(attributed.styleAtByte(text.len) == null);

    const bad = AttributedText{
        .text = text,
        .spans = &.{.{ .byte_range = .{ .start = 2, .len = 1 }, .style = .{} }},
    };
    try std.testing.expectError(error.InvalidUtf8Boundary, bad.validate());
}

test "attributed text splits style runs by byte range boundaries" {
    const allocator = std.testing.allocator;
    const text = "abcde";
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{ .font_size = 12 } },
        .{ .byte_range = .{ .start = 2, .len = 2 }, .style = .{ .font_size = 16 } },
        .{ .byte_range = .{ .start = 3, .len = 2 }, .style = .{ .font_size = 20 } },
    };
    const attributed = AttributedText{ .text = text, .spans = &spans };
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 4), runs.len);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_range.start);
    try std.testing.expectEqual(@as(usize, 2), runs[0].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 12), runs[0].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 2), runs[1].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[1].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), runs[1].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 3), runs[2].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[2].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), runs[2].style.font_size, 0.001);
    try std.testing.expectEqual(@as(usize, 4), runs[3].byte_range.start);
    try std.testing.expectEqual(@as(usize, 1), runs[3].byte_range.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), runs[3].style.font_size, 0.001);

    const default_runs = try (AttributedText{ .text = "ab", .spans = &.{} }).runs(allocator);
    defer allocator.free(default_runs);
    try std.testing.expectEqual(@as(usize, 1), default_runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), default_runs[0].style.font_size, 0.001);
}

test "measures attributed text with primary style" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();

    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{ .font_size = 20, .letter_spacing = 2, .line_height = 24 } },
    };
    const attributed = AttributedText{
        .text = "AA",
        .spans = &spans,
        .paragraph_style = .{ .text_align = .left },
    };
    const metrics = try measureAttributedTextUtf8(cascade, &layout_buffer, attributed, 100);

    try std.testing.expectApproxEqAbs(@as(f32, 34.0), metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), metrics.baseline, 0.001);
}

test "attributed text forwards normalized variation metrics" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var layout_buffer = context_output.Buffer.init(allocator);
    defer layout_buffer.deinit();

    const default_spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
    };
    const varied_spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20, .normalized_variation_coords = &.{0.5} } },
    };
    const default_metrics = try measureAttributedTextUtf8(cascade, &layout_buffer, .{ .text = "A", .spans = &default_spans }, 100);
    const varied_metrics = try measureAttributedTextUtf8(cascade, &layout_buffer, .{ .text = "A", .spans = &varied_spans }, 100);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), default_metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.08), varied_metrics.width, 0.001);

    var paragraph = try layoutAttributedParagraphUtf8(
        allocator,
        cascade,
        .{ .text = "A", .spans = &varied_spans },
        100,
    );
    defer paragraph.deinit();
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        paragraph.normalized_variation_coords,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        paragraph.paragraph.runs[0].normalizedVariationCoords(.{
            .glyphs = paragraph.paragraph.glyphs,
            .runs = paragraph.paragraph.runs,
            .normalized_variation_coords = paragraph.paragraph.normalized_variation_coords,
        }),
    );

    var glyph_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, .{ .text = "A", .spans = &varied_spans });
    defer glyph_runs.deinit();
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.08), glyph_runs.metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.08), glyph_runs.runs[0].glyphs[0].x_advance, 0.001);
}

test "attributed text forwards OpenType feature styling" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildScriptFeatureGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const enable_sups = [_]unicode.FeatureOverride{.{ .tag = unicode.tag("sups"), .enabled = true }};
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20, .font_features = &enable_sups } },
    };
    const attributed = AttributedText{ .text = "A", .spans = &spans };
    var glyph_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, attributed);
    defer glyph_runs.deinit();

    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs.len);
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs[0].glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), glyph_runs.runs[0].glyphs[0].glyph_id);
}

test "attributed text forwards locale language styling" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildNamedCjkLanguageGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const default_spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = "一".len }, .style = .{ .font_size = 20 } },
    };
    const japanese_spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = "一".len }, .style = .{ .font_size = 20, .locale = "ja-JP" } },
    };

    var default_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, .{ .text = "一", .spans = &default_spans });
    defer default_runs.deinit();
    var japanese_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, .{ .text = "一", .spans = &japanese_spans });
    defer japanese_runs.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), default_runs.runs[0].glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 2), japanese_runs.runs[0].glyphs[0].glyph_id);
}

test "measures attributed runs with per span style" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    const metrics = try measureAttributedRunsUtf8(allocator, cascade, attributed);

    try std.testing.expectApproxEqAbs(@as(f32, 48.0), metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), metrics.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), metrics.baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), metrics.ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), metrics.descent, 0.001);
}

test "layouts attributed runs with x offsets and metrics" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    var positioned = try layoutAttributedRunsUtf8(allocator, cascade, attributed);
    defer positioned.deinit();

    try std.testing.expectEqual(@as(usize, 2), positioned.runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), positioned.runs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), positioned.runs[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), positioned.runs[0].metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), positioned.runs[1].metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), positioned.metrics.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), positioned.metrics.height, 0.001);
}

test "layouts attributed glyph runs for rendering" {
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const spans = [_]StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{ .font_size = 20 } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{ .font_size = 40 } },
    };
    const attributed = AttributedText{ .text = "AA", .spans = &spans };
    var glyph_runs = try layoutAttributedGlyphRunsUtf8(allocator, cascade, attributed);
    defer glyph_runs.deinit();

    try std.testing.expectEqual(@as(usize, 2), glyph_runs.runs.len);
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs[0].glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), glyph_runs.runs[1].glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), glyph_runs.runs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), glyph_runs.runs[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), glyph_runs.runs[0].glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), glyph_runs.runs[1].glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), glyph_runs.metrics.width, 0.001);
}
