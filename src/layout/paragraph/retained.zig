//! Width-independent shaped paragraph ownership and repeatable visual reflow.

const std = @import("std");

const bidi_reorder = @import("../bidi/reorder/root.zig");
const glyph_position = @import("../glyph_position.zig");
const inline_object = @import("../inline_object/root.zig");
const paragraph_options = @import("options.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const paragraph_reflow = @import("../line_break/reflow/root.zig");
const shaping_output = @import("../../shaping/context/output.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

/// Width-independent, owning paragraph content.
///
/// Source text, pristine shaped output, and Unicode boundary analysis are
/// retained once. Font pointers inside `runs`, and an optional word-breaking
/// dictionary, are borrowed and must outlive this value and every reflow view.
pub const ShapedParagraph = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const glyph_position.GlyphPosition,
    runs: []const run_types.CascadeRun,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const unicode.LineBreak,
    inline_object_indexes: []const usize,
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
    default_metrics: paragraph_reflow.BaselineMetrics,
    shape_key: shaping_plan.ShapePlanKey,
    needs_bidi_reorder: bool,

    pub fn deinit(self: *ShapedParagraph) void {
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.inline_object_indexes);
        self.allocator.free(self.grapheme_clusters);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn shapedText(self: *const ShapedParagraph) run_types.ShapedText {
        return .{ .glyphs = self.glyphs, .runs = self.runs };
    }

    /// Rebuild visual lines without repeating GSUB/GPOS or Unicode analysis.
    ///
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
        try paragraph_reflow.build(
            &reflow.buffer,
            self.text,
            options,
            self.default_metrics,
            self.grapheme_clusters,
            self.line_breaks,
            self.word_break_dictionary,
        );
        if (self.needs_bidi_reorder) {
            try bidi_reorder.applyLines(
                &reflow.buffer,
                self.text,
                options.direction == .rtl,
            );
        }
        try inline_object.position(
            &reflow.buffer,
            options.inline_objects,
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
