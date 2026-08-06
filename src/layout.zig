const std = @import("std");
const Font = @import("font.zig").Font;
const GdefLookupMetadata = @import("font.zig").GdefLookupMetadata;
const GlyphClass = @import("font.zig").GlyphClass;
const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const gsub = @import("gsub.zig");
const layout_cache = @import("layout_cache.zig");
const layout_scratch = @import("layout_scratch.zig");
const unicode = @import("unicode.zig");
pub const ShapeStageProfile = @import("shape_profile.zig").ShapeStageProfile;
pub const GdefMetadataCache = layout_cache.GdefMetadataCache;
pub const GlyphIndexCache = layout_cache.GlyphIndexCache;
pub const GlyphMetrics = layout_cache.GlyphMetrics;
pub const GlyphMetricsCache = layout_cache.GlyphMetricsCache;
pub const GposTableProofCache = layout_cache.GposTableProofCache;
pub const GsubTableProofCache = layout_cache.GsubTableProofCache;
pub const LookupSelectionCache = layout_cache.LookupSelectionCache;
pub const VerticalGlyphMetrics = layout_cache.VerticalGlyphMetrics;

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
    vertical: bool = false,
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

    pub fn height(self: GlyphRun) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.y_advance;
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
    y_offset: f32 = 0,

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

    pub fn height(self: ShapedText) f32 {
        var total: f32 = 0;
        for (self.glyphs) |glyph| total += glyph.y_advance;
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

pub const WritingMode = enum {
    horizontal_tb,
    vertical_rl,
    vertical_lr,

    pub fn isVertical(self: WritingMode) bool {
        return self != .horizontal_tb;
    }
};

pub const TextOrientation = enum {
    mixed,
    upright,
    sideways,
};

pub const ScriptPosition = enum {
    normal,
    superscript,
    subscript,
};

pub const ShapeOptions = struct {
    direction: TextDirection = .ltr,
    /// Reorder the logical UTF-8 input into bidi visual order after shaping.
    ///
    /// Callers that already materialized visual text (for example, a retained
    /// document engine implementing its own unicode-bidi run boundaries) can
    /// disable this while retaining all other GSUB/GPOS and fallback behavior.
    reorder_bidi: bool = true,
    /// Shape through the OpenType native-direction buffer order even when final
    /// bidi reordering is disabled. This is mainly for parity tools that need
    /// HarfBuzz buffer order without Cangjie's paragraph-level bidi pass.
    native_direction_shaping: bool = false,
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    script_position: ScriptPosition = .normal,
    features: []const unicode.FeatureOverride = &.{},
};

/// Coarse shaping plan identity. It intentionally excludes the concrete font
/// and text bytes; those live in `ShapedRunCacheKey`. This part captures the
/// OpenType selection knobs that change which GSUB/GPOS lookups are active.
pub const ShapePlanKey = struct {
    direction: TextDirection = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    script_position: ScriptPosition = .normal,
    feature_hash: u64 = 0,

    pub fn fromText(text: []const u8, options: ShapeOptions) ShapePlanKey {
        return .{
            .direction = options.direction,
            .reorder_bidi = options.reorder_bidi,
            .native_direction_shaping = options.native_direction_shaping,
            .writing_mode = options.writing_mode,
            .text_orientation = options.text_orientation,
            .script_tag = effectiveScriptTag(text, options),
            .language_tag = effectiveLanguageTag(text, options),
            .script_position = options.script_position,
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

    pub fn selectionRectForBytes(self: ParagraphLayout, byte_start: usize, byte_end: usize) TextRect {
        if (byte_start == byte_end) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const start = self.textPositionForCluster(@min(byte_start, byte_end));
        const end = self.textPositionForCluster(@max(byte_start, byte_end));
        return self.selectionRect(
            start.glyph_index + @intFromBool(start.trailing),
            end.glyph_index + @intFromBool(end.trailing),
        );
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

    pub fn selectionRectsForBytes(self: ParagraphLayout, allocator: std.mem.Allocator, byte_start: usize, byte_end: usize) ![]TextRect {
        if (byte_start == byte_end) return try allocator.alloc(TextRect, 0);
        const start = self.textPositionForCluster(@min(byte_start, byte_end));
        const end = self.textPositionForCluster(@max(byte_start, byte_end));
        return try self.selectionRects(
            allocator,
            start.glyph_index + @intFromBool(start.trailing),
            end.glyph_index + @intFromBool(end.trailing),
        );
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

/// Deterministic per-cluster fallback decision used by headless tests,
/// diagnostics, and editor integration code that wants to explain why a glyph
/// came from a particular font before involving any renderer or UI layer.
pub const FontFallbackDecision = struct {
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    variation_selector: ?u21 = null,
    font_index: usize,
    glyph_id: GlyphId,
    /// True when the selected font explicitly advertised a cmap format 14
    /// Unicode Variation Sequence for `codepoint + variation_selector`.
    used_variation_mapping: bool = false,

    pub fn missingGlyph(self: FontFallbackDecision) bool {
        return self.glyph_id == 0;
    }
};

/// A missing-glyph entry captured during shaping-quality diagnostics.
///
/// This is intentionally source-oriented rather than renderer-oriented: byte
/// ranges and Unicode scalars are enough for tests, editor overlays, and font
/// fallback tooling to explain coverage holes without depending on a UI layer.
pub const MissingGlyphDiagnostic = struct {
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    variation_selector: ?u21 = null,
    font_index: usize,
    glyph_id: GlyphId,
};

/// Per-font-run quality details for a shaped UTF-8 pass.
///
/// The byte range is derived from glyph source spans instead of fallback
/// decisions so it also tracks future GSUB ligatures and multi-scalar clusters.
/// This gives regression tests a stable way to answer "which fallback run
/// produced the bad glyphs?" without depending on renderer draw commands.
pub const ShapeQualityFontRunDiagnostic = struct {
    font_index: usize,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,
    missing_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
};

/// Per-script quality details for a shaped UTF-8 pass.
///
/// Script runs are the OpenType lookup boundary used by Cangjie shaping.
/// Reporting the effective script/language tags next to coverage counters makes
/// script itemization and fallback splits auditable in headless CI, similar to
/// the diagnostics exposed by mature text stacks.
pub const ShapeQualityScriptRunDiagnostic = struct {
    script: unicode.Script,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,
    font_run_count: usize,
    missing_glyph_count: usize,
    fallback_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
};

/// Headless quality summary for one UTF-8 shaping pass.
///
/// Cangjie uses this as a small, deterministic contract for regression tests
/// and higher-level font pickers: callers can assert that fallback, variation
/// selector handling, and missing-glyph coverage did not silently regress
/// without rasterizing pixels or involving platform font APIs.
pub const ShapeQualityReport = struct {
    glyph_count: usize,
    font_run_count: usize,
    missing_glyph_count: usize,
    variation_selector_count: usize,
    fallback_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
    missing_glyphs: []MissingGlyphDiagnostic,
    font_runs: []ShapeQualityFontRunDiagnostic,
    script_runs: []ShapeQualityScriptRunDiagnostic,

    pub fn deinit(self: *ShapeQualityReport, allocator: std.mem.Allocator) void {
        allocator.free(self.script_runs);
        allocator.free(self.font_runs);
        allocator.free(self.missing_glyphs);
        self.* = undefined;
    }
};

/// Kind of source/caret invariant violation found in a shaped paragraph.
///
/// These diagnostics are intentionally byte-oriented because every public
/// layout/caret API in Cangjie maps back to UTF-8 byte offsets.  Keeping these
/// checks renderer-free makes them useful as CI guards for shaper changes that
/// alter clusters, ligature source spans, variation-selector folding, or bidi
/// reordering.
pub const ClusterCaretIssueKind = enum {
    glyph_cluster_out_of_bounds,
    glyph_source_end_out_of_bounds,
    empty_source_span,
    cluster_not_utf8_boundary,
    source_end_not_utf8_boundary,
    leading_caret_roundtrip_mismatch,
    trailing_caret_roundtrip_mismatch,
    grapheme_boundary_roundtrip_mismatch,
};

/// One cluster/caret consistency issue.
///
/// `glyph_index` is null for text-wide checks such as grapheme-boundary
/// round-trips; glyph-specific checks include the source span observed on the
/// offending glyph.  `expected_byte_offset` and `actual_byte_offset` are filled
/// for round-trip mismatches, where a source byte boundary was converted to a
/// TextPosition and then back to a byte offset.
pub const ClusterCaretDiagnostic = struct {
    kind: ClusterCaretIssueKind,
    glyph_index: ?usize = null,
    cluster: usize = 0,
    source_end: usize = 0,
    expected_byte_offset: usize = 0,
    actual_byte_offset: usize = 0,
};

/// Headless report that verifies shaped glyph clusters are valid UTF-8 source
/// spans and that paragraph caret mapping round-trips every glyph edge and
/// grapheme boundary.
pub const ClusterCaretConsistencyReport = struct {
    glyph_count: usize,
    caret_boundary_count: usize,
    grapheme_boundary_count: usize,
    issue_count: usize,
    issues: []ClusterCaretDiagnostic,

    pub fn deinit(self: *ClusterCaretConsistencyReport, allocator: std.mem.Allocator) void {
        allocator.free(self.issues);
        self.* = undefined;
    }
};

/// Build a stable fallback trace for UTF-8 text without shaping, rasterizing,
/// or consulting platform font APIs. Variation selectors are folded into the
/// preceding scalar, matching the shaping path's cluster model, so the returned
/// byte ranges can be compared directly against shaped glyph clusters.
///
/// The caller owns the returned slice and must free it with `allocator.free`.
pub fn diagnoseFontFallbackUtf8(allocator: std.mem.Allocator, cascade: FontCascade, text: []const u8) ![]FontFallbackDecision {
    try validateShapingUtf8(text);
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;

    var decisions = std.ArrayList(FontFallbackDecision).empty;
    errdefer decisions.deinit(allocator);

    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        if (isVariationSelector(codepoint)) {
            // A leading or otherwise detached variation selector shapes to no
            // glyph in Cangjie. Diagnostics follow that visible cluster model
            // instead of emitting a synthetic `.notdef` decision.
            continue;
        }

        var byte_len = it.i - byte_start;
        var variation_selector: ?u21 = null;
        var used_variation_mapping = false;
        var font_index: usize = 0;

        if (nextVariationSelector(text, it.i)) |selector| {
            variation_selector = selector;
            _ = it.nextCodepoint();
            byte_len = it.i - byte_start;

            for (cascade.fonts, 0..) |font, index| {
                if (try font.variationGlyphIndex(codepoint, selector) != null) {
                    font_index = index;
                    used_variation_mapping = true;
                    break;
                }
            } else {
                font_index = try cascade.selectFont(codepoint);
            }
        } else {
            font_index = try cascade.selectFont(codepoint);
        }

        const glyph_id = if (variation_selector) |selector|
            try cascade.fonts[font_index].glyphIndexWithVariation(codepoint, selector)
        else
            try cascade.fonts[font_index].glyphIndex(codepoint);

        try decisions.append(allocator, .{
            .byte_start = byte_start,
            .byte_len = byte_len,
            .codepoint = codepoint,
            .variation_selector = variation_selector,
            .font_index = font_index,
            .glyph_id = glyph_id,
            .used_variation_mapping = used_variation_mapping,
        });
    }

    return try decisions.toOwnedSlice(allocator);
}

/// Shape text and validate source cluster/caret invariants without depending on
/// a renderer, platform text API, or UI layer.
///
/// The paragraph is laid out with unbounded width so the report focuses on
/// shaper source metadata and caret normalization rather than line wrapping.
/// Callers can use this in fixtures and benchmarks as a cheap preflight before
/// asserting pixels or editor selection geometry.
pub fn diagnoseClusterCaretConsistencyUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ClusterCaretConsistencyReport {
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    _ = try TextShaper.shapeUtf8CascadeWithOptions(cascade, &buffer, text, font_size, options);
    try buildParagraphLines(&buffer, text, .{
        .max_width = std.math.inf(f32),
        .direction = options.direction,
    }, defaultBaselineMetrics(cascade.fonts[0], font_size));
    return try diagnoseClusterCaretConsistencyForLayout(allocator, text, buffer.paragraphLayout());
}

/// Shape text and return a compact quality/coverage report.
///
/// The report owns only the `missing_glyphs` slice. All other values are scalar
/// aggregates computed from the shaped glyph stream and deterministic fallback
/// decisions, so this helper remains cheap enough to run in unit tests,
/// benchmarks, and CI quality gates.
pub fn diagnoseShapeQualityUtf8(
    allocator: std.mem.Allocator,
    cascade: FontCascade,
    text: []const u8,
    font_size: f32,
    options: ShapeOptions,
) !ShapeQualityReport {
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    const scripted = try TextShaper.shapeUtf8ScriptRuns(cascade, &buffer, text, font_size, options);
    const fallback = try diagnoseFontFallbackUtf8(allocator, cascade, text);
    defer allocator.free(fallback);

    var missing = std.ArrayList(MissingGlyphDiagnostic).empty;
    errdefer missing.deinit(allocator);
    var font_run_diagnostics = std.ArrayList(ShapeQualityFontRunDiagnostic).empty;
    errdefer font_run_diagnostics.deinit(allocator);
    var script_run_diagnostics = std.ArrayList(ShapeQualityScriptRunDiagnostic).empty;
    errdefer script_run_diagnostics.deinit(allocator);

    var variation_selector_count: usize = 0;
    for (fallback) |decision| {
        if (decision.variation_selector != null) variation_selector_count += 1;
        if (!decision.missingGlyph()) continue;
        try missing.append(allocator, .{
            .byte_start = decision.byte_start,
            .byte_len = decision.byte_len,
            .codepoint = decision.codepoint,
            .variation_selector = decision.variation_selector,
            .font_index = decision.font_index,
            .glyph_id = decision.glyph_id,
        });
    }

    var fallback_glyph_count: usize = 0;
    for (scripted.font_runs) |run| {
        if (run.font_index != 0) fallback_glyph_count += run.glyph_len;
        try font_run_diagnostics.append(allocator, fontRunQualityDiagnostic(run, scripted.glyphs));
    }

    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;
    for (scripted.glyphs) |glyph| {
        if (glyph.x_advance == 0 and glyph.y_advance == 0) zero_advance_glyph_count += 1;
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    for (scripted.script_runs) |script_run| {
        try script_run_diagnostics.append(allocator, scriptRunQualityDiagnostic(script_run, scripted));
    }

    const missing_glyphs = try missing.toOwnedSlice(allocator);
    errdefer allocator.free(missing_glyphs);
    const font_runs = try font_run_diagnostics.toOwnedSlice(allocator);
    errdefer allocator.free(font_runs);
    const script_runs = try script_run_diagnostics.toOwnedSlice(allocator);
    return .{
        .glyph_count = scripted.glyphs.len,
        .font_run_count = scripted.font_runs.len,
        .missing_glyph_count = missing_glyphs.len,
        .variation_selector_count = variation_selector_count,
        .fallback_glyph_count = fallback_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
        .missing_glyphs = missing_glyphs,
        .font_runs = font_runs,
        .script_runs = script_runs,
    };
}

fn diagnoseClusterCaretConsistencyForLayout(allocator: std.mem.Allocator, text: []const u8, paragraph: ParagraphLayout) !ClusterCaretConsistencyReport {
    var issues = std.ArrayList(ClusterCaretDiagnostic).empty;
    errdefer issues.deinit(allocator);

    for (paragraph.glyphs, 0..) |glyph, glyph_index| {
        const source_end = glyphSourceEnd(glyph);
        const span_valid = try validateGlyphSourceSpanForCaretDiagnostic(allocator, text, glyph, glyph_index, &issues);
        if (!span_valid) continue;

        try checkCaretBoundaryRoundtrip(
            allocator,
            paragraph,
            glyph_index,
            glyph.cluster,
            .leading_caret_roundtrip_mismatch,
            &issues,
        );
        try checkCaretBoundaryRoundtrip(
            allocator,
            paragraph,
            glyph_index,
            source_end,
            .trailing_caret_roundtrip_mismatch,
            &issues,
        );
    }

    const graphemes = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    for (graphemes) |grapheme| {
        try checkCaretBoundaryRoundtrip(
            allocator,
            paragraph,
            null,
            grapheme.byte_start,
            .grapheme_boundary_roundtrip_mismatch,
            &issues,
        );
        try checkCaretBoundaryRoundtrip(
            allocator,
            paragraph,
            null,
            grapheme.byte_start + grapheme.byte_len,
            .grapheme_boundary_roundtrip_mismatch,
            &issues,
        );
    }

    const owned_issues = try issues.toOwnedSlice(allocator);
    return .{
        .glyph_count = paragraph.glyphs.len,
        .caret_boundary_count = paragraph.glyphs.len * 2,
        .grapheme_boundary_count = graphemes.len * 2,
        .issue_count = owned_issues.len,
        .issues = owned_issues,
    };
}

fn validateGlyphSourceSpanForCaretDiagnostic(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyph: GlyphPosition,
    glyph_index: usize,
    issues: *std.ArrayList(ClusterCaretDiagnostic),
) !bool {
    const source_end = glyphSourceEnd(glyph);
    var valid = true;

    if (glyph.source_byte_len == 0) {
        valid = false;
        try appendClusterCaretIssue(allocator, issues, .{
            .kind = .empty_source_span,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }
    if (glyph.cluster > text.len) {
        valid = false;
        try appendClusterCaretIssue(allocator, issues, .{
            .kind = .glyph_cluster_out_of_bounds,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    } else if (!isUtf8Boundary(text, glyph.cluster)) {
        valid = false;
        try appendClusterCaretIssue(allocator, issues, .{
            .kind = .cluster_not_utf8_boundary,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }
    if (source_end > text.len) {
        valid = false;
        try appendClusterCaretIssue(allocator, issues, .{
            .kind = .glyph_source_end_out_of_bounds,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    } else if (!isUtf8Boundary(text, source_end)) {
        valid = false;
        try appendClusterCaretIssue(allocator, issues, .{
            .kind = .source_end_not_utf8_boundary,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }

    return valid;
}

fn checkCaretBoundaryRoundtrip(
    allocator: std.mem.Allocator,
    paragraph: ParagraphLayout,
    glyph_index: ?usize,
    byte_offset: usize,
    kind: ClusterCaretIssueKind,
    issues: *std.ArrayList(ClusterCaretDiagnostic),
) !void {
    const position = paragraph.textPositionForCluster(byte_offset);
    const actual = positionByteOffset(paragraph, position);
    if (actual == byte_offset) return;
    try appendClusterCaretIssue(allocator, issues, .{
        .kind = kind,
        .glyph_index = glyph_index,
        .cluster = byte_offset,
        .source_end = byte_offset,
        .expected_byte_offset = byte_offset,
        .actual_byte_offset = actual,
    });
}

fn appendClusterCaretIssue(allocator: std.mem.Allocator, issues: *std.ArrayList(ClusterCaretDiagnostic), issue: ClusterCaretDiagnostic) !void {
    try issues.append(allocator, issue);
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset > text.len) return false;
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0xc0) != 0x80;
}

fn fontRunQualityDiagnostic(run: CascadeRun, glyphs: []const GlyphPosition) ShapeQualityFontRunDiagnostic {
    const run_glyphs = glyphs[run.glyph_start .. run.glyph_start + run.glyph_len];
    var byte_start: usize = 0;
    var byte_end: usize = 0;
    var missing_glyph_count: usize = 0;
    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;

    if (run_glyphs.len != 0) {
        byte_start = run_glyphs[0].cluster;
        byte_end = glyphSourceEnd(run_glyphs[0]);
    }
    for (run_glyphs) |glyph| {
        byte_start = @min(byte_start, glyph.cluster);
        byte_end = @max(byte_end, glyphSourceEnd(glyph));
        if (glyph.glyph_id == 0) missing_glyph_count += 1;
        if (glyph.x_advance == 0 and glyph.y_advance == 0) zero_advance_glyph_count += 1;
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    return .{
        .font_index = run.font_index,
        .glyph_start = run.glyph_start,
        .glyph_len = run.glyph_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .missing_glyph_count = missing_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
    };
}

fn scriptRunQualityDiagnostic(run: ScriptedRun, scripted: ScriptedText) ShapeQualityScriptRunDiagnostic {
    const glyph_end = run.glyph_start + run.glyph_len;
    var font_run_count: usize = 0;
    var missing_glyph_count: usize = 0;
    var fallback_glyph_count: usize = 0;
    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;

    for (scripted.glyphs[run.glyph_start..glyph_end]) |glyph| {
        if (glyph.glyph_id == 0) missing_glyph_count += 1;
        if (glyph.x_advance == 0 and glyph.y_advance == 0) zero_advance_glyph_count += 1;
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    for (scripted.font_runs) |font_run| {
        const font_glyph_start = font_run.glyph_start;
        const font_glyph_end = font_run.glyph_start + font_run.glyph_len;
        const overlap_start = @max(run.glyph_start, font_glyph_start);
        const overlap_end = @min(glyph_end, font_glyph_end);
        if (overlap_start >= overlap_end) continue;
        font_run_count += 1;
        if (font_run.font_index != 0) fallback_glyph_count += overlap_end - overlap_start;
    }

    return .{
        .script = run.script,
        .script_tag = run.script_tag,
        .language_tag = run.language_tag,
        .glyph_start = run.glyph_start,
        .glyph_len = run.glyph_len,
        .byte_start = run.byte_start,
        .byte_len = run.byte_len,
        .font_run_count = font_run_count,
        .missing_glyph_count = missing_glyph_count,
        .fallback_glyph_count = fallback_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
    };
}

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

fn gdefMetadataForShaping(font: *const Font, allocator: std.mem.Allocator, cache: ?*GdefMetadataCache, out_owned: *?GdefLookupMetadata) !*const GdefLookupMetadata {
    if (cache) |metadata_cache| {
        return try metadata_cache.metadata(font);
    }
    out_owned.* = try font.gdefLookupMetadataForShaping(allocator);
    return &out_owned.*.?;
}

pub const LayoutBuffer = struct {
    allocator: std.mem.Allocator,
    glyphs: std.ArrayList(GlyphPosition) = .empty,
    runs: std.ArrayList(CascadeRun) = .empty,
    lines: std.ArrayList(ParagraphLine) = .empty,
    script_runs: std.ArrayList(ScriptedRun) = .empty,
    shape_profile: ?*ShapeStageProfile = null,
    profile_io: ?std.Io = null,
    gdef_metadata_cache: ?*GdefMetadataCache = null,
    gsub_table_proof_cache: ?*GsubTableProofCache = null,
    gpos_table_proof_cache: ?*GposTableProofCache = null,
    lookup_selection_cache: ?*LookupSelectionCache = null,
    shape_scratch: layout_scratch.ShapeScratch = .{},

    pub fn init(allocator: std.mem.Allocator) LayoutBuffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LayoutBuffer) void {
        self.shape_scratch.deinit(self.allocator);
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
        return try shapeSingleFontInto(font, null, null, buffer, text, font_size, options);
    }

    pub fn shapeUtf8WithCaches(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
        return try shapeSingleFontInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, options);
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
        var pen_y: f32 = 0;

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
                const next_pen = try appendCascadeRun(
                    cascade.fonts[segment_font_index.?],
                    metrics_cache,
                    glyph_index_cache,
                    segment_font_index.?,
                    buffer,
                    text[segment_start..cluster],
                    font_size,
                    segment_start,
                    .{ .x = pen_x, .y = pen_y },
                    lookupOptionsForText(text[segment_start..cluster], options),
                );
                pen_x = next_pen.x;
                pen_y = next_pen.y;
                segment_start = cluster;
                segment_font_index = font_index;
            }
        }

        if (segment_font_index) |font_index| {
            _ = try appendCascadeRun(
                cascade.fonts[font_index],
                metrics_cache,
                glyph_index_cache,
                font_index,
                buffer,
                text[segment_start..],
                font_size,
                segment_start,
                .{ .x = pen_x, .y = pen_y },
                lookupOptionsForText(text[segment_start..], options),
            );
        }

        if (shouldApplyBidiVisualOrder(text, options)) {
            try applyBidiVisualOrder(buffer, text, options.direction, null);
        }
        const shaped = buffer.shapedText();
        if (shaped_cache) |cache| {
            try cache.store(cache_key, shaped);
        }
        return shaped;
    }

    pub fn shapeUtf8ScriptRuns(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !ScriptedText {
        try validateShapingInput(text, font_size, options);
        try shapeScriptRunsInto(cascade, buffer, text, font_size, options);
        if (shouldApplyBidiVisualOrder(text, options)) {
            try applyBidiVisualOrder(buffer, text, options.direction, null);
        }
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

    var pen = PenPosition{};
    for (script_runs) |script_run| {
        const run_text = text[script_run.byte_start .. script_run.byte_start + script_run.byte_len];
        pen = try shapeCascadeSegmentInto(
            cascade,
            buffer,
            run_text,
            font_size,
            script_run.byte_start,
            pen,
            .{
                .script_tag = unicode.openTypeScriptTag(script_run.script),
                .language_tag = effectiveLanguageTag(run_text, options),
                .direction = options.direction,
                .reorder_bidi = options.reorder_bidi,
                .native_direction_shaping = options.native_direction_shaping,
                .features = options.features,
                .writing_mode = options.writing_mode,
                .text_orientation = options.text_orientation,
            },
        );
    }
}

const PenPosition = struct {
    x: f32 = 0,
    y: f32 = 0,
};

fn shapeSingleFontInto(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ShapeOptions) !GlyphRun {
    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const total_start = shapeProfileNow(shape_profile, profile_io);
    defer {
        if (shape_profile) |p| p.total_ns += shapeProfileElapsed(total_start, profile_io);
    }

    const validate_start = shapeProfileNow(shape_profile, profile_io);
    try validateShapingInput(text, font_size, options);
    if (shape_profile) |p| p.validate_ns += shapeProfileElapsed(validate_start, profile_io);

    buffer.clear();
    const options_start = shapeProfileNow(shape_profile, profile_io);
    const lookup_options = lookupOptionsForText(text, options);
    if (shape_profile) |p| p.options_ns += shapeProfileElapsed(options_start, profile_io);

    try shapeSegmentInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, 0, lookup_options);
    const bidi_start = shapeProfileNow(shape_profile, profile_io);
    if (shouldApplyBidiVisualOrder(text, options)) {
        try applyBidiVisualOrder(buffer, text, options.direction, font);
    }
    if (shape_profile) |p| p.bidi_ns += shapeProfileElapsed(bidi_start, profile_io);
    return buffer.run(font, font_size);
}

fn shouldApplyBidiVisualOrder(text: []const u8, options: ShapeOptions) bool {
    if (!options.reorder_bidi) return false;
    if (options.direction == .rtl) return true;
    return textHasRtlBidiClass(text);
}

fn textHasRtlBidiClass(text: []const u8) bool {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (unicode.bidiClassForCodepoint(codepoint) == .rtl) return true;
    }
    return false;
}

fn shapeCascadeSegmentInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: LookupOptions) !PenPosition {
    // Script itemization happens outside this helper. This pass only performs
    // fallback segmentation inside that script run, so each append keeps the
    // same OpenType script/language lookup selection.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var segment_start: usize = 0;
    var segment_font_index: ?usize = null;
    var next_pen = pen;

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
            next_pen = try appendCascadeRun(cascade.fonts[segment_font_index.?], null, null, segment_font_index.?, buffer, text[segment_start..cluster], font_size, cluster_base + segment_start, next_pen, lookup_options);
            segment_start = cluster;
            segment_font_index = font_index;
        }
    }

    if (segment_font_index) |font_index| {
        next_pen = try appendCascadeRun(cascade.fonts[font_index], null, null, font_index, buffer, text[segment_start..], font_size, cluster_base + segment_start, next_pen, lookup_options);
    }
    return next_pen;
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
    if (item.direction == .rtl) {
        var glyph_index = glyphs.len;
        while (glyph_index > 0) {
            glyph_index -= 1;
            const glyph = glyphs[glyph_index];
            if (seen[glyph_index]) continue;
            if (glyph.cluster != item.byte_start) continue;
            const visual_codepoint = if (@max(glyph.source_byte_len, 1) == item.byte_len)
                item.visual_codepoint
            else
                null;
            try appendVisualGlyph(allocator, glyphs, old_runs, single_font, glyph_run_indices, seen, glyph_index, visual_codepoint, out_glyphs, out_run_indices);
        }
        return;
    }

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
            .y_offset = 0,
        });
        if (i < visual_run_indices.len) {
            start = i;
            current_run_index = visual_run_indices[i];
        }
    }
}

fn recomputeRunOffsets(buffer: *LayoutBuffer) void {
    var x_offset: f32 = 0;
    var y_offset: f32 = 0;
    for (buffer.runs.items) |*run| {
        run.x_offset = x_offset;
        run.y_offset = y_offset;
        for (buffer.glyphs.items[run.glyph_start .. run.glyph_start + run.glyph_len]) |glyph| {
            x_offset += glyph.x_advance;
            y_offset += glyph.y_advance;
        }
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

fn appendCascadeRun(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, font_index: usize, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: LookupOptions) !PenPosition {
    const glyph_start = buffer.glyphs.items.len;
    try shapeSegmentInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, cluster_base, lookup_options);
    const glyph_len = buffer.glyphs.items.len - glyph_start;
    try buffer.runs.append(buffer.allocator, .{
        .font = font,
        .font_index = font_index,
        .font_size = font_size,
        .glyph_start = glyph_start,
        .glyph_len = glyph_len,
        .x_offset = pen.x,
        .y_offset = pen.y,
    });
    var next_pen = pen;
    for (buffer.glyphs.items[glyph_start..]) |glyph| {
        next_pen.x += glyph.x_advance;
        next_pen.y += glyph.y_advance;
    }
    return next_pen;
}

const LookupOptions = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    direction: TextDirection = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    script_position: ScriptPosition = .normal,
    features: []const unicode.FeatureOverride = &.{},
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
};

fn lookupOptionsForText(text: []const u8, options: ShapeOptions) LookupOptions {
    return .{
        .script_tag = effectiveScriptTag(text, options),
        .language_tag = effectiveLanguageTag(text, options),
        .direction = options.direction,
        .reorder_bidi = options.reorder_bidi,
        .native_direction_shaping = options.native_direction_shaping,
        .script_position = options.script_position,
        .features = options.features,
        .writing_mode = options.writing_mode,
        .text_orientation = options.text_orientation,
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
        a.reorder_bidi == b.reorder_bidi and
        a.native_direction_shaping == b.native_direction_shaping and
        a.writing_mode == b.writing_mode and
        a.text_orientation == b.text_orientation and
        a.script_tag == b.script_tag and
        a.language_tag == b.language_tag and
        a.script_position == b.script_position and
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
    const scratch = &buffer.shape_scratch;
    scratch.clear();
    const glyph_ids = &scratch.glyph_ids;
    const codepoints = &scratch.codepoints;
    const clusters = &scratch.clusters;
    const source_ends = &scratch.source_ends;
    const glyph_source_indices = &scratch.glyph_source_indices;
    const ligature_components = &scratch.ligature_components;
    const joining_forms = &scratch.joining_forms;
    const source_features = &scratch.source_features;

    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const cmap_start = shapeProfileNow(shape_profile, profile_io);

    // Keep three parallel arrays through GSUB: glyph ids are mutable, while
    // codepoints and clusters retain source-text identity for rendering,
    // hit-testing, and debug output after substitutions.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var has_default_ignorable = false;
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
        has_default_ignorable = has_default_ignorable or isDefaultIgnorableForShaping(codepoint);
        const shaped_codepoint = try mirroredCodepointForRtlShaping(font, glyph_index_cache, codepoint, lookup_options);
        const source_cluster = if (lookup_options.direction == .rtl and
            unicode.inheritsPreviousClusterInRtlShaping(codepoint) and
            clusters.items.len != 0)
            clusters.items[clusters.items.len - 1] - cluster_base
        else
            cluster;
        try glyph_ids.append(buffer.allocator, try glyphIndexWithOptionalCache(font, glyph_index_cache, shaped_codepoint));
        try codepoints.append(buffer.allocator, codepoint);
        try clusters.append(buffer.allocator, cluster_base + source_cluster);
        try source_ends.append(buffer.allocator, cluster_base + it.i);
        try glyph_source_indices.append(buffer.allocator, glyph_source_indices.items.len);
        try ligature_components.append(buffer.allocator, defaultLigatureComponentInfo(glyph_source_indices.items.len - 1));
    }
    if (shape_profile) |p| {
        p.cmap_ns += shapeProfileElapsed(cmap_start, profile_io);
        p.glyph_count += glyph_ids.items.len;
    }

    if (shouldShapeInNativeDirection(lookup_options)) {
        reverseScratchGlyphOrderForNativeDirection(scratch);
    }

    const gdef_start = shapeProfileNow(shape_profile, profile_io);
    var owned_gdef_metadata: ?GdefLookupMetadata = null;
    const gdef_metadata = try gdefMetadataForShaping(font, buffer.allocator, buffer.gdef_metadata_cache, &owned_gdef_metadata);
    if (shape_profile) |p| p.gdef_ns += shapeProfileElapsed(gdef_start, profile_io);
    defer if (owned_gdef_metadata) |*metadata| metadata.deinit(buffer.allocator);

    // Keep source metadata parallel to glyph ids through GSUB. GPOS MarkLigPos
    // needs the original component sources for a ligature glyph; otherwise a
    // mark after a ligature can only guess a component from post-substitution
    // mark order.
    var gsub_options = gsub.LookupOptions{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        .features = lookup_options.features,
        .vertical = lookup_options.writing_mode.isVertical(),
        .apply_all_if_unselected = false,
        .glyph_source_indices = glyph_source_indices,
        .ligature_components = ligature_components,
        .source_codepoints = codepoints.items,
        .shape_profile = shape_profile,
        .profile_io = profile_io,
    };
    const gsub_start = shapeProfileNow(shape_profile, profile_io);
    const gsub_after_proof = if (buffer.gsub_table_proof_cache) |proof_cache| proof: {
        try proof_cache.prove(font);
        break :proof true;
    } else false;
    if (buffer.lookup_selection_cache) |selection_cache| {
        gsub_options.lookup_accelerators = try selection_cache.gsubLookupAccelerators(font);
    }
    if (lookup_options.script_tag == .arab and codepoints.items.len != 0) {
        reorderArabicMarksForShaping(glyph_ids, glyph_source_indices, ligature_components, codepoints.items);
        try joining_forms.resize(buffer.allocator, codepoints.items.len);
        try unicode.resolveJoiningForms(codepoints.items, joining_forms.items);
        try source_features.resize(buffer.allocator, joining_forms.items.len);
        for (joining_forms.items, source_features.items) |form, *feature| {
            feature.* = joiningFormFeatureTag(form);
        }
        var arabic_options = gsub_options;
        arabic_options.source_features = source_features.items;

        // Unicode Arabic joining forms are position-scoped and must run after
        // canonical/localized substitutions but before required ligatures.
        // Keeping the order explicit mirrors the OpenType Arabic shaping plan
        // without globally enabling mutually-exclusive form features.
        var applications_buf: [12]gsub.FeatureApplication = undefined;
        var application_count: usize = 0;
        const planned_features = [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("ccmp"), .auto_zwj = false },
            .{ .tag = unicode.tag("locl"), .auto_zwj = false },
            .{ .tag = unicode.tag("isol"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("fina"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("medi"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("init"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
            .{ .tag = unicode.tag("calt"), .auto_zwj = false },
            .{ .tag = unicode.tag("rclt"), .auto_zwj = false },
            .{ .tag = unicode.tag("liga"), .auto_zwj = false },
            .{ .tag = unicode.tag("clig"), .auto_zwj = false },
        };
        for (planned_features) |application| {
            if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
            applications_buf[application_count] = application;
            application_count += 1;
        }
        if (scriptPositionFeatureApplication(lookup_options.script_position)) |application| {
            applications_buf[application_count] = application;
            application_count += 1;
        }
        if (shape_profile) |profile| {
            for (applications_buf[0..application_count], 0..) |application, stage_index| {
                const stage_start = shapeProfileNow(shape_profile, profile_io);
                const lookup_count_before = profile.gsub_lookup_count;
                if (gsub_after_proof) {
                    try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(&.{application}, glyph_ids, buffer.allocator, arabic_options, gdef_metadata.*);
                } else {
                    try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(&.{application}, glyph_ids, buffer.allocator, arabic_options, gdef_metadata.*);
                }
                if (stage_index < profile.arabic_stage_ns.len) {
                    profile.arabic_stage_ns[stage_index] += shapeProfileElapsed(stage_start, profile_io);
                    profile.arabic_stage_lookup_count[stage_index] += profile.gsub_lookup_count - lookup_count_before;
                    profile.arabic_stage_count = @max(profile.arabic_stage_count, stage_index + 1);
                }
            }
        } else {
            if (gsub_after_proof and buffer.lookup_selection_cache != null) {
                const plan = try buffer.lookup_selection_cache.?.gsubFeatureLookupPlan(font, applications_buf[0..application_count], arabic_options, gdef_metadata.*);
                try font.applyGsubFeatureLookupPlanUsingGdefAfterProof(plan, glyph_ids, buffer.allocator, arabic_options, gdef_metadata.*);
            } else if (gsub_after_proof) {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(applications_buf[0..application_count], glyph_ids, buffer.allocator, arabic_options, gdef_metadata.*);
            } else {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(applications_buf[0..application_count], glyph_ids, buffer.allocator, arabic_options, gdef_metadata.*);
            }
        }
    } else {
        if (buffer.lookup_selection_cache) |selection_cache| {
            gsub_options.selected_lookups = try selection_cache.gsubLookups(font, gsub_options, gdef_metadata.*);
        }
        if (gsub_after_proof) {
            try font.applyGsubWithOptionsUsingGdefAfterProof(glyph_ids, buffer.allocator, gsub_options, gdef_metadata.*);
        } else {
            try font.applyGsubWithOptionsUsingGdefForShaping(glyph_ids, buffer.allocator, gsub_options, gdef_metadata.*);
        }
        if (scriptPositionFeatureApplication(lookup_options.script_position)) |application| {
            if (gsub_after_proof) {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(&.{application}, glyph_ids, buffer.allocator, gsub_options, gdef_metadata.*);
            } else {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(&.{application}, glyph_ids, buffer.allocator, gsub_options, gdef_metadata.*);
            }
        }
    }

    if (shape_profile) |p| p.gsub_ns += shapeProfileElapsed(gsub_start, profile_io);

    const gpos_adjustments = &scratch.gpos_adjustments;
    const gpos_start = shapeProfileNow(shape_profile, profile_io);
    var gpos_options = gpos.LookupOptions{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        .features = lookup_options.features,
        .apply_all_if_unselected = false,
        .run_has_gdef_marks = runHasGdefMarks(glyph_ids.items, gdef_metadata.*),
        .glyph_source_indices = glyph_source_indices.items,
        .ligature_components = ligature_components.items,
        .shape_profile = shape_profile,
        .profile_io = profile_io,
    };
    if (buffer.lookup_selection_cache) |selection_cache| {
        gpos_options.lookup_accelerators = try selection_cache.gposLookupAccelerators(font);
        gpos_options.selected_lookups = try selection_cache.gposLookups(font, gpos_options, gdef_metadata.*);
    }
    if (buffer.gpos_table_proof_cache) |proof_cache| {
        try proof_cache.prove(font);
        try font.collectGposAdjustmentsWithOptionsUsingGdefAfterProof(glyph_ids.items, gpos_adjustments, buffer.allocator, gpos_options, gdef_metadata.*);
    } else {
        try font.collectGposAdjustmentsWithOptionsUsingGdefForShaping(glyph_ids.items, gpos_adjustments, buffer.allocator, gpos_options, gdef_metadata.*);
    }
    if (shape_profile) |p| p.gpos_ns += shapeProfileElapsed(gpos_start, profile_io);

    const position_start = shapeProfileNow(shape_profile, profile_io);
    std.sort.heap(gpos.Adjustment, gpos_adjustments.items, {}, adjustmentIndexLessThan);
    // GPOS adjustments and legacy kern are accumulated in font units, then
    // scaled into user-space coordinates for the final GlyphPosition stream.
    var previous_glyph: ?GlyphId = null;
    var adjustment_cursor: usize = 0;
    const kern_lookup = if (!lookup_options.writing_mode.isVertical() and shapingFeatureEnabled(unicode.tag("kern"), lookup_options.features, true))
        try font.kernLookupForShaping()
    else
        null;
    const invisible_glyph_id = if (has_default_ignorable)
        try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ')
    else
        0;
    for (glyph_ids.items, 0..) |glyph_id, index| {
        const source_index = if (index < glyph_source_indices.items.len)
            @min(glyph_source_indices.items[index], codepoints.items.len -| 1)
        else
            @min(index, codepoints.items.len -| 1);
        const source_span = sourceSpanForGlyph(index, source_index, clusters.items, source_ends.items, ligature_components.items) orelse
            SourceSpan{ .start = cluster_base, .end = cluster_base };
        const metrics = try horizontalMetricsWithOptionalCache(font, metrics_cache, glyph_id);
        const glyph_class = gdef_metadata.glyphClass(glyph_id);
        if (kern_lookup) |lookup| {
            if (previous_glyph) |previous| {
                const previous_adjustment = findAdjustmentSorted(gpos_adjustments.items, index - 1, &adjustment_cursor);
                if (!previous_adjustment.pair_positioned) {
                    const kern = try lookup.kerning(previous, glyph_id);
                    if (kern != 0 and buffer.glyphs.items.len > 0) {
                        buffer.glyphs.items[buffer.glyphs.items.len - 1].x_advance += @as(f32, @floatFromInt(kern)) * scale;
                    }
                }
            }
        }
        const adjustment = findAdjustmentSorted(gpos_adjustments.items, index, &adjustment_cursor);
        var adjustment_x_advance = if (adjustment.x_advance_absolute)
            @as(f32, @floatFromInt(adjustment.x_advance)) - @as(f32, @floatFromInt(metrics.advance_width))
        else
            @as(f32, @floatFromInt(adjustment.x_advance));
        var x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) * scale;
        if (adjustment.mark_attachment) {
            const advance_to_base = if (adjustment.mark_base_index) |base_index|
                advanceBetweenGlyphs(buffer.glyphs.items, base_index, index)
            else if (buffer.glyphs.items.len > 0)
                buffer.glyphs.items[buffer.glyphs.items.len - 1].x_advance
            else
                0.0;
            // The accumulated advance between base and mark is already in
            // user-space units. Apply it after scaling the font-unit GPOS
            // placement instead of converting the combined value back to i16
            // font units; long runs can legitimately exceed the i16 placement
            // range even though the final f32 offset is perfectly usable.
            x_offset = markAttachmentXOffset(adjustment.x_placement, advance_to_base, scale);
            adjustment_x_advance = -@as(f32, @floatFromInt(metrics.advance_width));
        }
        const source_codepoint = if (codepoints.items.len == 0) 0 else codepoints.items[source_index];
        const hide_default_ignorable = isDefaultIgnorableForShaping(source_codepoint);
        const output_glyph_id = if (hide_default_ignorable and invisible_glyph_id != 0) invisible_glyph_id else glyph_id;
        const base_advance = if (hide_default_ignorable or (glyph_class == .mark and !adjustment.mark_attachment)) 0 else metrics.advance_width;
        const horizontal_advance = if (hide_default_ignorable)
            0
        else
            (@as(f32, @floatFromInt(base_advance)) + adjustment_x_advance) * scale;
        const use_sideways_vertical_advance = lookup_options.writing_mode.isVertical() and
            glyphUsesSidewaysAdvance(source_codepoint, lookup_options.text_orientation);
        const vertical_metrics = if (lookup_options.writing_mode.isVertical())
            try verticalMetricsWithOptionalCache(font, metrics_cache, glyph_id)
        else
            null;
        const vertical_advance = if (use_sideways_vertical_advance)
            horizontal_advance
        else if (vertical_metrics) |value|
            @as(f32, @floatFromInt(value.advance_height)) * scale
        else
            font_size;
        const vertical_x_offset = if (vertical_metrics) |_|
            // OpenType's synthesized vertical origin is centered in the
            // horizontal advance box. This keeps upright ideographs centered
            // on the column without rotating the entire run.
            (@as(f32, @floatFromInt(metrics.advance_width)) * 0.5) * scale
        else
            0.0;
        const vertical_y_offset = if (vertical_metrics) |value|
            @as(f32, @floatFromInt(value.top_side_bearing)) * scale
        else
            0.0;
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = output_glyph_id,
            .codepoint = source_codepoint,
            .cluster = source_span.start,
            .source_byte_len = source_span.end - source_span.start,
            .x_advance = if (lookup_options.writing_mode.isVertical()) 0.0 else horizontal_advance,
            .y_advance = if (hide_default_ignorable) 0 else if (lookup_options.writing_mode.isVertical()) vertical_advance else @as(f32, @floatFromInt(adjustment.y_advance)) * scale,
            .x_offset = if (hide_default_ignorable) 0 else if (lookup_options.writing_mode.isVertical()) vertical_x_offset + @as(f32, @floatFromInt(adjustment.x_placement)) * scale else x_offset,
            .y_offset = if (hide_default_ignorable) 0 else if (lookup_options.writing_mode.isVertical()) vertical_y_offset + @as(f32, @floatFromInt(adjustment.y_placement)) * scale else @as(f32, @floatFromInt(adjustment.y_placement)) * scale,
            .vertical = lookup_options.writing_mode.isVertical(),
        });
        previous_glyph = glyph_id;
    }
    if (shape_profile) |p| p.position_ns += shapeProfileElapsed(position_start, profile_io);
}

fn shapeProfileNow(profile: ?*ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null) std.Io.Clock.now(.awake, io.?).nanoseconds else 0;
}

fn shapeProfileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

fn joiningFormFeatureTag(form: unicode.JoiningForm) u32 {
    return switch (form) {
        .isolated => unicode.tag("isol"),
        .initial => unicode.tag("init"),
        .medial => unicode.tag("medi"),
        .final => unicode.tag("fina"),
        .none => 0,
    };
}

fn shapingFeatureEnabled(feature: u32, overrides: []const unicode.FeatureOverride, default_enabled: bool) bool {
    for (overrides) |override| {
        if (override.tag == feature) return override.enabled;
    }
    return default_enabled;
}

fn scriptPositionFeatureApplication(position: ScriptPosition) ?gsub.FeatureApplication {
    return switch (position) {
        .normal => null,
        .superscript => .{ .tag = unicode.tag("sups") },
        .subscript => .{ .tag = unicode.tag("subs") },
    };
}

fn shouldShapeInNativeDirection(options: LookupOptions) bool {
    if (!options.reorder_bidi and !options.native_direction_shaping) return false;
    if (options.writing_mode.isVertical()) return false;
    const native_direction = textDirectionFromBidiClass(unicode.openTypeScriptHorizontalDirection(options.script_tag) orelse return false);
    return options.direction != native_direction;
}

fn textDirectionFromBidiClass(direction: unicode.BidiClass) TextDirection {
    return if (direction == .rtl) .rtl else .ltr;
}

fn reverseScratchGlyphOrderForNativeDirection(scratch: *layout_scratch.ShapeScratch) void {
    const len = scratch.glyph_ids.items.len;
    if (len < 2) return;

    var group_start: usize = 0;
    var index: usize = 1;
    while (index <= len) : (index += 1) {
        if (index < len and scratchGlyphCluster(scratch, index) == scratchGlyphCluster(scratch, index - 1)) continue;
        reverseScratchGlyphRange(scratch, group_start, index);
        group_start = index;
    }
    reverseScratchGlyphRange(scratch, 0, len);
}

fn scratchGlyphCluster(scratch: *const layout_scratch.ShapeScratch, glyph_index: usize) usize {
    if (glyph_index >= scratch.glyph_source_indices.items.len) return glyph_index;
    const source_index = scratch.glyph_source_indices.items[glyph_index];
    if (source_index >= scratch.clusters.items.len) return source_index;
    return scratch.clusters.items[source_index];
}

fn reverseScratchGlyphRange(scratch: *layout_scratch.ShapeScratch, start: usize, end: usize) void {
    var left = start;
    var right = end;
    while (left + 1 < right) {
        right -= 1;
        swapScratchGlyphs(scratch, left, right);
        left += 1;
    }
}

fn swapScratchGlyphs(scratch: *layout_scratch.ShapeScratch, a: usize, b: usize) void {
    std.mem.swap(GlyphId, &scratch.glyph_ids.items[a], &scratch.glyph_ids.items[b]);
    std.mem.swap(usize, &scratch.glyph_source_indices.items[a], &scratch.glyph_source_indices.items[b]);
    std.mem.swap(gpos.LigatureComponentInfo, &scratch.ligature_components.items[a], &scratch.ligature_components.items[b]);
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

fn markAttachmentXOffset(x_placement_font_units: i16, advance_to_base: f32, scale: f32) f32 {
    return @as(f32, @floatFromInt(x_placement_font_units)) * scale - advance_to_base;
}

fn glyphUsesSidewaysAdvance(_: u21, orientation: TextOrientation) bool {
    return switch (orientation) {
        .sideways => true,
        .upright => false,
        // Keep mixed-mode advances on the existing vertical metrics path until
        // the Linux vertical gate has a true browser/CSS writing-mode
        // reference.  The current Pango gravity reference is still sensitive to
        // its rotated-line geometry, so changing mixed defaults here would
        // regress the committed quality signal even though explicit sideways
        // text benefits from horizontal advances.
        .mixed => false,
    };
}

fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn mirroredCodepointForRtlShaping(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, codepoint: u21, lookup_options: LookupOptions) !u21 {
    if (lookup_options.direction != .rtl) return codepoint;
    if (lookup_options.writing_mode.isVertical()) return codepoint;
    const mirrored = unicode.mirroredCodepoint(codepoint);
    if (mirrored == codepoint) return codepoint;
    return if (try glyphIndexWithOptionalCache(font, glyph_index_cache, mirrored) != 0) mirrored else codepoint;
}

fn reorderArabicMarksForShaping(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), ligature_components: *std.ArrayList(gpos.LigatureComponentInfo), codepoints: []const u21) void {
    var run_start: ?usize = null;
    for (glyph_source_indices.items, 0..) |source_index, glyph_index| {
        const modified_class = arabicMarkSortClass(source_index, codepoints);
        if (modified_class == 0) {
            if (run_start) |start| reorderArabicMarkRun(glyph_ids, glyph_source_indices, ligature_components, codepoints, start, glyph_index);
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = glyph_index;
    }
    if (run_start) |start| reorderArabicMarkRun(glyph_ids, glyph_source_indices, ligature_components, codepoints, start, glyph_source_indices.items.len);
}

fn reorderArabicMarkRun(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), ligature_components: *std.ArrayList(gpos.LigatureComponentInfo), codepoints: []const u21, start: usize, end: usize) void {
    var i = start + 1;
    while (i < end) : (i += 1) {
        var j = i;
        while (j > start and arabicMarkSortClass(glyph_source_indices.items[j - 1], codepoints) > arabicMarkSortClass(glyph_source_indices.items[j], codepoints)) : (j -= 1) {
            std.mem.swap(GlyphId, &glyph_ids.items[j - 1], &glyph_ids.items[j]);
            std.mem.swap(usize, &glyph_source_indices.items[j - 1], &glyph_source_indices.items[j]);
            std.mem.swap(gpos.LigatureComponentInfo, &ligature_components.items[j - 1], &ligature_components.items[j]);
        }
    }
}

fn arabicMarkSortClass(source_index: usize, codepoints: []const u21) u8 {
    if (source_index >= codepoints.len) return 0;
    return unicode.arabicModifiedCombiningClassForShaping(codepoints[source_index]);
}

fn isDefaultIgnorableForShaping(codepoint: u21) bool {
    return unicode.isDefaultIgnorableForShaping(codepoint);
}

fn glyphIndexWithOptionalCache(font: *const Font, cache: ?*GlyphIndexCache, codepoint: u21) !GlyphId {
    if (cache) |glyph_cache| return try glyph_cache.glyphIndex(font, codepoint);
    return try font.glyphIndex(codepoint);
}

fn runHasGdefMarks(glyphs: []const GlyphId, metadata: GdefLookupMetadata) bool {
    const classes = metadata.glyph_classes orelse return true;
    for (glyphs) |glyph| {
        if (glyph < classes.len and classes[glyph] == @intFromEnum(GlyphClass.mark)) return true;
    }
    return false;
}

fn horizontalMetricsWithOptionalCache(font: *const Font, cache: ?*GlyphMetricsCache, glyph_id: GlyphId) !GlyphMetrics {
    if (cache) |metrics_cache| return try metrics_cache.horizontalMetrics(font, glyph_id);
    const raw = try font.horizontalMetrics(glyph_id);
    return .{
        .advance_width = raw.advance_width,
        .left_side_bearing = raw.left_side_bearing,
    };
}

fn verticalMetricsWithOptionalCache(font: *const Font, cache: ?*GlyphMetricsCache, glyph_id: GlyphId) !?VerticalGlyphMetrics {
    if (cache) |metrics_cache| {
        return metrics_cache.verticalMetrics(font, glyph_id) catch |err| switch (err) {
            // Some deployed CJK fonts advertise optional vhea/vmtx tables with
            // unusable header line metrics. Vertical shaping must still retain
            // its y-axis contract and vert substitutions; fall back to one em
            // advance instead of abandoning shaping and rendering horizontally.
            error.InvalidMetrics => null,
            else => return err,
        };
    }
    const raw = font.verticalMetrics(glyph_id) catch |err| switch (err) {
        error.InvalidMetrics => null,
        else => return err,
    };
    return if (raw) |value| .{
        .advance_height = value.advance_height,
        .top_side_bearing = value.top_side_bearing,
    } else null;
}

test "font fallback diagnostics expose deterministic variation and missing glyph decisions" {
    const test_font = @import("test_font.zig");
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

test "shape quality diagnostics summarize fallback coverage and missing glyphs" {
    const test_font = @import("test_font.zig");
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
    try std.testing.expectEqual(@as(usize, 2), report.script_runs.len);
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
    const test_font = @import("test_font.zig");
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
    const test_font = @import("test_font.zig");
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

    var report = try diagnoseClusterCaretConsistencyForLayout(allocator, text, paragraph);
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

test "vertical shaping uses vmtx and keeps horizontal behavior isolated" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const horizontal = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expect(horizontal.width() > 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), horizontal.height(), 0.001);
    try std.testing.expect(!horizontal.glyphs[0].vertical);

    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 2), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    for (vertical.glyphs) |glyph| {
        try std.testing.expect(glyph.vertical);
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 20), glyph.y_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 8), glyph.x_offset, 0.001);
    }
}

test "vertical sideways text uses horizontal advance for rotated glyphs" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const sideways = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .sideways },
    );
    try std.testing.expectEqual(@as(usize, 2), sideways.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16), sideways.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32), sideways.height(), 0.001);

    const mixed = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), mixed.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), mixed.height(), 0.001);

    const upright = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), upright.glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), upright.height(), 0.001);
}

test "vertical shaped cache and fallback runs preserve independent y pens" {
    const test_font = @import("test_font.zig");
    const primary_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildVerticalMetricsTtf(std.testing.allocator);
    defer std.testing.allocator.free(fallback_bytes);
    var primary = try Font.parse(std.testing.allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(std.testing.allocator, fallback_bytes);
    defer fallback.deinit();

    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();
    var cache = ShapedRunCache.init(std.testing.allocator);
    defer cache.deinit();

    const horizontal = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{},
    );
    try std.testing.expect(horizontal.width() > 0);
    const vertical = try TextShaper.shapeUtf8CascadeWithCaches(
        cascade,
        null,
        null,
        null,
        &cache,
        &buffer,
        "AA",
        20,
        .{ .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectApproxEqAbs(@as(f32, 40), vertical.height(), 0.001);
    try std.testing.expectEqual(@as(usize, 2), cache.entries.items.len);
    try std.testing.expectEqual(WritingMode.horizontal_tb, cache.entries.items[0].key.plan.writing_mode);
    try std.testing.expectEqual(WritingMode.vertical_lr, cache.entries.items[1].key.plan.writing_mode);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.runs[0].y_offset, 0.001);
}

fn adjustmentIndexLessThan(_: void, lhs: gpos.Adjustment, rhs: gpos.Adjustment) bool {
    return lhs.index < rhs.index;
}

fn findAdjustmentSorted(adjustments: []const gpos.Adjustment, index: usize, cursor: *usize) gpos.Adjustment {
    while (cursor.* < adjustments.len and adjustments[cursor.*].index < index) {
        cursor.* += 1;
    }
    if (cursor.* < adjustments.len and adjustments[cursor.*].index == index) return adjustments[cursor.*];
    return .{ .index = index };
}

test "sorted adjustment cursor finds sparse GPOS entries in linear order" {
    const adjustments = [_]gpos.Adjustment{
        .{ .index = 1, .x_advance = 10 },
        .{ .index = 3, .x_placement = -4, .pair_positioned = true },
    };
    var cursor: usize = 0;

    const missing_0 = findAdjustmentSorted(&adjustments, 0, &cursor);
    try std.testing.expectEqual(@as(usize, 0), missing_0.index);
    try std.testing.expectEqual(@as(i16, 0), missing_0.x_advance);
    try std.testing.expectEqual(@as(usize, 0), cursor);

    const found_1 = findAdjustmentSorted(&adjustments, 1, &cursor);
    try std.testing.expectEqual(@as(i16, 10), found_1.x_advance);
    try std.testing.expectEqual(@as(usize, 0), cursor);

    const missing_2 = findAdjustmentSorted(&adjustments, 2, &cursor);
    try std.testing.expectEqual(@as(usize, 2), missing_2.index);
    try std.testing.expectEqual(@as(usize, 1), cursor);

    const found_3 = findAdjustmentSorted(&adjustments, 3, &cursor);
    try std.testing.expectEqual(@as(i16, -4), found_3.x_placement);
    try std.testing.expect(found_3.pair_positioned);
}

test "mark attachment offsets stay in user space for long advances" {
    const scale: f32 = 12.0 / 1000.0;

    try std.testing.expectApproxEqAbs(
        @as(f32, 24.0 - 48.0),
        markAttachmentXOffset(2000, 48.0, scale),
        0.0001,
    );

    // Large paragraphs can place a mark many glyph advances after its base
    // before MarkBase/MarkLig positioning pulls it back. This offset is well
    // within f32 layout range but outside the i16 font-unit storage used by
    // raw GPOS records; it must not be converted back through i16.
    try std.testing.expectApproxEqAbs(
        @as(f32, 12.0 - 50000.0),
        markAttachmentXOffset(1000, 50000.0, scale),
        0.01,
    );
}
