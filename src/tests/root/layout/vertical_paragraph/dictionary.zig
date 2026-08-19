//! Dictionary-authored word boundaries in vertical paragraph flow.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const WordBreakDictionary = support.WordBreakDictionary;
const layout = policy_support.layout;

const short_text = "กขคง";

test "vertical one-shot layout consumes dictionary word boundaries" {
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

    const natural = try layout(&font, &buffer, short_text, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const one = natural.glyphs[0].y_advance;
    const without_dictionary = try layout(&font, &buffer, short_text, .{
        .max_width = one + 0.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // UAX #14 keeps this SA run indivisible when no language dictionary is
    // supplied, so normal overflow retains one overfull column.
    try std.testing.expectEqual(@as(usize, 1), without_dictionary.lines.len);

    const result = try layout(&font, &buffer, short_text, .{
        .max_width = one + 0.1,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectShortDictionaryColumns(result);
    try std.testing.expect(result.lines[0].x < result.lines[1].x);
}

test "vertical dictionary boundaries participate in balanced wrapping" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "กขค", "งจ", "ฉช", "ซฌญฎ" },
    );
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "กขคงจฉชซฌญฎ";

    const natural = try layout(&font, &buffer, text, .{
        .max_width = 400,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const limit = natural.glyphs[0].y_advance * 5 + 0.1;
    const greedy = try layout(&font, &buffer, text, .{
        .max_width = limit,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectGlyphCounts(greedy, &.{ 5, 2, 4 });

    const balanced = try layout(&font, &buffer, text, .{
        .max_width = limit,
        .line_break_strategy = .balanced,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectGlyphCounts(balanced, &.{ 3, 4, 4 });
    try std.testing.expectEqual(greedy.lines.len, balanced.lines.len);
}

test "vertical ranged policy tailors preceding dictionary boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "ก", "ข", "คง" },
    );
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, short_text, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const result = try layout(&font, &buffer, short_text, .{
        .max_width = natural.glyphs[0].y_advance + 0.1,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = "ก".len,
            .wrap_mode = .no_wrap,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // Boundary policy belongs to the preceding scalar. Suppressing the first
    // dictionary edge therefore makes the next authored edge own กข.
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, "กข".len), result.lines[0].byte_len);
    try std.testing.expectEqual(result.lines[0].byteEnd(), result.lines[1].byte_start);

    const reenabled = try layout(&font, &buffer, short_text, .{
        .max_width = natural.glyphs[0].y_advance + 0.1,
        .wrap_mode = .no_wrap,
        .overflow_wrap = .normal,
        .word_break_dictionary = &dictionary,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = "ก".len,
            .wrap_mode = .word,
        }},
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    // A local range can likewise re-enable the dictionary edge while the rest
    // of a globally no-wrap paragraph remains an indivisible suffix.
    try std.testing.expectEqual(@as(usize, 2), reenabled.lines.len);
    try std.testing.expectEqual(@as(usize, 1), reenabled.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), reenabled.lines[1].glyph_len);
}

fn shortDictionary(allocator: std.mem.Allocator) !WordBreakDictionary {
    return WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "ก", "ขคง" },
    );
}

fn expectShortDictionaryColumns(result: support.ParagraphLayout) !void {
    try expectGlyphCounts(result, &.{ 1, 3 });
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, "ก".len), result.lines[0].byte_len);
    try std.testing.expectEqual(result.lines[0].byteEnd(), result.lines[1].byte_start);
    try std.testing.expectEqual(short_text.len, result.lines[1].byteEnd());
}

fn expectGlyphCounts(
    result: support.ParagraphLayout,
    expected: []const usize,
) !void {
    try std.testing.expectEqual(expected.len, result.lines.len);
    for (result.lines, expected) |line, count| {
        try std.testing.expectEqual(count, line.glyph_len);
    }
}
