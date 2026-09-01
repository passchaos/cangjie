//! Inline object integration across shaping, reflow, bidi, and rendering.

const std = @import("std");
const support = @import("../support.zig");
const inline_object = @import("../../../layout/inline_object/root.zig");
const render_bridge = @import("../../../render/bridge/root.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const TextShaper = support.TextShaper;

test "in-flow object wraps, owns line height, caret geometry, and draw output" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "A" ++ inline_object.object_replacement_utf8 ++ "A";
    const object = inline_object.Object{
        .id = 42,
        .byte_index = 1,
        .width = 18,
        .height = 30,
        .baseline = 10,
    };
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 30,
            .inline_objects = &.{object},
        },
    );

    try std.testing.expectEqual(@as(usize, 3), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.inline_objects.len);
    const positioned = paragraph.inline_objects[0];
    try std.testing.expectEqual(@as(u64, 42), positioned.id);
    try std.testing.expectEqual(@as(usize, 1), positioned.line_index);
    try std.testing.expectApproxEqAbs(@as(f32, 18), paragraph.lines[1].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 36), paragraph.lines[1].height, 0.001);
    try std.testing.expectApproxEqAbs(
        paragraph.lines[1].y + paragraph.lines[1].baseline -
            object.resolvedBaseline(),
        positioned.y,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].inlineObjects(paragraph).len);

    const leading = paragraph.hitTest(positioned.x + 1, positioned.y + 1);
    const trailing = paragraph.hitTest(
        positioned.x + positioned.width - 1,
        positioned.y + 1,
    );
    try std.testing.expectEqual(@as(usize, 1), leading.cluster);
    try std.testing.expectEqual(@as(usize, 4), trailing.cluster);
    try std.testing.expect(trailing.trailing);
    const selection = paragraph.selectionRectForBytes(1, 4);
    try std.testing.expectApproxEqAbs(
        positioned.width,
        selection.width,
        0.001,
    );

    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        paragraph,
        .{ .origin_x = 3, .origin_y = 5 },
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 1), draw_list.inline_objects.len);
    try std.testing.expectApproxEqAbs(
        positioned.x + 3,
        draw_list.inline_objects[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        positioned.anchor_x + 3,
        draw_list.inline_objects[0].anchor_x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        positioned.anchor_y + 5,
        draw_list.inline_objects[0].anchor_y,
        0.001,
    );
    // The marker is not font-owned and therefore produces no glyph draw.
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
}

test "out-of-flow object anchors without changing width or line height" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    const text = "A" ++ inline_object.object_replacement_utf8 ++ "A";

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .inline_objects = &.{.{
                .id = 7,
                .kind = .out_of_flow,
                .byte_index = 1,
                .width = 999,
                .height = 999,
            }},
        },
    );
    var visible_width: f32 = 0;
    var object_advance: ?f32 = null;
    for (paragraph.glyphs) |glyph| {
        if (glyph.isInlineObject()) {
            object_advance = glyph.x_advance;
        } else {
            visible_width += glyph.x_advance;
        }
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0), object_advance.?, 0.001);
    try std.testing.expectApproxEqAbs(visible_width, paragraph.width, 0.001);
    try std.testing.expect(paragraph.height < 999);
    try std.testing.expectEqual(@as(usize, 1), paragraph.inline_objects.len);
    try std.testing.expectEqual(
        inline_object.Kind.out_of_flow,
        paragraph.inline_objects[0].kind,
    );
    const hit = paragraph.hitTest(
        paragraph.inline_objects[0].x,
        paragraph.inline_objects[0].y,
    );
    try std.testing.expect(hit.cluster != 1);
}

test "LTR inline objects do not force bidi resolution" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;

    // U+FFFC still selects the paragraph's itemized shaping path, but neither
    // Latin nor Japanese needs resolved embedding levels. Keep that proof
    // visible here: the reusable UAX #9 storage must remain untouched while
    // the synthetic object's byte cluster and geometry stay intact.
    const fixtures = [_]struct { text: []const u8, marker_index: usize }{
        .{ .text = "A" ++ marker ++ "A", .marker_index = 1 },
        .{ .text = "あ" ++ marker ++ "い", .marker_index = "あ".len },
    };
    const kinds = [_]inline_object.Kind{
        .in_flow,
        .out_of_flow,
        .custom_out_of_flow,
    };
    for (fixtures) |fixture| {
        for (kinds) |kind| {
            var buffer = LayoutBuffer.init(allocator);
            defer buffer.deinit();
            const object = inline_object.Object{
                .id = 7,
                .kind = kind,
                .byte_index = fixture.marker_index,
                .width = 12,
                .height = 10,
                .baseline = 8,
            };
            const paragraph = try TextShaper.layoutParagraphUtf8(
                FontCascade.init(&fonts),
                &buffer,
                fixture.text,
                20,
                .{ .max_width = 100, .inline_objects = &.{object} },
            );

            try std.testing.expectEqual(@as(usize, 0), buffer.bidi_reorder_scratch.bidi_storage.scalars.items.len);
            try std.testing.expectEqual(@as(usize, 0), buffer.bidi_reorder_scratch.bidi_storage.scalars.capacity);
            try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs.len);
            try std.testing.expectEqual(fixture.marker_index, paragraph.glyphs[1].cluster);
            try std.testing.expectEqual(marker.len, paragraph.glyphs[1].source_byte_len);
            try std.testing.expect(paragraph.glyphs[1].isInlineObject());
            try std.testing.expectEqual(@as(usize, 1), paragraph.inline_objects.len);
            try std.testing.expectEqual(kind, paragraph.inline_objects[0].kind);
        }
    }
}

test "retained reflow updates object geometry without changing anchors" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A" ++ inline_object.object_replacement_utf8 ++ "A";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&fonts),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 100,
            .inline_objects = &.{.{
                .id = 1,
                .byte_index = 1,
                .width = 10,
                .height = 10,
            }},
        },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const paragraph = try shaped.layout(&reflow, .{
        .max_width = 100,
        .inline_objects = &.{.{
            .id = 9,
            .byte_index = 1,
            .width = 30,
            .height = 40,
            .baseline = 20,
        }},
    });
    try std.testing.expectEqual(@as(u64, 9), paragraph.inline_objects[0].id);
    try std.testing.expectApproxEqAbs(@as(f32, 30), paragraph.inline_objects[0].width, 0.001);
    try std.testing.expect(paragraph.height >= 40);

    try std.testing.expectError(error.InvalidInlineObjects, shaped.layout(&reflow, .{
        .max_width = 100,
        .inline_objects = &.{.{
            .id = 9,
            .byte_index = 0,
            .width = 30,
            .height = 40,
        }},
    }));
    try std.testing.expectError(error.InvalidInlineObjects, shaped.layout(&reflow, .{
        .max_width = 100,
        .inline_objects = &.{.{
            .id = 9,
            .byte_index = 1,
            .width = -1,
            .height = 40,
        }},
    }));
}

test "RTL object remains a non-font visual atom" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "א" ++ inline_object.object_replacement_utf8 ++ "ב";

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
            .inline_objects = &.{.{
                .id = 5,
                .byte_index = "א".len,
                .width = 12,
                .height = 12,
            }},
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.inline_objects.len);
    var font_owned_glyphs: usize = 0;
    for (paragraph.runs) |run| font_owned_glyphs += run.glyph_len;
    try std.testing.expectEqual(@as(usize, 2), font_owned_glyphs);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs.len);
}

test "object-only paragraph wraps without inventing font ownership" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const text = marker ++ marker ++ marker;

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        .{
            .max_width = 25,
            .inline_objects = &.{
                .{ .id = 1, .byte_index = 0, .width = 10, .height = 10 },
                .{ .id = 2, .byte_index = 3, .width = 10, .height = 10 },
                .{ .id = 3, .byte_index = 6, .width = 10, .height = 10 },
            },
        },
    );
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), paragraph.runs.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.inline_objects.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines[0].inline_object_len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[1].inline_object_len);
}
