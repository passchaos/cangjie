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

test "balanced line breaking minimizes whole-paragraph raggedness" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});

    const text = "AAA AA AA A";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const greedy = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 80 },
    );
    try std.testing.expectEqual(@as(usize, 3), greedy.lines.len);
    try std.testing.expectEqual(@as(usize, 3), greedy.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 5), greedy.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 1), greedy.lines[2].glyph_len);

    const balanced_layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 80,
            .line_break_strategy = .balanced,
        },
    );
    try std.testing.expectEqual(greedy.lines.len, balanced_layout.lines.len);
    try std.testing.expectEqual(@as(usize, 3), balanced_layout.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), balanced_layout.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), balanced_layout.lines[2].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), balanced_layout.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), balanced_layout.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 4), balanced_layout.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 3), balanced_layout.lines[1].byte_len);
    try std.testing.expectEqual(@as(usize, 7), balanced_layout.lines[2].byte_start);
    try std.testing.expectEqual(text.len - 7, balanced_layout.lines[2].byte_len);
}

test "balanced reflow composes with retained hard breaks and line limits" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "AAA AA AA A\nAAA AA AA A";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        text,
        20,
        .{ .max_width = 1000 },
    );
    defer paragraph.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const balanced_layout = try paragraph.layout(&reflow, .{
        .max_width = 80,
        .line_break_strategy = .balanced,
    });
    try std.testing.expectEqual(@as(usize, 6), balanced_layout.lines.len);
    try std.testing.expectEqual(@as(usize, 3), balanced_layout.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), balanced_layout.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), balanced_layout.lines[2].glyph_len);
    try std.testing.expectEqual(
        @as(usize, "AAA AA AA A\n".len),
        balanced_layout.lines[3].byte_start,
    );
    try std.testing.expectEqual(@as(usize, 3), balanced_layout.lines[3].glyph_len);

    const ellipsized = try paragraph.layout(&reflow, .{
        .max_width = 80,
        .line_break_strategy = .balanced,
        .max_lines = 2,
        .ellipsis = true,
    });
    try std.testing.expectEqual(@as(usize, 2), ellipsized.lines.len);
    const terminal = ellipsized.lines[1].glyphs(ellipsized);
    try std.testing.expect(terminal.len >= 3);
    try std.testing.expectEqual(@as(u21, '.'), terminal[terminal.len - 1].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), terminal[terminal.len - 2].codepoint);
    try std.testing.expectEqual(@as(u21, '.'), terminal[terminal.len - 3].codepoint);

    const unbounded = try paragraph.layout(&reflow, .{
        .max_width = std.math.inf(f32),
        .line_break_strategy = .balanced,
    });
    try std.testing.expectEqual(@as(usize, 2), unbounded.lines.len);
    try std.testing.expectEqual(
        @as(usize, "AAA AA AA A".len),
        unbounded.lines[0].glyph_len,
    );

    const no_wrap = try paragraph.layout(&reflow, .{
        .max_width = 1,
        .wrap_mode = .no_wrap,
        .line_break_strategy = .balanced,
    });
    try std.testing.expectEqual(@as(usize, 2), no_wrap.lines.len);
    try std.testing.expectEqual(
        @as(usize, "AAA AA AA A".len),
        no_wrap.lines[0].glyph_len,
    );
}

test "overflow wrap distinguishes overflow emergency and anywhere" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAAAAAA";

    const overflow = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 33,
            .overflow_wrap = .normal,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), overflow.lines.len);
    try std.testing.expectEqual(text.len, overflow.lines[0].glyph_len);
    try std.testing.expect(overflow.lines[0].width > 33);

    const break_word = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 33,
            .overflow_wrap = .break_word,
        },
    );
    try std.testing.expectEqual(@as(usize, 4), break_word.lines.len);
    for (break_word.lines) |line| {
        try std.testing.expectEqual(@as(usize, 2), line.glyph_len);
    }

    const anywhere = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 33,
            .overflow_wrap = .anywhere,
        },
    );
    try std.testing.expectEqual(break_word.lines.len, anywhere.lines.len);
    for (anywhere.lines) |line| {
        try std.testing.expect(line.width <= 33.001);
    }
}

test "balanced break word prefers regular edges while anywhere may rebalance" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAA AAAA";

    const break_word = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 70,
            .line_break_strategy = .balanced,
            .overflow_wrap = .break_word,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), break_word.lines.len);
    // The whitespace opportunity fits, so break-word cannot replace it with
    // an arbitrary intra-word edge merely to improve raggedness.
    try std.testing.expectEqual(@as(usize, 4), break_word.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), break_word.lines[1].glyph_len);

    const anywhere = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 70,
            .line_break_strategy = .balanced,
            .overflow_wrap = .anywhere,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), anywhere.lines.len);
    for (anywhere.lines) |line| {
        try std.testing.expect(line.width <= 70.001);
    }
}

test "word break all and keep all tailor Unicode soft boundaries" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const ascii_bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(ascii_bytes);
    var ascii = try Font.parse(allocator, ascii_bytes);
    defer ascii.deinit();
    const cjk_bytes = try test_font.buildNamedCjkTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(cjk_bytes);
    var cjk = try Font.parse(allocator, cjk_bytes);
    defer cjk.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const break_all = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&ascii}),
        &buffer,
        "AAAA",
        20,
        .{
            .max_width = 17,
            .word_break = .break_all,
            .overflow_wrap = .normal,
        },
    );
    try std.testing.expectEqual(@as(usize, 4), break_all.lines.len);
    for (break_all.lines) |line| {
        try std.testing.expectEqual(@as(usize, 1), line.glyph_len);
    }

    const normal = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&cjk}),
        &buffer,
        "一丁丂",
        20,
        .{
            .max_width = 17,
            .overflow_wrap = .normal,
        },
    );
    try std.testing.expect(normal.lines.len > 1);

    const keep_all = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&cjk}),
        &buffer,
        "一丁丂",
        20,
        .{
            .max_width = 17,
            .word_break = .keep_all,
            .overflow_wrap = .normal,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), keep_all.lines.len);
    try std.testing.expect(keep_all.lines[0].width > 17);

    const spaced_keep_all = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&cjk}),
        &buffer,
        "一丁 丂",
        20,
        .{
            .max_width = 35,
            .word_break = .keep_all,
            .overflow_wrap = .normal,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), spaced_keep_all.lines.len);
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

test "JSTF maximum positioning is scaled to the line target" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfExpansionTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const paragraph = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "A A A A",
        20,
        .{
            .max_width = 50,
            .alignment = .justify,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 50),
        paragraph.lines[0].width,
        0.001,
    );
    // Natural "A A" is 42px. The JSTF maximum adds 12px to the space, but
    // line-local interpolation consumes only the 8px needed by this measure.
    try std.testing.expectApproxEqAbs(
        @as(f32, 18),
        paragraph.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        paragraph.glyphs[3].x_advance,
        0.001,
    );
}

test "JSTF priorities rebuild enabled and disabled GSUB GPOS lookups in order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfModificationTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    var natural = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &buffer,
        "A A A",
        20,
        .{
            .max_width = 60,
            .alignment = .justify,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    defer natural.deinit();
    try std.testing.expectEqual(@as(u32, 1), natural.glyphs[0].glyph_id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 16),
        natural.glyphs[0].x_advance,
        0.001,
    );

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const paragraph = try natural.layout(
        &reflow,
        .{
            .max_width = 60,
            .alignment = .justify,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );

    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        paragraph.lines[0].width,
        0.001,
    );
    // Priority zero would leave glyph 3 and narrow the line, so the accepted
    // priority must restart at source glyph 1. Reassembled GSUB lookups run
    // 0 -> 1 while disabled lookup 2 stays out, yielding glyph 4. A naive
    // post-shape enable would instead leave glyph 3.
    try std.testing.expectEqual(@as(u32, 4), paragraph.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u32, 4), paragraph.glyphs[2].glyph_id);
    // GPOS lookup zero supplies placement, lookup one supplies +2px advance,
    // and disabled lookup two must not subtract 1px.
    try std.testing.expectApproxEqAbs(
        @as(f32, 2),
        paragraph.glyphs[0].x_offset,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 26),
        paragraph.glyphs[0].x_advance,
        0.001,
    );

    // Repeat through Engine's lookup-selection/proof caches. JSTF enablement
    // must merge with the cached active set before execution rather than
    // mutating cache-owned slices or appending a second pass.
    var engine = support.Engine.init(allocator, .{});
    defer engine.deinit();
    const cached = try engine.layout(
        @import("../../../font/face/root.zig").Cascade.init(
            &.{@import("../../../font/face/root.zig").backend.face(&font)},
        ),
        .{
            .text = "A A A",
            .font_size = 20,
            .options = .{
                .max_width = 60,
                .alignment = .justify,
                .font_expansion = .{ .enabled = false },
                .kashida = .{ .enabled = false },
            },
        },
    );
    try std.testing.expectEqual(@as(u32, 4), cached.glyphs[0].glyph_id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 26),
        cached.glyphs[0].x_advance,
        0.001,
    );
    try std.testing.expect(engine.stats().lookup_selection.hits > 0);
}

test "JSTF shrinkage keeps an overflowing source prefix on the line" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfShrinkageTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const paragraph = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AAA AAA",
        20,
        .{
            .max_width = 44,
            .alignment = .justify,
            .letter_spacing = 1,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );

    // Natural "AAA" is 51px after letter spacing and would emergency-wrap.
    // Priority zero still cannot fit. Priority one restarts from source,
    // reaches glyph 3 through ordered GSUB, disables the final GPOS lookup,
    // then interpolates shrinkageJstfMax to the exact 44px measure.
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 44),
        paragraph.lines[0].width,
        0.001,
    );
    for (paragraph.glyphs[0..3]) |glyph| {
        try std.testing.expectEqual(@as(u32, 3), glyph.glyph_id);
        try std.testing.expectApproxEqAbs(
            @as(f32, 1),
            glyph.x_offset,
            0.001,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, 44.0 / 3.0),
            glyph.x_advance,
            0.001,
        );
    }
    try std.testing.expectEqual(@as(u32, 2), paragraph.glyphs[3].glyph_id);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines[1].glyph_start);

    // The retained paragraph path owns pristine source geometry and must make
    // the same shrinkage decision on every reflow without accumulating it.
    var retained = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &buffer,
        "AAA AAA",
        20,
        .{
            .max_width = 100,
            .alignment = .justify,
            .letter_spacing = 1,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    defer retained.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const first = try retained.layout(
        &reflow,
        .{
            .max_width = 44,
            .alignment = .justify,
            .letter_spacing = 1,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), first.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 44),
        first.lines[0].width,
        0.001,
    );
    const repeated = try retained.layout(
        &reflow,
        .{
            .max_width = 44,
            .alignment = .justify,
            .letter_spacing = 1,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(u32, 3), repeated.glyphs[0].glyph_id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 44),
        repeated.lines[0].width,
        0.001,
    );

    // Engine's one-shot layout binds lookup-selection and proof caches to the
    // candidate buffer without changing the retained public API.
    var engine = support.Engine.init(allocator, .{});
    defer engine.deinit();
    const cached = try engine.layout(
        @import("../../../font/face/root.zig").Cascade.init(
            &.{@import("../../../font/face/root.zig").backend.face(&font)},
        ),
        .{
            .text = "AAA AAA",
            .font_size = 20,
            .options = .{
                .max_width = 44,
                .alignment = .justify,
                .letter_spacing = 1,
                .font_expansion = .{ .enabled = false },
                .kashida = .{ .enabled = false },
            },
        },
    );
    try std.testing.expectEqual(@as(u32, 3), cached.glyphs[0].glyph_id);
    try std.testing.expect(engine.stats().lookup_selection.hits > 0);
}

test "JSTF shrinkage preserves styled glyph metadata alignment" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfShrinkageTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAA AAA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 17,
        .font_size = 20,
        .letter_spacing = 1,
    }};

    const paragraph = try TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 44,
            .alignment = .justify,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(
        paragraph.glyphs.len,
        styled.glyphMetadata().len,
    );
    for (styled.glyphMetadata()) |metadata| {
        try std.testing.expectEqual(@as(u32, 17), metadata.style_index);
    }
    try std.testing.expectEqual(@as(u32, 3), paragraph.glyphs[0].glyph_id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 44),
        paragraph.lines[0].width,
        0.001,
    );
}

test "balanced styled probe rolls back JSTF shrinkage metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfShrinkageTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAA AAA AAA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 23,
        .font_size = 20,
        .letter_spacing = 1,
    }};

    const paragraph = try TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 44,
            .alignment = .justify,
            .line_break_strategy = .balanced,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expect(paragraph.lines.len >= 2);
    try std.testing.expectEqual(
        paragraph.glyphs.len,
        styled.glyphMetadata().len,
    );
    for (styled.glyphMetadata()) |metadata| {
        try std.testing.expectEqual(@as(u32, 23), metadata.style_index);
    }
}

test "JSTF shrinkage updates later line and run indexes after ligature collapse" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildJstfCardinalityShrinkageTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const paragraph = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AA AA",
        20,
        .{
            .max_width = 30,
            .alignment = .justify,
            .font_expansion = .{ .enabled = false },
            .kashida = .{ .enabled = false },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(u32, 3), paragraph.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[1].glyph_start);
    var run_coverage: usize = 0;
    for (paragraph.runs) |run| {
        try std.testing.expectEqual(run_coverage, run.glyph_start);
        run_coverage += run.glyph_len;
    }
    try std.testing.expectEqual(paragraph.glyphs.len, run_coverage);
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        paragraph.lines[0].width,
        0.001,
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
