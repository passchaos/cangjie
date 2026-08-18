//! End-to-end coverage for the deliberately bounded first vertical paragraph.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "vertical no-wrap paragraph exposes physical column geometry" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "AA",
        20,
        .{
            // The measure is an inline-size (column-height) request. No-wrap
            // intentionally permits the 40-unit column to overflow it.
            .max_width = 10,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );

    try std.testing.expectEqual(
        support.WritingMode.vertical_rl,
        layout.writing_mode,
    );
    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.height, 0.001);
    try std.testing.expectApproxEqAbs(
        layout.width / 2,
        layout.lines[0].baseline,
        0.001,
    );
    for (layout.glyphs) |glyph| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
        try std.testing.expectEqual(
            support.GlyphOrientation.upright,
            glyph.orientation,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        layout.runs[0].glyphRun(.{
            .glyphs = layout.glyphs,
            .runs = layout.runs,
            .normalized_variation_coords = layout.normalized_variation_coords,
        }).height(),
        0.001,
    );

    const before = layout.hitTest(10, 4);
    try std.testing.expectEqual(@as(usize, 0), before.glyph_index);
    try std.testing.expect(!before.trailing);
    const first_end = layout.hitTest(10, 16);
    try std.testing.expectEqual(@as(usize, 0), first_end.glyph_index);
    try std.testing.expect(first_end.trailing);
    const second = layout.hitTest(10, 24);
    try std.testing.expectEqual(@as(usize, 1), second.glyph_index);
    try std.testing.expect(!second.trailing);

    const caret = layout.caretRect(.{
        .glyph_index = 1,
        .cluster = 1,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), caret.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), caret.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), caret.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), caret.height, 0.001);

    const selection = layout.selectionRect(0, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), selection.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), selection.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), selection.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), selection.height, 0.001);

    const measured = try TextShaper.measureParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "AA",
        20,
        .{
            .max_width = 10,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(
        layout.width / 2,
        measured.baseline,
        0.001,
    );

    for ([_]support.ParagraphOptions{
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
        },
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .direction = .rtl,
        },
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .max_lines = 1,
        },
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .letter_spacing = -1,
        },
    }) |unsupported| {
        try std.testing.expectError(
            error.UnsupportedVerticalParagraphOptions,
            TextShaper.layoutParagraphUtf8(
                FontCascade.init(&.{&font}),
                &buffer,
                "AA",
                20,
                unsupported,
            ),
        );
    }
}

test "retained vertical paragraph reflows without mutating its snapshot" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();

    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "AA",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const first = try shaped.layout(&reflow, .{
        .max_width = 10,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .letter_spacing = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 44), first.height, 0.001);
    const second = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), second.height, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        shaped.glyphs[0].y_advance,
        0.001,
    );
    const widths = try shaped.contentWidths(.{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), widths.min, 0.001);
    try std.testing.expectApproxEqAbs(widths.min, widths.max, 0.001);
    try std.testing.expectError(
        error.UnsupportedVerticalParagraphBreaker,
        shaped.breakLines(&reflow, .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );
}

test "vertical paragraph text geometry and bridge retain the y pen" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "AA",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        "AA",
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(
        support.WritingMode.vertical_rl,
        geometry.writing_mode,
    );
    try std.testing.expectEqual(@as(usize, 2), geometry.graphemes.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        geometry.graphemes[0].inline_size,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        geometry.spans[0].bounds.width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        geometry.spans[0].bounds.height,
        0.001,
    );

    const middle = geometry.caret(.{
        .byte_offset = 1,
        .affinity = .downstream,
    }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0), middle.rect.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), middle.rect.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), middle.rect.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), middle.rect.height, 0.001);
    const hit = geometry.hitTest(10, 31).?;
    try std.testing.expectEqual(@as(usize, 2), hit.position.byte_offset);
    const fragments = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 1, .byte_end = 2 },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 1), fragments.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        fragments[0].rect.y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        fragments[0].rect.height,
        0.001,
    );
    const stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 3), stops.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), stops[0].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), stops[1].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), stops[2].inline_position, 0.001);

    var draw_list = try support.buildGlyphDrawList(
        allocator,
        layout,
        .{},
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        draw_list.glyphs[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        draw_list.glyphs[0].baseline_y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        draw_list.glyphs[1].baseline_y,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        draw_list.glyphs[0].y_advance,
        0.001,
    );
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        draw_list.glyphs[0].orientation,
    );

    var overlays = try support.buildDebugOverlays(
        allocator,
        layout,
        .{},
    );
    defer overlays.deinit();
    const baseline = for (overlays.items) |item| {
        if (item.kind == .baseline) break item.rect;
    } else return error.MissingVerticalBaselineOverlay;
    try std.testing.expectApproxEqAbs(
        layout.lines[0].baseline,
        baseline.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), baseline.width, 0.001);
    try std.testing.expectApproxEqAbs(layout.height, baseline.height, 0.001);
}

test "styled vertical paragraph shares shaping and intrinsic y geometry" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig")
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
}
