//! Single-column vertical layout and explicit rejection boundaries.

const std = @import("std");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "vertical no-wrap paragraph exposes physical column geometry" {
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

    try std.testing.expectError(
        error.UnsupportedVerticalParagraphOptions,
        TextShaper.layoutParagraphUtf8(
            FontCascade.init(&.{&font}),
            &buffer,
            "AA",
            20,
            .{
                .max_width = 100,
                .wrap_mode = .no_wrap,
                .writing_mode = .vertical_rl,
                .direction = .rtl,
            },
        ),
    );
}
