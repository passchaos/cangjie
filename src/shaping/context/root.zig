//! Public reusable ownership boundary for shaping and paragraph layout.
//!
//! The engine is a concrete source-level value with stable public methods.
//! Methods rebind internal cache pointers before work so moving an initialized
//! value remains safe until a returned borrowing view is requested.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const paragraph_options = @import("../../layout/paragraph/options.zig");
const retained_paragraph = @import("../../layout/paragraph/retained.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const run_types = @import("../../layout/types/runs.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
const styled_paragraph = @import("../../layout/styled_paragraph.zig");
const font_fallback = @import("../fallback/font/root.zig");
const shaping_plan = @import("../plan/root.zig");
const shape_profile = @import("../../shape_profile.zig");
const state_mod = @import("state.zig");
const stats_mod = @import("stats.zig");
const text_shaper = @import("../text_shaper.zig");
const unicode = @import("../../unicode.zig");

/// One-font shaping input. Feature ranges use UTF-8 byte offsets and remain
/// separate from `ShapeOptions` because they are uncommon and change GSUB
/// lookup eligibility rather than the run-wide segment properties.
pub const ShapeRequest = struct {
    /// Valid UTF-8 to shape. The bytes are borrowed only for this call.
    text: []const u8,
    /// Positive, finite font size in output units.
    font_size: f32,
    options: shaping_plan.ShapeOptions = .{},
    feature_ranges: []const unicode.GsubFeatureRange = &.{},
};

/// Fallback shaping input for an already selected cascade.
pub const CascadeRequest = struct {
    text: []const u8,
    font_size: f32,
    options: shaping_plan.ShapeOptions = .{},
};

/// Paragraph shaping and layout input. Keeping text, size, and options in one
/// record makes call sites resilient as the paragraph contract grows.
pub const ParagraphRequest = struct {
    text: []const u8,
    font_size: f32,
    options: paragraph_options.Options,
};

/// Styled paragraph input. Spans and their backing style data are borrowed for
/// the duration of the call; returned slices still follow the context lifetime.
pub const StyledParagraphRequest = struct {
    text: []const u8,
    default_font_size: f32,
    spans: []const styled_paragraph.Span,
    options: paragraph_options.Options,
};

/// Owns reusable shaping output, transient arrays, and font-derived caches.
///
/// Returned runs and layouts borrow the context and remain valid until its next
/// shaping/layout call. Faces referenced by cache keys and returned runs must
/// outlive the engine, or `clearCaches` must be called before they are freed.
/// An engine is not thread-safe; use one engine per concurrent worker.
pub const Engine = struct {
    /// Source-visible implementation storage. Applications should use the
    /// methods below rather than depending on this field's evolving layout.
    state: state_mod.State,

    pub const Options = struct {
        cache_font_data: bool = true,
        cache_shaped_runs: bool = false,
    };
    pub const Stats = stats_mod.Stats;
    pub const Counter = stats_mod.Counter;
    pub const StyledParagraph = struct {
        layout: paragraph_types.ParagraphLayout,
        glyph_metadata: []const styled_buffer.Metadata,
        content_widths: paragraph_types.ContentWidths,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        options: Options,
    ) Engine {
        return .{
            .state = state_mod.State.init(
                allocator,
                options.cache_font_data,
                options.cache_shaped_runs,
            ),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.state.deinit();
    }

    /// Enable or disable complete shaped-run caching without discarding entries.
    pub fn setShapedRunCaching(self: *Engine, enabled: bool) void {
        self.getState().cache_shaped_runs = enabled;
    }

    /// Clear result arrays while retaining allocated capacity.
    pub fn clearOutput(self: *Engine) void {
        self.getState().output.clear();
    }

    /// Discard every font-derived cache and reset aggregate counters.
    pub fn clearCaches(self: *Engine) void {
        self.getState().clearCaches();
    }

    pub fn stats(self: *const Engine) Stats {
        return self.getStateConst().stats();
    }

    pub fn enableProfiling(
        self: *Engine,
        profile: *shape_profile.ShapeStageProfile,
        io: std.Io,
        fast_path: bool,
    ) void {
        const state = self.getStateForWork();
        state.output.shape_profile = profile;
        state.output.profile_io = io;
        state.output.profile_fast_path = fast_path;
    }

    pub fn disableProfiling(self: *Engine) void {
        const state = self.getState();
        state.output.shape_profile = null;
        state.output.profile_io = null;
        state.output.profile_fast_path = false;
    }

    pub fn shape(
        self: *Engine,
        face: *const face_mod.Face,
        request: ShapeRequest,
    ) !run_types.GlyphRun {
        const state = self.getStateForWork();
        const font = face_mod.backend.font(face);
        if (request.feature_ranges.len != 0) {
            return text_shaper.TextShaper
                .shapeUtf8WithCachesAndGsubFeatureRanges(
                font,
                if (state.cache_font_data) &state.glyph_metrics else null,
                if (state.cache_font_data) &state.glyph_indices else null,
                &state.output,
                request.text,
                request.font_size,
                request.feature_ranges,
                request.options,
            );
        }
        return text_shaper.TextShaper.shapeUtf8WithCaches(
            font,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    /// Shape text through an ordered fallback cascade.
    pub fn shapeText(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: CascadeRequest,
    ) !run_types.ShapedText {
        const state = self.getStateForWork();
        return text_shaper.TextShaper.shapeUtf8CascadeWithCaches(
            internalCascade(cascade),
            if (state.cache_font_data) &state.font_fallback else null,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            state.shapedRunCache(),
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    /// Shape text and retain its script-itemization boundaries.
    pub fn itemize(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: CascadeRequest,
    ) !run_types.ScriptedText {
        const state = self.getStateForWork();
        return text_shaper.TextShaper.shapeUtf8ScriptRuns(
            internalCascade(cascade),
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    /// Prepare width-independent paragraph content for repeated reflow.
    pub fn prepareParagraph(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: ParagraphRequest,
    ) !retained_paragraph.ShapedParagraph {
        const state = self.getStateForWork();
        return text_shaper.TextShaper.shapeParagraphUtf8WithCaches(
            state.allocator,
            internalCascade(cascade),
            if (state.cache_font_data) &state.font_fallback else null,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            state.shapedRunCache(),
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    /// Shape and lay out a paragraph in one call.
    pub fn layout(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: ParagraphRequest,
    ) !paragraph_types.ParagraphLayout {
        const state = self.getStateForWork();
        return text_shaper.TextShaper.layoutParagraphUtf8WithCaches(
            internalCascade(cascade),
            if (state.cache_font_data) &state.font_fallback else null,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            state.shapedRunCache(),
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    pub fn layoutStyled(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: StyledParagraphRequest,
    ) !StyledParagraph {
        const state = self.getStateForWork();
        const paragraph = try text_shaper.TextShaper.layoutStyledParagraphUtf8(
            internalCascade(cascade),
            &state.output,
            &state.styled_output,
            request.text,
            request.default_font_size,
            request.spans,
            request.options,
        );
        return .{
            .layout = paragraph,
            .glyph_metadata = state.styled_output.glyphMetadata(),
            .content_widths = state.styled_output.contentWidths() orelse
                return error.InvalidParagraphLayout,
        };
    }

    /// Shape once, then calculate policy-aware intrinsic paragraph widths.
    pub fn contentWidths(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: ParagraphRequest,
    ) !paragraph_types.ContentWidths {
        const state = self.getStateForWork();
        var paragraph =
            try text_shaper.TextShaper.shapeParagraphUtf8WithCaches(
                state.allocator,
                internalCascade(cascade),
                if (state.cache_font_data) &state.font_fallback else null,
                if (state.cache_font_data) &state.glyph_metrics else null,
                if (state.cache_font_data) &state.glyph_indices else null,
                state.shapedRunCache(),
                &state.output,
                request.text,
                request.font_size,
                request.options,
            );
        defer paragraph.deinit();
        return paragraph.contentWidths(request.options);
    }

    pub fn measure(
        self: *Engine,
        cascade: face_mod.Cascade,
        request: ParagraphRequest,
    ) !paragraph_types.TextMetrics {
        const paragraph = try self.layout(cascade, request);
        return paragraph_types.metrics(paragraph);
    }

    fn getState(self: *Engine) *state_mod.State {
        return &self.state;
    }

    fn getStateForWork(self: *Engine) *state_mod.State {
        self.state.bindPlanCaches();
        return &self.state;
    }

    fn getStateConst(self: *const Engine) *const state_mod.State {
        return &self.state;
    }
};

fn internalCascade(cascade: face_mod.Cascade) font_fallback.Cascade {
    return .init(face_mod.backend.fonts(cascade.faces));
}
