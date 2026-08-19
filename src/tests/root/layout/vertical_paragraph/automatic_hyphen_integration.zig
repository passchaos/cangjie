//! Retained and styled integration for vertical automatic hyphenation.

const std = @import("std");
const support = @import("../../support.zig");
const Dictionary = @import("../../../../text/hyphenation/root.zig").Dictionary;
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

const text = "hyphenation";

test "retained vertical automatic hyphenation restores and measures source" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();
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
            .hyphenation = .{ .dictionary = &dictionary },
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
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // "phen-" and "ation" are the largest authored min-content fragments.
    try std.testing.expectApproxEqAbs(one * 5, widths.min, 0.001);
    try std.testing.expectApproxEqAbs(one * text.len, widths.max, 0.001);

    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try shaped.layout(&reflow, .{
        .max_width = one * 3 + 0.1,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(narrow.lines.len >= 2);
    try std.testing.expect(
        narrow.lines[0].glyphs(narrow)[
            narrow.lines[0].glyph_len - 1
        ].isAutomaticHyphen(),
    );
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );

    const wide = try shaped.layout(&reflow, .{
        .max_width = 1000,
        .hyphenation = .{ .dictionary = &dictionary },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);
    try std.testing.expectEqual(pristine.len, wide.glyphs.len);
    for (wide.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        shaped.layout(&reflow, .{
            .max_width = one * 3 + 0.1,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        }),
    );
}

test "styled vertical automatic hyphen inherits preceding fragment metadata" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var dictionary = try Dictionary.init(
        allocator,
        "a1b",
        "hy-phenation",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 7,
            .font_size = 20,
            .letter_spacing = 3,
        },
        .{
            .byte_start = 2,
            .byte_len = text.len - 2,
            .style_index = 9,
            .font_size = 40,
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
            .max_width = 70.1,
            .max_lines = 1,
            .hyphenation = .{
                .dictionary = &dictionary,
                .character = 0x2022,
            },
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(result.glyphs.len, styled.glyphMetadata().len);
    const line = result.lines[0];
    const glyphs = line.glyphs(result);
    try std.testing.expect(glyphs.len != 0);
    const automatic = line.glyph_start + glyphs.len - 1;
    try std.testing.expect(result.glyphs[automatic].isAutomaticHyphen());
    try std.testing.expectEqual(@as(u21, 0x2022), result.glyphs[automatic].codepoint);
    const metadata = styled.glyphMetadata()[automatic];
    try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
    try std.testing.expectApproxEqAbs(@as(f32, 0), metadata.layout_spacing, 0.001);

    const ellipsized = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 60.1,
            .max_lines = 1,
            .ellipsis = true,
            .hyphenation = .{ .dictionary = &dictionary },
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), ellipsized.lines.len);
    try std.testing.expectEqual(
        ellipsized.glyphs.len,
        styled.glyphMetadata().len,
    );
    const terminal = ellipsized.lines[0].glyphs(ellipsized);
    for (terminal) |glyph| {
        try std.testing.expect(!glyph.isDiscretionaryHyphen());
    }
    try std.testing.expect(terminal.len >= 3);
    for (terminal[terminal.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
}

fn englishDictionary(allocator: std.mem.Allocator) !Dictionary {
    return Dictionary.init(
        allocator,
        "hyphenation",
        "hy-phen-ation",
        .{ .left_min = 2, .right_min = 2 },
    );
}

fn hyphenFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            '.',
            'a',
            'e',
            'h',
            'i',
            'n',
            'o',
            'p',
            't',
            'y',
            0x2010,
            0x2022,
        },
    );
}
