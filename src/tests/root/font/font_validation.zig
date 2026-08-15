//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const FontFallbackCache = support.FontFallbackCache;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const FeatureOverride = support.FeatureOverride;
const Font = support.Font;
const GlyphId = support.GlyphId;
const FontCascade = support.FontCascade;
const openTypeTag = support.openTypeTag;
const testing = support.testing;

test "shapes cmap format 14 variation selectors as base glyph variants" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A\u{fe0f}B", 20);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 'A'), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(GlyphId, 2), run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(u21, 'B'), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 4), run.glyphs[1].cluster);
}

test "shaping rejects malformed UTF-8 without clearing existing glyphs" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);
    try std.testing.expectError(error.InvalidUtf8, TextShaper.shapeUtf8(&font, &layout_buffer, "\xf0\x28\x8c\x28", 20));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);
}

test "public shaping APIs reject invalid font sizes before mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), valid.width(), 0.001);

    // Invalid sizes would otherwise become NaN/Inf/negative advances and cache
    // keys. Public entry points reject them before clearing the caller's last
    // good layout or touching fallback/shaped-run caches.
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", 0));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", std.math.inf(f32)));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8(&font, &layout_buffer, "A", std.math.nan(f32)));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);

    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;
    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", -1, .{}));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    try std.testing.expectError(error.InvalidFontSize, TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "A", 0, .{}));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A", -20, .{ .max_width = 100 }));
    try std.testing.expectError(error.InvalidFontSize, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "A", std.math.inf(f32), .{ .max_width = 100 }));
}

test "public shaping APIs reject malformed feature overrides before mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);

    const invalid_feature = [_]FeatureOverride{.{ .tag = 0x6c696700, .enabled = true }};
    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "A", 20, .{ .features = &invalid_feature }));
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);

    const duplicate_features = [_]FeatureOverride{
        .{ .tag = openTypeTag("liga"), .enabled = true },
        .{ .tag = openTypeTag("liga"), .enabled = false },
    };
    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;
    try std.testing.expectError(error.DuplicateFeatureTag, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .features = &duplicate_features }));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.shapeUtf8ScriptRuns(cascade, &layout_buffer, "A", 20, .{ .features = &invalid_feature }));
}

test "paragraph layout rejects non-finite options before shaping mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const valid = try TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{ .max_width = 100 });
    try std.testing.expectEqual(@as(usize, 1), valid.glyphs.len);

    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;

    // These geometry knobs are applied after shaping. Validate them first so a
    // rejected paragraph call cannot clear the previous layout or populate
    // caches with text that never produced valid line metrics.
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .line_height = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8WithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "AA", 20, .{
        .max_width = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .letter_spacing = std.math.inf(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .word_spacing = -std.math.inf(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .first_line_indent = std.math.nan(f32),
    }));
    try std.testing.expectError(error.InvalidParagraphOptions, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A\nA", 20, .{
        .max_width = 100,
        .paragraph_spacing = std.math.inf(f32),
    }));
    try std.testing.expectError(error.InvalidFeatureTag, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{
        .max_width = 100,
        .features = &.{.{ .tag = 0, .enabled = true }},
    }));

    try std.testing.expectEqual(@as(usize, 1), layout_buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(usize, 1), layout_buffer.lines.items.len);
    try std.testing.expectEqual(@as(GlyphId, 1), layout_buffer.glyphs.items[0].glyph_id);
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);

    // Infinite max_width remains a valid way to request unbounded paragraph
    // layout; only NaN/non-finite secondary geometry is rejected.
    _ = try TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "AA", 20, .{ .max_width = std.math.inf(f32) });
}

test "cascade and paragraph shaping reject malformed UTF-8 before cache mutation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var shaped_cache = ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const shaped = try TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "A", 20, .{});
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs.len);
    const fallback_hits = fallback_cache.hits;
    const fallback_misses = fallback_cache.misses;
    const shaped_hits = shaped_cache.hits;
    const shaped_misses = shaped_cache.misses;

    // Public UTF-8 APIs must reject malformed bytes before std.unicode.Utf8Iterator
    // can hit its unreachable path, and before malformed text enters caches.
    try std.testing.expectError(error.InvalidUtf8, TextShaper.shapeUtf8CascadeWithCaches(cascade, &fallback_cache, null, null, &shaped_cache, &layout_buffer, "\xc3\x28", 20, .{}));
    try std.testing.expectEqual(fallback_hits, fallback_cache.hits);
    try std.testing.expectEqual(fallback_misses, fallback_cache.misses);
    try std.testing.expectEqual(shaped_hits, shaped_cache.hits);
    try std.testing.expectEqual(shaped_misses, shaped_cache.misses);
    try std.testing.expectError(error.InvalidUtf8, TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "\xe2\x82", 20, .{ .max_width = 100 }));
    try std.testing.expectError(error.InvalidUtf8, TextShaper.measureParagraphUtf8(cascade, &layout_buffer, "\x80", 20, .{ .max_width = 100 }));
}

test "cascade shaping keeps variation selectors with fallback base font" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'C', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A\u{fe0f}C", 20);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), shaped.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(GlyphId, 1), shaped.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 4), shaped.glyphs[1].cluster);
}

test "cascade fallback prefers fonts with variation selector records" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const variant_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(variant_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var variant = try Font.parse(allocator, variant_bytes);
    defer variant.deinit();

    const fonts = [_]*const Font{ &primary, &variant };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const base = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), base.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), base.runs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 1), base.glyphs[0].glyph_id);

    const varied = try TextShaper.shapeUtf8Cascade(FontCascade.init(&fonts), &layout_buffer, "A\u{fe0f}", 20);
    try std.testing.expectEqual(@as(usize, 1), varied.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), varied.runs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 3), varied.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 0), varied.glyphs[0].cluster);
}
