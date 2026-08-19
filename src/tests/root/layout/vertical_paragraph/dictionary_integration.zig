//! Retained and styled integration for vertical dictionary segmentation.

const std = @import("std");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const WordBreakDictionary = support.WordBreakDictionary;

const short_text = "กขคง";

test "retained vertical dictionary reflow preserves intrinsic analysis" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try shortDictionary(allocator);
    defer dictionary.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        short_text,
        20,
        .{
            .max_width = 200,
            .word_break_dictionary = &dictionary,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine = try allocator.dupe(@TypeOf(shaped.glyphs[0]), shaped.glyphs);
    defer allocator.free(pristine);
    const one = shaped.glyphs[0].y_advance;
    const widths = try shaped.contentWidths(.{
        .max_width = 200,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(one * 3, widths.min, 0.001);
    try std.testing.expectApproxEqAbs(one * 4, widths.max, 0.001);

    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const wrapped = try shaped.layout(&reflow, .{
        .max_width = one + 0.1,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectShortDictionaryColumns(wrapped);
    try std.testing.expect(wrapped.lines[0].x > wrapped.lines[1].x);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );
    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        shaped.layout(&reflow, .{
            .max_width = one + 0.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );
}

test "styled vertical dictionary keeps metadata and intrinsic widths parallel" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try shortDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const first_word_len = "ก".len;
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = first_word_len,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = first_word_len,
            .byte_len = short_text.len - first_word_len,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const natural = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        short_text,
        20,
        &spans,
        .{
            .max_width = 200,
            .wrap_mode = .no_wrap,
            .word_break_dictionary = &dictionary,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    const one = natural.glyphs[0].y_advance;
    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        short_text,
        20,
        &spans,
        .{
            .max_width = one + 0.1,
            .overflow_wrap = .normal,
            .word_break_dictionary = &dictionary,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectShortDictionaryColumns(result);
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    try std.testing.expectEqual(@as(u32, 1), styled.glyphMetadata()[0].style_index);
    try std.testing.expectEqual(@as(u32, 2), styled.glyphMetadata()[1].style_index);
    const widths = styled.contentWidths().?;
    try std.testing.expectApproxEqAbs(one * 3, widths.min, 0.001);
    try std.testing.expectApproxEqAbs(one * 4, widths.max, 0.001);
}

fn shortDictionary(allocator: std.mem.Allocator) !WordBreakDictionary {
    return WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "ก", "ขคง" },
    );
}

fn expectShortDictionaryColumns(result: support.ParagraphLayout) !void {
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), result.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, "ก".len), result.lines[0].byte_len);
    try std.testing.expectEqual(result.lines[0].byteEnd(), result.lines[1].byte_start);
    try std.testing.expectEqual(short_text.len, result.lines[1].byteEnd());
}
