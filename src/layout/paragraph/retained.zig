//! Width-independent paragraph ownership and repeatable visual reflow.

const std = @import("std");

const font_fallback = @import("../../shaping/fallback/font/root.zig");
const glyph_position = @import("../glyph_position.zig");
const inline_object = @import("../inline_object/root.zig");
const paragraph_options = @import("options.zig");
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
    needs_bidi_reorder: bool,
    /// Borrowed shaping recipe for line-local source transformations.
    ///
    /// The font-pointer slice is owned by this paragraph, while the referenced
    /// parsed fonts must outlive it just like the pointers already in `runs`.
    cascade_fonts: []const *const @import("../../font.zig").Font,
    font_size: f32,

    pub fn deinit(self: *ShapedParagraph) void {
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
        );
        return reflow.buffer.paragraphLayout();
    }

    /// Start caller-driven, resumable greedy line breaking.
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
            .cascade_fonts = self.cascade_fonts,
            .font_size = self.font_size,
        });
    }

    fn validateLayoutOptions(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) !void {
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
    }
};

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
        try self.buffer.variation_coords.appendSlice(
            self.buffer.allocator,
            paragraph.normalized_variation_coords,
        );
        try self.buffer.glyphs.appendSlice(
            self.buffer.allocator,
            paragraph.glyphs,
        );
        errdefer self.buffer.clear();
        try self.buffer.runs.appendSlice(
            self.buffer.allocator,
            paragraph.runs,
        );
    }

    fn bumpGeneration(self: *ReflowBuffer) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }
};
