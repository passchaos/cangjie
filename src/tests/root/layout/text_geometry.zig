//! Platform-neutral paragraph text-run geometry integration coverage.

const std = @import("std");

const inline_object = @import("../../../layout/inline_object/root.zig");
const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const TextShaper = support.TextShaper;

test "text geometry divides a shaped ligature over source graphemes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "AA AA";
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqual(@as(usize, 3), layout.glyphs.len);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(text.len, geometry.source_byte_len);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans.len);
    try std.testing.expectEqual(@as(usize, 5), geometry.graphemes.len);
    const span = geometry.spans[0];
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        span.direction,
    );
    try std.testing.expectEqual(@as(usize, 0), span.byte_start);
    try std.testing.expectEqual(text.len, span.byte_len);
    try std.testing.expect(span.font_run != null);
    try std.testing.expectEqual(@as(usize, 0), span.font_run.?.run_index);
    try std.testing.expectEqual(@as(usize, 0), span.font_run.?.cascade_index);
    try std.testing.expectApproxEqAbs(
        geometry.graphemes[0].width,
        geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        layout.glyphs[0].x_advance,
        geometry.graphemes[0].width + geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        layout.glyphs[2].x_advance,
        geometry.graphemes[3].width + geometry.graphemes[4].width,
        0.001,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 3 },
        span.wordStarts(geometry),
    );

    // Geometry owns its flat arrays rather than borrowing the reusable layout
    // buffer. A subsequent shaping call must not invalidate the first result.
    _ = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "A",
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqual(@as(usize, 5), geometry.graphemes.len);
    try std.testing.expectEqual(@as(usize, 3), geometry.graphemes[3].byte_start);
}

test "text geometry keeps bidi spans logical and positions RTL graphemes visually" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    const text = "AאבB";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 1, 5 }, &.{
        layout.glyphs[0].cluster,
        layout.glyphs[1].cluster,
        layout.glyphs[2].cluster,
        layout.glyphs[3].cluster,
    });

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        geometry.spans[0].direction,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[1].direction,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        geometry.spans[2].direction,
    );
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[0].previous_on_line);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[0].next_on_line);
    try std.testing.expectEqual(@as(?usize, 0), geometry.spans[1].previous_on_line);
    try std.testing.expectEqual(@as(?usize, 2), geometry.spans[1].next_on_line);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[2].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].next_on_line);

    const rtl = geometry.spans[1].graphemes(geometry);
    try std.testing.expectEqual(@as(usize, 1), rtl[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), rtl[1].byte_start);
    try std.testing.expectApproxEqAbs(@as(f32, 10), rtl[0].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rtl[1].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(
        layout.glyphs[0].x_advance,
        geometry.spans[1].bounds.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), geometry.spans[1].bounds.width, 0.001);
}

test "text geometry honors an explicit RTL paragraph base direction" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "אב";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{ .direction = .rtl },
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 1), geometry.spans.len);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[0].direction,
    );
    const graphemes = geometry.spans[0].graphemes(geometry);
    try std.testing.expectEqual(@as(usize, 0), graphemes[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), graphemes[1].byte_start);
    try std.testing.expect(graphemes[0].inline_position >
        graphemes[1].inline_position);
}

test "styled text geometry splits style identities and links only within a line" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    const text = "AA\nAA";
    const styles = [_]paragraph.StyledSpan{
        .{ .byte_start = 0, .byte_len = 1, .style_index = 4, .font_size = 16 },
        .{ .byte_start = 1, .byte_len = 2, .style_index = 7, .font_size = 16 },
        .{ .byte_start = 3, .byte_len = 2, .style_index = 9, .font_size = 16 },
    };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    var styled_buffer = StyledParagraphBuffer.init(allocator);
    defer styled_buffer.deinit();
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &layout_buffer,
        &styled_buffer,
        text,
        16,
        &styles,
        .{ .max_width = 100 },
    );

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        layout,
        &styles,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(@as(?u32, 4), geometry.spans[0].style_index);
    try std.testing.expectEqual(@as(?u32, 7), geometry.spans[1].style_index);
    try std.testing.expectEqual(@as(?u32, 9), geometry.spans[2].style_index);
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[0].line_index);
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[1].line_index);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans[2].line_index);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[0].next_on_line);
    try std.testing.expectEqual(@as(?usize, 0), geometry.spans[1].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[1].next_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].next_on_line);
    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        geometry.spans[0].wordStarts(geometry),
    );
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[1].word_start_len);
    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        geometry.spans[2].wordStarts(geometry),
    );
}

test "text geometry preserves fallback ownership and fontless inline objects" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
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
    const cascade = FontCascade.init(&fonts);

    const text = "A" ++ inline_object.object_replacement_utf8 ++ "B";
    const object = inline_object.Object{
        .id = 8,
        .byte_index = 1,
        .width = 12,
        .height = 18,
    };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 200,
            .inline_objects = &.{object},
        },
    );

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(@as(?usize, 0), if (geometry.spans[0].font_run) |run|
        run.cascade_index
    else
        null);
    try std.testing.expect(geometry.spans[1].font_run == null);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans[1].byte_start);
    try std.testing.expectApproxEqAbs(
        object.width,
        geometry.spans[1].bounds.width,
        0.001,
    );
    try std.testing.expectEqual(@as(?usize, 1), if (geometry.spans[2].font_run) |run|
        run.cascade_index
    else
        null);
}
