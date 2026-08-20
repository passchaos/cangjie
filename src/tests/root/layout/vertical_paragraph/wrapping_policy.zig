//! Global wrapping policy for vertical columns.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical overflow wrap normal preserves an overfull word" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "AAAA AA", .{
        .max_width = 200,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const one = natural.glyphs[0].y_advance;
    const normal = try layout(&font, &buffer, "AAAA AA", .{
        .max_width = one * 2 + 0.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), normal.lines.len);
    try std.testing.expectEqual(@as(usize, 4), normal.lines[0].glyph_len);
    try std.testing.expect(normal.lines[0].height > one * 2);

    const emergency = try layout(&font, &buffer, "AAAA AA", .{
        .max_width = one * 2 + 0.1,
        .overflow_wrap = .break_word,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), emergency.lines.len);
    try std.testing.expectEqual(@as(usize, 2), emergency.lines[0].glyph_len);
}

test "vertical break all and anywhere expose ordinary grapheme candidates" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "AAAA", .{
        .max_width = 200,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const one = natural.glyphs[0].y_advance;
    const break_all = try layout(&font, &buffer, "AAAA", .{
        .max_width = one * 2 + 0.1,
        .word_break = .break_all,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), break_all.lines.len);
    try std.testing.expectEqual(@as(usize, 2), break_all.lines[0].glyph_len);

    const anywhere = try layout(&font, &buffer, "AAAA", .{
        .max_width = one * 2 + 0.1,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), anywhere.lines.len);
    try std.testing.expectEqual(@as(usize, 2), anywhere.lines[0].glyph_len);

    const no_wrap = try layout(&font, &buffer, "AAAA", .{
        .max_width = one,
        .wrap_mode = .no_wrap,
        .word_break = .break_all,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), no_wrap.lines.len);
}

test "vertical keep all suppresses CJK opportunities" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const natural = try layout(&font, &buffer, "你好你", .{
        .max_width = 200,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const one = natural.glyphs[0].y_advance;
    const kept = try layout(&font, &buffer, "你好你", .{
        .max_width = one + 0.1,
        .word_break = .keep_all,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), kept.lines.len);
    try std.testing.expectEqual(@as(usize, 3), kept.lines[0].glyph_len);

    const emergency = try layout(&font, &buffer, "你好你", .{
        .max_width = one + 0.1,
        .word_break = .keep_all,
        .overflow_wrap = .break_word,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), emergency.lines.len);
}

test "retained vertical widths and reflow follow global policy" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "AAAA",
        20,
        .{
            .max_width = 100,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();

    const normal = try shaped.contentWidths(.{
        .max_width = 100,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(normal.max, normal.min, 0.001);
    const anywhere = try shaped.contentWidths(.{
        .max_width = 100,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(anywhere.min < anywhere.max);
    try std.testing.expectApproxEqAbs(
        shaped.glyphs[0].y_advance,
        anywhere.min,
        0.001,
    );

    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const break_all = try shaped.layout(&reflow, .{
        .max_width = shaped.glyphs[0].y_advance * 2 + 0.1,
        .word_break = .break_all,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), break_all.lines.len);
}
