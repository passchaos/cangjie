//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphPosition = support.GlyphPosition;
const FontCascade = support.FontCascade;
const ReflowBuffer = support.ReflowBuffer;
const testing = support.testing;
const lineAdvanceSum = support.lineAdvanceSum;

test "wraps CJK text at character boundaries without spaces" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "一丁丂", 20, .{
        .max_width = 32,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), paragraph.lines[1].width, 0.001);
    try std.testing.expectEqual(@as(u21, 0x4e00), paragraph.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x4e01), paragraph.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x4e02), paragraph.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(usize, 0), paragraph.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 6), paragraph.glyphs[2].cluster);
}

test "paragraph wrapping keeps combining grapheme clusters atomic" {
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
        .max_width = 20,
        .line_height = 24,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 'A'), paragraph.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x0301), paragraph.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), paragraph.glyphs[2].codepoint);
    try std.testing.expectEqual(@as(usize, 0), paragraph.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 1), paragraph.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs[2].cluster);
}

test "paragraph wrapping keeps multiple-substitution glyph atoms together" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMultipleGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", 20, .{
        .max_width = 1,
        .line_height = 24,
    });

    // Both output glyphs represent the same source scalar. Breaking between
    // them would create a line boundary with no corresponding source caret.
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(paragraph.glyphs[0].cluster, paragraph.glyphs[1].cluster);
}

test "extremely narrow wrapping skips leading spaces after an emergency line" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &layout_buffer,
        "A A A",
        20,
        .{ .max_width = 100 },
    );
    defer paragraph.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const narrow = try paragraph.layout(&reflow, .{ .max_width = 15 });
    try std.testing.expectEqual(@as(usize, 3), narrow.lines.len);
    for (narrow.lines) |line| {
        try std.testing.expectEqual(@as(usize, 1), line.glyph_len);
    }
}

test "paragraph wrapping consumes Unicode line break data" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const ascii_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ascii_bytes);
    var ascii_font = try Font.parse(allocator, ascii_bytes);
    defer ascii_font.deinit();
    const ascii_fonts = [_]*const Font{&ascii_font};
    const ascii_cascade = FontCascade.init(&ascii_fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const crlf = try TextShaper.layoutParagraphUtf8(ascii_cascade, &layout_buffer, "A\r\nA", 20, .{
        .max_width = 80,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), crlf.lines.len);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), crlf.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), crlf.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 3), crlf.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 1), crlf.lines[1].byte_len);
    try std.testing.expectEqual(@as(u21, 'A'), crlf.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'A'), crlf.glyphs[3].codepoint);

    const cjk_bytes = try test_font.buildNamedCjkTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(cjk_bytes);
    var cjk_font = try Font.parse(allocator, cjk_bytes);
    defer cjk_font.deinit();
    const cjk_fonts = [_]*const Font{&cjk_font};
    const cjk_cascade = FontCascade.init(&cjk_fonts);

    const ivs = try TextShaper.layoutParagraphUtf8(cjk_cascade, &layout_buffer, "\u{4e00}\u{e0100}丁", 20, .{
        .max_width = 20,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), ivs.lines.len);
    try std.testing.expectEqual(@as(usize, 1), ivs.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), ivs.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x4e00), ivs.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), ivs.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 7), ivs.glyphs[0].source_byte_len);
    try std.testing.expectEqual(@as(usize, 7), ivs.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, 0), ivs.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 7), ivs.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 7), ivs.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 3), ivs.lines[1].byte_len);
}

test "soft hyphen becomes visible only at a selected wrap" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const font_bytes = try test_font.buildCodepointSetTtf(allocator, &.{
        0x0020,
        0x002d,
        'a',
        'c',
        'e',
        'o',
        'p',
        'r',
        't',
        0x00ad,
        0x2010,
    });
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    const text = "co\u{00ad}operate";

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const unwrapped = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 1000 },
    );
    try std.testing.expectEqual(@as(usize, 1), unwrapped.lines.len);
    try std.testing.expectEqual(@as(u21, 0x00ad), unwrapped.glyphs[2].codepoint);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        unwrapped.glyphs[2].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        unwrapped.selectionRectForBytes(2, 4).width,
        0.001,
    );

    const hyphen_glyph = try font.glyphIndex(0x2010);
    const hyphen_metrics = try font.horizontalMetrics(hyphen_glyph);
    const hyphen_width = @as(
        f32,
        @floatFromInt(hyphen_metrics.advance_width),
    ) * (20.0 / @as(f32, @floatFromInt(font.units_per_em)));
    const first_line_width =
        unwrapped.glyphs[0].x_advance +
        unwrapped.glyphs[1].x_advance +
        hyphen_width +
        0.5;
    const wrapped = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = first_line_width },
    );
    try std.testing.expect(wrapped.lines.len >= 2);
    try std.testing.expectEqual(@as(usize, 3), wrapped.lines[0].glyph_len);
    try std.testing.expect(
        wrapped.glyphs[wrapped.lines[0].glyph_start + 2].codepoint == 0x2010 or
            wrapped.glyphs[wrapped.lines[0].glyph_start + 2].codepoint == '-',
    );
    try std.testing.expect(
        wrapped.glyphs[wrapped.lines[0].glyph_start + 2].x_advance > 0,
    );
    try std.testing.expectEqual(@as(usize, 0), wrapped.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), wrapped.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 4), wrapped.lines[1].byte_start);
    try std.testing.expect(
        wrapped.selectionRectForBytes(2, 4).width > 0,
    );
    for (wrapped.lines[1..], 1..) |line, line_index| {
        try std.testing.expectEqual(
            wrapped.lines[line_index - 1].byteEnd(),
            line.byte_start,
        );
    }
    try std.testing.expectEqual(
        text.len,
        wrapped.lines[wrapped.lines.len - 1].byteEnd(),
    );

    const spaced = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 1000, .letter_spacing = 7 },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        spaced.glyphs[2].x_advance,
        0.001,
    );

    const rtl_text = "اب\u{00ad}جد";
    const rtl_unwrapped = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        rtl_text,
        20,
        .{ .max_width = 1000, .direction = .rtl },
    );
    const rtl_width =
        rtl_unwrapped.glyphs[0].x_advance +
        rtl_unwrapped.glyphs[1].x_advance +
        hyphen_width +
        0.5;
    const rtl_wrapped = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        rtl_text,
        20,
        .{ .max_width = rtl_width, .direction = .rtl },
    );
    try std.testing.expect(rtl_wrapped.lines.len >= 2);
    const rtl_first = rtl_wrapped.lines[0].glyphs(rtl_wrapped);
    try std.testing.expect(rtl_first.len != 0);
    try std.testing.expect(rtl_first[0].isDiscretionaryHyphen());
}

test "retained reflow restores an unselected soft hyphen" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const font_bytes = try test_font.buildCodepointSetTtf(allocator, &.{
        0x0020,
        0x002d,
        'a',
        'c',
        'e',
        'o',
        'p',
        'r',
        't',
        0x00ad,
        0x2010,
    });
    defer allocator.free(font_bytes);
    var font = try Font.parse(allocator, font_bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "co\u{00ad}operate",
        20,
        .{ .max_width = 1000 },
    );
    defer paragraph.deinit();
    try std.testing.expectEqual(@as(u21, 0x00ad), paragraph.glyphs[2].codepoint);
    try std.testing.expectApproxEqAbs(@as(f32, 0), paragraph.glyphs[2].x_advance, 0.001);
    const pristine_glyphs = try allocator.dupe(GlyphPosition, paragraph.glyphs);
    defer allocator.free(pristine_glyphs);

    const hyphen_metrics = try font.horizontalMetrics(try font.glyphIndex(0x2010));
    const narrow_width =
        paragraph.glyphs[0].x_advance +
        paragraph.glyphs[1].x_advance +
        @as(f32, @floatFromInt(hyphen_metrics.advance_width)) *
            (20.0 / @as(f32, @floatFromInt(font.units_per_em))) +
        0.5;
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try paragraph.layout(&reflow, .{ .max_width = narrow_width });
    try std.testing.expect(narrow.lines.len >= 2);
    try std.testing.expectEqual(@as(u21, 0x2010), narrow.glyphs[2].codepoint);
    try std.testing.expect(narrow.glyphs[2].x_advance > 0);

    const wide = try paragraph.layout(&reflow, .{ .max_width = 1000 });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);
    try std.testing.expectEqual(@as(u21, 0x00ad), wide.glyphs[2].codepoint);
    try std.testing.expectApproxEqAbs(@as(f32, 0), wide.glyphs[2].x_advance, 0.001);
    try std.testing.expectEqual(@as(u21, 0x00ad), paragraph.glyphs[2].codepoint);
    try std.testing.expectEqualSlices(GlyphPosition, pristine_glyphs, paragraph.glyphs);

    const ellipsized = try paragraph.layout(&reflow, .{
        .max_width = narrow_width,
        .max_lines = 1,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    for (ellipsized.lines[0].glyphs(ellipsized)) |glyph| {
        try std.testing.expect(!glyph.isDiscretionaryHyphen());
    }
}

test "paragraph layout preserves an empty caret line after trailing newline" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\n", 20, .{
        .max_width = 80,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[1].glyph_len);
    try std.testing.expectEqual(paragraph.glyphs.len, paragraph.lines[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[1].byte_len);
}

test "paragraph wrapping honors UAX 14 punctuation and no-break glue" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const cjk_bytes = try test_font.buildNamedCjkTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(cjk_bytes);
    var cjk_font = try Font.parse(allocator, cjk_bytes);
    defer cjk_font.deinit();
    const cjk_fonts = [_]*const Font{&cjk_font};
    const cjk_cascade = FontCascade.init(&cjk_fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const punctuation = try TextShaper.layoutParagraphUtf8(cjk_cascade, &layout_buffer, "你。好", 20, .{
        .max_width = 20,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), punctuation.lines.len);
    try std.testing.expectEqual(@as(usize, 2), punctuation.lines[0].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x4f60), punctuation.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x3002), punctuation.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(u21, 0x597d), punctuation.glyphs[2].codepoint);

    const ascii_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ascii_bytes);
    var ascii_font = try Font.parse(allocator, ascii_bytes);
    defer ascii_font.deinit();
    const ascii_fonts = [_]*const Font{&ascii_font};
    const ascii_cascade = FontCascade.init(&ascii_fonts);
    const glued = try TextShaper.layoutParagraphUtf8(ascii_cascade, &layout_buffer, "A A\u{00a0}A", 20, .{
        .max_width = 50,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), glued.lines.len);
    try std.testing.expectEqual(@as(usize, 1), glued.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), glued.lines[1].glyph_len);
    try std.testing.expectEqual(@as(u21, 0x00a0), glued.glyphs[3].codepoint);
}

test "paragraph no-wrap mode preserves explicit hard breaks" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A\nA A", 20, .{
        .max_width = 10,
        .wrap_mode = .no_wrap,
        .line_height = 24,
    });
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[1].glyph_len);
    try std.testing.expect(paragraph.lines[0].width > 10);
    try std.testing.expect(paragraph.lines[1].width > 10);
}

test "paragraph justification expands only non-terminal soft-wrapped lines" {
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
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A A", 20, .{
        .max_width = 50,
        .line_height = 24,
        .alignment = .justify,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 18), paragraph.glyphs[1].x_advance, 0.001);

    // Caret and selection geometry consume the expanded advance instead of a
    // second, renderer-only spacing sidecar.
    const after_space = paragraph.caretRect(.{
        .glyph_index = paragraph.lines[0].glyph_start + 2,
        .cluster = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 34), after_space.x, 0.001);
    const first_line_selection = try paragraph.selectionRects(allocator, 0, 3);
    defer allocator.free(first_line_selection);
    try std.testing.expectEqual(@as(usize, 1), first_line_selection.len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), first_line_selection[0].width, 0.001);
}

test "paragraph justification skips hard breaks tabs and lines without spaces" {
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
    const hard_break = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A\nA A", 20, .{
        .max_width = 80,
        .line_height = 24,
        .alignment = .justify,
    });
    try std.testing.expectEqual(@as(usize, 2), hard_break.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 42), hard_break.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 42), hard_break.lines[1].width, 0.001);

    const natural_tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA A", 20, .{
        .max_width = 80,
        .line_height = 24,
        .alignment = .left,
    });
    try std.testing.expectEqual(@as(usize, 2), natural_tabs.lines.len);
    const natural_tab_line_width = natural_tabs.lines[0].width;
    const natural_tab_advance = natural_tabs.glyphs[1].x_advance;

    const tabs = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\tA A", 20, .{
        .max_width = 80,
        .line_height = 24,
        .alignment = .justify,
    });
    try std.testing.expectEqual(@as(usize, 2), tabs.lines.len);
    try std.testing.expectApproxEqAbs(natural_tab_line_width, tabs.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(natural_tab_advance, tabs.glyphs[1].x_advance, 0.001);

    const cjk_bytes = try test_font.buildNamedCjkTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(cjk_bytes);
    var cjk_font = try Font.parse(allocator, cjk_bytes);
    defer cjk_font.deinit();
    const cjk_fonts = [_]*const Font{&cjk_font};
    const cjk = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&cjk_fonts),
        &layout_buffer,
        "一丁丂",
        20,
        .{
            .max_width = 32,
            .line_height = 24,
            .alignment = .justify,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), cjk.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 32), cjk.lines[0].width, 0.001);
}

test "truncated terminal line is not justified" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "A A A A",
        20,
        .{
            .max_width = 50,
            .max_lines = 1,
            .alignment = .justify,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(
        lineAdvanceSum(paragraph.lines[0].glyphs(paragraph)),
        paragraph.lines[0].width,
        0.001,
    );
    try std.testing.expect(paragraph.lines[0].width < 50);
}

test "justification expands a variable width axis before spacing" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildWidthVariationTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text = "A A A A";
    const expanded = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 50,
            .alignment = .justify,
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), expanded.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 50),
        expanded.lines[0].width,
        0.001,
    );
    try std.testing.expect(expanded.runs[0].variation_coord_len == 1);
    const expanded_shaped = support.ShapedText{
        .glyphs = expanded.glyphs,
        .runs = expanded.runs,
        .normalized_variation_coords = expanded.normalized_variation_coords,
    };
    const axis_value =
        expanded.runs[0].normalizedVariationCoords(expanded_shaped)[0];
    try std.testing.expect(axis_value > 0 and axis_value <= 1);
    const expanded_space_advance = expanded.glyphs[1].x_advance;

    const spacing_only = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 50,
            .alignment = .justify,
            .kashida = .{ .enabled = false },
            .font_expansion = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 0), spacing_only.runs[0].variation_coord_len);
    try std.testing.expect(
        spacing_only.glyphs[1].x_advance >
            expanded_space_advance,
    );
}

test "right-to-left justification keeps line origin and survives bidi reorder" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "אב אב אב", 20, .{
        .max_width = 80,
        .line_height = 24,
        .direction = .rtl,
        .alignment = .justify,
    });

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 80), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), paragraph.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), paragraph.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80), lineAdvanceSum(paragraph.lines[0].glyphs(paragraph)), 0.001);
}
