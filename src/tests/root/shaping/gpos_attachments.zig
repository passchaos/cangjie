//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphId = support.GlyphId;
const testing = support.testing;

test "applies GPOS single positioning offsets during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_offset, 0.001);
}

test "applies GPOS extension positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildExtensionGposTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_offset, 0.001);
}

test "applies GPOS class pair positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposClassTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
}

test "applies GPOS mark-to-base positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GPOS mark anchors with contour and device formats" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGposMarkAnchorFormatsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS mark-to-base positioning across intervening marks" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[2].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[0].x_advance + run.glyphs[2].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[1].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), run.glyphs[2].y_offset, 0.001);
}

test "applies GPOS mark-to-mark positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkToMarkTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), run.glyphs[1].y_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GPOS cursive positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposCursiveTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), run.glyphs[1].y_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GPOS mark-to-ligature positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposMarkToLigatureTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.4), run.glyphs[1].y_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "passes GSUB ligature component sources into GPOS mark-to-ligature shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGsubGposMarkToLigatureComponentsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), run.glyphs[0].x_advance + run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.4), run.glyphs[1].y_offset, 0.001);
}

test "applies GPOS coverage-based contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposContextTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GPOS chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[2].isUnsafeToBreakBefore());
}

test "applies GPOS glyph-based chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposGlyphChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[2].isUnsafeToBreakBefore());
}

test "applies GPOS class-based chaining contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposClassChainingTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[2].isUnsafeToBreakBefore());
}

test "applies GPOS glyph-based contextual positioning" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposGlyphContextTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), run.glyphs[1].x_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}
