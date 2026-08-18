//! Caller-controlled per-line regions across direct, retained, and styled layout.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const StyledParagraphSpan = support.StyledParagraphSpan;
const TextShaper = support.TextShaper;

test "direct line regions override natural geometry and preserve alignment" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const regions = [_]paragraph.LineRegion{
        .{ .x = 10, .y = 100, .width = 40 },
        .{ .x = 80, .y = 100, .width = 30 },
        .{ .x = 10, .y = 130, .width = 50 },
    };
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        "A A A A A",
        20,
        .{
            .max_width = 200,
            .alignment = .right,
            .first_line_indent = 25,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 200,
                .height = 200,
            }},
            .line_regions = &regions,
        },
    );

    try std.testing.expect(layout.lines.len >= 3);
    for (layout.lines[0..3], regions) |line, region| {
        try std.testing.expectApproxEqAbs(region.x, line.region_x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.y, 0.001);
        try std.testing.expectApproxEqAbs(
            region.width,
            line.region_width,
            0.001,
        );
        try std.testing.expectApproxEqAbs(@as(f32, 0), line.indent, 0.001);
        try std.testing.expect(
            line.x + line.width <= region.x + region.width + 0.001,
        );
    }
}

test "line region resolver replays retained paragraph across columns" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "A A A A A A A",
        20,
        .{ .max_width = 45 },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var resolver = paragraph.LineRegionResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(.{ .max_width = 45 });

    const placements = [_]paragraph.LineRegion{
        .{ .x = 0, .y = 0, .width = 45 },
        .{ .x = 0, .y = 24, .width = 45 },
        .{ .x = 80, .y = 0, .width = 45 },
        .{ .x = 80, .y = 24, .width = 45 },
    };
    var placement_index: usize = 0;
    var final_layout: ?paragraph.Layout = null;
    while (true) {
        const pass_value = try resolver.pass();
        const layout = try shaped.layout(&reflow, pass_value.options);
        switch (try resolver.next(pass_value, layout)) {
            .complete => {
                final_layout = layout;
                break;
            },
            .place => |request| {
                try std.testing.expectEqual(
                    placement_index,
                    request.line_index,
                );
                try std.testing.expect(placement_index < placements.len);
                try resolver.submit(request, placements[placement_index]);
                placement_index += 1;
                try std.testing.expectError(
                    error.StaleLineRegionPass,
                    resolver.next(pass_value, layout),
                );
            },
        }
    }
    const layout = final_layout.?;
    try std.testing.expectEqual(layout.lines.len, resolver.items().len);
    try std.testing.expectEqual(placement_index, resolver.items().len);
    for (layout.lines, resolver.items()) |line, region| {
        try std.testing.expectApproxEqAbs(region.x, line.region_x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.y, 0.001);
        try std.testing.expectApproxEqAbs(
            region.width,
            line.region_width,
            0.001,
        );
    }
    const resolved = try resolver.resolvedOptions();
    try std.testing.expectEqual(layout.lines.len, resolved.line_regions.len);
    // The third line starts a new column and intentionally returns to page top.
    try std.testing.expect(layout.lines[2].y < layout.lines[1].y);
    const third_hit = layout.hitTest(
        layout.lines[2].x + 1,
        layout.lines[2].y + 1,
    );
    try std.testing.expect(
        third_hit.glyph_index >= layout.lines[2].glyph_start,
    );
}

test "line region resolver rejects pending stale and invalid submissions" {
    const allocator = std.testing.allocator;
    var resolver = paragraph.LineRegionResolver.init(allocator);
    defer resolver.deinit();
    try std.testing.expectError(
        error.LineRegionResolverNotActive,
        resolver.pass(),
    );
    try resolver.begin(.{ .max_width = 40 });
    const pass_value = try resolver.pass();
    const layout = paragraph.Layout{
        .glyphs = &.{},
        .runs = &.{},
        .lines = &.{.{
            .glyph_start = 0,
            .glyph_len = 0,
            .run_start = 0,
            .run_len = 0,
            .byte_start = 0,
            .byte_len = 0,
            .x = 0,
            .y = 0,
            .region_x = 0,
            .region_width = 40,
            .width = 0,
            .height = 20,
            .baseline = 16,
            .ascent = 16,
            .descent = 4,
            .leading = 0,
        }},
        .width = 0,
        .height = 20,
    };
    const request = switch (try resolver.next(pass_value, layout)) {
        .place => |value| value,
        .complete => return error.TestExpectedRegionRequest,
    };
    try std.testing.expectError(
        error.LineRegionPlacementPending,
        resolver.pass(),
    );
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        resolver.submit(request, .{ .x = 0, .y = 0, .width = 0 }),
    );
    var stale = request;
    stale.token +%= 1;
    try std.testing.expectError(
        error.StaleLineRegionRequest,
        resolver.submit(stale, .{ .x = 0, .y = 0, .width = 40 }),
    );
}

test "styled balanced layout consumes explicit line regions" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "A A A A";
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 31,
        .font_size = 20,
    }};
    const regions = [_]paragraph.LineRegion{
        .{ .x = 10, .y = 60, .width = 35 },
        .{ .x = 70, .y = 60, .width = 35 },
        .{ .x = 10, .y = 90, .width = 35 },
    };
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .line_break_strategy = .balanced,
            .line_regions = &regions,
        },
    );
    try std.testing.expect(layout.lines.len >= 3);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
    for (layout.lines[0..3], regions) |line, region| {
        try std.testing.expectApproxEqAbs(region.x, line.region_x, 0.001);
        try std.testing.expectApproxEqAbs(region.y, line.y, 0.001);
    }
    for (styled.glyphMetadata()) |item| {
        try std.testing.expectEqual(@as(u32, 31), item.style_index);
    }
}
