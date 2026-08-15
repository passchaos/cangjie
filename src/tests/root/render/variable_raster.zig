//! Integration coverage migrated from the former package root.

const std = @import("std");
const font_raster = @import("../../../font.zig").raster_backend;
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const FeatureOverride = support.FeatureOverride;
const Font = support.Font;
const CharmapMapping = support.CharmapMapping;
const FontFormat = support.FontFormat;
const FontTableInfo = support.FontTableInfo;
const HorizontalMetricInfo = support.HorizontalMetricInfo;
const VerticalMetricInfo = support.VerticalMetricInfo;
const VerticalOriginMetric = support.VerticalOriginMetric;
const GlyphId = support.GlyphId;
const Bounds = support.Bounds;
const initGlyphRun = @import("../../../layout/types/runs.zig").initGlyphRun;
const GlyphPosition = support.GlyphPosition;
const openTypeTag = support.openTypeTag;
const ColorRenderTarget = support.ColorRenderTarget;
const RenderTarget = support.RenderTarget;
const Rasterizer = support.Rasterizer;
const testing = support.testing;
const renderTargetPixelDifference = support.renderTargetPixelDifference;
const colorRenderTargetPixelDifference = support.colorRenderTargetPixelDifference;
const writeU16Test = support.writeU16Test;

test "rasterizer renders variable outlines at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const glyphs = [_]GlyphPosition{.{
        .glyph_id = 2,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 1,
        .x_advance = 200,
    }};
    const run = initGlyphRun(&font, 200, &glyphs);

    var default_target = try RenderTarget.init(allocator, 220, 220);
    defer default_target.deinit();
    var varied_target = try RenderTarget.init(allocator, 220, 220);
    defer varied_target.deinit();

    var rasterizer = Rasterizer.init(allocator);
    rasterizer.hint_size_px = 200;
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderRun(&default_target, run, 20, 180);
    try rasterizer.renderRunAtCoords(&varied_target, run, 20, 180, &.{0.5});

    try std.testing.expect(renderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "color rasterizer renders variable outlines at normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_target = try ColorRenderTarget.init(allocator, 220, 220);
    defer default_target.deinit();
    var varied_target = try ColorRenderTarget.init(allocator, 220, 220);
    defer varied_target.deinit();

    var rasterizer = Rasterizer.init(allocator);
    rasterizer.hint_size_px = 200;
    rasterizer.embolden_small_glyphs = false;
    try rasterizer.renderColorGlyph(&default_target, &font, 2, 200, 20, 180, 0);
    try rasterizer.renderColorGlyphAtCoords(&varied_target, &font, 2, 200, 20, 180, 0, &.{0.5});

    try std.testing.expect(colorRenderTargetPixelDifference(&default_target, &varied_target) > 0);
}

test "lazy gvar metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.gvarInfo()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.gvarInfo());
}

test "generic glyph at-coords APIs validate coordinates and fall back" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const bounds = try font.glyphBoundsAtCoords(1, &.{0.5});
    try std.testing.expectEqual(@as(i16, 0), bounds.x_min);
    var outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expect(outline.commands.items.len != 0);
    try std.testing.expectError(error.BadSfnt, font.glyphBoundsAtCoords(1, &.{std.math.nan(f32)}));
    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{1.0001}));
}

test "lazy CFF2 metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.cff2Info()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_offset = table.offset;
    }
    bytes[cff2_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.cff2Info());
}

test "CFF2 raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    // Mutate a trailing CFF2 byte that invalidates the table checksum without
    // touching the already-validated CharStrings/FD data used by the parsed-font
    // raster fast path.
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 0));
    var outline = try font_raster.glyphOutline(&font, allocator, 0);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), outline.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), outline.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.y_max);
}

test "CFF2 variation raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 0, &.{0.5}));
    var outline = try font_raster.glyphOutlineAtCoords(&font, allocator, 0, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 60), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), outline.bounds.x_max);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), outline.commands.items[1].line_to.x);
}

test "CFF2 default variation raster outline skips variation table reread" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var cff2_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "CFF2")) cff2_tail = table.offset + table.length - 1;
    }
    bytes[cff2_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 0, &.{0.5}));
    var outline = try font_raster.glyphOutlineAtCoords(&font, allocator, 0, &.{0.0});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 60), outline.bounds.x_max);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[1].line_to.x);
}

test "gvar raster outline uses parsed-font fast path" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font_raster.glyphOutlineAtCoords(&font, allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 5), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 5), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 809), outline.advance_width);
}

test "gvar default raster outline skips gvar reread" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gvar_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gvar")) gvar_tail = table.offset + table.length - 1;
    }
    bytes[gvar_tail orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font_raster.glyphOutlineAtCoords(&font, allocator, 1, &.{0.0});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 0), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 0), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 800), outline.advance_width);
}

test "gvar raster outline reuses parsed fvar axis count" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var fvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "fvar")) fvar_offset = table.offset;
    }

    // The parsed-font raster path should not re-read the fvar header on every
    // glyph. Mutating axisCount after parse makes defensive public APIs reject
    // the now-inconsistent borrowed bytes, while the raster fast path continues
    // to use the parse-time axis count paired with the already-validated gvar.
    writeU16Test(bytes, (fvar_offset orelse return error.MissingTable) + 8, 2);

    try std.testing.expectError(error.BadSfnt, font.glyphOutlineAtCoords(allocator, 1, &.{0.5}));
    var outline = try font_raster.glyphOutlineAtCoords(&font, allocator, 1, &.{0.5});
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 5), outline.bounds.x_min);
    try std.testing.expectEqual(@as(f32, 5), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(u16, 809), outline.advance_width);
}
