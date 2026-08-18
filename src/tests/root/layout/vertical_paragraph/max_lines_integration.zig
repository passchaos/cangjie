//! Object, retained, styled, and ellipsis-boundary integration for vertical max-lines.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "vertical max-lines omits suffix objects and geometry" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const marker = paragraph.object_replacement_utf8;
    const text = marker ++ marker;

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 20.1,
            .max_lines = 1,
            .inline_objects = &.{
                .{ .id = 1, .byte_index = 0, .width = 20, .height = 20 },
                .{ .id = 2, .byte_index = 3, .width = 20, .height = 20 },
            },
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(@as(usize, 1), result.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectEqual(@as(u64, 1), result.inline_objects[0].id);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        result,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectEqual(@as(usize, 1), geometry.lines.len);
    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = marker.len, .byte_end = text.len },
        ),
    );
}

test "retained vertical max-lines restores the full paragraph" {
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
            .max_width = 20.1,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine_len = shaped.glyphs.len;
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const limited = try shaped.layout(&reflow, .{
        .max_width = 20.1,
        .max_lines = 1,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), limited.lines.len);
    try std.testing.expectEqual(@as(usize, 1), limited.glyphs.len);

    const restored = try shaped.layout(&reflow, .{
        .max_width = 20.1,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 4), restored.lines.len);
    try std.testing.expectEqual(pristine_len, restored.glyphs.len);
    try std.testing.expectEqual(pristine_len, shaped.glyphs.len);

    const limited_widths = try shaped.contentWidths(.{
        .max_width = 20.1,
        .max_lines = 1,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const full_widths = try shaped.contentWidths(.{
        .max_width = 20.1,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(full_widths, limited_widths);
}

test "styled vertical max-lines synchronizes glyph metadata" {
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
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = 4,
        .style_index = 9,
        .font_size = 20,
    }};

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        "AAAA",
        20,
        &spans,
        .{
            .max_width = 20.1,
            .max_lines = 2,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expectEqual(@as(usize, 2), result.glyphs.len);
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
}
