//! Integration coverage migrated from the former package root.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const OpenTypeScriptTag = support.OpenTypeScriptTag;
const Font = support.Font;
const testing = support.testing;

test "applies GPOS pair positioning during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), run.glyphs[1].y_offset, 0.001);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "empty GSUB topology does not suppress independent GPOS shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildEmptyGsubGposTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const selection = try font_shaping.selectGsubScriptForShaping(&font, .latin, null);
    try std.testing.expectEqual(@as(?OpenTypeScriptTag, null), selection.tag);
    try std.testing.expect(!selection.requested);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    // The null GSUB lists are inert, but GPOS still owns the normal PairPos
    // result. This protects the table-plan boundary that the Unicode GPOS-4
    // fixture exercises rather than only testing the low-level GSUB parser.
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), run.glyphs[1].y_offset, 0.001);
}

test "prefers GPOS pair positioning over legacy kern for same pair" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGposAndKernTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), run.width(), 0.001);
}

test "AAT kerx format 0 positioning takes precedence over legacy kern" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    // kerx contributes -30 for (glyph 1, glyph 1). The coexisting legacy kern
    // contributes -100 for the same pair and must not run after kerx.
    try std.testing.expectApproxEqAbs(@as(f32, 1570), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -15), run.glyphs[1].x_offset, 0.001);

    layout_buffer.clear();
    const disabled = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "AA", 1000, .{
        .features = &.{.{ .tag = @import("../../../unicode.zig").tag("kern"), .enabled = false }},
    });
    try std.testing.expectApproxEqAbs(@as(f32, 1600), disabled.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), disabled.glyphs[1].x_offset, 0.001);
}

test "AAT kerx format 1 state positioning takes precedence over legacy kern" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxFormat1Ttf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1570), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 770), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -30), run.glyphs[0].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), run.glyphs[1].x_offset, 0.001);
}

test "AAT kerx format 2 class positioning takes precedence over legacy kern" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxFormat2Ttf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1570), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -15), run.glyphs[1].x_offset, 0.001);
}

test "AAT kerx format 4 coordinate attachment offsets the current glyph" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxFormat4Ttf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1600), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[1].x_advance, 0.001);
    // Coordinate action: (mark 10,20) - (current 40,-5).
    try std.testing.expectApproxEqAbs(@as(f32, -830), run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25), run.glyphs[1].y_offset, 0.001);
}

test "AAT kerx format 4 resolves ankr-indexed attachment points" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxFormat4AnkrTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1600), run.width(), 0.001);
    // Both glyphs select anchor 0=(100,-50), so the local anchor delta is zero;
    // propagation still pulls the attached glyph back by its parent advance.
    try std.testing.expectApproxEqAbs(@as(f32, -800), run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), run.glyphs[1].y_offset, 0.001);
}

test "AAT kerx format 6 sparse positioning takes precedence over legacy kern" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildKerxFormat6Ttf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 1000);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1570), run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 785), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -15), run.glyphs[1].x_offset, 0.001);
}

test "AAT kerx simple cross-stream formats position the minor axis" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    for ([_]u8{ 0, 2, 6 }) |format| {
        const horizontal_bytes = try test_font.buildKerxCrossStreamTtf(allocator, format, false);
        defer allocator.free(horizontal_bytes);
        var horizontal_font = try Font.parse(allocator, horizontal_bytes);
        defer horizontal_font.deinit();

        var layout_buffer = LayoutBuffer.init(allocator);
        defer layout_buffer.deinit();
        const horizontal = try TextShaper.shapeUtf8(&horizontal_font, &layout_buffer, "AAA", 1000);

        try std.testing.expectEqual(@as(usize, 3), horizontal.glyphs.len);
        try std.testing.expectApproxEqAbs(@as(f32, 2400), horizontal.width(), 0.001);
        for (horizontal.glyphs) |glyph| {
            try std.testing.expectApproxEqAbs(@as(f32, 800), glyph.x_advance, 0.001);
        }
        try std.testing.expectApproxEqAbs(@as(f32, 0), horizontal.glyphs[0].y_offset, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, -30), horizontal.glyphs[1].y_offset, 0.001);
        // Cross-stream subtables cursively chain the run, so the third glyph
        // accumulates the second pair's assignment through its parent.
        try std.testing.expectApproxEqAbs(@as(f32, -60), horizontal.glyphs[2].y_offset, 0.001);

        const vertical_bytes = try test_font.buildKerxCrossStreamTtf(allocator, format, true);
        defer allocator.free(vertical_bytes);
        var vertical_font = try Font.parse(allocator, vertical_bytes);
        defer vertical_font.deinit();

        layout_buffer.clear();
        const vertical = try TextShaper.shapeUtf8WithOptions(&vertical_font, &layout_buffer, "AAA", 1000, .{
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
            // HarfBuzz does not enable `vkrn` by default; an explicit request
            // is required to exercise simple vertical kerx subtables.
            .features = &.{.{ .tag = @import("../../../unicode.zig").tag("vkrn"), .enabled = true }},
        });

        try std.testing.expectEqual(@as(usize, 3), vertical.glyphs.len);
        for (vertical.glyphs) |glyph| {
            try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 1000), glyph.y_advance, 0.001);
        }
        try std.testing.expectApproxEqAbs(@as(f32, -400), vertical.glyphs[0].x_offset, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, -430), vertical.glyphs[1].x_offset, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, -460), vertical.glyphs[2].x_offset, 0.001);
    }
}

test "AAT kerx format 1 cross-stream actions accumulate and reset offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const horizontal_bytes = try test_font.buildKerxFormat1CrossStreamTtf(allocator, false, false);
    defer allocator.free(horizontal_bytes);
    var horizontal_font = try Font.parse(allocator, horizontal_bytes);
    defer horizontal_font.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const horizontal = try TextShaper.shapeUtf8(&horizontal_font, &layout_buffer, "AA", 1000);
    try std.testing.expectEqual(@as(usize, 2), horizontal.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 800), horizontal.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), horizontal.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -30), horizontal.glyphs[0].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -30), horizontal.glyphs[1].y_offset, 0.001);

    layout_buffer.clear();
    const disabled_horizontal = try TextShaper.shapeUtf8WithOptions(&horizontal_font, &layout_buffer, "AA", 1000, .{
        .features = &.{.{ .tag = @import("../../../unicode.zig").tag("kern"), .enabled = false }},
    });
    // Cross-stream format 1 remains active when ordinary pair kerning is
    // disabled, matching HarfBuzz's separate `requested_kerning || cross`
    // applicability rule.
    try std.testing.expectApproxEqAbs(@as(f32, -30), disabled_horizontal.glyphs[0].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -30), disabled_horizontal.glyphs[1].y_offset, 0.001);

    const reset_bytes = try test_font.buildKerxFormat1CrossStreamTtf(allocator, false, true);
    defer allocator.free(reset_bytes);
    var reset_font = try Font.parse(allocator, reset_bytes);
    defer reset_font.deinit();
    layout_buffer.clear();
    const reset = try TextShaper.shapeUtf8(&reset_font, &layout_buffer, "AA", 1000);
    try std.testing.expectApproxEqAbs(@as(f32, 0), reset.glyphs[0].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), reset.glyphs[1].y_offset, 0.001);

    const vertical_bytes = try test_font.buildKerxFormat1CrossStreamTtf(allocator, true, false);
    defer allocator.free(vertical_bytes);
    var vertical_font = try Font.parse(allocator, vertical_bytes);
    defer vertical_font.deinit();
    layout_buffer.clear();
    const vertical = try TextShaper.shapeUtf8WithOptions(&vertical_font, &layout_buffer, "AA", 1000, .{
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .features = &.{.{ .tag = @import("../../../unicode.zig").tag("vkrn"), .enabled = true }},
    });
    try std.testing.expectEqual(@as(usize, 2), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, -430), vertical.glyphs[0].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -830), vertical.glyphs[1].x_offset, 0.001);
}

test "AAT kerx selection yields to GPOS only with GSUB" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const with_kern_bytes = try test_font.buildKerxGsubGposTtf(allocator, "kern");
    defer allocator.free(with_kern_bytes);
    var with_kern = try Font.parse(allocator, with_kern_bytes);
    defer with_kern.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const gpos_run = try TextShaper.shapeUtf8(&with_kern, &layout_buffer, "AA", 1000);
    // The active GSUB+GPOS-kern plan owns positioning, so its -50 PairPos
    // applies and both AAT kerx (-30) and legacy kern (-100) stay suppressed.
    try std.testing.expectApproxEqAbs(@as(f32, 1550), gpos_run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 750), gpos_run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), gpos_run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), gpos_run.glyphs[1].x_offset, 0.001);

    const without_kern_bytes = try test_font.buildKerxGsubGposTtf(allocator, "mark");
    defer allocator.free(without_kern_bytes);
    var without_kern = try Font.parse(allocator, without_kern_bytes);
    defer without_kern.deinit();

    layout_buffer.clear();
    const gpos_without_kern_run = try TextShaper.shapeUtf8(&without_kern, &layout_buffer, "AA", 1000);
    // HarfBuzz chooses the GPOS engine at table-plan level whenever GSUB and
    // GPOS are both active. The selected feature tag controls which lookups
    // GPOS runs, but does not switch the engine back to kerx.
    try std.testing.expectApproxEqAbs(@as(f32, 1550), gpos_without_kern_run.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 750), gpos_without_kern_run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 800), gpos_without_kern_run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), gpos_without_kern_run.glyphs[1].x_offset, 0.001);
}
