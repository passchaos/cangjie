//! Width-independent paragraph ownership and repeatable visual reflow.

const std = @import("std");

const bidi_reorder = @import("../bidi/reorder/root.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const glyph_position = @import("../glyph_position.zig");
const inline_object = @import("../inline_object/root.zig");
const font_expansion = @import("../justification/font_expansion.zig");
const jstf_justification = @import("../justification/jstf.zig");
const jstf_extender = @import("../justification/jstf/extender.zig");
const kashida_justification = @import("../justification/kashida.zig");
const paragraph_options = @import("options.zig");
const line_break_opportunity = @import("../line_break/opportunity.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const paragraph_reflow = @import("../line_break/reflow/root.zig");
const reshape = @import("reshape.zig");
const punctuation_compression = @import("../punctuation/compression.zig");
const punctuation_hanging = @import("../punctuation/hanging.zig");
const shaping_output = @import("../../shaping/context/output.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

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
        try paragraph_options.validate(options);
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
        try jstf_justification.apply(
            &reflow.buffer,
            options,
            recipe,
        );
        try jstf_extender.apply(
            &reflow.buffer,
            self.text,
            options,
            recipe,
        );
        try font_expansion.apply(
            &reflow.buffer,
            options,
            recipe,
        );
        try kashida_justification.apply(
            &reflow.buffer,
            self.text,
            options,
            recipe,
        );
        paragraph_reflow.applyPendingJustification(&reflow.buffer);
        try punctuation_compression.apply(&reflow.buffer, options);
        if (self.needs_bidi_reorder) {
            try bidi_reorder.applyLines(
                &reflow.buffer,
                self.text,
                options.direction == .rtl,
            );
        }
        punctuation_hanging.apply(&reflow.buffer, options);
        try inline_object.position(
            &reflow.buffer,
            options.inline_objects,
            options.out_of_flow_placements,
        );
        return reflow.buffer.paragraphLayout();
    }
};

/// Reusable output storage for reflowing a retained paragraph.
pub const ReflowBuffer = struct {
    buffer: shaping_output.Buffer,

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
};
