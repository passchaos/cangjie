//! Font fallback, UVS, and normalization integration coverage.

const std = @import("std");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const FontFallbackCache = support.FontFallbackCache;
const GlyphId = support.GlyphId;
const GlyphIndexCache = support.GlyphIndexCache;
const GlyphPosition = support.GlyphPosition;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const diagnoseFontFallbackUtf8 = support.diagnoseFontFallbackUtf8;
const fallbackGlyphIndexWithOptionalCache =
    @import("../../../shaping/pipeline/source/root.zig").fallbackGlyphIndex;

const ExpectedGlyphOutput = struct {
    glyph_id: GlyphId,
    codepoint: u21,
    cluster: usize,
    source_byte_len: usize,
    x_advance: f32,
    x_offset: f32 = 0,
    y_offset: f32 = 0,
    unsafe_to_break_before: bool = false,
};

fn expectGlyphOutput(expected: ExpectedGlyphOutput, glyph: GlyphPosition) !void {
    try std.testing.expectEqual(expected.glyph_id, glyph.glyph_id);
    try std.testing.expectEqual(@as(?u32, null), glyph.synthetic_glyph_id);
    try std.testing.expectEqual(expected.codepoint, glyph.codepoint);
    try std.testing.expectEqual(expected.cluster, glyph.cluster);
    try std.testing.expectEqual(expected.source_byte_len, glyph.source_byte_len);
    try std.testing.expectApproxEqAbs(expected.x_advance, glyph.x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.y_advance, 0.001);
    try std.testing.expectApproxEqAbs(expected.x_offset, glyph.x_offset, 0.001);
    try std.testing.expectApproxEqAbs(expected.y_offset, glyph.y_offset, 0.001);
    try std.testing.expectEqual(.horizontal, glyph.orientation);
    try std.testing.expectEqual(
        expected.unsafe_to_break_before,
        glyph.flags.unsafe_to_break_before,
    );
    try std.testing.expect(!glyph.flags.discretionary_hyphen);
    try std.testing.expect(!glyph.flags.inline_object);
    try std.testing.expect(!glyph.flags.automatic_hyphen);
    try std.testing.expect(!glyph.flags.safe_to_insert_tatweel);
    try std.testing.expect(!glyph.flags.kashida);
    try std.testing.expect(!glyph.flags.tab);
    try std.testing.expect(!glyph.flags.collapsed_whitespace);
}

fn expectGlyphOutputs(
    expected: []const ExpectedGlyphOutput,
    glyphs: []const GlyphPosition,
) !void {
    try std.testing.expectEqual(expected.len, glyphs.len);
    for (expected, glyphs) |expected_glyph, glyph| {
        try expectGlyphOutput(expected_glyph, glyph);
    }
}

test "mapped spaces use the glyph index cache before fallback" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildSingleCodepointTtf(allocator, ' ');
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, ' '));
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    const cmap = for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "cmap")) break table;
    } else return error.TestUnexpectedResult;
    bytes[cmap.offset + cmap.length - 1] ^= 1;

    // Public cmap lookup remains deliberately defensive for borrowed bytes.
    // The explicit cache, however, is the caller's immutable-font proof and
    // must serve ordinary U+0020 just like every other cached codepoint.
    try std.testing.expectError(error.BadSfnt, font.glyphIndex(' '));
    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, ' '));
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);
}

test "missing Unicode spaces still fall back to the cached ASCII space" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildSingleCodepointTtf(allocator, ' ');
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(allocator);
    defer cache.deinit();

    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, 0x2002));
    try std.testing.expectEqual(@as(usize, 2), cache.misses);
    try std.testing.expectEqual(@as(GlyphId, 1), try fallbackGlyphIndexWithOptionalCache(&font, &cache, 0x2002));
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 2), cache.misses);
}

test "font fallback diagnostics expose deterministic variation and missing glyph decisions" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const variant_bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(variant_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var variant = try Font.parse(allocator, variant_bytes);
    defer variant.deinit();

    const fonts = [_]*const Font{ &primary, &variant };
    const cascade = FontCascade.init(&fonts);

    const text = "A\u{fe0f}B\u{fe0e}C";
    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, text);
    defer allocator.free(decisions);

    try std.testing.expectEqual(@as(usize, 3), decisions.len);

    try std.testing.expectEqual(@as(usize, 0), decisions[0].byte_start);
    try std.testing.expectEqual(@as(usize, 4), decisions[0].byte_len);
    try std.testing.expectEqual(@as(u21, 'A'), decisions[0].codepoint);
    try std.testing.expectEqual(@as(?u21, 0xfe0f), decisions[0].variation_selector);
    try std.testing.expectEqual(@as(usize, 1), decisions[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 3), decisions[0].glyph_id);
    try std.testing.expect(decisions[0].used_variation_mapping);
    try std.testing.expect(!decisions[0].missingGlyph());

    try std.testing.expectEqual(@as(usize, 4), decisions[1].byte_start);
    try std.testing.expectEqual(@as(usize, 4), decisions[1].byte_len);
    try std.testing.expectEqual(@as(u21, 'B'), decisions[1].codepoint);
    try std.testing.expectEqual(@as(?u21, 0xfe0e), decisions[1].variation_selector);
    try std.testing.expectEqual(@as(usize, 1), decisions[1].font_index);
    try std.testing.expectEqual(@as(GlyphId, 2), decisions[1].glyph_id);
    try std.testing.expect(!decisions[1].used_variation_mapping);

    try std.testing.expectEqual(@as(usize, 8), decisions[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), decisions[2].byte_len);
    try std.testing.expectEqual(@as(u21, 'C'), decisions[2].codepoint);
    try std.testing.expectEqual(@as(?u21, null), decisions[2].variation_selector);
    try std.testing.expectEqual(@as(usize, 0), decisions[2].font_index);
    try std.testing.expectEqual(@as(GlyphId, 0), decisions[2].glyph_id);
    try std.testing.expect(decisions[2].missingGlyph());

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, text, 20);
    try std.testing.expectEqual(decisions.len, shaped.glyphs.len);
    for (decisions, shaped.glyphs) |decision, glyph| {
        try std.testing.expectEqual(decision.byte_start, glyph.cluster);
        try std.testing.expectEqual(decision.byte_len, glyph.source_byte_len);
        try std.testing.expectEqual(decision.codepoint, glyph.codepoint);
        try std.testing.expectEqual(decision.glyph_id, glyph.glyph_id);
    }
}

test "font fallback keeps combining graphemes in a fully covering font" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 'A', 'B', 0x0301 });
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster("A\u{0301}"));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, "A\u{0301}B", 20);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 3), shaped.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, "A\u{0301}".len), shaped.glyphs[2].cluster);
    try std.testing.expect(shaped.glyphs[1].glyph_id != 0);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, "A\u{0301}B");
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 3), decisions.len);
    for (decisions) |decision| try std.testing.expectEqual(@as(usize, 1), decision.font_index);
    try std.testing.expect(!decisions[0].missingGlyph());
    try std.testing.expect(!decisions[1].missingGlyph());

    var fallback_cache = FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    var glyph_cache = GlyphIndexCache.init(allocator);
    defer glyph_cache.deinit();
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontForCluster(cascade, &glyph_cache, "A\u{0301}"));
    try std.testing.expectEqual(@as(usize, 1), try fallback_cache.selectFontForCluster(cascade, &glyph_cache, "A\u{0301}"));
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), fallback_cache.misses);
}

test "fallback mark output preserves ASCII and consecutive mark semantics" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildFallbackMarkTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const ascii = try TextShaper.shapeUtf8(&font, &buffer, "Xx", 20);
    try expectGlyphOutputs(&.{
        .{ .glyph_id = 1, .codepoint = 'X', .cluster = 0, .source_byte_len = 1, .x_advance = 16 },
        .{ .glyph_id = 2, .codepoint = 'x', .cluster = 1, .source_byte_len = 1, .x_advance = 16 },
    }, ascii.glyphs);

    const marked = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "x\u{0301}\u{0301}",
        20,
        .{ .cluster_level = .monotone_characters },
    );
    try expectGlyphOutputs(&.{
        .{ .glyph_id = 2, .codepoint = 'x', .cluster = 0, .source_byte_len = 1, .x_advance = 16 },
        .{ .glyph_id = 3, .codepoint = 0x0301, .cluster = 1, .source_byte_len = 2, .x_advance = 0, .x_offset = -8, .y_offset = 1.24, .unsafe_to_break_before = true },
        .{ .glyph_id = 3, .codepoint = 0x0301, .cluster = 3, .source_byte_len = 2, .x_advance = 0, .x_offset = -8, .y_offset = 2.48, .unsafe_to_break_before = true },
    }, marked.glyphs);
}

test "script itemization does not split a grapheme before fallback" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const text = "A\u{0951}";

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 'A', 0x0951 },
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const cascade = FontCascade.init(&.{ &primary, &fallback });
    try std.testing.expectEqual(
        @as(usize, 1),
        try cascade.selectFontForCluster(text),
    );
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, text, 20);

    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expect(shaped.glyphs[0].glyph_id != 0);
    try std.testing.expect(shaped.glyphs[1].glyph_id != 0);
    try std.testing.expectEqual(@as(usize, 0), shaped.glyphs[0].cluster);
    // The default public cluster policy may preserve the mark's scalar byte
    // offset; font ownership, not output cluster coalescing, is the invariant
    // guarded here.
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs[1].cluster);
}

test "Arabic normalization composes base mark pairs when the font has the precomposed glyph" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const composed_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0622});
    defer allocator.free(composed_bytes);
    var composed_font = try Font.parse(allocator, composed_bytes);
    defer composed_font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8WithOptions(
        &composed_font,
        &buffer,
        "آ",
        20,
        .{ .direction = .rtl, .script_tag = .arab },
    );

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x0622), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, "آ".len), run.glyphs[0].source_byte_len);

    const decomposed_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 0x0627, 0x0653 });
    defer allocator.free(decomposed_bytes);
    var decomposed_font = try Font.parse(allocator, decomposed_bytes);
    defer decomposed_font.deinit();
    const decomposed_run = try TextShaper.shapeUtf8WithOptions(
        &decomposed_font,
        &buffer,
        "آ",
        20,
        .{ .direction = .rtl, .script_tag = .arab },
    );

    try std.testing.expectEqual(@as(usize, 2), decomposed_run.glyphs.len);
    var saw_alef = false;
    var saw_maddah = false;
    for (decomposed_run.glyphs) |glyph| {
        saw_alef = saw_alef or glyph.codepoint == 0x0627;
        saw_maddah = saw_maddah or glyph.codepoint == 0x0653;
    }
    try std.testing.expect(saw_alef);
    try std.testing.expect(saw_maddah);
}

test "missing precomposed Latin uses the shortest supported canonical decomposition" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    // U+1EA4 decomposes directly to U+00C2 U+0301, while recursive NFD is
    // U+0041 U+0302 U+0301. Omitting A and circumflex proves the normalizer
    // accepts the direct chain instead of requiring every NFD component.
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x006e, 0x00c2, 0x0301 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &buffer, "Ấn", 1000);

    try std.testing.expectEqual(@as(usize, 3), run.glyphs.len);
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 2, 3, 1 },
        &.{
            run.glyphs[0].glyph_id,
            run.glyphs[1].glyph_id,
            run.glyphs[2].glyph_id,
        },
    );
    try std.testing.expectEqual(@as(u21, 0x00c2), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(u21, 0x0301), run.glyphs[1].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, "Ấ".len), run.glyphs[0].source_byte_len);
    try std.testing.expectEqual(@as(usize, "Ấ".len), run.glyphs[1].source_byte_len);
    // Fonts without GDEF synthesize mark classes from Unicode Mn. The source
    // mark must therefore be zero-width even when hmtx authors a spacing
    // advance, matching HarfBuzz's default-shaper late-zero policy.
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        run.glyphs[1].x_advance,
        0.001,
    );
}

test "missing precomposed Latin falls back to recursive NFD components" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &.{ 0x0041, 0x0301, 0x0302 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &buffer, "Ấ", 1000);

    try expectGlyphOutputs(&.{
        .{ .glyph_id = 1, .codepoint = 0x0041, .cluster = 0, .source_byte_len = "Ấ".len, .x_advance = 800 },
        .{ .glyph_id = 3, .codepoint = 0x0302, .cluster = 0, .source_byte_len = "Ấ".len, .x_advance = 0, .x_offset = -400, .y_offset = 62 },
        .{ .glyph_id = 2, .codepoint = 0x0301, .cluster = 0, .source_byte_len = "Ấ".len, .x_advance = 0, .x_offset = -400, .y_offset = 124 },
    }, run.glyphs);
}

test "missing canonical singleton decomposes through its supported target" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    // ANGSTROM SIGN canonically aliases A WITH RING ABOVE. HarfBuzz follows
    // canonical singleton mappings as well as the more common 1:2 mappings.
    const bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x00c5});
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &buffer, "Å", 1000);

    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x00c5), run.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 0), run.glyphs[0].cluster);
    try std.testing.expectEqual(@as(usize, "Å".len), run.glyphs[0].source_byte_len);
}

test "font fallback accepts Arabic clusters covered through normalization" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0627});
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0622});
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster("آ"));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &buffer, "آ", 20, .{ .direction = .rtl });
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), shaped.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u21, 0x0622), shaped.glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, "آ".len), shaped.glyphs[0].source_byte_len);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, "آ");
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 1), decisions.len);
    try std.testing.expectEqual(@as(usize, 1), decisions[0].font_index);
    try std.testing.expectEqual(@as(u21, 0x0622), decisions[0].codepoint);
    try std.testing.expectEqual(@as(usize, "آ".len), decisions[0].byte_len);
    try std.testing.expect(!decisions[0].missingGlyph());
}

test "font fallback keeps emoji ZWJ sequences atomic" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const woman: u21 = 0x1f469;
    const laptop: u21 = 0x1f4bb;

    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{woman});
    defer allocator.free(primary_bytes);
    const emoji_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ woman, laptop });
    defer allocator.free(emoji_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var emoji = try Font.parse(allocator, emoji_bytes);
    defer emoji.deinit();

    const fonts = [_]*const Font{ &primary, &emoji };
    const cascade = FontCascade.init(&fonts);
    const sequence = "\u{1f469}\u{200d}\u{1f4bb}";
    try std.testing.expectEqual(@as(usize, 1), try cascade.selectFontForCluster(sequence));

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, sequence, 20);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[0].font_index);
    // ZWJ participates in shaping but emits no visible fallback glyph when it
    // is not substituted.
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expect(shaped.glyphs[0].glyph_id != 0);
    try std.testing.expect(shaped.glyphs[1].glyph_id != 0);

    const decisions = try diagnoseFontFallbackUtf8(allocator, cascade, sequence);
    defer allocator.free(decisions);
    try std.testing.expectEqual(@as(usize, 2), decisions.len);
    for (decisions) |decision| {
        try std.testing.expectEqual(@as(usize, 1), decision.font_index);
        try std.testing.expect(!decision.missingGlyph());
    }
}

test "font fallback does not split a partially covered grapheme" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const base_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(base_bytes);
    const mark_bytes = try test_font.buildCodepointSetTtf(allocator, &.{0x0301});
    defer allocator.free(mark_bytes);

    var base_font = try Font.parse(allocator, base_bytes);
    defer base_font.deinit();
    var mark_font = try Font.parse(allocator, mark_bytes);
    defer mark_font.deinit();

    const fonts = [_]*const Font{ &base_font, &mark_font };
    const cascade = FontCascade.init(&fonts);
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(cascade, &buffer, "A\u{0301}", 20);

    try std.testing.expectEqual(@as(usize, 1), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 2), shaped.glyphs.len);
    try std.testing.expect(shaped.glyphs[0].glyph_id != 0);
    try std.testing.expectEqual(@as(GlyphId, 0), shaped.glyphs[1].glyph_id);
}
