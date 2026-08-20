//! Retained and styled integration for vertical U+00AD materialization.

const std = @import("std");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

const text = "co\u{00ad}operate";
const soft_hyphen_index: usize = 2;

test "retained vertical soft hyphen restores across reflow widths" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 1000,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    const pristine = try allocator.dupe(@TypeOf(shaped.glyphs[0]), shaped.glyphs);
    defer allocator.free(pristine);
    const one = shaped.glyphs[0].y_advance;
    const widths = try shaped.contentWidths(.{
        .max_width = 1000,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(one * 7, widths.min, 0.001);
    try std.testing.expectApproxEqAbs(one * 9, widths.max, 0.001);

    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const wrapped = try shaped.layout(&reflow, .{
        .max_width = one * 3 + 0.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectVisibleHyphen(wrapped);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );

    const restored = try shaped.layout(&reflow, .{
        .max_width = 1000,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), restored.lines.len);
    try std.testing.expectEqual(pristine.len, restored.glyphs.len);
    try std.testing.expect(findDiscretionaryHyphen(restored.glyphs) == null);
    try std.testing.expect(findCodepoint(restored.glyphs, 0x00ad) == null);
}

test "styled vertical soft hyphen keeps metadata parallel" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = "co\u{00ad}".len,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = "co\u{00ad}".len,
            .byte_len = text.len - "co\u{00ad}".len,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 60.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectVisibleHyphen(result);
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    const hyphen_index =
        findDiscretionaryHyphen(result.lines[0].glyphs(result)) orelse
        return error.TestExpectedVisibleHyphen;
    try std.testing.expectEqual(
        @as(u32, 1),
        styled.glyphMetadata()[
            result.lines[0].glyph_start + hyphen_index
        ].style_index,
    );
    const widths = styled.contentWidths().?;
    try std.testing.expectApproxEqAbs(
        result.glyphs[0].y_advance * 7,
        widths.min,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.glyphs[0].y_advance * 9,
        widths.max,
        0.001,
    );
}

fn expectVisibleHyphen(result: support.ParagraphLayout) !void {
    try std.testing.expect(result.lines.len >= 2);
    const first = result.lines[0].glyphs(result);
    const hyphen_index =
        findDiscretionaryHyphen(first) orelse
        return error.TestExpectedVisibleHyphen;
    try std.testing.expect(first[hyphen_index].isDiscretionaryHyphen());
    try std.testing.expectEqual(
        @as(u21, 0x2010),
        first[hyphen_index].codepoint,
    );
    try std.testing.expect(first[hyphen_index].y_advance > 0);
}

fn findCodepoint(
    glyphs: []const support.GlyphPosition,
    codepoint: u21,
) ?usize {
    for (glyphs, 0..) |glyph, index| {
        if (glyph.codepoint == codepoint) return index;
    }
    return null;
}

fn findDiscretionaryHyphen(
    glyphs: []const support.GlyphPosition,
) ?usize {
    for (glyphs, 0..) |glyph, index| {
        if (glyph.isDiscretionaryHyphen()) return index;
    }
    return null;
}

fn hyphenFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            'a',
            'c',
            'e',
            'o',
            'p',
            'r',
            't',
            0x00ad,
            0x2010,
        },
    );
}
