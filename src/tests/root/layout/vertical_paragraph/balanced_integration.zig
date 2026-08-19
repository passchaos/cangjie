//! Policy, tab, retained, and styled integration for vertical balancing.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical balanced measures aligned tabs and signed spacing per edge" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\tAA AA AA A";

    const result = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .letter_spacing = -2,
        .tab_stops = &.{.{
            .position = 90,
            .alignment = .end,
        }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(result.lines.len > 1);
    try std.testing.expect(result.glyphs[1].isTab());
    for (result.lines) |line| {
        try std.testing.expect(line.height <= 100.001);
    }
}

test "vertical balanced honors ranged emergency policy" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAABBBB";

    const result = try layout(&font, &buffer, text, .{
        .max_width = 20.1,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 4,
            .wrap_mode = .no_wrap,
        }},
    });
    try std.testing.expect(result.lines.len > 1);
    // The boundary after byte 4 belongs to the preceding no-wrap range. The
    // first legal emergency edge remains after one scalar of the next range.
    try std.testing.expectEqual(@as(usize, 5), result.lines[0].byte_len);
}

test "vertical balanced penalizes break-word but may use anywhere edges" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAA AAAA";

    const break_word = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .overflow_wrap = .break_word,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), break_word.lines.len);
    // A fitting ordinary space edge exists, so emergency word-internal edges
    // must not replace it merely to improve visual balance.
    try std.testing.expectEqual(@as(usize, 5), break_word.lines[0].byte_len);

    const anywhere = try layout(&font, &buffer, text, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), anywhere.lines.len);
    for (anywhere.lines) |line| {
        try std.testing.expect(line.height <= 100.001);
    }
}

test "vertical balanced whitespace edges retain contiguous source ownership" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A   A   A";

    const collapsed = try layout(&font, &buffer, text, .{
        .max_width = 20.1,
        .line_break_strategy = .balanced,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectContiguousSourceRanges(collapsed, text.len);
    try std.testing.expect(collapsed.lines.len >= 3);
    // The visible glyph range omits the discarded blanks, but the preceding
    // column continues to own them in its logical source interval.
    try std.testing.expectEqual(@as(usize, 4), collapsed.lines[0].byteEnd());
    try std.testing.expectEqual(@as(usize, 1), collapsed.lines[0].glyph_len);
    try std.testing.expectEqual(
        collapsed.lines[0].byteEnd(),
        collapsed.lines[1].byte_start,
    );

    const break_spaces = try layout(&font, &buffer, text, .{
        .max_width = 20.1,
        .line_break_strategy = .balanced,
        .white_space_collapse = .break_spaces,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectContiguousSourceRanges(break_spaces, text.len);
    try std.testing.expect(break_spaces.lines.len > collapsed.lines.len);
    var saw_owned_space = false;
    for (break_spaces.lines) |line| {
        if (line.glyph_len == 0) continue;
        const final_glyph =
            break_spaces.glyphs[line.glyph_start + line.glyph_len - 1];
        if (final_glyph.codepoint == ' ' and final_glyph.y_advance > 0) {
            saw_owned_space = true;
        }
    }
    try std.testing.expect(saw_owned_space);
}

test "retained vertical balanced reflow restores and limits source output" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const text = "AAA AA AA A";
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 200,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine_len = shaped.glyphs.len;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const balanced = try shaped.layout(&reflow, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectGlyphCounts(balanced, &.{ 3, 2, 4 });

    const ellipsized = try shaped.layout(&reflow, .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .max_lines = 2,
        .ellipsis = true,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), ellipsized.lines.len);
    const terminal = ellipsized.lines[1].glyphs(ellipsized);
    try std.testing.expect(terminal.len >= 3);
    for (terminal[terminal.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }

    const restored = try shaped.layout(&reflow, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), restored.lines.len);
    try std.testing.expectEqual(pristine_len, restored.glyphs.len);
    try std.testing.expectEqual(pristine_len, shaped.glyphs.len);
}

test "styled vertical balanced keeps metadata parallel to selected columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const text = "AAA AA AA A";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 4,
            .byte_len = text.len - 4,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .line_break_strategy = .balanced,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectGlyphCounts(result, &.{ 3, 2, 4 });
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
    try std.testing.expectEqual(@as(u32, 1), styled.glyphMetadata()[0].style_index);
    try std.testing.expectEqual(@as(u32, 2), styled.glyphMetadata()[4].style_index);
}

test "vertical balanced ranges feed final column-local bidi order" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "Aאב Bגד C";

    const result = try layout(&font, &buffer, text, .{
        .max_width = 80.1,
        .line_break_strategy = .balanced,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    // Each selected source-order range enters the existing column-local UAX #9
    // pass; the Hebrew subruns reverse without crossing either soft boundary.
    try expectLineClusters(result, 0, &.{ 0, 3, 1 });
    try expectLineClusters(result, 1, &.{ 6, 9, 7 });
    try expectLineClusters(result, 2, &.{12});
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    for (result.lines[1..], result.lines[0 .. result.lines.len - 1]) |
        current,
        previous,
    | {
        try std.testing.expectEqual(previous.byteEnd(), current.byte_start);
    }
    for (result.lines) |line| {
        try std.testing.expect(line.height <= 80.101);
    }
}

fn expectGlyphCounts(
    result: support.ParagraphLayout,
    expected: []const usize,
) !void {
    try std.testing.expectEqual(expected.len, result.lines.len);
    for (result.lines, expected) |line, glyph_count| {
        try std.testing.expectEqual(glyph_count, line.glyph_len);
    }
}

fn expectContiguousSourceRanges(
    result: support.ParagraphLayout,
    text_len: usize,
) !void {
    try std.testing.expect(result.lines.len != 0);
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    for (result.lines[1..], result.lines[0 .. result.lines.len - 1]) |
        current,
        previous,
    | {
        try std.testing.expectEqual(previous.byteEnd(), current.byte_start);
    }
    try std.testing.expectEqual(
        text_len,
        result.lines[result.lines.len - 1].byteEnd(),
    );
}

fn expectLineClusters(
    result: support.ParagraphLayout,
    line_index: usize,
    expected: []const usize,
) !void {
    const line = result.lines[line_index];
    const glyphs =
        result.glyphs[line.glyph_start .. line.glyph_start + line.glyph_len];
    try std.testing.expectEqual(expected.len, glyphs.len);
    for (glyphs, expected) |glyph, cluster| {
        try std.testing.expectEqual(cluster, glyph.cluster);
    }
}
