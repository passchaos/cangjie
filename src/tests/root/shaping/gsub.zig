//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const FeatureOverride = support.FeatureOverride;
const GsubFeatureRange = support.GsubFeatureRange;
const Font = support.Font;
const GlyphId = support.GlyphId;
const openTypeTag = support.openTypeTag;
const testing = support.testing;

test "applies GSUB ligature substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs[0].source_byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), run.width(), 0.001);
}

test "applies GSUB multiple substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMultipleGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
}

test "applies GSUB alternate substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildAlternateGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
}

test "applies GSUB feature values by UTF-8 source byte range" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildScriptFeatureGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const enable_alternate = [_]GsubFeatureRange{.{
        .tag = openTypeTag("sups"),
        .value = 1,
        .byte_start = 1,
        .byte_end = 3,
    }};
    const run = try TextShaper.shapeUtf8WithGsubFeatureRanges(
        &font,
        &layout_buffer,
        "AAA",
        20,
        &enable_alternate,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 1, 2, 2 },
        &.{
            run.glyphs[0].glyph_id,
            run.glyphs[1].glyph_id,
            run.glyphs[2].glyph_id,
        },
    );

    const overlapping = [_]GsubFeatureRange{
        .{ .tag = openTypeTag("sups"), .value = 1, .byte_start = 0, .byte_end = 3 },
        .{ .tag = openTypeTag("sups"), .value = 0, .byte_start = 1, .byte_end = 2 },
    };
    const later_wins = try TextShaper.shapeUtf8WithGsubFeatureRanges(
        &font,
        &layout_buffer,
        "AAA",
        20,
        &overlapping,
        .{},
    );
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 2, 1, 2 },
        &.{
            later_wins.glyphs[0].glyph_id,
            later_wins.glyphs[1].glyph_id,
            later_wins.glyphs[2].glyph_id,
        },
    );
}

test "rejects invalid or stage-specific GSUB feature ranges" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildAlternateGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    try std.testing.expectError(
        error.InvalidFeatureRange,
        TextShaper.shapeUtf8WithGsubFeatureRanges(
            &font,
            &layout_buffer,
            "\u{00e9}",
            20,
            &.{.{
                .tag = openTypeTag("test"),
                .value = 1,
                .byte_start = 1,
                .byte_end = 2,
            }},
            .{},
        ),
    );
    try std.testing.expectError(
        error.UnsupportedFeatureRanges,
        TextShaper.shapeUtf8WithGsubFeatureRanges(
            &font,
            &layout_buffer,
            "A",
            20,
            &.{.{
                .tag = openTypeTag("rand"),
                .value = 1,
                .byte_start = 0,
                .byte_end = 1,
            }},
            .{},
        ),
    );
}

test "applies GSUB extension substitution during shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildExtensionGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);
}

test "applies only GSUB lookups referenced by active features" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildSelectiveGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[0].glyph_id);

    const disabled = [_]FeatureOverride{.{ .tag = openTypeTag("liga"), .enabled = false }};
    const unligated = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "AA", 20, .{ .features = &disabled });
    try std.testing.expectEqual(@as(usize, 2), unligated.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), unligated.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), unligated.glyphs[1].glyph_id);
}

test "applies optional GSUB superscript and subscript features when enabled" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildScriptFeatureGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const plain = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), plain.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), plain.glyphs[0].glyph_id);

    const enable_sups = [_]FeatureOverride{.{ .tag = openTypeTag("sups"), .enabled = true }};
    const superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &enable_sups });
    try std.testing.expectEqual(@as(usize, 1), superscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), superscript.glyphs[0].glyph_id);

    const enable_subs = [_]FeatureOverride{.{ .tag = openTypeTag("subs"), .enabled = true }};
    const subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &enable_subs });
    try std.testing.expectEqual(@as(usize, 1), subscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), subscript.glyphs[0].glyph_id);

    const preset_superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .superscript });
    try std.testing.expectEqual(@as(usize, 1), preset_superscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), preset_superscript.glyphs[0].glyph_id);

    const preset_subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .subscript });
    try std.testing.expectEqual(@as(usize, 1), preset_subscript.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), preset_subscript.glyphs[0].glyph_id);
}

test "script feature visual test font gives substitute glyphs outlines" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildScriptFeatureGsubVisualTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const normal = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    const normal_id = normal.glyphs[0].glyph_id;
    const superscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .superscript });
    const superscript_id = superscript.glyphs[0].glyph_id;
    const subscript = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .script_position = .subscript });
    const subscript_id = subscript.glyphs[0].glyph_id;
    try std.testing.expectEqual(@as(GlyphId, 1), normal_id);
    try std.testing.expectEqual(@as(GlyphId, 2), superscript_id);
    try std.testing.expectEqual(@as(GlyphId, 3), subscript_id);

    var normal_outline = try font.glyphOutline(allocator, 1);
    defer normal_outline.deinit();
    var superscript_outline = try font.glyphOutline(allocator, 2);
    defer superscript_outline.deinit();
    var subscript_outline = try font.glyphOutline(allocator, 3);
    defer subscript_outline.deinit();

    try std.testing.expect(normal_outline.commands.items.len >= 4);
    try std.testing.expect(superscript_outline.commands.items.len >= 4);
    try std.testing.expect(subscript_outline.commands.items.len >= 4);
    const normal_second_x = switch (normal_outline.commands.items[1]) {
        .line_to => |point| point.x,
        else => return error.UnexpectedOutlineCommand,
    };
    const superscript_second_x = switch (superscript_outline.commands.items[1]) {
        .line_to => |point| point.x,
        else => return error.UnexpectedOutlineCommand,
    };
    const normal_peak_y = switch (normal_outline.commands.items[2]) {
        .line_to => |point| point.y,
        else => return error.UnexpectedOutlineCommand,
    };
    const subscript_peak_y = switch (subscript_outline.commands.items[2]) {
        .line_to => |point| point.y,
        else => return error.UnexpectedOutlineCommand,
    };
    try std.testing.expect(superscript_second_x < normal_second_x);
    try std.testing.expect(subscript_peak_y < normal_peak_y);
}

test "applies GSUB contextual substitution with nested lookup" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildContextGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GSUB coverage-based contextual substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildContextFormat3GsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GSUB class-based contextual substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildContextClassGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[1].glyph_id);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
}

test "applies GSUB chaining contextual substitution with nested lookup" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildChainingGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AAA", 20);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[2].glyph_id);
    try std.testing.expect(!run.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[1].isUnsafeToBreakBefore());
    try std.testing.expect(run.glyphs[2].isUnsafeToBreakBefore());
}

test "applies GSUB reverse chaining single substitution" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildReverseChainingGsubTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[1].glyph_id);
}
