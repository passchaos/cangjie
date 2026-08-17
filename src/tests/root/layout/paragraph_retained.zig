//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const GraphemeCluster = support.GraphemeCluster;
const LineBreakOpportunity =
    @import("../../../layout/line_break/opportunity.zig").Opportunity;
const Font = support.Font;
const GlyphPosition = support.GlyphPosition;
const CascadeRun = support.CascadeRun;
const FontCascade = support.FontCascade;
const ReflowBuffer = support.ReflowBuffer;
const testing = support.testing;
const lineAdvanceSum = support.lineAdvanceSum;

test "shaped paragraphs reflow repeatedly without reshaping or accumulating layout changes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var source = [_]u8{ 'A', '\t', 'A', ' ', 'A', ' ', 'A' };
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        &source,
        20,
        .{
            .max_width = 200,
            .letter_spacing = 2,
            .word_spacing = 3,
        },
    );
    defer paragraph.deinit();
    source[0] = 'Z';
    try std.testing.expectEqualStrings("A\tA A A", paragraph.text);
    const pristine_glyphs = try allocator.dupe(GlyphPosition, paragraph.glyphs);
    defer allocator.free(pristine_glyphs);
    const pristine_runs = try allocator.dupe(CascadeRun, paragraph.runs);
    defer allocator.free(pristine_runs);
    const pristine_graphemes = try allocator.dupe(GraphemeCluster, paragraph.grapheme_clusters);
    defer allocator.free(pristine_graphemes);
    const pristine_breaks = try allocator.dupe(
        LineBreakOpportunity,
        paragraph.line_breaks,
    );
    defer allocator.free(pristine_breaks);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try paragraph.layout(&reflow, .{
        .max_width = 45,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expect(narrow.lines.len > 1);
    const narrow_line_count = narrow.lines.len;
    const narrow_first_width = narrow.lines[0].width;

    const wide = try paragraph.layout(&reflow, .{
        .max_width = 500,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);

    const narrow_again = try paragraph.layout(&reflow, .{
        .max_width = 45,
        .letter_spacing = 2,
        .word_spacing = 3,
    });
    try std.testing.expectEqual(narrow_line_count, narrow_again.lines.len);
    try std.testing.expectApproxEqAbs(narrow_first_width, narrow_again.lines[0].width, 0.001);
    try std.testing.expectEqualSlices(GlyphPosition, pristine_glyphs, paragraph.glyphs);
    try std.testing.expectEqualSlices(CascadeRun, pristine_runs, paragraph.runs);
    try std.testing.expectEqualSlices(GraphemeCluster, pristine_graphemes, paragraph.grapheme_clusters);
    try std.testing.expectEqualSlices(
        LineBreakOpportunity,
        pristine_breaks,
        paragraph.line_breaks,
    );
}

test "shaped paragraphs restore advances between justified reflows" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "A A A",
        20,
        .{ .max_width = 200 },
    );
    defer paragraph.deinit();
    const pristine_space_advance = paragraph.glyphs[1].x_advance;

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const justified = try paragraph.layout(&reflow, .{
        .max_width = 50,
        .alignment = .justify,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), justified.lines[0].width, 0.001);
    try std.testing.expect(justified.glyphs[1].x_advance > pristine_space_advance);

    const natural = try paragraph.layout(&reflow, .{
        .max_width = 500,
        .alignment = .left,
    });
    try std.testing.expectEqual(@as(usize, 1), natural.lines.len);
    try std.testing.expectApproxEqAbs(pristine_space_advance, natural.glyphs[1].x_advance, 0.001);

    const justified_again = try paragraph.layout(&reflow, .{
        .max_width = 50,
        .alignment = .justify,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), justified_again.lines[0].width, 0.001);
    try std.testing.expectEqualSlices(GlyphPosition, paragraph.glyphs, shape_buffer.glyphs.items);
}

test "retained paragraphs own run variation coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "A A",
        20,
        .{
            .max_width = 200,
            .normalized_variation_coords = &.{0.5},
        },
    );
    defer paragraph.deinit();
    // Reuse the shaping buffer with unrelated output; retained ownership must
    // keep the coordinate pool and run ranges intact.
    _ = try TextShaper.shapeUtf8WithOptions(
        &font,
        &shape_buffer,
        "A",
        20,
        .{},
    );

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const layout = try paragraph.layout(&reflow, .{
        .max_width = 200,
        .normalized_variation_coords = &.{0.5},
    });
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        layout.normalized_variation_coords,
    );
    const shaped = paragraph.shapedText();
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        shaped.runs[0].normalizedVariationCoords(shaped),
    );
}

test "shaped paragraph reflow restores content after ellipsis truncation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "A A A A A",
        20,
        .{ .max_width = 200 },
    );
    defer paragraph.deinit();
    const shaped_glyph_count = paragraph.glyphs.len;

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const clipped = try paragraph.layout(&reflow, .{
        .max_width = 42,
        .max_lines = 1,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 1), clipped.lines.len);
    try std.testing.expect(clipped.glyphs.len <= shaped_glyph_count);

    const restored = try paragraph.layout(&reflow, .{ .max_width = 500 });
    try std.testing.expectEqual(shaped_glyph_count, restored.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), restored.lines.len);
    try std.testing.expectEqual(@as(u21, 'A'), restored.glyphs[restored.glyphs.len - 1].codepoint);
}

test "ellipsis keeps the last visible justified line at natural width" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A A", 20, .{
        .max_width = 60,
        .max_lines = 1,
        .ellipsis = true,
        .alignment = .justify,
    });

    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    const line = paragraph.lines[0];
    try std.testing.expect(line.width < 60);
    try std.testing.expectApproxEqAbs(line.width, lineAdvanceSum(line.glyphs(paragraph)), 0.001);
    try std.testing.expectEqual(@as(u21, '.'), line.glyphs(paragraph)[line.glyph_len - 1].codepoint);
}

test "shaped paragraph rejects options that require reshaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "AA",
        20,
        .{ .max_width = 100 },
    );
    defer paragraph.deinit();

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    try std.testing.expectError(error.ParagraphShapingOptionsChanged, paragraph.layout(&reflow, .{
        .max_width = 100,
        .direction = .rtl,
    }));
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.lines.items.len);
}

test "limits paragraph lines and appends ellipsis" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const ellipsized = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = true,
    });

    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    try std.testing.expectEqual(@as(usize, ellipsized.lines[0].glyph_len), ellipsized.glyphs.len);
    try std.testing.expect(ellipsized.lines[0].width <= 42);
    try std.testing.expect(ellipsized.glyphs.len >= 3);
    const glyph_count = ellipsized.glyphs.len;
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 1].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 2].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), ellipsized.glyphs[glyph_count - 3].codepoint);

    const truncated = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = false,
    });
    try std.testing.expectEqual(@as(usize, 1), truncated.lines.len);
    try std.testing.expect(truncated.glyphs[truncated.glyphs.len - 1].codepoint != '.');

    const hidden = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 0,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 0), hidden.lines.len);
    try std.testing.expectEqual(@as(usize, 0), hidden.glyphs.len);

    const exactly_limited = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 42,
        .line_height = 24,
        .max_lines = 1,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 1), exactly_limited.lines.len);
    try std.testing.expectEqual(@as(usize, 1), exactly_limited.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), exactly_limited.glyphs[0].codepoint);
}

test "expands tabs to configurable tab stops" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const default_tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA", 20, .{
        .max_width = 200,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 3), default_tabs.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), default_tabs.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), default_tabs.lines[0].width, 0.001);

    const narrow_tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA", 20, .{
        .max_width = 200,
        .line_height = 24,
        .tab_width = 2,
    });

    try std.testing.expectApproxEqAbs(@as(f32, 16.0), narrow_tabs.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), narrow_tabs.lines[0].width, 0.001);
}

test "applies letter and word spacing during paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const letter_spaced = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 200,
        .line_height = 24,
        .letter_spacing = 2,
    });

    try std.testing.expectEqual(@as(usize, 2), letter_spaced.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 17.0), letter_spaced.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 17.0), letter_spaced.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 34.0), letter_spaced.lines[0].width, 0.001);

    const word_spaced = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 200,
        .line_height = 24,
        .letter_spacing = 2,
        .word_spacing = 5,
    });

    try std.testing.expectEqual(@as(usize, 3), word_spaced.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), word_spaced.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), word_spaced.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), word_spaced.glyphs[2].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 51.0), word_spaced.lines[0].width, 0.001);

    const wrapped = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 45,
        .line_height = 24,
        .letter_spacing = 2,
        .word_spacing = 5,
    });
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines.len);
}

test "applies first line indent to paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 48,
        .line_height = 24,
        .first_line_indent = 16,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), paragraph.width, 0.001);

    const centered = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 80,
        .line_height = 24,
        .alignment = .center,
        .first_line_indent = 20,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), centered.lines[0].x, 0.001);
}

test "applies paragraph spacing after hard breaks" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const hard_break = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\nA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .first_line_indent = 10,
        .paragraph_spacing = 6,
    });

    try std.testing.expectEqual(@as(usize, 2), hard_break.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), hard_break.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), hard_break.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), hard_break.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), hard_break.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 54.0), hard_break.height, 0.001);

    const soft_wrap = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 48,
        .line_height = 24,
        .first_line_indent = 16,
        .paragraph_spacing = 6,
    });

    try std.testing.expectEqual(@as(usize, 2), soft_wrap.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), soft_wrap.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), soft_wrap.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), soft_wrap.lines[1].y, 0.001);
}
