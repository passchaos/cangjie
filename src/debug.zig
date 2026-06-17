const std = @import("std");
const buffer_mod = @import("buffer.zig");
const font_mod = @import("font.zig");
const layout = @import("layout.zig");
const unicode = @import("unicode.zig");

pub const OverlayKind = enum {
    baseline,
    line_box,
    glyph_box,
    cluster_boundary,
    cursor_rect,
    selection_rect,
    fallback_font_region,
    bidi_run,
};

pub const DebugOverlay = struct {
    kind: OverlayKind,
    rect: layout.TextRect,
    line_start_x: f32 = 0,
    line_start_y: f32 = 0,
    line_end_x: f32 = 0,
    line_end_y: f32 = 0,
    byte_start: usize = 0,
    byte_end: usize = 0,
    label_index: usize = 0,
};

pub const DebugOverlayList = struct {
    allocator: std.mem.Allocator,
    items: []DebugOverlay,

    pub fn deinit(self: *DebugOverlayList) void {
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const OverlayOptions = struct {
    cursor: ?layout.TextPosition = null,
    selection_start_glyph: ?usize = null,
    selection_end_glyph: ?usize = null,
    bidi_text: ?[]const u8 = null,
    bidi_base_direction: unicode.BidiClass = .ltr,
};

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

pub fn dumpFontFallback(writer: *std.Io.Writer, cascade: layout.FontCascade, text: []const u8) !void {
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

pub fn dumpShapeRuns(writer: *std.Io.Writer, shaped: layout.ShapedText) !void {
    try writer.print("shape.runs count={d} glyphs={d} width={d:.3}\n", .{ shaped.runs.len, shaped.glyphs.len, shaped.width() });
    for (shaped.runs, 0..) |run, index| {
        try writer.print("  run[{d}] font_index={d} glyphs={d}..{d} font_size={d:.3} x_offset={d:.3}\n", .{
            index,
            run.font_index,
            run.glyph_start,
            run.glyph_start + run.glyph_len,
            run.font_size,
            run.x_offset,
        });
    }
}

pub fn dumpGlyphClusters(writer: *std.Io.Writer, glyphs: []const layout.GlyphPosition) !void {
    try writer.print("glyph_clusters count={d}\n", .{glyphs.len});
    for (glyphs, 0..) |glyph, index| {
        try writer.print("  glyph[{d}] id={d} cp=U+{X:0>4} cluster={d} advance={d:.3} offset=({d:.3},{d:.3})\n", .{
            index,
            glyph.glyph_id,
            glyph.codepoint,
            glyph.cluster,
            glyph.x_advance,
            glyph.x_offset,
            glyph.y_offset,
        });
    }
}

pub fn dumpParagraphLayout(writer: *std.Io.Writer, paragraph: layout.ParagraphLayout) !void {
    try writer.print("paragraph size=({d:.3},{d:.3}) lines={d} glyphs={d} runs={d}\n", .{
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

pub fn dumpHitTest(writer: *std.Io.Writer, paragraph: layout.ParagraphLayout, x: f32, y: f32) !void {
    const hit = paragraph.hitTest(x, y);
    try writer.print("hit_test point=({d:.3},{d:.3}) glyph_index={d} cluster={d} trailing={}\n", .{
        x,
        y,
        hit.glyph_index,
        hit.cluster,
        hit.trailing,
    });
}

pub fn dumpSelectionRects(writer: *std.Io.Writer, allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, start_glyph: usize, end_glyph: usize) !void {
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

pub fn buildDebugOverlays(allocator: std.mem.Allocator, paragraph: layout.ParagraphLayout, options: OverlayOptions) !DebugOverlayList {
    var overlays = std.ArrayList(DebugOverlay).empty;
    errdefer overlays.deinit(allocator);

    for (paragraph.lines, 0..) |line, index| {
        try overlays.append(allocator, .{
            .kind = .line_box,
            .rect = .{ .x = line.x, .y = line.y, .width = line.width, .height = line.height },
            .label_index = index,
        });
        try overlays.append(allocator, .{
            .kind = .baseline,
            .rect = .{ .x = line.x, .y = line.y + line.baseline, .width = line.width, .height = 0 },
            .line_start_x = line.x,
            .line_start_y = line.y + line.baseline,
            .line_end_x = line.x + line.width,
            .line_end_y = line.y + line.baseline,
            .label_index = index,
        });
        try appendGlyphAndClusterOverlays(allocator, &overlays, paragraph, line, index);
        try appendFallbackRegionOverlays(allocator, &overlays, paragraph, line, index);
    }

    if (options.cursor) |position| {
        try overlays.append(allocator, .{
            .kind = .cursor_rect,
            .rect = paragraph.caretRect(position),
        });
    }

    if (options.selection_start_glyph != null and options.selection_end_glyph != null) {
        const rects = try paragraph.selectionRects(allocator, options.selection_start_glyph.?, options.selection_end_glyph.?);
        defer allocator.free(rects);
        for (rects, 0..) |rect, index| {
            try overlays.append(allocator, .{
                .kind = .selection_rect,
                .rect = rect,
                .label_index = index,
            });
        }
    }

    if (options.bidi_text) |text| {
        const runs = try unicode.itemizeBidiRuns(allocator, text, options.bidi_base_direction);
        defer allocator.free(runs);
        for (runs, 0..) |run, index| {
            try overlays.append(allocator, .{
                .kind = .bidi_run,
                .rect = .{ .x = 0, .y = @floatFromInt(index), .width = @floatFromInt(run.byte_len), .height = 1 },
                .byte_start = run.byte_start,
                .byte_end = run.byte_start + run.byte_len,
                .label_index = index,
            });
        }
    }

    return .{
        .allocator = allocator,
        .items = try overlays.toOwnedSlice(allocator),
    };
}

fn appendGlyphAndClusterOverlays(allocator: std.mem.Allocator, overlays: *std.ArrayList(DebugOverlay), paragraph: layout.ParagraphLayout, line: layout.ParagraphLine, line_index: usize) !void {
    var x = line.x;
    const glyph_end = line.glyph_start + line.glyph_len;
    var previous_cluster: ?usize = null;
    for (paragraph.glyphs[line.glyph_start..glyph_end], line.glyph_start..) |glyph, glyph_index| {
        if (previous_cluster == null or previous_cluster.? != glyph.cluster) {
            try overlays.append(allocator, .{
                .kind = .cluster_boundary,
                .rect = .{ .x = x, .y = line.y, .width = 0, .height = line.height },
                .line_start_x = x,
                .line_start_y = line.y,
                .line_end_x = x,
                .line_end_y = line.y + line.height,
                .byte_start = glyph.cluster,
                .byte_end = glyph.cluster,
                .label_index = glyph_index,
            });
            previous_cluster = glyph.cluster;
        }
        try overlays.append(allocator, .{
            .kind = .glyph_box,
            .rect = .{
                .x = x + glyph.x_offset,
                .y = line.y + line.baseline - line.ascent + glyph.y_offset,
                .width = glyph.x_advance,
                .height = line.ascent + line.descent,
            },
            .byte_start = glyph.cluster,
            .byte_end = glyph.cluster,
            .label_index = glyph_index,
        });
        x += glyph.x_advance;
    }
    try overlays.append(allocator, .{
        .kind = .cluster_boundary,
        .rect = .{ .x = x, .y = line.y, .width = 0, .height = line.height },
        .line_start_x = x,
        .line_start_y = line.y,
        .line_end_x = x,
        .line_end_y = line.y + line.height,
        .byte_start = if (glyph_end > line.glyph_start) paragraph.glyphs[glyph_end - 1].cluster else 0,
        .byte_end = if (glyph_end > line.glyph_start) paragraph.glyphs[glyph_end - 1].cluster else 0,
        .label_index = line_index,
    });
}

fn appendFallbackRegionOverlays(allocator: std.mem.Allocator, overlays: *std.ArrayList(DebugOverlay), paragraph: layout.ParagraphLayout, line: layout.ParagraphLine, line_index: usize) !void {
    const line_glyph_end = line.glyph_start + line.glyph_len;
    for (line.runs(paragraph)) |run| {
        const start = @max(line.glyph_start, run.glyph_start);
        const end = @min(line_glyph_end, run.glyph_start + run.glyph_len);
        if (start >= end) continue;
        const start_x = line.x + advanceBefore(paragraph.glyphs[line.glyph_start..line_glyph_end], start - line.glyph_start);
        const end_x = line.x + advanceBefore(paragraph.glyphs[line.glyph_start..line_glyph_end], end - line.glyph_start);
        try overlays.append(allocator, .{
            .kind = .fallback_font_region,
            .rect = .{ .x = start_x, .y = line.y, .width = end_x - start_x, .height = line.height },
            .byte_start = if (start < paragraph.glyphs.len) paragraph.glyphs[start].cluster else 0,
            .byte_end = if (end > start and end - 1 < paragraph.glyphs.len) paragraph.glyphs[end - 1].cluster else 0,
            .label_index = run.font_index + line_index * 1000,
        });
    }
}

fn advanceBefore(glyphs: []const layout.GlyphPosition, count: usize) f32 {
    var width: f32 = 0;
    for (glyphs[0..@min(count, glyphs.len)]) |glyph| {
        width += glyph.x_advance;
    }
    return width;
}

pub fn dumpDebugOverlays(writer: *std.Io.Writer, overlays: DebugOverlayList) !void {
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

pub fn dumpMissingGlyphs(writer: *std.Io.Writer, cascade: layout.FontCascade, text: []const u8) !void {
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

pub fn dumpShapePlanCacheStats(writer: *std.Io.Writer, cache: layout.ShapePlanCache) !void {
    var total_hits: usize = 0;
    for (cache.plans.items) |plan| total_hits += plan.hits;
    try writer.print("shape_cache plans={d} hits={d}\n", .{ cache.plans.items.len, total_hits });
}

pub fn dumpShapedRunCacheStats(writer: *std.Io.Writer, cache: layout.ShapedRunCache) !void {
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

pub fn dumpFontFallbackCacheStats(writer: *std.Io.Writer, cache: layout.FontFallbackCache) !void {
    try writer.print("font_fallback_cache entries={d} hits={d} misses={d}\n", .{
        cache.entries.count(),
        cache.hits,
        cache.misses,
    });
}

pub fn dumpGlyphMetricsCacheStats(writer: *std.Io.Writer, cache: layout.GlyphMetricsCache) !void {
    try writer.print("glyph_metrics_cache entries={d} hits={d} misses={d}\n", .{
        cache.entries.count(),
        cache.hits,
        cache.misses,
    });
}

pub fn dumpGlyphIndexCacheStats(writer: *std.Io.Writer, cache: layout.GlyphIndexCache) !void {
    try writer.print("glyph_index_cache entries={d} hits={d} misses={d}\n", .{
        cache.entries.count(),
        cache.hits,
        cache.misses,
    });
}

pub fn dumpTextBufferLayoutStats(writer: *std.Io.Writer, buffer: buffer_mod.TextBuffer) !void {
    const dirty = buffer.dirtyRange();
    try writer.print("layout_cache text_bytes={d} layout_valid={} dirty={d}..{d} scroll_y={d:.3} grapheme_cache={d} word_cache={d}\n", .{
        buffer.slice().len,
        buffer.layout_valid,
        dirty.byte_start,
        dirty.byte_end,
        buffer.scroll_y,
        buffer.grapheme_cache.items.len,
        buffer.word_cache.items.len,
    });
}

test "debug dumps unicode bidi paragraph hit selection and cache stats" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    var layout_buffer = layout.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try layout.TextShaper.shapeUtf8Cascade(cascade, &layout_buffer, "A A", 20);
    const paragraph = try layout.TextShaper.layoutParagraphUtf8(cascade, &layout_buffer, "A A", 20, .{
        .max_width = 100,
        .line_height = 24,
    });

    var cache = layout.ShapePlanCache.init(allocator);
    defer cache.deinit();
    _ = try cache.getOrPut(layout.ShapePlanKey.fromText("A", .{}));
    var shaped_cache = layout.ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    var fallback_cache = layout.FontFallbackCache.init(allocator);
    defer fallback_cache.deinit();
    _ = try fallback_cache.selectFont(cascade, 'A');
    _ = try fallback_cache.selectFont(cascade, 'A');
    var metrics_cache = layout.GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();
    _ = try metrics_cache.horizontalMetrics(&font, 1);
    _ = try metrics_cache.horizontalMetrics(&font, 1);
    var glyph_index_cache = layout.GlyphIndexCache.init(allocator);
    defer glyph_index_cache.deinit();
    _ = try glyph_index_cache.glyphIndex(&font, 'A');
    _ = try glyph_index_cache.glyphIndex(&font, 'A');

    var text_buffer = try buffer_mod.TextBuffer.initText(allocator, "A A");
    defer text_buffer.deinit();

    var storage: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    try dumpUnicodeSegmentation(&writer, allocator, "A\u{0301} B");
    try dumpBidiRuns(&writer, allocator, "A ב", .ltr);
    var bidi_map = try unicode.buildBidiMap(allocator, "A ב", .ltr);
    defer bidi_map.deinit();
    try dumpBidiMap(&writer, bidi_map);
    try dumpLineBreaks(&writer, allocator, "A B\n一丁");
    try dumpFontFallback(&writer, cascade, "AZ");
    try dumpShapeRuns(&writer, shaped);
    try dumpGlyphClusters(&writer, paragraph.glyphs);
    try dumpParagraphLayout(&writer, paragraph);
    try dumpHitTest(&writer, paragraph, 5, 5);
    try dumpSelectionRects(&writer, allocator, paragraph, 0, 2);
    var overlays = try buildDebugOverlays(allocator, paragraph, .{
        .cursor = .{ .glyph_index = 1, .cluster = 1 },
        .selection_start_glyph = 0,
        .selection_end_glyph = 2,
        .bidi_text = "A ב",
    });
    defer overlays.deinit();
    try dumpDebugOverlays(&writer, overlays);
    try dumpMissingGlyphs(&writer, cascade, "Z");
    try dumpFontCoverage(&writer, &font, "AZ");
    try dumpShapePlanCacheStats(&writer, cache);
    try dumpShapedRunCacheStats(&writer, shaped_cache);
    try dumpFontFallbackCacheStats(&writer, fallback_cache);
    try dumpGlyphIndexCacheStats(&writer, glyph_index_cache);
    try dumpGlyphMetricsCacheStats(&writer, metrics_cache);
    try dumpTextBufferLayoutStats(&writer, text_buffer);

    const output = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, output, "unicode.graphemes") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi.runs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line_breaks") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_fallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shape.runs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_clusters") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "paragraph size=") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hit_test") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "selection_rects") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "debug_overlays") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "baseline") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line_box") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "cursor_rect") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "selection_rect") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "bidi_run") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "missing_glyphs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_coverage") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shape_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "shaped_run_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "font_fallback_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_index_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "glyph_metrics_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "layout_cache") != null);
}
