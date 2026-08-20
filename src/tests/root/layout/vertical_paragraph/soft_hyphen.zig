//! Source U+00AD discretionary hyphens in vertical paragraph columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

const text = "co\u{00ad}operate";
const soft_hyphen_index: usize = 2;

test "vertical soft hyphen is visible only at its selected boundary" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const unwrapped = try layout(&font, &buffer, .{
        .max_width = 1000,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), unwrapped.lines.len);
    const unselected_index =
        findCodepoint(unwrapped.glyphs, 0x00ad) orelse
        return error.TestExpectedSoftHyphen;
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        unwrapped.glyphs[unselected_index].y_advance,
        0.001,
    );
    try std.testing.expect(
        !unwrapped.glyphs[unselected_index].isDiscretionaryHyphen(),
    );
    const one = unwrapped.glyphs[0].y_advance;

    const wrapped = try layout(&font, &buffer, .{
        .max_width = one * 3 + 0.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectVisibleHyphen(wrapped, 0x2010);
    try std.testing.expect(wrapped.lines[0].x < wrapped.lines[1].x);
    try std.testing.expectEqual(@as(usize, 0), wrapped.lines[0].byte_start);
    try std.testing.expectEqual(
        @as(usize, "co\u{00ad}".len),
        wrapped.lines[0].byte_len,
    );
    try std.testing.expectEqual(
        wrapped.lines[0].byteEnd(),
        wrapped.lines[1].byte_start,
    );
    try std.testing.expectEqual(
        text.len,
        wrapped.lines[wrapped.lines.len - 1].byteEnd(),
    );
    try std.testing.expectApproxEqAbs(
        one * 3,
        wrapped.lines[0].height,
        0.001,
    );

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        wrapped,
        .{},
    );
    defer geometry.deinit();
    const fragments = try geometry.selectionFragments(
        allocator,
        .{
            .byte_start = soft_hyphen_index,
            .byte_end = "co\u{00ad}".len,
        },
    );
    defer allocator.free(fragments);
    try std.testing.expectEqual(@as(usize, 1), fragments.len);
    try std.testing.expect(fragments[0].rect.height > 0);
    var draw_list = try support.buildGlyphDrawList(allocator, wrapped, .{});
    defer draw_list.deinit();
    var saw_hyphen = false;
    for (draw_list.glyphs) |glyph| {
        if (glyph.codepoint == 0x2010) saw_hyphen = true;
    }
    try std.testing.expect(saw_hyphen);
}

test "vertical soft hyphen inserts when shaping omits its source atom" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
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
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const unwrapped = try layout(&font, &buffer, .{
        .max_width = 1000,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(findCodepoint(unwrapped.glyphs, 0x00ad) == null);
    const source_glyph_count = unwrapped.glyphs.len;

    const wrapped = try layout(&font, &buffer, .{
        .max_width = unwrapped.glyphs[0].y_advance * 3 + 0.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectVisibleHyphen(wrapped, 0x2010);
    try std.testing.expectEqual(source_glyph_count + 1, wrapped.glyphs.len);
    const hyphen_index =
        findDiscretionaryHyphen(wrapped.lines[0].glyphs(wrapped)).?;
    const hyphen = wrapped.lines[0].glyphs(wrapped)[hyphen_index];
    try std.testing.expectEqual(@as(usize, soft_hyphen_index), hyphen.cluster);
    try std.testing.expectEqual(
        @as(usize, "\u{00ad}".len),
        hyphen.source_byte_len,
    );
}

test "vertical sideways soft hyphen uses horizontal advance along y" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, .{
        .max_width = 60.1,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
        .text_orientation = .sideways,
    });
    const first = result.lines[0].glyphs(result);
    const hyphen = first[findDiscretionaryHyphen(first).?];
    try std.testing.expectEqual(
        support.GlyphOrientation.sideways,
        hyphen.orientation,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), hyphen.x_advance, 0.001);
    try std.testing.expect(hyphen.y_advance > 0);
}

test "vertical aligned tab field measures its terminal soft hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const tab_text = "a\tco\u{00ad}operate";

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        tab_text,
        20,
        .{
            .max_width = 100.1,
            .overflow_wrap = .normal,
            .tab_stops = &.{.{
                .position = 100,
                .alignment = .end,
            }},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(result.lines.len >= 2);
    const first = result.lines[0].glyphs(result);
    const hyphen_index =
        findDiscretionaryHyphen(first) orelse
        return error.TestExpectedVisibleHyphen;
    try std.testing.expect(first[hyphen_index].y_advance > 0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 100),
        result.lines[0].height,
        0.001,
    );
}

test "vertical balanced wrapping retains a selected soft hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, .{
        .max_width = 60.1,
        .line_break_strategy = .balanced,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectVisibleHyphen(result, 0x2010);
    try std.testing.expect(result.lines[0].x > result.lines[1].x);
}

test "vertical custom hyphen is exact and never becomes invisible" {
    const allocator = std.testing.allocator;
    const bytes = try hyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const custom = try layout(&font, &buffer, .{
        .max_width = 60.1,
        .overflow_wrap = .normal,
        .hyphenation = .{ .character = 0x2022 },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectVisibleHyphen(custom, 0x2022);

    const unsupported = try layout(&font, &buffer, .{
        .max_width = 60.1,
        .overflow_wrap = .normal,
        .hyphenation = .{ .character = 0x2603 },
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    // An exact requested character that the owning font cannot render makes
    // the discretionary opportunity unavailable; it must not create an
    // invisible break at U+00AD.
    try std.testing.expectEqual(@as(usize, 1), unsupported.lines.len);
    try std.testing.expect(
        !unsupported.glyphs[soft_hyphen_index].isDiscretionaryHyphen(),
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        unsupported.glyphs[soft_hyphen_index].y_advance,
        0.001,
    );
}

test "vertical ellipsis replaces a continuation soft hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try omittedSoftHyphenFont(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const result = try layout(&font, &buffer, .{
        .max_width = 60.1,
        .max_lines = 1,
        .ellipsis = true,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    const glyphs = result.lines[0].glyphs(result);
    try std.testing.expect(glyphs.len >= 3);
    for (glyphs) |glyph| {
        try std.testing.expect(!glyph.isDiscretionaryHyphen());
    }
    for (glyphs[glyphs.len - 3 ..]) |glyph| {
        try std.testing.expectEqual(@as(u21, '.'), glyph.codepoint);
    }
    try std.testing.expect(result.lines[0].height <= 60.101);
}

test "vertical bidi retains a materialized soft hyphen in its source column" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x0020,
            0x002d,
            'A',
            'B',
            0x00ad,
            0x05d0,
            0x05d1,
            0x05d2,
            0x05d3,
            0x2010,
        },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const bidi_text = "Aאב\u{00ad}גדB";

    const result = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        bidi_text,
        20,
        .{
            .max_width = 80.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(result.lines.len >= 2);
    const first = result.lines[0].glyphs(result);
    const hyphen_index =
        findDiscretionaryHyphen(first) orelse
        return error.TestExpectedVisibleHyphen;
    try std.testing.expectEqual(@as(u21, 0x2010), first[hyphen_index].codepoint);
    try std.testing.expectEqual(@as(usize, 0), result.lines[0].byte_start);
    try std.testing.expectEqual(
        @as(usize, "Aאב\u{00ad}".len),
        result.lines[0].byteEnd(),
    );
    try std.testing.expectEqual(
        result.lines[0].byteEnd(),
        result.lines[1].byte_start,
    );
}

fn layout(
    font: *const Font,
    buffer: *LayoutBuffer,
    options: support.ParagraphOptions,
) !support.ParagraphLayout {
    return TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{font}),
        buffer,
        text,
        20,
        options,
    );
}

fn expectVisibleHyphen(
    result: support.ParagraphLayout,
    codepoint: u21,
) !void {
    try std.testing.expect(result.lines.len >= 2);
    const first = result.lines[0].glyphs(result);
    const hyphen_index =
        findDiscretionaryHyphen(first) orelse
        return error.TestExpectedVisibleHyphen;
    const hyphen = first[hyphen_index];
    try std.testing.expect(hyphen.isDiscretionaryHyphen());
    try std.testing.expect(!hyphen.isAutomaticHyphen());
    try std.testing.expectEqual(codepoint, hyphen.codepoint);
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        hyphen.orientation,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 0), hyphen.x_advance, 0.001);
    try std.testing.expect(hyphen.y_advance > 0);
    try std.testing.expect(hyphen.x_offset < 0);
    try std.testing.expect(hyphen.y_offset < 0);
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
            0x0020,
            0x002d,
            '.',
            'a',
            'c',
            'e',
            'o',
            'p',
            'r',
            't',
            0x00ad,
            0x2010,
            0x2022,
        },
    );
}

fn omittedSoftHyphenFont(allocator: std.mem.Allocator) ![]u8 {
    return @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{
            0x002d,
            '.',
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
