//! Renderer-free shaping diagnostics and visibility controls.

const std = @import("std");
const support = @import("../support.zig");

const ClusterCaretIssueKind = support.ClusterCaretIssueKind;
const Font = support.Font;
const FontCascade = support.FontCascade;
const GlyphId = support.GlyphId;
const GlyphPosition = support.GlyphPosition;
const LayoutBuffer = support.LayoutBuffer;
const ParagraphLayout = support.ParagraphLayout;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const diagnoseClusterCaretConsistencyUtf8 =
    support.diagnoseClusterCaretConsistencyUtf8;
const diagnoseShapeQualityUtf8 = support.diagnoseShapeQualityUtf8;
const caret_analyze =
    @import("../../../shaping/diagnostics/caret.zig").analyze;
const unicode = @import("../../../unicode.zig");

test "shape quality diagnostics summarize fallback coverage and missing glyphs" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Primary", "Regular", "Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Fallback", "Regular", "Fallback Regular");
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    var report = try diagnoseShapeQualityUtf8(allocator, cascade, "AB\u{fe0f}C", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 3), report.font_run_count);
    try std.testing.expectEqual(@as(usize, 1), report.variation_selector_count);
    try std.testing.expectEqual(@as(usize, 1), report.fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyphs.len);
    try std.testing.expectEqual(@as(u21, 'C'), report.missing_glyphs[0].codepoint);
    try std.testing.expectEqual(@as(usize, 5), report.missing_glyphs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyphs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.missing_glyphs[0].font_index);
    try std.testing.expectEqual(@as(GlyphId, 0), report.missing_glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs.len);
    // FE0F is Script=Inherited and remains inside the surrounding Latin run.
    try std.testing.expectEqual(@as(usize, 1), report.script_runs.len);
    var script_fallback_glyphs: usize = 0;
    var script_missing_glyphs: usize = 0;
    for (report.script_runs) |script_run| {
        script_fallback_glyphs += script_run.fallback_glyph_count;
        script_missing_glyphs += script_run.missing_glyph_count;
    }
    try std.testing.expectEqual(report.fallback_glyph_count, script_fallback_glyphs);
    try std.testing.expectEqual(report.missing_glyph_count, script_missing_glyphs);
    try std.testing.expect(report.horizontal_advance > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), report.vertical_advance, 0.001);
}

test "shape quality diagnostics expose per font and script run counters" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const latin_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'A', "Latin", "Regular", "Latin Regular");
    defer allocator.free(latin_bytes);
    const greek_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 0x03b2, "Greek", "Regular", "Greek Regular");
    defer allocator.free(greek_bytes);

    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var greek = try Font.parse(allocator, greek_bytes);
    defer greek.deinit();

    const fonts = [_]*const Font{ &latin, &greek };
    const cascade = FontCascade.init(&fonts);

    var report = try diagnoseShapeQualityUtf8(allocator, cascade, "AβZ", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs.len);
    try std.testing.expectEqual(@as(usize, 3), report.script_runs.len);
    try std.testing.expectEqual(@as(usize, 1), report.fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[0].missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 1), report.font_runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), report.font_runs[1].byte_len);
    try std.testing.expectEqual(@as(usize, 0), report.font_runs[1].missing_glyph_count);

    try std.testing.expectEqual(@as(usize, 0), report.font_runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 3), report.font_runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[2].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.font_runs[2].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.latin, report.script_runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[0].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[0].font_run_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[0].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.greek, report.script_runs[1].script);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), report.script_runs[1].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].font_run_count);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[1].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[1].missing_glyph_count);

    try std.testing.expectEqual(unicode.Script.latin, report.script_runs[2].script);
    try std.testing.expectEqual(@as(usize, 3), report.script_runs[2].byte_start);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].byte_len);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].font_run_count);
    try std.testing.expectEqual(@as(usize, 0), report.script_runs[2].fallback_glyph_count);
    try std.testing.expectEqual(@as(usize, 1), report.script_runs[2].missing_glyph_count);
}

test "cluster caret diagnostics accept variation selectors and fallback runs" {
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

    var report = try diagnoseClusterCaretConsistencyUtf8(allocator, cascade, "A\u{fe0f}B\u{fe0e}", 20, .{});
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 4), report.caret_boundary_count);
    try std.testing.expectEqual(@as(usize, 4), report.grapheme_boundary_count);
    try std.testing.expectEqual(@as(usize, 0), report.issue_count);
    try std.testing.expectEqual(@as(usize, 0), report.issues.len);
}

test "unsupported variation selectors can report a synthetic not-found glyph" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text = "B\u{fe00}";
    const default_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{});
    try std.testing.expectEqual(@as(usize, 1), default_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), default_run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(?u32, null), default_run.glyphs[0].synthetic_glyph_id);
    try std.testing.expectEqual(@as(u32, 2), default_run.glyphs[0].outputGlyphId());
    try std.testing.expectEqual(@as(usize, text.len), default_run.glyphs[0].source_byte_len);

    const synthetic_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{
        .not_found_variation_selector_glyph = 1_000_000,
    });
    try std.testing.expectEqual(@as(usize, 2), synthetic_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 2), synthetic_run.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(u32, 2), synthetic_run.glyphs[0].outputGlyphId());
    try std.testing.expectEqual(@as(GlyphId, 0), synthetic_run.glyphs[1].glyph_id);
    try std.testing.expectEqual(@as(?u32, 1_000_000), synthetic_run.glyphs[1].synthetic_glyph_id);
    try std.testing.expectEqual(@as(u32, 1_000_000), synthetic_run.glyphs[1].outputGlyphId());
    try std.testing.expectEqual(@as(usize, 0), synthetic_run.glyphs[1].cluster);
    try std.testing.expectEqual(@as(usize, text.len), synthetic_run.glyphs[1].source_byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), synthetic_run.glyphs[1].y_offset, 0.001);
}

test "remove-default-ignorables deletes the font's fallback space glyph" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;

    const bytes = try test_font.buildDefaultIgnorableSpaceTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const text = "A\u{200b}";
    const default_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{});
    try std.testing.expectEqual(@as(usize, 2), default_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), default_run.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0), default_run.glyphs[1].x_advance, 0.001);

    const removed_run = try TextShaper.shapeUtf8WithOptions(&font, &buffer, text, 20, .{
        .remove_default_ignorables = true,
    });
    try std.testing.expectEqual(@as(usize, 1), removed_run.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 1), removed_run.glyphs[0].glyph_id);

    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    const default_key = ShapedRunCache.key(cascade.fonts, text, 20, .{});
    const removed_key = ShapedRunCache.key(cascade.fonts, text, 20, .{ .remove_default_ignorables = true });
    try std.testing.expect(!default_key.plan.eql(removed_key.plan));
}

test "cluster caret diagnostics catch invalid UTF-8 source spans" {
    const allocator = std.testing.allocator;
    const text = "Aβ";
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 0x03b2,
            .cluster = 2,
            .source_byte_len = 1,
            .x_advance = 10,
        },
    };
    const paragraph = ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &.{},
        .lines = &.{},
        .width = 10,
        .height = 0,
    };

    var report = try caret_analyze(allocator, text, paragraph);
    defer report.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), report.glyph_count);
    try std.testing.expectEqual(@as(usize, 4), report.issue_count);
    try std.testing.expectEqual(ClusterCaretIssueKind.cluster_not_utf8_boundary, report.issues[0].kind);
    try std.testing.expectEqual(@as(?usize, 0), report.issues[0].glyph_index);
    try std.testing.expectEqual(@as(usize, 2), report.issues[0].cluster);
    try std.testing.expectEqual(@as(usize, 3), report.issues[0].source_end);
    try std.testing.expectEqual(ClusterCaretIssueKind.grapheme_boundary_roundtrip_mismatch, report.issues[1].kind);
    try std.testing.expectEqual(@as(usize, 0), report.issues[1].expected_byte_offset);
    try std.testing.expectEqual(@as(usize, 2), report.issues[1].actual_byte_offset);
}
