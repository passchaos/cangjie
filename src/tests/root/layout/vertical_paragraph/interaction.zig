//! Vertical TextGeometry, bridge, and debug output.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "vertical paragraph text geometry and bridge retain the y pen" {
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
