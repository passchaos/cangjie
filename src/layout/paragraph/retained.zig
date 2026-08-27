//! Width-independent paragraph ownership and repeatable visual reflow.

const std = @import("std");

const font_fallback = @import("../../shaping/fallback/font/root.zig");
const glyph_position = @import("../glyph_position.zig");
const inline_object = @import("../inline_object/root.zig");
const paragraph_options = @import("options.zig");
const vertical_columns = @import("vertical_columns.zig");
const content_widths = @import("content_widths.zig");
const line_break_opportunity = @import("../line_break/opportunity.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const paragraph_reflow = @import("../line_break/reflow/root.zig");
const breaker = @import("retained/breaker.zig");
const presentation = @import("retained/presentation.zig");
const reshape = @import("reshape.zig");
const shaping_output = @import("../../shaping/context/output.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

pub const Breaker = breaker.Breaker;
pub const BreakerInput = breaker.Input;
pub const BreakerStep = breaker.Step;
pub const BreakerCheckpoint = breaker.Checkpoint;
pub const BreakerHeightExceeded = breaker.HeightExceeded;

/// Width-independent, owning paragraph content.
///
/// Source text, pristine shaped output, and Unicode boundary analysis are
/// retained once. Font pointers inside `runs` and optional segmentation or
/// hyphenation dictionaries are borrowed and must outlive this value and every
/// reflow view.
pub const ShapedParagraph = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const glyph_position.GlyphPosition,
    runs: []const run_types.CascadeRun,
    normalized_variation_coords: []const f32,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const line_break_opportunity.Opportunity,
    inline_object_indexes: []const usize,
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../text/hyphenation/root.zig").Dictionary,
    default_metrics: paragraph_reflow.BaselineMetrics,
    shape_key: shaping_plan.ShapePlanKey,
    inferred_script_tag: unicode.OpenTypeScriptTag,
    inferred_language_tag: unicode.OpenTypeLanguageTag,
    needs_bidi_reorder: bool,
    pure_rtl_lines: bool,
    pure_rtl_may_have_mirroring: bool,
    simple_reflow: bool,
    /// Width-independent UAX #9 paragraph state retained from preparation.
    /// Line-dependent L1/L2 work still runs after each set of breaks, but UTF-8
    /// decoding and paragraph-level resolution are not repeated per reflow.
    bidi_paragraph: ?unicode.BidiParagraph,
    /// Borrowed shaping recipe for line-local source transformations.
    ///
    /// The font-pointer slice is owned by this paragraph, while the referenced
    /// parsed fonts must outlive it just like the pointers already in `runs`.
    cascade_fonts: []const *const @import("../../font.zig").Font,
    font_size: f32,

    pub fn deinit(self: *ShapedParagraph) void {
        if (self.bidi_paragraph) |*paragraph| paragraph.deinit();
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.inline_object_indexes);
        self.allocator.free(self.grapheme_clusters);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        self.allocator.free(self.normalized_variation_coords);
        self.allocator.free(self.cascade_fonts);
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn shapedText(self: *const ShapedParagraph) run_types.ShapedText {
        return .{
            .glyphs = self.glyphs,
            .runs = self.runs,
            .normalized_variation_coords = self.normalized_variation_coords,
        };
    }

    /// Calculate intrinsic inline-size bounds without another shaping pass.
    ///
    /// Geometry-only options such as width, alignment, line limits,
    /// exclusions, and out-of-flow placements do not affect these bounds.
    pub fn contentWidths(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) !paragraph_types.ContentWidths {
        try paragraph_options.validateForText(self.text, options);
        try inline_object.validate(self.text, options.inline_objects);
        if (options.word_break_dictionary != self.word_break_dictionary or
            options.hyphenation.dictionary != self.hyphenation_dictionary or
            !inline_object.indexesMatch(
                self.inline_object_indexes,
                options.inline_objects,
            ) or
            !paragraph_options.matchesShapeKey(
                self.text,
                options,
                self.shape_key,
            ))
        {
            return error.ParagraphShapingOptionsChanged;
        }
        if (options.writing_mode.isVertical()) {
            return vertical_columns.contentWidths(
                self.allocator,
                self.text,
                self.glyphs,
                self.runs,
                self.normalized_variation_coords,
                self.grapheme_clusters,
                self.line_breaks,
                options,
            );
        }
        return content_widths.calculate(
            self.allocator,
            self.text,
            self.glyphs,
            self.runs,
            self.grapheme_clusters,
            self.line_breaks,
            options,
        );
    }

    /// Rebuild visual lines without repeating whole-paragraph shaping or
    /// Unicode analysis.
    ///
    /// Justified lines may perform bounded JSTF shrink/extension reshaping, and
    /// Arabic lines may additionally insert U+0640 at retained safe boundaries.
    /// Returned slices borrow `reflow` until its next layout call. Separate
    /// buffers may reflow the same immutable paragraph concurrently.
    pub fn layout(
        self: *const ShapedParagraph,
        reflow: *ReflowBuffer,
        options: paragraph_options.Options,
    ) !paragraph_types.ParagraphLayout {
        try self.validateLayoutOptions(options);
        try reflow.restore(self);
        errdefer reflow.buffer.clear();
        if (self.simple_reflow and
            try paragraph_reflow.tryBuildSimpleRetained(
                &reflow.buffer,
                self.text,
                options,
                self.default_metrics,
                self.grapheme_clusters,
                self.line_breaks,
            ))
        {
            try presentation.applySimpleRetained(
                &reflow.buffer,
                options,
                self.needs_bidi_reorder,
                self.pure_rtl_lines,
                self.pure_rtl_may_have_mirroring,
                self.bidi_paragraph,
            );
            return reflow.buffer.paragraphLayout(options.writing_mode);
        }
        const recipe = reshape.Uniform{
            .cascade = font_fallback.Cascade.init(self.cascade_fonts),
            .text = self.text,
            .font_size = self.font_size,
            .options = options,
        };
        try paragraph_reflow.buildWithJstfShrinkage(
            &reflow.buffer,
            self.text,
            options,
            self.default_metrics,
            self.grapheme_clusters,
            self.line_breaks,
            self.word_break_dictionary,
            self.hyphenation_dictionary,
            recipe,
        );
        try presentation.apply(
            &reflow.buffer,
            self.text,
            options,
            recipe,
            self.needs_bidi_reorder,
            self.pure_rtl_lines,
            self.bidi_paragraph,
        );
        return reflow.buffer.paragraphLayout(options.writing_mode);
    }

    /// Start caller-driven, resumable greedy line/column breaking.
    ///
    /// The returned breaker borrows this paragraph and `reflow`; both must
    /// outlive it and neither may be reused until the breaker is deinitialized.
    pub fn breakLines(
        self: *const ShapedParagraph,
        reflow: *ReflowBuffer,
        options: paragraph_options.Options,
    ) !breaker.Breaker {
        try self.validateLayoutOptions(options);
        if (options.line_break_strategy != .greedy) {
            return error.ResumableBreakerRequiresGreedyStrategy;
        }
        try reflow.restore(self);
        errdefer reflow.buffer.clear();
        return breaker.Breaker.create(.{
            .allocator = reflow.buffer.allocator,
            .buffer = &reflow.buffer,
            .buffer_generation = &reflow.generation,
            .session_generation = reflow.generation,
            .text = self.text,
            .options = options,
            .default_metrics = self.default_metrics,
            .grapheme_clusters = self.grapheme_clusters,
            .line_breaks = self.line_breaks,
            .word_break_dictionary = self.word_break_dictionary,
            .hyphenation_dictionary = self.hyphenation_dictionary,
            .needs_bidi_reorder = self.needs_bidi_reorder,
            .pure_rtl_lines = self.pure_rtl_lines,
            .bidi_paragraph = self.bidi_paragraph,
            .cascade_fonts = self.cascade_fonts,
            .font_size = self.font_size,
        });
    }

    fn validateLayoutOptions(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) !void {
        if (self.simple_reflow and simpleOptionsNeedNoDeepValidation(options))
            try validateSimpleOptions(options)
        else
            try paragraph_options.validateForText(self.text, options);
        // Preparation already proved that immutable text without markers has
        // an empty object list. Avoid rescanning the full source on the common
        // object-free reflow; non-empty geometry remains fully validated.
        try inline_object.validateRetained(
            self.inline_object_indexes,
            options.inline_objects,
        );
        if (options.word_break_dictionary != self.word_break_dictionary or
            options.hyphenation.dictionary != self.hyphenation_dictionary or
            !self.matchesShapeOptions(options))
        {
            return error.ParagraphShapingOptionsChanged;
        }
    }

    fn matchesShapeOptions(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) bool {
        const shape_options = paragraph_options.shapeOptions(options);
        // Resolve optional overrides against inference retained at preparation
        // time. This preserves ShapePlanKey equality while avoiding a fresh
        // script/language scan over immutable text on every reflow.
        return (shape_options.script_tag orelse self.inferred_script_tag) ==
            self.shape_key.script_tag and
            (shape_options.language_tag orelse self.inferred_language_tag) ==
                self.shape_key.language_tag and
            shape_options.direction == self.shape_key.direction and
            shape_options.reorder_bidi == self.shape_key.reorder_bidi and
            shape_options.native_direction_shaping ==
                self.shape_key.native_direction_shaping and
            shape_options.writing_mode == self.shape_key.writing_mode and
            shape_options.text_orientation == self.shape_key.text_orientation and
            shape_options.script_position == self.shape_key.script_position and
            (if (shape_options.features.len == 0)
                self.shape_key.feature_hash == 0
            else
                shaping_plan.featureOverridesHash(shape_options.features) ==
                    self.shape_key.feature_hash) and
            (if (shape_options.normalized_variation_coords.len == 0)
                self.shape_key.variation_hash == 0
            else
                shaping_plan.normalizedVariationCoordsHash(
                    shape_options.normalized_variation_coords,
                ) == self.shape_key.variation_hash) and
            self.shape_key.context_hash == 0 and
            shape_options.beginning_of_text ==
                self.shape_key.beginning_of_text and
            shape_options.end_of_text == self.shape_key.end_of_text and
            shape_options.not_found_variation_selector_glyph ==
                self.shape_key.not_found_variation_selector_glyph and
            shape_options.remove_default_ignorables ==
                self.shape_key.remove_default_ignorables and
            shape_options.cluster_level == self.shape_key.cluster_level;
    }
};

fn simpleOptionsNeedNoDeepValidation(options: paragraph_options.Options) bool {
    return options.line_break_policy_ranges.len == 0 and
        options.exclusions.len == 0 and
        options.line_regions.len == 0 and
        options.out_of_flow_placements.len == 0 and
        options.tab_stops.len == 0 and
        options.features.len == 0 and
        options.normalized_variation_coords.len == 0 and
        options.hyphenation.character == null;
}

/// Validate the scalar options used by the allocation-free retained path. The
/// slice-backed policies are known empty by `simpleOptionsNeedNoDeepValidation`
/// and were already validated when the paragraph was prepared.
fn validateSimpleOptions(options: paragraph_options.Options) !void {
    if (std.math.isNan(options.max_width) or
        (options.line_height != null and
            (!std.math.isFinite(options.line_height.?) or
                options.line_height.? <= 0)) or
        !std.math.isFinite(options.letter_spacing) or
        !std.math.isFinite(options.word_spacing) or
        !std.math.isFinite(options.first_line_indent) or
        !std.math.isFinite(options.paragraph_spacing) or
        (options.max_block_size != null and
            (!std.math.isFinite(options.max_block_size.?) or
                options.max_block_size.? < 0)) or
        !std.math.isFinite(options.punctuation.end_hanging_fraction) or
        options.punctuation.end_hanging_fraction < 0 or
        options.punctuation.end_hanging_fraction > 1 or
        !std.math.isFinite(options.punctuation.max_compression_fraction) or
        options.punctuation.max_compression_fraction < 0 or
        options.punctuation.max_compression_fraction > 1)
    {
        return error.InvalidParagraphOptions;
    }
}

/// Reusable output storage for reflowing a retained paragraph.
pub const ReflowBuffer = struct {
    buffer: shaping_output.Buffer,
    generation: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) ReflowBuffer {
        return .{ .buffer = shaping_output.Buffer.init(allocator) };
    }

    pub fn deinit(self: *ReflowBuffer) void {
        self.buffer.deinit();
        self.* = undefined;
    }

    fn restore(
        self: *ReflowBuffer,
        paragraph: *const ShapedParagraph,
    ) !void {
        self.bumpGeneration();
        self.buffer.clear();
        // Reserve all three immutable arrays before copying. A reflow buffer
        // retains these capacities, so the steady-state restore becomes only
        // fixed-size memory copies rather than three allocator entry points.
        try self.buffer.variation_coords.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.normalized_variation_coords.len,
        );
        try self.buffer.glyphs.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.glyphs.len,
        );
        try self.buffer.runs.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.runs.len,
        );
        errdefer self.buffer.clear();
        self.buffer.variation_coords.appendSliceAssumeCapacity(
            paragraph.normalized_variation_coords,
        );
        self.buffer.glyphs.appendSliceAssumeCapacity(paragraph.glyphs);
        self.buffer.runs.appendSliceAssumeCapacity(paragraph.runs);
    }

    fn bumpGeneration(self: *ReflowBuffer) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }
};
