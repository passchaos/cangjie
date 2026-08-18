//! Renderer-free textual diagnostics for Unicode, fonts, shaping, and caches.

const std = @import("std");
const font_mod = @import("../font.zig");
const glyph_position = @import("../layout/glyph_position.zig");
const paragraph_types = @import("../layout/types/paragraph.zig");
const run_types = @import("../layout/types/runs.zig");
const layout_cache = @import("../shaping/context/cache/root.zig");
const font_fallback = @import("../shaping/fallback/font/root.zig");
const shaping_plan = @import("../shaping/plan/root.zig");
const unicode = @import("../unicode.zig");
const overlay_mod = @import("overlays.zig");

pub fn dumpUnicodeSegmentation(writer: *std.Io.Writer, allocator: std.mem.Allocator, text: []const u8) !void {
    try writer.print("unicode.text bytes={d}\n", .{text.len});

    const graphemes = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    try writer.print("unicode.graphemes count={d}\n", .{graphemes.len});
    for (graphemes, 0..) |cluster, index| {
        try writer.print("  grapheme[{d}] bytes={d}..{d} text=\"{s}\"\n", .{
            index,
            cluster.byte_start,
            cluster.byte_start + cluster.byte_len,
            text[cluster.byte_start..][0..cluster.byte_len],
        });
    }

    const words = try unicode.itemizeWordSegments(allocator, text);
    defer allocator.free(words);
    try writer.print("unicode.words count={d}\n", .{words.len});
    for (words, 0..) |word, index| {
        try writer.print("  word[{d}] bytes={d}..{d} text=\"{s}\"\n", .{
            index,
            word.byte_start,
            word.byte_start + word.byte_len,
            text[word.byte_start..][0..word.byte_len],
        });
    }

    const scripts = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(scripts);
    try writer.print("unicode.scripts count={d}\n", .{scripts.len});
    for (scripts, 0..) |run, index| {
        try writer.print("  script[{d}] {s} bytes={d}..{d}\n", .{
            index,
            @tagName(run.script),
            run.byte_start,
            run.byte_start + run.byte_len,
        });
    }
}

pub fn dumpBidiRuns(writer: *std.Io.Writer, allocator: std.mem.Allocator, text: []const u8, base_direction: unicode.BidiClass) !void {
    const runs = try unicode.itemizeBidiRuns(allocator, text, base_direction);
    defer allocator.free(runs);
    try writer.print("bidi.runs base={s} count={d}\n", .{ @tagName(base_direction), runs.len });
    for (runs, 0..) |run, index| {
        try writer.print("  bidi[{d}] direction={s} bytes={d}..{d} text=\"{s}\"\n", .{
            index,
            @tagName(run.direction),
            run.byte_start,
            run.byte_start + run.byte_len,
            text[run.byte_start..][0..run.byte_len],
        });
    }
}

pub fn dumpBidiMap(writer: *std.Io.Writer, bidi_map: unicode.BidiMap) !void {
    try writer.print("bidi.map items={d}\n", .{bidi_map.items.len});
    for (bidi_map.items) |item| {
        try writer.print("  visual[{d}] logical={d} bytes={d}..{d} direction={s} cp=U+{X:0>4} visual_cp=U+{X:0>4}\n", .{
            item.visual_index,
            item.logical_index,
            item.byte_start,
            item.byte_start + item.byte_len,
            @tagName(item.direction),
            item.codepoint,
            item.visual_codepoint,
        });
    }
}

pub fn dumpLineBreaks(writer: *std.Io.Writer, allocator: std.mem.Allocator, text: []const u8) !void {
    const breaks = try unicode.itemizeLineBreaks(allocator, text);
    defer allocator.free(breaks);
    try writer.print("line_breaks count={d}\n", .{breaks.len});
    for (breaks, 0..) |line_break, index| {
        try writer.print("  line_break[{d}] byte={d} kind={s}\n", .{
            index,
            line_break.byte_offset,
            @tagName(line_break.kind),
        });
    }
}

pub fn dumpFontFallback(writer: *std.Io.Writer, cascade: font_fallback.Cascade, text: []const u8) !void {
    try writer.print("font_fallback fonts={d}\n", .{cascade.fonts.len});
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const font_index = try cascade.selectFont(codepoint);
        const glyph_id = try cascade.fonts[font_index].glyphIndex(codepoint);
        try writer.print("  cp=U+{X:0>4} byte={d} font_index={d} glyph={d} missing={}\n", .{
            codepoint,
            byte_start,
            font_index,
            glyph_id,
            glyph_id == 0,
        });
    }
}

pub fn dumpShapeRuns(writer: *std.Io.Writer, shaped: run_types.ShapedText) !void {
    try writer.print("shape.runs count={d} glyphs={d} size=({d:.3},{d:.3})\n", .{
        shaped.runs.len,
        shaped.glyphs.len,
        shaped.width(),
        shaped.height(),
    });
    for (shaped.runs, 0..) |run, index| {
        try writer.print("  run[{d}] font_index={d} glyphs={d}..{d} font_size={d:.3} variation_coords={d} offset=({d:.3},{d:.3})\n", .{
            index,
            run.font_index,
            run.glyph_start,
            run.glyph_start + run.glyph_len,
            run.font_size,
            run.variation_coord_len,
            run.x_offset,
            run.y_offset,
        });
    }
}

pub fn dumpGlyphClusters(writer: *std.Io.Writer, glyphs: []const glyph_position.GlyphPosition) !void {
    try writer.print("glyph_clusters count={d}\n", .{glyphs.len});
    for (glyphs, 0..) |glyph, index| {
        try writer.print("  glyph[{d}] id={d} cp=U+{X:0>4} cluster={d} advance=({d:.3},{d:.3}) offset=({d:.3},{d:.3})\n", .{
            index,
            glyph.glyph_id,
            glyph.codepoint,
            glyph.cluster,
            glyph.x_advance,
            glyph.y_advance,
            glyph.x_offset,
            glyph.y_offset,
        });
    }
}

pub fn dumpParagraphLayout(writer: *std.Io.Writer, paragraph: paragraph_types.ParagraphLayout) !void {
    try writer.print("paragraph mode={s} size=({d:.3},{d:.3}) lines={d} glyphs={d} runs={d}\n", .{
        @tagName(paragraph.writing_mode),
        paragraph.width,
        paragraph.height,
        paragraph.lines.len,
        paragraph.glyphs.len,
        paragraph.runs.len,
    });
    for (paragraph.lines, 0..) |line, index| {
        try writer.print("  line[{d}] glyphs={d}..{d} runs={d}..{d} rect=({d:.3},{d:.3},{d:.3},{d:.3}) baseline={d:.3} ascent={d:.3} descent={d:.3} leading={d:.3}\n", .{
            index,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
            line.run_start,
            line.run_start + line.run_len,
            line.x,
            line.y,
            line.width,
            line.height,
            line.baseline,
            line.ascent,
            line.descent,
            line.leading,
        });
    }
}

pub fn dumpHitTest(writer: *std.Io.Writer, paragraph: paragraph_types.ParagraphLayout, x: f32, y: f32) !void {
    const hit = paragraph.hitTest(x, y);
    try writer.print("hit_test point=({d:.3},{d:.3}) glyph_index={d} cluster={d} trailing={}\n", .{
        x,
        y,
        hit.glyph_index,
        hit.cluster,
        hit.trailing,
    });
}

pub fn dumpSelectionRects(writer: *std.Io.Writer, allocator: std.mem.Allocator, paragraph: paragraph_types.ParagraphLayout, start_glyph: usize, end_glyph: usize) !void {
    const rects = try paragraph.selectionRects(allocator, start_glyph, end_glyph);
    defer allocator.free(rects);
    try writer.print("selection_rects glyphs={d}..{d} count={d}\n", .{ start_glyph, end_glyph, rects.len });
    for (rects, 0..) |rect, index| {
        try writer.print("  selection[{d}] rect=({d:.3},{d:.3},{d:.3},{d:.3})\n", .{
            index,
            rect.x,
            rect.y,
            rect.width,
            rect.height,
        });
    }
}
pub fn dumpDebugOverlays(writer: *std.Io.Writer, overlays: overlay_mod.DebugOverlayList) !void {
    try writer.print("debug_overlays count={d}\n", .{overlays.items.len});
    for (overlays.items, 0..) |overlay, index| {
        try writer.print("  overlay[{d}] kind={s} rect=({d:.3},{d:.3},{d:.3},{d:.3}) line=({d:.3},{d:.3})->({d:.3},{d:.3}) bytes={d}..{d} label={d}\n", .{
            index,
            @tagName(overlay.kind),
            overlay.rect.x,
            overlay.rect.y,
            overlay.rect.width,
            overlay.rect.height,
            overlay.line_start_x,
            overlay.line_start_y,
            overlay.line_end_x,
            overlay.line_end_y,
            overlay.byte_start,
            overlay.byte_end,
            overlay.label_index,
        });
    }
}

pub fn dumpMissingGlyphs(writer: *std.Io.Writer, cascade: font_fallback.Cascade, text: []const u8) !void {
    var missing_count: usize = 0;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const font_index = try cascade.selectFont(codepoint);
        const glyph_id = try cascade.fonts[font_index].glyphIndex(codepoint);
        if (glyph_id == 0) {
            if (missing_count == 0) try writer.writeAll("missing_glyphs\n");
            missing_count += 1;
            try writer.print("  missing cp=U+{X:0>4} byte={d} fallback_font_index={d}\n", .{ codepoint, byte_start, font_index });
        }
    }
    if (missing_count == 0) {
        try writer.writeAll("missing_glyphs none\n");
    }
}

pub fn dumpFontCoverage(writer: *std.Io.Writer, font: *const font_mod.Font, text: []const u8) !void {
    try writer.writeAll("font_coverage\n");
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const glyph_id = try font.glyphIndex(codepoint);
        try writer.print("  cp=U+{X:0>4} byte={d} glyph={d} covered={}\n", .{
            codepoint,
            byte_start,
            glyph_id,
            glyph_id != 0,
        });
    }
}

pub fn dumpShapePlanCacheStats(writer: *std.Io.Writer, cache: shaping_plan.ShapePlanCache) !void {
    var total_hits: usize = 0;
    for (cache.plans.items) |plan| total_hits += plan.hits;
    try writer.print("shape_cache plans={d} hits={d}\n", .{ cache.plans.items.len, total_hits });
}

pub fn dumpShapedRunCacheStats(writer: *std.Io.Writer, cache: layout_cache.ShapedRunCache) !void {
    var entry_hits: usize = 0;
    var glyphs: usize = 0;
    var runs: usize = 0;
    for (cache.entries.items) |entry| {
        entry_hits += entry.hits;
        glyphs += entry.glyphs.len;
        runs += entry.runs.len;
    }
    try writer.print("shaped_run_cache entries={d} hits={d} misses={d} entry_hits={d} glyphs={d} runs={d}\n", .{
        cache.entries.items.len,
        cache.hits,
        cache.misses,
        entry_hits,
        glyphs,
        runs,
    });
}

pub fn dumpFontFallbackCacheStats(writer: *std.Io.Writer, cache: layout_cache.FontFallbackCache) !void {
    const scalar_entries = cache.scalarEntryCount();
    const cluster_entries = cache.clusterEntryCount();
    try writer.print("font_fallback_cache entries={d} scalar_entries={d} cluster_entries={d} hits={d} misses={d}\n", .{
        scalar_entries + cluster_entries,
        scalar_entries,
        cluster_entries,
        cache.hits,
        cache.misses,
    });
}

pub fn dumpGlyphMetricsCacheStats(writer: *std.Io.Writer, cache: layout_cache.GlyphMetricsCache) !void {
    try writer.print("glyph_metrics_cache entries={d} hits={d} misses={d}\n", .{
        cache.entries.count(),
        cache.hits,
        cache.misses,
    });
}

pub fn dumpGlyphIndexCacheStats(writer: *std.Io.Writer, cache: layout_cache.GlyphIndexCache) !void {
    try writer.print("glyph_index_cache entries={d} hits={d} misses={d}\n", .{
        cache.entries.count(),
        cache.hits,
        cache.misses,
    });
}
