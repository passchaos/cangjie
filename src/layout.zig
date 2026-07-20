const std = @import("std");
const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const unicode = @import("unicode.zig");

/// One positioned glyph after cmap mapping, GSUB substitution, and GPOS/kern
/// adjustment. `cluster` is a byte offset into the original UTF-8 text, so
/// hit testing and selection can map glyph positions back to source text.
pub const GlyphPosition = struct {
    glyph_id: GlyphId,
    codepoint: u21,
    cluster: usize,
    /// Number of UTF-8 bytes in the source span represented by this glyph.
    /// This is usually one scalar, but it can include skipped variation
    /// selectors or all components collapsed into a GSUB ligature. Keeping the
    /// extent next to the cluster start lets caret logic recover the trailing
    /// source byte offset even when there is no following glyph.
    source_byte_len: usize = 0,
    x_advance: f32,
    y_advance: f32 = 0,
    x_offset: f32 = 0,
    y_offset: f32 = 0,
};

/// A contiguous range of glyphs rendered by one font at one size.
pub const GlyphRun = struct {
    font: *const Font,
    font_size: f32,
    glyphs: []const GlyphPosition,

    pub fn width(self: GlyphRun) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.x_advance;
        return total;
    }
};

/// A subrange of the shaped glyph stream selected from a font cascade.
/// Multiple cascade runs can exist inside a single paragraph line.
pub const CascadeRun = struct {
    font: *const Font,
    font_index: usize,
    font_size: f32,
    glyph_start: usize,
    glyph_len: usize,
    x_offset: f32,

    pub fn glyphs(self: CascadeRun, shaped: ShapedText) []const GlyphPosition {
        return shaped.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }

    pub fn glyphRun(self: CascadeRun, shaped: ShapedText) GlyphRun {
        return .{ .font = self.font, .font_size = self.font_size, .glyphs = self.glyphs(shaped) };
    }
};

/// Flat shaping result. Glyphs are stored once, while runs describe which font
/// owns each contiguous range.
pub const ShapedText = struct {
    glyphs: []const GlyphPosition,
    runs: []const CascadeRun,

    pub fn width(self: ShapedText) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.x_advance;
        return total;
    }
};

pub const ScriptedRun = struct {
    script: unicode.Script,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,

    pub fn glyphs(self: ScriptedRun, text: ScriptedText) []const GlyphPosition {
        return text.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }
};

pub const ScriptedText = struct {
    glyphs: []const GlyphPosition,
    font_runs: []const CascadeRun,
    script_runs: []const ScriptedRun,
};

pub const TextDirection = enum {
    ltr,
    rtl,
};

pub const ShapeOptions = struct {
    direction: TextDirection = .ltr,
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    features: []const unicode.FeatureOverride = &.{},
};

/// Coarse shaping plan identity. It intentionally excludes the concrete font
/// and text bytes; those live in `ShapedRunCacheKey`. This part captures the
/// OpenType selection knobs that change which GSUB/GPOS lookups are active.
pub const ShapePlanKey = struct {
    direction: TextDirection = .ltr,
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    feature_hash: u64 = 0,

    pub fn fromText(text: []const u8, options: ShapeOptions) ShapePlanKey {
        return .{
            .direction = options.direction,
            .script_tag = effectiveScriptTag(text, options),
            .language_tag = effectiveLanguageTag(text, options),
            .feature_hash = featureOverridesHash(options.features),
        };
    }
};

pub const ShapePlan = struct {
    key: ShapePlanKey,
    hits: usize = 0,
};

pub const ShapePlanCache = struct {
    allocator: std.mem.Allocator,
    plans: std.ArrayList(ShapePlan) = .empty,

    pub fn init(allocator: std.mem.Allocator) ShapePlanCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ShapePlanCache) void {
        self.plans.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn getOrPut(self: *ShapePlanCache, key: ShapePlanKey) !*ShapePlan {
        for (self.plans.items) |*plan| {
            if (shapePlanKeysEqual(plan.key, key)) {
                plan.hits += 1;
                return plan;
            }
        }
        try self.plans.append(self.allocator, .{ .key = key, .hits = 1 });
        return &self.plans.items[self.plans.items.len - 1];
    }
};

pub const ShapedRunCacheKey = struct {
    cascade_hash: u64,
    text_hash: u64,
    text_len: usize,
    font_size_bits: u32,
    plan: ShapePlanKey,
};

pub const ShapedRunCacheEntry = struct {
    key: ShapedRunCacheKey,
    glyphs: []GlyphPosition,
    runs: []CascadeRun,
    hits: usize = 0,
};

pub const ShapedRunCache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(ShapedRunCacheEntry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ShapedRunCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ShapedRunCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *ShapedRunCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.glyphs);
            self.allocator.free(entry.runs);
        }
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn key(cascade: FontCascade, text: []const u8, font_size: f32, options: ShapeOptions) ShapedRunCacheKey {
        return .{
            .cascade_hash = cascadeHash(cascade),
            .text_hash = std.hash.Wyhash.hash(0, text),
            .text_len = text.len,
            .font_size_bits = @bitCast(font_size),
            .plan = ShapePlanKey.fromText(text, options),
        };
    }

    pub fn load(self: *ShapedRunCache, key_value: ShapedRunCacheKey, buffer: *LayoutBuffer) !?ShapedText {
        for (self.entries.items) |*entry| {
            if (!shapedRunCacheKeysEqual(entry.key, key_value)) continue;
            self.hits += 1;
            entry.hits += 1;
            buffer.clear();
            try buffer.glyphs.appendSlice(buffer.allocator, entry.glyphs);
            try buffer.runs.appendSlice(buffer.allocator, entry.runs);
            return buffer.shapedText();
        }
        self.misses += 1;
        return null;
    }

    pub fn store(self: *ShapedRunCache, key_value: ShapedRunCacheKey, shaped: ShapedText) !void {
        const glyphs = try self.allocator.dupe(GlyphPosition, shaped.glyphs);
        errdefer self.allocator.free(glyphs);
        const runs = try self.allocator.dupe(CascadeRun, shaped.runs);
        errdefer self.allocator.free(runs);
        try self.entries.append(self.allocator, .{
            .key = key_value,
            .glyphs = glyphs,
            .runs = runs,
        });
    }
};

pub const TextAlign = enum {
    left,
    center,
    right,
};

pub const BaselineMetrics = struct {
    ascent: f32,
    descent: f32,
    leading: f32,

    pub fn lineHeight(self: BaselineMetrics) f32 {
        return self.ascent + self.descent + self.leading;
    }
};

pub const TextMetrics = struct {
    width: f32,
    height: f32,
    baseline: f32,
    ascent: f32,
    descent: f32,
    leading: f32,
};

pub const ParagraphOptions = struct {
    max_width: f32,
    alignment: TextAlign = .left,
    line_height: ?f32 = null,
    direction: TextDirection = .ltr,
    max_lines: ?usize = null,
    /// Append a simple "..." marker only when `max_lines` actually removes
    /// content. A paragraph whose natural line count exactly equals the limit
    /// should remain byte-for-byte shaped text, not be rewritten as truncated.
    ellipsis: bool = false,
    tab_width: usize = 4,
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    first_line_indent: f32 = 0,
    paragraph_spacing: f32 = 0,
};

/// A laid-out visual line. Glyph and run ranges are indexes into the owning
/// ParagraphLayout arrays, keeping line objects small and cheap to copy.
pub const ParagraphLine = struct {
    glyph_start: usize,
    glyph_len: usize,
    run_start: usize,
    run_len: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    baseline: f32,
    ascent: f32,
    descent: f32,
    leading: f32,

    pub fn glyphs(self: ParagraphLine, paragraph: ParagraphLayout) []const GlyphPosition {
        return paragraph.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }

    pub fn runs(self: ParagraphLine, paragraph: ParagraphLayout) []const CascadeRun {
        return paragraph.runs[self.run_start .. self.run_start + self.run_len];
    }
};

pub const TextPosition = struct {
    glyph_index: usize,
    cluster: usize,
    trailing: bool = false,
};

pub const TextRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const ParagraphLayout = struct {
    glyphs: []const GlyphPosition,
    runs: []const CascadeRun,
    lines: []const ParagraphLine,
    width: f32,
    height: f32,

    /// Return the closest glyph caret for a point in paragraph coordinates.
    /// This is midpoint-based: clicks in the left half of a glyph choose its
    /// leading edge, and clicks in the right half choose its trailing edge.
    pub fn hitTest(self: ParagraphLayout, x: f32, y: f32) TextPosition {
        if (self.lines.len == 0) return .{ .glyph_index = 0, .cluster = 0 };
        const line_index = self.lineIndexAtY(y);
        const line = self.lines[line_index];
        if (line.glyph_len == 0) return .{ .glyph_index = line.glyph_start, .cluster = 0 };

        const local_x = x - line.x;
        if (local_x <= 0) {
            const glyph = self.glyphs[line.glyph_start];
            return .{ .glyph_index = line.glyph_start, .cluster = glyph.cluster };
        }

        var pen_x: f32 = 0;
        const glyph_end = line.glyph_start + line.glyph_len;
        for (self.glyphs[line.glyph_start..glyph_end], line.glyph_start..) |glyph, glyph_index| {
            const midpoint = pen_x + glyph.x_advance / 2;
            if (local_x < midpoint) {
                return .{ .glyph_index = glyph_index, .cluster = glyph.cluster };
            }
            if (local_x < pen_x + glyph.x_advance) {
                return textPositionAtGlyphTrailingEdge(self, glyph_index);
            }
            pen_x += glyph.x_advance;
        }

        return textPositionAtGlyphTrailingEdge(self, glyph_end - 1);
    }

    /// Convert a logical TextPosition back to a zero-width caret rectangle.
    /// The y/height are taken from the resolved line metrics, not from glyph
    /// bounds, so selections remain visually stable across mixed glyph shapes.
    pub fn caretRect(self: ParagraphLayout, position: TextPosition) TextRect {
        if (self.lines.len == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const glyph_index = @min(position.glyph_index, self.glyphs.len);
        const line = self.lineForCaret(glyph_index);
        return .{
            .x = self.caretXInLine(line, glyph_index, position.trailing),
            .y = line.y,
            .width = 0,
            .height = line.height,
        };
    }

    pub fn selectionRect(self: ParagraphLayout, start: usize, end: usize) TextRect {
        if (self.lines.len == 0 or start == end) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        var buffer: [32]TextRect = undefined;
        const rects = self.selectionRectsInto(&buffer, start, end);
        if (rects.len == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        var found = false;
        var min_x: f32 = std.math.inf(f32);
        var min_y: f32 = std.math.inf(f32);
        var max_x: f32 = -std.math.inf(f32);
        var max_y: f32 = -std.math.inf(f32);

        for (rects) |rect| {
            min_x = @min(min_x, rect.x);
            min_y = @min(min_y, rect.y);
            max_x = @max(max_x, rect.x + rect.width);
            max_y = @max(max_y, rect.y + rect.height);
            found = true;
        }

        if (!found) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        return .{ .x = min_x, .y = min_y, .width = max_x - min_x, .height = max_y - min_y };
    }

    pub fn selectionRects(self: ParagraphLayout, allocator: std.mem.Allocator, start: usize, end: usize) ![]TextRect {
        if (self.lines.len == 0 or start == end) return try allocator.alloc(TextRect, 0);
        var rects = std.ArrayList(TextRect).empty;
        errdefer rects.deinit(allocator);
        const range_start = @min(start, end);
        const range_end = @max(start, end);
        for (self.lines) |line| {
            if (selectionRectForLine(self, line, range_start, range_end)) |rect| {
                try rects.append(allocator, rect);
            }
        }
        return try rects.toOwnedSlice(allocator);
    }

    pub fn selectionRectsInto(self: ParagraphLayout, buffer: []TextRect, start: usize, end: usize) []TextRect {
        if (self.lines.len == 0 or start == end or buffer.len == 0) return buffer[0..0];
        const range_start = @min(start, end);
        const range_end = @max(start, end);
        var count: usize = 0;
        for (self.lines) |line| {
            if (count >= buffer.len) break;
            if (selectionRectForLine(self, line, range_start, range_end)) |rect| {
                buffer[count] = rect;
                count += 1;
            }
        }
        return buffer[0..count];
    }

    pub fn snapToGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var best = clusters[0].byte_start;
        for (clusters) |cluster| {
            const start = cluster.byte_start;
            const end = cluster.byte_start + cluster.byte_len;
            if (byte_pos <= start) {
                best = start;
                break;
            }
            if (byte_pos < end) {
                best = if (byte_pos - start < end - byte_pos) start else end;
                break;
            }
            best = end;
        }
        return self.textPositionForCluster(best);
    }

    pub fn nextGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        for (clusters) |cluster| {
            const end = cluster.byte_start + cluster.byte_len;
            if (end > byte_pos) return self.textPositionForCluster(end);
        }
        return self.textPositionForCluster(clusters[clusters.len - 1].byte_start + clusters[clusters.len - 1].byte_len);
    }

    pub fn previousGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var previous = clusters[0].byte_start;
        for (clusters) |cluster| {
            if (cluster.byte_start >= byte_pos) return self.textPositionForCluster(previous);
            previous = cluster.byte_start;
        }
        return self.textPositionForCluster(previous);
    }

    pub fn snapToWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var best = words[0].byte_start;
        for (words) |word| {
            const start = word.byte_start;
            const end = word.byte_start + word.byte_len;
            if (byte_pos <= start) {
                best = start;
                break;
            }
            if (byte_pos < end) {
                best = if (byte_pos - start < end - byte_pos) start else end;
                break;
            }
            best = end;
        }
        return self.textPositionForCluster(best);
    }

    pub fn nextWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        for (words) |word| {
            const end = word.byte_start + word.byte_len;
            if (end > byte_pos) return self.textPositionForCluster(end);
        }
        return self.textPositionForCluster(words[words.len - 1].byte_start + words[words.len - 1].byte_len);
    }

    pub fn previousWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var previous = words[0].byte_start;
        for (words) |word| {
            if (word.byte_start >= byte_pos) return self.textPositionForCluster(previous);
            previous = word.byte_start;
        }
        return self.textPositionForCluster(previous);
    }

    fn lineIndexAtY(self: ParagraphLayout, y: f32) usize {
        if (y <= self.lines[0].y) return 0;
        for (self.lines, 0..) |line, index| {
            if (y < line.y + line.height) return index;
        }
        return self.lines.len - 1;
    }

    fn textPositionForCluster(self: ParagraphLayout, cluster: usize) TextPosition {
        if (self.glyphs.len == 0) return .{ .glyph_index = 0, .cluster = cluster };
        var nearest_after_index: ?usize = null;
        var nearest_after_cluster: usize = std.math.maxInt(usize);
        var nearest_before_index: usize = 0;
        var nearest_before_end: usize = 0;
        for (self.glyphs, 0..) |glyph, index| {
            const glyph_start = glyph.cluster;
            const glyph_end = glyph_start + @max(glyph.source_byte_len, 1);
            if (cluster == glyph_start) return .{ .glyph_index = index, .cluster = glyph_start };
            if (cluster > glyph_start and cluster < glyph_end) {
                return .{ .glyph_index = index, .cluster = glyph_start, .trailing = cluster - glyph_start >= glyph_end - cluster };
            }
            if (glyph_start > cluster and glyph_start < nearest_after_cluster) {
                nearest_after_index = index;
                nearest_after_cluster = glyph_start;
            }
            if (glyph_end <= cluster and glyph_end >= nearest_before_end) {
                nearest_before_index = index;
                nearest_before_end = glyph_end;
            }
        }
        if (nearest_after_index) |index| {
            return .{ .glyph_index = index, .cluster = self.glyphs[index].cluster };
        }
        return .{ .glyph_index = nearest_before_index, .cluster = cluster, .trailing = true };
    }

    fn lineForCaret(self: ParagraphLayout, glyph_index: usize) ParagraphLine {
        for (self.lines) |line| {
            const line_start = line.glyph_start;
            const line_end = line.glyph_start + line.glyph_len;
            if (glyph_index >= line_start and glyph_index <= line_end) return line;
        }
        return self.lines[self.lines.len - 1];
    }

    fn caretXInLine(self: ParagraphLayout, line: ParagraphLine, glyph_index: usize, trailing: bool) f32 {
        var x = line.x;
        const clamped_index = @min(glyph_index, line.glyph_start + line.glyph_len);
        var index = line.glyph_start;
        while (index < clamped_index) : (index += 1) {
            x += self.glyphs[index].x_advance;
        }
        if (trailing and clamped_index < line.glyph_start + line.glyph_len) {
            x += self.glyphs[clamped_index].x_advance;
        }
        return x;
    }
};

fn positionByteOffset(layout_value: ParagraphLayout, position: TextPosition) usize {
    if (layout_value.glyphs.len == 0) return position.cluster;
    if (position.glyph_index >= layout_value.glyphs.len) return position.cluster;
    const glyph = layout_value.glyphs[position.glyph_index];
    if (!position.trailing) return glyph.cluster;
    return trailingByteOffsetForGlyph(layout_value, position.glyph_index);
}

fn textPositionAtGlyphTrailingEdge(layout_value: ParagraphLayout, glyph_index: usize) TextPosition {
    return .{
        .glyph_index = glyph_index,
        // `TextPosition.cluster` is the byte offset represented by the caret.
        // For a trailing edge this may be beyond the glyph's leading cluster
        // when source metadata folded variation selectors or a GSUB ligature
        // into a single rendered glyph. Keeping the visible hit-test result and
        // the internal byte-offset conversion in sync avoids snapping trailing
        // clicks back to the start of an extended source span.
        .cluster = trailingByteOffsetForGlyph(layout_value, glyph_index),
        .trailing = true,
    };
}

fn trailingByteOffsetForGlyph(layout_value: ParagraphLayout, glyph_index: usize) usize {
    const glyph = layout_value.glyphs[glyph_index];
    const glyph_end = glyph.cluster + @max(glyph.source_byte_len, 1);
    if (glyph_index + 1 < layout_value.glyphs.len) {
        const next_cluster = layout_value.glyphs[glyph_index + 1].cluster;
        if (next_cluster > glyph.cluster) return next_cluster;
    }
    return glyph_end;
}

fn selectionRectForLine(layout_value: ParagraphLayout, line: ParagraphLine, range_start: usize, range_end: usize) ?TextRect {
    const line_start = line.glyph_start;
    const line_end = line.glyph_start + line.glyph_len;
    const overlap_start = @max(range_start, line_start);
    const overlap_end = @min(range_end, line_end);
    if (overlap_start >= overlap_end) return null;

    const x0 = layout_value.caretXInLine(line, overlap_start, false);
    const x1 = layout_value.caretXInLine(line, overlap_end, false);
    return .{
        .x = @min(x0, x1),
        .y = line.y,
        .width = @abs(x1 - x0),
        .height = line.height,
    };
}

pub const FontCascade = struct {
    fonts: []const *const Font,

    pub fn init(fonts: []const *const Font) FontCascade {
        return .{ .fonts = fonts };
    }

    /// Pick the first font that maps the codepoint to a non-zero glyph id.
    /// Glyph id 0 is treated as `.notdef`, so it does not count as coverage.
    pub fn selectFont(self: FontCascade, codepoint: u21) !usize {
        if (self.fonts.len == 0) return error.EmptyFontCascade;
        for (self.fonts, 0..) |font, index| {
            if (try font.glyphIndex(codepoint) != 0) return index;
        }
        return 0;
    }
};

/// Caches codepoint-to-font decisions for a cascade. This is separate from the
/// glyph-id cache because the same codepoint can map to different glyph ids in
/// different fonts, while fallback only needs the winning font index.
pub const FontFallbackCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(u21, usize),
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FontFallbackCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u21, usize).init(allocator),
        };
    }

    pub fn deinit(self: *FontFallbackCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *FontFallbackCache) void {
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn selectFont(self: *FontFallbackCache, cascade: FontCascade, codepoint: u21) !usize {
        if (self.entries.get(codepoint)) |font_index| {
            self.hits += 1;
            return font_index;
        }
        self.misses += 1;
        const font_index = try cascade.selectFont(codepoint);
        try self.entries.put(codepoint, font_index);
        return font_index;
    }

    pub fn selectFontWithGlyphCache(self: *FontFallbackCache, cascade: FontCascade, glyph_index_cache: *GlyphIndexCache, codepoint: u21) !usize {
        if (self.entries.get(codepoint)) |font_index| {
            self.hits += 1;
            return font_index;
        }
        self.misses += 1;
        const font_index = try selectFontUsingGlyphCache(cascade, glyph_index_cache, codepoint);
        try self.entries.put(codepoint, font_index);
        return font_index;
    }
};

pub const GlyphMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

const GlyphMetricsKey = struct {
    font_addr: usize,
    glyph_id: GlyphId,
};

pub const GlyphMetricsCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphMetricsKey, GlyphMetrics),
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphMetricsCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphMetricsKey, GlyphMetrics).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphMetricsCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphMetricsCache) void {
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn horizontalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !GlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id);
        if (self.entries.get(key)) |metrics| {
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = try font.horizontalMetrics(glyph_id);
        const metrics = GlyphMetrics{
            .advance_width = raw.advance_width,
            .left_side_bearing = raw.left_side_bearing,
        };
        try self.entries.put(key, metrics);
        return metrics;
    }
};

const GlyphIndexKey = struct {
    font_addr: usize,
    codepoint: u21,
};

pub const GlyphIndexCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphIndexKey, GlyphId),
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphIndexCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphIndexKey, GlyphId).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphIndexCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphIndexCache) void {
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn glyphIndex(self: *GlyphIndexCache, font: *const Font, codepoint: u21) !GlyphId {
        const key = glyphIndexKey(font, codepoint);
        if (self.entries.get(key)) |glyph_id| {
            self.hits += 1;
            return glyph_id;
        }
        self.misses += 1;
        const glyph_id = try font.glyphIndex(codepoint);
        try self.entries.put(key, glyph_id);
        return glyph_id;
    }
};

pub const LayoutBuffer = struct {
    allocator: std.mem.Allocator,
    glyphs: std.ArrayList(GlyphPosition) = .empty,
    runs: std.ArrayList(CascadeRun) = .empty,
    lines: std.ArrayList(ParagraphLine) = .empty,
    script_runs: std.ArrayList(ScriptedRun) = .empty,

    pub fn init(allocator: std.mem.Allocator) LayoutBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LayoutBuffer) void {
        self.script_runs.deinit(self.allocator);
        self.lines.deinit(self.allocator);
        self.runs.deinit(self.allocator);
        self.glyphs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *LayoutBuffer) void {
        self.glyphs.clearRetainingCapacity();
        self.runs.clearRetainingCapacity();
        self.lines.clearRetainingCapacity();
        self.script_runs.clearRetainingCapacity();
    }

    pub fn run(self: *const LayoutBuffer, font: *const Font, font_size: f32) GlyphRun {
        return .{ .font = font, .font_size = font_size, .glyphs = self.glyphs.items };
    }

    pub fn shapedText(self: *const LayoutBuffer) ShapedText {
        return .{ .glyphs = self.glyphs.items, .runs = self.runs.items };
    }

    pub fn scriptedText(self: *const LayoutBuffer) ScriptedText {
        return .{
            .glyphs = self.glyphs.items,
            .font_runs = self.runs.items,
            .script_runs = self.script_runs.items,
        };
    }

    pub fn paragraphLayout(self: *const LayoutBuffer) ParagraphLayout {
        var max_width: f32 = 0;
        var height: f32 = 0;
        for (self.lines.items) |line| {
            max_width = @max(max_width, line.x + line.width);
            height = @max(height, line.y + line.height);
        }
        return .{
            .glyphs = self.glyphs.items,
            .runs = self.runs.items,
            .lines = self.lines.items,
            .width = max_width,
            .height = height,
        };
    }
};

pub const TextShaper = struct {
    pub fn shapeUtf8(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !GlyphRun {
        return try shapeUtf8WithOptions(font, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8WithOptions(font: *const Font, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        try validateShapingInput(text, font_size, options);
        buffer.clear();
        try shapeSegmentInto(font, null, null, buffer, text, font_size, 0, lookupOptionsForText(text, options));
        try applyBidiVisualOrder(buffer, text, options.direction, font);
        return buffer.run(font, font_size);
    }

    pub fn shapeUtf8Cascade(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeWithOptions(cascade, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeWithOptions(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeCachedWithOptions(cascade, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeCached(cascade: FontCascade, cache: *FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeCachedWithOptions(cascade, cache, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeCachedWithOptions(cascade: FontCascade, cache: ?*FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeFullyCachedWithOptions(cascade, cache, null, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeFullyCached(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32) !ShapedText {
        return try shapeUtf8CascadeFullyCachedWithOptions(cascade, fallback_cache, metrics_cache, null, buffer, text, font_size, .{});
    }

    pub fn shapeUtf8CascadeFullyCachedWithOptions(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        return try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8CascadeWithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ShapedText {
        try validateShapingInput(text, font_size, options);
        const cache_key = if (shaped_cache != null) ShapedRunCache.key(cascade, text, font_size, options) else undefined;
        if (shaped_cache) |cache| {
            if (try cache.load(cache_key, buffer)) |cached| return cached;
        }
        buffer.clear();
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;

        // Split only when the selected fallback font changes. Each segment can
        // then be shaped independently through its own font while preserving a
        // single flat glyph stream for paragraph layout and rendering.
        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        var segment_start: usize = 0;
        var segment_font_index: ?usize = null;
        var pen_x: f32 = 0;

        while (it.i < text.len) {
            const cluster = it.i;
            const codepoint = it.nextCodepoint() orelse break;
            if (isVariationSelector(codepoint)) {
                // Keep variation selectors in the current segment so cmap
                // format 14 can be applied by the font that shaped the base
                // scalar. Selecting fallback for the selector itself would
                // split the run and discard the variation relationship.
                continue;
            }
            const variation_selector = nextVariationSelector(text, it.i);
            const font_index = if (variation_selector) |selector|
                try selectFontForVariation(cascade, fallback_cache, glyph_index_cache, codepoint, selector)
            else
                try selectFontWithOptionalCache(cascade, fallback_cache, glyph_index_cache, codepoint);
            if (segment_font_index == null) {
                segment_start = cluster;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                pen_x = try appendCascadeRun(cascade.fonts[segment_font_index.?], metrics_cache, glyph_index_cache, segment_font_index.?, buffer, text[segment_start..cluster], font_size, segment_start, pen_x, lookupOptionsForText(text[segment_start..cluster], options));
                segment_start = cluster;
                segment_font_index = font_index;
            }
        }

        if (segment_font_index) |font_index| {
            _ = try appendCascadeRun(cascade.fonts[font_index], metrics_cache, glyph_index_cache, font_index, buffer, text[segment_start..], font_size, segment_start, pen_x, lookupOptionsForText(text[segment_start..], options));
        }

        try applyBidiVisualOrder(buffer, text, options.direction, null);
        const shaped = buffer.shapedText();
        if (shaped_cache) |cache| {
            try cache.store(cache_key, shaped);
        }
        return shaped;
    }

    pub fn shapeUtf8ScriptRuns(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ScriptedText {
        try validateShapingInput(text, font_size, options);
        try shapeScriptRunsInto(cascade, buffer, text, font_size, options);
        try applyBidiVisualOrder(buffer, text, options.direction, null);
        try buildScriptRuns(buffer, text, options.direction, options.language_tag);
        return buffer.scriptedText();
    }

    pub fn layoutParagraphUtf8(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8WithOptions(cascade, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8WithOptions(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8CachedWithOptions(cascade, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8Cached(cascade: FontCascade, cache: *FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8CachedWithOptions(cascade, cache, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8CachedWithOptions(cascade: FontCascade, cache: ?*FontFallbackCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8FullyCachedWithOptions(cascade, cache, null, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8FullyCached(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        return try layoutParagraphUtf8FullyCachedWithOptions(cascade, fallback_cache, metrics_cache, null, buffer, text, font_size, options);
    }

    pub fn layoutParagraphUtf8FullyCachedWithOptions(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try validateParagraphOptions(options);
        // Paragraph layout is deliberately staged: shape first, then line-wrap
        // the finished glyph advances. That keeps OpenType substitution and
        // positioning independent from wrapping policy.
        _ = try shapeUtf8CascadeFullyCachedWithOptions(cascade, fallback_cache, metrics_cache, glyph_index_cache, buffer, text, font_size, .{ .direction = options.direction });
        try buildParagraphLines(buffer, text, options, defaultBaselineMetrics(cascade.fonts[0], font_size));
        return buffer.paragraphLayout();
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try validateParagraphOptions(options);
        _ = try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, shaped_cache, buffer, text, font_size, .{ .direction = options.direction });
        try buildParagraphLines(buffer, text, options, defaultBaselineMetrics(cascade.fonts[0], font_size));
        return buffer.paragraphLayout();
    }

    pub fn measureParagraphUtf8(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !TextMetrics {
        const paragraph = try layoutParagraphUtf8(cascade, buffer, text, font_size, options);
        return textMetricsFromParagraph(paragraph);
    }

    pub fn measureParagraphsUtf8(allocator: std.mem.Allocator, cascade: FontCascade, texts: []const []const u8, font_size: f32, options: ParagraphOptions) ![]TextMetrics {
        var buffer = LayoutBuffer.init(allocator);
        defer buffer.deinit();
        const metrics = try allocator.alloc(TextMetrics, texts.len);
        errdefer allocator.free(metrics);
        for (texts, 0..) |text, index| {
            metrics[index] = try measureParagraphUtf8(cascade, &buffer, text, font_size, options);
        }
        return metrics;
    }
};

fn textMetricsFromParagraph(paragraph: ParagraphLayout) TextMetrics {
    if (paragraph.lines.len == 0) {
        return .{ .width = 0, .height = 0, .baseline = 0, .ascent = 0, .descent = 0, .leading = 0 };
    }
    const first = paragraph.lines[0];
    return .{
        .width = paragraph.width,
        .height = paragraph.height,
        .baseline = first.y + first.baseline,
        .ascent = first.ascent,
        .descent = first.descent,
        .leading = first.leading,
    };
}

fn validateShapingInput(text: []const u8, font_size: f32, options: ShapeOptions) !void {
    try validateShapingUtf8(text);
    try validateShapingFontSize(font_size);
    try validateFeatureOverrides(options.features);
}

fn validateShapingUtf8(text: []const u8) !void {
    // The shaping pipeline uses std.unicode.Utf8Iterator, whose decode helpers
    // assume a validated byte stream and mark malformed input as unreachable.
    // Keep every public `*Utf8` entry point total by rejecting bad source bytes
    // before cache keys are built or layout buffers are mutated.
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
}

fn validateShapingFontSize(font_size: f32) !void {
    // A public shaping size becomes a scale factor, participates in shaped-run
    // cache keys, and is copied onto glyph runs. Non-finite or non-positive
    // sizes would produce NaN/Inf advances (or direction-dependent zero-width
    // runs) that are hard for layout, hit testing, and renderers to handle
    // consistently, so reject them before caches or buffers observe the call.
    if (!std.math.isFinite(font_size) or font_size <= 0) return error.InvalidFontSize;
}

fn validateFeatureOverrides(features: []const unicode.FeatureOverride) !void {
    for (features, 0..) |feature, index| {
        // Feature tags are public shaping controls, not font bytes. Require a
        // real OpenType tag and one decision per tag before shape-plan keys or
        // glyph buffers observe the request; otherwise duplicate entries would
        // hash as distinct cache entries while GSUB/GPOS only honor the first.
        if (!isOpenTypeFeatureTag(feature.tag)) return error.InvalidFeatureTag;
        for (features[0..index]) |previous| {
            if (previous.tag == feature.tag) return error.DuplicateFeatureTag;
        }
    }
}

fn isOpenTypeFeatureTag(tag_value: u32) bool {
    inline for (0..4) |shift_index| {
        const shift: u5 = @intCast((3 - shift_index) * 8);
        const byte: u8 = @intCast((tag_value >> shift) & 0xff);
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}

fn validateParagraphOptions(options: ParagraphOptions) !void {
    // Paragraph options are applied after shaping, but they still feed public
    // layout geometry, hit testing, and measurements. Reject non-finite values
    // before shaping or cache mutation so NaN/Inf cannot poison line widths,
    // alignments, tab stops, or baseline metrics. Infinite max_width is a
    // supported shorthand for unbounded layout; NaN is not a usable geometry
    // input because every comparison against it fails.
    if (std.math.isNan(options.max_width)) return error.InvalidParagraphOptions;
    if (options.line_height) |line_height| {
        if (!std.math.isFinite(line_height) or line_height <= 0) return error.InvalidParagraphOptions;
    }
    if (!std.math.isFinite(options.letter_spacing) or
        !std.math.isFinite(options.word_spacing) or
        !std.math.isFinite(options.first_line_indent) or
        !std.math.isFinite(options.paragraph_spacing))
    {
        return error.InvalidParagraphOptions;
    }
}

fn shapeScriptRunsInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !void {
    buffer.clear();
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    const script_runs = try unicode.itemizeScriptRuns(buffer.allocator, text);
    defer buffer.allocator.free(script_runs);

    var pen_x: f32 = 0;
    for (script_runs) |script_run| {
        const run_text = text[script_run.byte_start .. script_run.byte_start + script_run.byte_len];
        pen_x = try shapeCascadeSegmentInto(
            cascade,
            buffer,
            run_text,
            font_size,
            script_run.byte_start,
            pen_x,
            .{
                .script_tag = unicode.openTypeScriptTag(script_run.script),
                .language_tag = effectiveLanguageTag(run_text, options),
                .features = options.features,
            },
        );
    }
}

fn shapeCascadeSegmentInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen_x: f32, lookup_options: LookupOptions) !f32 {
    // Script itemization happens outside this helper. This pass only performs
    // fallback segmentation inside that script run, so each append keeps the
    // same OpenType script/language lookup selection.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var segment_start: usize = 0;
    var segment_font_index: ?usize = null;
    var next_pen_x = pen_x;

    while (it.i < text.len) {
        const cluster = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        if (isVariationSelector(codepoint)) continue;
        const variation_selector = nextVariationSelector(text, it.i);
        const font_index = if (variation_selector) |selector|
            try selectFontForVariation(cascade, null, null, codepoint, selector)
        else
            try cascade.selectFont(codepoint);
        if (segment_font_index == null) {
            segment_start = cluster;
            segment_font_index = font_index;
        } else if (segment_font_index.? != font_index) {
            next_pen_x = try appendCascadeRun(cascade.fonts[segment_font_index.?], null, null, segment_font_index.?, buffer, text[segment_start..cluster], font_size, cluster_base + segment_start, next_pen_x, lookup_options);
            segment_start = cluster;
            segment_font_index = font_index;
        }
    }

    if (segment_font_index) |font_index| {
        next_pen_x = try appendCascadeRun(cascade.fonts[font_index], null, null, font_index, buffer, text[segment_start..], font_size, cluster_base + segment_start, next_pen_x, lookup_options);
    }
    return next_pen_x;
}

fn nextVariationSelector(text: []const u8, byte_index: usize) ?u21 {
    if (byte_index >= text.len) return null;
    var lookahead = std.unicode.Utf8Iterator{ .bytes = text, .i = byte_index };
    const selector = lookahead.nextCodepoint() orelse return null;
    return if (isVariationSelector(selector)) selector else null;
}

fn selectFontForVariation(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, glyph_index_cache: ?*GlyphIndexCache, codepoint: u21, variation_selector: u21) !usize {
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    for (cascade.fonts, 0..) |font, index| {
        if (try font.variationGlyphIndex(codepoint, variation_selector) != null) return index;
    }
    return try selectFontWithOptionalCache(cascade, fallback_cache, glyph_index_cache, codepoint);
}

fn selectFontUsingGlyphCache(cascade: FontCascade, glyph_index_cache: *GlyphIndexCache, codepoint: u21) !usize {
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    for (cascade.fonts, 0..) |font, index| {
        if (try glyph_index_cache.glyphIndex(font, codepoint) != 0) return index;
    }
    return 0;
}

fn selectFontWithOptionalCache(cascade: FontCascade, cache: ?*FontFallbackCache, glyph_index_cache: ?*GlyphIndexCache, codepoint: u21) !usize {
    if (cache) |fallback_cache| {
        if (glyph_index_cache) |glyph_cache| return try fallback_cache.selectFontWithGlyphCache(cascade, glyph_cache, codepoint);
        return try fallback_cache.selectFont(cascade, codepoint);
    }
    if (glyph_index_cache) |glyph_cache| return try selectFontUsingGlyphCache(cascade, glyph_cache, codepoint);
    return try cascade.selectFont(codepoint);
}

fn buildScriptRuns(buffer: *LayoutBuffer, text: []const u8, direction: TextDirection, language_tag: ?unicode.OpenTypeLanguageTag) !void {
    buffer.script_runs.clearRetainingCapacity();
    const script_runs = try unicode.itemizeScriptRuns(buffer.allocator, text);
    defer buffer.allocator.free(script_runs);

    if (direction == .ltr) {
        for (script_runs) |script_run| {
            try appendScriptedRunForByteRange(buffer, text, script_run, language_tag);
        }
    } else {
        var index = script_runs.len;
        while (index > 0) {
            index -= 1;
            try appendScriptedRunForByteRange(buffer, text, script_runs[index], language_tag);
        }
    }
}

fn appendScriptedRunForByteRange(buffer: *LayoutBuffer, text: []const u8, script_run: unicode.ScriptRun, language_tag: ?unicode.OpenTypeLanguageTag) !void {
    const byte_start = script_run.byte_start;
    const byte_end = script_run.byte_start + script_run.byte_len;
    var glyph_start: ?usize = null;
    var glyph_end: usize = 0;
    for (buffer.glyphs.items, 0..) |glyph, index| {
        if (glyph.cluster < byte_start or glyph.cluster >= byte_end) continue;
        if (glyph_start == null) glyph_start = index;
        glyph_end = index + 1;
    }
    if (glyph_start == null) return;
    try buffer.script_runs.append(buffer.allocator, .{
        .script = script_run.script,
        .script_tag = unicode.openTypeScriptTag(script_run.script),
        .language_tag = language_tag orelse unicode.inferOpenTypeLanguageTag(text[byte_start..byte_end]),
        .glyph_start = glyph_start.?,
        .glyph_len = glyph_end - glyph_start.?,
        .byte_start = byte_start,
        .byte_len = script_run.byte_len,
    });
}

fn applyBidiVisualOrder(buffer: *LayoutBuffer, text: []const u8, direction: TextDirection, single_font: ?*const Font) !void {
    if (buffer.glyphs.items.len == 0) return;
    const base_direction: unicode.BidiClass = if (direction == .rtl) .rtl else .ltr;
    var bidi_map = try unicode.buildBidiMap(buffer.allocator, text, base_direction);
    defer bidi_map.deinit();
    if (bidi_map.items.len == 0) return;

    const old_runs = try buffer.allocator.dupe(CascadeRun, buffer.runs.items);
    defer buffer.allocator.free(old_runs);
    const old_glyphs = try buffer.allocator.dupe(GlyphPosition, buffer.glyphs.items);
    defer buffer.allocator.free(old_glyphs);
    var glyph_run_indices = try buffer.allocator.alloc(usize, old_glyphs.len);
    defer buffer.allocator.free(glyph_run_indices);
    for (glyph_run_indices) |*slot| slot.* = 0;
    for (old_runs, 0..) |run, run_index| {
        const end = @min(old_glyphs.len, run.glyph_start + run.glyph_len);
        if (run.glyph_start >= end) continue;
        for (glyph_run_indices[run.glyph_start..end]) |*slot| slot.* = run_index;
    }

    const seen = try buffer.allocator.alloc(bool, old_glyphs.len);
    defer buffer.allocator.free(seen);
    @memset(seen, false);
    var visual_glyphs: std.ArrayList(GlyphPosition) = .empty;
    defer visual_glyphs.deinit(buffer.allocator);
    var visual_run_indices: std.ArrayList(usize) = .empty;
    defer visual_run_indices.deinit(buffer.allocator);

    for (bidi_map.items) |item| {
        try appendVisualGlyphsForBidiItem(
            buffer.allocator,
            old_glyphs,
            old_runs,
            single_font,
            glyph_run_indices,
            seen,
            item,
            &visual_glyphs,
            &visual_run_indices,
        );
    }
    // GSUB ligatures or skipped variation selectors can make glyph count differ
    // from bidi scalar count. Preserve any unmatched glyphs in source order
    // rather than dropping them when the compact bidi map lacks a one-to-one
    // visual item.
    for (old_glyphs, 0..) |_, glyph_index| {
        if (seen[glyph_index]) continue;
        try appendVisualGlyph(buffer.allocator, old_glyphs, old_runs, single_font, glyph_run_indices, seen, glyph_index, null, &visual_glyphs, &visual_run_indices);
    }
    if (visual_glyphs.items.len != old_glyphs.len) return error.InvalidBidiMap;

    var changed = false;
    for (old_glyphs, visual_glyphs.items) |old, visual| {
        if (old.cluster != visual.cluster or old.glyph_id != visual.glyph_id or old.codepoint != visual.codepoint) {
            changed = true;
            break;
        }
    }
    if (!changed) return;

    buffer.glyphs.clearRetainingCapacity();
    try buffer.glyphs.appendSlice(buffer.allocator, visual_glyphs.items);
    try rebuildRunsForVisualGlyphs(buffer, old_runs, visual_run_indices.items);
    recomputeRunOffsets(buffer);
}

fn appendVisualGlyphsForBidiItem(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: []const CascadeRun,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    for (glyphs, 0..) |glyph, glyph_index| {
        if (seen[glyph_index]) continue;
        if (glyph.cluster != item.byte_start) continue;
        const visual_codepoint = if (@max(glyph.source_byte_len, 1) == item.byte_len)
            item.visual_codepoint
        else
            null;
        try appendVisualGlyph(allocator, glyphs, old_runs, single_font, glyph_run_indices, seen, glyph_index, visual_codepoint, out_glyphs, out_run_indices);
    }
}

fn appendVisualGlyph(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    old_runs: []const CascadeRun,
    single_font: ?*const Font,
    glyph_run_indices: []const usize,
    seen: []bool,
    glyph_index: usize,
    visual_codepoint: ?u21,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    seen[glyph_index] = true;
    var glyph = glyphs[glyph_index];
    if (visual_codepoint) |codepoint| mirror: {
        if (codepoint == glyph.codepoint) break :mirror;
        const font = visualGlyphFont(old_runs, single_font, glyph_run_indices[glyph_index]) orelse break :mirror;
        const mirrored_glyph = font.glyphIndex(codepoint) catch break :mirror;
        if (mirrored_glyph == 0) break :mirror;
        // Unicode bidi mirroring is a visual substitution.  Keep the shaped
        // positioning deltas from the logical glyph because this pass runs
        // after GSUB/GPOS, but use the mirrored glyph when the same cascade font
        // can render it so parentheses/brackets match Unicode visual order.
        glyph.codepoint = codepoint;
        glyph.glyph_id = mirrored_glyph;
    }
    try out_glyphs.append(allocator, glyph);
    try out_run_indices.append(allocator, glyph_run_indices[glyph_index]);
}

fn visualGlyphFont(old_runs: []const CascadeRun, single_font: ?*const Font, run_index: usize) ?*const Font {
    if (run_index < old_runs.len) return old_runs[run_index].font;
    return single_font;
}

fn rebuildRunsForVisualGlyphs(buffer: *LayoutBuffer, old_runs: []const CascadeRun, visual_run_indices: []const usize) !void {
    buffer.runs.clearRetainingCapacity();
    if (visual_run_indices.len == 0 or old_runs.len == 0) return;
    var start: usize = 0;
    var current_run_index = visual_run_indices[0];
    var i: usize = 1;
    while (i <= visual_run_indices.len) : (i += 1) {
        if (i < visual_run_indices.len and visual_run_indices[i] == current_run_index) continue;
        if (current_run_index >= old_runs.len) return error.InvalidBidiMap;
        const source_run = old_runs[current_run_index];
        try buffer.runs.append(buffer.allocator, .{
            .font = source_run.font,
            .font_index = source_run.font_index,
            .font_size = source_run.font_size,
            .glyph_start = start,
            .glyph_len = i - start,
            .x_offset = 0,
        });
        if (i < visual_run_indices.len) {
            start = i;
            current_run_index = visual_run_indices[i];
        }
    }
}

fn recomputeRunOffsets(buffer: *LayoutBuffer) void {
    var x_offset: f32 = 0;
    for (buffer.runs.items) |*run| {
        run.x_offset = x_offset;
        x_offset += lineWidth(buffer.glyphs.items[run.glyph_start .. run.glyph_start + run.glyph_len]);
    }
}

fn buildParagraphLines(buffer: *LayoutBuffer, text: []const u8, options: ParagraphOptions, default_metrics: BaselineMetrics) !void {
    buffer.lines.clearRetainingCapacity();
    const line_height = options.line_height orelse default_metrics.lineHeight();
    const line_metrics = metricsForLineHeight(default_metrics, line_height);
    const max_width = if (options.max_width > 0) options.max_width else std.math.inf(f32);
    const alignment = defaultAlignment(options);
    var line_start: usize = 0;
    var line_width: f32 = 0;
    var last_break: ?usize = null;
    var width_at_break: f32 = 0;
    var y: f32 = 0;
    var index: usize = 0;
    var line_in_paragraph: usize = 0;
    const max_lines = options.max_lines orelse std.math.maxInt(usize);
    const space_advance = defaultSpaceAdvance(buffer.glyphs.items);
    const tab_stop = @as(f32, @floatFromInt(@max(1, options.tab_width))) * space_advance;
    const grapheme_clusters = try unicode.itemizeGraphemeClusters(buffer.allocator, text);
    defer buffer.allocator.free(grapheme_clusters);
    const line_breaks = try unicode.itemizeLineBreaks(buffer.allocator, text);
    defer buffer.allocator.free(line_breaks);
    var line_break_index: usize = 0;

    // Greedy line breaking tracks the most recent soft break. When a line
    // overflows, it prefers that break; otherwise it breaks at the overflowing
    // grapheme cluster so long words and CJK runs still make progress. Falling
    // back at grapheme boundaries is critical for clusters that shape into
    // multiple glyphs, such as base+combining-mark sequences when a font lacks
    // mark attachment: splitting inside that cluster would put one user-visible
    // character on two different lines.
    glyph_loop: while (index < buffer.glyphs.items.len) : (index += 1) {
        var glyph = &buffer.glyphs.items[index];
        if (glyph.codepoint == '\n' or glyph.codepoint == '\r') {
            try appendParagraphLine(buffer, line_start, index, line_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
            if (buffer.lines.items.len >= max_lines) {
                try truncateParagraphLines(buffer, max_lines, options.ellipsis, max_width, alignment, true);
                return;
            }
            y += line_height + options.paragraph_spacing;
            const break_end_index = if (glyph.codepoint == '\r' and index + 1 < buffer.glyphs.items.len and buffer.glyphs.items[index + 1].codepoint == '\n') index + 2 else index + 1;
            consumeLineBreaksThrough(line_breaks, &line_break_index, glyphSourceEnd(buffer.glyphs.items[break_end_index - 1]));
            line_start = break_end_index;
            line_width = 0;
            last_break = null;
            width_at_break = 0;
            line_in_paragraph = 0;
            index = break_end_index - 1;
            continue :glyph_loop;
        }

        if (glyph.codepoint == '\t') {
            // Tabs are resolved during layout because their width depends on the
            // current line pen position, not on font metrics alone.
            glyph.x_advance = tabAdvance(line_width, tab_stop, space_advance);
        }
        glyph.x_advance += spacingForGlyph(glyph.codepoint, options);
        line_width += glyph.x_advance;
        const current_line_limit = lineWidthLimit(line_in_paragraph, max_width, options);
        if (line_width > current_line_limit and index + 1 > line_start) {
            const overflow_break = chooseOverflowBreak(buffer.glyphs.items, grapheme_clusters, index, line_start, last_break);
            if (overflow_break.defer_until_cluster_end) continue;
            const break_end = overflow_break.index;
            const break_width = if (overflow_break.uses_current_discardable)
                line_width - glyph.x_advance
            else if (last_break != null and break_end == last_break.?)
                width_at_break
            else
                lineWidth(buffer.glyphs.items[line_start..break_end]);
            try appendParagraphLine(buffer, line_start, break_end, break_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
            if (buffer.lines.items.len >= max_lines) {
                try truncateParagraphLines(buffer, max_lines, options.ellipsis, max_width, alignment, true);
                return;
            }
            y += line_height;
            line_in_paragraph += 1;
            line_start = break_end;
            trimLeadingSoftBreaks(buffer.glyphs.items, &line_start);
            line_width = lineWidth(buffer.glyphs.items[line_start .. index + 1]);
            last_break = null;
            width_at_break = 0;
        }
        const glyph_source_end = glyphSourceEnd(glyph.*);
        while (line_break_index < line_breaks.len and line_breaks[line_break_index].byte_offset <= glyph_source_end) {
            const line_break = line_breaks[line_break_index];
            line_break_index += 1;
            switch (line_break.kind) {
                .soft => recordSoftLineBreak(buffer.glyphs.items, line_break.byte_offset, index, line_start, line_width, &last_break, &width_at_break),
                .hard => {},
            }
        }
    }

    try appendParagraphLine(buffer, line_start, buffer.glyphs.items.len, line_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
    try truncateParagraphLines(buffer, max_lines, options.ellipsis, max_width, alignment, false);
}

const OverflowBreak = struct {
    index: usize,
    uses_current_discardable: bool = false,
    defer_until_cluster_end: bool = false,
};

fn chooseOverflowBreak(glyphs: []const GlyphPosition, grapheme_clusters: []const unicode.GraphemeCluster, index: usize, line_start: usize, last_break: ?usize) OverflowBreak {
    if (isDiscardableBreak(glyphs[index].codepoint)) return .{ .index = index, .uses_current_discardable = true };
    if (last_break != null and last_break.? > line_start) return .{ .index = last_break.?, .uses_current_discardable = false };
    return graphemeOverflowBreak(glyphs, grapheme_clusters, index, line_start);
}

fn recordSoftLineBreak(glyphs: []const GlyphPosition, byte_offset: usize, index: usize, line_start: usize, line_width: f32, last_break: *?usize, width_at_break: *f32) void {
    if (glyphs.len == 0) return;
    const current = glyphs[index];
    if (isDiscardableBreak(current.codepoint) and glyphSourceEnd(current) == byte_offset) {
        if (index > line_start) {
            last_break.* = index;
            width_at_break.* = line_width - current.x_advance;
        }
        return;
    }
    const break_index = glyphIndexForSourceBoundary(glyphs, byte_offset, line_start, index + 1) orelse @min(index + 1, glyphs.len);
    if (break_index > line_start) {
        last_break.* = break_index;
        width_at_break.* = lineWidth(glyphs[line_start..break_index]);
    }
}

fn consumeLineBreaksThrough(line_breaks: []const unicode.LineBreak, line_break_index: *usize, byte_offset: usize) void {
    while (line_break_index.* < line_breaks.len and line_breaks[line_break_index.*].byte_offset <= byte_offset) {
        line_break_index.* += 1;
    }
}

fn graphemeOverflowBreak(glyphs: []const GlyphPosition, grapheme_clusters: []const unicode.GraphemeCluster, index: usize, line_start: usize) OverflowBreak {
    const cluster_start = glyphClusterStart(glyphs[index]);
    const line_cluster_start = glyphClusterStart(glyphs[line_start]);
    const current_cluster = graphemeClusterContaining(grapheme_clusters, cluster_start) orelse return .{ .index = index + 1 };
    const current_cluster_start = current_cluster.byte_start;
    const current_cluster_end = current_cluster.byte_start + current_cluster.byte_len;

    if (current_cluster_start > line_cluster_start) {
        return .{ .index = glyphIndexForSourceBoundary(glyphs, current_cluster_start, line_start, index) orelse index };
    }
    if (glyphSourceEnd(glyphs[index]) >= current_cluster_end) {
        return .{ .index = index + 1 };
    }
    return .{ .index = index, .defer_until_cluster_end = true };
}

fn glyphClusterStart(glyph: GlyphPosition) usize {
    return glyph.cluster;
}

fn glyphSourceEnd(glyph: GlyphPosition) usize {
    return glyph.cluster + @max(glyph.source_byte_len, 1);
}

fn graphemeClusterContaining(clusters: []const unicode.GraphemeCluster, byte_offset: usize) ?unicode.GraphemeCluster {
    for (clusters) |cluster| {
        const end = cluster.byte_start + cluster.byte_len;
        if (byte_offset >= cluster.byte_start and byte_offset < end) return cluster;
    }
    return null;
}

fn glyphIndexForSourceBoundary(glyphs: []const GlyphPosition, boundary: usize, line_start: usize, fallback: usize) ?usize {
    var index = line_start + 1;
    while (index < glyphs.len and index <= fallback) : (index += 1) {
        if (glyphClusterStart(glyphs[index]) >= boundary) return index;
    }
    if (glyphs.len != 0 and fallback >= glyphs.len and boundary >= glyphSourceEnd(glyphs[glyphs.len - 1])) return glyphs.len;
    return null;
}

fn defaultAlignment(options: ParagraphOptions) TextAlign {
    if (options.direction == .rtl and options.alignment == .left) return .right;
    return options.alignment;
}

fn lineIndent(line_index: usize, options: ParagraphOptions) f32 {
    if (line_index == 0) return @max(0, options.first_line_indent);
    return 0;
}

fn lineWidthLimit(line_index: usize, max_width: f32, options: ParagraphOptions) f32 {
    return lineWidthLimitForIndent(max_width, lineIndent(line_index, options));
}

fn lineWidthLimitForIndent(max_width: f32, indent: f32) f32 {
    if (!std.math.isFinite(max_width)) return max_width;
    return @max(0, max_width - indent);
}

fn truncateParagraphLines(buffer: *LayoutBuffer, max_lines: usize, ellipsis: bool, max_width: f32, alignment: TextAlign, content_omitted: bool) !void {
    if (buffer.lines.items.len < max_lines or (buffer.lines.items.len == max_lines and !content_omitted)) return;
    if (max_lines == 0) {
        buffer.lines.clearRetainingCapacity();
        buffer.runs.clearRetainingCapacity();
        buffer.glyphs.clearRetainingCapacity();
        return;
    }

    buffer.lines.shrinkRetainingCapacity(max_lines);
    const last_line = &buffer.lines.items[max_lines - 1];
    const keep_glyphs = last_line.glyph_start + last_line.glyph_len;
    buffer.glyphs.shrinkRetainingCapacity(keep_glyphs);
    trimRunsToGlyphCount(buffer, keep_glyphs);

    if (ellipsis and content_omitted and keep_glyphs > 0) {
        try appendEllipsisToLastLine(buffer, max_width, alignment);
    }
}

fn trimRunsToGlyphCount(buffer: *LayoutBuffer, glyph_count: usize) void {
    // Truncation can cut through the last cascade run. Keep surviving run
    // ranges consistent with the shortened glyph array and each line's range.
    var run_count: usize = 0;
    for (buffer.runs.items) |*run| {
        if (run.glyph_start >= glyph_count) break;
        if (run.glyph_start + run.glyph_len > glyph_count) {
            run.glyph_len = glyph_count - run.glyph_start;
        }
        run_count += 1;
    }
    buffer.runs.shrinkRetainingCapacity(run_count);
    for (buffer.lines.items) |*line| {
        const run_range = runRangeForGlyphs(buffer.runs.items, line.glyph_start, line.glyph_start + line.glyph_len);
        line.run_start = run_range.start;
        line.run_len = run_range.len;
    }
}

fn appendEllipsisToLastLine(buffer: *LayoutBuffer, max_width: f32, alignment: TextAlign) !void {
    if (buffer.lines.items.len == 0 or buffer.runs.items.len == 0) return;
    const line = &buffer.lines.items[buffer.lines.items.len - 1];
    const ellipsis_count: usize = 3;
    const run_index = line.run_start + line.run_len - 1;
    var run = &buffer.runs.items[run_index];
    const dot_metrics = try run.font.horizontalMetrics(try run.font.glyphIndex('.'));
    const dot_advance = @as(f32, @floatFromInt(dot_metrics.advance_width)) * (run.font_size / @as(f32, @floatFromInt(run.font.units_per_em)));
    const ellipsis_width = dot_advance * @as(f32, @floatFromInt(ellipsis_count));
    const width_limit = if (std.math.isFinite(max_width)) max_width else std.math.inf(f32);

    while (line.glyph_len > 0 and line.width + ellipsis_width > width_limit) {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        if (run.glyph_len > 0) run.glyph_len -= 1;
    }

    const dot_glyph = try run.font.glyphIndex('.');
    const cluster = if (line.glyph_len > 0)
        buffer.glyphs.items[line.glyph_start + line.glyph_len - 1].cluster
    else
        0;
    for (0..ellipsis_count) |_| {
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = dot_glyph,
            .codepoint = '.',
            .cluster = cluster,
            .x_advance = dot_advance,
        });
        line.glyph_len += 1;
        run.glyph_len += 1;
        line.width += dot_advance;
    }
    line.run_len = runRangeForGlyphs(buffer.runs.items, line.glyph_start, line.glyph_start + line.glyph_len).len;
    line.x = alignedLineX(line.width, max_width, alignment);
}

fn appendParagraphLine(buffer: *LayoutBuffer, glyph_start: usize, glyph_end: usize, width: f32, metrics: BaselineMetrics, y: f32, alignment: TextAlign, max_width: f32, indent: f32) !void {
    const available_width = lineWidthLimitForIndent(max_width, indent);
    const x = indent + alignedLineX(width, available_width, alignment);
    const run_range = runRangeForGlyphs(buffer.runs.items, glyph_start, glyph_end);
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = run_range.start,
        .run_len = run_range.len,
        .x = x,
        .y = y,
        .width = width,
        .height = metrics.lineHeight(),
        .baseline = metrics.ascent,
        .ascent = metrics.ascent,
        .descent = metrics.descent,
        .leading = metrics.leading,
    });
}

fn alignedLineX(width: f32, max_width: f32, alignment: TextAlign) f32 {
    if (!std.math.isFinite(max_width)) return 0;
    return switch (alignment) {
        .left => 0,
        .center => @max(0, (max_width - width) / 2),
        .right => @max(0, max_width - width),
    };
}

fn lineWidth(glyphs: []const GlyphPosition) f32 {
    var width: f32 = 0;
    for (glyphs) |glyph| width += glyph.x_advance;
    return width;
}

fn defaultSpaceAdvance(glyphs: []const GlyphPosition) f32 {
    for (glyphs) |glyph| {
        if (glyph.codepoint == ' ') return @max(glyph.x_advance, 1);
    }
    for (glyphs) |glyph| {
        if (glyph.codepoint != '\n' and glyph.codepoint != '\t' and glyph.x_advance > 0) {
            return glyph.x_advance;
        }
    }
    return 1;
}

fn tabAdvance(current_width: f32, tab_stop: f32, fallback_advance: f32) f32 {
    if (tab_stop <= 0) return fallback_advance;
    const stops_passed = @floor(current_width / tab_stop);
    const next_stop = (stops_passed + 1) * tab_stop;
    return @max(fallback_advance, next_stop - current_width);
}

fn spacingForGlyph(codepoint: u21, options: ParagraphOptions) f32 {
    if (codepoint == '\n') return 0;
    if (codepoint == ' ' or codepoint == '\t') return options.word_spacing;
    return options.letter_spacing;
}

fn trimLeadingSoftBreaks(glyphs: []const GlyphPosition, start: *usize) void {
    while (start.* < glyphs.len and isDiscardableBreak(glyphs[start.*].codepoint)) {
        start.* += 1;
    }
}

fn isDiscardableBreak(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t';
}

fn runRangeForGlyphs(runs: []const CascadeRun, glyph_start: usize, glyph_end: usize) struct { start: usize, len: usize } {
    var start: ?usize = null;
    var end: usize = 0;
    for (runs, 0..) |run, index| {
        const run_start = run.glyph_start;
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run_start >= glyph_end) continue;
        if (start == null) start = index;
        end = index + 1;
    }
    const actual_start = start orelse 0;
    return .{ .start = actual_start, .len = end - actual_start };
}

fn defaultBaselineMetrics(font: *const Font, font_size: f32) BaselineMetrics {
    const units = @as(f32, @floatFromInt(font.units_per_em));
    const scale = font_size / units;
    const ascender = @as(f32, @floatFromInt(font.ascender));
    const descender = @as(f32, @floatFromInt(font.descender));
    const line_gap = @as(f32, @floatFromInt(font.line_gap));
    return .{
        .ascent = ascender * scale,
        .descent = -descender * scale,
        .leading = line_gap * scale,
    };
}

fn metricsForLineHeight(default_metrics: BaselineMetrics, line_height: f32) BaselineMetrics {
    const natural_height = default_metrics.lineHeight();
    if (natural_height <= 0) {
        return .{ .ascent = line_height, .descent = 0, .leading = 0 };
    }
    const extra_leading = @max(0, line_height - natural_height);
    return .{
        .ascent = default_metrics.ascent + extra_leading / 2,
        .descent = default_metrics.descent,
        .leading = default_metrics.leading + extra_leading / 2,
    };
}

fn appendCascadeRun(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, font_index: usize, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen_x: f32, lookup_options: LookupOptions) !f32 {
    const glyph_start = buffer.glyphs.items.len;
    try shapeSegmentInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, cluster_base, lookup_options);
    const glyph_len = buffer.glyphs.items.len - glyph_start;
    try buffer.runs.append(buffer.allocator, .{
        .font = font,
        .font_index = font_index,
        .font_size = font_size,
        .glyph_start = glyph_start,
        .glyph_len = glyph_len,
        .x_offset = pen_x,
    });
    var next_pen_x = pen_x;
    for (buffer.glyphs.items[glyph_start..]) |glyph| next_pen_x += glyph.x_advance;
    return next_pen_x;
}

const LookupOptions = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    features: []const unicode.FeatureOverride = &.{},
};

fn lookupOptionsForText(text: []const u8, options: ShapeOptions) LookupOptions {
    return .{
        .script_tag = effectiveScriptTag(text, options),
        .language_tag = effectiveLanguageTag(text, options),
        .features = options.features,
    };
}

fn effectiveScriptTag(text: []const u8, options: ShapeOptions) unicode.OpenTypeScriptTag {
    return options.script_tag orelse unicode.openTypeScriptTag(scriptForText(text));
}

fn effectiveLanguageTag(text: []const u8, options: ShapeOptions) unicode.OpenTypeLanguageTag {
    return options.language_tag orelse unicode.inferOpenTypeLanguageTag(text);
}

fn featureOverridesHash(features: []const unicode.FeatureOverride) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (features) |feature| {
        hasher.update(std.mem.asBytes(&feature.tag));
        const enabled: u8 = @intFromBool(feature.enabled);
        hasher.update(std.mem.asBytes(&enabled));
    }
    return hasher.final();
}

fn shapePlanKeysEqual(a: ShapePlanKey, b: ShapePlanKey) bool {
    return a.direction == b.direction and
        a.script_tag == b.script_tag and
        a.language_tag == b.language_tag and
        a.feature_hash == b.feature_hash;
}

fn shapedRunCacheKeysEqual(a: ShapedRunCacheKey, b: ShapedRunCacheKey) bool {
    return a.cascade_hash == b.cascade_hash and
        a.text_hash == b.text_hash and
        a.text_len == b.text_len and
        a.font_size_bits == b.font_size_bits and
        shapePlanKeysEqual(a.plan, b.plan);
}

fn cascadeHash(cascade: FontCascade) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (cascade.fonts) |font| {
        const addr = @intFromPtr(font);
        hasher.update(std.mem.asBytes(&addr));
    }
    return hasher.final();
}

fn scriptForText(text: []const u8) unicode.Script {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        const script = unicode.scriptForCodepoint(codepoint);
        if (script != .common and script != .inherited and script != .unknown) return script;
    }
    return .common;
}

fn shapeSegmentInto(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, lookup_options: LookupOptions) !void {
    const scale = font_size / @as(f32, @floatFromInt(font.units_per_em));
    var glyph_ids = std.ArrayList(GlyphId).empty;
    defer glyph_ids.deinit(buffer.allocator);
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(buffer.allocator);
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(buffer.allocator);
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(buffer.allocator);
    var glyph_source_indices = std.ArrayList(usize).empty;
    defer glyph_source_indices.deinit(buffer.allocator);
    var ligature_components = std.ArrayList(gpos.LigatureComponentInfo).empty;
    defer ligature_components.deinit(buffer.allocator);

    // Keep three parallel arrays through GSUB: glyph ids are mutable, while
    // codepoints and clusters retain source-text identity for rendering,
    // hit-testing, and debug output after substitutions.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const cluster = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        if (isVariationSelector(codepoint)) {
            if (glyph_ids.items.len != 0) {
                if (try font.variationGlyphIndex(codepoints.items[codepoints.items.len - 1], codepoint)) |variant_glyph| {
                    glyph_ids.items[glyph_ids.items.len - 1] = variant_glyph;
                }
                source_ends.items[source_ends.items.len - 1] = cluster_base + it.i;
            }
            // Variation selectors refine the preceding scalar and do not
            // advance text themselves. Keeping them out of the glyph stream
            // preserves caret/cluster identity on the base character while
            // still allowing cmap format 14 to select emoji/text or IVS glyphs.
            continue;
        }
        try glyph_ids.append(buffer.allocator, try glyphIndexWithOptionalCache(font, glyph_index_cache, codepoint));
        try codepoints.append(buffer.allocator, codepoint);
        try clusters.append(buffer.allocator, cluster_base + cluster);
        try source_ends.append(buffer.allocator, cluster_base + it.i);
        try glyph_source_indices.append(buffer.allocator, glyph_source_indices.items.len);
        try ligature_components.append(buffer.allocator, defaultLigatureComponentInfo(glyph_source_indices.items.len - 1));
    }
    // Keep source metadata parallel to glyph ids through GSUB. GPOS MarkLigPos
    // needs the original component sources for a ligature glyph; otherwise a
    // mark after a ligature can only guess a component from post-substitution
    // mark order.
    try font.applyGsubWithOptions(&glyph_ids, buffer.allocator, .{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        .features = lookup_options.features,
        .apply_all_if_unselected = false,
        .glyph_source_indices = &glyph_source_indices,
        .ligature_components = &ligature_components,
    });

    var gpos_adjustments = std.ArrayList(gpos.Adjustment).empty;
    defer gpos_adjustments.deinit(buffer.allocator);
    try font.collectGposAdjustmentsWithOptions(glyph_ids.items, &gpos_adjustments, buffer.allocator, .{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        .features = lookup_options.features,
        .apply_all_if_unselected = false,
        .glyph_source_indices = glyph_source_indices.items,
        .ligature_components = ligature_components.items,
    });

    // GPOS adjustments and legacy kern are accumulated in font units, then
    // scaled into user-space coordinates for the final GlyphPosition stream.
    var previous_glyph: ?GlyphId = null;
    for (glyph_ids.items, 0..) |glyph_id, index| {
        const source_index = if (index < glyph_source_indices.items.len)
            @min(glyph_source_indices.items[index], codepoints.items.len -| 1)
        else
            @min(index, codepoints.items.len -| 1);
        const source_span = sourceSpanForGlyph(index, source_index, clusters.items, source_ends.items, ligature_components.items) orelse
            SourceSpan{ .start = cluster_base, .end = cluster_base };
        const metrics = try horizontalMetricsWithOptionalCache(font, metrics_cache, glyph_id);
        const glyph_class = font.glyphClass(glyph_id) catch .unclassified;
        if (previous_glyph) |previous| {
            const previous_adjustment = findAdjustment(gpos_adjustments.items, index - 1);
            if (!previous_adjustment.pair_positioned) {
                const kern = try font.kerning(previous, glyph_id);
                if (kern != 0 and buffer.glyphs.items.len > 0) {
                    buffer.glyphs.items[buffer.glyphs.items.len - 1].x_advance += @as(f32, @floatFromInt(kern)) * scale;
                }
            }
        }
        var adjustment = findAdjustment(gpos_adjustments.items, index);
        if (adjustment.mark_attachment) {
            const advance_to_base = if (adjustment.mark_base_index) |base_index|
                advanceBetweenGlyphs(buffer.glyphs.items, base_index, index)
            else if (buffer.glyphs.items.len > 0)
                buffer.glyphs.items[buffer.glyphs.items.len - 1].x_advance
            else
                0.0;
            adjustment.x_placement = @intFromFloat(@round(@as(f32, @floatFromInt(adjustment.x_placement)) - advance_to_base / scale));
            adjustment.x_advance = -@as(i16, @intCast(metrics.advance_width));
        }
        const base_advance = if (glyph_class == .mark and !adjustment.mark_attachment) 0 else metrics.advance_width;
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = glyph_id,
            .codepoint = if (codepoints.items.len == 0) 0 else codepoints.items[source_index],
            .cluster = source_span.start,
            .source_byte_len = source_span.end - source_span.start,
            .x_advance = (@as(f32, @floatFromInt(base_advance)) + @as(f32, @floatFromInt(adjustment.x_advance))) * scale,
            .x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) * scale,
            .y_offset = @as(f32, @floatFromInt(adjustment.y_placement)) * scale,
        });
        previous_glyph = glyph_id;
    }
}

const SourceSpan = struct {
    start: usize,
    end: usize,
};

fn sourceSpanForGlyph(glyph_index: usize, fallback_source_index: usize, starts: []const usize, ends: []const usize, ligature_components: []const gpos.LigatureComponentInfo) ?SourceSpan {
    if (glyph_index < ligature_components.len and ligature_components[glyph_index].component_count > 1) {
        const info = ligature_components[glyph_index];
        var span: ?SourceSpan = null;
        const component_count = @min(info.component_count, gpos.max_ligature_components);
        for (0..component_count) |component_index| {
            const component_span = sourceSpanForIndex(info.component_sources[component_index], starts, ends) orelse continue;
            if (span) |*accumulated| {
                accumulated.start = @min(accumulated.start, component_span.start);
                accumulated.end = @max(accumulated.end, component_span.end);
            } else {
                span = component_span;
            }
        }
        if (span) |value| return value;
    }
    return sourceSpanForIndex(fallback_source_index, starts, ends);
}

fn sourceSpanForIndex(source_index: usize, starts: []const usize, ends: []const usize) ?SourceSpan {
    if (starts.len == 0) return null;
    const index = @min(source_index, starts.len - 1);
    const start = starts[index];
    const end = if (index < ends.len) @max(ends[index], start) else start;
    return .{ .start = start, .end = end };
}

fn defaultLigatureComponentInfo(source_index: usize) gpos.LigatureComponentInfo {
    var info = gpos.LigatureComponentInfo{};
    info.component_sources[0] = source_index;
    return info;
}

fn advanceBetweenGlyphs(glyphs: []const GlyphPosition, base_index: usize, mark_index: usize) f32 {
    if (mark_index <= base_index or base_index >= glyphs.len) return 0.0;
    const end = @min(mark_index, glyphs.len);
    var advance: f32 = 0.0;
    for (glyphs[base_index..end]) |glyph| {
        advance += glyph.x_advance;
    }
    return advance;
}

fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn glyphMetricsKey(font: *const Font, glyph_id: GlyphId) GlyphMetricsKey {
    return .{
        .font_addr = @intFromPtr(font),
        .glyph_id = glyph_id,
    };
}

fn glyphIndexKey(font: *const Font, codepoint: u21) GlyphIndexKey {
    return .{
        .font_addr = @intFromPtr(font),
        .codepoint = codepoint,
    };
}

fn glyphIndexWithOptionalCache(font: *const Font, cache: ?*GlyphIndexCache, codepoint: u21) !GlyphId {
    if (cache) |glyph_cache| return try glyph_cache.glyphIndex(font, codepoint);
    return try font.glyphIndex(codepoint);
}

fn horizontalMetricsWithOptionalCache(font: *const Font, cache: ?*GlyphMetricsCache, glyph_id: GlyphId) !GlyphMetrics {
    if (cache) |metrics_cache| return try metrics_cache.horizontalMetrics(font, glyph_id);
    const raw = try font.horizontalMetrics(glyph_id);
    return .{
        .advance_width = raw.advance_width,
        .left_side_bearing = raw.left_side_bearing,
    };
}

fn findAdjustment(adjustments: []const gpos.Adjustment, index: usize) gpos.Adjustment {
    for (adjustments) |adjustment| {
        if (adjustment.index == index) return adjustment;
    }
    return .{ .index = index };
}
