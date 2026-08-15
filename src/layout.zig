const std = @import("std");
const aat_kerx = @import("aat_kerx.zig");
const arabic_normalization = @import("arabic_normalization.zig");
const attachment = @import("attachment.zig");
const Font = @import("font.zig").Font;
const fallback_mark = @import("shaping/fallback/mark.zig");
const GdefLookupMetadata = @import("font.zig").GdefLookupMetadata;
const GlyphClass = @import("font.zig").GlyphClass;
const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const khmer = @import("khmer.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const gsub = @import("gsub.zig");
const indic = @import("indic.zig");
const layout_cache = @import("shaping/context/cache/root.zig");
const layout_scratch = @import("shaping/context/scratch.zig");
const myanmar = @import("myanmar.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const shaping_sections = @import("shaping_sections.zig");
const run_metadata = @import("shaping/run_metadata.zig");
const diagnostics = @import("shaping/diagnostics/root.zig");
const diagnostic_caret = diagnostics.caret;
const diagnostic_quality = diagnostics.quality;
const diagnostic_types = diagnostics.types;
const stch_feature = @import("shaping/features/stch/root.zig");
const bidi_reorder = @import("layout/bidi/reorder/root.zig");
const glyph_position = @import("layout/glyph_position.zig");
const paragraph_types = @import("layout/types/paragraph.zig");
const run_types = @import("layout/types/runs.zig");
const line_break_analysis = @import("layout/line_break/analysis.zig");
const paragraph_reflow = @import("layout/line_break/reflow/root.zig");
const shaped_boundary = @import("layout/line_break/shaped_boundary.zig");
const styled_bidi = @import("layout/styled_bidi.zig");
const styled_buffer = @import("layout/styled_buffer.zig");
const styled_paragraph = @import("layout/styled_paragraph.zig");
const bidi = @import("text/bidi.zig");
const segmentation = @import("text/segmentation/root.zig");
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
pub const GlyphPosition = glyph_position.GlyphPosition;

pub const GlyphRun = run_types.GlyphRun;
pub const CascadeRun = run_types.CascadeRun;
pub const ShapedText = run_types.ShapedText;
pub const ScriptedRun = run_types.ScriptedRun;
pub const ScriptedText = run_types.ScriptedText;

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
    /// Delete untouched default-ignorables after substitution and positioning.
    ///
    /// The default behavior mirrors HarfBuzz by replacing them with the font's
    /// space glyph at zero advance when one exists. This explicit mode forces
    /// deletion even in that case, while substituted controls and a requested
    /// not-found variation-selector glyph remain visible.
    remove_default_ignorables: bool = false,
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
    remove_default_ignorables: bool = false,
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
            .remove_default_ignorables = options.remove_default_ignorables,
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

pub const TextAlign = paragraph_types.TextAlign;
pub const WrapMode = paragraph_types.WrapMode;

pub const BaselineMetrics = paragraph_reflow.BaselineMetrics;

pub const TextMetrics = paragraph_types.TextMetrics;

pub const ParagraphOptions = struct {
    max_width: f32,
    wrap_mode: WrapMode = .word,
    alignment: TextAlign = .start,
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
    /// Optional language dictionary for scripts that normally omit spaces.
    ///
    /// The dictionary adds soft opportunities to UAX #14; all candidates still
    /// pass grapheme and shaping `unsafe-to-break` checks. The dictionary must
    /// outlive this layout call and any `ShapedParagraph` created from it.
    word_break_dictionary: ?*const segmentation.WordBreakDictionary = null,
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

/// One contiguous style item for unified paragraph shaping.
///
/// Spans form an exact, ordered partition of the UTF-8 input. Font family
/// resolution remains the caller's responsibility through `FontCascade`;
/// these fields describe the shaping and geometry choices that are meaningful
/// after a cascade has been selected.
pub const StyledParagraphSpan = styled_paragraph.Span;
pub const StyledGlyphMetadata = styled_buffer.Metadata;
pub const StyledParagraphBuffer = styled_buffer.Buffer;

pub const ParagraphLine = paragraph_types.ParagraphLine;
pub const TextPosition = paragraph_types.TextPosition;
pub const TextRect = paragraph_types.TextRect;
pub const ParagraphLayout = paragraph_types.ParagraphLayout;
const positionByteOffset = paragraph_types.positionByteOffset;

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
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
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
        if (options.word_break_dictionary != self.word_break_dictionary or
            !paragraphOptionsMatchShapeKey(self.text, options, self.shape_key))
        {
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
            self.word_break_dictionary,
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

pub const FontFallbackDecision = diagnostic_types.FontFallbackDecision;
pub const MissingGlyphDiagnostic = diagnostic_types.MissingGlyphDiagnostic;
pub const ShapeQualityFontRunDiagnostic = diagnostic_types.ShapeQualityFontRunDiagnostic;
pub const ShapeQualityScriptRunDiagnostic = diagnostic_types.ShapeQualityScriptRunDiagnostic;
pub const ShapeQualityReport = diagnostic_types.ShapeQualityReport;
pub const ClusterCaretIssueKind = diagnostic_types.ClusterCaretIssueKind;
pub const ClusterCaretDiagnostic = diagnostic_types.ClusterCaretDiagnostic;
pub const ClusterCaretConsistencyReport = diagnostic_types.ClusterCaretConsistencyReport;

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
            if (unicode.isVariationSelector(codepoint) or isClusterCoverageIgnorable(codepoint)) {
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
    }, defaultBaselineMetrics(cascade.fonts[0], font_size), null, null, null);
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

    const scripted = try TextShaper.shapeUtf8ScriptRuns(
        cascade,
        &buffer,
        text,
        font_size,
        options,
    );
    const fallback = try diagnoseFontFallbackUtf8(allocator, cascade, text);
    defer allocator.free(fallback);
    return try diagnostic_quality.summarize(allocator, scripted, fallback);
}

const diagnoseClusterCaretConsistencyForLayout = diagnostic_caret.analyze;

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
        const line_breaks = try line_break_analysis.itemize(
            allocator,
            text,
            grapheme_clusters,
            options.word_break_dictionary,
        );
        errdefer allocator.free(line_breaks);

        return .{
            .allocator = allocator,
            .text = owned_text,
            .glyphs = owned_glyphs,
            .runs = owned_runs,
            .grapheme_clusters = grapheme_clusters,
            .line_breaks = line_breaks,
            .word_break_dictionary = options.word_break_dictionary,
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
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
        );
        if (options.direction == .rtl or textHasRtlBidiClass(text)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        return buffer.paragraphLayout();
    }

    pub fn layoutParagraphUtf8WithCaches(cascade: FontCascade, fallback_cache: ?*FontFallbackCache, metrics_cache: ?*GlyphMetricsCache, glyph_index_cache: ?*GlyphIndexCache, shaped_cache: ?*ShapedRunCache, buffer: *LayoutBuffer, text: []const u8, font_size: f32, options: ParagraphOptions) !ParagraphLayout {
        try validateParagraphOptions(options);
        _ = try shapeUtf8CascadeWithCaches(cascade, fallback_cache, metrics_cache, glyph_index_cache, shaped_cache, buffer, text, font_size, shapeOptionsForParagraph(options));
        try normalizeParagraphGlyphsToLogicalOrder(buffer);
        try buildParagraphLines(
            buffer,
            text,
            options,
            defaultBaselineMetrics(cascade.fonts[0], font_size),
            null,
            null,
            options.word_break_dictionary,
        );
        if (options.direction == .rtl or textHasRtlBidiClass(text)) {
            try applyParagraphLineBidiVisualOrder(buffer, text, options.direction);
        }
        return buffer.paragraphLayout();
    }

    /// Shape style items into one paragraph before line breaking.
    ///
    /// Unlike the legacy attributed-run helpers, style boundaries do not
    /// create independent paragraphs: all items share one source coordinate
    /// space, fallback stream, line breaker, bidi pass, and alignment result.
    pub fn layoutStyledParagraphUtf8(
        cascade: FontCascade,
        buffer: *LayoutBuffer,
        styled: *StyledParagraphBuffer,
        text: []const u8,
        default_font_size: f32,
        spans: []const StyledParagraphSpan,
        options: ParagraphOptions,
    ) !ParagraphLayout {
        try validateParagraphOptions(options);
        try validateShapingUtf8(text);
        try validateShapingFontSize(default_font_size);
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;

        buffer.clear();
        styled.clear();
        var driver = StyledParagraphDriver{
            .cascade = cascade,
            .buffer = buffer,
            .styled = styled,
            .text = text,
            .default_font_size = default_font_size,
            .options = options,
        };
        try styled_paragraph.layout(&driver, text, spans);

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

const StyledParagraphDriver = struct {
    cascade: FontCascade,
    buffer: *LayoutBuffer,
    styled: *StyledParagraphBuffer,
    text: []const u8,
    default_font_size: f32,
    options: ParagraphOptions,
    pen: PenPosition = .{},

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return self.buffer.allocator;
    }

    pub fn validateSpan(_: *@This(), span: StyledParagraphSpan) !void {
        try validateShapingFontSize(span.font_size);
        if (span.fonts) |fonts| {
            if (fonts.len == 0) return error.EmptyFontCascade;
        }
        try validateFeatureOverrides(span.features);
        try validateNormalizedVariationCoords(span.normalized_variation_coords);
        if (!std.math.isFinite(span.letter_spacing) or
            !std.math.isFinite(span.word_spacing))
        {
            return error.InvalidStyleSpans;
        }
        if (span.minimum_line_height) |height| {
            if (!std.math.isFinite(height) or height <= 0) {
                return error.InvalidStyleSpans;
            }
        }
    }

    fn normalizeNewRunFontIndices(
        self: *@This(),
        run_start: usize,
    ) void {
        // `shapeCascadeSegmentInto` records indexes relative to the style-local
        // cascade. Public paragraph runs use the driver's union cascade so
        // diagnostics and render integrations see one stable index space.
        for (self.buffer.runs.items[run_start..]) |*run| {
            for (self.cascade.fonts, 0..) |font, font_index| {
                if (font != run.font) continue;
                run.font_index = font_index;
                break;
            }
        }
    }

    pub fn shapeItem(
        self: *@This(),
        byte_start: usize,
        byte_end: usize,
        inferred_script: unicode.Script,
        span: StyledParagraphSpan,
    ) !void {
        const item_text = self.text[byte_start..byte_end];
        const item_cascade = FontCascade.init(span.fonts orelse self.cascade.fonts);
        const run_start = self.buffer.runs.items.len;
        self.pen = try shapeCascadeSegmentInto(
            item_cascade,
            self.buffer,
            item_text,
            span.font_size,
            byte_start,
            self.pen,
            .{
                .lookup = .{
                    .script = inferred_script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(inferred_script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(item_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    .context_before = self.text[0..byte_start],
                    .context_after = self.text[byte_end..],
                    .beginning_of_text = byte_start == 0,
                    .end_of_text = byte_end == self.text.len,
                },
                .all_ascii = textIsAscii(item_text),
            },
        );
        if (span.fonts != null) {
            self.normalizeNewRunFontIndices(run_start);
        }
    }

    pub fn finish(self: *@This(), spans: []const StyledParagraphSpan) !void {
        try normalizeParagraphGlyphsToLogicalOrder(self.buffer);
        try rebuildStyledGlyphMetadata(self.buffer, self.styled, spans);
        try styled_buffer.applySpacing(
            self.styled.metadata.items,
            self.buffer.glyphs.items,
        );
        const shaped_glyph_count = self.buffer.glyphs.items.len;
        var line_options = self.options;
        // The established line engine remains style-agnostic. Defer synthetic
        // dots until its prefix truncation is complete so the sidecar can
        // capture the terminal visible style before the fit loop removes it.
        line_options.ellipsis = false;
        try buildParagraphLines(
            self.buffer,
            self.text,
            line_options,
            defaultBaselineMetrics(
                self.cascade.fonts[0],
                self.default_font_size,
            ),
            null,
            null,
            self.options.word_break_dictionary,
        );
        const content_omitted = self.buffer.glyphs.items.len < shaped_glyph_count or
            (self.buffer.lines.items.len != 0 and
                self.buffer.lines.items[self.buffer.lines.items.len - 1].byteEnd() <
                    self.text.len);
        try styled_buffer.synchronizeAfterTruncation(
            &self.styled.metadata,
            self.buffer.glyphs.items.len,
        );
        if (self.options.ellipsis and content_omitted and
            self.buffer.glyphs.items.len != 0)
        {
            try styled_buffer.appendEllipsis(
                &self.styled.metadata,
                self.styled.allocator,
                self.buffer,
                if (self.options.max_width > 0)
                    self.options.max_width
                else
                    std.math.inf(f32),
                resolvedAlignment(self.options),
                alignedLineX,
            );
        }
        styled_buffer.applyMinimumLineHeights(
            self.styled.metadata.items,
            self.buffer.glyphs.items.len,
            self.buffer.lines.items,
        );
        if (self.options.direction == .rtl or textHasRtlBidiClass(self.text)) {
            const visual_order = try styled_bidi.visualPermutation(
                self.buffer.allocator,
                self.text,
                self.options.direction == .rtl,
                self.buffer.lines.items,
                self.buffer.glyphs.items,
            );
            defer self.buffer.allocator.free(visual_order);
            try applyParagraphLineBidiVisualOrder(
                self.buffer,
                self.text,
                self.options.direction,
            );
            try styled_buffer.reorderByPermutation(
                &self.styled.metadata,
                self.styled.allocator,
                visual_order,
            );
        }
    }
};

fn rebuildStyledGlyphMetadata(
    buffer: *LayoutBuffer,
    styled: *StyledParagraphBuffer,
    spans: []const StyledParagraphSpan,
) !void {
    return try styled_buffer.rebuild(
        &styled.metadata,
        styled.allocator,
        buffer.glyphs.items,
        spans,
    );
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
    return if (unicode.isVariationSelector(selector)) selector else null;
}

const ArabicCompositionMatch = struct {
    codepoint: u21,
    glyph_id: GlyphId,
    byte_end: usize,
};

fn arabicCompositionForFontAt(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, starter: u21, text: []const u8, mark_byte_start: usize) !?ArabicCompositionMatch {
    if (!arabic_normalization.canStartComposition(starter)) return null;
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
        if (unicode.isVariationSelector(codepoint) or isClusterCoverageIgnorable(codepoint)) continue;
        if (glyph_index_cache) |cache| return try selectFontUsingGlyphCache(cascade, cache, codepoint);
        return try cascade.selectFont(codepoint);
    }
    return 0;
}

fn clusterHasVariationSelector(cluster: []const u8) bool {
    var it = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (unicode.isVariationSelector(codepoint)) return true;
    }
    return false;
}

fn fontCoversCluster(font: *const Font, glyph_index_cache: ?*GlyphIndexCache, cluster: []const u8, require_variation_mapping: bool) !bool {
    var it = std.unicode.Utf8Iterator{ .bytes = cluster, .i = 0 };
    var previous_visible: ?u21 = null;
    while (it.nextCodepoint()) |codepoint| {
        if (unicode.isVariationSelector(codepoint)) {
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
    return !unicode.isVariationSelector(codepoint) and unicode.isDefaultIgnorableForShaping(codepoint);
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

fn applyBidiVisualOrder(
    buffer: *LayoutBuffer,
    text: []const u8,
    direction: TextDirection,
    single_font: ?*const Font,
) !void {
    return try bidi_reorder.apply(
        buffer,
        text,
        direction == .rtl,
        single_font,
    );
}

const normalizeParagraphGlyphsToLogicalOrder = bidi_reorder.normalizeLogical;

fn applyParagraphLineBidiVisualOrder(
    buffer: *LayoutBuffer,
    text: []const u8,
    direction: TextDirection,
) !void {
    return try bidi_reorder.applyLines(buffer, text, direction == .rtl);
}

/// Typed adapter between public paragraph records and the internal generic
/// reflow module. Keeping concrete types here also gives struct literals their
/// complete `ParagraphOptions` result type at call sites.
fn buildParagraphLines(
    buffer: *LayoutBuffer,
    text: []const u8,
    options: ParagraphOptions,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const unicode.LineBreak,
    dictionary: ?*const segmentation.WordBreakDictionary,
) !void {
    return try paragraph_reflow.build(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
    );
}

const resolvedAlignment = paragraph_reflow.resolvedAlignment;
const alignedLineX = paragraph_reflow.alignedLineX;
const runRangeForGlyphs = paragraph_reflow.runRangeForGlyphs;
const defaultBaselineMetrics = paragraph_reflow.defaultBaselineMetrics;
const glyphSourceEnd = shaped_boundary.glyphSourceEnd;

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
    remove_default_ignorables: bool = false,
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
        .remove_default_ignorables = options.remove_default_ignorables,
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
        a.remove_default_ignorables == b.remove_default_ignorables and
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
    const glyph_script_positions = &scratch.glyph_script_positions;
    const glyph_output_indices = &scratch.glyph_output_indices;
    const stch_actions = &scratch.stch_actions;
    const source_boundaries = &scratch.source_boundaries;

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
            if (unicode.isVariationSelector(codepoint)) {
                if (glyph_ids.items.len != 0) {
                    if (selected_lookup_options.script_tag != .mym2) {
                        if (try font.variationGlyphIndex(codepoints.items[codepoints.items.len - 1], codepoint)) |variant_glyph| {
                            glyph_ids.items[glyph_ids.items.len - 1] = variant_glyph;
                            source_ends.items[source_ends.items.len - 1] = cluster_base + it.i;
                            continue;
                        }
                    }
                    // Myanmar's syllable grammar gives VS an explicit category,
                    // so mym2 keeps the selector's nominal glyph (or glyph 0)
                    // instead of folding a cmap-14 variant into the base.
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
            const leading_default_ignorable_cluster = codepoints.items.len == 1 and
                clusters.items.len == 1 and
                inheritsLeadingDefaultIgnorableCluster(codepoints.items, clusters.items, if (default_ignorable_invisible_glyph_id) |glyph| glyph else resolve: {
                    const glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
                    default_ignorable_invisible_glyph_id = glyph;
                    break :resolve glyph;
                });
            const previous_zwnj_cluster = selected_lookup_options.direction == .rtl and
                codepoints.items.len != 0 and
                codepoints.items[codepoints.items.len - 1] == 0x200c and
                inheritsPreviousZwnjClusterInRtlShaping(
                    selected_lookup_options.direction,
                    codepoints.items,
                    if (default_ignorable_invisible_glyph_id) |glyph| glyph else resolve: {
                        const glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, ' ');
                        default_ignorable_invisible_glyph_id = glyph;
                        break :resolve glyph;
                    },
                );
            const inherits_previous_cluster = leading_default_ignorable_cluster or
                codepoint == 0x200d or
                (explicit_cluster_level != null and unicode.isUnicodeMarkCodepoint(codepoint)) or
                (selected_lookup_options.script_tag == .tibt and isTibetanClusterExtender(codepoint)) or
                (usesThaiLaoSaraAmPreprocess(selected_lookup_options.script_tag) and isThaiLaoClusterExtender(codepoint)) or
                previous_zwnj_cluster or
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
    source_boundaries.reset(cluster_base, text.len, clusters.items);

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
    const gsub_feature_overrides = if (runNeedsHangulDefaultDisabledCalt(codepoints.items))
        featureOverridesWithDefaultDisabledCalt(hangul_feature_overrides_buf[0..], lookup_options.features) orelse lookup_options.features
    else
        lookup_options.features;

    var gsub_random_state: u32 = 1;
    var gsub_run_limits = try gsub.RunLimits.init(glyph_ids.items.len);
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
        .source_boundaries = source_boundaries,
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
        .aat_buffer_reversed = shape_in_native_direction,
    };
    // Script shapers split one logical GSUB pass into several feature stages.
    // Keep HarfBuzz-style operation and growth limits shared across every
    // stage, including nested contextual lookups, rather than resetting the
    // safety envelope for each feature.
    gsub_run_limits.applyTo(&gsub_options);
    const gsub_start = shapeProfileNow(shape_profile, profile_io);
    const gsub_after_proof = if (buffer.gsub_table_proof_cache) |proof_cache| proof: {
        try proof_cache.prove(font);
        break :proof true;
    } else false;
    if (buffer.lookup_selection_cache) |selection_cache| {
        gsub_options.lookup_accelerators = try selection_cache.gsubLookupAccelerators(font);
    }
    if (lookup_options.beginning_of_text and
        lookup_options.context_before.len == 0 and
        codepoints.items.len != 0 and
        unicode.isUnicodeMarkCodepoint(codepoints.items[0]) and
        lookup_options.script_tag != .mym2)
    {
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
        source_boundaries.bindSourceByteStarts(clusters.items);
    }
    const use_shape = use_shaper.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const myanmar_shape = myanmar.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const khmer_shape = khmer.shouldShape(lookup_options.script_tag) and codepoints.items.len != 0;
    const early_zero_mark_shape = use_shape or myanmar_shape;
    if (use_shape or myanmar_shape) {
        // Cluster ownership for source text must be established before vowel
        // constraints inject synthetic U+25CC sources that do not exist in the
        // original UTF-8 byte stream.
        try use_shaper.assignShapingClusterOwners(
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
                lookup_options.cluster_level orelse .monotone_graphemes,
            );
        }
        gsub_options.source_codepoints = codepoints.items;
        source_boundaries.bindSourceByteStarts(clusters.items);
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
    var arabic_joining_features: ?[]const u32 = null;
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
        arabic_joining_features = source_features.items;

        const stch_enabled = shapingFeatureEnabled(unicode.tag("stch"), lookup_options.features, true);
        var common_features_buf: [2]gsub.FeatureApplication = undefined;
        var common_feature_count: usize = 0;
        if (randomFeatureApplication(lookup_options.features)) |application| {
            common_features_buf[common_feature_count] = application;
            common_feature_count += 1;
        }
        if (stch_enabled) {
            common_features_buf[common_feature_count] = .{
                .tag = unicode.tag("stch"),
                .auto_zwj = false,
            };
            common_feature_count += 1;
        }
        if (common_feature_count != 0) {
            // `rand` is a common HarfBuzz feature collected before the Arabic
            // shaper adds `stch`; both therefore occupy the same GSUB stage.
            // Merge by lookup-list order rather than applying tag order, while
            // retaining the random semantic bit in the resulting plan.
            try applyMergedGsubFeatureApplicationsForShaping(
                font,
                buffer,
                gsub_after_proof,
                common_features_buf[0..common_feature_count],
                glyph_ids,
                joining_options,
                gdef_metadata.*,
            );
        }
        if (stch_enabled) {
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
        myanmar.markSourceSyllables(
            source_syllables.items,
            glyph_source_indices.items,
            codepoints.items,
        );
        var myanmar_options = gsub_options;
        myanmar_options.source_syllables = source_syllables.items;

        // Myanmar marks syllables before `locl`/`ccmp`, but HarfBuzz applies
        // those features before dotted-circle insertion and reordering.
        try applyGsubFeatureApplicationsForShaping(
            font,
            buffer,
            gsub_after_proof,
            &.{ .{ .tag = unicode.tag("locl") }, .{ .tag = unicode.tag("ccmp") } },
            glyph_ids,
            gsub_options,
            gdef_metadata.*,
        );
        const dotted_circle_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, 0x25cc);
        try myanmar.insertDottedCirclesForBrokenSyllables(
            buffer.allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            source_syllables.items,
            dotted_circle_glyph,
        );
        try myanmar.reorder(
            buffer.allocator,
            glyph_ids,
            glyph_source_indices,
            glyph_cluster_indices,
            glyph_substituted,
            ligature_components,
            glyph_script_positions,
            source_syllables.items,
            codepoints.items,
        );
        try gsub.validateScriptShaperRunMetadata(myanmar_options, glyph_ids.items.len);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.rphf), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.pref), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.blwf), glyph_ids, myanmar_options, gdef_metadata.*);
        try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, myanmar.featureApplications(.pstf), glyph_ids, myanmar_options, gdef_metadata.*);

        var myanmar_final_buf: [20]gsub.FeatureApplication = undefined;
        var myanmar_final_count: usize = 0;
        for (myanmar.featureApplications(.final)) |application| {
            if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
            myanmar_final_buf[myanmar_final_count] = application;
            myanmar_final_count += 1;
        }
        const myanmar_typographic_features = [_]gsub.FeatureApplication{
            .{ .tag = unicode.tag("rlig") },
            .{ .tag = unicode.tag("calt") },
            .{ .tag = unicode.tag("clig") },
            .{ .tag = unicode.tag("liga") },
        };
        for (myanmar_typographic_features) |application| {
            if (!shapingFeatureEnabled(application.tag, lookup_options.features, true)) continue;
            myanmar_final_buf[myanmar_final_count] = application;
            myanmar_final_count += 1;
        }
        myanmar_final_count += explicitOptionalFeatureApplications(
            myanmar_final_buf[myanmar_final_count..],
            lookup_options.features,
        );
        // HarfBuzz places Myanmar's four post-reorder features and the common
        // typographic features in one map stage. Merge them before sorting by
        // LookupList index; applying two batches changes authored lookup order.
        try applyMergedGsubFeatureApplicationsAfterRunProof(
            font,
            buffer,
            gsub_after_proof,
            myanmar_final_buf[0..myanmar_final_count],
            glyph_ids,
            gsub_options,
            gdef_metadata.*,
        );
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
        source_boundaries.bindSourceByteStarts(clusters.items);
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
        // GSUB mutation helpers preserve source-parallel cardinalities even
        // when a format-1 delta temporarily leaves maxp's renderable range.
        // Prove the current maximal USE metadata contract once after stage-only
        // scratch is detached, then reuse it through all remaining stages.
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
                lookup_options.cluster_level orelse .monotone_graphemes,
            );
            gsub_options.source_codepoints = codepoints.items;
            source_boundaries.bindSourceByteStarts(clusters.items);
        }
        if (lookup_options.script_tag == .hang and hasHangulJamo(codepoints.items)) {
            try source_features.resize(buffer.allocator, codepoints.items.len);
            if (markHangulJamoSourceFeatures(source_features.items, codepoints.items) and
                hangulJamoFeaturesCoverAllJamo(source_features.items, codepoints.items))
            {
                mergeHangulJamoClusters(glyph_cluster_indices.items, glyph_source_indices.items, codepoints.items);
                var hangul_jamo_feature_overrides_buf: [32]unicode.FeatureOverride = undefined;
                const hangul_features = hangulFeatureOverridesWithJamoFeatures(hangul_jamo_feature_overrides_buf[0..], gsub_options.features) orelse gsub_options.features;
                var hangul_options = gsub_options;
                hangul_options.features = hangul_features;
                if (gsub_after_proof) {
                    try font.applyGsubWithOptionsUsingGdefAfterProof(glyph_ids, buffer.allocator, hangul_options, gdef_metadata.*);
                } else {
                    try font.applyGsubWithOptionsUsingGdefForShaping(glyph_ids, buffer.allocator, hangul_options, gdef_metadata.*);
                }
            }
        }
        const apply_aat_substitution = font.hasAatSubstitutionForShaping() and
            (!lookup_options.writing_mode.isVertical() or !font.hasGsubTableForShaping());
        if (apply_aat_substitution) {
            try font.applyAatSubstitutionForShaping(glyph_ids, buffer.allocator, gsub_options);
        } else {
            const gsub_needs_value_selection = needsValueAwareGsubSelection(
                font,
                gsub_options.features,
                gsub_options.lookup_accelerators,
                gsub_after_proof,
            );
            if (lookup_options.normalized_variation_coords.len == 0 and !gsub_needs_value_selection) if (buffer.lookup_selection_cache) |selection_cache| {
                gsub_options.selected_lookups = try selection_cache.gsubLookups(font, gsub_options, gdef_metadata.*);
            };
            if (gsub_after_proof) {
                const has_cached_selection = if (gsub_options.selected_lookups) |lookups|
                    lookups.len != 0
                else
                    false;
                if (has_cached_selection and buffer.lookup_selection_cache != null) {
                    try applyGenericGsubAfterTableProof(
                        font,
                        buffer,
                        glyph_ids,
                        gsub_options,
                        gdef_metadata.*,
                    );
                } else {
                    try font.applyGsubWithOptionsUsingGdefAfterProof(glyph_ids, buffer.allocator, gsub_options, gdef_metadata.*);
                }
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
            indic.mergeMalayalamDotRephBrokenCluster(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.mergePlaceholderDependentMarks(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.mergeTrailingDependentMarks(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.mergeKannadaOldSpecTrailingBlwf(glyph_cluster_indices, glyph_source_indices, codepoints.items, lookup_options.script_tag);
            indic.normalizeOldSpecPostBaseHalantOrder(
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

            try gsub.validateScriptShaperRunMetadata(gsub_options, glyph_ids.items.len);
            // The maximal proof covers the pre-reorder stage too: source
            // features/syllables and every glyph-parallel sidecar are already
            // complete here, and all supported GSUB mutations preserve those
            // contracts. Start the trusted cached-plan sequence immediately
            // instead of defensively validating this same run twice.
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.preReorderFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
            // Kannada BEFORE_SUB vowels must already be between the main and
            // below-base consonants when `blwf` evaluates its context. Telugu
            // performs its related move during final reordering instead.
            indic.reorderInitialKannadaVowels(
                glyph_ids,
                glyph_source_indices,
                glyph_cluster_indices,
                glyph_substituted,
                ligature_components,
                codepoints.items,
                lookup_options.script_tag,
            );
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
            indic.reorderBengaliBelowVowelsAfterBase(glyph_ids, glyph_source_indices, glyph_cluster_indices, glyph_substituted, ligature_components, codepoints.items, lookup_options.script_tag);
            try applyGsubFeatureApplicationsAfterRunProof(font, buffer, gsub_after_proof, indic.finalFeatureApplications(), glyph_ids, gsub_options, gdef_metadata.*);
            indic.mergeMalayalamOldSpecTrailingViramaClusters(glyph_cluster_indices, glyph_source_indices, ligature_components, codepoints.items, lookup_options.script_tag);
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

    // OpenType SingleSubst format 1 is a modulo-16-bit graph. Individual
    // lookups may use IDs above maxp as internal states, but no such transient
    // value may escape the complete GSUB stage into GPOS, metrics, or outlines.
    try font.validateShapedGlyphRunForShaping(glyph_ids.items);

    if (shape_profile) |p| p.gsub_ns += shapeProfileElapsed(gsub_start, profile_io);

    const gpos_adjustments = &scratch.gpos_adjustments;
    const gpos_start = shapeProfileNow(shape_profile, profile_io);
    var gpos_unsafe_glyphs = run_metadata.UnsafeGlyphs{};
    const gpos_run_metadata = run_metadata.Positioning{
        .glyph_source_indices = glyph_source_indices.items,
        .source_codepoints = codepoints.items,
        .glyph_substituted = glyph_substituted.items,
        .ligature_components = ligature_components,
        .source_boundaries = source_boundaries,
    };
    var gpos_options = gpos.LookupOptions{
        .script_tag = gpos_script_tag,
        .language_tag = lookup_options.language_tag,
        .direction = if (shapingDirectionForGpos(lookup_options) == .rtl) .rtl else .ltr,
        .vertical = lookup_options.writing_mode.isVertical(),
        .features = lookup_options.features,
        .normalized_variation_coords = lookup_options.normalized_variation_coords,
        .apply_all_if_unselected = false,
        .run_may_have_mark_attachments = runMayHaveMarkAttachments(glyph_ids.items, codepoints.items, glyph_source_indices.items, gdef_metadata.*),
        .run_has_default_ignorables = has_default_ignorable,
        .run_metadata = &gpos_run_metadata,
        .unsafe_glyphs = &gpos_unsafe_glyphs,
        .shape_profile = shape_profile,
        .profile_io = profile_io,
        .visible_variation_selectors = lookup_options.not_found_variation_selector_glyph != null,
    };
    const apply_aat_substitution = font.hasAatSubstitutionForShaping() and
        (!lookup_options.writing_mode.isVertical() or !font.hasGsubTableForShaping());
    // HarfBuzz prefers GPOS whenever GSUB and GPOS are both the active
    // OpenType engines. If horizontal morx was selected, GSUB is deliberately
    // excluded from that pair and kerx owns positioning instead.
    const use_kerx_positioning = font.hasKerxTableForShaping() and
        (apply_aat_substitution or
            !(font.hasGsubTableForShaping() and font.hasGposTableForShaping()));
    if (!use_kerx_positioning) {
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
    }
    if (shape_profile) |p| p.gpos_ns += shapeProfileElapsed(gpos_start, profile_io);

    const position_start = shapeProfileNow(shape_profile, profile_io);
    const position_sort_start = shapeProfileNow(shape_profile, profile_io);
    std.sort.heap(gpos.Adjustment, gpos_adjustments.items, {}, adjustmentIndexLessThan);
    if (shape_profile) |p| p.position_sort_ns += shapeProfileElapsed(position_sort_start, profile_io);
    const has_gpos_attachments = adjustmentsHaveAttachments(gpos_adjustments.items);
    const has_gdef_glyph_classes = gdef_metadata.glyph_classes != null;
    const has_gpos_positioning = font.hasGposTableForShaping() and !use_kerx_positioning;
    const kerning_enabled = shapingFeatureEnabled(
        if (lookup_options.writing_mode.isVertical()) unicode.tag("vkrn") else unicode.tag("kern"),
        lookup_options.features,
        !lookup_options.writing_mode.isVertical(),
    );
    // HarfBuzz chooses kerx ahead of both GPOS and legacy kern unless GSUB and
    // GPOS are the active OpenType engines. This AAT path intentionally
    // preserves that table-level decision, so a present kerx table suppresses
    // duplicate legacy `kern` application even when no subtable changes this
    // particular run.
    // Cross-stream format-1 actions apply even when `kern`/`vkrn` is disabled,
    // so retain the selected kerx engine independently of the pair-feature
    // mask. The ordered executor receives `kerning_enabled` and suppresses only
    // kerning-requested same/simple subtables.
    const kerx_lookup = if (use_kerx_positioning)
        try font.kerxLookupForShaping()
    else
        null;
    const kerx_adjustments = &scratch.kerx_adjustments;
    const kerx_simple_pair_eligible = &scratch.kerx_simple_pair_eligible;
    var kerx_summary = aat_kerx.Summary{};
    if (kerx_lookup) |lookup| {
        const vertical = lookup_options.writing_mode.isVertical();
        if (try lookup.hasOutputSideAdjustments(vertical, kerning_enabled)) {
            try kerx_simple_pair_eligible.resize(buffer.allocator, glyph_ids.items.len);
            for (glyph_ids.items, kerx_simple_pair_eligible.items, 0..) |glyph_id, *eligible, index| {
                const source_index = if (index < glyph_source_indices.items.len)
                    @min(glyph_source_indices.items[index], codepoints.items.len -| 1)
                else
                    @min(index, codepoints.items.len -| 1);
                const source_codepoint = if (codepoints.items.len == 0) 0 else codepoints.items[source_index];
                const glyph_class = gdef_metadata.glyphClass(glyph_id);
                const was_substituted = index < glyph_substituted.items.len and glyph_substituted.items[index];
                eligible.* = !kerxMachineSkipsGlyph(
                    glyph_class,
                    has_gdef_glyph_classes,
                    source_codepoint,
                    was_substituted,
                );
            }
            kerx_summary = try lookup.collectOrderedAdjustments(
                glyph_ids.items,
                kerx_adjustments,
                buffer.allocator,
                vertical,
                shapingDirectionForGpos(lookup_options) == .rtl,
                kerning_enabled,
                kerx_simple_pair_eligible.items,
                lookup_options.normalized_variation_coords,
            );
        }
    }
    const has_kerx_state_attachments = adjustmentsHaveKerxAttachments(kerx_adjustments.items);
    // GPOS and kerx adjustments are accumulated in font units, then scaled
    // into user-space coordinates for the final GlyphPosition stream.
    const fallback_mark_enabled = fallback_mark.enabled(
        lookup_options.script_tag,
        early_zero_mark_shape,
        has_gpos_positioning,
        has_gpos_attachments or has_kerx_state_attachments,
        use_kerx_positioning,
        lookup_options.writing_mode.isVertical(),
    );
    var previous_kern_glyph: ?GlyphId = null;
    var previous_kern_output_index: ?usize = null;
    var fallback_mark_base: ?fallback_mark.Base = null;
    var adjustment_cursor: usize = 0;
    const kern_lookup = if (kerx_lookup == null and
        !font.hasKerxTableForShaping() and
        !lookup_options.writing_mode.isVertical() and
        shouldApplyLegacyKernFallback(lookup_options.script_tag) and
        kerning_enabled)
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
    const needs_attachment_remapping = has_gpos_attachments or
        has_kerx_state_attachments;
    if (needs_attachment_remapping) {
        // Parent indexes refer to the post-GSUB input stream. Simple
        // cross-stream kerx activates the whole run's cursive chain even when
        // only one pair has a non-zero value, so reserve the reusable sidecars
        // before walking output rather than allocating inside the pair loop.
        try attachment_links.resize(buffer.allocator, glyph_ids.items.len);
        @memset(attachment_links.items, .{});
        try glyph_output_indices.resize(buffer.allocator, glyph_ids.items.len);
        @memset(glyph_output_indices.items, std.math.maxInt(usize));
    }
    const position_loop_start = shapeProfileNow(shape_profile, profile_io);
    for (glyph_ids.items, 0..) |input_glyph_id, index| {
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
        const source_codepoint = if (codepoints.items.len == 0) 0 else codepoints.items[source_index];
        var glyph_id = input_glyph_id;
        if (arabic_joining_features) |features| {
            if (try arabicPresentationFallbackGlyph(font, glyph_index_cache, glyph_id, source_codepoint, source_index, features)) |fallback_glyph| {
                glyph_id = fallback_glyph;
            }
        }
        const metrics = try horizontalMetricsWithOptionalCache(font, metrics_cache, glyph_id, lookup_options.normalized_variation_coords);
        const glyph_class = gdef_metadata.glyphClass(glyph_id);
        const kerx_adjustment = if (index < kerx_adjustments.items.len)
            kerx_adjustments.items[index]
        else
            aat_kerx.Adjustment{};
        var kern_x_advance: f32 = 0;
        const kerx_state_x_offset = @as(f32, @floatFromInt(kerx_adjustment.x_offset)) * scale;
        var kern_x_offset: f32 = 0;
        const was_substituted = index < glyph_substituted.items.len and glyph_substituted.items[index];
        const kerx_skips_glyph = kerx_lookup != null and kerxMachineSkipsGlyph(
            glyph_class,
            has_gdef_glyph_classes,
            source_codepoint,
            was_substituted,
        );
        const active_kern = if (kerx_lookup) |lookup|
            if (kerning_enabled and !kerx_skips_glyph) if (previous_kern_glyph) |previous|
                try lookup.kerning(
                    previous,
                    glyph_id,
                    lookup_options.writing_mode.isVertical(),
                    lookup_options.normalized_variation_coords,
                )
            else
                0 else 0
        else if (kern_lookup) |lookup|
            if (previous_kern_glyph) |previous|
                try lookup.kerning(previous, glyph_id)
            else
                0
        else
            0;
        if (!lookup_options.writing_mode.isVertical()) {
            if (previous_kern_glyph != null) {
                const previous_adjustment = findAdjustmentSorted(gpos_adjustments.items, index - 1, &adjustment_cursor);
                if (kerx_lookup != null or !previous_adjustment.pair_positioned) {
                    if (active_kern != 0) if (previous_kern_output_index) |previous_output_index| {
                        // Legacy `kern` relates the previous participating
                        // source to the current one. HarfBuzz marks that span
                        // unsafe because reshaping either side independently
                        // would lose the pair adjustment.
                        if (kern_lookup != null and index != 0) {
                            try source_boundaries.markGlyphPair(
                                buffer.allocator,
                                glyph_source_indices.items,
                                index - 1,
                                index,
                            );
                        }
                        // Format 6 can carry 32-bit values. Split in that
                        // wider domain before scaling so large but valid AAT
                        // adjustments are not truncated to legacy i16 range.
                        const kern_1 = active_kern >> 1;
                        const kern_2 = active_kern - kern_1;
                        buffer.glyphs.items[previous_output_index].x_advance += @as(f32, @floatFromInt(kern_1)) * scale;
                        kern_x_advance = @as(f32, @floatFromInt(kern_2)) * scale;
                        kern_x_offset = kern_x_advance;
                    };
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
        const attachment_cross_x = if (lookup_options.writing_mode.isVertical())
            @as(f32, @floatFromInt(adjustment.attachment_cross_offset)) * scale
        else
            0.0;
        const attachment_cross_y = if (lookup_options.writing_mode.isVertical())
            0.0
        else
            @as(f32, @floatFromInt(adjustment.attachment_cross_offset)) * scale;
        const gpos_x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) * scale +
            attachment_cross_x;
        const mark_attachment = adjustment.attachment_type == .mark;
        const synthetic_base = index < ligature_components.infos.items.len and
            ligature_components.infos.items[index].flags.synthetic_base;
        const visible_not_found_variation_selector = lookup_options.not_found_variation_selector_glyph != null and
            unicode.isVariationSelector(source_codepoint) and
            !was_substituted and
            !synthetic_base;
        const hide_default_ignorable = isDefaultIgnorableForShaping(source_codepoint) and
            !was_substituted and
            !synthetic_base and
            !visible_not_found_variation_selector;
        const skip_default_ignorable = hide_default_ignorable and
            (lookup_options.remove_default_ignorables or
                invisible_glyph_id == 0 or
                (glyph_id == 0 and unicode.isVariationSelector(source_codepoint) and
                    !variationSelectorFallbackShouldRender(index, source_index, ligature_components)));
        // HarfBuzz removes an untouched default-ignorable when the font has no
        // usable invisible/space glyph. Do this after GPOS so the character was
        // still available to every contextual lookup, then remap attachment
        // links below for the compacted output stream.
        if (skip_default_ignorable) {
            // Removed controls must not become pair candidates, but still
            // record their absent output slot so a later cross-stream chain
            // can compact around them safely.
            if (needs_attachment_remapping) {
                glyph_output_indices.items[index] = std.math.maxInt(usize);
            }
            if (kerx_lookup == null) previous_kern_glyph = glyph_id;
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
            synthetic_base,
            mark_attachment,
            has_gpos_positioning,
            lookup_options,
        );
        const fallback_space_advance = if (!lookup_options.writing_mode.isVertical() and space_fallback.mayNeedHorizontalAdvanceFallback(source_codepoint))
            try space_fallback.advanceWidth(font, source_codepoint, glyph_id, metrics.advance_width)
        else
            null;
        const default_vertical_advance_units: i32 = @as(i32, font.ascender) - @as(i32, font.descender);
        const fallback_space_vertical_advance = if (lookup_options.writing_mode.isVertical() and space_fallback.mayNeedVerticalAdvanceFallback(source_codepoint))
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
            (@as(f32, @floatFromInt(base_advance)) + adjustment_x_advance +
                @as(f32, @floatFromInt(kerx_adjustment.x_advance))) * scale + kern_x_advance;
        const use_sideways_vertical_advance = lookup_options.writing_mode.isVertical() and
            glyphUsesSidewaysAdvance(source_codepoint, lookup_options.text_orientation);
        const vertical_metrics = if (lookup_options.writing_mode.isVertical())
            try verticalMetricsWithOptionalCache(font, metrics_cache, glyph_id, lookup_options.normalized_variation_coords)
        else
            null;
        const unzeroed_vertical_advance = if (use_sideways_vertical_advance)
            (@as(f32, @floatFromInt(metrics.advance_width)) + adjustment_x_advance +
                @as(f32, @floatFromInt(kerx_adjustment.y_advance))) * scale
        else if (vertical_metrics) |value|
            @as(f32, @floatFromInt(value.advance_height)) * scale
        else
            font_size;
        const vertical_advance = if (mark_zeroing.zero_advance)
            0
        else if (fallback_space_vertical_advance) |value|
            (@as(f32, @floatFromInt(value)) + @as(f32, @floatFromInt(kerx_adjustment.y_advance))) * scale
        else if (use_sideways_vertical_advance)
            unzeroed_vertical_advance
        else if (vertical_metrics) |value|
            (@as(f32, @floatFromInt(value.advance_height)) + @as(f32, @floatFromInt(kerx_adjustment.y_advance))) * scale
        else
            font_size + @as(f32, @floatFromInt(kerx_adjustment.y_advance)) * scale;
        const vertical_x_offset = if (vertical_metrics) |_|
            // OpenType's synthesized vertical origin is centered in the
            // horizontal advance box. This keeps upright ideographs centered
            // on the column without rotating the entire run.
            (@as(f32, @floatFromInt(metrics.advance_width)) * 0.5) * scale
        else
            0.0;
        const vertical_y_offset = if (lookup_options.writing_mode.isVertical()) origin: {
            // Store the complete vertical-origin translation in the public
            // positioned glyph, not only vmtx's top-side bearing. This lets
            // raster/render bridges place upright glyphs correctly for VORG,
            // glyf+vmtx, and the no-vmtx extent-centering fallback alike.
            const origin_y = try font.shapingVerticalOriginYForShaping(
                glyph_id,
                lookup_options.normalized_variation_coords,
            );
            break :origin @as(f32, @floatFromInt(origin_y)) * scale;
        } else 0.0;
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
        if (fallback_mark_enabled and
            unicode.isNonspacingMarkCodepoint(source_codepoint))
        {
            if (fallback_mark_base) |*base| {
                fallback_mark_offset = fallback_mark.offset(
                    font,
                    glyph_id,
                    source_codepoint,
                    source_span.start,
                    base,
                    scale,
                ) catch .{};
                // Safety metadata is best-effort under allocation failure,
                // matching GPOS's existing source-boundary fallback: shaping
                // geometry itself remains available if a long-run dynamic
                // bitset cannot grow.
                fallback_mark_offset.recordBreakSafety(
                    source_boundaries,
                    buffer.allocator,
                ) catch {};
            }
        }
        if (needs_attachment_remapping) {
            glyph_output_indices.items[index] = buffer.glyphs.items.len - segment_glyph_start;
        }
        const output_x_offset = if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (lookup_options.writing_mode.isVertical())
            if (kerx_adjustment.cross_stream_assigned or kerx_adjustment.cross_stream_reset)
                // Cross-stream kerning assigns the current minor-axis offset;
                // it does not add to the default vertical origin. The cursive
                // chain below then accumulates the parent's origin and prior
                // cross-stream assignments exactly once.
                kerx_state_x_offset
            else if (kerx_adjustment.attachment_type == .cursive and
                kerx_adjustment.attachment_parent_index != null)
                // Cursive propagation adds the parent's complete minor-axis
                // offset. HarfBuzz's pre-propagation vertical origin is
                // negative, so non-root chain members start at the negative
                // origin while the edge root retains Cangjie's public positive
                // origin convention.
                -vertical_x_offset + kerx_state_x_offset
            else
                vertical_x_offset + gpos_x_offset + kerx_state_x_offset +
                    zeroed_mark_x_offset + fallback_mark_offset.x
        else
            gpos_x_offset + kerx_state_x_offset + kern_x_offset + zeroed_mark_x_offset + fallback_mark_offset.x;
        const output_y_offset = if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (lookup_options.writing_mode.isVertical())
            vertical_y_offset +
                @as(f32, @floatFromInt(adjustment.y_placement + kerx_adjustment.y_offset)) * scale +
                attachment_cross_y + zeroed_mark_y_offset + fallback_mark_offset.y
        else
            @as(f32, @floatFromInt(adjustment.y_placement + kerx_adjustment.y_offset)) * scale +
                attachment_cross_y + zeroed_mark_y_offset + fallback_mark_offset.y;
        buffer.glyphs.appendAssumeCapacity(.{
            .glyph_id = output_glyph_id,
            .synthetic_glyph_id = synthetic_glyph_id,
            .codepoint = source_codepoint,
            .cluster = source_span.start,
            .source_byte_len = source_span.end - source_span.start,
            .flags = .{
                .unsafe_to_break_before = gpos_unsafe_glyphs.isUnsafeBefore(index) or
                    source_boundaries.isUnsafeBeforeByte(source_span.start),
            },
            .x_advance = if (visible_not_found_variation_selector) 0 else if (lookup_options.writing_mode.isVertical()) 0.0 else horizontal_advance,
            .y_advance = if (hide_default_ignorable or visible_not_found_variation_selector) 0 else if (lookup_options.writing_mode.isVertical()) vertical_advance else @as(f32, @floatFromInt(adjustment.y_advance)) * scale,
            .x_offset = output_x_offset,
            .y_offset = output_y_offset,
            .vertical = lookup_options.writing_mode.isVertical(),
        });
        if (lookup_options.writing_mode.isVertical() and active_kern != 0) if (previous_kern_output_index) |previous_output_index| {
            const kern_1 = active_kern >> 1;
            const kern_2 = active_kern - kern_1;
            buffer.glyphs.items[previous_output_index].y_advance += @as(f32, @floatFromInt(kern_1)) * scale;
            buffer.glyphs.items[buffer.glyphs.items.len - 1].y_advance += @as(f32, @floatFromInt(kern_2)) * scale;
            buffer.glyphs.items[buffer.glyphs.items.len - 1].y_offset += @as(f32, @floatFromInt(kern_2)) * scale;
        };
        try appendStchActionForOutput(
            buffer.allocator,
            stch_actions,
            stch_action,
            buffer.glyphs.items.len - segment_glyph_start,
        );
        if (needs_attachment_remapping and !hide_default_ignorable) {
            attachment_links.items[index] = attachmentLinkForKerxAdjustment(
                kerx_adjustment,
                adjustment,
            );
        }
        if (fallback_mark_enabled and !hide_default_ignorable and !visible_not_found_variation_selector and !unicode.isNonspacingMarkCodepoint(source_codepoint)) {
            fallback_mark_base = fallback_mark.baseForGlyph(font, glyph_id, source_span.end, output_y_offset, horizontal_advance, scale, shapingDirectionForGpos(lookup_options) == .ltr) catch null;
        }
        if (!kerx_skips_glyph) {
            previous_kern_glyph = glyph_id;
            previous_kern_output_index = buffer.glyphs.items.len - 1;
        }
    }
    if (shape_profile) |p| {
        p.position_loop_ns += shapeProfileElapsed(position_loop_start, profile_io);
        p.position_output_glyphs += buffer.glyphs.items.len - segment_glyph_start;
    }
    const has_kerx_attachments = (has_kerx_state_attachments and
        kerx_summary.has_cross_stream_adjustment) or
        adjustmentsHaveKerxMarkAttachments(kerx_adjustments.items);
    if (has_gpos_attachments or has_kerx_attachments) {
        const attachment_start = shapeProfileNow(shape_profile, profile_io);
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
        if (shape_profile) |p| p.position_attachment_ns += shapeProfileElapsed(attachment_start, profile_io);
    }
    if (stch_actions.items.len != 0) {
        const stch_start = shapeProfileNow(shape_profile, profile_io);
        try stch_feature.apply(
            buffer.allocator,
            &buffer.glyphs,
            stch_actions.items,
            segment_glyph_start,
            lookup_options.direction == .rtl,
            shape_in_native_direction and shapingDirectionForGpos(lookup_options) == .rtl,
            scale,
            font,
            metrics_cache,
            lookup_options.normalized_variation_coords,
        );
        if (shape_profile) |p| p.position_stch_ns += shapeProfileElapsed(stch_start, profile_io);
    }
    if (!lookup_options.writing_mode.isVertical()) {
        const tracking_start = shapeProfileNow(shape_profile, profile_io);
        if (try font.horizontalTrackingForShaping(buffer.allocator, font_size)) |tracking| {
            if (tracking != 0) {
                const tracking_advance = tracking * scale;
                for (buffer.glyphs.items[segment_glyph_start..]) |*glyph| {
                    glyph.x_advance += tracking_advance;
                }
            }
        }
        if (shape_profile) |p| p.position_tracking_ns += shapeProfileElapsed(tracking_start, profile_io);
    }
    if (shape_in_native_direction and shapingDirectionForGpos(lookup_options) == .rtl) {
        const reverse_start = shapeProfileNow(shape_profile, profile_io);
        std.mem.reverse(GlyphPosition, buffer.glyphs.items[segment_glyph_start..]);
        if (shape_profile) |p| p.position_reverse_ns += shapeProfileElapsed(reverse_start, profile_io);
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

// Keep the cache-contract branch out of the already-large shapeSegmentInto
// body. Besides reducing its frame/code growth, the dedicated section prevents
// this generic-script optimization from shifting Arabic and GPOS hot functions
// whose instruction-cache layout is performance-sensitive.
noinline fn applyGenericGsubAfterTableProof(
    font: *const Font,
    buffer: *LayoutBuffer,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) linksection(shaping_sections.isolated_hotpaths) !void {
    if (try font.applyGsubCachedLookupSelectionUsingGdefAfterRunProof(
        glyph_ids,
        buffer.allocator,
        options,
        gdef_metadata,
    )) {
        return;
    }
    try font.applyGsubWithOptionsUsingGdefAfterProof(
        glyph_ids,
        buffer.allocator,
        options,
        gdef_metadata,
    );
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
    const plan = if (gsub_after_proof and buffer.lookup_selection_cache != null)
        try buffer.lookup_selection_cache.?.gsubMergedFeatureLookupPlan(
            font,
            applications,
            options,
            gdef_metadata,
        )
    else
        try font.gsubMergedFeatureLookupPlanForShaping(
            buffer.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (!gsub_after_proof or buffer.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(buffer.allocator);
    };
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

fn arabicPresentationFallbackGlyph(
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    glyph_id: GlyphId,
    codepoint: u21,
    source: usize,
    source_features: []const u32,
) !?GlyphId {
    if (font.hasGsubTableForShaping()) return null;
    if (source >= source_features.len) return null;
    const fallback_codepoint = arabicPresentationFallbackCodepoint(codepoint, source_features[source]) orelse return null;
    const fallback_glyph = try glyphIndexWithOptionalCache(font, glyph_index_cache, fallback_codepoint);
    if (fallback_glyph == 0 or fallback_glyph == glyph_id) return null;
    return fallback_glyph;
}

fn arabicPresentationFallbackCodepoint(codepoint: u21, source_feature: u32) ?u21 {
    const bare_features = source_feature & ~gsub.source_feature_mask_marker;
    const fina_mask = gsub.sourceFeatureMaskForTag(unicode.tag("fina")).? & ~gsub.source_feature_mask_marker;
    const medi_mask = gsub.sourceFeatureMaskForTag(unicode.tag("medi")).? & ~gsub.source_feature_mask_marker;
    if ((bare_features & fina_mask) != 0) {
        return switch (codepoint) {
            0x0627 => 0xfe8e,
            0x06cc => 0xfbfd,
            else => null,
        };
    }
    if ((bare_features & medi_mask) != 0) {
        return switch (codepoint) {
            0x062a => 0xfe98,
            0x0644 => 0xfee0,
            0x0645 => 0xfee4,
            0x06cc => 0xfbff,
            else => null,
        };
    }
    return null;
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

test "Arabic presentation fallback maps retained positional cmap forms" {
    const fina_mask = gsub.sourceFeatureMaskForTag(unicode.tag("fina")).?;
    const medi_mask = gsub.sourceFeatureMaskForTag(unicode.tag("medi")).?;

    try std.testing.expectEqual(@as(?u21, 0xfe8e), arabicPresentationFallbackCodepoint(0x0627, fina_mask));
    try std.testing.expectEqual(@as(?u21, 0xfee0), arabicPresentationFallbackCodepoint(0x0644, medi_mask));
    try std.testing.expectEqual(@as(?u21, 0xfe98), arabicPresentationFallbackCodepoint(0x062a, medi_mask));
    try std.testing.expectEqual(@as(?u21, null), arabicPresentationFallbackCodepoint(0x0644, fina_mask));
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

fn runNeedsHangulDefaultDisabledCalt(codepoints: []const u21) bool {
    var has_hangul_jamo = false;
    for (codepoints) |codepoint| {
        if (isHangulJamoCodepoint(codepoint)) {
            has_hangul_jamo = true;
            continue;
        }
        if (isHangulSyllableCodepoint(codepoint)) {
            continue;
        }
        const script = unicode.scriptForCodepoint(codepoint);
        if (script != .common and script != .inherited and script != .unknown) return false;
    }
    return has_hangul_jamo;
}

fn isHangulCodepoint(codepoint: u21) bool {
    return isHangulJamoCodepoint(codepoint) or
        isHangulSyllableCodepoint(codepoint);
}

fn isHangulSyllableCodepoint(codepoint: u21) bool {
    return codepoint >= 0xac00 and codepoint <= 0xd7af;
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
        if (!unicode.isMongolianFreeVariationSelector(codepoint) or index == 0) continue;
        source_features[index] = source_features[index - 1];
    }
}

fn hasHangulJamo(codepoints: []const u21) bool {
    for (codepoints) |codepoint| {
        if (hangulJamoFeatureTag(codepoint) != null) return true;
    }
    return false;
}

fn markHangulJamoSourceFeatures(source_features: []u32, codepoints: []const u21) bool {
    @memset(source_features, 0);
    var any = false;
    var source: usize = 0;
    while (source < codepoints.len) {
        if (!isHangulLeadingJamo(codepoints[source]) or source + 1 >= codepoints.len or !isHangulVowelJamo(codepoints[source + 1])) {
            source += 1;
            continue;
        }
        source_features[source] = unicode.tag("ljmo");
        source_features[source + 1] = unicode.tag("vjmo");
        any = true;
        if (source + 2 < codepoints.len and isHangulTrailingJamo(codepoints[source + 2])) {
            source_features[source + 2] = unicode.tag("tjmo");
            source += 3;
        } else {
            source += 2;
        }
    }
    return any;
}

fn hangulJamoFeaturesCoverAllJamo(source_features: []const u32, codepoints: []const u21) bool {
    for (codepoints, source_features) |codepoint, feature| {
        if (hangulJamoFeatureTag(codepoint) != null and feature == 0) return false;
    }
    return true;
}

fn mergeHangulJamoClusters(clusters: []usize, sources: []const usize, codepoints: []const u21) void {
    var glyph_index: usize = 0;
    while (glyph_index < sources.len) {
        const source = sources[glyph_index];
        if (source >= codepoints.len or !isHangulLeadingJamo(codepoints[source])) {
            glyph_index += 1;
            continue;
        }
        var end = glyph_index + 1;
        var saw_vowel = false;
        while (end < sources.len) : (end += 1) {
            const next_source = sources[end];
            if (next_source >= codepoints.len) break;
            const codepoint = codepoints[next_source];
            if (!saw_vowel and isHangulVowelJamo(codepoint)) {
                saw_vowel = true;
                continue;
            }
            if (saw_vowel and isHangulTrailingJamo(codepoint)) continue;
            break;
        }
        if (saw_vowel) {
            shaping_metadata.mergeMonotoneClusters(clusters, glyph_index, end);
        }
        glyph_index = end;
    }
}

fn hangulFeatureOverridesWithJamoFeatures(out: []unicode.FeatureOverride, overrides: []const unicode.FeatureOverride) ?[]const unicode.FeatureOverride {
    if (out.len < overrides.len + 3) return null;
    var count: usize = 0;
    var has_ljmo = false;
    var has_vjmo = false;
    var has_tjmo = false;
    for (overrides) |override| {
        if (override.tag == unicode.tag("ljmo")) has_ljmo = true;
        if (override.tag == unicode.tag("vjmo")) has_vjmo = true;
        if (override.tag == unicode.tag("tjmo")) has_tjmo = true;
        out[count] = override;
        count += 1;
    }
    if (!has_ljmo) {
        out[count] = .{ .tag = unicode.tag("ljmo"), .enabled = true };
        count += 1;
    }
    if (!has_vjmo) {
        out[count] = .{ .tag = unicode.tag("vjmo"), .enabled = true };
        count += 1;
    }
    if (!has_tjmo) {
        out[count] = .{ .tag = unicode.tag("tjmo"), .enabled = true };
        count += 1;
    }
    return out[0..count];
}

fn hangulJamoFeatureTag(codepoint: u21) ?u32 {
    if (isHangulLeadingJamo(codepoint)) return unicode.tag("ljmo");
    if (isHangulVowelJamo(codepoint)) return unicode.tag("vjmo");
    if (isHangulTrailingJamo(codepoint)) return unicode.tag("tjmo");
    return null;
}

fn isHangulLeadingJamo(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x115f) or
        (codepoint >= 0xa960 and codepoint <= 0xa97f);
}

fn isHangulVowelJamo(codepoint: u21) bool {
    return (codepoint >= 0x1160 and codepoint <= 0x11a7) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7c7);
}

fn isHangulTrailingJamo(codepoint: u21) bool {
    return (codepoint >= 0x11a8 and codepoint <= 0x11ff) or
        (codepoint >= 0xd7cb and codepoint <= 0xd7fb);
}

fn shapingFeatureEnabled(feature: u32, overrides: []const unicode.FeatureOverride, default_enabled: bool) bool {
    for (overrides) |override| {
        if (override.tag == feature) return override.enabled;
    }
    return default_enabled;
}

fn randomFeatureApplication(overrides: []const unicode.FeatureOverride) ?gsub.FeatureApplication {
    for (overrides) |override| {
        if (override.tag != unicode.tag("rand")) continue;
        if (!override.enabled) return null;
        return .{
            .tag = override.tag,
            .value = override.effectiveValue(),
        };
    }
    return .{
        .tag = unicode.tag("rand"),
        .value = gsub.random_feature_value,
    };
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
    return feature != unicode.tag("rand") and
        feature != unicode.tag("stch") and
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

fn needsValueAwareGsubSelection(
    font: *const Font,
    features: []const unicode.FeatureOverride,
    lookup_accelerators: ?[]const gsub.LookupAccelerator,
    table_proved: bool,
) bool {
    var rand_disabled = false;
    for (features) |feature| {
        if (feature.effectiveValue() > 1) return true;
        if (feature.tag == unicode.tag("rand") and !feature.enabled) rand_disabled = true;
    }
    if (rand_disabled) return false;
    if (table_proved) {
        if (lookup_accelerators) |accelerators| {
            if (font.hasGsubRandomFeatureWithAcceleratorsForShaping(accelerators)) |has_random| {
                return has_random;
            }
        }
    }
    return font.hasGsubFeatureForShaping(unicode.tag("rand")) catch false;
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
        .mark => .{
            .kind = .mark,
            .parent_index = adjustment.attachment_parent_index,
            .cross_axis_resolved = true,
        },
        .cursive => .{ .kind = .cursive, .parent_index = adjustment.attachment_parent_index },
    };
}

fn adjustmentsHaveAttachments(adjustments: []const gpos.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none) return true;
    }
    return false;
}

fn adjustmentsHaveKerxAttachments(adjustments: []const aat_kerx.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none and adjustment.attachment_parent_index != null) return true;
    }
    return false;
}

fn adjustmentsHaveKerxMarkAttachments(adjustments: []const aat_kerx.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type == .mark and adjustment.attachment_parent_index != null) return true;
    }
    return false;
}

fn attachmentLinkForKerxAdjustment(kerx_adjustment: aat_kerx.Adjustment, gpos_adjustment: gpos.Adjustment) attachment.Link {
    return switch (kerx_adjustment.attachment_type) {
        .none => attachmentLinkForAdjustment(gpos_adjustment),
        .mark => .{ .kind = .mark, .parent_index = kerx_adjustment.attachment_parent_index },
        .cursive => .{ .kind = .cursive, .parent_index = kerx_adjustment.attachment_parent_index },
    };
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
    return .{
        .kind = link.kind,
        .parent_index = output_parent,
        .cross_axis_resolved = link.cross_axis_resolved,
    };
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

const recordStchActions = stch_feature.recordSubstitutions;
const appendStchActionForOutput = stch_feature.appendOutput;

test "ordinary shaping clears and leaves stch sidecar empty" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    // Model reuse after a prior stretch-bearing segment. ShapeScratch.clear
    // must drop that old length, and the ordinary output loop must not regrow
    // the sidecar with `.none` entries.
    try buffer.shape_scratch.stch_actions.append(
        std.testing.allocator,
        @intFromEnum(ligature_provenance.StchAction.fixed),
    );
    const run = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.stch_actions.items.len);
}

fn shapingDirectionForGpos(options: LookupOptions) TextDirection {
    if (shouldShapeInNativeDirection(options)) {
        const native = nativeHorizontalDirection(options) orelse return options.direction;
        return textDirectionFromBidiClass(native);
    }
    return options.direction;
}

fn kerxMachineSkipsGlyph(glyph_class: GlyphClass, has_gdef_glyph_classes: bool, source_codepoint: u21, was_substituted: bool) bool {
    if (glyph_class == .mark) return true;
    // HarfBuzz synthesizes a mark class from Unicode Mn only when the font has
    // no GDEF GlyphClassDef. Default-ignorables stay base-like during that
    // synthesis but remain transparent to positioning unless GSUB consumed
    // and replaced them.
    if (!has_gdef_glyph_classes and
        unicode.isNonspacingMarkCodepoint(source_codepoint) and
        !unicode.isDefaultIgnorableForShaping(source_codepoint))
    {
        return true;
    }
    return unicode.isDefaultIgnorableForShaping(source_codepoint) and !was_substituted;
}

test "kerx machine skips GDEF marks and untouched Unicode controls" {
    try std.testing.expect(kerxMachineSkipsGlyph(.mark, true, 'A', false));
    try std.testing.expect(kerxMachineSkipsGlyph(.unclassified, false, 0x0301, false));
    try std.testing.expect(!kerxMachineSkipsGlyph(.unclassified, true, 0x0301, false));
    try std.testing.expect(kerxMachineSkipsGlyph(.unclassified, false, 0x200d, false));
    try std.testing.expect(!kerxMachineSkipsGlyph(.unclassified, false, 0x200d, true));
    try std.testing.expect(!kerxMachineSkipsGlyph(.base, true, 'A', false));
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
    const glyph = try glyphIndexWithOptionalCache(font, cache, codepoint);
    if (glyph != 0) return glyph;

    // Space fallback is needed only after the primary cmap proved this Unicode
    // space missing. Resolve U+0020 through the same optional cache rather than
    // bypassing it through Font.glyphIndex: ordinary spaces dominate prose and
    // must not revalidate a borrowed cmap table once per occurrence.
    if (space_fallback.mayUseSpaceGlyphFallback(codepoint)) {
        const space_glyph = try glyphIndexWithOptionalCache(font, cache, ' ');
        if (space_glyph != 0) return space_glyph;
    }
    return (try unicode_glyph_fallback.glyphForMissingCodepoint(font, codepoint)) orelse glyph;
}

test "mapped spaces use the glyph index cache before fallback" {
    const test_font = @import("test_font.zig");
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
    const test_font = @import("test_font.zig");
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

test "remove-default-ignorables deletes the font's fallback space glyph" {
    const test_font = @import("test_font.zig");
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
    const default_key = ShapedRunCache.key(cascade, text, 20, .{});
    const removed_key = ShapedRunCache.key(cascade, text, 20, .{ .remove_default_ignorables = true });
    try std.testing.expect(!shapePlanKeysEqual(default_key.plan, removed_key.plan));
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

test "vertical shaping centers glyph extents when vmtx is absent" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const bounds = try font.glyphBounds(1);
    const font_height = @as(i32, font.ascender) - @as(i32, font.descender);
    const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
    const expected_origin = @as(i32, bounds.y_max) + @divFloor(font_height - glyph_height, 2);
    try std.testing.expectEqual(
        expected_origin,
        try font.shapingVerticalOriginYAtCoords(1, &.{}),
    );

    const font_size: f32 = @floatFromInt(font.units_per_em);
    const vertical = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "A",
        font_size,
        .{ .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    try std.testing.expectEqual(@as(usize, 1), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatFromInt(expected_origin)),
        vertical.glyphs[0].y_offset,
        0.001,
    );
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
