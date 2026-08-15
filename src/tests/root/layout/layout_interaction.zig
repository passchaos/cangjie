//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const TextRect = support.TextRect;
const buildDebugOverlays = support.buildDebugOverlays;
const itemizeGraphemeClusters = support.itemizeGraphemeClusters;
const itemizeWordSegments = support.itemizeWordSegments;
const testing = support.testing;

test "lays out wrapped and aligned fallback text into paragraph lines" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(allocator, 'B');
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A B A", 20, .{
        .max_width = 42,
        .alignment = .right,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), paragraph.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), paragraph.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), paragraph.height, 0.001);
    try std.testing.expect(paragraph.lines[0].run_len >= 2);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].byte_len);
}

test "paragraph lines expose baseline metrics" {
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
    const natural = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
    });
    try std.testing.expectEqual(@as(usize, 1), natural.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), natural.lines[0].baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), natural.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), natural.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), natural.lines[0].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), natural.lines[0].height, 0.001);

    const expanded = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), expanded.lines[0].baseline, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), expanded.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), expanded.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), expanded.lines[0].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), expanded.lines[0].height, 0.001);
}

test "paragraph line metrics include fallback fonts on each line" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'A',
        800,
        -200,
        0,
    );
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'B',
        1100,
        -350,
        100,
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\nB", 20, .{
        .max_width = 100,
        .paragraph_spacing = 3,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].run_start);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].run_start);
    try std.testing.expectApproxEqAbs(@as(f32, 16), paragraph.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), paragraph.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), paragraph.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 22), paragraph.lines[1].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), paragraph.lines[1].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), paragraph.lines[1].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31), paragraph.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 23), paragraph.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 54), paragraph.height, 0.001);

    // A requested line height is a minimum: it can add leading to ordinary
    // text but cannot make a fallback glyph's own vertical metrics disappear.
    const explicit = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AB", 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 1), explicit.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 22), explicit.lines[0].ascent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), explicit.lines[0].descent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), explicit.lines[0].leading, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31), explicit.lines[0].height, 0.001);

    const soft_wrap = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A B", 20, .{
        .max_width = 40,
    });
    try std.testing.expectEqual(@as(usize, 2), soft_wrap.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), soft_wrap.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), soft_wrap.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31), soft_wrap.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 51), soft_wrap.height, 0.001);
}

test "empty paragraph lines retain the primary font strut" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'A',
        800,
        -200,
        0,
    );
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'B',
        1100,
        -350,
        100,
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fonts = [_]*const Font{ &primary, &fallback };

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        "B\n",
        20,
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 31), paragraph.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), paragraph.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31), paragraph.lines[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 51), paragraph.height, 0.001);
}

test "builds debug overlay geometry for paragraph text" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var overlays = try buildDebugOverlays(allocator, paragraph, .{
        .cursor = .{ .glyph_index = 1, .cluster = 1 },
        .selection_start_glyph = 0,
        .selection_end_glyph = 2,
        .bidi_text = "A ב",
    });
    defer overlays.deinit();

    var saw_baseline = false;
    var saw_line_box = false;
    var saw_cursor = false;
    var saw_selection = false;
    var saw_bidi = false;
    var saw_glyph = false;
    var saw_cluster = false;
    var saw_fallback = false;
    for (overlays.items) |overlay| {
        switch (overlay.kind) {
            .baseline => {
                saw_baseline = true;
                try std.testing.expectApproxEqAbs(@as(f32, 18.0), overlay.line_start_y, 0.001);
                try std.testing.expectApproxEqAbs(@as(f32, 30.0), overlay.line_end_x, 0.001);
            },
            .line_box => {
                saw_line_box = true;
                try std.testing.expectApproxEqAbs(@as(f32, 24.0), overlay.rect.height, 0.001);
            },
            .cursor_rect => {
                saw_cursor = true;
                try std.testing.expectApproxEqAbs(@as(f32, 15.0), overlay.rect.x, 0.001);
            },
            .selection_rect => saw_selection = true,
            .glyph_box => {
                saw_glyph = true;
                try std.testing.expect(overlay.rect.width > 0);
                try std.testing.expect(overlay.rect.height > 0);
            },
            .cluster_boundary => {
                saw_cluster = true;
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), overlay.rect.width, 0.001);
                try std.testing.expect(overlay.line_end_y > overlay.line_start_y);
            },
            .fallback_font_region => {
                saw_fallback = true;
                try std.testing.expect(overlay.rect.width > 0);
            },
            .bidi_run => {
                saw_bidi = true;
                try std.testing.expect(overlay.byte_end > overlay.byte_start);
            },
        }
    }
    try std.testing.expect(saw_baseline);
    try std.testing.expect(saw_line_box);
    try std.testing.expect(saw_cursor);
    try std.testing.expect(saw_selection);
    try std.testing.expect(saw_bidi);
    try std.testing.expect(saw_glyph);
    try std.testing.expect(saw_cluster);
    try std.testing.expect(saw_fallback);
}

test "hit tests carets and selection geometry in paragraph layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(allocator, 'B');
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A B A", 20, .{
        .max_width = 42,
        .alignment = .right,
        .line_height = 24,
    });

    const first = paragraph.hitTest(1, 8);
    try std.testing.expectEqual(@as(usize, 0), first.glyph_index);
    try std.testing.expect(!first.trailing);

    const after_first = paragraph.hitTest(15, 8);
    try std.testing.expectEqual(@as(usize, 0), after_first.glyph_index);
    try std.testing.expect(after_first.trailing);

    const second_line = paragraph.hitTest(30, 30);
    try std.testing.expectEqual(@as(usize, 4), second_line.glyph_index);
    try std.testing.expect(!second_line.trailing);

    const caret = paragraph.caretRect(.{ .glyph_index = 4, .cluster = 4 });
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), caret.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), caret.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), caret.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), caret.height, 0.001);

    const selection = paragraph.selectionRect(1, 4);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), selection.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), selection.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), selection.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), selection.height, 0.001);

    const byte_selection = paragraph.selectionRectForBytes(1, 4);
    try std.testing.expectApproxEqAbs(selection.x, byte_selection.x, 0.001);
    try std.testing.expectApproxEqAbs(selection.y, byte_selection.y, 0.001);
    try std.testing.expectApproxEqAbs(selection.width, byte_selection.width, 0.001);
    try std.testing.expectApproxEqAbs(selection.height, byte_selection.height, 0.001);

    const rects = try paragraph.selectionRects(allocator, 1, 5);
    defer allocator.free(rects);
    try std.testing.expectEqual(@as(usize, 2), rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), rects[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), rects[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), rects[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), rects[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[1].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), rects[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rects[1].height, 0.001);

    var rect_buffer: [1]TextRect = undefined;
    const clipped_rects = paragraph.selectionRectsInto(&rect_buffer, 1, 5);
    try std.testing.expectEqual(@as(usize, 1), clipped_rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), clipped_rects[0].x, 0.001);
}

test "moves paragraph carets across grapheme cluster boundaries" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\u{0301}A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    const clusters = try itemizeGraphemeClusters(allocator, "A\u{0301}A");
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 2), clusters.len);
    const start = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 0, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 0), start.cluster);
    const next = paragraph.nextGraphemeCaret(clusters, start);
    try std.testing.expectEqual(@as(usize, 3), next.cluster);
    try std.testing.expectEqual(@as(usize, 2), next.glyph_index);
    const previous = paragraph.previousGraphemeCaret(clusters, next);
    try std.testing.expectEqual(@as(usize, 0), previous.cluster);

    const inside_mark = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 1, .cluster = 1 });
    try std.testing.expectEqual(@as(usize, 0), inside_mark.cluster);
}

test "hit testing reports trailing source byte offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "A\u{fe0f}";
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs.len);
    try std.testing.expectEqual(@as(usize, text.len), paragraph.glyphs[0].source_byte_len);

    const leading = paragraph.hitTest(1, 8);
    try std.testing.expectEqual(@as(usize, 0), leading.glyph_index);
    try std.testing.expectEqual(@as(usize, 0), leading.cluster);
    try std.testing.expect(!leading.trailing);

    const trailing = paragraph.hitTest(15, 8);
    try std.testing.expectEqual(@as(usize, 0), trailing.glyph_index);
    try std.testing.expectEqual(@as(usize, text.len), trailing.cluster);
    try std.testing.expect(trailing.trailing);
}

test "paragraph carets use shaped glyph source extents" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "A\u{fe0f}";
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 100,
        .line_height = 24,
    });
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), paragraph.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, text.len), paragraph.glyphs[0].source_byte_len);
    // A variation selector does not produce its own glyph, so the last glyph's
    // trailing edge must carry the selector byte extent. Otherwise snapping a
    // clicked trailing caret would jump back to the start of the grapheme.
    const snapped = paragraph.snapToGraphemeCaret(clusters, .{ .glyph_index = 0, .cluster = 0, .trailing = true });
    try std.testing.expect(snapped.trailing);
    try std.testing.expectEqual(@as(usize, text.len), snapped.cluster);
}

test "moves paragraph carets across word boundaries" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA BB", 20, .{
        .max_width = 120,
        .line_height = 24,
    });
    const words = try itemizeWordSegments(allocator, "AA BB");
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    const start = paragraph.snapToWordCaret(words, .{ .glyph_index = 0, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 0), start.cluster);
    const first_end = paragraph.nextWordCaret(words, start);
    try std.testing.expectEqual(@as(usize, 2), first_end.cluster);
    const second_end = paragraph.nextWordCaret(words, first_end);
    try std.testing.expectEqual(@as(usize, 5), second_end.cluster);
    const previous = paragraph.previousWordCaret(words, .{ .glyph_index = 3, .cluster = 3 });
    try std.testing.expectEqual(@as(usize, 0), previous.cluster);
    const snapped_inside = paragraph.snapToWordCaret(words, .{ .glyph_index = 1, .cluster = 1 });
    try std.testing.expectEqual(@as(usize, 2), snapped_inside.cluster);
}
