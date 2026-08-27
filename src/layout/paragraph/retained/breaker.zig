//! Resumable greedy line breaking over a retained shaped paragraph.
//!
//! The breaker borrows immutable paragraph analysis and one `ReflowBuffer`.
//! It owns width-dependent analysis tailoring, caller-supplied line/column
//! regions, and its logical cursor. Horizontal lines retain their zero-copy
//! forward state machine. Vertical columns transactionally rebuild from a
//! private pristine snapshot when a caller changes the next region, then expose
//! only the committed prefix. Final justification, bidi, punctuation, and
//! object placement run exactly once when all fragments have been committed.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const glyph_position = @import("../../glyph_position.zig");
const inline_object = @import("../../inline_object/root.zig");
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const paragraph_reflow = @import("../../line_break/reflow/root.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const run_types = @import("../../types/runs.zig");
const font_fallback = @import("../../../shaping/fallback/font/root.zig");
const shaping_output = @import("../../../shaping/context/output.zig");
const segmentation = @import("../../../text/segmentation/root.zig");
const unicode = @import("../../../unicode.zig");
const hyphenation = @import("../../../text/hyphenation/root.zig");
const line_regions = @import("../line_regions.zig");
const paragraph_options = @import("../options.zig");
const presentation = @import("presentation.zig");
const reshape = @import("../reshape.zig");
const vertical_columns = @import("../vertical_columns.zig");

/// Per-fragment geometry supplied while advancing a retained breaker.
pub const Input = struct {
    /// Replace or append the explicit region for the next visual line.
    ///
    /// Null preserves a region already present in the initial paragraph
    /// options and otherwise uses the natural indent/exclusion container.
    region: ?line_regions.Region = null,
    /// Maximum permitted physical height for the next line/column.
    ///
    /// When the selected line exceeds this value the breaker rolls back the
    /// attempted line and returns `.height_exceeded`. The caller can then move
    /// the same logical line to a new region and resume.
    max_height: ?f32 = null,
};

pub const HeightExceeded = struct {
    line_index: usize,
    required_height: f32,
    byte_start: usize,
    byte_len: usize,
    region_x: f32,
    region_y: f32,
    region_width: f32,
};

pub const Step = union(enum) {
    /// One logical line/column was committed. The record is a value snapshot;
    /// final presentation may later adjust its geometry and glyph/run indexes.
    line: paragraph_types.ParagraphLine,
    /// The attempted line exceeded `Input.max_height` and was not committed.
    height_exceeded: HeightExceeded,
    /// Every line and presentation transform is complete.
    complete: paragraph_types.ParagraphLayout,
};

/// Explicitly owned rollback point for a `Breaker`.
///
/// Saving is intentionally not implicit: it copies mutable reflow storage so
/// normal forward-only pagination remains allocation-free after `begin`.
pub const Checkpoint = struct {
    allocator: std.mem.Allocator,
    buffer_identity: usize,
    session_generation: u64,
    greedy: ?paragraph_reflow.GreedyState.Checkpoint,
    glyphs: []glyph_position.GlyphPosition,
    runs: []run_types.CascadeRun,
    variation_coords: []f32,
    lines: []paragraph_types.ParagraphLine,
    regions: []line_regions.Region,
    committed_columns: usize,
    vertical_complete_ready: bool,

    pub fn deinit(self: *Checkpoint) void {
        self.allocator.free(self.regions);
        self.allocator.free(self.lines);
        self.allocator.free(self.variation_coords);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        if (self.greedy) |*greedy| greedy.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const Init = struct {
    allocator: std.mem.Allocator,
    buffer: *shaping_output.Buffer,
    buffer_generation: *u64,
    session_generation: u64,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: paragraph_reflow.BaselineMetrics,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const line_break_opportunity.Opportunity,
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const hyphenation.Dictionary,
    needs_bidi_reorder: bool,
    pure_rtl_lines: bool,
    bidi_paragraph: ?unicode.BidiParagraph,
    cascade_fonts: []const *const font_mod.Font,
    font_size: f32,
};

/// Concrete, caller-driven retained line breaker.
pub const Breaker = struct {
    allocator: std.mem.Allocator,
    buffer: *shaping_output.Buffer,
    buffer_generation: *u64,
    session_generation: u64,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: paragraph_reflow.BaselineMetrics,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const line_break_opportunity.Opportunity,
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const hyphenation.Dictionary,
    needs_bidi_reorder: bool,
    pure_rtl_lines: bool,
    bidi_paragraph: ?unicode.BidiParagraph,
    cascade_fonts: []const *const font_mod.Font,
    font_size: f32,
    regions: std.ArrayList(line_regions.Region) = .empty,
    greedy: paragraph_reflow.GreedyState,
    vertical_glyphs: []glyph_position.GlyphPosition = &.{},
    vertical_runs: []run_types.CascadeRun = &.{},
    vertical_variation_coords: []f32 = &.{},
    committed_columns: usize = 0,
    vertical_complete_ready: bool = false,
    finished: bool = false,
    failed: bool = false,

    pub fn create(init: Init) !Breaker {
        if (init.options.line_break_strategy != .greedy) {
            return error.ResumableBreakerRequiresGreedyStrategy;
        }
        var self = Breaker{
            .allocator = init.allocator,
            .buffer = init.buffer,
            .buffer_generation = init.buffer_generation,
            .session_generation = init.session_generation,
            .text = init.text,
            .options = init.options,
            .default_metrics = init.default_metrics,
            .grapheme_clusters = init.grapheme_clusters,
            .line_breaks = init.line_breaks,
            .word_break_dictionary = init.word_break_dictionary,
            .hyphenation_dictionary = init.hyphenation_dictionary,
            .needs_bidi_reorder = init.needs_bidi_reorder,
            .pure_rtl_lines = init.pure_rtl_lines,
            .bidi_paragraph = init.bidi_paragraph,
            .cascade_fonts = init.cascade_fonts,
            .font_size = init.font_size,
            .greedy = paragraph_reflow.GreedyState.init(init.allocator),
        };
        errdefer self.deinit();
        try self.regions.appendSlice(
            self.allocator,
            init.options.line_regions,
        );
        self.refreshOptions();
        if (self.options.writing_mode.isVertical()) {
            self.vertical_glyphs = try self.allocator.dupe(
                glyph_position.GlyphPosition,
                self.buffer.glyphs.items,
            );
            self.vertical_runs = try self.allocator.dupe(
                run_types.CascadeRun,
                self.buffer.runs.items,
            );
            self.vertical_variation_coords = try self.allocator.dupe(
                f32,
                self.buffer.variation_coords.items,
            );
        } else {
            try paragraph_reflow.beginGreedy(
                &self.greedy,
                self.buffer,
                self.text,
                self.options,
                self.default_metrics,
                self.grapheme_clusters,
                self.line_breaks,
                self.word_break_dictionary,
                self.hyphenation_dictionary,
            );
        }
        return self;
    }

    pub fn deinit(self: *Breaker) void {
        self.allocator.free(self.vertical_variation_coords);
        self.allocator.free(self.vertical_runs);
        self.allocator.free(self.vertical_glyphs);
        self.greedy.deinit();
        self.regions.deinit(self.allocator);
        self.* = undefined;
    }

    /// Commit at most one visual line.
    pub fn advance(self: *Breaker, input: Input) !Step {
        try self.validateSession();
        if (self.finished) return error.ParagraphBreakerComplete;
        if (self.failed) return error.ParagraphBreakerFailed;
        if (self.options.writing_mode.isVertical()) {
            return self.advanceVertical(input);
        }
        if (self.greedy.complete) return try self.finish();

        if (input.max_height) |height| {
            if (!std.math.isFinite(height) or height <= 0) {
                return error.InvalidParagraphBreakerInput;
            }
        }
        if (input.region) |region| {
            try line_regions.validate(&.{region});
            const line_index = self.buffer.lines.items.len;
            if (line_index < self.regions.items.len) {
                self.regions.items[line_index] = region;
            } else if (line_index == self.regions.items.len) {
                try self.regions.append(self.allocator, region);
            } else {
                return error.InvalidParagraphBreakerState;
            }
            self.refreshOptions();
        }
        try paragraph_reflow.refreshGreedyRegion(
            &self.greedy,
            self.buffer,
            self.options,
        );
        var rollback: ?Checkpoint =
            if (input.max_height != null) try self.save() else null;
        defer if (rollback) |*checkpoint| checkpoint.deinit();
        const reshape_recipe = self.recipe();
        const previous_line_count = self.buffer.lines.items.len;
        const result = paragraph_reflow.advanceGreedy(
            &self.greedy,
            self.buffer,
            self.text,
            self.options,
            self.default_metrics,
            reshape_recipe,
        ) catch |err| {
            if (rollback) |*checkpoint| {
                // A max-height request already paid for a complete transaction
                // snapshot. Reuse it for every failed attempt, not only for the
                // expected height rejection.
                self.restore(checkpoint) catch {
                    self.failed = true;
                };
            } else {
                // The forward-only fast path deliberately does not copy the
                // paragraph before every line. An unexpected error can occur
                // after tabs, whitespace, or a JSTF candidate mutated output,
                // so continuing without an explicit checkpoint would be
                // unsound.
                self.failed = true;
            }
            return err;
        };
        switch (result) {
            .line => {
                if (self.buffer.lines.items.len != previous_line_count + 1) {
                    return error.InvalidParagraphBreakerState;
                }
                const line = self.buffer.lines.items[
                    self.buffer.lines.items.len - 1
                ];
                if (input.max_height) |limit| {
                    if (line.height > limit) {
                        const exceeded = HeightExceeded{
                            .line_index = previous_line_count,
                            .required_height = line.height,
                            .byte_start = line.byte_start,
                            .byte_len = line.byte_len,
                            .region_x = line.region_x,
                            .region_y = line.y,
                            .region_width = line.region_width,
                        };
                        try self.restore(&rollback.?);
                        return .{ .height_exceeded = exceeded };
                    }
                }
                return .{ .line = line };
            },
            .complete => return try self.finish(),
        }
    }

    /// Copy all mutable logical state for later retry.
    pub fn save(self: *const Breaker) !Checkpoint {
        try self.validateSession();
        if (self.finished) return error.ParagraphBreakerComplete;
        if (self.failed) return error.ParagraphBreakerFailed;
        var greedy_checkpoint: ?paragraph_reflow.GreedyState.Checkpoint =
            if (self.options.writing_mode.isVertical())
                null
            else
                try self.greedy.save();
        errdefer if (greedy_checkpoint) |*checkpoint| {
            checkpoint.deinit(self.allocator);
        };
        const glyphs = try self.allocator.dupe(
            glyph_position.GlyphPosition,
            self.buffer.glyphs.items,
        );
        errdefer self.allocator.free(glyphs);
        const runs = try self.allocator.dupe(
            run_types.CascadeRun,
            self.buffer.runs.items,
        );
        errdefer self.allocator.free(runs);
        const coords = try self.allocator.dupe(
            f32,
            self.buffer.variation_coords.items,
        );
        errdefer self.allocator.free(coords);
        const lines = try self.allocator.dupe(
            paragraph_types.ParagraphLine,
            self.buffer.lines.items,
        );
        errdefer self.allocator.free(lines);
        const region_copy = try self.allocator.dupe(
            line_regions.Region,
            self.regions.items,
        );
        return .{
            .allocator = self.allocator,
            .buffer_identity = @intFromPtr(self.buffer),
            .session_generation = self.session_generation,
            .greedy = greedy_checkpoint,
            .glyphs = glyphs,
            .runs = runs,
            .variation_coords = coords,
            .lines = lines,
            .regions = region_copy,
            .committed_columns = self.committed_columns,
            .vertical_complete_ready = self.vertical_complete_ready,
        };
    }

    /// Restore a checkpoint from this breaker's current session.
    pub fn restore(self: *Breaker, checkpoint: *const Checkpoint) !void {
        try self.validateSession();
        if (self.finished) return error.ParagraphBreakerComplete;
        if (checkpoint.buffer_identity != @intFromPtr(self.buffer) or
            checkpoint.session_generation != self.session_generation)
        {
            return error.StaleParagraphBreakerCheckpoint;
        }

        try self.buffer.glyphs.ensureTotalCapacity(
            self.allocator,
            checkpoint.glyphs.len,
        );
        try self.buffer.runs.ensureTotalCapacity(
            self.allocator,
            checkpoint.runs.len,
        );
        try self.buffer.variation_coords.ensureTotalCapacity(
            self.allocator,
            checkpoint.variation_coords.len,
        );
        try self.buffer.lines.ensureTotalCapacity(
            self.allocator,
            checkpoint.lines.len,
        );
        try self.regions.ensureTotalCapacity(
            self.allocator,
            checkpoint.regions.len,
        );
        if (checkpoint.greedy) |greedy| {
            try self.greedy.restore(greedy);
        }

        replaceList(
            glyph_position.GlyphPosition,
            &self.buffer.glyphs,
            checkpoint.glyphs,
        );
        replaceList(run_types.CascadeRun, &self.buffer.runs, checkpoint.runs);
        replaceList(
            f32,
            &self.buffer.variation_coords,
            checkpoint.variation_coords,
        );
        replaceList(
            paragraph_types.ParagraphLine,
            &self.buffer.lines,
            checkpoint.lines,
        );
        replaceList(line_regions.Region, &self.regions, checkpoint.regions);
        self.buffer.inline_objects.clearRetainingCapacity();
        self.refreshOptions();
        self.committed_columns = checkpoint.committed_columns;
        self.vertical_complete_ready = checkpoint.vertical_complete_ready;
        self.failed = false;
    }

    /// Logical source-order lines committed so far.
    ///
    /// This view is invalidated by `advance`, `restore`, completion, or any
    /// other operation that reuses the same `ReflowBuffer`.
    pub fn partialLayout(
        self: *const Breaker,
    ) !paragraph_types.ParagraphLayout {
        try self.validateSession();
        if (self.finished) return error.ParagraphBreakerComplete;
        if (self.failed) return error.ParagraphBreakerFailed;
        if (self.options.writing_mode.isVertical() and
            self.buffer.lines.items.len > self.committed_columns)
        {
            const all_lines = self.buffer.lines.items;
            self.buffer.lines.items = all_lines[0..self.committed_columns];
            defer self.buffer.lines.items = all_lines;
            return self.buffer.paragraphLayout(self.options.writing_mode);
        }
        return self.buffer.paragraphLayout(self.options.writing_mode);
    }

    fn finish(self: *Breaker) !Step {
        var checkpoint = try self.save();
        defer checkpoint.deinit();
        const reshape_recipe = self.recipe();
        presentation.apply(
            self.buffer,
            self.text,
            self.options,
            reshape_recipe,
            self.needs_bidi_reorder,
            self.pure_rtl_lines,
            self.bidi_paragraph,
        ) catch |err| {
            // Presentation mutates glyph/run arrays in several ordered stages.
            // Restore the complete logical break result so callers can inspect
            // or retry after a recoverable allocation failure.
            try self.restore(&checkpoint);
            return err;
        };
        self.finished = true;
        return .{
            .complete = self.buffer.paragraphLayout(
                self.options.writing_mode,
            ),
        };
    }

    fn advanceVertical(self: *Breaker, input: Input) !Step {
        if (self.vertical_complete_ready) return self.finish();
        try self.validateInput(input);
        try self.updateRegion(input.region, self.committed_columns);

        var rollback: ?Checkpoint =
            if (input.max_height != null) try self.save() else null;
        defer if (rollback) |*checkpoint| checkpoint.deinit();
        self.rebuildVertical() catch |err| {
            if (rollback) |*checkpoint| {
                self.restore(checkpoint) catch {
                    self.failed = true;
                };
            } else {
                self.failed = true;
            }
            return err;
        };
        if (self.committed_columns >= self.buffer.lines.items.len) {
            if (self.committed_columns == 0) {
                self.vertical_complete_ready = true;
                return self.finish();
            }
            self.failed = true;
            return error.InvalidParagraphBreakerState;
        }

        const line = self.buffer.lines.items[self.committed_columns];
        if (input.max_height) |limit| {
            if (line.height > limit) {
                const exceeded = HeightExceeded{
                    .line_index = self.committed_columns,
                    .required_height = line.height,
                    .byte_start = line.byte_start,
                    .byte_len = line.byte_len,
                    .region_x = line.region_x,
                    .region_y = line.region_inline_start,
                    .region_width = line.region_inline_size,
                };
                try self.restore(&rollback.?);
                return .{ .height_exceeded = exceeded };
            }
        }

        self.committed_columns += 1;
        if (self.committed_columns == self.buffer.lines.items.len) {
            self.vertical_complete_ready = true;
        }
        return .{ .line = line };
    }

    fn rebuildVertical(self: *Breaker) !void {
        try self.buffer.glyphs.ensureTotalCapacity(
            self.allocator,
            self.vertical_glyphs.len,
        );
        try self.buffer.runs.ensureTotalCapacity(
            self.allocator,
            self.vertical_runs.len,
        );
        try self.buffer.variation_coords.ensureTotalCapacity(
            self.allocator,
            self.vertical_variation_coords.len,
        );
        replaceList(
            glyph_position.GlyphPosition,
            &self.buffer.glyphs,
            self.vertical_glyphs,
        );
        replaceList(run_types.CascadeRun, &self.buffer.runs, self.vertical_runs);
        replaceList(
            f32,
            &self.buffer.variation_coords,
            self.vertical_variation_coords,
        );
        self.buffer.lines.clearRetainingCapacity();
        self.buffer.inline_objects.clearRetainingCapacity();
        try vertical_columns.build(
            self.buffer,
            self.text,
            self.options,
            self.default_metrics,
            self.grapheme_clusters,
            self.line_breaks,
            self.word_break_dictionary,
            self.hyphenation_dictionary,
            self.recipe(),
        );
    }

    fn validateInput(_: *Breaker, input: Input) !void {
        if (input.max_height) |height| {
            if (!std.math.isFinite(height) or height <= 0) {
                return error.InvalidParagraphBreakerInput;
            }
        }
    }

    fn updateRegion(
        self: *Breaker,
        region: ?line_regions.Region,
        line_index: usize,
    ) !void {
        const value = region orelse return;
        try line_regions.validate(&.{value});
        if (line_index < self.regions.items.len) {
            self.regions.items[line_index] = value;
        } else if (line_index == self.regions.items.len) {
            try self.regions.append(self.allocator, value);
        } else {
            return error.InvalidParagraphBreakerState;
        }
        self.refreshOptions();
    }

    fn recipe(self: *const Breaker) reshape.Uniform {
        return .{
            .cascade = font_fallback.Cascade.init(self.cascade_fonts),
            .text = self.text,
            .font_size = self.font_size,
            .options = self.options,
        };
    }

    fn refreshOptions(self: *Breaker) void {
        self.options.line_regions = self.regions.items;
    }

    fn validateSession(self: *const Breaker) !void {
        if (self.buffer_generation.* != self.session_generation) {
            return error.StaleParagraphBreaker;
        }
    }
};

fn replaceList(
    comptime T: type,
    list: *std.ArrayList(T),
    items: []const T,
) void {
    list.clearRetainingCapacity();
    list.appendSliceAssumeCapacity(items);
}
