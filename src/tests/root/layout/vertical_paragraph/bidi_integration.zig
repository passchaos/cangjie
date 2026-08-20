//! Retained and styled integration for vertical UAX #9.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const policy_support = @import("policy_support.zig");
const support = @import("../../support.zig");
const Font = policy_support.Font;
const FontCascade = policy_support.FontCascade;
const LayoutBuffer = policy_support.LayoutBuffer;
const TextShaper = policy_support.TextShaper;

test "retained vertical bidi reorders each restored layout only" {
    const allocator = std.testing.allocator;
    const text = "AאבB";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
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
            .max_width = 200,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    try expectClusters(shaped.glyphs, &.{ 0, 1, 3, 5 });
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const wide = try shaped.layout(&reflow, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try expectClusters(wide.glyphs, &.{ 0, 3, 1, 5 });
    const narrow = try shaped.layout(&reflow, .{
        .max_width = 40.1,
        .word_break = .break_all,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expectEqual(@as(usize, 2), narrow.lines.len);
    try expectClusters(shaped.glyphs, &.{ 0, 1, 3, 5 });
    const repeated = try shaped.layout(&reflow, .{
        .max_width = 200,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try expectClusters(repeated.glyphs, &.{ 0, 3, 1, 5 });
}

test "styled vertical bidi keeps metadata parallel to visual glyphs" {
    const allocator = std.testing.allocator;
    const text = "AאבB";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{ .byte_start = 0, .byte_len = 1, .style_index = 1, .font_size = 20 },
        .{ .byte_start = 1, .byte_len = 2, .style_index = 2, .font_size = 20 },
        .{ .byte_start = 3, .byte_len = 2, .style_index = 3, .font_size = 20 },
        .{ .byte_start = 5, .byte_len = 1, .style_index = 4, .font_size = 20 },
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
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try expectClusters(result.glyphs, &.{ 0, 3, 1, 5 });
    const metadata = styled.glyphMetadata();
    try std.testing.expectEqualSlices(u32, &.{ 1, 3, 2, 4 }, &.{
        metadata[0].style_index,
        metadata[1].style_index,
        metadata[2].style_index,
        metadata[3].style_index,
    });

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        result,
        &spans,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectEqual(@as(?u32, 2), geometry.spans[1].style_index);
    try std.testing.expectEqual(@as(?u32, 3), geometry.spans[2].style_index);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[1].direction,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[2].direction,
    );
    // TextGeometry spans remain in logical source order, while their physical
    // y positions encode the final visual order inside the RTL subrun.
    try std.testing.expect(
        geometry.spans[1].bounds.y > geometry.spans[2].bounds.y,
    );
}

test "styled explicit override keeps metadata parallel across soft columns" {
    const allocator = std.testing.allocator;
    const text = "\u{202e}ABCD\u{202c}";
    const bytes = try @import("../../../../test_font.zig")
        .buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{
        .{ .byte_start = 0, .byte_len = 4, .style_index = 1, .font_size = 20 },
        .{ .byte_start = 4, .byte_len = 2, .style_index = 2, .font_size = 20 },
        .{ .byte_start = 6, .byte_len = 1, .style_index = 3, .font_size = 20 },
        .{ .byte_start = 7, .byte_len = 3, .style_index = 4, .font_size = 20 },
    };

    const result = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 40.1,
            .word_break = .break_all,
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    var visible_clusters: [4]usize = undefined;
    var visible_styles: [4]u32 = undefined;
    var visible_count: usize = 0;
    for (result.glyphs, styled.glyphMetadata()) |glyph, metadata| {
        if (glyph.codepoint < 'A' or glyph.codepoint > 'D') continue;
        if (visible_count >= visible_clusters.len) {
            return error.TestUnexpectedVisibleGlyph;
        }
        visible_clusters[visible_count] = glyph.cluster;
        visible_styles[visible_count] = metadata.style_index;
        visible_count += 1;
    }
    try std.testing.expectEqual(visible_clusters.len, visible_count);
    try std.testing.expectEqualSlices(usize, &.{ 4, 3, 6, 5 }, &visible_clusters);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1, 3, 2 }, &visible_styles);
}

fn expectClusters(glyphs: []const support.GlyphPosition, expected: []const usize) !void {
    try std.testing.expectEqual(expected.len, glyphs.len);
    for (glyphs, expected) |glyph, cluster| {
        try std.testing.expectEqual(cluster, glyph.cluster);
    }
}
