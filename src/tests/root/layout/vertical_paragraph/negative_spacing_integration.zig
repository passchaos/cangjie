//! Retained and styled integration for safe vertical negative spacing.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "retained vertical negative spacing and intrinsic widths restore exactly" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
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
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const compressed = try shaped.layout(&reflow, .{
        .max_width = 32.1,
        .word_break = .break_all,
        .letter_spacing = -4,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), compressed.lines.len);
    const widths = try shaped.contentWidths(.{
        .max_width = 32.1,
        .word_break = .break_all,
        .letter_spacing = -4,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 16), widths.min, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 64), widths.max, 0.001);
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        shaped.contentWidths(.{
            .max_width = 100,
            .letter_spacing = -20.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );

    const restored = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), restored.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 80), restored.height, 0.001);
    for (shaped.glyphs) |glyph| {
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
    }
}

test "styled vertical negative spacing validates final advances" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "A A";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 5,
        .font_size = 20,
        .letter_spacing = -3,
        .word_spacing = -5,
    }};

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .letter_spacing = -2,
            .word_spacing = -4,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 15), result.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), result.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15), result.glyphs[2].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 36), result.height, 0.001);
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    const content_widths = styled.contentWidths().?;
    try std.testing.expectApproxEqAbs(@as(f32, 36), content_widths.max, 0.001);

    const invalid_spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = 1,
        .style_index = 6,
        .font_size = 20,
        .letter_spacing = -20.1,
    }};
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        TextShaper.layoutStyledParagraphUtf8(
            FontCascade.init(&.{&font}),
            &buffer,
            &styled,
            "A",
            20,
            &invalid_spans,
            .{
                .max_width = 100,
                .writing_mode = .vertical_lr,
                .text_orientation = .upright,
            },
        ),
    );
}
