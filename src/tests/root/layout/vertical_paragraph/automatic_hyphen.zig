//! Liang-pattern automatic hyphenation in vertical paragraph columns.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Dictionary = @import("../../../../text/hyphenation/root.zig").Dictionary;
const Font = policy_support.Font;
const LayoutBuffer = policy_support.LayoutBuffer;
const layout = policy_support.layout;

const text = "hyphenation";

test "vertical automatic boundary inserts one source-neutral hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const wide = try layout(&font, &buffer, text, .{
        .max_width = 1000,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);
    const one = wide.glyphs[0].y_advance;
    for (wide.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }

    const wrapped = try layout(&font, &buffer, text, .{
        .max_width = one * 3 + 0.1,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(wrapped.lines.len >= 2);
    const first = wrapped.lines[0].glyphs(wrapped);
    const automatic = first[first.len - 1];
    try std.testing.expect(automatic.isAutomaticHyphen());
    try std.testing.expect(automatic.isDiscretionaryHyphen());
    try std.testing.expectEqual(@as(u21, 0x2010), automatic.codepoint);
    try std.testing.expectEqual(@as(usize, 2), automatic.cluster);
    try std.testing.expectEqual(@as(usize, 0), automatic.source_byte_len);
    try std.testing.expectEqual(@as(usize, 2), wrapped.lines[0].byteEnd());
    try std.testing.expectEqual(
        wrapped.lines[0].byteEnd(),
        wrapped.lines[1].byte_start,
    );
    try std.testing.expectApproxEqAbs(
        one * 3,
        wrapped.lines[0].height,
        0.001,
    );
}

test "vertical automatic hyphen supports balanced and custom characters" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, text, .{
        .max_width = 60.1,
        .line_break_strategy = .balanced,
        .hyphenation = .{
            .dictionary = &dictionary,
            .character = 0x2022,
        },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    var saw_custom = false;
    for (result.glyphs) |glyph| {
        if (!glyph.isAutomaticHyphen()) continue;
        saw_custom = true;
        try std.testing.expectEqual(@as(u21, 0x2022), glyph.codepoint);
    }
    try std.testing.expect(saw_custom);
}

test "vertical break-all and missing custom glyph suppress automatic hyphens" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const break_all = try layout(&font, &buffer, text, .{
        .max_width = 40.1,
        .word_break = .break_all,
        .overflow_wrap = .normal,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    for (break_all.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }

    const missing = try layout(&font, &buffer, text, .{
        .max_width = 60.1,
        .hyphenation = .{
            .dictionary = &dictionary,
            .character = 0x2603,
        },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    for (missing.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
}

test "vertical ranged policy can re-enable automatic hyphenation" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, text, .{
        .max_width = 60.1,
        .wrap_mode = .no_wrap,
        .hyphenation = .{ .dictionary = &dictionary },
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 2,
            .wrap_mode = .word,
        }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    const first = result.lines[0].glyphs(result);
    try std.testing.expect(first[first.len - 1].isAutomaticHyphen());
    try std.testing.expectEqual(@as(usize, 2), result.lines[0].byteEnd());
    // The suffix inherits global no-wrap and therefore remains one overfull
    // terminal column rather than consuming the later authored opportunity.
    try std.testing.expectEqual(
        text.len - 2,
        result.lines[1].byte_len,
    );
}

test "vertical consecutive hyphen limit resets after ordinary column" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            'a',
            'b',
            'c',
            'd',
            'e',
            'f',
            'g',
            'h',
            'i',
            'j',
            'k',
            'l',
            'm',
            'n',
            0x2010,
        },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try Dictionary.init(
        allocator,
        "a1b",
        "abc-def-ghi-jkl-mn",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    for ([_]@import("../../../../layout/types/paragraph.zig").LineBreakStrategy{
        .greedy,
        .balanced,
    }) |strategy| {
        const result = try layout(&font, &buffer, "abcdefghijklmn", .{
            .max_width = 80.1,
            .line_break_strategy = strategy,
            .hyphenation = .{
                .dictionary = &dictionary,
                .max_consecutive_lines = 1,
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        });
        var count: usize = 0;
        var previous = false;
        for (result.lines) |line| {
            var current = false;
            for (line.glyphs(result)) |glyph| {
                current = current or glyph.isAutomaticHyphen();
            }
            try std.testing.expect(!(previous and current));
            count += @intFromBool(current);
            previous = current;
        }
        try std.testing.expect(count >= 2);
    }

    const suppressed = try layout(&font, &buffer, "abcdefghijklmn", .{
        .max_width = 80.1,
        .line_break_strategy = .balanced,
        .hyphenation = .{
            .dictionary = &dictionary,
            .max_consecutive_lines = 0,
        },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    for (suppressed.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
}

test "vertical ellipsis removes automatic continuation hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, text, .{
        .max_width = 60.1,
        .max_lines = 1,
        .ellipsis = true,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    const first = result.lines[0].glyphs(result);
    for (first) |glyph| {
        try std.testing.expect(!glyph.isDiscretionaryHyphen());
    }
    try std.testing.expect(first.len >= 3);
    for (first[first.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}

test "vertical bidi keeps automatic hyphen at the visual column end" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            0x05d0,
            0x05d1,
            0x05d2,
            0x05d3,
            0x2010,
        },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try Dictionary.init(
        allocator,
        "א1ב",
        "אב-גד",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const bidi_text = "אבגד";

    const result = try layout(&font, &buffer, bidi_text, .{
        .max_width = 60.1,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(result.lines.len >= 2);
    const first = result.lines[0].glyphs(result);
    var automatic: ?support.GlyphPosition = null;
    for (first) |glyph| {
        if (glyph.isAutomaticHyphen()) automatic = glyph;
    }
    const hyphen = automatic orelse return error.TestExpectedAutomaticHyphen;
    try std.testing.expectEqual(@as(u21, 0x2010), hyphen.codepoint);
    try std.testing.expectEqual(@as(usize, "אב".len), hyphen.cluster);
    try std.testing.expectEqual(@as(usize, 0), hyphen.source_byte_len);
    try std.testing.expectEqual(@as(usize, "אב".len), result.lines[0].byteEnd());
    try std.testing.expectEqual(
        result.lines[0].byteEnd(),
        result.lines[1].byte_start,
    );
}

fn englishDictionary(allocator: std.mem.Allocator) !Dictionary {
    return Dictionary.init(
        allocator,
        "hyphenation",
        "hy-phen-ation",
        .{ .left_min = 2, .right_min = 2 },
    );
}

fn hyphenFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            '.',
            'a',
            'e',
            'h',
            'i',
            'n',
            'o',
            'p',
            't',
            'y',
            0x2010,
            0x2022,
        },
    );
}
