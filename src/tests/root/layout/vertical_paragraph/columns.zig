//! Hard-break column placement, block progression, and empty columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "hard breaks place vertical columns in writing-mode block order" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "A\nAA";

    const rl = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 10,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try expectVerticalHardBreakColumns(rl, .vertical_rl);
    try std.testing.expect(rl.lines[0].x > rl.lines[1].x);
    try std.testing.expectApproxEqAbs(@as(f32, 20), rl.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rl.lines[1].x, 0.001);
    try std.testing.expectEqual(@as(usize, 0), rl.hitTest(30, 10).glyph_index);
    try std.testing.expectEqual(@as(usize, 2), rl.hitTest(10, 10).glyph_index);

    var geometry = try paragraph.buildGeometry(allocator, text, rl, .{});
    defer geometry.deinit();
    try std.testing.expectEqual(@as(usize, 2), geometry.lines.len);
    try std.testing.expectEqual(@as(usize, 0), geometry.lines[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), geometry.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 2), geometry.lines[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), geometry.lines[1].byte_len);
    const newline = geometry.caret(.{
        .byte_offset = 2,
        .affinity = .upstream,
    }).?;
    const next_column = geometry.caret(.{
        .byte_offset = 2,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 0), newline.line_index);
    try std.testing.expectEqual(@as(usize, 1), next_column.line_index);
    try std.testing.expect(newline.rect.x > next_column.rect.x);
    const moved = geometry.nextLineCaret(
        .{ .byte_offset = 0, .affinity = .downstream },
        10,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), moved.line_index);

    var draw_list = try support.buildGlyphDrawList(allocator, rl, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 3), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        draw_list.glyphs[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        draw_list.glyphs[1].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        draw_list.glyphs[2].baseline_y,
        0.001,
    );

    const lr = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 10,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectVerticalHardBreakColumns(lr, .vertical_lr);
    try std.testing.expect(lr.lines[0].x < lr.lines[1].x);
    try std.testing.expectApproxEqAbs(@as(f32, 0), lr.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), lr.lines[1].x, 0.001);
}

test "vertical block progression handles unequal fallback column widths" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const narrow_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'A',
        800,
        -200,
        0,
    );
    defer allocator.free(narrow_bytes);
    const wide_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'B',
        1200,
        -300,
        0,
    );
    defer allocator.free(wide_bytes);
    var narrow = try Font.parse(allocator, narrow_bytes);
    defer narrow.deinit();
    var wide = try Font.parse(allocator, wide_bytes);
    defer wide.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const cascade = FontCascade.init(&.{ &narrow, &wide });

    const rl = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "A\nB",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), rl.lines.len);
    try std.testing.expect(rl.lines[1].width > rl.lines[0].width);
    try std.testing.expectApproxEqAbs(
        rl.lines[1].width,
        rl.lines[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), rl.lines[1].x, 0.001);
    try std.testing.expectApproxEqAbs(
        rl.lines[0].width + rl.lines[1].width,
        rl.width,
        0.001,
    );

    const lr = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "A\nB",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), lr.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(
        lr.lines[0].width,
        lr.lines[1].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        lr.lines[0].width + lr.lines[1].width,
        lr.width,
        0.001,
    );
}

test "vertical CRLF and trailing hard breaks preserve empty columns" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "A\r\n",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqual(@as(usize, 1), layout.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), layout.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), layout.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, 3), layout.lines[1].byte_start);
    try std.testing.expectApproxEqAbs(@as(f32, 0), layout.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), layout.glyphs[2].y_advance, 0.001);
    try std.testing.expect(layout.lines[0].x < layout.lines[1].x);

    var geometry = try paragraph.buildGeometry(
        allocator,
        "A\r\n",
        layout,
        .{},
    );
    defer geometry.deinit();
    const visible_hit = geometry.hitTest(
        layout.lines[0].x + layout.lines[0].width / 2,
        0,
    ).?;
    try std.testing.expectEqual(@as(usize, 0), visible_hit.line_index);
    const empty_hit = geometry.hitTest(
        layout.lines[1].x + layout.lines[1].width / 2,
        0,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), empty_hit.line_index);
    try std.testing.expectEqual(@as(usize, 3), empty_hit.position.byte_offset);
}

fn expectVerticalHardBreakColumns(
    layout: support.ParagraphLayout,
    writing_mode: support.WritingMode,
) !void {
    try std.testing.expectEqual(writing_mode, layout.writing_mode);
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqual(@as(usize, 1), layout.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), layout.lines[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), layout.lines[0].glyph_start);
    try std.testing.expectEqual(@as(usize, 2), layout.lines[1].glyph_start);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), layout.glyphs[1].y_advance, 0.001);
}
