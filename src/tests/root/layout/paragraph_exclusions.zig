//! Rectangular exclusion regions across one-shot, retained, and styled reflow.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const TextShaper = support.TextShaper;

test "left and right exclusions persist line regions through alignment" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "A A A A A";

    const left = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 80,
            .alignment = .center,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 24,
                .height = 20,
            }},
        },
    );
    try std.testing.expect(left.lines.len >= 2);
    try std.testing.expectApproxEqAbs(@as(f32, 24), left.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 56), left.lines[0].region_width, 0.001);
    try std.testing.expect(left.lines[0].x >= left.lines[0].region_x);
    try std.testing.expect(
        left.lines[0].x + left.lines[0].width <=
            left.lines[0].region_x + left.lines[0].region_width + 0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), left.lines[1].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80), left.lines[1].region_width, 0.001);

    const right = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 80,
            .alignment = .right,
            .exclusions = &.{.{
                .x = 56,
                .y = 0,
                .width = 24,
                .height = 20,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), right.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 56), right.lines[0].region_width, 0.001);
    try std.testing.expect(
        right.lines[0].x + right.lines[0].width <= 56.001,
    );
}

test "multiple exclusions select widest region with directional tie break" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const widest_exclusions = [_]paragraph.Exclusion{
        .{ .x = 20, .y = 0, .width = 10, .height = 30 },
        .{ .x = 60, .y = 0, .width = 10, .height = 30 },
    };

    const ltr = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A",
        20,
        .{
            .max_width = 90,
            .exclusions = &widest_exclusions,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 30), ltr.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), ltr.lines[0].region_width, 0.001);

    const tie = [_]paragraph.Exclusion{
        .{ .x = 30, .y = 0, .width = 20, .height = 30 },
    };
    const tie_ltr = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A",
        20,
        .{
            .max_width = 80,
            .exclusions = &tie,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), tie_ltr.lines[0].region_x, 0.001);

    const rtl = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A",
        20,
        .{
            .max_width = 80,
            .direction = .rtl,
            .exclusions = &tie,
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 50), rtl.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), rtl.lines[0].region_width, 0.001);
}

test "first-line indent narrows the exclusion container before subtraction" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
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
        "A",
        20,
        .{
            .max_width = 80,
            .first_line_indent = 20,
            .exclusions = &.{.{
                .x = 20,
                .y = 0,
                .width = 10,
                .height = 20,
            }},
        },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.lines[0].indent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), layout.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), layout.lines[0].region_width, 0.001);
}

test "unbounded paragraphs still subtract finite exclusions" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
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
        "A",
        20,
        .{
            .max_width = std.math.inf(f32),
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 20,
                .height = 20,
            }},
        },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.lines[0].region_x, 0.001);
    try std.testing.expect(std.math.isInf(layout.lines[0].region_width));
    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.lines[0].x, 0.001);
}

test "fully blocked bands move text below the nearest exclusion bottom" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
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
        "A A",
        20,
        .{
            .max_width = 60,
            .exclusions = &.{
                .{ .x = 0, .y = 0, .width = 60, .height = 30 },
                .{ .x = 0, .y = 0, .width = 60, .height = 80 },
            },
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 80), layout.lines[0].y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60), layout.lines[0].region_width, 0.001);

    const no_wrap = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A A",
        20,
        .{
            .max_width = 20,
            .wrap_mode = .no_wrap,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 20,
                .height = 100,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), no_wrap.lines[0].y, 0.001);
    try std.testing.expectEqual(@as(usize, 1), no_wrap.lines.len);
}

test "retained reflow changes exclusions without reshaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&fonts),
        &shape_buffer,
        "A A A A",
        20,
        .{ .max_width = 100 },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const excluded = try shaped.layout(&reflow, .{
        .max_width = 100,
        .exclusions = &.{.{
            .x = 0,
            .y = 0,
            .width = 50,
            .height = 21,
        }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 50), excluded.lines[0].region_x, 0.001);
    const excluded_line_count = excluded.lines.len;

    const plain = try shaped.layout(&reflow, .{ .max_width = 100 });
    try std.testing.expectEqual(@as(usize, 1), plain.lines.len);
    try std.testing.expect(excluded_line_count > plain.lines.len);

    const repeated = try shaped.layout(&reflow, .{
        .max_width = 100,
        .exclusions = &.{.{
            .x = 0,
            .y = 0,
            .width = 50,
            .height = 21,
        }},
    });
    try std.testing.expectEqual(excluded_line_count, repeated.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 50), repeated.lines[0].region_x, 0.001);
}

test "styled minimum line height participates in exclusion overlap" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AA";
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 4,
        .font_size = 20,
        .minimum_line_height = 40,
    }};
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 80,
            .exclusions = &.{.{
                .x = 0,
                .y = 25,
                .width = 40,
                .height = 10,
            }},
        },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.lines[0].height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.lines[0].region_x, 0.001);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
}

test "tall styled overflow keeps a fitting earlier soft break" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AA A";
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 3,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 3,
            .byte_len = 1,
            .style_index = 2,
            .font_size = 20,
            .minimum_line_height = 40,
        },
    };
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 50,
            .exclusions = &.{.{
                .x = 0,
                .y = 25,
                .width = 30,
                .height = 10,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    // The overflowing tall glyph narrows its prospective band, but the
    // preceding "AA" candidate has the normal-height full measure and remains
    // the preferred soft break. Its discarded space belongs only to source
    // geometry, not to the visible glyph range or occupied width.
    try std.testing.expectEqual(@as(usize, 2), layout.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 30), layout.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), layout.lines[0].region_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 30), layout.lines[1].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), layout.lines[1].region_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), layout.lines[1].height, 0.001);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
}

test "exclusion regions constrain justification and ellipsis post-processing" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const justified = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A A A A",
        20,
        .{
            .max_width = 80,
            .alignment = .justify,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 30,
                .height = 20,
            }},
        },
    );
    try std.testing.expect(justified.lines.len >= 2);
    try std.testing.expectApproxEqAbs(
        justified.lines[0].region_width,
        justified.lines[0].width,
        0.001,
    );
    try std.testing.expect(
        justified.lines[0].x + justified.lines[0].width <=
            justified.lines[0].region_x +
                justified.lines[0].region_width + 0.001,
    );

    const ellipsized = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A A A A A",
        20,
        .{
            .max_width = 80,
            .max_lines = 1,
            .ellipsis = true,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 30,
                .height = 20,
            }},
        },
    );
    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    try std.testing.expect(
        ellipsized.lines[0].width <=
            ellipsized.lines[0].region_width + 0.001,
    );
    try std.testing.expect(
        ellipsized.lines[0].x + ellipsized.lines[0].width <=
            ellipsized.lines[0].region_x +
                ellipsized.lines[0].region_width + 0.001,
    );
}

test "exclusion regions constrain punctuation compression and hanging" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3001, 0x3002, 0x4e00, 0x4e01 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const exclusion = paragraph.Exclusion{
        .x = 0,
        .y = 0,
        .width = 38,
        .height = 20,
    };

    const compressed = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "一。、丁",
        20,
        .{
            .max_width = 80,
            .exclusions = &.{exclusion},
            .punctuation = .{ .max_compression_fraction = 1 },
        },
    );
    try std.testing.expectEqual(@as(usize, 3), compressed.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 38), compressed.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 42), compressed.lines[0].region_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 42), compressed.lines[0].width, 0.001);
    try std.testing.expect(
        compressed.lines[0].x + compressed.lines[0].width <= 80.001,
    );

    const hanging = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "一。丁",
        20,
        .{
            .max_width = 80,
            .alignment = .right,
            .exclusions = &.{.{
                .x = 0,
                .y = 0,
                .width = 48,
                .height = 20,
            }},
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), hanging.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 48), hanging.lines[0].region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), hanging.lines[0].region_width, 0.001);
    try std.testing.expect(hanging.lines[0].hang_end > 0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 80),
        hanging.lines[0].x + hanging.lines[0].width,
        0.001,
    );
}

test "attributed paragraph styles forward rectangular exclusions" {
    const style_mod = @import("../../../text/style/root.zig");
    const exclusion = paragraph.Exclusion{
        .x = 1,
        .y = 2,
        .width = 3,
        .height = 4,
    };
    const options = (style_mod.ParagraphStyle{
        .exclusions = &.{exclusion},
    }).paragraphOptions(100);
    try std.testing.expectEqual(@as(usize, 1), options.exclusions.len);
    try std.testing.expectEqual(exclusion, options.exclusions[0]);
}
