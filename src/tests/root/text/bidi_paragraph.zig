//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const ReflowBuffer = support.ReflowBuffer;
const itemizeGraphemeClusters = support.itemizeGraphemeClusters;
const testing = support.testing;

test "cascade shaping can preserve caller-materialized visual order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(allocator, "Visual Sans", "Regular", "Visual Sans Regular");
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const reordered = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &layout_buffer,
        "A\u{05d0}",
        20,
        .{ .direction = .rtl },
    );
    try std.testing.expectEqual(@as(u21, 0x05d0), reordered.glyphs[0].codepoint);

    const preserved = try TextShaper.shapeUtf8CascadeWithOptions(
        cascade,
        &layout_buffer,
        "A\u{05d0}",
        20,
        .{ .direction = .rtl, .reorder_bidi = false },
    );
    try std.testing.expectEqual(@as(u21, 'A'), preserved.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), preserved.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 0), preserved.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 1), preserved.glyphs[1].cluster);
}

test "variable-direction Old Italic preserves explicit RTL shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildOldItalicDirectionalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &layout_buffer,
        "\u{10300}\u{10301}",
        20,
        .{
            .direction = .rtl,
            .reorder_bidi = false,
            .native_direction_shaping = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    // Old Italic may be written in either direction. Its native direction is
    // therefore indeterminate, so the caller's RTL direction selects `rtlm`
    // while the already-visual buffer order remains unchanged.
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 4), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x10300), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x10301), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 4), run.glyphs[1].cluster);
}

test "shapes cascade text right-to-left with visual glyph order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const hebrew_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Hebrew Sans", "Regular", "Hebrew Sans Regular");
    defer allocator.free(hebrew_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var hebrew = try Font.parse(allocator, hebrew_bytes);
    defer hebrew.deinit();

    const fonts = [_]*const Font{ &primary, &hebrew };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "A\u{05d0}", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[1].font_index);
}

test "shapes mixed-direction cascade text in bidi visual order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);
    const trailing_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Trailing Sans", "Regular", "Trailing Sans Regular");
    defer allocator.free(trailing_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();
    var trailing = try Font.parse(allocator, trailing_bytes);
    defer trailing.deinit();

    const fonts = [_]*const Font{ &primary, &alef, &bet, &trailing };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "A\u{05d0}\u{05d1}B", 20, .{ .direction = .ltr });

    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d1), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(u21, 'B'), shaped.glyphs[3].codepoint);
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 1, 5 }, &.{
        shaped.glyphs[0].cluster,
        shaped.glyphs[1].cluster,
        shaped.glyphs[2].cluster,
        shaped.glyphs[3].cluster,
    });

    try std.testing.expectEqual(@as(usize, 4), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 2), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs[3].font_index);
}

test "shapes mirrored bidi punctuation with mirrored glyph ids" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(allocator, "Mirror Sans", "Regular", "Mirror Sans Regular");
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "(\u{05d0})", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqual(@as(u21, '('), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, ')'), run.glyphs[2].codepoint);
    try std.testing.expectEqual(try font.glyphIndex('('), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(try font.glyphIndex(0x05d0), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(try font.glyphIndex(')'), run.glyphs[2].glyph_id);
    try std.testing.expectEqualSlices(usize, &.{ 3, 1, 0 }, &.{
        run.glyphs[0].cluster,
        run.glyphs[1].cluster,
        run.glyphs[2].cluster,
    });
}

test "shapes right-to-left text with numeric subruns left-to-right" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const one_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '1', "One Sans", "Regular", "One Sans Regular");
    defer allocator.free(one_bytes);
    const two_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '2', "Two Sans", "Regular", "Two Sans Regular");
    defer allocator.free(two_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);

    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var one = try Font.parse(allocator, one_bytes);
    defer one.deinit();
    var two = try Font.parse(allocator, two_bytes);
    defer two.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();

    const fonts = [_]*const Font{ &alef, &one, &two, &bet };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &layout_buffer, "\u{05d0}12\u{05d1}", 20, .{ .direction = .rtl });

    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs.len);
    try std.testing.expectEqual(@as(u21, 0x05d1), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, '1'), shaped.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, '2'), shaped.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(u21, 0x05d0), shaped.glyphs[3].codepoint);
    try std.testing.expectEqualSlices(usize, &.{ 4, 2, 3, 0 }, &.{
        shaped.glyphs[0].cluster,
        shaped.glyphs[1].cluster,
        shaped.glyphs[2].cluster,
        shaped.glyphs[3].cluster,
    });
}

test "maps logical carets onto visually reordered bidi glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const alef_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d0, "Alef Sans", "Regular", "Alef Sans Regular");
    defer allocator.free(alef_bytes);
    const one_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '1', "One Sans", "Regular", "One Sans Regular");
    defer allocator.free(one_bytes);
    const two_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, '2', "Two Sans", "Regular", "Two Sans Regular");
    defer allocator.free(two_bytes);
    const bet_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x05d1, "Bet Sans", "Regular", "Bet Sans Regular");
    defer allocator.free(bet_bytes);

    var alef = try Font.parse(allocator, alef_bytes);
    defer alef.deinit();
    var one = try Font.parse(allocator, one_bytes);
    defer one.deinit();
    var two = try Font.parse(allocator, two_bytes);
    defer two.deinit();
    var bet = try Font.parse(allocator, bet_bytes);
    defer bet.deinit();

    const fonts = [_]*const Font{ &alef, &one, &two, &bet };
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "\u{05d0}12\u{05d1}", 20, .{ .max_width = 200, .direction = .rtl });
    const clusters = try itemizeGraphemeClusters(allocator, "\u{05d0}12\u{05d1}");
    defer allocator.free(clusters);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, "\u{05d0}12\u{05d1}".len), paragraph.lines[0].byte_len);

    const after_alef = paragraph.nextGraphemeCaret(clusters, .{ .glyph_index = 3, .cluster = 0 });
    try std.testing.expectEqual(@as(usize, 1), after_alef.glyph_index);
    try std.testing.expectEqual(@as(usize, 2), after_alef.cluster);
    try std.testing.expect(!after_alef.trailing);

    const after_one = paragraph.nextGraphemeCaret(clusters, after_alef);
    try std.testing.expectEqual(@as(usize, 2), after_one.glyph_index);
    try std.testing.expectEqual(@as(usize, 3), after_one.cluster);
    try std.testing.expect(!after_one.trailing);

    const digit_selection = paragraph.selectionRectForBytes(2, 4);
    try std.testing.expect(digit_selection.width > 0);
    try std.testing.expect(digit_selection.x >= 0);
}

test "mixed bidi paragraphs wrap and reorder each visual line independently" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    // This test isolates per-line bidi ordering. The normal last-resort
    // fixture also carries a legacy kern pair for glyph 1; since every scalar
    // maps to that glyph, the pair intentionally makes every adjacent source
    // boundary unsafe and would turn this into a kern break-safety test.
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "AB אב 12 אב";
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, text, 20, .{
        .max_width = 60,
        .line_height = 24,
        .direction = .ltr,
    });

    try std.testing.expectEqual(@as(usize, 4), paragraph.lines.len);
    const expected_codepoints = [_][]const u21{
        &.{ 'A', 'B' },
        &.{ 0x05d1, 0x05d0 },
        &.{ '1', '2' },
        &.{ 0x05d1, 0x05d0 },
    };
    const expected_byte_starts = [_]usize{ 0, 3, 8, 11 };
    const expected_byte_lens = [_]usize{ 3, 5, 3, 4 };
    for (paragraph.lines, 0..) |line, line_index| {
        try std.testing.expectEqual(expected_byte_starts[line_index], line.byte_start);
        try std.testing.expectEqual(expected_byte_lens[line_index], line.byte_len);
        const line_glyphs = line.glyphs(paragraph);
        try std.testing.expectEqual(expected_codepoints[line_index].len, line_glyphs.len);
        for (line_glyphs, expected_codepoints[line_index]) |glyph, expected| {
            try std.testing.expectEqual(expected, glyph.codepoint);
        }
    }
    try std.testing.expectEqual(text.len, paragraph.lines[paragraph.lines.len - 1].byteEnd());
}

test "paragraph shaping retains logical order before per-line bidi reordering" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Logical Hebrew",
        "Regular",
        "Logical Hebrew Regular",
    );
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
        "אב",
        20,
        .{ .max_width = 100, .direction = .ltr },
    );
    defer paragraph.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, &.{
        paragraph.glyphs[0].cluster,
        paragraph.glyphs[1].cluster,
    });

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const visual = try paragraph.layout(&reflow, .{
        .max_width = 100,
        .direction = .ltr,
    });
    try std.testing.expectEqualSlices(usize, &.{ 2, 0 }, &.{
        visual.glyphs[0].cluster,
        visual.glyphs[1].cluster,
    });
}

test "logical and physical paragraph alignment stay distinct in RTL" {
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
    const start = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .rtl,
    });

    try std.testing.expectEqual(@as(usize, 1), start.lines.len);
    try std.testing.expectEqual(@as(u21, 'A'), start.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), start.glyphs[0].cluster);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), start.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), start.lines[0].x, 0.001);

    const end = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .rtl,
        .alignment = .end,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), end.lines[0].x, 0.001);

    const physical_left = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .rtl,
        .alignment = .left,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), physical_left.lines[0].x, 0.001);

    const physical_right = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .ltr,
        .alignment = .right,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), physical_right.lines[0].x, 0.001);

    const ltr_end = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .ltr,
        .alignment = .end,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), ltr_end.lines[0].x, 0.001);
}
