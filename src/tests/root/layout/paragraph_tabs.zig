//! Explicit tab-ruler integration across reflow and final geometry.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const render_bridge = @import("../../../render/bridge/root.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const StyledParagraphSpan = support.StyledParagraphSpan;
const TextShaper = support.TextShaper;

test "explicit tab ruler precedes its repeating fallback grid" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\tA\tA\tA";
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 200,
            .tab_width = 2,
            .word_spacing = 9,
            .tab_stops = &.{
                .{ .position = 40 },
                .{ .position = 90 },
            },
        },
    );

    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 24), layout.glyphs[1].x_advance, 0.001);
    try std.testing.expectEqual(
        @as(?paragraph.Align, .left),
        layout.lines[0].resolved_alignment,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 34), layout.glyphs[3].x_advance, 0.001);
    // The 32-unit fallback interval repeats from the final explicit stop.
    try std.testing.expectApproxEqAbs(@as(f32, 16), layout.glyphs[5].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 138), layout.lines[0].width, 0.001);
    try std.testing.expectEqual(@as(usize, 4), layout.runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), layout.runs[0].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.runs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 90), layout.runs[2].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 122), layout.runs[3].x_offset, 0.001);

    const before_last_field = layout.caretRect(.{
        .glyph_index = 6,
        .cluster = 6,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 122), before_last_field.x, 0.001);
    const selected_prefix = layout.selectionRectForBytes(0, 6);
    try std.testing.expectApproxEqAbs(@as(f32, 122), selected_prefix.width, 0.001);

    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        layout,
        .{},
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 4), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 4), draw_list.runs.len);
    for (draw_list.glyphs, draw_list.runs) |glyph, run| {
        try std.testing.expectApproxEqAbs(glyph.x, run.x, 0.001);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 40), draw_list.glyphs[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 90), draw_list.glyphs[2].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 122), draw_list.glyphs[3].x, 0.001);
}

test "tab ruler pins aligned LTR lines to logical start" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    for ([_]paragraph.Align{ .center, .right, .justify }) |alignment| {
        const layout = try TextShaper.layoutParagraphUtf8(
            FontCascade.init(&fonts),
            &buffer,
            "A\tA",
            20,
            .{
                .max_width = 100,
                .alignment = alignment,
                .tab_stops = &.{.{ .position = 40 }},
            },
        );
        try std.testing.expectApproxEqAbs(@as(f32, 0), layout.lines[0].x, 0.001);
        try std.testing.expectEqual(
            @as(?paragraph.Align, .left),
            layout.lines[0].resolved_alignment,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, 24),
            layout.glyphs[1].x_advance,
            0.001,
        );
        try std.testing.expect(layout.glyphs[1].isTab());
        try std.testing.expectEqual(@as(u16, 0), layout.glyphs[1].glyph_id);
        var font_owned_glyphs: usize = 0;
        for (layout.runs) |run| font_owned_glyphs += run.glyph_len;
        try std.testing.expectEqual(@as(usize, 2), font_owned_glyphs);
    }
}

test "render run starts at the first visible glyph after a leading tab" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "\tA",
        20,
        .{
            .max_width = 100,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        layout,
        .{},
    );
    defer draw_list.deinit();

    try std.testing.expectEqual(@as(usize, 1), draw_list.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), draw_list.runs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), draw_list.glyphs[0].x, 0.001);
    try std.testing.expectApproxEqAbs(
        draw_list.glyphs[0].x,
        draw_list.runs[0].x,
        0.001,
    );
}

test "tab ellipsis and hanging preserve logical-start alignment" {
    const allocator = std.testing.allocator;
    const latin_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(latin_bytes);
    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const ellipsized = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&latin}),
        &buffer,
        "A\tA A A",
        20,
        .{
            .max_width = 80,
            .alignment = .right,
            .max_lines = 1,
            .ellipsis = true,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), ellipsized.lines[0].x, 0.001);
    try std.testing.expectEqual(
        @as(?paragraph.Align, .left),
        ellipsized.lines[0].resolved_alignment,
    );

    const tab_removed = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&latin}),
        &buffer,
        "A\tA A",
        20,
        .{
            .max_width = 60,
            .alignment = .right,
            .max_lines = 1,
            .ellipsis = true,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    try std.testing.expectEqual(@as(usize, 1), tab_removed.lines.len);
    try std.testing.expectEqual(
        @as(?paragraph.Align, .right),
        tab_removed.lines[0].resolved_alignment,
    );
    try std.testing.expect(tab_removed.lines[0].x > 0);
    for (tab_removed.glyphs) |glyph| {
        try std.testing.expect(glyph.codepoint != '\t');
    }

    const cjk_bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01 },
    );
    defer allocator.free(cjk_bytes);
    var cjk = try Font.parse(allocator, cjk_bytes);
    defer cjk.deinit();
    const hanging = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&cjk}),
        &buffer,
        "一\t丁。",
        20,
        .{
            .max_width = 80,
            .alignment = .center,
            .tab_stops = &.{.{ .position = 40 }},
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        hanging.lines[0].x,
        0.001,
    );
    try std.testing.expect(hanging.lines[0].hang_end > 0);
}

test "tab stops are local to indented and excluded line fragments" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tA",
        20,
        .{
            .max_width = 100,
            .first_line_indent = 10,
            .tab_stops = &.{.{ .position = 40 }},
            .exclusions = &.{.{
                .x = 10,
                .y = 0,
                .width = 20,
                .height = 20,
            }},
        },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 30), layout.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 70), layout.lines[0].region_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), layout.lines[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24), layout.glyphs[1].x_advance, 0.001);
    const second_glyph = layout.caretRect(.{
        .glyph_index = 2,
        .cluster = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 70), second_glyph.x, 0.001);
}

test "explicit tabs reset after hard and soft line breaks" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const hard = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tA\nAA\tA",
        20,
        .{
            .max_width = 200,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    try std.testing.expectEqual(@as(usize, 2), hard.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 24), hard.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        hard.glyphs[4].x_advance +
            hard.glyphs[5].x_advance +
            hard.glyphs[6].x_advance,
        0.001,
    );

    const soft = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A A\tA",
        20,
        .{
            .max_width = 60,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    try std.testing.expectEqual(@as(usize, 2), soft.lines.len);
    for (soft.lines) |line| {
        try std.testing.expect(line.width <= line.region_width + 0.001);
    }
    // UAX #14 discards the tab at the selected boundary just like an ordinary
    // break space. Its source bytes stay on the preceding logical line while
    // neither visual line includes the marker glyph.
    try std.testing.expectEqual(@as(usize, 3), soft.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), soft.lines[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 4), soft.lines[0].byte_len);
}

test "retained reflow changes tab rulers without reshaping" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tA";
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&fonts),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    defer shaped.deinit();
    const pristine_tab_advance = shaped.glyphs[1].x_advance;
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const first = try shaped.layout(&reflow, .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 40 }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 24), first.glyphs[1].x_advance, 0.001);
    const second = try shaped.layout(&reflow, .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 70 }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 54), second.glyphs[1].x_advance, 0.001);
    const repeated = try shaped.layout(&reflow, .{
        .max_width = 200,
        .tab_stops = &.{.{ .position = 40 }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 24), repeated.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(
        pristine_tab_advance,
        shaped.glyphs[1].x_advance,
        0.001,
    );
}

test "styled tab rulers ignore word spacing and preserve metadata" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tA";
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 51,
        .font_size = 20,
        .word_spacing = 9,
    }};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 200,
            .word_spacing = 11,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 24), layout.glyphs[1].x_advance, 0.001);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
    for (styled.glyphMetadata()) |metadata| {
        try std.testing.expectEqual(@as(u32, 51), metadata.style_index);
    }
}

test "RTL tab positions are measured from logical inline start" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "א\tב";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );

    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    const line = layout.lines[0];
    try std.testing.expectApproxEqAbs(@as(f32, 56), line.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 44), line.x, 0.001);
    try std.testing.expectEqual(
        @as(?paragraph.Align, .right),
        line.resolved_alignment,
    );
    // The field after the logical tab is the physical-left glyph. Its right
    // edge is exactly 40 units inward from the region's physical-right edge.
    try std.testing.expectEqual(@as(u21, 'ב'), layout.glyphs[0].codepoint);
    const field_right = line.x + layout.glyphs[0].x_advance;
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        line.region_x + line.region_width - field_right,
        0.001,
    );
}

test "owned text geometry exposes the same tab partition" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tA";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .tab_stops = &.{.{ .position = 40 }},
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.graphemes.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        geometry.graphemes[1].inline_size,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        geometry.graphemes[2].inline_position,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expect(geometry.spans[1].font_run == null);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        geometry.spans[2].bounds.x,
        0.001,
    );
    const selection = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = 2 },
    );
    defer allocator.free(selection);
    try std.testing.expectEqual(@as(usize, 1), selection.len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), selection[0].rect.width, 0.001);
}
