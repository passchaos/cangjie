const std = @import("std");
const arabic_normalization = @import("arabic_normalization.zig");
const attachment = @import("attachment.zig");
const Font = @import("font.zig").Font;
const fallback_mark = @import("fallback_mark.zig");
const GdefLookupMetadata = @import("font.zig").GdefLookupMetadata;
const GlyphClass = @import("font.zig").GlyphClass;
const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const khmer = @import("khmer.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const gsub = @import("gsub.zig");
const indic = @import("indic.zig");
const layout_cache = @import("layout_cache.zig");
const layout_scratch = @import("layout_scratch.zig");
const myanmar = @import("myanmar.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const bidi = @import("text/bidi.zig");
const space_fallback = @import("space_fallback.zig");
const unicode = @import("unicode.zig");
const unicode_glyph_fallback = @import("unicode_glyph_fallback.zig");
const use_shaper = @import("use_shaper.zig");
pub const ShapeStageProfile = @import("shape_profile.zig").ShapeStageProfile;
pub const GdefMetadataCache = layout_cache.GdefMetadataCache;
pub const GlyphIndexCache = layout_cache.GlyphIndexCache;
pub const GlyphMetrics = layout_cache.GlyphMetrics;
pub const GlyphMetricsCache = layout_cache.GlyphMetricsCache;
pub const GposTableProofCache = layout_cache.GposTableProofCache;
pub const GsubTableProofCache = layout_cache.GsubTableProofCache;
pub const LookupSelectionCache = layout_cache.LookupSelectionCache;
pub const VerticalGlyphMetrics = layout_cache.VerticalGlyphMetrics;
pub const ClusterLevel = shaping_metadata.ClusterLevel;

/// One positioned glyph after cmap mapping, GSUB substitution, and GPOS/kern
/// adjustment. `cluster` is a byte offset into the original UTF-8 text, so
/// hit testing and selection can map glyph positions back to source text.
pub const GlyphPosition = struct {
    glyph_id: GlyphId,
    /// Optional synthetic glyph id used only for shaping-diagnostic parity
    /// knobs such as HarfBuzz's not-found variation-selector glyph. The real
    /// OpenType pipeline still uses `glyph_id` for GSUB, GPOS, metrics, and
    /// rendering.
    synthetic_glyph_id: ?u32 = null,
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

    pub fn outputGlyphId(self: GlyphPosition) u32 {
        return self.synthetic_glyph_id orelse self.glyph_id;
    }
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
    /// Normalized variation-space coordinates in fvar axis order after avar
    /// mapping. The default empty slice preserves legacy/default-instance
    /// shaping and lets glyph metric caches stay keyed only by glyph id.
    normalized_variation_coords: []const f32 = &.{},
    /// Optional HarfBuzz-compatible synthetic glyph id for unsupported
    /// variation selectors. This is a diagnostics/parity switch: it keeps the
    /// unsupported selector visible to GSUB/GPOS matching and reports this glyph
    /// id with zero advance, without changing the real font glyph id.
    not_found_variation_selector_glyph: ?u32 = null,
    /// Optional item context used for HarfBuzz-style shaping of a substring.
    ///
    /// The context is not emitted. It only influences joining decisions at the
    /// item boundaries, matching the common use of hb_buffer pre/post context.
    context_before: []const u8 = &.{},
    context_after: []const u8 = &.{},
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    cluster_level: ?ClusterLevel = null,
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
    variation_hash: u64 = 0,
    context_hash: u64 = 0,
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    not_found_variation_selector_glyph: ?u32 = null,
    cluster_level: ?ClusterLevel = null,

    pub fn fromText(text: []const u8, options: ShapeOptions) ShapePlanKey {
        const infer_both = options.script_tag == null and options.language_tag == null;
        const inferred = if (infer_both)
            unicode.inferOpenTypeProperties(text)
        else
            undefined;
        return .{
            .direction = options.direction,
            .reorder_bidi = options.reorder_bidi,
            .native_direction_shaping = options.native_direction_shaping,
            .writing_mode = options.writing_mode,
            .text_orientation = options.text_orientation,
            .script_tag = options.script_tag orelse unicode.openTypeScriptTag(if (infer_both) inferred.script else unicode.inferOpenTypeScript(text)),
            .language_tag = options.language_tag orelse if (infer_both) inferred.language else unicode.inferOpenTypeLanguageTag(text),
            .script_position = options.script_position,
            .feature_hash = featureOverridesHash(options.features),
            .variation_hash = normalizedVariationCoordsHash(options.normalized_variation_coords),
            .context_hash = contextHash(options.context_before, options.context_after),
            .beginning_of_text = options.beginning_of_text,
            .end_of_text = options.end_of_text,
            .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
            .cluster_level = options.cluster_level,
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

pub const WrapMode = enum {
    /// Preserve explicit Unicode hard breaks but do not introduce lines to
    /// satisfy `max_width`.
    no_wrap,
    /// Greedily wrap at UAX #14 opportunities, with grapheme-boundary
    /// emergency breaks when an unbreakable fragment exceeds `max_width`.
    word,
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
    wrap_mode: WrapMode = .word,
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
    /// Optional shaping controls used before wrapping. Paragraph layout keeps
    /// these beside spacing/line options so higher-level styled text can drive
    /// GSUB/GPOS without doing a separate pre-shape pass.
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    features: []const unicode.FeatureOverride = &.{},
    /// Normalized variation-space coordinates forwarded to shaping. Paragraph
    /// layout itself only consumes shaped advances, but variable font metrics
    /// must be selected before line wrapping.
    normalized_variation_coords: []const f32 = &.{},
};

/// A laid-out visual line. Glyph and run ranges are indexes into the owning
/// ParagraphLayout arrays, keeping line objects small and cheap to copy.
pub const ParagraphLine = struct {
    glyph_start: usize,
    glyph_len: usize,
    run_start: usize,
    run_len: usize,
    /// Logical UTF-8 source range represented by this visual line.
    ///
    /// Soft wrapping excludes discarded boundary whitespace from the next
    /// line but keeps it in the preceding line's source range. Explicit line
    /// separators are included in the preceding line. A trailing hard break
    /// therefore creates an empty final line at `text.len`.
    byte_start: usize,
    byte_len: usize,
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

    pub fn byteEnd(self: ParagraphLine) usize {
        return self.byte_start + self.byte_len;
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

/// Width-independent, owning paragraph content.
///
/// HarfBuzz shapes one homogeneous buffer, while Parley retains shaped
/// paragraph content and rebuilds only visual lines when the available width
/// changes. This object is Cangjie's equivalent boundary: it owns immutable
/// source bytes, glyphs, font runs, and Unicode boundary analysis, but no line
/// geometry. Fonts referenced by `runs` must outlive this object and every
/// layout returned from it.
pub const ShapedParagraph = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const CascadeRun,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const unicode.LineBreak,
    default_metrics: BaselineMetrics,
    shape_key: ShapePlanKey,
    needs_bidi_reorder: bool,

    pub fn deinit(self: *ShapedParagraph) void {
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.grapheme_clusters);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn shapedText(self: *const ShapedParagraph) ShapedText {
        return .{ .glyphs = self.glyphs, .runs = self.runs };
    }

    /// Reflow this immutable shaping result into reusable output storage.
    ///
    /// The returned slices borrow `reflow` and remain valid until its next
    /// `layout` call or deinitialization. A separate `ReflowBuffer` may be used
    /// concurrently for the same paragraph; one buffer itself is single-user.
    pub fn layout(self: *const ShapedParagraph, reflow: *ReflowBuffer, options: ParagraphOptions) !ParagraphLayout {
        try validateParagraphOptions(options);
        if (!paragraphOptionsMatchShapeKey(self.text, options, self.shape_key)) {
            return error.ParagraphShapingOptionsChanged;
        }
        try reflow.restore(self);
        errdefer reflow.buffer.clear();
        try buildParagraphLines(
            &reflow.buffer,
            self.text,
            options,
            self.default_metrics,
            self.grapheme_clusters,
            self.line_breaks,
        );
        if (self.needs_bidi_reorder) {
            try applyParagraphLineBidiVisualOrder(&reflow.buffer, self.text, options.direction);
        }
        return reflow.buffer.paragraphLayout();
    }
};

/// Reusable scratch/output storage for reflowing a `ShapedParagraph`.
///
/// Reflow restores pristine shaped glyphs and runs before applying tabs,
/// spacing, line limits, or ellipsis. This prevents width changes from
/// accumulating advance adjustments or permanently truncating the shaped
/// paragraph.
pub const ReflowBuffer = struct {
    buffer: LayoutBuffer,

    pub fn init(allocator: std.mem.Allocator) ReflowBuffer {
        return .{ .buffer = LayoutBuffer.init(allocator) };
    }

    pub fn deinit(self: *ReflowBuffer) void {
        self.buffer.deinit();
        self.* = undefined;
    }

    fn restore(self: *ReflowBuffer, paragraph: *const ShapedParagraph) !void {
        self.buffer.clear();
        try self.buffer.glyphs.appendSlice(self.buffer.allocator, paragraph.glyphs);
        errdefer self.buffer.clear();
        try self.buffer.runs.appendSlice(self.buffer.allocator, paragraph.runs);
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

    /// Pick one font for an entire extended grapheme cluster.
    ///
    /// Modern layout engines keep combining sequences, emoji ZWJ sequences,
    /// and Indic conjunct requests atomic while choosing fallback. Splitting at
    /// scalar boundaries prevents GSUB/GPOS from seeing the sequence and can
    /// strand marks in a font unrelated to their base. Default-ignorables do
    /// not require nominal cmap coverage, but a variation selector requires an
    /// explicit/default UVS record in the same font as its base.
    pub fn selectFontForCluster(self: FontCascade, cluster: []const u8) !usize {
        if (!std.unicode.utf8ValidateSlice(cluster)) return error.InvalidUtf8;
        return try selectFontForClusterWithGlyphCache(self, null, cluster);
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

    var clusters = unicode.graphemeClustersAssumeValid(text);
    while (clusters.next()) |cluster| {
        const cluster_end = cluster.byte_start + cluster.byte_len;
        const cluster_text = text[cluster.byte_start..cluster_end];
        const font_index = try selectFontForClusterWithGlyphCache(cascade, null, cluster_text);
        const font = cascade.fonts[font_index];

        var it = std.unicode.Utf8Iterator{ .bytes = cluster_text, .i = 0 };
        while (it.i < cluster_text.len) {
            const local_start = it.i;
            const codepoint = it.nextCodepoint() orelse break;
            if (isVariationSelector(codepoint) or isClusterCoverageIgnorable(codepoint)) {
                // Detached selectors and join controls participate in cluster
                // selection but do not produce visible fallback decisions.
                continue;
            }

            if (try arabicCompositionForFontAt(font, null, codepoint, cluster_text, it.i)) |composition| {
                try decisions.append(allocator, .{
                    .byte_start = cluster.byte_start + local_start,
                    .byte_len = composition.byte_end - local_start,
                    .codepoint = composition.codepoint,
                    .font_index = font_index,
                    .glyph_id = composition.glyph_id,
                });
                it.i = composition.byte_end;
                continue;
            }

            var byte_len = it.i - local_start;
            var variation_selector: ?u21 = null;
            var used_variation_mapping = false;
            if (nextVariationSelector(cluster_text, it.i)) |selector| {
                variation_selector = selector;
                _ = it.nextCodepoint();
                byte_len = it.i - local_start;
                used_variation_mapping = try font.variationGlyphIndex(codepoint, selector) != null;
            }

            const glyph_id = if (variation_selector) |selector|
                try font.glyphIndexWithVariation(codepoint, selector)
            else
                try font.glyphIndex(codepoint);

            try decisions.append(allocator, .{
                .byte_start = cluster.byte_start + local_start,
                .byte_len = byte_len,
                .codepoint = codepoint,
                .variation_selector = variation_selector,
                .font_index = font_index,
                .glyph_id = glyph_id,
                .used_variation_mapping = used_variation_mapping,
            });
        }
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
    }, defaultBaselineMetrics(cascade.fonts[0], font_size), null, null);
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
    cluster_entries: std.StringHashMap(usize),
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FontFallbackCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(u21, usize).init(allocator),
            .cluster_entries = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *FontFallbackCache) void {
        self.freeClusterKeys();
        self.cluster_entries.deinit();
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *FontFallbackCache) void {
        self.freeClusterKeys();
        self.cluster_entries.clearRetainingCapacity();
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

    pub fn selectFontForCluster(self: *FontFallbackCache, cascade: FontCascade, glyph_index_cache: ?*GlyphIndexCache, cluster: []const u8) !usize {
        if (cluster.len == 1 and cluster[0] < 0x80) {
            if (glyph_index_cache) |cache| return try self.selectFontWithGlyphCache(cascade, cache, cluster[0]);
            return try self.selectFont(cascade, cluster[0]);
        }
        if (self.cluster_entries.get(cluster)) |font_index| {
            self.hits += 1;
            return font_index;
        }

        self.misses += 1;
        const font_index = try selectFontForClusterWithGlyphCache(cascade, glyph_index_cache, cluster);
        const owned_cluster = try self.allocator.dupe(u8, cluster);
        errdefer self.allocator.free(owned_cluster);
        try self.cluster_entries.put(owned_cluster, font_index);
        return font_index;
    }

    fn freeClusterKeys(self: *FontFallbackCache) void {
        var iterator = self.cluster_entries.iterator();
        while (iterator.next()) |entry| self.allocator.free(entry.key_ptr.*);
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
    profile_fast_path: bool = false,
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

        // Select fallback for complete grapheme/shaping clusters. Keeping a
        // combining sequence or emoji ZWJ chain in one segment lets the chosen
        // font's GSUB/GPOS observe the whole sequence instead of producing
        // unrelated glyph runs for the base and its continuations.
        var segment_start: usize = 0;
        var segment_font_index: ?usize = null;
        var pen_x: f32 = 0;
        var pen_y: f32 = 0;

        if (textIsAscii(text)) {
            // ASCII is one grapheme per byte (CRLF still chooses the same font
            // for both controls). Preserve the old one-pass fallback loop so
            // the dominant Latin/UI path does not pay for Unicode clustering.
            for (text, 0..) |codepoint, cluster_start| {
                const font_index = try selectFontWithOptionalCache(cascade, fallback_cache, glyph_index_cache, codepoint);
                if (segment_font_index == null) {
                    segment_start = cluster_start;
                    segment_font_index = font_index;
                } else if (segment_font_index.? != font_index) {
                    const next_pen = try appendCascadeRun(
                        cascade.fonts[segment_font_index.?],
                        metrics_cache,
                        glyph_index_cache,
                        segment_font_index.?,
                        buffer,
                        text[segment_start..cluster_start],
                        font_size,
                        segment_start,
                        .{ .x = pen_x, .y = pen_y },
                        lookupOptionsForText(text[segment_start..cluster_start], options),
                    );
                    pen_x = next_pen.x;
                    pen_y = next_pen.y;
                    segment_start = cluster_start;
                    segment_font_index = font_index;
                }
            }
        } else {
            var clusters = unicode.graphemeClustersAssumeValid(text);
            while (clusters.next()) |cluster| {
                const cluster_end = cluster.byte_start + cluster.byte_len;
                const cluster_text = text[cluster.byte_start..cluster_end];
                const font_index = try selectFontForCluster(
                    cascade,
                    fallback_cache,
                    glyph_index_cache,
                    cluster_text,
                );
                if (segment_font_index == null) {
                    segment_start = cluster.byte_start;
                    segment_font_index = font_index;
                } else if (segment_font_index.? != font_index) {
                    const next_pen = try appendCascadeRun(
                        cascade.fonts[segment_font_index.?],
                        metrics_cache,
                        glyph_index_cache,
                        segment_font_index.?,
                        buffer,
                        text[segment_start..cluster.byte_start],
                        font_size,
                        segment_start,
                        .{ .x = pen_x, .y = pen_y },
                        lookupOptionsForText(text[segment_start..cluster.byte_start], options),
                    );
                    pen_x = next_pen.x;
                    pen_y = next_pen.y;
                    segment_start = cluster.byte_start;
                    segment_font_index = font_index;
                }
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

    /// Shape and retain a width-independent paragraph.
    ///
    /// Unlike `layoutParagraphUtf8`, this performs GSUB/GPOS and fallback only
    /// once. Call `ShapedParagraph.layout` with different `ParagraphOptions`
    /// to rebuild visual lines without reshaping.
    pub fn shapeParagraphUtf8(allocator: std.mem.Allocator, cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ShapedParagraph {
        return try shapeParagraphUtf8WithCaches(allocator, cascade, null, null, null, null, buffer, text, font_size, options);
    }

    pub fn shapeParagraphUtf8WithCaches(
        allocator: std.mem.Allocator,
        cascade: FontCascade,
        fallback_cache: ?*FontFallbackCache,
        metrics_cache: ?*GlyphMetricsCache,
        glyph_index_cache: ?*GlyphIndexCache,
        shaped_cache: ?*ShapedRunCache,
        buffer: *LayoutBuffer,
        text: []const u8,
        font_size: f32,
        options: ParagraphOptions,
    ) !ShapedParagraph {
        try validateParagraphOptions(options);
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;
        const shape_options = shapeOptionsForParagraph(options);
        _ = try shapeUtf8CascadeWithCaches(
            cascade,
            fallback_cache,
            metrics_cache,
            glyph_index_cache,
            shaped_cache,
            buffer,
            text,
            font_size,
            shape_options,
        );
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        const logical_shaped = buffer.shapedText();

        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);
        const owned_glyphs = try allocator.dupe(GlyphPosition, logical_shaped.glyphs);
        errdefer allocator.free(owned_glyphs);
        const owned_runs = try allocator.dupe(CascadeRun, logical_shaped.runs);
        errdefer allocator.free(owned_runs);
        const grapheme_clusters = try unicode.itemizeGraphemeClusters(allocator, text);
        errdefer allocator.free(grapheme_clusters);
        const line_breaks = try unicode.itemizeLineBreaks(allocator, text);
        errdefer allocator.free(line_breaks);

        return .{
            .allocator = allocator,
            .text = owned_text,
            .glyphs = owned_glyphs,
            .runs = owned_runs,
            .grapheme_clusters = grapheme_clusters,
            .line_breaks = line_breaks,
            .default_metrics = defaultBaselineMetrics(cascade.fonts[0], font_size),
            .shape_key = ShapePlanKey.fromText(text, shape_options),
            .needs_bidi_reorder = options.direction == .rtl or textHasRtlBidiClass(text),
        };
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
        _ = try shapeUtf8CascadeFullyCachedWithOptions(cascade, fallback_cache, metrics_cache, glyph_index_cache, buffer, text, font_size, shapeOptionsForParagraph(options));
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        try buildParagraphLines(buffer, text, options, defaultBaselineMetrics(cascade.fonts[0], font_size), null, null);
        if (options.direction == .rtl or textHasRtlBidiClass(text)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        return buffer.paragraphLayout();
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try validateParagraphOptions(options);
        _ = try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, shaped_cache, buffer, text, font_size, shapeOptionsForParagraph(options));
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        try buildParagraphLines(buffer, text, options, defaultBaselineMetrics(cascade.fonts[0], font_size), null, null);
        if (options.direction == .rtl or textHasRtlBidiClass(text)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
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
    try validateShapingUtf8(options.context_before);
    try validateShapingUtf8(options.context_after);
    try validateShapingFontSize(font_size);
    try validateFeatureOverrides(options.features);
    try validateNormalizedVariationCoords(options.normalized_variation_coords);
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

fn validateNormalizedVariationCoords(coords: []const f32) !void {
    for (coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) return error.BadSfnt;
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
    try validateFeatureOverrides(options.features);
    try validateNormalizedVariationCoords(options.normalized_variation_coords);
}

fn shapeOptionsForParagraph(options: ParagraphOptions) ShapeOptions {
    return .{
        .direction = options.direction,
        // Paragraph shaping retains logical source order so line breaking sees
        // monotonic clusters. Individual script segments still shape in their
        // OpenType-native direction; visual bidi order is applied after each
        // line's source range is known.
        .reorder_bidi = false,
        .native_direction_shaping = true,
        .script_tag = options.script_tag,
        .language_tag = options.language_tag,
        .features = options.features,
        .normalized_variation_coords = options.normalized_variation_coords,
    };
}

fn paragraphOptionsMatchShapeKey(text: []const u8, options: ParagraphOptions, shape_key: ShapePlanKey) bool {
    return shapePlanKeysEqual(ShapePlanKey.fromText(text, shapeOptionsForParagraph(options)), shape_key);
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
                .lookup = .{
                    .script = script_run.script,
                    .script_tag = options.script_tag orelse unicode.openTypeScriptTag(script_run.script),
                    .script_tag_explicit = options.script_tag != null,
                    .language_tag = effectiveLanguageTag(run_text, options),
                    // Script-run itemization already decoded this slice, but does
                    // not currently retain an ASCII summary. Keep this path
                    // conservative rather than introducing another scan.
                    .direction = options.direction,
                    .reorder_bidi = options.reorder_bidi,
                    .native_direction_shaping = options.native_direction_shaping,
                    .features = options.features,
                    .writing_mode = options.writing_mode,
                    .text_orientation = options.text_orientation,
                    .normalized_variation_coords = options.normalized_variation_coords,
                },
                .all_ascii = false,
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
    if (shouldApplyBidiVisualOrderWithAsciiProof(text, options, lookup_options.all_ascii)) {
        try applyBidiVisualOrder(buffer, text, options.direction, font);
    }
    if (shape_profile) |p| p.bidi_ns += shapeProfileElapsed(bidi_start, profile_io);
    return buffer.run(font, font_size);
}

fn shouldApplyBidiVisualOrder(text: []const u8, options: ShapeOptions) bool {
    return shouldApplyBidiVisualOrderWithAsciiProof(text, options, false);
}

fn shouldApplyBidiVisualOrderWithAsciiProof(text: []const u8, options: ShapeOptions, all_ascii: bool) bool {
    if (!options.reorder_bidi) return false;
    if (options.writing_mode.isVertical()) return false;
    if (options.direction == .rtl) return true;
    // Default property inference already scans the complete run before cmap
    // construction. Reuse its all-ASCII result instead of decoding every byte
    // again after shaping merely to prove that no strong RTL scalar exists.
    if (all_ascii) return false;
    return textHasRtlBidiClass(text);
}

fn textHasRtlBidiClass(text: []const u8) bool {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        // No ASCII scalar has a strong RTL class. Latin word lists and common
        // UI strings can therefore reject paragraph-level bidi reordering
        // without entering the all-script classifier for every byte.
        if (codepoint <= 0x7f) continue;
        if (unicode.bidiClassForCodepoint(codepoint) == .rtl) return true;
    }
    return false;
}

test "RTL presence scan ignores ASCII without hiding RTL scripts" {
    try std.testing.expect(!textHasRtlBidiClass("ASCII 123 ()"));
    try std.testing.expect(textHasRtlBidiClass("ASCII \u{05d0}"));
    try std.testing.expect(textHasRtlBidiClass("فارسی"));
    try std.testing.expect(!shouldApplyBidiVisualOrderWithAsciiProof("ASCII 123 ()", .{}, true));
    // Explicit RTL remains authoritative even when the source is all ASCII.
    try std.testing.expect(shouldApplyBidiVisualOrderWithAsciiProof("ASCII", .{ .direction = .rtl }, true));
}

fn shapeCascadeSegmentInto(cascade: FontCascade, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: ResolvedLookupOptions) !PenPosition {
    // Script itemization happens outside this helper. This pass only performs
    // fallback segmentation inside that script run, so each append keeps the
    // same OpenType script/language lookup selection.
    var segment_start: usize = 0;
    var segment_font_index: ?usize = null;
    var next_pen = pen;

    if (textIsAscii(text)) {
        for (text, 0..) |codepoint, cluster_start| {
            const font_index = try cascade.selectFont(codepoint);
            if (segment_font_index == null) {
                segment_start = cluster_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try appendCascadeRun(cascade.fonts[segment_font_index.?], null, null, segment_font_index.?, buffer, text[segment_start..cluster_start], font_size, cluster_base + segment_start, next_pen, lookup_options);
                segment_start = cluster_start;
                segment_font_index = font_index;
            }
        }
    } else {
        var clusters = unicode.graphemeClustersAssumeValid(text);
        while (clusters.next()) |cluster| {
            const cluster_end = cluster.byte_start + cluster.byte_len;
            const font_index = try cascade.selectFontForCluster(text[cluster.byte_start..cluster_end]);
            if (segment_font_index == null) {
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try appendCascadeRun(cascade.fonts[segment_font_index.?], null, null, segment_font_index.?, buffer, text[segment_start..cluster.byte_start], font_size, cluster_base + segment_start, next_pen, lookup_options);
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            }
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

const ArabicCompositionMatch = struct {
    codepoint: u21,
    glyph_id: GlyphId,
    byte_end: usize,
};

fn arabicCompositionForFontAt(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, starter: u21, text: []const u8, mark_byte_start: usize) !?ArabicCompositionMatch {
    if (mark_byte_start >= text.len) return null;
    var lookahead = std.unicode.Utf8Iterator{ .bytes = text, .i = mark_byte_start };
    const mark = lookahead.nextCodepoint() orelse return null;
    const composition = try arabic_normalization.composePairForFont(font, glyph_index_cache, starter, mark) orelse return null;
    return .{
        .codepoint = composition.codepoint,
        .glyph_id = composition.glyph_id,
        .byte_end = lookahead.i,
    };
}

fn selectFontForCluster(
    cascade: FontCascade,
    fallback_cache: ?*FontFallbackCache,
    glyph_index_cache: ?*GlyphIndexCache,
    cluster: []const u8,
) !usize {
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;
    if (cascade.fonts.len == 1) return 0;

    // One-byte clusters dominate Latin/UI shaping. Preserve the existing
    // codepoint fallback cache and its direct ASCII glyph cache for this case.
    if (cluster.len == 1 and cluster[0] < 0x80) {
        return try selectFontWithOptionalCache(cascade, fallback_cache, glyph_index_cache, cluster[0]);
    }

    if (fallback_cache) |cache| {
        return try cache.selectFontForCluster(cascade, glyph_index_cache, cluster);
    }
    return try selectFontForClusterWithGlyphCache(cascade, glyph_index_cache, cluster);
}

fn textIsAscii(text: []const u8) bool {
    for (text) |byte| {
        if (byte >= 0x80) return false;
    }
    return true;
}

fn selectFontForClusterWithGlyphCache(
    cascade: FontCascade,
    glyph_index_cache: ?*GlyphIndexCache,
    cluster: []const u8,
) !usize {
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;

    const has_variation_selector = clusterHasVariationSelector(cluster);
    if (has_variation_selector) {
        // Prefer a font that explicitly supports every UVS in the cluster.
        // Only if no such font exists do we apply OpenType's normal fallback of
        // ignoring an unsupported selector and using the base cmap glyph.
        for (cascade.fonts, 0..) |font, index| {
            if (try fontCoversCluster(font, glyph_index_cache, cluster, true)) return index;
        }
    }
    for (cascade.fonts, 0..) |font, index| {
        if (try fontCoversCluster(font, glyph_index_cache, cluster, false)) return index;
    }

    // No font covers every visible scalar. Keep the cluster atomic in the font
    // selected for its first visible scalar; missing continuations remain
    // explicit `.notdef` glyphs for diagnostics instead of being silently
    // detached into another font run.
    var it = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (isVariationSelector(codepoint) or isClusterCoverageIgnorable(codepoint)) continue;
        if (glyph_index_cache) |cache| return try selectFontUsingGlyphCache(cascade, cache, codepoint);
        return try cascade.selectFont(codepoint);
    }
    return 0;
}

fn clusterHasVariationSelector(cluster: []const u8) bool {
    var it = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (isVariationSelector(codepoint)) return true;
    }
    return false;
}

fn fontCoversCluster(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, cluster: []const u8, require_variation_mapping: bool) !bool {
    var it = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    var previous_visible: ?u21 = null;
    while (it.nextCodepoint()) |codepoint| {
        if (isVariationSelector(codepoint)) {
            if (!require_variation_mapping) continue;
            const base = previous_visible orelse return false;
            const glyph_id = (try font.variationGlyphIndex(base, codepoint)) orelse return false;
            if (glyph_id == 0) return false;
            continue;
        }
        if (isClusterCoverageIgnorable(codepoint)) continue;
        if (try arabicCompositionForFontAt(font, glyph_index_cache, codepoint, cluster, it.i)) |composition| {
            it.i = composition.byte_end;
            previous_visible = composition.codepoint;
            continue;
        }
        if (try glyphIndexWithOptionalCache(font, glyph_index_cache, codepoint) == 0) return false;
        previous_visible = codepoint;
    }
    return true;
}

fn isClusterCoverageIgnorable(codepoint: u21) bool {
    // Join controls and other default-ignorables participate in shaping but do
    // not need nominal cmap glyphs. Variation selectors are handled separately
    // because they refine the preceding scalar through cmap format 14.
    return !isVariationSelector(codepoint) and unicode.isDefaultIgnorableForShaping(codepoint);
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
    const can_reverse_in_place = single_font != null or buffer.runs.items.len <= 1;
    if (can_reverse_in_place and bidi.visualOrderInputKind(text, direction == .rtl) == .pure_rtl) {
        bidi.applyPureRtlVisualOrder(&buffer.glyphs, single_font);
        recomputeRunOffsets(buffer);
        return;
    }
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
    const glyph_cluster_index = try buildBidiGlyphClusterIndex(buffer.allocator, old_glyphs);
    defer buffer.allocator.free(glyph_cluster_index);

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
            glyph_cluster_index,
            seen,
            0,
            old_glyphs.len,
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
    glyph_cluster_index: []const BidiGlyphClusterEntry,
    seen: []bool,
    allowed_glyph_start: usize,
    allowed_glyph_end: usize,
    item: unicode.BidiMapItem,
    out_glyphs: *std.ArrayList(GlyphPosition),
    out_run_indices: *std.ArrayList(usize),
) !void {
    const range = bidiGlyphClusterRange(glyph_cluster_index, item.byte_start) orelse return;
    if (item.direction == .rtl) {
        var entry_index = range.end;
        while (entry_index > range.start) {
            entry_index -= 1;
            const glyph_index = glyph_cluster_index[entry_index].glyph_index;
            if (glyph_index < allowed_glyph_start or glyph_index >= allowed_glyph_end) continue;
            if (seen[glyph_index]) continue;
            const glyph = glyphs[glyph_index];
            const visual_codepoint = if (@max(glyph.source_byte_len, 1) == item.byte_len)
                item.visual_codepoint
            else
                null;
            try appendVisualGlyph(allocator, glyphs, old_runs, single_font, glyph_run_indices, seen, glyph_index, visual_codepoint, out_glyphs, out_run_indices);
        }
        return;
    }

    for (glyph_cluster_index[range.start..range.end]) |entry| {
        const glyph_index = entry.glyph_index;
        if (glyph_index < allowed_glyph_start or glyph_index >= allowed_glyph_end) continue;
        if (seen[glyph_index]) continue;
        const glyph = glyphs[glyph_index];
        const visual_codepoint = if (@max(glyph.source_byte_len, 1) == item.byte_len)
            item.visual_codepoint
        else
            null;
        try appendVisualGlyph(allocator, glyphs, old_runs, single_font, glyph_run_indices, seen, glyph_index, visual_codepoint, out_glyphs, out_run_indices);
    }
}

const BidiGlyphClusterEntry = struct {
    cluster: usize,
    glyph_index: usize,
};

fn buildBidiGlyphClusterIndex(allocator: std.mem.Allocator, glyphs: []const GlyphPosition) ![]BidiGlyphClusterEntry {
    const entries = try allocator.alloc(BidiGlyphClusterEntry, glyphs.len);
    var monotone = true;
    for (glyphs, entries, 0..) |glyph, *entry, glyph_index| {
        entry.* = .{ .cluster = glyph.cluster, .glyph_index = glyph_index };
        if (glyph_index != 0 and glyph.cluster < glyphs[glyph_index - 1].cluster) {
            monotone = false;
        }
    }
    // Cmap, GSUB cluster merging, and ordinary GPOS preserve monotone public
    // clusters, so the entries above are already in the exact order required
    // by binary search (equal-cluster glyph indexes were emitted ascending).
    // Script reordering and mixed native-direction runs can break that
    // invariant; retain the full stable tie-break sort only for those cases.
    if (monotone) return entries;
    std.sort.heap(BidiGlyphClusterEntry, entries, {}, bidiGlyphClusterEntryLessThan);
    return entries;
}

fn bidiGlyphClusterEntryLessThan(_: void, lhs: BidiGlyphClusterEntry, rhs: BidiGlyphClusterEntry) bool {
    if (lhs.cluster == rhs.cluster) return lhs.glyph_index < rhs.glyph_index;
    return lhs.cluster < rhs.cluster;
}

fn bidiGlyphClusterRange(entries: []const BidiGlyphClusterEntry, cluster: usize) ?struct { start: usize, end: usize } {
    var low: usize = 0;
    var high: usize = entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (entries[mid].cluster < cluster) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    const start = low;
    while (low < entries.len and entries[low].cluster == cluster) {
        low += 1;
    }
    if (start == low) return null;
    return .{ .start = start, .end = low };
}

test "bidi glyph cluster index skips or repairs ordering as needed" {
    const monotone = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 3, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
    };
    const monotone_index = try buildBidiGlyphClusterIndex(std.testing.allocator, &monotone);
    defer std.testing.allocator.free(monotone_index);
    try std.testing.expectEqualSlices(BidiGlyphClusterEntry, &.{
        .{ .cluster = 0, .glyph_index = 0 },
        .{ .cluster = 0, .glyph_index = 1 },
        .{ .cluster = 2, .glyph_index = 2 },
    }, monotone_index);

    const reordered = [_]GlyphPosition{
        .{ .glyph_id = 3, .codepoint = 'B', .cluster = 2, .x_advance = 1 },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
    };
    const reordered_index = try buildBidiGlyphClusterIndex(std.testing.allocator, &reordered);
    defer std.testing.allocator.free(reordered_index);
    try std.testing.expectEqualSlices(BidiGlyphClusterEntry, &.{
        .{ .cluster = 0, .glyph_index = 1 },
        .{ .cluster = 0, .glyph_index = 2 },
        .{ .cluster = 2, .glyph_index = 0 },
    }, reordered_index);
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

fn normalizeParagraphGlyphsToLogicalOrder(buffer: *LayoutBuffer) !void {
    if (buffer.glyphs.items.len < 2) return;
    var monotonic = true;
    for (buffer.glyphs.items[1..], buffer.glyphs.items[0 .. buffer.glyphs.items.len - 1]) |current, previous| {
        if (current.cluster < previous.cluster) {
            monotonic = false;
            break;
        }
    }
    if (monotonic) return;

    const old_runs = try buffer.allocator.dupe(CascadeRun, buffer.runs.items);
    defer buffer.allocator.free(old_runs);
    var glyph_run_indices = try buffer.allocator.alloc(usize, buffer.glyphs.items.len);
    defer buffer.allocator.free(glyph_run_indices);
    for (glyph_run_indices) |*slot| slot.* = 0;
    for (old_runs, 0..) |run, run_index| {
        const end = @min(buffer.glyphs.items.len, run.glyph_start + run.glyph_len);
        if (run.glyph_start >= end) continue;
        for (glyph_run_indices[run.glyph_start..end]) |*slot| slot.* = run_index;
    }

    const order = try buffer.allocator.alloc(usize, buffer.glyphs.items.len);
    defer buffer.allocator.free(order);
    for (order, 0..) |*slot, index| slot.* = index;
    const Context = struct {
        glyphs: []const GlyphPosition,

        fn lessThan(context: @This(), lhs: usize, rhs: usize) bool {
            const lhs_cluster = context.glyphs[lhs].cluster;
            const rhs_cluster = context.glyphs[rhs].cluster;
            if (lhs_cluster == rhs_cluster) return lhs < rhs;
            return lhs_cluster < rhs_cluster;
        }
    };
    std.sort.heap(usize, order, Context{ .glyphs = buffer.glyphs.items }, Context.lessThan);

    const old_glyphs = try buffer.allocator.dupe(GlyphPosition, buffer.glyphs.items);
    defer buffer.allocator.free(old_glyphs);
    const reordered_run_indices = try buffer.allocator.alloc(usize, order.len);
    defer buffer.allocator.free(reordered_run_indices);
    for (order, 0..) |old_index, new_index| {
        buffer.glyphs.items[new_index] = old_glyphs[old_index];
        reordered_run_indices[new_index] = glyph_run_indices[old_index];
    }
    try rebuildRunsForVisualGlyphs(buffer, old_runs, reordered_run_indices);
    recomputeRunOffsets(buffer);
}

fn applyParagraphLineBidiVisualOrder(buffer: *LayoutBuffer, text: []const u8, direction: TextDirection) !void {
    if (buffer.glyphs.items.len == 0 or buffer.lines.items.len == 0) return;

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
    const glyph_cluster_index = try buildBidiGlyphClusterIndex(buffer.allocator, old_glyphs);
    defer buffer.allocator.free(glyph_cluster_index);
    const seen = try buffer.allocator.alloc(bool, old_glyphs.len);
    defer buffer.allocator.free(seen);
    @memset(seen, false);

    var visual_glyphs: std.ArrayList(GlyphPosition) = .empty;
    defer visual_glyphs.deinit(buffer.allocator);
    var visual_run_indices: std.ArrayList(usize) = .empty;
    defer visual_run_indices.deinit(buffer.allocator);

    const base_direction: unicode.BidiClass = if (direction == .rtl) .rtl else .ltr;
    for (buffer.lines.items) |*line| {
        const visual_start = visual_glyphs.items.len;
        const old_line_start = line.glyph_start;
        const old_line_end = old_line_start + line.glyph_len;
        if (line.byte_len != 0 and old_line_start < old_line_end) {
            var bidi_map = try unicode.buildBidiMap(
                buffer.allocator,
                text[line.byte_start..line.byteEnd()],
                base_direction,
            );
            defer bidi_map.deinit();
            for (bidi_map.items) |item_value| {
                var item = item_value;
                item.byte_start += line.byte_start;
                try appendVisualGlyphsForBidiItem(
                    buffer.allocator,
                    old_glyphs,
                    old_runs,
                    null,
                    glyph_run_indices,
                    glyph_cluster_index,
                    seen,
                    old_line_start,
                    old_line_end,
                    item,
                    &visual_glyphs,
                    &visual_run_indices,
                );
            }
        }
        // Whitespace discarded by wrapping and multi-scalar source folding can
        // leave glyphs outside the map. Preserve only unmatched glyphs that
        // belong to this logical line; discarded whitespace intentionally
        // stays absent from every visual line.
        for (old_line_start..old_line_end) |glyph_index| {
            if (seen[glyph_index]) continue;
            try appendVisualGlyph(
                buffer.allocator,
                old_glyphs,
                old_runs,
                null,
                glyph_run_indices,
                seen,
                glyph_index,
                null,
                &visual_glyphs,
                &visual_run_indices,
            );
        }
        line.glyph_start = visual_start;
        line.glyph_len = visual_glyphs.items.len - visual_start;
    }

    // Preserve shaped glyphs omitted from visual lines (normally wrap
    // whitespace) after the visible stream so source/caret metadata remains
    // available without assigning them to a line.
    for (old_glyphs, 0..) |_, glyph_index| {
        if (seen[glyph_index]) continue;
        try appendVisualGlyph(
            buffer.allocator,
            old_glyphs,
            old_runs,
            null,
            glyph_run_indices,
            seen,
            glyph_index,
            null,
            &visual_glyphs,
            &visual_run_indices,
        );
    }
    if (visual_glyphs.items.len != old_glyphs.len) return error.InvalidBidiMap;

    buffer.glyphs.clearRetainingCapacity();
    try buffer.glyphs.appendSlice(buffer.allocator, visual_glyphs.items);
    try rebuildRunsForVisualGlyphs(buffer, old_runs, visual_run_indices.items);
    for (buffer.lines.items) |*line| {
        const run_range = runRangeForGlyphs(
            buffer.runs.items,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
        );
        line.run_start = run_range.start;
        line.run_len = run_range.len;
    }
    recomputeRunOffsets(buffer);
}

fn buildParagraphLines(
    buffer: *LayoutBuffer,
    text: []const u8,
    options: ParagraphOptions,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const unicode.LineBreak,
) !void {
    buffer.lines.clearRetainingCapacity();
    const line_height = options.line_height orelse default_metrics.lineHeight();
    const line_metrics = metricsForLineHeight(default_metrics, line_height);
    const max_width = if (options.max_width > 0) options.max_width else std.math.inf(f32);
    const wrap_width = if (options.wrap_mode == .no_wrap) std.math.inf(f32) else max_width;
    const alignment = defaultAlignment(options);
    var line_start: usize = 0;
    var line_byte_start: usize = 0;
    var line_width: f32 = 0;
    var last_break: ?usize = null;
    var width_at_break: f32 = 0;
    var y: f32 = 0;
    var index: usize = 0;
    var line_in_paragraph: usize = 0;
    var terminal_emergency_line_committed = false;
    const max_lines = options.max_lines orelse std.math.maxInt(usize);
    const space_advance = defaultSpaceAdvance(buffer.glyphs.items);
    const tab_stop = @as(f32, @floatFromInt(@max(1, options.tab_width))) * space_advance;
    // Retained paragraphs carry font-independent grapheme analysis so width
    // changes do not repeat UAX #29 work. Legacy one-shot layout computes a
    // temporary array only when emergency wrapping can need it.
    var owned_graphemes: ?[]unicode.GraphemeCluster = null;
    defer if (owned_graphemes) |clusters| buffer.allocator.free(clusters);
    const grapheme_clusters = analyzed_graphemes orelse clusters: {
        if (options.wrap_mode == .no_wrap) break :clusters &.{};
        owned_graphemes = try unicode.itemizeGraphemeClusters(buffer.allocator, text);
        break :clusters owned_graphemes.?;
    };
    var line_breaks = LineBreakCursor.init(text, analyzed_line_breaks);

    // Greedy line breaking tracks the most recent soft break. When a line
    // overflows, it prefers that break; otherwise it breaks at the overflowing
    // grapheme cluster so long words and CJK runs still make progress. UAX #14
    // opportunities are pulled only as glyph source ranges are consumed rather
    // than materialized into a paragraph-sized side array. This mirrors the
    // streaming boundary stage used by unicode-linebreak and keeps reflow's
    // transient memory independent of the number of legal break positions.
    //
    // Falling back at grapheme boundaries remains critical for clusters that
    // shape into multiple glyphs, such as base+combining-mark sequences when a
    // font lacks mark attachment: splitting inside that cluster would put one
    // user-visible character on two different lines.
    glyph_loop: while (index < buffer.glyphs.items.len) : (index += 1) {
        var glyph = &buffer.glyphs.items[index];
        if (isMandatoryLineBreak(glyph.codepoint)) {
            const break_end_index = if (glyph.codepoint == '\r' and index + 1 < buffer.glyphs.items.len and buffer.glyphs.items[index + 1].codepoint == '\n') index + 2 else index + 1;
            const line_byte_end = glyphSourceEnd(buffer.glyphs.items[break_end_index - 1]);
            try appendParagraphLine(buffer, line_start, index, line_byte_start, line_byte_end, line_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
            if (buffer.lines.items.len >= max_lines) {
                try truncateParagraphLines(buffer, max_lines, options.ellipsis, max_width, alignment, true);
                return;
            }
            y += line_height + options.paragraph_spacing;
            line_breaks.discardThrough(glyphSourceEnd(buffer.glyphs.items[break_end_index - 1]));
            line_start = break_end_index;
            line_byte_start = line_byte_end;
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
        const current_line_limit = lineWidthLimit(line_in_paragraph, wrap_width, options);
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
            var next_line_start = break_end;
            trimLeadingSoftBreaks(buffer.glyphs.items, &next_line_start);
            // Boundary whitespace is omitted from both visual glyph ranges but
            // still belongs to the preceding line's logical source range.
            // Advancing the byte boundary through `next_line_start` keeps line
            // ranges contiguous and gives per-line bidi the exact source slice.
            const line_byte_end = byteEndForGlyphPrefix(buffer.glyphs.items, next_line_start, line_byte_start);
            try appendParagraphLine(buffer, line_start, break_end, line_byte_start, line_byte_end, break_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
            if (buffer.lines.items.len >= max_lines) {
                try truncateParagraphLines(buffer, max_lines, options.ellipsis, max_width, alignment, true);
                return;
            }
            y += line_height;
            line_in_paragraph += 1;
            line_start = next_line_start;
            line_byte_start = byteEndForGlyphPrefix(buffer.glyphs.items, line_start, line_byte_end);
            line_width = lineWidth(buffer.glyphs.items[line_start .. index + 1]);
            terminal_emergency_line_committed = break_end == buffer.glyphs.items.len;
            last_break = null;
            width_at_break = 0;
        }
        const atom_continues = index + 1 < buffer.glyphs.items.len and
            glyphClusterStart(buffer.glyphs.items[index + 1]) == glyphClusterStart(glyph.*);
        if (!atom_continues) {
            const glyph_source_end = glyphSourceEnd(glyph.*);
            while (line_breaks.nextThrough(glyph_source_end)) |line_break| {
                switch (line_break.kind) {
                    .soft => recordSoftLineBreak(buffer.glyphs.items, line_break.byte_offset, index, line_start, line_width, &last_break, &width_at_break),
                    .hard => {},
                }
            }
        }
    }

    // A final emergency break may consume the complete last shaped atom. In
    // that case `line_start == glyph_count`; appending again would fabricate an
    // empty trailing line even though the source contains no hard terminator.
    if (!terminal_emergency_line_committed) {
        try appendParagraphLine(buffer, line_start, buffer.glyphs.items.len, line_byte_start, text.len, line_width, line_metrics, y, alignment, max_width, lineIndent(line_in_paragraph, options));
    }
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
    const current_source_end = glyphSourceEnd(current);
    if (byte_offset > current.cluster and byte_offset < current_source_end) {
        // The Unicode opportunity falls inside a source span collapsed by
        // shaping (for example, a GSUB ligature). Reusing the current glyph
        // stream across that boundary would be incorrect; HarfBuzz marks this
        // situation UNSAFE_TO_BREAK and Parley consumes the shaped atom whole.
        return;
    }
    if (byte_offset == current_source_end) {
        // The caller invokes this only after reaching the last output glyph of
        // the source atom. This is the overwhelmingly common case and avoids a
        // linear search through every glyph accumulated on the current line.
        const break_index = index + 1;
        if (break_index > line_start) {
            last_break.* = break_index;
            width_at_break.* = line_width;
        }
        return;
    }
    const break_index = glyphIndexForSourceBoundary(glyphs, byte_offset, line_start, index + 1) orelse @min(index + 1, glyphs.len);
    if (break_index > line_start) {
        last_break.* = break_index;
        width_at_break.* = lineWidth(glyphs[line_start..break_index]);
    }
}

test "soft line break mapping never splits a shaped source atom" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 2,
            .x_advance = 10,
        },
        .{
            .glyph_id = 2,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 2,
            .x_advance = 5,
        },
    };
    var last_break: ?usize = null;
    var width_at_break: f32 = 0;

    // A boundary inside a ligature/source span is unsafe without reshaping.
    recordSoftLineBreak(&glyphs, 1, 1, 0, 15, &last_break, &width_at_break);
    try std.testing.expectEqual(@as(?usize, null), last_break);

    // A boundary at the atom's source end consumes every output glyph.
    recordSoftLineBreak(&glyphs, 2, 1, 0, 15, &last_break, &width_at_break);
    try std.testing.expectEqual(@as(?usize, 2), last_break);
    try std.testing.expectApproxEqAbs(@as(f32, 15), width_at_break, 0.001);
}

const LineBreakCursor = struct {
    iterator: unicode.LineBreakIterator,
    analyzed: ?[]const unicode.LineBreak = null,
    analyzed_index: usize = 0,
    pending: ?unicode.LineBreak = null,

    fn init(text: []const u8, analyzed: ?[]const unicode.LineBreak) LineBreakCursor {
        return .{
            .iterator = unicode.lineBreaksAssumeValid(text),
            .analyzed = analyzed,
        };
    }

    /// Return the next boundary whose source position has already been covered
    /// by shaped glyphs. Retained paragraphs read pre-analyzed opportunities;
    /// one-shot layout uses one-item iterator lookahead without allocating a
    /// complete boundary list.
    fn nextThrough(self: *LineBreakCursor, byte_offset: usize) ?unicode.LineBreak {
        const candidate = if (self.analyzed) |breaks|
            if (self.analyzed_index < breaks.len) breaks[self.analyzed_index] else return null
        else candidate: {
            if (self.pending == null) self.pending = self.iterator.next();
            break :candidate self.pending orelse return null;
        };
        if (candidate.byte_offset > byte_offset) return null;
        if (self.analyzed != null) {
            self.analyzed_index += 1;
        } else {
            self.pending = null;
        }
        return candidate;
    }

    fn discardThrough(self: *LineBreakCursor, byte_offset: usize) void {
        while (self.nextThrough(byte_offset) != null) {}
    }
};

fn isMandatoryLineBreak(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
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
    // MultipleSubst and other one-to-many transformations can emit adjacent
    // glyphs with the same source cluster. Source extent alone cannot tell
    // whether the current output glyph is the last member of that atom, so do
    // not commit an emergency line until the following glyph starts another
    // source cluster. This matches Parley's rule that a shaped atom (including
    // all glyphs of a ligature/multi-output cluster) is consumed as a whole.
    const cluster_continues = index + 1 < glyphs.len and
        glyphClusterStart(glyphs[index + 1]) == current_cluster_start;
    if (!cluster_continues and glyphSourceEnd(glyphs[index]) >= current_cluster_end) {
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

fn byteEndForGlyphPrefix(glyphs: []const GlyphPosition, glyph_end: usize, fallback: usize) usize {
    var byte_end = fallback;
    // Logical line byte boundaries are independent of visual glyph order. A
    // prefix scan is therefore intentionally source-oriented: it finds the
    // largest source end represented before the visual split even when bidi
    // clusters inside that prefix are not monotonic.
    for (glyphs[0..@min(glyph_end, glyphs.len)]) |glyph| {
        byte_end = @max(byte_end, glyphSourceEnd(glyph));
    }
    return byte_end;
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

fn appendParagraphLine(buffer: *LayoutBuffer, glyph_start: usize, glyph_end: usize, byte_start: usize, byte_end: usize, width: f32, metrics: BaselineMetrics, y: f32, alignment: TextAlign, max_width: f32, indent: f32) !void {
    const available_width = lineWidthLimitForIndent(max_width, indent);
    const x = indent + alignedLineX(width, available_width, alignment);
    const run_range = runRangeForGlyphs(buffer.runs.items, glyph_start, glyph_end);
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = run_range.start,
        .run_len = run_range.len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
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

fn appendCascadeRun(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, font_index: usize, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, pen: PenPosition, lookup_options: ResolvedLookupOptions) !PenPosition {
    const glyph_start = buffer.glyphs.items.len;
    try shapeSegmentInto(font, metrics_cache, glyph_index_cache, buffer, text, font_size, cluster_base, lookup_options);
    const glyph_len = buffer.glyphs.items.len - glyph_start;
    // A segment made solely of default-ignorables/variation selectors may
    // legitimately emit no glyphs. Do not retain a zero-length font run: it
    // has no owner in the flat glyph stream and destabilizes diagnostics and
    // line-to-run range calculations.
    if (glyph_len == 0) return pen;
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
    script: unicode.Script = .common,
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    script_tag_explicit: bool = false,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    direction: TextDirection = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    script_position: ScriptPosition = .normal,
    features: []const unicode.FeatureOverride = &.{},
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    normalized_variation_coords: []const f32 = &.{},
    not_found_variation_selector_glyph: ?u32 = null,
    context_before: []const u8 = &.{},
    context_after: []const u8 = &.{},
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    cluster_level: ?ClusterLevel = null,
    run_has_decimal_number: bool = false,
    run_has_letter: bool = false,
};

const ResolvedLookupOptions = struct {
    lookup: LookupOptions,
    all_ascii: bool,
};

fn lookupOptionsForText(text: []const u8, options: ShapeOptions) ResolvedLookupOptions {
    const infer_language = options.language_tag == null;
    const inferred = if (infer_language)
        unicode.inferOpenTypeProperties(text)
    else
        undefined;
    const script = if (infer_language) inferred.script else unicode.inferOpenTypeScript(text);
    return .{ .lookup = .{
        .script = script,
        .script_tag = options.script_tag orelse unicode.openTypeScriptTag(script),
        .script_tag_explicit = options.script_tag != null,
        .language_tag = options.language_tag orelse inferred.language,
        .direction = options.direction,
        .reorder_bidi = options.reorder_bidi,
        .native_direction_shaping = options.native_direction_shaping,
        .script_position = options.script_position,
        .features = options.features,
        .writing_mode = options.writing_mode,
        .text_orientation = options.text_orientation,
        .normalized_variation_coords = options.normalized_variation_coords,
        .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
        .context_before = options.context_before,
        .context_after = options.context_after,
        .beginning_of_text = options.beginning_of_text,
        .end_of_text = options.end_of_text,
        .cluster_level = options.cluster_level,
    }, .all_ascii = infer_language and inferred.all_ascii };
}

fn effectiveLanguageTag(text: []const u8, options: ShapeOptions) unicode.OpenTypeLanguageTag {
    return options.language_tag orelse unicode.inferOpenTypeLanguageTag(text);
}

fn featureOverridesHash(features: []const unicode.FeatureOverride) u64 {
    // Reserve zero for the overwhelmingly common no-override plan and avoid
    // constructing/finalizing Wyhash per run. Non-empty plans retain their
    // established hash representation for cache compatibility.
    if (features.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    for (features) |feature| {
        hasher.update(std.mem.asBytes(&feature.tag));
        const value = feature.effectiveValue();
        hasher.update(std.mem.asBytes(&value));
    }
    return hasher.final();
}

fn normalizedVariationCoordsHash(coords: []const f32) u64 {
    // Match GlyphMetricsCache's established default-instance key. No axis
    // coordinates means there are no bytes to distinguish, so hashing the
    // empty length only adds work to every default shaping plan.
    if (coords.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&coords.len));
    for (coords) |coord| {
        const bits: u32 = @bitCast(coord);
        hasher.update(std.mem.asBytes(&bits));
    }
    return hasher.final();
}

fn contextHash(before: []const u8, after: []const u8) u64 {
    if (before.len == 0 and after.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&before.len));
    hasher.update(before);
    hasher.update(std.mem.asBytes(&after.len));
    hasher.update(after);
    return hasher.final();
}

test "default shape-plan inputs use zero hashes" {
    try std.testing.expectEqual(@as(u64, 0), featureOverridesHash(&.{}));
    try std.testing.expectEqual(@as(u64, 0), normalizedVariationCoordsHash(&.{}));
    try std.testing.expectEqual(@as(u64, 0), contextHash("", ""));

    // Non-empty values must still take the payload-sensitive hash path.
    try std.testing.expect(featureOverridesHash(&.{
        .{ .tag = unicode.tag("liga"), .enabled = false },
    }) != 0);
    try std.testing.expect(normalizedVariationCoordsHash(&.{0.25}) != 0);
    try std.testing.expect(contextHash("a", "") != 0);
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
        a.feature_hash == b.feature_hash and
        a.variation_hash == b.variation_hash and
        a.context_hash == b.context_hash and
        a.beginning_of_text == b.beginning_of_text and
        a.end_of_text == b.end_of_text and
        a.not_found_variation_selector_glyph == b.not_found_variation_selector_glyph and
        a.cluster_level == b.cluster_level;
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

fn shapeSegmentInto(font: *const Font, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, cluster_base: usize, resolved_lookup_options: ResolvedLookupOptions) !void {
    const scale = font_size / @as(f32, @floatFromInt(font.units_per_em));
    var selected_lookup_options = resolved_lookup_options.lookup;
    const explicit_script_tag = if (resolved_lookup_options.lookup.script_tag_explicit) resolved_lookup_options.lookup.script_tag else null;
    const layout_scripts: layout_cache.LayoutScriptSelections = if (buffer.lookup_selection_cache) |cache|
        try cache.layoutScripts(font, resolved_lookup_options.lookup.script, explicit_script_tag)
    else
        .{
            .gsub = try font.selectGsubScriptForShaping(resolved_lookup_options.lookup.script, explicit_script_tag),
            .gpos = try font.selectGposScriptForShaping(resolved_lookup_options.lookup.script, explicit_script_tag),
        };
    const gsub_script = layout_scripts.gsub;
    const gpos_script = layout_scripts.gpos;
    if (gsub_script.tag) |selected_tag| {
        selected_lookup_options.script_tag = selected_tag;
    }
    const gpos_script_tag = gpos_script.tag orelse selected_lookup_options.script_tag;
    const scratch = &buffer.shape_scratch;
    scratch.clear();
    const glyph_ids = &scratch.glyph_ids;
    const codepoints = &scratch.codepoints;
    const clusters = &scratch.clusters;
    const source_ends = &scratch.source_ends;
    const glyph_source_indices = &scratch.glyph_source_indices;
    const glyph_cluster_indices = &scratch.glyph_cluster_indices;
    const glyph_substituted = &scratch.glyph_substituted;
    const glyph_stage_substituted = &scratch.glyph_stage_substituted;
    const ligature_components = &scratch.ligature_components;
    const joining_forms = &scratch.joining_forms;
    const source_features = &scratch.source_features;
    const source_syllables = &scratch.source_syllables;
    const source_rphf_substituted = &scratch.source_rphf_substituted;
    const source_pref_substituted = &scratch.source_pref_substituted;
    const glyph_output_indices = &scratch.glyph_output_indices;
    const stch_actions = &scratch.stch_actions;

    const shape_profile = buffer.shape_profile;
    const profile_io = buffer.profile_io;
    const cmap_start = shapeProfileNow(shape_profile, profile_io);

    // Keep three parallel arrays through GSUB: glyph ids are mutable, while
    // codepoints and clusters retain source-text identity for rendering,
    // hit-testing, and debug output after substitutions.
    // Valid UTF-8 has at most one retained source per input byte; variation
    // selectors only lower that count. Reserve every parallel cmap array once
    // so the scalar loop does not repeat eight capacity checks per glyph.
    try glyph_ids.ensureUnusedCapacity(buffer.allocator, text.len);
    try codepoints.ensureUnusedCapacity(buffer.allocator, text.len);
    try clusters.ensureUnusedCapacity(buffer.allocator, text.len);
    try source_ends.ensureUnusedCapacity(buffer.allocator, text.len);
    try glyph_source_indices.ensureUnusedCapacity(buffer.allocator, text.len);
    try glyph_cluster_indices.ensureUnusedCapacity(buffer.allocator, text.len);
    try glyph_substituted.ensureUnusedCapacity(buffer.allocator, text.len);
    try ligature_components.infos.ensureUnusedCapacity(buffer.allocator, text.len);

    var has_default_ignorable = false;
    var run_has_decimal_number = false;
    var run_has_letter = false;
    var default_ignorable_invisible_glyph_id: ?GlyphId = null;
    if (resolved_lookup_options.all_ascii and selected_lookup_options.direction == .ltr) {
        // `lookupOptionsForText` already scanned the complete validated run to
        // infer script/language. Reuse its all-ASCII proof: one byte is one
        // source scalar, no variation selector/default-ignorable exists, and
        // LTR shaping needs neither bidi mirroring nor inherited clustering.
        for (text, 0..) |byte, cluster| {
            const glyph_id = try glyphIndexWithOptionalCache(font, glyph_index_cache, byte);
            run_has_decimal_number = run_has_decimal_number or isShapeNativeDirectionDecimalNumber(byte);
            run_has_letter = run_has_letter or isShapeNativeDirectionLetter(byte);
            glyph_ids.appendAssumeCapacity(glyph_id);
            codepoints.appendAssumeCapacity(byte);
            clusters.appendAssumeCapacity(cluster_base + cluster);
            source_ends.appendAssumeCapacity(cluster_base + cluster + 1);
            glyph_source_indices.appendAssumeCapacity(glyph_source_indices.items.len);
            glyph_cluster_indices.appendAssumeCapacity(glyph_cluster_indices.items.len);
            glyph_substituted.appendAssumeCapacity(false);
            ligature_components.infos.appendAssumeCapacity(.{});
        }
    } else {
        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (it.i < text.len) {
            const cluster = it.i;
            const codepoint = it.nextCodepoint() orelse break;
            run_has_decimal_number = run_has_decimal_number or isShapeNativeDirectionDecimalNumber(codepoint);
            run_has_letter = run_has_letter or isShapeNativeDirectionLetter(codepoint);
            if (isVariationSelector(codepoint)) {
                if (glyph_ids.items.len != 0) {
                    if (try font.variationGlyphIndex(codepoints.items[codepoints.items.len - 1], codepoint)) |variant_glyph| {
                        glyph_ids.items[glyph_ids.items.len - 1] = variant_glyph;
                        source_ends.items[source_ends.items.len - 1] = cluster_base + it.i;
                        continue;
                    }
                    const selector_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, codepoint);
                    has_default_ignorable = true;
                    source_ends.items[source_ends.items.len - 1] = cluster_base + it.i;
                    glyph_ids.appendAssumeCapacity(selector_glyph);
                    codepoints.appendAssumeCapacity(codepoint);
                    const source_cluster = if ((selected_lookup_options.cluster_level == null or selected_lookup_options.cluster_level.?.groupsGraphemes()) and clusters.items.len != 0)
                        clusters.items[clusters.items.len - 1] - cluster_base
                    else
                        cluster;
                    clusters.appendAssumeCapacity(cluster_base + source_cluster);
                    source_ends.appendAssumeCapacity(cluster_base + it.i);
                    glyph_source_indices.appendAssumeCapacity(glyph_source_indices.items.len);
                    const cluster_owner_index = if (source_cluster != cluster and glyph_cluster_indices.items.len != 0)
                        glyph_cluster_indices.items[glyph_cluster_indices.items.len - 1]
                    else
                        glyph_cluster_indices.items.len;
                    glyph_cluster_indices.appendAssumeCapacity(cluster_owner_index);
                    glyph_substituted.appendAssumeCapacity(false);
                    ligature_components.infos.appendAssumeCapacity(.{});
                    continue;
                }
                // Variation selectors refine the preceding scalar and do not
                // advance text themselves. Keeping them out of the glyph stream
                // preserves caret/cluster identity on the base character while
                // still allowing cmap format 14 to select emoji/text or IVS glyphs.
                continue;
            }
            has_default_ignorable = has_default_ignorable or isDefaultIgnorableForShaping(codepoint);
            if (usesThaiLaoSaraAmPreprocess(selected_lookup_options.script_tag) and isThaiLaoSaraAm(codepoint)) {
                const source_end = cluster_base + it.i;
                const cluster_level = selected_lookup_options.cluster_level orelse .monotone_graphemes;
                const source_cluster = if (cluster_level.groupsGraphemes() and clusters.items.len != 0)
                    clusters.items[clusters.items.len - 1] - cluster_base
                else
                    cluster;
                const nikhahit = nikhahitFromSaraAm(codepoint);
                const sara_aa = saraAaFromSaraAm(codepoint);
                const nikhahit_glyph = try fallbackGlyphIndexWithOptionalCache(font, glyph_index_cache, nikhahit);
                const sara_aa_glyph = try fallbackGlyphIndexWithOptionalCache(font, glyph_index_cache, sara_aa);

                const nikhahit_index = glyph_ids.items.len;
                glyph_ids.appendAssumeCapacity(nikhahit_glyph);
                codepoints.appendAssumeCapacity(nikhahit);
                clusters.appendAssumeCapacity(cluster_base + source_cluster);
                source_ends.appendAssumeCapacity(source_end);
                glyph_source_indices.appendAssumeCapacity(glyph_source_indices.items.len);
                glyph_cluster_indices.appendAssumeCapacity(if (source_cluster != cluster and glyph_cluster_indices.items.len != 0)
                    glyph_cluster_indices.items[glyph_cluster_indices.items.len - 1]
                else
                    glyph_cluster_indices.items.len);
                glyph_substituted.appendAssumeCapacity(false);
                ligature_components.infos.appendAssumeCapacity(.{});

                glyph_ids.appendAssumeCapacity(sara_aa_glyph);
                codepoints.appendAssumeCapacity(sara_aa);
                clusters.appendAssumeCapacity(cluster_base + source_cluster);
                source_ends.appendAssumeCapacity(source_end);
                glyph_source_indices.appendAssumeCapacity(glyph_source_indices.items.len);
                glyph_cluster_indices.appendAssumeCapacity(if (source_cluster != cluster and glyph_cluster_indices.items.len != 0)
                    glyph_cluster_indices.items[glyph_cluster_indices.items.len - 1]
                else
                    glyph_cluster_indices.items.len);
                glyph_substituted.appendAssumeCapacity(false);
                ligature_components.infos.appendAssumeCapacity(.{});

                var nikhahit_destination = nikhahit_index;
                while (nikhahit_destination > 0) {
                    const previous_source = glyph_source_indices.items[nikhahit_destination - 1];
                    if (previous_source >= codepoints.items.len or !isThaiLaoSaraAmAboveBaseMark(codepoints.items[previous_source])) break;
                    nikhahit_destination -= 1;
                }
                if (nikhahit_destination != nikhahit_index) {
                    shaping_metadata.move(
                        glyph_ids,
                        glyph_source_indices,
                        glyph_cluster_indices,
                        glyph_substituted,
                        ligature_components,
                        nikhahit_index,
                        nikhahit_destination,
                    );
                }
                const merge_start = nikhahit_destination;
                const merge_end = glyph_ids.items.len;
                if (merge_start < merge_end and merge_start < glyph_cluster_indices.items.len and cluster_level.isMonotone()) {
                    shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, merge_start, merge_end);
                }
                const grapheme_merge_start = if (nikhahit_destination > 0) nikhahit_destination - 1 else nikhahit_destination;
                if (grapheme_merge_start < merge_end and cluster_level.groupsGraphemes()) {
                    if (cluster_level.isMonotone()) {
                        shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, grapheme_merge_start, merge_end);
                    } else {
                        shaping_metadata.mergeClusterRange(glyph_cluster_indices.items, grapheme_merge_start, merge_end);
                    }
                }
                continue;
            }
            const composition = try arabicCompositionForFontAt(font, glyph_index_cache, codepoint, text, it.i);
            const source_end = if (composition) |value| value.byte_end else it.i;
            const normalized_codepoint = if (composition) |value| value.codepoint else codepoint;
            const glyph_id = if (composition) |value| glyph: {
                it.i = value.byte_end;
                break :glyph value.glyph_id;
            } else glyph: {
                const shaped_codepoint = try presentationCodepointForShaping(font, glyph_index_cache, codepoint, selected_lookup_options);
                break :glyph try fallbackGlyphIndexWithOptionalCache(font, glyph_index_cache, shaped_codepoint);
            };
            const explicit_cluster_level = selected_lookup_options.cluster_level;
            const inherit_grapheme_cluster = if (explicit_cluster_level) |level| level.groupsGraphemes() else true;
            const inherits_previous_cluster = inheritsLeadingDefaultIgnorableCluster(codepoints.items, clusters.items, if (default_ignorable_invisible_glyph_id) |glyph| glyph else resolve: {
                const glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
                default_ignorable_invisible_glyph_id = glyph;
                break :resolve glyph;
            }) or
                codepoint == 0x200d or
                (explicit_cluster_level != null and unicode.isUnicodeMarkCodepoint(codepoint)) or
                (selected_lookup_options.script_tag == .tibt and isTibetanClusterExtender(codepoint)) or
                (usesThaiLaoSaraAmPreprocess(selected_lookup_options.script_tag) and isThaiLaoClusterExtender(codepoint)) or
                inheritsPreviousZwnjClusterInRtlShaping(
                    selected_lookup_options.direction,
                    codepoints.items,
                    if (default_ignorable_invisible_glyph_id) |glyph| glyph else resolve: {
                        const glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
                        default_ignorable_invisible_glyph_id = glyph;
                        break :resolve glyph;
                    },
                ) or
                (selected_lookup_options.direction == .rtl and unicode.inheritsPreviousClusterInRtlShaping(codepoint));
            const source_cluster = if (inherit_grapheme_cluster and inherits_previous_cluster and
                clusters.items.len != 0)
                clusters.items[clusters.items.len - 1] - cluster_base
            else
                cluster;
            glyph_ids.appendAssumeCapacity(glyph_id);
            codepoints.appendAssumeCapacity(normalized_codepoint);
            clusters.appendAssumeCapacity(cluster_base + source_cluster);
            source_ends.appendAssumeCapacity(cluster_base + source_end);
            glyph_source_indices.appendAssumeCapacity(glyph_source_indices.items.len);
            const cluster_owner_index = if (source_cluster != cluster and glyph_cluster_indices.items.len != 0)
                glyph_cluster_indices.items[glyph_cluster_indices.items.len - 1]
            else
                glyph_cluster_indices.items.len;
            glyph_cluster_indices.appendAssumeCapacity(cluster_owner_index);
            glyph_substituted.appendAssumeCapacity(false);
            ligature_components.infos.appendAssumeCapacity(.{});
        }
    }
    if (shape_profile) |p| {
        p.cmap_ns += shapeProfileElapsed(cmap_start, profile_io);
        p.glyph_count += glyph_ids.items.len;
    }

    selected_lookup_options.run_has_decimal_number = run_has_decimal_number;
    selected_lookup_options.run_has_letter = run_has_letter;
    const lookup_options = selected_lookup_options;

    const shape_in_native_direction = shouldShapeInNativeDirection(lookup_options);
    if (shape_in_native_direction) {
        reverseScratchGlyphOrderForNativeDirection(scratch);
    }

    const gdef_start = shapeProfileNow(shape_profile, profile_io);
    var owned_gdef_metadata: ?GdefLookupMetadata = null;
    const gdef_metadata = try gdefMetadataForShaping(font, buffer.allocator, buffer.gdef_metadata_cache, &owned_gdef_metadata);
    if (shape_profile) |p| p.gdef_ns += shapeProfileElapsed(gdef_start, profile_io);
    defer if (owned_gdef_metadata) |*metadata| metadata.deinit(buffer.allocator);

    var hangul_feature_overrides_buf: [17]unicode.FeatureOverride = undefined;
    const gsub_feature_overrides = if (runIsHangul(codepoints.items))
        featureOverridesWithDefaultDisabledCalt(hangul_feature_overrides_buf[0..], lookup_options.features) orelse lookup_options.features
    else
        lookup_options.features;

    var gsub_random_state: u32 = 1;
    // Keep source metadata parallel to glyph ids through GSUB. GPOS MarkLigPos
    // needs the original component sources for a ligature glyph; otherwise a
    // mark after a ligature can only guess a component from post-substitution
    // mark order.
    var gsub_options = gsub.LookupOptions{
        .script_tag = lookup_options.script_tag,
        .language_tag = lookup_options.language_tag,
        .text_direction = if (lookup_options.direction == .rtl) .rtl else .ltr,
        .features = gsub_feature_overrides,
        .normalized_variation_coords = lookup_options.normalized_variation_coords,
        .vertical = lookup_options.writing_mode.isVertical(),
        .apply_all_if_unselected = false,
        .glyph_source_indices = glyph_source_indices,
        .glyph_cluster_indices = glyph_cluster_indices,
        .cluster_level = lookup_options.cluster_level orelse .monotone_characters,
        .glyph_substituted = glyph_substituted,
        .ligature_components = ligature_components,
        // The LTR ASCII cmap fast path proves there is no CGJ, joiner, or
        // default-ignorable scalar for contextual/ligature skipping. Omit the
        // source slice so generic Latin GSUB avoids scanning the identity
        // source map merely to re-prove those codepoint bounds.
        .source_codepoints = if (resolved_lookup_options.all_ascii and lookup_options.direction == .ltr)
            null
        else
            codepoints.items,
        .shape_profile = shape_profile,
        .profile_fast_path = buffer.profile_fast_path,
        .profile_io = profile_io,
        .visible_variation_selectors = lookup_options.not_found_variation_selector_glyph != null,
        .random_state = &gsub_random_state,
    };
    const gsub_start = shapeProfileNow(shape_profile, profile_io);
    const gsub_after_proof = if (buffer.gsub_table_proof_cache) |proof_cache| proof: {
        try proof_cache.prove(font);
        break :proof true;
    } else false;
    if (buffer.lookup_selection_cache) |selection_cache| {
        gsub_options.lookup_accelerators = try selection_cache.gsubLookupAccelerators(font);
    }
    if (lookup_options.beginning_of_text and lookup_options.context_before.len == 0 and codepoints.items.len != 0 and unicode.isUnicodeMarkCodepoint(codepoints.items[0])) {
        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try insertBeginningDottedCircle(
            buffer.allocator,
            glyph_ids,
            codepoints,
            clusters,
            source_ends,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            dotted_circle_glyph,
        );
        gsub_options.source_codepoints = codepoints.items;
    }
    const use_shape = use_shaper.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const myanmar_shape = myanmar.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const khmer_shape = khmer.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const early_zero_mark_shape = use_shape or myanmar_shape;
    if (use_shape or myanmar_shape) {
        // Cluster ownership for source text must be established before vowel
        // constraints inject synthetic U+25CC sources that do not exist in the
        // original UTF-8 byte stream.
        try use_shaper.assignGraphemeClusterOwners(
            buffer.allocator,
            text,
            cluster_base,
            clusters.items,
            codepoints.items,
            glyph_cluster_indices.items,
        );
        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        if (use_shape) {
            try use_shaper.insertVowelConstraintDottedCircles(
                buffer.allocator,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                dotted_circle_glyph,
                false,
            );
            try use_shaper.decomposeCanonicalSources(
                buffer.allocator,
                font,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
            );
        }
        gsub_options.source_codepoints = codepoints.items;
    }
    // HarfBuzz normalizes every shaping buffer before script-specific GSUB.
    // Keep immutable source codepoints in logical order, but reorder the glyph
    // stream and its parallel metadata by modified combining class. USE then
    // runs its syllable machine over this canonicalized source permutation.
    reorderMarksForShaping(
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        codepoints.items,
        lookup_options.cluster_level,
    );
    if (lookup_options.script_tag == .arab) {
        reorderArabicModifierMarksForShaping(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            codepoints.items,
        );
    }
    if (usesArabicJoiningShaper(lookup_options.script_tag) and codepoints.items.len != 0) {
        try source_features.resize(buffer.allocator, codepoints.items.len);
        if (shape_in_native_direction) {
            markArabicJoiningSourceFeatures(source_features.items, codepoints.items, glyph_source_indices.items);
        } else {
            try joining_forms.resize(buffer.allocator, codepoints.items.len);
            try resolveJoiningFormsWithItemContext(
                buffer.allocator,
                lookup_options.context_before,
                codepoints.items,
                lookup_options.context_after,
                joining_forms.items,
            );
            for (joining_forms.items, source_features.items) |form, *feature| {
                feature.* = joiningFormFeatureTag(form);
            }
        }
        if (lookup_options.script_tag == .mong) {
            inheritMongolianVariationSelectorFeatures(source_features.items, codepoints.items);
        }
        var joining_options = gsub_options;
        joining_options.source_features = source_features.items;

        if (shapingFeatureEnabled(unicode.tag("stch"), lookup_options.features, true)) {
            try applyGsubFeatureApplicationsForShaping(
                font,
                buffer,
                gsub_after_proof,
                &.{.{ .tag = unicode.tag("stch"), .auto_zwj = false }},
                glyph_ids,
                joining_options,
                gdef_metadata.*,
            );
            recordStchActions(ligature_components);
        }

        // Unicode Arabic joining forms are position-scoped and must run after
        // canonical/localized substitutions but before required ligatures.
        // Keeping the order explicit mirrors the OpenType Arabic shaping plan
        // without globally enabling mutually-exclusive form features.
        var applications_buf: [15]gsub.FeatureApplication = undefined;
        var application_count: usize = 0;
        const planned_features = [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("ccmp"), .auto_zwj = false },
            .{ .tag = unicode.tag("locl"), .auto_zwj = false },
            .{ .tag = unicode.tag("ltrm"), .auto_zwj = false },
            .{ .tag = unicode.tag("rtlm"), .auto_zwj = false },
            .{ .tag = unicode.tag("isol"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("fina"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("fin2"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("fin3"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("medi"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("med2"), .source_scoped = true, .auto_zwj = false },
            .{ .tag = unicode.tag("init"), .source_scoped = true, .auto_zwj = false },
        };
        for (planned_features) |application| {
            if (lookup_options.script_tag == .mong and (application.tag == unicode.tag("rlig") or application.tag == unicode.tag("calt"))) continue;
            if (lookup_options.script_tag != .phag and (application.tag == unicode.tag("ltrm") or application.tag == unicode.tag("rtlm"))) continue;
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
                    try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(&.{application}, glyph_ids, buffer.allocator, joining_options, gdef_metadata.*);
                } else {
                    try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(&.{application}, glyph_ids, buffer.allocator, joining_options, gdef_metadata.*);
                }
                if (stage_index < profile.arabic_stage_ns.len) {
                    profile.arabic_stage_ns[stage_index] += shapeProfileElapsed(stage_start, profile_io);
                    profile.arabic_stage_lookup_count[stage_index] += profile.gsub_lookup_count - lookup_count_before;
                    profile.arabic_stage_count = @max(profile.arabic_stage_count, stage_index + 1);
                }
            }
        } else {
            if (gsub_after_proof and buffer.lookup_selection_cache != null) {
                const plan = try buffer.lookup_selection_cache.?.gsubFeatureLookupPlan(font, applications_buf[0..application_count], joining_options, gdef_metadata.*);
                try font.applyGsubFeatureLookupPlanUsingGdefAfterProof(plan, glyph_ids, buffer.allocator, joining_options, gdef_metadata.*);
            } else if (gsub_after_proof) {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(applications_buf[0..application_count], glyph_ids, buffer.allocator, joining_options, gdef_metadata.*);
            } else {
                try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(applications_buf[0..application_count], glyph_ids, buffer.allocator, joining_options, gdef_metadata.*);
            }
        }
        if (lookup_options.script_tag == .mong) {
            var merged_features_buf: [2]gsub.FeatureApplication = undefined;
            var merged_feature_count: usize = 0;
            const mongolian_merged_features = [_]gsub.FeatureApplication{
                .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
                .{ .tag = unicode.tag("calt"), .auto_zwj = false },
            };
            for (mongolian_merged_features) |application| {
                if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
                merged_features_buf[merged_feature_count] = application;
                merged_feature_count += 1;
            }
            try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, merged_features_buf[0..merged_feature_count], glyph_ids, joining_options, gdef_metadata.*);
        }
        var final_features_buf: [24]gsub.FeatureApplication = undefined;
        var final_feature_count: usize = 0;
        if (lookup_options.script_tag == .arab and shapingFeatureEnabled(unicode.tag("rlig"), lookup_options.features, true)) {
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, &.{.{ .tag = unicode.tag("rlig"), .auto_zwj = false }}, glyph_ids, joining_options, gdef_metadata.*);
        }
        if (lookup_options.script_tag == .arab) {
            var arabic_calt_features_buf: [2]gsub.FeatureApplication = undefined;
            var arabic_calt_feature_count: usize = 0;
            const arabic_calt_features = [_]gsub.FeatureApplication{
                .{ .tag = unicode.tag("calt"), .auto_zwj = false },
                .{ .tag = unicode.tag("rclt"), .auto_zwj = false },
            };
            for (arabic_calt_features) |application| {
                if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
                arabic_calt_features_buf[arabic_calt_feature_count] = application;
                arabic_calt_feature_count += 1;
            }
            try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, arabic_calt_features_buf[0..arabic_calt_feature_count], glyph_ids, joining_options, gdef_metadata.*);
        }
        const final_features = [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
            .{ .tag = unicode.tag("calt"), .auto_zwj = false },
            .{ .tag = unicode.tag("rclt"), .auto_zwj = false },
            .{ .tag = unicode.tag("liga"), .auto_zwj = false },
            .{ .tag = unicode.tag("clig"), .auto_zwj = false },
        };
        for (final_features) |application| {
            if (lookup_options.script_tag == .arab and application.tag == unicode.tag("rlig")) continue;
            if (lookup_options.script_tag == .arab and (application.tag == unicode.tag("calt") or application.tag == unicode.tag("rclt"))) continue;
            if (lookup_options.script_tag == .mong and (application.tag == unicode.tag("rlig") or application.tag == unicode.tag("calt"))) continue;
            if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
            final_features_buf[final_feature_count] = application;
            final_feature_count += 1;
        }
        final_feature_count += explicitOptionalFeatureApplications(
            final_features_buf[final_feature_count..],
            lookup_options.features,
        );
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, final_features_buf[0..final_feature_count], glyph_ids, gsub_options, gdef_metadata.*);
    } else if (myanmar_shape) {
        try source_syllables.resize(buffer.allocator, codepoints.items.len);
        myanmar.markSourceSyllables(source_syllables.items, codepoints.items);
        var myanmar_options = gsub_options;
        myanmar_options.source_syllables = source_syllables.items;

        try applyGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, myanmar.featureApplications(.preprocessing), glyph_ids, myanmar_options, gdef_metadata.*);
        myanmar.reorder(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_syllables.items,
            codepoints.items,
        );
        try gsub.validateScriptShaperRunMetadata(myanmar_options, glyph_ids.items.len);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.rphf), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.pref), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.blwf), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.pstf), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.final), glyph_ids, myanmar_options, gdef_metadata.*);
    } else if (khmer_shape) {
        try khmer.decomposeSplitMatraSources(
            buffer.allocator,
            font,
            glyph_ids,
            codepoints,
            clusters,
            source_ends,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
        );
        try source_features.resize(buffer.allocator, codepoints.items.len);
        try source_syllables.resize(buffer.allocator, codepoints.items.len);
        khmer.markSourceFeatures(source_features.items, source_syllables.items, codepoints.items);
        var khmer_options = gsub_options;
        khmer_options.source_codepoints = codepoints.items;
        khmer_options.source_features = source_features.items;
        khmer_options.source_syllables = source_syllables.items;

        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try khmer.insertDottedCirclesForBrokenMarks(
            buffer.allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_syllables.items,
            codepoints.items,
            dotted_circle_glyph,
        );
        khmer.reorder(
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_syllables.items,
            codepoints.items,
        );
        khmer.assignJoinerClusterOwners(glyph_cluster_indices, glyph_source_indices, codepoints.items);
        try gsub.validateScriptShaperRunMetadata(khmer_options, glyph_ids.items.len);
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, khmer.featureApplications(.basic), glyph_ids, khmer_options, gdef_metadata.*);
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, khmer.featureApplications(.final), glyph_ids, khmer_options, gdef_metadata.*);
    } else if (use_shape) {
        try source_features.resize(buffer.allocator, codepoints.items.len);
        try source_syllables.resize(buffer.allocator, codepoints.items.len);
        try source_rphf_substituted.resize(buffer.allocator, codepoints.items.len);
        try source_pref_substituted.resize(buffer.allocator, codepoints.items.len);
        @memset(source_rphf_substituted.items, false);
        @memset(source_pref_substituted.items, false);
        try use_shaper.markSourceFeatures(
            buffer.allocator,
            source_features.items,
            source_syllables.items,
            codepoints.items,
            glyph_source_indices.items,
        );
        if (useShapeUsesArabicJoiningMasks(lookup_options.script_tag)) {
            overlayArabicJoiningSourceFeatures(source_features.items, codepoints.items, glyph_source_indices.items);
        }
        var use_options = gsub_options;
        use_options.source_features = source_features.items;
        use_options.source_syllables = source_syllables.items;

        if (useShapeUsesDirectionFeatures(lookup_options.script_tag)) {
            var direction_features_buf: [2]gsub.FeatureApplication = undefined;
            var direction_feature_count: usize = 0;
            const direction_features = if (lookup_options.direction == .rtl)
                [_]gsub.FeatureApplication{
                    .{ .tag = unicode.tag("rtla") },
                    .{ .tag = unicode.tag("rtlm") },
                }
            else
                [_]gsub.FeatureApplication{
                    .{ .tag = unicode.tag("ltra") },
                    .{ .tag = unicode.tag("ltrm") },
                };
            for (direction_features) |application| {
                if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
                direction_features_buf[direction_feature_count] = application;
                direction_feature_count += 1;
            }
            try applyMergedGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, direction_features_buf[0..direction_feature_count], glyph_ids, use_options, gdef_metadata.*);
        }
        try applyGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, use_shaper.defaultPreprocessingFeatureApplications(), glyph_ids, use_options, gdef_metadata.*);
        try glyph_stage_substituted.resize(buffer.allocator, glyph_ids.items.len);
        @memset(glyph_stage_substituted.items, false);
        var rphf_options = use_options;
        rphf_options.glyph_stage_substituted = glyph_stage_substituted;
        try applyGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, use_shaper.rphfFeatureApplications(), glyph_ids, rphf_options, gdef_metadata.*);
        use_shaper.recordRphfSubstitutions(
            glyph_source_indices.items,
            glyph_stage_substituted.items,
            source_features.items,
            source_syllables.items,
            source_rphf_substituted.items,
        );
        glyph_stage_substituted.clearRetainingCapacity();
        try glyph_stage_substituted.resize(buffer.allocator, glyph_ids.items.len);
        @memset(glyph_stage_substituted.items, false);
        var pref_options = use_options;
        pref_options.glyph_stage_substituted = glyph_stage_substituted;
        try applyGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, use_shaper.prefFeatureApplications(), glyph_ids, pref_options, gdef_metadata.*);
        use_shaper.recordPrefSubstitutions(
            glyph_source_indices.items,
            glyph_stage_substituted.items,
            source_pref_substituted.items,
        );
        glyph_stage_substituted.clearRetainingCapacity();
        // Every earlier public stage has validated the run it received, and
        // GSUB mutation helpers preserve glyph bounds plus source-parallel
        // cardinalities. Prove the current maximal USE metadata contract once
        // after stage-only scratch is detached, then reuse it through all
        // remaining explicit stages.
        try gsub.validateScriptShaperRunMetadata(use_options, glyph_ids.items.len);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, use_shaper.basicFeatureApplications(), glyph_ids, use_options, gdef_metadata.*);
        if (use_shaper.hasBrokenSyllable(source_syllables.items)) {
            const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
            try use_shaper.insertDottedCirclesForBrokenSyllables(
                buffer.allocator,
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                source_syllables.items,
                source_rphf_substituted.items,
                source_pref_substituted.items,
                codepoints.items,
                dotted_circle_glyph,
            );
        }
        use_shaper.reorderGlyphs(
            glyph_ids.items,
            glyph_source_indices.items,
            glyph_cluster_indices.items,
            glyph_substituted.items,
            ligature_components.infos.items,
            source_syllables.items,
            source_rphf_substituted.items,
            source_pref_substituted.items,
            codepoints.items,
        );
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, use_shaper.topographicalFeatureApplications(), glyph_ids, use_options, gdef_metadata.*);
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, use_shaper.finalFeatureApplications(), glyph_ids, use_options, gdef_metadata.*);
        try applyMergedGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, use_shaper.typographicFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
    } else {
        const indic_shape = indic.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
        if (indic_shape) {
            const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
            try use_shaper.insertVowelConstraintDottedCircles(
                buffer.allocator,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                dotted_circle_glyph,
                true,
            );
            try use_shaper.decomposeCanonicalSources(
                buffer.allocator,
                font,
                glyph_ids,
                codepoints,
                clusters,
                source_ends,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
            );
            gsub_options.source_codepoints = codepoints.items;
        }
        const apply_morx = font.hasMorxTableForShaping() and
            (!lookup_options.writing_mode.isVertical() or !font.hasGsubTableForShaping());
        if (apply_morx) {
            try font.applyMorxForShaping(glyph_ids, buffer.allocator, gsub_options);
        } else {
            const gsub_needs_value_selection = needsValueAwareGsubSelection(font, gsub_options.features);
            if (lookup_options.normalized_variation_coords.len == 0 and !gsub_needs_value_selection) if (buffer.lookup_selection_cache) |selection_cache| {
                gsub_options.selected_lookups = try selection_cache.gsubLookups(font, gsub_options, gdef_metadata.*);
            };
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
        if (indic_shape) {
            const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
            try indic.insertDottedCirclesForBrokenClusters(
                buffer.allocator,
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                codepoints.items,
                dotted_circle_glyph,
                lookup_options.script_tag,
            );
            indic.mergePlaceholderDependentMarks(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.mergeTrailingDependentMarks(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.mergeKannadaOldSpecTrailingBlwf(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.normalizeOldSpecDevanagariHalantOrder(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                codepoints.items,
                lookup_options.script_tag,
            );
            indic.normalizeInitialConsonantSyllableOrder(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                codepoints.items,
                lookup_options.script_tag,
            );
            indic.normalizeOldSpecBengaliRaViramaOrder(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                codepoints.items,
                lookup_options.script_tag,
            );

            try source_features.resize(buffer.allocator, codepoints.items.len);
            try source_syllables.resize(buffer.allocator, codepoints.items.len);
            indic.markSourceSyllables(source_syllables.items, codepoints.items, lookup_options.script_tag);
            try source_pref_substituted.resize(buffer.allocator, codepoints.items.len);
            @memset(source_pref_substituted.items, false);
            const has_basic_source_features = indic.markBasicSourceFeatures(source_features.items, codepoints.items, lookup_options.script_tag);
            gsub_options.source_features = source_features.items;
            gsub_options.source_syllables = source_syllables.items;

            try applyGsubFeatureApplicationsForShaping(font, buffer, gsub_after_proof, indic.preReorderFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
            try gsub.validateScriptShaperRunMetadata(gsub_options, glyph_ids.items.len);
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.basicFeatureApplications(has_basic_source_features), glyph_ids, gsub_options, gdef_metadata.*);
            try glyph_stage_substituted.resize(buffer.allocator, glyph_ids.items.len);
            @memset(glyph_stage_substituted.items, false);
            var pref_options = gsub_options;
            pref_options.glyph_stage_substituted = glyph_stage_substituted;
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.prefFeatureApplications(), glyph_ids, pref_options, gdef_metadata.*);
            indic.recordPrefSubstitutions(
                glyph_source_indices.items,
                glyph_stage_substituted.items,
                source_pref_substituted.items,
            );
            glyph_stage_substituted.clearRetainingCapacity();
            indic.reorderPreBaseMatras(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
            indic.reorderPrefGlyphs(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, source_pref_substituted.items, codepoints.items, lookup_options.script_tag);
            _ = indic.markInitialMatraGlyphSources(source_features.items, glyph_source_indices.items, codepoints.items, lookup_options.script_tag);
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.preRephFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
            indic.reorderRephs(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
            indic.reorderLogicalRepha(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
            indic.reorderBeforeSubscriptVowels(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.finalFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
            indic.reorderGujaratiSplitMatraComponents(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
        }
    }
    if (hasRunnableFraction(codepoints.items)) {
        try source_features.resize(buffer.allocator, codepoints.items.len);
        var fraction_options = gsub_options;
        fraction_options.source_features = source_features.items;
        if (markFractionSourceFeatures(source_features.items, codepoints.items, .numerator)) {
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, &.{.{ .tag = unicode.tag("numr"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
        if (markFractionSourceFeatures(source_features.items, codepoints.items, .fraction)) {
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, &.{.{ .tag = unicode.tag("frac"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
        if (markFractionSourceFeatures(source_features.items, codepoints.items, .denominator)) {
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, &.{.{ .tag = unicode.tag("dnom"), .source_scoped = true }}, glyph_ids, fraction_options, gdef_metadata.*);
        }
    }

    if (shape_profile) |p| p.gsub_ns += shapeProfileElapsed(gsub_start, profile_io);

    const gpos_adjustments = &scratch.gpos_adjustments;
    const gpos_start = shapeProfileNow(shape_profile, profile_io);
    var gpos_options = gpos.LookupOptions{
        .script_tag = gpos_script_tag,
        .language_tag = lookup_options.language_tag,
        .direction = if (shapingDirectionForGpos(lookup_options) == .rtl) .rtl else .ltr,
        .features = lookup_options.features,
        .apply_all_if_unselected = false,
        .run_may_have_mark_attachments = runMayHaveMarkAttachments(glyph_ids.items, codepoints.items, glyph_source_indices.items, gdef_metadata.*),
        .run_has_default_ignorables = has_default_ignorable,
        .glyph_source_indices = glyph_source_indices.items,
        .source_codepoints = codepoints.items,
        .glyph_substituted = glyph_substituted.items,
        .ligature_components = ligature_components,
        .shape_profile = shape_profile,
        .profile_io = profile_io,
        .visible_variation_selectors = lookup_options.not_found_variation_selector_glyph != null,
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
    const has_gpos_attachments = adjustmentsHaveAttachments(gpos_adjustments.items);
    // GPOS adjustments and legacy kern are accumulated in font units, then
    // scaled into user-space coordinates for the final GlyphPosition stream.
    const has_gdef_glyph_classes = gdef_metadata.glyph_classes != null;
    const has_gpos_positioning = font.hasGposTableForShaping();
    var previous_glyph: ?GlyphId = null;
    var fallback_mark_base: ?fallback_mark.Base = null;
    var adjustment_cursor: usize = 0;
    const kern_lookup = if (!lookup_options.writing_mode.isVertical() and
        shouldApplyLegacyKernFallback(lookup_options.script_tag) and
        shapingFeatureEnabled(unicode.tag("kern"), lookup_options.features, true))
        try font.kernLookupForShaping()
    else
        null;
    const invisible_glyph_id = if (has_default_ignorable)
        if (default_ignorable_invisible_glyph_id) |glyph| glyph else resolve: {
            const glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
            default_ignorable_invisible_glyph_id = glyph;
            break :resolve glyph;
        }
    else
        0;
    const segment_glyph_start = buffer.glyphs.items.len;
    // Positioning can suppress untouched default-ignorables but never emits
    // more final glyphs than the post-GSUB stream. Reserve the segment once so
    // the output loop does not repeat a large GlyphPosition capacity check.
    try buffer.glyphs.ensureUnusedCapacity(buffer.allocator, glyph_ids.items.len);
    const attachment_links = &scratch.attachment_links;
    if (has_gpos_attachments) {
        // Parent indexes refer to the post-GSUB input stream. Allocate the
        // remapping arrays only when GPOS actually emitted a mark/cursive
        // attachment; ordinary PairPos-only Latin runs need neither array.
        try attachment_links.resize(buffer.allocator, glyph_ids.items.len);
        @memset(attachment_links.items, .{});
        try glyph_output_indices.resize(buffer.allocator, glyph_ids.items.len);
        @memset(glyph_output_indices.items, std.math.maxInt(usize));
    }
    for (glyph_ids.items, 0..) |glyph_id, index| {
        const source_index = if (index < glyph_source_indices.items.len)
            @min(glyph_source_indices.items[index], codepoints.items.len -| 1)
        else
            @min(index, codepoints.items.len -| 1);
        const cluster_index = if (index < glyph_cluster_indices.items.len)
            @min(glyph_cluster_indices.items[index], clusters.items.len -| 1)
        else
            source_index;
        const source_span = sourceSpanForGlyph(index, source_index, cluster_index, clusters.items, source_ends.items, ligature_components) orelse
            SourceSpan{ .start = cluster_base, .end = cluster_base };
        const metrics = try horizontalMetricsWithOptionalCache(font, metrics_cache, glyph_id, lookup_options.normalized_variation_coords);
        const glyph_class = gdef_metadata.glyphClass(glyph_id);
        var kern_x_advance: f32 = 0;
        var kern_x_offset: f32 = 0;
        if (kern_lookup) |lookup| {
            if (previous_glyph) |previous| {
                const previous_adjustment = findAdjustmentSorted(gpos_adjustments.items, index - 1, &adjustment_cursor);
                if (!previous_adjustment.pair_positioned) {
                    const kern = try lookup.kerning(previous, glyph_id);
                    if (kern != 0 and buffer.glyphs.items.len > 0) {
                        const kern_1 = kern >> 1;
                        const kern_2 = kern - kern_1;
                        buffer.glyphs.items[buffer.glyphs.items.len - 1].x_advance += @as(f32, @floatFromInt(kern_1)) * scale;
                        kern_x_advance = @as(f32, @floatFromInt(kern_2)) * scale;
                        kern_x_offset = kern_x_advance;
                    }
                }
            }
        }
        const adjustment = findAdjustmentSorted(gpos_adjustments.items, index, &adjustment_cursor);
        const stch_action: ligature_provenance.StchAction = if (index < ligature_components.infos.items.len)
            ligature_components.infos.items[index].flags.stch_action
        else
            .none;
        const adjustment_x_advance = if (adjustment.x_advance_absolute)
            @as(f32, @floatFromInt(adjustment.x_advance)) - @as(f32, @floatFromInt(metrics.advance_width))
        else
            @as(f32, @floatFromInt(adjustment.x_advance));
        const source_codepoint = if (codepoints.items.len == 0) 0 else codepoints.items[source_index];
        const was_substituted = index < glyph_substituted.items.len and glyph_substituted.items[index];
        const gpos_x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) * scale;
        const mark_attachment = adjustment.attachment_type == .mark;
        const visible_not_found_variation_selector = lookup_options.not_found_variation_selector_glyph != null and
            isVariationSelector(source_codepoint) and
            !was_substituted;
        const hide_default_ignorable = isDefaultIgnorableForShaping(source_codepoint) and
            !was_substituted and
            !visible_not_found_variation_selector;
        const skip_default_ignorable = hide_default_ignorable and
            (invisible_glyph_id == 0 or
                (glyph_id == 0 and isVariationSelector(source_codepoint) and
                    !variationSelectorFallbackShouldRender(index, source_index, ligature_components)));
        // HarfBuzz removes an untouched default-ignorable when the font has no
        // usable invisible/space glyph. Do this after GPOS so the character was
        // still available to every contextual lookup, then remap attachment
        // links below for the compacted output stream.
        if (skip_default_ignorable) {
            previous_glyph = glyph_id;
            continue;
        }
        const output_glyph_id = if (hide_default_ignorable and invisible_glyph_id != 0) invisible_glyph_id else glyph_id;
        const synthetic_glyph_id = if (visible_not_found_variation_selector)
            lookup_options.not_found_variation_selector_glyph
        else
            null;
        const mark_zeroing = markAdvanceZeroingPolicy(
            early_zero_mark_shape,
            glyph_class,
            has_gdef_glyph_classes,
            source_codepoint,
            index < ligature_components.infos.items.len and ligature_components.infos.items[index].flags.synthetic_base,
            mark_attachment,
            has_gpos_positioning,
            lookup_options,
        );
        const fallback_space_advance = if (!lookup_options.writing_mode.isVertical())
            try space_fallback.advanceWidth(font, source_codepoint, glyph_id, metrics.advance_width)
        else
            null;
        const default_vertical_advance_units: i32 = @as(i32, font.ascender) - @as(i32, font.descender);
        const fallback_space_vertical_advance = if (lookup_options.writing_mode.isVertical())
            try space_fallback.advanceHeight(font, source_codepoint, glyph_id, default_vertical_advance_units)
        else
            null;
        const base_advance = if (hide_default_ignorable or mark_zeroing.zero_advance)
            0
        else if (fallback_space_advance) |value|
            value
        else
            metrics.advance_width;
        const horizontal_advance = if (hide_default_ignorable)
            0
        else
            (@as(f32, @floatFromInt(base_advance)) + adjustment_x_advance) * scale + kern_x_advance;
        const use_sideways_vertical_advance = lookup_options.writing_mode.isVertical() and
            glyphUsesSidewaysAdvance(source_codepoint, lookup_options.text_orientation);
        const vertical_metrics = if (lookup_options.writing_mode.isVertical())
            try verticalMetricsWithOptionalCache(font, metrics_cache, glyph_id, lookup_options.normalized_variation_coords)
        else
            null;
        const unzeroed_vertical_advance = if (use_sideways_vertical_advance)
            (@as(f32, @floatFromInt(metrics.advance_width)) + adjustment_x_advance) * scale
        else if (vertical_metrics) |value|
            @as(f32, @floatFromInt(value.advance_height)) * scale
        else
            font_size;
        const vertical_advance = if (mark_zeroing.zero_advance)
            0
        else if (fallback_space_vertical_advance) |value|
            @as(f32, @floatFromInt(value)) * scale
        else if (use_sideways_vertical_advance)
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
        // USE zeroes marks before GPOS. Without a positioning table, HarfBuzz
        // preserves the visual origin of a forward-direction mark by moving it
        // back by its original advance before clearing that advance.
        const zeroed_mark_x_offset = if (mark_zeroing.adjust_offsets and !lookup_options.writing_mode.isVertical())
            -@as(f32, @floatFromInt(metrics.advance_width)) * scale
        else
            0.0;
        const zeroed_mark_y_offset = if (mark_zeroing.adjust_offsets and lookup_options.writing_mode.isVertical())
            -unzeroed_vertical_advance
        else
            0.0;
        var fallback_mark_offset = fallback_mark.Offset{};
        if (fallback_mark.enabled(early_zero_mark_shape, has_gpos_positioning, has_gpos_attachments, mark_attachment, lookup_options.writing_mode.isVertical()) and
            unicode.isNonspacingMarkCodepoint(source_codepoint))
        {
            if (fallback_mark_base) |*base| {
                fallback_mark_offset = fallback_mark.offset(
                    font,
                    glyph_id,
                    source_codepoint,
                    base,
                    scale,
                ) catch .{};
            }
        }
        if (has_gpos_attachments) {
            glyph_output_indices.items[index] = buffer.glyphs.items.len - segment_glyph_start;
        }
        const output_x_offset = if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (lookup_options.writing_mode.isVertical())
            vertical_x_offset + gpos_x_offset + zeroed_mark_x_offset + fallback_mark_offset.x
        else
            gpos_x_offset + kern_x_offset + zeroed_mark_x_offset + fallback_mark_offset.x;
        const output_y_offset = if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (lookup_options.writing_mode.isVertical())
            vertical_y_offset + @as(f32, @floatFromInt(adjustment.y_placement)) * scale + zeroed_mark_y_offset + fallback_mark_offset.y
        else
            @as(f32, @floatFromInt(adjustment.y_placement)) * scale + zeroed_mark_y_offset + fallback_mark_offset.y;
        buffer.glyphs.appendAssumeCapacity(.{
            .glyph_id = output_glyph_id,
            .synthetic_glyph_id = synthetic_glyph_id,
            .codepoint = source_codepoint,
            .cluster = source_span.start,
            .source_byte_len = source_span.end - source_span.start,
            .x_advance = if (visible_not_found_variation_selector) 0 else if (lookup_options.writing_mode.isVertical()) 0.0 else horizontal_advance,
            .y_advance = if (hide_default_ignorable or visible_not_found_variation_selector) 0 else if (lookup_options.writing_mode.isVertical()) vertical_advance else @as(f32, @floatFromInt(adjustment.y_advance)) * scale,
            .x_offset = output_x_offset,
            .y_offset = output_y_offset,
            .vertical = lookup_options.writing_mode.isVertical(),
        });
        const stch_context_flag: u8 = if (stchContextCodepoint(source_codepoint)) 0x80 else 0;
        try stch_actions.append(buffer.allocator, @intFromEnum(stch_action) | stch_context_flag);
        if (has_gpos_attachments and !hide_default_ignorable) {
            attachment_links.items[index] = attachmentLinkForAdjustment(adjustment);
        }
        if (!hide_default_ignorable and !visible_not_found_variation_selector and !unicode.isNonspacingMarkCodepoint(source_codepoint)) {
            fallback_mark_base = fallback_mark.baseForGlyph(font, glyph_id, source_span.start, output_y_offset, horizontal_advance, scale, shapingDirectionForGpos(lookup_options) == .ltr) catch null;
        }
        previous_glyph = glyph_id;
    }
    if (has_gpos_attachments) {
        compactAttachmentLinks(
            attachment_links.items,
            glyph_output_indices.items,
            buffer.glyphs.items.len - segment_glyph_start,
        );
        propagateGlyphAttachmentOffsets(
            buffer.glyphs.items[segment_glyph_start..],
            attachment_links.items[0 .. buffer.glyphs.items.len - segment_glyph_start],
            lookup_options,
        );
    }
    try applyStchToSegment(
        buffer.allocator,
        &buffer.glyphs,
        stch_actions.items,
        segment_glyph_start,
        lookup_options.direction == .rtl,
        scale,
        font,
        metrics_cache,
        lookup_options.normalized_variation_coords,
    );
    if (!lookup_options.writing_mode.isVertical()) {
        if (try font.horizontalTrackingForShaping(buffer.allocator, font_size)) |tracking| {
            if (tracking != 0) {
                const tracking_advance = tracking * scale;
                for (buffer.glyphs.items[segment_glyph_start..]) |*glyph| {
                    glyph.x_advance += tracking_advance;
                }
            }
        }
    }
    if (shape_in_native_direction and shapingDirectionForGpos(lookup_options) == .rtl) {
        std.mem.reverse(GlyphPosition, buffer.glyphs.items[segment_glyph_start..]);
    }
    if (shape_profile) |p| p.position_ns += shapeProfileElapsed(position_start, profile_io);
}

fn applyGsubFeatureApplicationsForShaping(
    font: *const Font,
    buffer: *LayoutBuffer,
    gsub_after_proof: bool,
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (applications.len == 0) return;
    if (gsub_after_proof and buffer.lookup_selection_cache != null) {
        // Explicit script shapers apply several ordered feature stages to each
        // word. Cache the immutable Script/LangSys/FeatureList resolution just
        // as the Arabic path already does; the plan preserves stage order and
        // per-application source/joiner/syllable flags while avoiding repeated
        // table walks on every stage of every word.
        const plan = try buffer.lookup_selection_cache.?.gsubFeatureLookupPlan(
            font,
            applications,
            options,
            gdef_metadata,
        );
        try font.applyGsubFeatureLookupPlanUsingGdefAfterProof(
            plan,
            glyph_ids,
            buffer.allocator,
            options,
            gdef_metadata,
        );
    } else if (gsub_after_proof) {
        try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(applications, glyph_ids, buffer.allocator, options, gdef_metadata);
    } else {
        try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(applications, glyph_ids, buffer.allocator, options, gdef_metadata);
    }
}

fn applyGsubFeatureApplicationsAfterRunProof(
    font: *const Font,
    buffer: *LayoutBuffer,
    gsub_after_proof: bool,
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (!gsub_after_proof or buffer.lookup_selection_cache == null) {
        return try applyGsubFeatureApplicationsForShaping(
            font,
            buffer,
            gsub_after_proof,
            applications,
            glyph_ids,
            options,
            gdef_metadata,
        );
    }
    if (applications.len == 0) return;
    const plan = try buffer.lookup_selection_cache.?.gsubFeatureLookupPlan(
        font,
        applications,
        options,
        gdef_metadata,
    );
    try font.applyGsubFeatureLookupPlanUsingGdefAfterRunProof(
        plan,
        glyph_ids,
        buffer.allocator,
        options,
        gdef_metadata,
    );
}

fn applyMergedGsubFeatureApplicationsForShaping(
    font: *const Font,
    buffer: *LayoutBuffer,
    gsub_after_proof: bool,
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (applications.len == 0) return;
    _ = gsub_after_proof;
    const plan = try font.gsubMergedFeatureLookupPlanForShaping(buffer.allocator, applications, options, gdef_metadata);
    defer {
        var mutable_plan = plan;
        mutable_plan.deinit(buffer.allocator);
    }
    try font.applyGsubMergedFeatureLookupPlanUsingGdefAfterProof(plan, glyph_ids, buffer.allocator, options, gdef_metadata);
}

fn applyMergedGsubFeatureApplicationsAfterRunProof(
    font: *const Font,
    buffer: *LayoutBuffer,
    gsub_after_proof: bool,
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (!gsub_after_proof) {
        return try applyMergedGsubFeatureApplicationsForShaping(
            font,
            buffer,
            gsub_after_proof,
            applications,
            glyph_ids,
            options,
            gdef_metadata,
        );
    }
    if (applications.len == 0) return;
    const plan = if (buffer.lookup_selection_cache) |selection_cache|
        try selection_cache.gsubMergedFeatureLookupPlan(font, applications, options, gdef_metadata)
    else
        try font.gsubMergedFeatureLookupPlanForShaping(
            buffer.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (buffer.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(buffer.allocator);
    };
    try font.applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof(
        plan,
        glyph_ids,
        buffer.allocator,
        options,
        gdef_metadata,
    );
}

fn shapeProfileNow(profile: ?*ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null) std.Io.Clock.now(.awake, io.?).nanoseconds else 0;
}

fn shapeProfileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

fn markArabicJoiningSourceFeatures(source_features: []u32, codepoints: []const u21, glyph_source_indices: []const usize) void {
    @memset(source_features, 0);
    overlayArabicJoiningSourceFeatures(source_features, codepoints, glyph_source_indices);
}

fn overlayArabicJoiningSourceFeatures(source_features: []u32, codepoints: []const u21, glyph_source_indices: []const usize) void {
    if (codepoints.len == 0 or glyph_source_indices.len == 0) return;

    var ordered_codepoints: [128]u21 = undefined;
    var ordered_sources: [128]usize = undefined;
    if (glyph_source_indices.len > ordered_codepoints.len) {
        markArabicJoiningSourceFeaturesFallback(source_features, codepoints, glyph_source_indices);
        return;
    }

    var ordered_len: usize = 0;
    for (glyph_source_indices) |source| {
        if (source >= codepoints.len) continue;
        ordered_sources[ordered_len] = source;
        ordered_codepoints[ordered_len] = codepoints[source];
        ordered_len += 1;
    }
    if (ordered_len == 0) return;

    var forms: [128]unicode.JoiningForm = undefined;
    unicode.resolveJoiningForms(ordered_codepoints[0..ordered_len], forms[0..ordered_len]) catch return;
    for (forms[0..ordered_len], ordered_sources[0..ordered_len]) |form, source| {
        setArabicJoiningSourceFeature(source_features, source, form);
    }
}

fn markArabicJoiningSourceFeaturesFallback(source_features: []u32, codepoints: []const u21, glyph_source_indices: []const usize) void {
    var previous_source: ?usize = null;
    var previous_form: unicode.JoiningForm = .none;
    for (glyph_source_indices) |source| {
        if (source >= codepoints.len) continue;
        var pair = [_]u21{ codepoints[source], 0 };
        if (previous_source) |prev| {
            pair[0] = codepoints[prev];
            pair[1] = codepoints[source];
            var forms: [2]unicode.JoiningForm = undefined;
            unicode.resolveJoiningForms(&pair, &forms) catch {
                previous_source = source;
                previous_form = .none;
                continue;
            };
            if (previous_form == .none) setArabicJoiningSourceFeature(source_features, prev, forms[0]);
            previous_form = forms[1];
            setArabicJoiningSourceFeature(source_features, source, forms[1]);
        } else {
            previous_form = .none;
        }
        previous_source = source;
    }
}

fn setArabicJoiningSourceFeature(source_features: []u32, source: usize, form: unicode.JoiningForm) void {
    if (source >= source_features.len) return;
    const joining_mask =
        (gsub.sourceFeatureMaskForTag(unicode.tag("isol")).? |
            gsub.sourceFeatureMaskForTag(unicode.tag("init")).? |
            gsub.sourceFeatureMaskForTag(unicode.tag("medi")).? |
            gsub.sourceFeatureMaskForTag(unicode.tag("fina")).?) & ~gsub.source_feature_mask_marker;
    const form_mask = switch (form) {
        .isolated => gsub.sourceFeatureMaskForTag(unicode.tag("isol")).?,
        .initial => gsub.sourceFeatureMaskForTag(unicode.tag("init")).?,
        .medial => gsub.sourceFeatureMaskForTag(unicode.tag("medi")).?,
        .final => gsub.sourceFeatureMaskForTag(unicode.tag("fina")).?,
        .none => 0,
    };
    const existing = source_features[source];
    source_features[source] = (existing & ~joining_mask) | form_mask;
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

fn resolveJoiningFormsWithItemContext(
    allocator: std.mem.Allocator,
    before: []const u8,
    item_codepoints: []const u21,
    after: []const u8,
    item_forms: []unicode.JoiningForm,
) !void {
    if (before.len == 0 and after.len == 0) {
        return try unicode.resolveJoiningForms(item_codepoints, item_forms);
    }

    var context_codepoints = std.ArrayList(u21).empty;
    defer context_codepoints.deinit(allocator);
    try appendUtf8Codepoints(allocator, &context_codepoints, before);
    const item_start = context_codepoints.items.len;
    try context_codepoints.appendSlice(allocator, item_codepoints);
    try appendUtf8Codepoints(allocator, &context_codepoints, after);

    const context_forms = try allocator.alloc(unicode.JoiningForm, context_codepoints.items.len);
    defer allocator.free(context_forms);
    try unicode.resolveJoiningForms(context_codepoints.items, context_forms);
    @memcpy(item_forms, context_forms[item_start..][0..item_codepoints.len]);
}

fn appendUtf8Codepoints(allocator: std.mem.Allocator, out: *std.ArrayList(u21), text: []const u8) !void {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        try out.append(allocator, codepoint);
    }
}

fn insertBeginningDottedCircle(
    allocator: std.mem.Allocator,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: *std.ArrayList(u21),
    clusters: *std.ArrayList(usize),
    source_ends: *std.ArrayList(usize),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    dotted_circle_glyph: GlyphId,
) !void {
    if (dotted_circle_glyph == 0 or codepoints.items.len == 0 or glyph_ids.items.len == 0) return;
    const source_start = clusters.items[0];
    const source_end = source_ends.items[0];

    try codepoints.replaceRange(allocator, 0, 0, &.{0x25cc});
    errdefer _ = codepoints.orderedRemove(0);
    try clusters.replaceRange(allocator, 0, 0, &.{source_start});
    errdefer _ = clusters.orderedRemove(0);
    try source_ends.replaceRange(allocator, 0, 0, &.{source_end});
    errdefer _ = source_ends.orderedRemove(0);

    for (glyph_source_indices.items) |*source| source.* += 1;
    for (glyph_cluster_indices.items) |*owner| owner.* += 1;
    ligature_components.shiftSourceIndices(0, 1);

    try shaping_metadata.insert(
        allocator,
        glyph_ids,
        glyph_source_indices,
        glyph_cluster_indices,
        glyph_substituted,
        ligature_components,
        0,
        dotted_circle_glyph,
        0,
        0,
    );
}

test "beginning item dotted circle creates a synthetic base source" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 3);
    var codepoints = std.ArrayList(u21).empty;
    defer codepoints.deinit(allocator);
    try codepoints.append(allocator, 0x064e);
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.append(allocator, 0);
    var source_ends = std.ArrayList(usize).empty;
    defer source_ends.deinit(allocator);
    try source_ends.append(allocator, 2);
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 0);
    var cluster_owners = std.ArrayList(usize).empty;
    defer cluster_owners.deinit(allocator);
    try cluster_owners.append(allocator, 0);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.append(allocator, false);
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.append(allocator, .{});

    try insertBeginningDottedCircle(allocator, &glyphs, &codepoints, &clusters, &source_ends, &sources, &cluster_owners, &substituted, &ligatures, 4);

    try std.testing.expectEqualSlices(GlyphId, &.{ 4, 3 }, glyphs.items);
    try std.testing.expectEqualSlices(u21, &.{ 0x25cc, 0x064e }, codepoints.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, cluster_owners.items);
}

test "Arabic item context influences only joining forms" {
    const allocator = std.testing.allocator;
    const item = [_]u21{0x0628};
    var forms: [1]unicode.JoiningForm = undefined;

    try resolveJoiningFormsWithItemContext(allocator, "", &item, "", &forms);
    try std.testing.expectEqual(unicode.JoiningForm.isolated, forms[0]);

    try resolveJoiningFormsWithItemContext(allocator, "ب", &item, "ب", &forms);
    try std.testing.expectEqual(unicode.JoiningForm.medial, forms[0]);
}

fn usesArabicJoiningShaper(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .arab or script_tag == .syrc or script_tag == .adlm or script_tag == .mong;
}

fn inheritsPreviousZwnjClusterInRtlShaping(direction: TextDirection, prior_codepoints: []const u21, invisible_glyph_id: GlyphId) bool {
    return direction == .rtl and invisible_glyph_id == 0 and prior_codepoints.len != 0 and prior_codepoints[prior_codepoints.len - 1] == 0x200c;
}

test "RTL shaping makes glyph after ZWNJ inherit join-control cluster" {
    try std.testing.expect(inheritsPreviousZwnjClusterInRtlShaping(.rtl, &.{ 0x0628, 0x200c }, 0));
    try std.testing.expect(!inheritsPreviousZwnjClusterInRtlShaping(.rtl, &.{ 0x0628, 0x200c }, 3));
    try std.testing.expect(!inheritsPreviousZwnjClusterInRtlShaping(.ltr, &.{ 0x0628, 0x200c }, 0));
    try std.testing.expect(!inheritsPreviousZwnjClusterInRtlShaping(.rtl, &.{0x0628}, 0));
}

fn useShapeUsesArabicJoiningMasks(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .phag;
}

fn useShapeUsesDirectionFeatures(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .phag;
}

fn shouldApplyLegacyKernFallback(script_tag: unicode.OpenTypeScriptTag) bool {
    if (indic.shouldShape(script_tag) or use_shaper.shouldShape(script_tag) or myanmar.shouldShape(script_tag)) return false;
    return switch (script_tag) {
        .deva, .dev2, .dev3, .hang, .khmr => false,
        else => true,
    };
}

fn runIsHangul(codepoints: []const u21) bool {
    var has_hangul = false;
    for (codepoints) |codepoint| {
        if (isHangulCodepoint(codepoint)) {
            has_hangul = true;
            continue;
        }
        const script = unicode.scriptForCodepoint(codepoint);
        if (script != .common and script != .inherited and script != .unknown) return false;
    }
    return has_hangul;
}

fn isHangulCodepoint(codepoint: u21) bool {
    return isHangulJamoCodepoint(codepoint) or
        (codepoint >= 0xac00 and codepoint <= 0xd7af);
}

fn isHangulJamoCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0x3130 and codepoint <= 0x318f) or
        (codepoint >= 0xa960 and codepoint <= 0xa97f) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7ff);
}

fn usesLateGdefMarkZeroing(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .arab, .hebr, .thai, .lao, .dflt => true,
        else => false,
    };
}

fn usesThaiLaoSaraAmPreprocess(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .thai or script_tag == .lao;
}

fn isTibetanClusterExtender(codepoint: u21) bool {
    return codepoint == 0x0f35 or
        codepoint == 0x0f37 or
        codepoint == 0x0f39 or
        (codepoint >= 0x0f71 and codepoint <= 0x0f84) or
        (codepoint >= 0x0f86 and codepoint <= 0x0f87) or
        (codepoint >= 0x0f8d and codepoint <= 0x0f97) or
        (codepoint >= 0x0f99 and codepoint <= 0x0fbc) or
        codepoint == 0x0fc6;
}

fn isThaiLaoSaraAm(codepoint: u21) bool {
    return (codepoint & ~@as(u21, 0x80)) == 0x0e33;
}

fn nikhahitFromSaraAm(codepoint: u21) u21 {
    return codepoint - 0x0e33 + 0x0e4d;
}

fn saraAaFromSaraAm(codepoint: u21) u21 {
    return codepoint - 1;
}

fn isThaiLaoSaraAmAboveBaseMark(codepoint: u21) bool {
    const normalized = codepoint & ~@as(u21, 0x80);
    return (normalized >= 0x0e34 and normalized <= 0x0e37) or
        (normalized >= 0x0e47 and normalized <= 0x0e4e) or
        normalized == 0x0e31 or
        normalized == 0x0e3b;
}

fn isThaiLaoClusterExtender(codepoint: u21) bool {
    const normalized = codepoint & ~@as(u21, 0x80);
    return normalized == 0x0e31 or
        (normalized >= 0x0e34 and normalized <= 0x0e3a) or
        (normalized >= 0x0e47 and normalized <= 0x0e4e);
}

fn inheritMongolianVariationSelectorFeatures(source_features: []u32, codepoints: []const u21) void {
    for (codepoints, 0..) |codepoint, index| {
        if (!isMongolianFreeVariationSelector(codepoint) or index == 0) continue;
        source_features[index] = source_features[index - 1];
    }
}

fn isMongolianFreeVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0x180b and codepoint <= 0x180d) or codepoint == 0x180f;
}

fn shapingFeatureEnabled(feature: u32, overrides: []const unicode.FeatureOverride, default_enabled: bool) bool {
    for (overrides) |override| {
        if (override.tag == feature) return override.enabled;
    }
    return default_enabled;
}

fn featureOverridesWithDefaultDisabledCalt(out: []unicode.FeatureOverride, overrides: []const unicode.FeatureOverride) ?[]const unicode.FeatureOverride {
    if (out.len < overrides.len + 1) return null;
    var count: usize = 0;
    for (overrides) |override| {
        if (override.tag == unicode.tag("calt")) return overrides;
        out[count] = override;
        count += 1;
    }
    out[count] = .{ .tag = unicode.tag("calt"), .enabled = false };
    return out[0 .. count + 1];
}

fn explicitOptionalFeatureApplications(out: []gsub.FeatureApplication, overrides: []const unicode.FeatureOverride) usize {
    var count: usize = 0;
    for (overrides) |override| {
        if (!override.enabled or !explicitOptionalFeatureShouldRun(override.tag)) continue;
        if (count >= out.len) break;
        out[count] = .{ .tag = override.tag, .auto_zwj = false, .value = override.value };
        count += 1;
    }
    return count;
}

fn explicitOptionalFeatureShouldRun(feature: u32) bool {
    return feature != unicode.tag("stch") and
        feature != unicode.tag("ccmp") and
        feature != unicode.tag("locl") and
        feature != unicode.tag("isol") and
        feature != unicode.tag("fina") and
        feature != unicode.tag("fin2") and
        feature != unicode.tag("fin3") and
        feature != unicode.tag("medi") and
        feature != unicode.tag("med2") and
        feature != unicode.tag("init") and
        feature != unicode.tag("rlig") and
        feature != unicode.tag("calt") and
        feature != unicode.tag("rclt") and
        feature != unicode.tag("liga") and
        feature != unicode.tag("clig") and
        feature != unicode.tag("sups") and
        feature != unicode.tag("subs");
}

fn needsValueAwareGsubSelection(font: *const Font, features: []const unicode.FeatureOverride) bool {
    var rand_disabled = false;
    for (features) |feature| {
        if (feature.effectiveValue() > 1) return true;
        if (feature.tag == unicode.tag("rand") and !feature.enabled) rand_disabled = true;
    }
    return !rand_disabled and (font.hasGsubFeatureForShaping(unicode.tag("rand")) catch false);
}

fn scriptPositionFeatureApplication(position: ScriptPosition) ?gsub.FeatureApplication {
    return switch (position) {
        .normal => null,
        .superscript => .{ .tag = unicode.tag("sups") },
        .subscript => .{ .tag = unicode.tag("subs") },
    };
}

const FractionStage = enum {
    numerator,
    fraction,
    denominator,
};

const FractionRun = struct {
    start: usize,
    slash: usize,
    end: usize,
};

fn hasRunnableFraction(codepoints: []const u21) bool {
    return firstFractionRunFrom(codepoints, 0) != null;
}

fn markFractionSourceFeatures(source_features: []u32, codepoints: []const u21, stage: FractionStage) bool {
    @memset(source_features, 0);
    var any = false;
    var search_start: usize = 0;
    const Range = struct {
        start: usize,
        end: usize,
        tag: u32,
    };
    while (firstFractionRunFrom(codepoints, search_start)) |run| {
        const range: Range = switch (stage) {
            .numerator => .{ .start = run.start, .end = run.slash, .tag = unicode.tag("numr") },
            .fraction => .{ .start = run.start, .end = run.end, .tag = unicode.tag("frac") },
            .denominator => .{ .start = run.slash + 1, .end = run.end, .tag = unicode.tag("dnom") },
        };
        for (range.start..range.end) |index| source_features[index] = range.tag;
        any = true;
        search_start = run.end;
    }
    return any;
}

fn firstFractionRunFrom(codepoints: []const u21, start_index: usize) ?FractionRun {
    var index = start_index;
    while (index < codepoints.len) : (index += 1) {
        if (codepoints[index] != 0x2044) continue;
        var start = index;
        while (start > 0 and isFractionDecimalNumber(codepoints[start - 1])) start -= 1;
        var end = index + 1;
        while (end < codepoints.len and isFractionDecimalNumber(codepoints[end])) end += 1;
        if (start == index or end == index + 1) continue;
        return .{ .start = start, .slash = index, .end = end };
    }
    return null;
}

fn isFractionDecimalNumber(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669);
}

fn isShapeNativeDirectionDecimalNumber(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

fn isShapeNativeDirectionLetter(codepoint: u21) bool {
    if (isShapeNativeDirectionDecimalNumber(codepoint) or
        unicode.isUnicodeMarkCodepoint(codepoint) or
        unicode.isDefaultIgnorableForShaping(codepoint) or
        isShapeNativeDirectionFormatControl(codepoint))
    {
        return false;
    }
    return switch (unicode.bidiClassForCodepoint(codepoint)) {
        .ltr, .rtl => true,
        else => false,
    };
}

fn isShapeNativeDirectionFormatControl(codepoint: u21) bool {
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or
        codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2 or
        codepoint == 0x0d4e or
        codepoint == 0x110bd or
        codepoint == 0x110cd;
}

fn shouldShapeInNativeDirection(options: LookupOptions) bool {
    if (!options.reorder_bidi and !options.native_direction_shaping) return false;
    if (options.writing_mode.isVertical()) return false;
    const native_direction = textDirectionFromBidiClass(nativeHorizontalDirection(options) orelse return false);
    if (options.direction == .ltr and native_direction == .rtl and options.run_has_decimal_number and !options.run_has_letter) return false;
    return options.direction != native_direction;
}

fn nativeHorizontalDirection(options: LookupOptions) ?unicode.BidiClass {
    // ScriptList negotiation may select DFLT/latn or a generation-specific
    // OpenType tag. Text direction remains a Unicode-script property, not a
    // property of whichever font table entry happened to provide lookups.
    // An explicit caller override is authoritative, however.
    const direction_tag = if (options.script_tag_explicit)
        options.script_tag
    else if (options.script != .common and options.script != .inherited and options.script != .unknown)
        unicode.openTypeScriptTag(options.script)
    else
        options.script_tag;
    return unicode.openTypeScriptHorizontalDirection(direction_tag);
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
        if (index < len and scratchGlyphContinuesNativeGrapheme(scratch, index)) continue;
        reverseScratchGlyphRange(scratch, group_start, index);
        group_start = index;
    }
    reverseScratchGlyphRange(scratch, 0, len);
}

fn scratchGlyphContinuesNativeGrapheme(scratch: *const layout_scratch.ShapeScratch, glyph_index: usize) bool {
    const source_index = if (glyph_index < scratch.glyph_source_indices.items.len)
        scratch.glyph_source_indices.items[glyph_index]
    else
        glyph_index;
    if (source_index < scratch.codepoints.items.len and unicode.isUnicodeMarkCodepoint(scratch.codepoints.items[source_index])) return true;
    return scratchGlyphCluster(scratch, glyph_index) == scratchGlyphCluster(scratch, glyph_index - 1);
}

fn scratchGlyphCluster(scratch: *const layout_scratch.ShapeScratch, glyph_index: usize) usize {
    if (glyph_index >= scratch.glyph_cluster_indices.items.len) return glyph_index;
    const source_index = scratch.glyph_cluster_indices.items[glyph_index];
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
    std.mem.swap(usize, &scratch.glyph_cluster_indices.items[a], &scratch.glyph_cluster_indices.items[b]);
    std.mem.swap(bool, &scratch.glyph_substituted.items[a], &scratch.glyph_substituted.items[b]);
    std.mem.swap(ligature_provenance.Info, &scratch.ligature_components.infos.items[a], &scratch.ligature_components.infos.items[b]);
}

const SourceSpan = struct {
    start: usize,
    end: usize,
};

fn sourceSpanForGlyph(glyph_index: usize, fallback_source_index: usize, fallback_cluster_index: usize, starts: []const usize, ends: []const usize, ligature_components: *const ligature_provenance.Store) ?SourceSpan {
    const cluster = sourceSpanForIndex(fallback_cluster_index, starts, ends);
    if (glyph_index < ligature_components.infos.items.len and ligature_components.infos.items[glyph_index].component_count > 1) {
        const info = ligature_components.infos.items[glyph_index];
        var span: ?SourceSpan = null;
        const component_sources = ligature_components.componentSources(info) orelse return cluster;
        for (component_sources) |component_source| {
            const component_span = sourceSpanForIndex(component_source, starts, ends) orelse continue;
            if (span) |*accumulated| {
                accumulated.start = @min(accumulated.start, component_span.start);
                accumulated.end = @max(accumulated.end, component_span.end);
            } else {
                span = component_span;
            }
        }
        if (span) |value| {
            // Ligature components determine the source extent, but GSUB's
            // cluster-owner metadata determines the public cluster start.
            // Reordering or a later ligature can merge that owner farther left
            // than the ligature's own first logical component.
            return .{ .start = if (cluster) |owner| owner.start else value.start, .end = value.end };
        }
    }
    const span = sourceSpanForIndex(fallback_source_index, starts, ends) orelse return cluster;
    const owner = cluster orelse return span;
    return .{ .start = owner.start, .end = span.end };
}

fn sourceSpanForIndex(source_index: usize, starts: []const usize, ends: []const usize) ?SourceSpan {
    if (starts.len == 0) return null;
    const index = @min(source_index, starts.len - 1);
    const start = starts[index];
    const end = if (index < ends.len) @max(ends[index], start) else start;
    return .{ .start = start, .end = end };
}

test "ligature source spans honor a merged cluster owner" {
    const starts = [_]usize{ 0, 3, 6, 9 };
    const ends = [_]usize{ 3, 6, 9, 12 };
    var provenance = ligature_provenance.Store{};
    defer provenance.deinit(std.testing.allocator);
    const info = try provenance.addLigature(std.testing.allocator, &.{ 2, 3 });
    try provenance.infos.append(std.testing.allocator, info);

    const span = sourceSpanForGlyph(0, 2, 1, &starts, &ends, &provenance).?;

    try std.testing.expectEqual(SourceSpan{ .start = 3, .end = 12 }, span);
}

fn attachmentLinkForAdjustment(adjustment: gpos.Adjustment) attachment.Link {
    return switch (adjustment.attachment_type) {
        .none => .{},
        .mark => .{ .kind = .mark, .parent_index = adjustment.attachment_parent_index },
        .cursive => .{ .kind = .cursive, .parent_index = adjustment.attachment_parent_index },
    };
}

fn adjustmentsHaveAttachments(adjustments: []const gpos.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none) return true;
    }
    return false;
}

test "attachment scratch is needed only for emitted attachment adjustments" {
    try std.testing.expect(!adjustmentsHaveAttachments(&.{
        .{ .index = 0, .x_advance = -20, .pair_positioned = true },
    }));
    try std.testing.expect(adjustmentsHaveAttachments(&.{
        .{ .index = 0, .attachment_type = .mark, .attachment_parent_index = 1 },
    }));
    try std.testing.expect(adjustmentsHaveAttachments(&.{
        .{ .index = 0, .attachment_type = .cursive, .attachment_parent_index = 1 },
    }));
}

test "attachment remapping scratch follows emitted adjustment type across runs" {
    const test_font = @import("test_font.zig");
    const mark_bytes = try test_font.buildMinimalGposMarkTtf(std.testing.allocator);
    defer std.testing.allocator.free(mark_bytes);
    var mark_font = try Font.parse(std.testing.allocator, mark_bytes);
    defer mark_font.deinit();
    const pair_bytes = try test_font.buildMinimalGposTtf(std.testing.allocator);
    defer std.testing.allocator.free(pair_bytes);
    var pair_font = try Font.parse(std.testing.allocator, pair_bytes);
    defer pair_font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const mark_run = try TextShaper.shapeUtf8(&mark_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), mark_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.glyph_output_indices.items.len);

    // Shape into the same reusable buffer. Its clear step drops the old lengths,
    // and PairPos does not regrow arrays that it cannot consume.
    const pair_run = try TextShaper.shapeUtf8(&pair_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), pair_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.glyph_output_indices.items.len);
}

fn remapAttachmentLinkForOutput(link: attachment.Link, output_indices: []const usize) attachment.Link {
    const parent = link.parent_index orelse return link;
    if (parent >= output_indices.len) return .{};
    const output_parent = output_indices[parent];
    if (output_parent == std.math.maxInt(usize)) return .{};
    return .{ .kind = link.kind, .parent_index = output_parent };
}

fn compactAttachmentLinks(links: []attachment.Link, output_indices: []const usize, output_len: usize) void {
    for (output_indices, 0..) |output_index, input_index| {
        if (output_index == std.math.maxInt(usize) or output_index >= output_len) continue;
        links[output_index] = remapAttachmentLinkForOutput(links[input_index], output_indices);
    }
}

test "attachment links remap after hidden glyph removal" {
    const removed = std.math.maxInt(usize);
    const output_indices = [_]usize{ 0, removed, 1 };
    var links = [_]attachment.Link{
        .{},
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    compactAttachmentLinks(&links, &output_indices, 2);

    try std.testing.expectEqual(attachment.Link{}, links[0]);
    try std.testing.expectEqual(attachment.Link{ .kind = .mark, .parent_index = 0 }, links[1]);
}

fn propagateGlyphAttachmentOffsets(glyphs: []GlyphPosition, links: []attachment.Link, options: LookupOptions) void {
    const direction: attachment.Direction = switch (shapingDirectionForGpos(options)) {
        .ltr => .forward,
        .rtl => .backward,
    };
    const axis: attachment.Axis = if (options.writing_mode.isVertical()) .vertical else .horizontal;
    attachment.propagateOffsets(GlyphPosition, glyphs, links, direction, axis);
}

fn recordStchActions(ligature_components: *ligature_provenance.Store) void {
    for (ligature_components.infos.items) |*info| {
        if (!info.flags.multiplied) continue;
        info.flags.stch_action = if (info.flags.multiple_component % 2 == 0)
            .fixed
        else
            .repeating;
    }
}

fn applyStchToSegment(
    allocator: std.mem.Allocator,
    glyphs: *std.ArrayList(GlyphPosition),
    stch_actions: []const u8,
    segment_start: usize,
    rtl: bool,
    scale: f32,
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
) !void {
    const segment_len = glyphs.items.len - segment_start;
    if (segment_len == 0 or stch_actions.len != segment_len) return;

    var has_stch = false;
    for (stch_actions) |raw_action| {
        if (stchActionFromInt(raw_action) != .none) {
            has_stch = true;
            break;
        }
    }
    if (!has_stch) return;

    var extra_glyphs_needed: usize = 0;
    var i = segment_len;
    while (i > 0) {
        if (stchActionFromInt(stch_actions[i - 1]) == .none) {
            i -= 1;
            continue;
        }
        const metrics = try measureStchRun(font, metrics_cache, normalized_variation_coords, glyphs.items[segment_start..], stch_actions, i, rtl, scale);
        extra_glyphs_needed += metrics.n_copies * metrics.n_repeating;
        i = metrics.start;
    }

    const old_len = glyphs.items.len;
    const new_len = old_len + extra_glyphs_needed;
    try glyphs.ensureUnusedCapacity(allocator, extra_glyphs_needed);
    const source = glyphs.items[segment_start..old_len];
    var output = std.ArrayList(GlyphPosition).empty;
    defer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, segment_len + extra_glyphs_needed);

    i = 0;
    while (i < segment_len) {
        if (stchActionFromInt(stch_actions[i]) == .none) {
            output.appendAssumeCapacity(source[i]);
            i += 1;
            continue;
        }
        const metrics = try measureStchRun(font, metrics_cache, normalized_variation_coords, source, stch_actions, stchRunEnd(stch_actions, i), rtl, scale);
        try appendStchRun(font, metrics_cache, normalized_variation_coords, source[metrics.start..metrics.end], stch_actions[metrics.start..metrics.end], metrics, rtl, scale, &output);
        i = metrics.end;
    }

    glyphs.items.len = new_len;
    @memcpy(glyphs.items[segment_start .. segment_start + output.items.len], output.items);
}

const StchRunMetrics = struct {
    start: usize,
    end: usize,
    w_remaining_units: i32,
    extra_repeat_overlap_units: i32,
    n_repeating: usize,
    n_copies: usize,
};

fn measureStchRun(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    segment: []const GlyphPosition,
    stch_actions: []const u8,
    end: usize,
    rtl: bool,
    scale: f32,
) !StchRunMetrics {
    var i = end;
    var w_total: i32 = 0;
    var w_fixed: i32 = 0;
    var w_repeating: i32 = 0;
    var n_fixed: usize = 0;
    var n_repeating: usize = 0;

    while (i > 0 and stchActionFromInt(stch_actions[i - 1]) != .none) {
        i -= 1;
        const width = try stchGlyphAdvanceUnits(font, metrics_cache, normalized_variation_coords, segment[i].glyph_id);
        switch (stchActionFromInt(stch_actions[i])) {
            .fixed => {
                w_fixed += width;
                n_fixed += 1;
            },
            .repeating => {
                w_repeating += width;
                n_repeating += 1;
            },
            .none => {},
        }
    }
    const start = i;
    if (rtl) {
        var context = end;
        while (context < segment.len and stchActionFromInt(stch_actions[context]) == .none and stchContextFromInt(stch_actions[context])) : (context += 1) {
            w_total += floatToFontUnits(segment[context].x_advance, scale);
        }
    } else {
        var context = i;
        while (context > 0 and stchActionFromInt(stch_actions[context - 1]) == .none and stchContextFromInt(stch_actions[context - 1])) {
            context -= 1;
            w_total += floatToFontUnits(segment[context].x_advance, scale);
        }
    }

    var w_remaining = w_total - w_fixed;
    var n_copies: usize = 0;
    if (w_remaining > w_repeating and w_repeating > 0) {
        n_copies = @intCast(@divTrunc(w_remaining, w_repeating) - 1);
    }

    var extra_repeat_overlap: i32 = 0;
    const shortfall = w_remaining - w_repeating * @as(i32, @intCast(n_copies + 1));
    if (shortfall > 0 and n_repeating > 0) {
        n_copies += 1;
        const excess = @as(i32, @intCast(n_copies + 1)) * w_repeating - w_remaining;
        if (excess > 0) {
            extra_repeat_overlap = @divTrunc(excess, @as(i32, @intCast(n_copies * n_repeating)));
            w_remaining = 0;
        }
    }

    const stch_max_glyphs = 256;
    var max_copies: usize = 0;
    if (n_repeating > 0) {
        const base_glyphs = n_fixed + n_repeating;
        if (base_glyphs < stch_max_glyphs) max_copies = (stch_max_glyphs - base_glyphs) / n_repeating;
    }
    n_copies = @min(n_copies, max_copies);

    return .{
        .start = start,
        .end = end,
        .w_remaining_units = w_remaining,
        .extra_repeat_overlap_units = extra_repeat_overlap,
        .n_repeating = n_repeating,
        .n_copies = n_copies,
    };
}

fn stchRunEnd(stch_actions: []const u8, start: usize) usize {
    var end = start;
    while (end < stch_actions.len and stchActionFromInt(stch_actions[end]) != .none) : (end += 1) {}
    return end;
}

fn appendStchRun(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    run: []const GlyphPosition,
    actions: []const u8,
    metrics: StchRunMetrics,
    rtl: bool,
    scale: f32,
    output: *std.ArrayList(GlyphPosition),
) !void {
    var x_offset_units: i32 = @divTrunc(metrics.w_remaining_units, 2);
    if (!rtl and x_offset_units > 0) x_offset_units = 0;
    const overlap_units = metrics.extra_repeat_overlap_units;
    if (rtl) {
        var k = run.len;
        while (k > 0) {
            k -= 1;
            try appendStchGlyphCopies(font, metrics_cache, normalized_variation_coords, run[k], stchActionFromInt(actions[k]), metrics.n_copies, rtl, &x_offset_units, overlap_units, scale, output);
        }
        std.mem.reverse(GlyphPosition, output.items[output.items.len - (run.len + metrics.n_copies * metrics.n_repeating) ..]);
    } else {
        for (run, actions) |glyph, raw_action| {
            try appendStchGlyphCopies(font, metrics_cache, normalized_variation_coords, glyph, stchActionFromInt(raw_action), metrics.n_copies, rtl, &x_offset_units, overlap_units, scale, output);
        }
    }
}

fn appendStchGlyphCopies(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    glyph: GlyphPosition,
    action: ligature_provenance.StchAction,
    n_copies: usize,
    rtl: bool,
    x_offset_units: *i32,
    overlap_units: i32,
    scale: f32,
    output: *std.ArrayList(GlyphPosition),
) !void {
    const repeat = if (action == .repeating) 1 + n_copies else 1;
    const width_units = try stchGlyphAdvanceUnits(font, metrics_cache, normalized_variation_coords, glyph.glyph_id);
    var copy_index: usize = 0;
    while (copy_index < repeat) : (copy_index += 1) {
        var item = glyph;
        item.x_advance = 0;
        if (rtl) {
            x_offset_units.* -= width_units;
            if (copy_index > 0) x_offset_units.* += overlap_units;
        }
        item.x_offset = @as(f32, @floatFromInt(x_offset_units.*)) * scale;
        output.appendAssumeCapacity(item);
        if (!rtl) {
            x_offset_units.* += width_units;
            if (copy_index > 0) x_offset_units.* -= overlap_units;
        }
    }
}

fn stchGlyphAdvanceUnits(font: *const Font, metrics_cache: ?*GlyphMetricsCache, normalized_variation_coords: []const f32, glyph_id: GlyphId) !i32 {
    const metrics = try horizontalMetricsWithOptionalCache(font, metrics_cache, glyph_id, normalized_variation_coords);
    return metrics.advance_width;
}

fn floatToFontUnits(value: f32, scale: f32) i32 {
    if (scale == 0) return 0;
    return @intFromFloat(@round(value / scale));
}

fn stchActionFromInt(value: u8) ligature_provenance.StchAction {
    return switch (value & 0x03) {
        @intFromEnum(ligature_provenance.StchAction.fixed) => .fixed,
        @intFromEnum(ligature_provenance.StchAction.repeating) => .repeating,
        else => .none,
    };
}

fn stchContextFromInt(value: u8) bool {
    return (value & 0x80) != 0;
}

fn stchContextCodepoint(codepoint: u21) bool {
    return codepoint == 0x070f or
        unicode.isDefaultIgnorableForShaping(codepoint) or
        arabicStchWordCodepoint(codepoint);
}

fn arabicStchWordCodepoint(codepoint: u21) bool {
    if (unicode.isUnicodeMarkCodepoint(codepoint) or unicode.isSpacingMarkCodepoint(codepoint)) return true;
    if (isShapeNativeDirectionDecimalNumber(codepoint)) return true;
    return switch (unicode.joiningTypeForCodepoint(codepoint)) {
        .non_joining => false,
        .transparent => false,
        else => true,
    };
}

fn shapingDirectionForGpos(options: LookupOptions) TextDirection {
    if (shouldShapeInNativeDirection(options)) {
        const native = nativeHorizontalDirection(options) orelse return options.direction;
        return textDirectionFromBidiClass(native);
    }
    return options.direction;
}

const MarkAdvanceZeroing = struct {
    zero_advance: bool = false,
    adjust_offsets: bool = false,
};

fn markAdvanceZeroingPolicy(
    use_shape: bool,
    glyph_class: GlyphClass,
    has_gdef_glyph_classes: bool,
    source_codepoint: u21,
    synthetic_base: bool,
    mark_attachment: bool,
    has_gpos_positioning: bool,
    options: LookupOptions,
) MarkAdvanceZeroing {
    if (synthetic_base) return .{};

    const gdef_mark = glyph_class == .mark and
        (!unicode.isSpacingMarkCodepoint(source_codepoint) or use_shape) and
        !indic.shouldShape(options.script_tag);
    // HarfBuzz only synthesizes classes when the face has no GlyphClassDef at
    // all. An unclassified glyph in a present ClassDef remains unclassified;
    // falling back per glyph would override an explicit font-author decision.
    const synthesized_mark = !has_gdef_glyph_classes and
        unicode.isNonspacingMarkCodepoint(source_codepoint) and
        !unicode.isDefaultIgnorableForShaping(source_codepoint) and
        (use_shape or usesLateGdefMarkZeroing(options.script_tag));
    const attachment_mark_without_gdef = mark_attachment and !has_gdef_glyph_classes;
    const zero_advance = gdef_mark or synthesized_mark or attachment_mark_without_gdef;
    if (!zero_advance) return .{};

    const forward_direction = options.writing_mode.isVertical() or
        shapingDirectionForGpos(options) == .ltr;
    return .{
        .zero_advance = true,
        // USE's early-zero mode shifts marks only when later GPOS cannot
        // replace the provisional placement. Other shapers retain the previous
        // Cangjie policy until their early/late/fallback plans are represented.
        .adjust_offsets = use_shape and !has_gpos_positioning and forward_direction,
    };
}

test "USE mark zeroing synthesizes only nonspacing marks without GDEF classes" {
    const options = LookupOptions{ .script_tag = .brah };

    const nonspacing = markAdvanceZeroingPolicy(true, .unclassified, false, 0x11038, false, false, false, options);
    try std.testing.expect(nonspacing.zero_advance);
    try std.testing.expect(nonspacing.adjust_offsets);

    const spacing = markAdvanceZeroingPolicy(true, .unclassified, false, 0x11000, false, false, false, options);
    try std.testing.expectEqual(MarkAdvanceZeroing{}, spacing);

    const explicit_unclassified = markAdvanceZeroingPolicy(true, .unclassified, true, 0x11038, false, false, false, options);
    try std.testing.expectEqual(MarkAdvanceZeroing{}, explicit_unclassified);

    const dotted_circle = markAdvanceZeroingPolicy(true, .unclassified, false, 0x11038, true, false, false, options);
    try std.testing.expectEqual(MarkAdvanceZeroing{}, dotted_circle);
}

test "Indic shaper preserves GDEF mark advances" {
    const malayalam = markAdvanceZeroingPolicy(false, .mark, true, 0x0d41, false, false, false, .{ .script_tag = .mlm2 });
    try std.testing.expectEqual(MarkAdvanceZeroing{}, malayalam);
}

test "USE mark zeroing honors explicit GDEF spacing marks" {
    const tai_tham = markAdvanceZeroingPolicy(true, .mark, true, 0x1a6e, false, false, false, .{ .script_tag = .lana });
    try std.testing.expect(tai_tham.zero_advance);
    try std.testing.expect(tai_tham.adjust_offsets);
}

test "USE mark zeroing leaves offset adjustment to GPOS and honors native direction" {
    const with_gpos = markAdvanceZeroingPolicy(
        true,
        .unclassified,
        false,
        0x11038,
        false,
        false,
        true,
        .{ .script_tag = .brah },
    );
    try std.testing.expect(with_gpos.zero_advance);
    try std.testing.expect(!with_gpos.adjust_offsets);

    // A forced RTL request is normalized to Brahmi's native LTR shaping
    // direction before positioning, so it remains a forward buffer.
    const native_ltr = markAdvanceZeroingPolicy(
        true,
        .unclassified,
        false,
        0x11038,
        false,
        false,
        false,
        .{
            .script_tag = .brah,
            .direction = .rtl,
            .native_direction_shaping = true,
        },
    );
    try std.testing.expect(native_ltr.adjust_offsets);
}

test "USE shaping zeroes synthesized nonspacing marks without a GDEF table" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const features = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "𑀓𑀸", // BRAHMI LETTER KA + Mn VOWEL SIGN AA.
        1000,
        .{ .script_tag = .brah, .features = &features },
    );

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -800), run.glyphs[1].x_offset, 0.001);
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

fn variationSelectorFallbackShouldRender(glyph_index: usize, source_index: usize, ligature_components: *const ligature_provenance.Store) bool {
    if (glyph_index == 0 or glyph_index - 1 >= ligature_components.infos.items.len) return false;
    const sources = ligature_components.componentSources(ligature_components.infos.items[glyph_index - 1]) orelse return false;
    if (sources.len <= 1) return false;
    return source_index > sources[0] and source_index < sources[sources.len - 1];
}

fn presentationCodepointForShaping(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, codepoint: u21, lookup_options: LookupOptions) !u21 {
    if (lookup_options.writing_mode.isVertical()) {
        const vertical_source = if (lookup_options.writing_mode == .vertical_lr)
            unicode.mirroredCodepoint(codepoint)
        else
            codepoint;
        if (unicode.verticalPresentationCodepoint(vertical_source)) |vertical| {
            if (try glyphIndexWithOptionalCache(font, glyph_index_cache, vertical) != 0) return vertical;
        }
        return codepoint;
    }
    if (lookup_options.direction != .rtl) return codepoint;
    const mirrored = unicode.mirroredCodepoint(codepoint);
    if (mirrored == codepoint) return codepoint;
    return if (try glyphIndexWithOptionalCache(font, glyph_index_cache, mirrored) != 0) mirrored else codepoint;
}

fn reorderMarksForShaping(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), glyph_cluster_indices: *std.ArrayList(usize), glyph_substituted: *std.ArrayList(bool), ligature_components: *ligature_provenance.Store, codepoints: []const u21, cluster_level: ?ClusterLevel) void {
    var run_start: ?usize = null;
    for (glyph_source_indices.items, 0..) |source_index, glyph_index| {
        const modified_class = markSortClass(source_index, codepoints);
        if (modified_class == 0) {
            if (run_start) |start| reorderMarkRun(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, glyph_index, cluster_level);
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = glyph_index;
    }
    if (run_start) |start| reorderMarkRun(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, glyph_source_indices.items.len, cluster_level);
}

fn reorderMarkRun(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), glyph_cluster_indices: *std.ArrayList(usize), glyph_substituted: *std.ArrayList(bool), ligature_components: *ligature_provenance.Store, codepoints: []const u21, start: usize, end: usize, cluster_level: ?ClusterLevel) void {
    var i = start + 1;
    while (i < end) : (i += 1) {
        var j = i;
        const current_class = markSortClass(glyph_source_indices.items[i], codepoints);
        while (j > start and markSortClass(glyph_source_indices.items[j - 1], codepoints) > current_class) : (j -= 1) {}
        if (j == i) continue;
        if (cluster_level) |level| {
            if (level.isMonotone()) shaping_metadata.mergeMonotoneClusters(glyph_cluster_indices.items, j, i + 1);
        }
        var move_index = i;
        while (move_index > j) {
            std.mem.swap(GlyphId, &glyph_ids.items[move_index - 1], &glyph_ids.items[move_index]);
            std.mem.swap(usize, &glyph_source_indices.items[move_index - 1], &glyph_source_indices.items[move_index]);
            std.mem.swap(usize, &glyph_cluster_indices.items[move_index - 1], &glyph_cluster_indices.items[move_index]);
            std.mem.swap(bool, &glyph_substituted.items[move_index - 1], &glyph_substituted.items[move_index]);
            std.mem.swap(ligature_provenance.Info, &ligature_components.infos.items[move_index - 1], &ligature_components.infos.items[move_index]);
            move_index -= 1;
        }
    }
}

test "mark reorder merges clusters for explicit monotone cluster levels" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(std.testing.allocator, &.{ .{}, .{} });
    const codepoints = [_]u21{ 0x05bc, 0x05c1 };

    reorderMarkRun(&glyphs, &sources, &clusters, &substituted, &ligatures, &codepoints, 0, 2, .monotone_characters);

    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 0 }, clusters.items);
}

fn reorderArabicModifierMarksForShaping(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), glyph_cluster_indices: *std.ArrayList(usize), glyph_substituted: *std.ArrayList(bool), ligature_components: *ligature_provenance.Store, codepoints: []const u21) void {
    var run_start: ?usize = null;
    for (glyph_source_indices.items, 0..) |source_index, glyph_index| {
        const modified_class = markSortClass(source_index, codepoints);
        if (modified_class == 0) {
            if (run_start) |start| reorderArabicModifierMarkRun(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, glyph_index);
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = glyph_index;
    }
    if (run_start) |start| reorderArabicModifierMarkRun(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints, start, glyph_source_indices.items.len);
}

fn reorderArabicModifierMarkRun(glyph_ids: *std.ArrayList(GlyphId), glyph_source_indices: *std.ArrayList(usize), glyph_cluster_indices: *std.ArrayList(usize), glyph_substituted: *std.ArrayList(bool), ligature_components: *ligature_provenance.Store, codepoints: []const u21, start: usize, end: usize) void {
    var group_start = start;
    for ([_]u8{ 220, 230 }) |target_class| {
        var index = group_start;
        while (index < end and markSortClass(glyph_source_indices.items[index], codepoints) < target_class) : (index += 1) {}
        if (index == end) break;
        if (markSortClass(glyph_source_indices.items[index], codepoints) > target_class) continue;

        var group_end = index;
        while (group_end < end and
            markSortClass(glyph_source_indices.items[group_end], codepoints) == target_class and
            glyph_source_indices.items[group_end] < codepoints.len and
            isArabicModifierCombiningMark(codepoints[glyph_source_indices.items[group_end]])) : (group_end += 1)
        {}

        if (group_end == index) continue;
        var move_index = index;
        while (move_index < group_end) : (move_index += 1) {
            shaping_metadata.move(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                move_index,
                group_start,
            );
            group_start += 1;
        }
    }
}

fn isArabicModifierCombiningMark(codepoint: u21) bool {
    return switch (codepoint) {
        0x0654, 0x0655, 0x0658, 0x06dc, 0x06e3, 0x06e7, 0x06e8, 0x08ca, 0x08cb, 0x08cd, 0x08ce, 0x08cf, 0x08d3, 0x08f3 => true,
        else => false,
    };
}

fn markSortClass(source_index: usize, codepoints: []const u21) u8 {
    if (source_index >= codepoints.len) return 0;
    return unicode.modifiedCombiningClassForShaping(codepoints[source_index]);
}

fn inheritsLeadingDefaultIgnorableCluster(codepoints: []const u21, clusters: []const usize, invisible_glyph_id: GlyphId) bool {
    return codepoints.len == 1 and clusters.len == 1 and
        invisible_glyph_id == 0 and
        unicode.isDefaultIgnorableForShaping(codepoints[0]) and
        unicode.joiningTypeForCodepoint(codepoints[0]) != .join_causing;
}

fn isDefaultIgnorableForShaping(codepoint: u21) bool {
    return unicode.isDefaultIgnorableForShaping(codepoint);
}

fn glyphIndexWithOptionalCache(font: *const Font, cache: ?*GlyphIndexCache, codepoint: u21) !GlyphId {
    if (cache) |glyph_cache| return try glyph_cache.glyphIndex(font, codepoint);
    return try font.glyphIndex(codepoint);
}

fn fallbackGlyphIndexWithOptionalCache(font: *const Font, cache: ?*GlyphIndexCache, codepoint: u21) !GlyphId {
    if (try space_fallback.glyphForCodepoint(font, codepoint)) |glyph| return glyph;
    const glyph = try glyphIndexWithOptionalCache(font, cache, codepoint);
    if (glyph != 0) return glyph;
    return (try unicode_glyph_fallback.glyphForMissingCodepoint(font, codepoint)) orelse glyph;
}

fn runMayHaveMarkAttachments(glyphs: []const GlyphId, codepoints: []const u21, glyph_source_indices: []const usize, metadata: GdefLookupMetadata) bool {
    const classes = metadata.glyph_classes orelse return true;
    for (glyphs, 0..) |glyph, index| {
        if (glyph < classes.len and classes[glyph] == @intFromEnum(GlyphClass.mark)) return true;
        const source_index = if (index < glyph_source_indices.len)
            @min(glyph_source_indices[index], codepoints.len -| 1)
        else
            @min(index, codepoints.len -| 1);
        if (source_index < codepoints.len and unicode.isUnicodeMarkCodepoint(codepoints[source_index])) return true;
    }
    return false;
}

fn horizontalMetricsWithOptionalCache(font: *const Font, cache: ?*GlyphMetricsCache, glyph_id: GlyphId, normalized_variation_coords: []const f32) !GlyphMetrics {
    if (cache) |metrics_cache| return try metrics_cache.horizontalMetricsAtCoords(font, glyph_id, normalized_variation_coords);
    const raw = if (normalized_variation_coords.len == 0)
        try font.horizontalMetrics(glyph_id)
    else
        try font.horizontalMetricsAtCoords(glyph_id, normalized_variation_coords);
    return .{
        .advance_width = raw.advance_width,
        .left_side_bearing = raw.left_side_bearing,
    };
}

fn verticalMetricsWithOptionalCache(font: *const Font, cache: ?*GlyphMetricsCache, glyph_id: GlyphId, normalized_variation_coords: []const f32) !?VerticalGlyphMetrics {
    if (cache) |metrics_cache| {
        return metrics_cache.verticalMetricsAtCoords(font, glyph_id, normalized_variation_coords) catch |err| switch (err) {
            // Some deployed CJK fonts advertise optional vhea/vmtx tables with
            // unusable header line metrics. Vertical shaping must still retain
            // its y-axis contract and vert substitutions; fall back to one em
            // advance instead of abandoning shaping and rendering horizontally.
            error.InvalidMetrics => null,
            else => return err,
        };
    }
    const raw = (if (normalized_variation_coords.len == 0)
        font.verticalMetrics(glyph_id)
    else
        font.verticalMetricsAtCoords(glyph_id, normalized_variation_coords)) catch |err| switch (err) {
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

test "font fallback keeps combining graphemes in a fully covering font" {
    const test_font = @import("test_font.zig");
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

test "Arabic normalization composes base mark pairs when the font has the precomposed glyph" {
    const test_font = @import("test_font.zig");
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

test "font fallback accepts Arabic clusters covered through normalization" {
    const test_font = @import("test_font.zig");
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
    const test_font = @import("test_font.zig");
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
    const test_font = @import("test_font.zig");
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

test "unsupported variation selectors can report a synthetic not-found glyph" {
    const test_font = @import("test_font.zig");
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

test "vertical presentation fallback survives bottom-to-top shaping" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildCodepointSetTtf(std.testing.allocator, &.{
        0x3008,
        0x3009,
        0xfe3f,
        0xfe40,
    });
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const ttb = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), ttb.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 3), ttb.glyphs[0].glyph_id);

    const btt = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "\u{3008}",
        20,
        .{ .direction = .rtl, .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), btt.glyphs.len);
    try std.testing.expectEqual(@as(GlyphId, 4), btt.glyphs[0].glyph_id);
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

test "mark attachment propagation keeps long advances in user space" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 50000 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 1, .x_advance = 0, .x_offset = 12 },
    };
    var links = [_]attachment.Link{
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    attachment.propagateOffsets(GlyphPosition, &glyphs, &links, .forward, .horizontal);

    // Large paragraphs can place a mark many glyph advances after its base
    // before MarkBase/MarkLig positioning pulls it back. This offset is well
    // within f32 layout range and must not be converted back through i16.
    try std.testing.expectApproxEqAbs(@as(f32, 12.0 - 50000.0), glyphs[1].x_offset, 0.01);
}
