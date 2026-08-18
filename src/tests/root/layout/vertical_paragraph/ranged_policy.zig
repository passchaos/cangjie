//! Ranged and attributed wrapping policy for vertical columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "ranged vertical no-wrap defers emergency to the following range" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAABBBB";

    const layout_result = try layout(&font, &buffer, text, .{
        .max_width = 20.1,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 4,
            .wrap_mode = .no_wrap,
        }},
    });
    try std.testing.expect(layout_result.lines.len > 1);
    // The boundary after byte 4 belongs to the preceding no-wrap range. The
    // first legal emergency edge is after one scalar of the following range.
    try std.testing.expectEqual(@as(usize, 5), layout_result.lines[0].byte_len);

    const normal = try layout(&font, &buffer, text, .{
        .max_width = 20.1,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 4,
            .overflow_wrap = .normal,
        }},
    });
    try std.testing.expect(normal.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), normal.lines[0].byte_len);

    const hard = try layout(&font, &buffer, "AA\nAA", .{
        .max_width = 1,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = "AA\nAA".len,
            .wrap_mode = .no_wrap,
        }},
    });
    try std.testing.expectEqual(@as(usize, 2), hard.lines.len);
}

test "ranged vertical policy can re-enable global no-wrap" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const layout_result = try layout(&font, &buffer, "AAAABBBB", .{
        .max_width = 20.1,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 4,
            .byte_len = 4,
            .wrap_mode = .word,
            .overflow_wrap = .anywhere,
        }},
    });
    try std.testing.expect(layout_result.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), layout_result.lines[0].byte_len);
}

test "ranged vertical break-all and keep-all own preceding boundaries" {
    const allocator = std.testing.allocator;
    const latin_bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(latin_bytes);
    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const latin_result = try layout(&latin, &buffer, "AAAABBBB", .{
        .max_width = 20.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 4,
            .word_break = .break_all,
        }},
    });
    try std.testing.expectEqual(@as(usize, 5), latin_result.lines.len);
    for (latin_result.lines[0..4]) |line| {
        try std.testing.expectEqual(@as(usize, 1), line.byte_len);
    }
    try std.testing.expectEqual(
        @as(usize, 4),
        latin_result.lines[4].byte_len,
    );

    const cjk_bytes = try @import("../../../../test_font.zig")
        .buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(cjk_bytes);
    var cjk = try Font.parse(allocator, cjk_bytes);
    defer cjk.deinit();
    const text = "一丁丂";
    const first_len = "一".len;
    const cjk_result = try layout(&cjk, &buffer, text, .{
        .max_width = 40.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = first_len,
            .word_break = .keep_all,
        }},
    });
    try std.testing.expectEqual(@as(usize, 2), cjk_result.lines.len);
    try std.testing.expectEqual(
        @as(usize, "一丁".len),
        cjk_result.lines[0].byte_len,
    );
}

test "retained vertical paragraphs reflow ranged policy" {
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
        "AAAABBBB",
        20,
        .{
            .max_width = 200,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const ranges = [_]paragraph.LineBreakPolicyRange{.{
        .byte_start = 0,
        .byte_len = 4,
        .word_break = .break_all,
    }};

    const ranged = try shaped.layout(&reflow, .{
        .max_width = 20.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .line_break_policy_ranges = &ranges,
    });
    try std.testing.expectEqual(@as(usize, 5), ranged.lines.len);
    const widths = try shaped.contentWidths(.{
        .max_width = 20.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .line_break_policy_ranges = &ranges,
    });
    try std.testing.expect(widths.min < widths.max);

    const local_wrap_widths = try shaped.contentWidths(.{
        .max_width = 20.1,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
        .line_break_policy_ranges = &.{.{
            .byte_start = 4,
            .byte_len = 4,
            .wrap_mode = .word,
            .overflow_wrap = .anywhere,
        }},
    });
    try std.testing.expect(local_wrap_widths.min < local_wrap_widths.max);

    const inherited = try shaped.layout(&reflow, .{
        .max_width = 20.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), inherited.lines.len);
}

test "styled vertical paragraphs project and merge wrapping ranges" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAAABBBB";
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 1,
            .font_size = 20,
            .word_break = .break_all,
        },
        .{
            .byte_start = 4,
            .byte_len = 4,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const natural = try layout(&font, &buffer, text, .{
        .max_width = 200,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const wrapped = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = natural.glyphs[0].y_advance + 0.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 5), wrapped.lines.len);
    try std.testing.expectEqual(
        wrapped.glyphs.len,
        styled.glyphMetadata().len,
    );

    var merged = spans;
    merged[0].word_break = null;
    const merged_layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &merged,
        .{
            .max_width = natural.glyphs[0].y_advance + 0.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
            .line_break_policy_ranges = &.{.{
                .byte_start = 0,
                .byte_len = 4,
                .wrap_mode = .no_wrap,
            }},
        },
    );
    try std.testing.expect(merged_layout.lines.len > 1);
    try std.testing.expectEqual(
        @as(usize, 5),
        merged_layout.lines[0].byte_len,
    );

    var no_wrap_spans = spans;
    no_wrap_spans[0].word_break = null;
    no_wrap_spans[0].wrap_mode = .no_wrap;
    const attributed_no_wrap = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &no_wrap_spans,
        .{
            .max_width = natural.glyphs[0].y_advance + 0.1,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(attributed_no_wrap.lines.len > 1);
    try std.testing.expectEqual(
        @as(usize, 5),
        attributed_no_wrap.lines[0].byte_len,
    );
}
