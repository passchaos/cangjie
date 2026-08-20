//! Source-preserving whitespace policy in vertical paragraph flow.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "vertical collapse keeps source atoms with one interior blank" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "  A   A  ";

    const preserved = try layout(&font, &buffer, text, .{
        .max_width = 400,
        .white_space_collapse = .preserve,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const preserved_height = preserved.height;
    const collapsed = try layout(&font, &buffer, text, .{
        .max_width = 400,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, text.len), collapsed.glyphs.len);
    try std.testing.expect(collapsed.height < preserved_height);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[0].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[1].y_advance);
    try std.testing.expect(collapsed.glyphs[3].y_advance > 0);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[4].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[5].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[7].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[8].y_advance);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        collapsed.selectionRectForBytes(0, 2).height,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        collapsed.selectionRectForBytes(7, text.len).height,
        0.001,
    );
}

test "vertical collapse trims soft column edges while break-spaces owns blanks" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A   A";

    const natural = try layout(&font, &buffer, text, .{
        .max_width = 400,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const one = natural.glyphs[0].y_advance;
    const collapsed = try layout(&font, &buffer, text, .{
        .max_width = one + 0.1,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), collapsed.lines.len);
    try std.testing.expectApproxEqAbs(
        one,
        collapsed.lines[0].height,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 4), collapsed.lines[0].byte_len);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[1].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[2].y_advance);
    try std.testing.expectEqual(@as(f32, 0), collapsed.glyphs[3].y_advance);

    const break_spaces = try layout(&font, &buffer, text, .{
        .max_width = one + 0.1,
        .white_space_collapse = .break_spaces,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(break_spaces.lines.len > collapsed.lines.len);
    var saw_space_ended_column = false;
    for (break_spaces.lines) |line| {
        if (line.glyph_len == 0) continue;
        const last =
            break_spaces.glyphs[line.glyph_start + line.glyph_len - 1];
        if (last.codepoint == ' ' and last.y_advance > 0) {
            saw_space_ended_column = true;
        }
    }
    try std.testing.expect(saw_space_ended_column);

    const pure_spaces = try layout(&font, &buffer, "   ", .{
        .max_width = one + 0.1,
        .white_space_collapse = .break_spaces,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 3), pure_spaces.lines.len);
    for (pure_spaces.lines) |line| {
        try std.testing.expectEqual(@as(usize, 1), line.glyph_len);
        try std.testing.expectEqual(@as(usize, 1), line.byte_len);
        try std.testing.expect(line.height > 0);
    }
}

test "retained vertical reflow and intrinsic widths switch whitespace policy" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const text = "  A   A  ";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 400,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine = try allocator.dupe(
        @TypeOf(shaped.glyphs[0]),
        shaped.glyphs,
    );
    defer allocator.free(pristine);
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const collapsed = try shaped.layout(&reflow, .{
        .max_width = 400,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const collapsed_height = collapsed.height;
    const collapsed_widths = try shaped.contentWidths(.{
        .max_width = 400,
        .white_space_collapse = .collapse,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const preserved_widths = try shaped.contentWidths(.{
        .max_width = 400,
        .white_space_collapse = .preserve,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(collapsed_widths.max < preserved_widths.max);

    var spaces = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "   ",
        20,
        .{
            .max_width = 400,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    defer spaces.deinit();
    const break_space_widths = try spaces.contentWidths(.{
        .max_width = 400,
        .white_space_collapse = .break_spaces,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    const preserved_space_widths = try spaces.contentWidths(.{
        .max_width = 400,
        .white_space_collapse = .preserve,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(
        break_space_widths.min < preserved_space_widths.min,
    );

    const preserved = try shaped.layout(&reflow, .{
        .max_width = 400,
        .white_space_collapse = .preserve,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(preserved.height > collapsed_height);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );
}

test "styled vertical collapse preserves metadata and owned geometry" {
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
    const text = " A  A ";
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 3,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 3,
            .byte_len = text.len - 3,
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
            .max_width = 400,
            .white_space_collapse = .collapse,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(
        result.glyphs.len,
        styled.glyphMetadata().len,
    );
    try std.testing.expectEqual(@as(f32, 0), result.glyphs[0].y_advance);
    const collapsed_widths = styled.contentWidths().?;
    const collapsed_height = result.height;
    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();

    const preserved = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 400,
            .white_space_collapse = .preserve,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(
        collapsed_widths.max < styled.contentWidths().?.max,
    );
    try std.testing.expect(preserved.height > collapsed_height);
    try std.testing.expectEqual(text.len, geometry.graphemes.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        geometry.graphemes[0].inline_size,
        0.001,
    );
}
