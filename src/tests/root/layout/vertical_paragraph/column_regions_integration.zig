//! Retained resolver, styled metadata, geometry, and draw integration for vertical regions.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "line region resolver replays retained vertical columns" {
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
        "AAAAA",
        20,
        .{
            .max_width = 40,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var resolver = paragraph.LineRegionResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(.{
        .max_width = 40,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    const placements = [_]paragraph.LineRegion{
        .{ .x = 100, .y = 10, .width = 40 },
        .{ .x = 60, .y = 20, .width = 40 },
        .{ .x = 20, .y = 30, .width = 40 },
    };
    var placement_index: usize = 0;
    var final_layout: ?paragraph.Layout = null;
    while (true) {
        const pass_value = try resolver.pass();
        const result = try shaped.layout(&reflow, pass_value.options);
        switch (try resolver.next(pass_value, result)) {
            .complete => {
                final_layout = result;
                break;
            },
            .place => |request| {
                try std.testing.expectEqual(placement_index, request.line_index);
                try std.testing.expect(placement_index < placements.len);
                try resolver.submit(request, placements[placement_index]);
                placement_index += 1;
            },
        }
    }
    const result = final_layout.?;
    try std.testing.expectEqual(placements.len, result.lines.len);
    for (result.lines, placements) |line, region| {
        try std.testing.expectApproxEqAbs(region.x, line.x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.region_inline_start, 0.001);
        try std.testing.expectApproxEqAbs(region.width, line.region_inline_size, 0.001);
    }
}

test "styled vertical regions drive geometry and renderer origins" {
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
    const text = "AAAAA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 31,
        .font_size = 20,
    }};
    const regions = [_]paragraph.LineRegion{
        .{ .x = 100, .y = 10, .width = 30 },
        .{ .x = 60, .y = 20, .width = 50 },
        .{ .x = 20, .y = 30, .width = 40 },
    };
    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 200,
            .line_regions = &regions,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    for (styled.glyphMetadata()) |item| {
        try std.testing.expectEqual(@as(u32, 31), item.style_index);
    }
    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectApproxEqAbs(regions[0].x, geometry.lines[0].bounds.x, 0.001);
    try std.testing.expectApproxEqAbs(regions[0].y, geometry.lines[0].bounds.y, 0.001);

    var draw_list = try support.buildGlyphDrawList(allocator, result, .{});
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        regions[0].x + result.lines[0].baseline,
        draw_list.glyphs[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(regions[0].y, draw_list.glyphs[0].baseline_y, 0.001);
}
