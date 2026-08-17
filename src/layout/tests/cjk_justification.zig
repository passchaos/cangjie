const std = @import("std");
const font_mod = @import("../../font.zig");
const glyph_position = @import("../glyph_position.zig");
const retained_paragraph = @import("../paragraph/retained.zig");
const styled_buffer = @import("../styled_buffer.zig");
const styled_paragraph = @import("../styled_paragraph.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

test "CJK soft-wrapped lines justify without spaces" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "一丁丂",
        20,
        .{
            .max_width = 40,
            .alignment = .justify,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), paragraph.lines[0].width, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        lineAdvance(paragraph.lines[0].glyphs(paragraph)),
        0.001,
    );
    // The entire gap belongs to the first source atom's trailing edge, so
    // caret and selection geometry observe the same justified position.
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        paragraph.glyphs[0].x_advance,
        0.001,
    );
    const selection = paragraph.selectionRectForBytes(0, "一".len);
    try std.testing.expectApproxEqAbs(@as(f32, 24), selection.width, 0.001);
    const caret = paragraph.caretRect(.{
        .glyph_index = 1,
        .cluster = "一".len,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 24), caret.x, 0.001);

    // The terminal line is never justified.
    try std.testing.expectApproxEqAbs(@as(f32, 16), paragraph.lines[1].width, 0.001);
}

test "CJK punctuation boundaries retain natural spacing" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3001, 0x4e00, 0x4e01 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const disable_kern = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "一、丁一",
        20,
        .{
            .max_width = 55,
            .alignment = .justify,
            .features = &disable_kern,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines[0].glyph_len);
    // Although the first line is non-terminal, punctuation on both candidate
    // boundaries prevents generic inter-character expansion.
    try std.testing.expectApproxEqAbs(@as(f32, 48), paragraph.lines[0].width, 0.001);
}

test "CJK line-end punctuation hangs without changing glyph geometry" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const text = "一。丁";

    const natural = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 32 },
    );
    try std.testing.expectEqual(@as(usize, 2), natural.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 32),
        natural.lines[0].width,
        0.001,
    );
    const punctuation_advance = natural.glyphs[1].x_advance;

    const hanging = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 32,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    const first = hanging.lines[0];
    try std.testing.expectEqual(@as(usize, 2), first.glyph_len);
    try std.testing.expectApproxEqAbs(
        punctuation_advance / 2,
        first.hang_end,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        lineAdvance(first.glyphs(hanging)) - first.hang_end,
        first.width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        punctuation_advance,
        hanging.glyphs[1].x_advance,
        0.001,
    );
    // Carets and selection remain source/glyph based, so hanging changes the
    // occupied measure without collapsing interactive text geometry.
    const trailing = hanging.caretRect(.{
        .glyph_index = first.glyph_start + first.glyph_len - 1,
        .cluster = "一。".len,
        .trailing = true,
    });
    try std.testing.expectApproxEqAbs(
        first.x + lineAdvance(first.glyphs(hanging)),
        trailing.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        lineAdvance(first.glyphs(hanging)),
        hanging.selectionRectForBytes(0, "一。".len).width,
        0.001,
    );
}

test "punctuation hanging enlarges line fit but not source ranges" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const text = "一丁。丂";

    const natural = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{ .max_width = 40 },
    );
    try std.testing.expectEqual(@as(usize, 1), natural.lines[0].glyph_len);

    const hanging = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 40,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    try std.testing.expectEqual(@as(usize, 3), hanging.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), hanging.lines[0].byte_start);
    try std.testing.expectEqual("一丁。".len, hanging.lines[0].byte_len);
    try std.testing.expectEqual(
        hanging.lines[0].byteEnd(),
        hanging.lines[1].byte_start,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        hanging.lines[0].width,
        0.001,
    );
}

test "retained CJK reflow restores and reapplies inter-character expansion" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var shape_buffer = context_output.Buffer.init(allocator);
    defer shape_buffer.deinit();

    var paragraph = try shaping_orchestrator.TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "一丁丂",
        20,
        .{ .max_width = 100 },
    );
    defer paragraph.deinit();
    const pristine_advance = paragraph.glyphs[0].x_advance;

    var reflow = retained_paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const justified = try paragraph.layout(&reflow, .{
        .max_width = 40,
        .alignment = .justify,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), justified.lines[0].width, 0.001);
    try std.testing.expect(justified.glyphs[0].x_advance > pristine_advance);

    const natural = try paragraph.layout(&reflow, .{
        .max_width = 100,
        .alignment = .left,
    });
    try std.testing.expectApproxEqAbs(pristine_advance, natural.glyphs[0].x_advance, 0.001);

    const justified_again = try paragraph.layout(&reflow, .{
        .max_width = 40,
        .alignment = .justify,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), justified_again.lines[0].width, 0.001);
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        paragraph.glyphs,
        shape_buffer.glyphs.items,
    );
}

test "retained reflow changes punctuation policy without reshaping" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var shape_buffer = context_output.Buffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try shaping_orchestrator.TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "一丁。丂",
        20,
        .{ .max_width = 100 },
    );
    defer paragraph.deinit();
    const pristine = try allocator.dupe(
        glyph_position.GlyphPosition,
        paragraph.glyphs,
    );
    defer allocator.free(pristine);

    var reflow = retained_paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const natural = try paragraph.layout(&reflow, .{ .max_width = 40 });
    try std.testing.expectEqual(@as(usize, 1), natural.lines[0].glyph_len);

    const hanging = try paragraph.layout(&reflow, .{
        .max_width = 40,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
    });
    try std.testing.expectEqual(@as(usize, 3), hanging.lines[0].glyph_len);
    try std.testing.expect(hanging.lines[0].hang_end > 0);

    const restored = try paragraph.layout(&reflow, .{ .max_width = 40 });
    try std.testing.expectEqual(@as(usize, 1), restored.lines[0].glyph_len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        restored.lines[0].hang_end,
        0.001,
    );
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        pristine,
        paragraph.glyphs,
    );
}

test "styled CJK justification preserves metadata and geometry" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = font_fallback.Cascade.init(&fonts);
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    const text = "一丁丂";
    const spans = [_]styled_paragraph.Span{
        .{
            .byte_start = 0,
            .byte_len = "一".len,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = "一".len,
            .byte_len = text.len - "一".len,
            .style_index = 2,
            .font_size = 20,
        },
    };

    const paragraph = try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 40,
            .alignment = .justify,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectApproxEqAbs(@as(f32, 40), paragraph.lines[0].width, 0.001);
    try std.testing.expectEqual(paragraph.glyphs.len, styled.glyphMetadata().len);
    try std.testing.expectEqual(@as(u32, 1), styled.glyphMetadata()[0].style_index);
    try std.testing.expectEqual(@as(u32, 2), styled.glyphMetadata()[1].style_index);
    const selection = paragraph.selectionRectForBytes(0, "一".len);
    try std.testing.expectApproxEqAbs(@as(f32, 24), selection.width, 0.001);
}

test "styled paragraph retains punctuation hanging metadata alignment" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x3002, 0x4e00, 0x4e01 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    const text = "一。丁";
    const spans = [_]styled_paragraph.Span{
        .{
            .byte_start = 0,
            .byte_len = "一。".len,
            .style_index = 4,
            .font_size = 20,
        },
        .{
            .byte_start = "一。".len,
            .byte_len = "丁".len,
            .style_index = 8,
            .font_size = 20,
        },
    };
    const paragraph =
        try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
            cascade,
            &buffer,
            &styled,
            text,
            20,
            &spans,
            .{
                .max_width = 32,
                .punctuation = .{ .end_hanging_fraction = 0.5 },
            },
        );
    try std.testing.expect(paragraph.lines[0].hang_end > 0);
    try std.testing.expectEqual(
        paragraph.glyphs.len,
        styled.glyphMetadata().len,
    );
    try std.testing.expectEqual(
        @as(u32, 4),
        styled.glyphMetadata()[1].style_index,
    );
}

test "ellipsis replaces terminal hanging punctuation without stale width" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ '.', 0x3002, 0x4e00, 0x4e01, 0x4e02 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "一丁。丂",
        20,
        .{
            .max_width = 40,
            .max_lines = 1,
            .ellipsis = true,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    const line = paragraph.lines[0];
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        line.hang_end,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        lineAdvance(line.glyphs(paragraph)),
        line.width,
        0.001,
    );
    // The existing plain-text ellipsis contract always emits three dots even
    // when the synthetic marker itself exceeds `max_width`.
    try std.testing.expectEqual(
        @as(u21, '.'),
        line.glyphs(paragraph)[line.glyph_len - 1].codepoint,
    );
}

test "RTL punctuation hangs at the physical start edge" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x05d0, 0x05d1, 0x3002 },
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const text = "אב。";

    const natural = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
        },
    );
    const natural_x = natural.lines[0].x;
    const natural_width = natural.lines[0].width;
    const hanging = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
            .punctuation = .{ .end_hanging_fraction = 0.5 },
        },
    );
    const line = hanging.lines[0];
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        line.hang_end,
        0.001,
    );
    try std.testing.expect(line.hang_start > 0);
    try std.testing.expectApproxEqAbs(
        natural_x,
        line.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        natural_width - line.hang_start,
        line.width,
        0.001,
    );
    try std.testing.expect(
        line.glyphs(hanging)[0].codepoint == 0x3002,
    );
}

fn lineAdvance(glyphs: []const glyph_position.GlyphPosition) f32 {
    var total: f32 = 0;
    for (glyphs) |glyph| total += glyph.x_advance;
    return total;
}
