//! Bottom-to-top vertical inline progression across layout consumers.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;
const layout = policy_support.layout;

test "bottom-to-top alignment mirrors start end and first indent" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    for ([_]struct { alignment: paragraph.Align, expected_y: f32 }{
        .{ .alignment = .start, .expected_y = 80 },
        .{ .alignment = .center, .expected_y = 40 },
        .{ .alignment = .end, .expected_y = 0 },
    }) |case| {
        const result = try layout(&font, &buffer, "A", .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .alignment = case.alignment,
            .direction = .rtl,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        });
        try std.testing.expectApproxEqAbs(case.expected_y, result.lines[0].y, 0.001);
    }

    const indented = try layout(&font, &buffer, "A", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .first_line_indent = 10,
        .direction = .rtl,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // Logical start is at y=100; a ten-unit indent moves the 20-unit glyph
    // box upward to [70, 90].
    try std.testing.expectApproxEqAbs(@as(f32, 70), indented.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), indented.lines[0].indent, 0.001);
}

test "bottom-to-top bidi geometry and renderer share physical order" {
    const allocator = std.testing.allocator;
    const text = "אב";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .direction = .rtl,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 60), result.lines[0].y, 0.001);
    try std.testing.expectEqual(@as(usize, 2), result.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), result.glyphs[1].cluster);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        result,
        .{ .direction = .rtl },
    );
    defer geometry.deinit();
    const logical_start = geometry.caret(.{
        .byte_offset = 0,
        .affinity = .downstream,
    }).?;
    const logical_end = geometry.caret(.{
        .byte_offset = text.len,
        .affinity = .upstream,
    }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 100), logical_start.rect.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), logical_end.rect.y, 0.001);
    try std.testing.expectEqual(@as(usize, 2), result.hitTest(10, 64).cluster);
    try std.testing.expectEqual(@as(usize, 0), result.hitTest(10, 84).cluster);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), draw_list.glyphs[1].cluster);
    try std.testing.expectApproxEqAbs(@as(f32, 60), draw_list.glyphs[0].baseline_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80), draw_list.glyphs[1].baseline_y, 0.001);
}

test "bottom-to-top explicit regions and exclusions keep top-origin geometry" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const explicit = try layout(&font, &buffer, "A", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .alignment = .start,
        .direction = .rtl,
        .line_regions = &.{.{ .x = 7, .y = 10, .width = 50 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), explicit.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), explicit.lines[0].region_inline_start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), explicit.lines[0].region_inline_size, 0.001);

    const excluded = try layout(&font, &buffer, "AA", .{
        .max_width = 60,
        .first_line_indent = 10,
        .direction = .rtl,
        .exclusions = &.{.{ .x = 0, .y = 30, .width = 20, .height = 20 }},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // The indent excludes [50, 60] at logical start. The physical obstacle
    // removes [30, 50], leaving [0, 30]. Logical start aligns the 20-unit
    // glyph to the bottom of that fragment, so its physical origin is y=10.
    try std.testing.expectApproxEqAbs(@as(f32, 10), excluded.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), excluded.lines[0].region_inline_size, 0.001);
}

test "retained and styled bottom-to-top layout preserve direction policy" {
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
        "A",
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const at_start = try shaped.layout(&reflow, .{
        .max_width = 100,
        .alignment = .start,
        .direction = .rtl,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 80), at_start.lines[0].y, 0.001);
    const at_end = try shaped.layout(&reflow, .{
        .max_width = 100,
        .alignment = .end,
        .direction = .rtl,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0), at_end.lines[0].y, 0.001);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const styled_result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &layout_buffer,
        &styled,
        "A",
        20,
        &.{.{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 3,
            .font_size = 20,
        }},
        .{
            .max_width = 100,
            .direction = .rtl,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 80), styled_result.lines[0].y, 0.001);
    try std.testing.expectEqual(styled_result.glyphs.len, styled.glyphMetadata().len);
}
