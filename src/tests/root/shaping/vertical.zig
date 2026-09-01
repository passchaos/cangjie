//! Vertical shaping, presentation, metrics, and cache integration coverage.

const std = @import("std");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const GlyphId = support.GlyphId;
const LayoutBuffer = support.LayoutBuffer;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const WritingMode = support.WritingMode;
const font_shaping = @import("../../../font.zig").shaping;

test "vertical shaping uses vmtx and keeps horizontal behavior isolated" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const horizontal = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expect(horizontal.width() > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), horizontal.height(), 0.001);
    try std.testing.expect(!horizontal.glyphs[0].isVertical());

    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 2), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    for (vertical.glyphs) |glyph| {
        try std.testing.expectEqual(
            support.GlyphOrientation.upright,
            glyph.orientation,
        );
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, -8), glyph.x_offset, 0.001);
    }
}

test "vertical shaping centers glyph extents when vmtx is absent" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const bounds = try font.glyphBounds(1);
    const font_height = @as(i32, font.ascender) - @as(i32, font.descender);
    const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
    const expected_origin = @as(i32, bounds.y_max) + @divFloor(font_height - glyph_height, 2);
    try std.testing.expectEqual(
        expected_origin,
        try font_shaping.verticalOriginYAtCoords(&font, 1, &.{}),
    );

    const font_size: f32 = @floatFromInt(font.units_per_em);
    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "A",
        font_size,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(
        -@as(f32, @floatFromInt(expected_origin)),
        vertical.glyphs[0].y_offset,
        0.001,
    );
}

test "vertical sideways text uses horizontal advance for rotated glyphs" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const sideways = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .sideways },
    );
    try std.testing.expectEqual(@as(usize, 2), sideways.glyphs.len);
    try std.testing.expectEqual(
        support.GlyphOrientation.sideways,
        sideways.glyphs[0].orientation,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 16), sideways.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), sideways.height(), 0.001);

    const mixed = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl },
    );
    try std.testing.expectEqual(
        support.GlyphOrientation.sideways,
        mixed.glyphs[0].orientation,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 16), mixed.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), mixed.height(), 0.001);

    const upright = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        upright.glyphs[0].orientation,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), upright.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), upright.height(), 0.001);
}

test "mixed vertical orientation follows CSS UAX 50 resolution" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        std.testing.allocator,
        false,
    );
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const mixed = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "A中、〈",
        20,
        .{ .writing_mode = .vertical_rl },
    );
    try std.testing.expectEqual(@as(usize, 4), mixed.glyphs.len);
    try std.testing.expectEqual(
        support.GlyphOrientation.sideways,
        mixed.glyphs[0].orientation,
    );
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        mixed.glyphs[1].orientation,
    );
    // CSS mixed keeps both Tu and Tr upright after vertical substitution had a
    // chance to supply their typographic variants.
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        mixed.glyphs[2].orientation,
    );
    try std.testing.expectEqual(
        support.GlyphOrientation.upright,
        mixed.glyphs[3].orientation,
    );

    const upright = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "A中",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    for (upright.glyphs) |glyph| {
        try std.testing.expectEqual(
            support.GlyphOrientation.upright,
            glyph.orientation,
        );
    }
}

test "vertical presentation fallback survives bottom-to-top shaping" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(std.testing.allocator, &.{
        0x3008,
        0x3009,
        0xfe3f,
        0xfe40,
    });
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const ttb = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), ttb.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), ttb.glyphs[0].glyph_id);

    const btt = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .direction = .rtl, .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), btt.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 4), btt.glyphs[0].glyph_id);
}

test "vertical paragraph bidi itemization preserves requested direction" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMixedScriptDirectionalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &buffer,
        "A\u{0628}",
        20,
        .{
            .max_width = 200,
            .direction = .rtl,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();

    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    // UAX #9 resolves Latin to an even (horizontal-LTR) level. Vertical RTL
    // must nevertheless remain bottom-to-top, so the directional `ltra`
    // substitution must not replace source glyph 1 with glyph 3.
    try std.testing.expectEqual(@as(GlyphId, 1), shaped.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
}

test "vertical shaped cache and fallback runs preserve independent y pens" {
    const test_font = @import("../../../test_font.zig");
    const primary_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(fallback_bytes);
    var primary = try Font.parse(std.testing.allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(std.testing.allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();
    var cache = ShapedRunCache.init(std.testing.allocator);
    defer cache.deinit();

    const horizontal = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{},
    );
    try std.testing.expect(horizontal.width() > 0);
    const vertical = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    try std.testing.expectEqual(@as(usize, 2), cache.entries.items.len);
    try std.testing.expectEqual(WritingMode.horizontal_tb, cache.entries.items[0].key.plan.writing_mode);
    try std.testing.expectEqual(WritingMode.vertical_lr, cache.entries.items[1].key.plan.writing_mode);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.runs[0].y_offset, 0.001);
}

test "vertical column progression does not imply bottom-to-top mirroring" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(std.testing.allocator, &.{
        0x3008,
        0x3009,
        0xfe3f,
        0xfe40,
    });
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const rl = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    const rl_glyph = rl.glyphs[0].glyph_id;
    const lr = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectEqual(rl_glyph, lr.glyphs[0].glyph_id);

    const btt = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{
            .direction = .rtl,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    try std.testing.expect(rl_glyph != btt.glyphs[0].glyph_id);
}
