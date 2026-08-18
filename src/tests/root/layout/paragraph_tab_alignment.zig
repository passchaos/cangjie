//! Center, end, and decimal tab-field alignment integration.

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

test "center end and decimal tabs align complete fields" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const center = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tAA",
        20,
        .{
            .max_width = 120,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .center,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 29),
        center.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 45),
        center.caretRect(.{ .glyph_index = 2, .cluster = 2 }).x,
        0.001,
    );
    const center_field_start =
        center.caretRect(.{ .glyph_index = 2, .cluster = 2 }).x;
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        center_field_start +
            (center.glyphs[2].x_advance + center.glyphs[3].x_advance) / 2,
        0.001,
    );

    const end = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tAA",
        20,
        .{
            .max_width = 120,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .end,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        end.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        end.lines[0].width,
        0.001,
    );

    const decimal = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tAA.A",
        20,
        .{
            .max_width = 140,
            .tab_stops = &.{.{
                .position = 70,
                .alignment = .decimal,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        decimal.glyphs[1].x_advance,
        0.001,
    );
    // The decimal marker begins exactly at the ruler. The synthetic test font
    // maps it to notdef, but source identity and the 16-unit advance remain.
    try std.testing.expectApproxEqAbs(
        @as(f32, 70),
        decimal.caretRect(.{ .glyph_index = 4, .cluster = 4 }).x,
        0.001,
    );
}

test "decimal tabs support custom separators and missing fallback" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const custom = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tA,A",
        20,
        .{
            .max_width = 120,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .decimal,
                .decimal_point = ',',
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 28),
        custom.glyphs[1].x_advance,
        0.001,
    );

    const missing = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A\tAA",
        20,
        .{
            .max_width = 120,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .decimal,
                .decimal_point = ',',
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        missing.glyphs[1].x_advance,
        0.001,
    );
}

test "multiple aligned stops consume fields independently" {
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
        "A\tAA\tA",
        20,
        .{
            .max_width = 140,
            .tab_stops = &.{
                .{ .position = 60, .alignment = .center },
                .{ .position = 110, .alignment = .end },
            },
        },
    );

    try std.testing.expectApproxEqAbs(
        @as(f32, 29),
        layout.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 19),
        layout.glyphs[4].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 110),
        layout.lines[0].width,
        0.001,
    );
}

test "aligned field clamps instead of overlapping preceding content" {
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
        "AA\tAAAA",
        20,
        .{
            .max_width = 140,
            .tab_stops = &.{.{
                .position = 40,
                .alignment = .end,
            }},
        },
    );

    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        layout.glyphs[2].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        layout.caretRect(.{ .glyph_index = 3, .cluster = 3 }).x,
        0.001,
    );
}

test "aligned tab recomputes after a soft wrap truncates its field" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A\tAA AA";
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 65,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .end,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqual(@as(usize, 4), layout.lines[0].glyph_len);
    // The prospective field was "AA AA" (74 units), but the accepted line is
    // only "AA ". Re-resolution moves that shorter visible field to the stop.
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        layout.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 60),
        layout.lines[0].width,
        0.001,
    );
}

test "aligned tab recomputes when ellipsis truncates its field" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tAA AA AA";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .max_lines = 1,
            .ellipsis = true,
            .tab_stops = &.{.{
                .position = 90,
                .alignment = .end,
            }},
        },
    );
    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expect(layout.lines[0].width <= 100.001);
    try std.testing.expect(layout.glyphs[1].isTab());

    const visible_field_width = blk: {
        var width: f32 = 0;
        for (layout.glyphs[2..]) |glyph| width += glyph.x_advance;
        break :blk width;
    };
    const field_start = layout.glyphs[0].x_advance +
        layout.glyphs[1].x_advance;
    try std.testing.expectApproxEqAbs(
        @as(f32, 90),
        field_start + visible_field_width,
        0.001,
    );
}

test "styled ellipsis participates in aligned tab field width" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tAA AA AA";
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 63,
        .font_size = 20,
    }};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled_buffer = StyledParagraphBuffer.init(allocator);
    defer styled_buffer.deinit();
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled_buffer,
        text,
        20,
        &spans,
        .{
            .max_width = 100,
            .max_lines = 1,
            .ellipsis = true,
            .tab_stops = &.{.{
                .position = 90,
                .alignment = .end,
            }},
        },
    );

    try std.testing.expect(layout.glyphs[1].isTab());
    try std.testing.expectEqual(
        layout.glyphs.len,
        styled_buffer.glyphMetadata().len,
    );
    var visible_field_width: f32 = 0;
    for (layout.glyphs[2..]) |glyph| visible_field_width += glyph.x_advance;
    try std.testing.expectApproxEqAbs(
        @as(f32, 90),
        layout.glyphs[0].x_advance +
            layout.glyphs[1].x_advance +
            visible_field_width,
        0.001,
    );
}

test "ellipsis rebuilds a valid terminal run across a fontless tab gap" {
    const allocator = std.testing.allocator;
    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(
        allocator,
        'B',
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fonts = [_]*const Font{ &primary, &fallback };
    const text = "A\tBBBB BBBB";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .max_lines = 1,
            .ellipsis = true,
            .tab_stops = &.{.{
                .position = 90,
                .alignment = .end,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expect(layout.glyphs[1].isTab());
    const last = layout.glyphs.len - 1;
    for (layout.runs) |run| {
        try std.testing.expect(run.glyph_start <= layout.glyphs.len);
        try std.testing.expect(
            run.glyph_len <= layout.glyphs.len - run.glyph_start,
        );
    }
    const terminal_run = for (layout.runs, 0..) |run, run_index| {
        if (last >= run.glyph_start and
            last < run.glyph_start + run.glyph_len)
        {
            break run_index;
        }
    } else return error.TestExpectedTerminalRun;
    try std.testing.expect(
        layout.runs[terminal_run].glyph_start +
            layout.runs[terminal_run].glyph_len ==
            layout.glyphs.len,
    );
}

test "aligned tabs support retained and styled reflow" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tAA";
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&fonts),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 120 },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const end = try shaped.layout(&reflow, .{
        .max_width = 120,
        .tab_stops = &.{.{
            .position = 60,
            .alignment = .end,
        }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 14), end.glyphs[1].x_advance, 0.001);
    const center = try shaped.layout(&reflow, .{
        .max_width = 120,
        .tab_stops = &.{.{
            .position = 60,
            .alignment = .center,
        }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 29), center.glyphs[1].x_advance, 0.001);

    var styled_buffer = StyledParagraphBuffer.init(allocator);
    defer styled_buffer.deinit();
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 61,
        .font_size = 20,
    }};
    const styled = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &shape_buffer,
        &styled_buffer,
        text,
        20,
        &spans,
        .{
            .max_width = 120,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .center,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 29), styled.glyphs[1].x_advance, 0.001);
    try std.testing.expectEqual(styled.glyphs.len, styled_buffer.glyphMetadata().len);
}

test "aligned tab fields include paragraph and styled spacing" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\tAA";
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const paragraph_spaced = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 140,
            .letter_spacing = 2,
            .tab_stops = &.{.{
                .position = 70,
                .alignment = .end,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 18),
        paragraph_spaced.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 70),
        paragraph_spaced.lines[0].width,
        0.001,
    );

    var styled_buffer = StyledParagraphBuffer.init(allocator);
    defer styled_buffer.deinit();
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 62,
        .font_size = 20,
        .letter_spacing = 3,
    }};
    const styled = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled_buffer,
        text,
        20,
        &spans,
        .{
            .max_width = 140,
            .letter_spacing = 2,
            .tab_stops = &.{.{
                .position = 70,
                .alignment = .end,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 9),
        styled.glyphs[1].x_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 70),
        styled.lines[0].width,
        0.001,
    );
}

test "RTL aligned tabs retain logical field geometry" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "א\tבג",
        20,
        .{
            .max_width = 120,
            .direction = .rtl,
            .tab_stops = &.{.{
                .position = 60,
                .alignment = .end,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 60), layout.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), layout.lines[0].x, 0.001);
    const tab_index = for (layout.glyphs, 0..) |glyph, glyph_index| {
        if (glyph.isTab()) break glyph_index;
    } else return error.TestExpectedTabMarker;
    try std.testing.expectApproxEqAbs(
        @as(f32, 12),
        layout.glyphs[tab_index].x_advance,
        0.001,
    );

    var geometry = try paragraph.buildGeometry(
        allocator,
        "א\tבג",
        layout,
        .{ .direction = .rtl },
    );
    defer geometry.deinit();
    try std.testing.expectEqual(@as(usize, 4), geometry.graphemes.len);
}
