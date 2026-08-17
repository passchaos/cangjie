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

fn lineAdvance(glyphs: []const glyph_position.GlyphPosition) f32 {
    var total: f32 = 0;
    for (glyphs) |glyph| total += glyph.x_advance;
    return total;
}
