//! Retained and styled vertical ellipsis integration.

const std = @import("std");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "retained vertical ellipsis restores the immutable shaped suffix" {
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
        "AAAAAA",
        20,
        .{
            .max_width = 100.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const clipped = try shaped.layout(&reflow, .{
        .max_width = 100.1,
        .max_lines = 1,
        .ellipsis = true,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(u21, '.'), clipped.glyphs[4].codepoint);
    try std.testing.expectEqual(@as(usize, 6), shaped.glyphs.len);
    const widths = try shaped.contentWidths(.{
        .max_width = 100.1,
        .max_lines = 1,
        .ellipsis = true,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 120), widths.max, 0.001);

    const restored = try shaped.layout(&reflow, .{
        .max_width = 200,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 6), restored.glyphs.len);
    try std.testing.expectEqual(@as(u21, 'A'), restored.glyphs[5].codepoint);
}

test "styled vertical dots inherit the terminal pre-fit source style" {
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
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 4,
            .font_size = 20,
        },
        .{
            .byte_start = 2,
            .byte_len = 5,
            .style_index = 9,
            .font_size = 20,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "AAAAAAA",
        20,
        &spans,
        .{
            .max_width = 100.1,
            .max_lines = 1,
            .ellipsis = true,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    const metadata = styled.glyphMetadata();
    try std.testing.expectEqual(result.glyphs.len, metadata.len);
    try std.testing.expectEqual(@as(usize, 5), metadata.len);
    try std.testing.expectEqual(@as(u32, 4), metadata[0].style_index);
    try std.testing.expectEqual(@as(u32, 4), metadata[1].style_index);
    for (metadata[metadata.len - 3 ..]) |item| {
        try std.testing.expectEqual(@as(u32, 9), item.style_index);
        try std.testing.expectApproxEqAbs(
            @as(f32, 0),
            item.layout_spacing,
            0.001,
        );
    }
}

test "styled vertical ellipsis honors the terminal style-local cascade" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const primary_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{ 'A', 'B' },
    );
    defer allocator.free(primary_bytes);
    const styled_bytes = try test_font.buildVerticalFallbackTtf(
        allocator,
        &.{ '.', 'B' },
    );
    defer allocator.free(styled_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var styled_font = try Font.parse(allocator, styled_bytes);
    defer styled_font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const styled_faces = [_]*const @import("../../../../font/face/root.zig").Face{
        @import("../../../../font/face/root.zig").backend.face(&styled_font),
    };
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 2,
            .font_size = 20,
        },
        .{
            .byte_start = 1,
            .byte_len = 5,
            .style_index = 8,
            .font_size = 30,
            .faces = &styled_faces,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{ &primary, &styled_font }),
        &buffer,
        &styled,
        "ABBBBB",
        20,
        &spans,
        .{
            .max_width = 120.1,
            .max_lines = 1,
            .ellipsis = true,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    const terminal_run = result.runs[result.runs.len - 1];
    try std.testing.expectEqual(@as(usize, 1), terminal_run.font_index);
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        terminal_run.font_size,
        0.001,
    );
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(try styled_font.glyphIndex('.'), glyph.glyph_id);
        try std.testing.expectApproxEqAbs(@as(f32, 30), glyph.y_advance, 0.001);
    }
}

test "styled RL ellipsis repairs prior columns after terminal width shrinks" {
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
    const marker = @import("../../../../api/paragraph/root.zig")
        .object_replacement_utf8;
    const text = "A" ++ marker ++ "AAAA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 3,
        .font_size = 20,
    }};

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 40.1,
            .max_lines = 2,
            .ellipsis = true,
            .inline_objects = &.{.{
                .id = 22,
                .byte_index = 1,
                .width = 80,
                .height = 20,
            }},
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), result.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), result.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(
        result.lines[1].width,
        result.lines[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.lines[0].x + result.lines[0].width,
        result.width,
        0.001,
    );
}

test "styled vertical ellipsis detects an omitted trailing empty column" {
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
    const text = "A\n";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 7,
        .font_size = 20,
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
            .max_lines = 1,
            .ellipsis = true,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 4), result.glyphs.len);
    for (result.glyphs[result.glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
}
