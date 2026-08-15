//! Public reusable ownership boundary for shaping and paragraph layout.
//!
//! The context is a small heap-backed handle. Internal scratch arrays and
//! caches cannot be accidentally copied or rewired by callers.

const std = @import("std");

const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
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
    options: layout.ShapeOptions = .{},
    feature_ranges: []const unicode.GsubFeatureRange = &.{},
};

/// Fallback shaping input for an already selected cascade.
pub const CascadeRequest = struct {
    text: []const u8,
    font_size: f32,
    options: layout.ShapeOptions = .{},
};

/// Paragraph shaping and layout input. Keeping text, size, and options in one
/// record makes call sites resilient as the paragraph contract grows.
pub const ParagraphRequest = struct {
    text: []const u8,
    font_size: f32,
    options: layout.ParagraphOptions,
};

/// Styled paragraph input. Spans and their backing style data are borrowed for
/// the duration of the call; returned slices still follow the context lifetime.
pub const StyledParagraphRequest = struct {
    text: []const u8,
    default_font_size: f32,
    spans: []const layout.StyledParagraphSpan,
    options: layout.ParagraphOptions,
};

/// Owns reusable shaping output, transient arrays, and font-derived caches.
///
/// Returned runs and layouts borrow the context and remain valid until its next
/// shaping/layout call. Fonts referenced by cache keys and returned runs must
/// outlive the context, or `clearCaches` must be called before they are freed.
/// A context is not thread-safe; use one context per concurrent worker.
pub const TextContext = opaque {
    pub const Options = struct {
        cache_font_data: bool = true,
        cache_shaped_runs: bool = false,
    };
    pub const Stats = stats_mod.Stats;
    pub const Counter = stats_mod.Counter;
    pub const ShapeInput = ShapeRequest;
    pub const CascadeInput = CascadeRequest;
    pub const ParagraphInput = ParagraphRequest;
    pub const StyledParagraphInput = StyledParagraphRequest;
    pub const StyledParagraph = struct {
        layout: layout.ParagraphLayout,
        glyph_metadata: []const layout.StyledGlyphMetadata,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        options: Options,
    ) !*TextContext {
        const state = try allocator.create(state_mod.State);
        state.* = state_mod.State.init(
            allocator,
            options.cache_font_data,
            options.cache_shaped_runs,
        );
        state.bindPlanCaches();
        return @ptrCast(state);
    }

    pub fn deinit(self: *TextContext) void {
        const state: *state_mod.State = @ptrCast(@alignCast(self));
        const allocator = state.allocator;
        state.deinit();
        allocator.destroy(state);
    }

    /// Enable or disable complete shaped-run caching without discarding entries.
    pub fn setShapedRunCaching(self: *TextContext, enabled: bool) void {
        self.getState().cache_shaped_runs = enabled;
    }

    /// Clear result arrays while retaining allocated capacity.
    pub fn clearOutput(self: *TextContext) void {
        self.getState().output.clear();
    }

    /// Discard every font-derived cache and reset aggregate counters.
    pub fn clearCaches(self: *TextContext) void {
        self.getState().clearCaches();
    }

    pub fn stats(self: *const TextContext) Stats {
        return self.getStateConst().stats();
    }

    pub fn enableProfiling(
        self: *TextContext,
        profile: *layout.ShapeStageProfile,
        io: std.Io,
        fast_path: bool,
    ) void {
        const state = self.getState();
        state.output.shape_profile = profile;
        state.output.profile_io = io;
        state.output.profile_fast_path = fast_path;
    }

    pub fn disableProfiling(self: *TextContext) void {
        const state = self.getState();
        state.output.shape_profile = null;
        state.output.profile_io = null;
        state.output.profile_fast_path = false;
    }

    pub fn shape(
        self: *TextContext,
        font: *const Font,
        request: ShapeRequest,
    ) !layout.GlyphRun {
        const state = self.getState();
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

    pub fn shapeCascade(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: CascadeRequest,
    ) !layout.ShapedText {
        const state = self.getState();
        return layout.TextShaper.shapeUtf8CascadeWithCaches(
            cascade,
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

    pub fn shapeScriptRuns(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: CascadeRequest,
    ) !layout.ScriptedText {
        const state = self.getState();
        return layout.TextShaper.shapeUtf8ScriptRuns(
            cascade,
            &state.output,
            request.text,
            request.font_size,
            request.options,
        );
    }

    pub fn shapeParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: ParagraphRequest,
    ) !layout.ShapedParagraph {
        const state = self.getState();
        return layout.TextShaper.shapeParagraphUtf8WithCaches(
            state.allocator,
            cascade,
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

    pub fn layoutParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: ParagraphRequest,
    ) !layout.ParagraphLayout {
        const state = self.getState();
        return layout.TextShaper.layoutParagraphUtf8WithCaches(
            cascade,
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

    pub fn layoutStyledParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: StyledParagraphRequest,
    ) !StyledParagraph {
        const state = self.getState();
        const paragraph = try layout.TextShaper.layoutStyledParagraphUtf8(
            cascade,
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
        };
    }

    pub fn measureParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        request: ParagraphRequest,
    ) !layout.TextMetrics {
        const paragraph = try self.layoutParagraph(cascade, request);
        if (paragraph.lines.len == 0) {
            return .{
                .width = 0,
                .height = 0,
                .baseline = 0,
                .ascent = 0,
                .descent = 0,
                .leading = 0,
            };
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

    fn getState(self: *TextContext) *state_mod.State {
        return @ptrCast(@alignCast(self));
    }

    fn getStateConst(self: *const TextContext) *const state_mod.State {
        return @ptrCast(@alignCast(self));
    }
};
