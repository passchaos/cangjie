//! Styled vertical columns and intrinsic inline geometry.

const std = @import("std");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "styled vertical paragraph shares shaping and intrinsic y geometry" {
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

    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "AA",
        20,
        &.{
            .{
                .byte_start = 0,
                .byte_len = 1,
                .style_index = 1,
                .font_size = 20,
                .letter_spacing = 1,
            },
            .{
                .byte_start = 1,
                .byte_len = 1,
                .style_index = 2,
                .font_size = 20,
                .letter_spacing = 3,
            },
        },
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(
        support.WritingMode.vertical_rl,
        layout.writing_mode,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 44), layout.height, 0.001);
    const widths = styled.contentWidths().?;
    try std.testing.expectApproxEqAbs(@as(f32, 44), widths.min, 0.001);
    try std.testing.expectApproxEqAbs(widths.min, widths.max, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 21),
        layout.glyphs[0].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 23),
        layout.glyphs[1].y_advance,
        0.001,
    );

    const columns = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "A\nA",
        20,
        &.{
            .{
                .byte_start = 0,
                .byte_len = 2,
                .style_index = 1,
                .font_size = 20,
            },
            .{
                .byte_start = 2,
                .byte_len = 1,
                .style_index = 2,
                .font_size = 20,
            },
        },
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), columns.lines.len);
    try std.testing.expect(columns.lines[0].x < columns.lines[1].x);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        columns.glyphs[1].y_advance,
        0.001,
    );

    const wrapped = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "A A A",
        20,
        &.{.{
            .byte_start = 0,
            .byte_len = 5,
            .style_index = 1,
            .font_size = 20,
        }},
        .{
            .max_width = 20.1,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 3), wrapped.lines.len);
    const wrapped_widths = styled.contentWidths().?;
    try std.testing.expect(wrapped_widths.max > wrapped_widths.min);
}
