//! Public reusable ownership boundary for shaping and paragraph layout.
//!
//! `TextContext` is a small heap-backed handle. Internal scratch arrays and
//! caches cannot be accidentally copied or rewired by callers.

const std = @import("std");

const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
const state_mod = @import("state.zig");
const stats_mod = @import("stats.zig");
const text_shaper = @import("../text_shaper.zig");
const unicode = @import("../../unicode.zig");

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
        text: []const u8,
        font_size: f32,
        options: layout.ShapeOptions,
    ) !layout.GlyphRun {
        const state = self.getState();
        return text_shaper.TextShaper.shapeUtf8WithCaches(
            font,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            &state.output,
            text,
            font_size,
            options,
        );
    }

    pub fn shapeWithFeatureRanges(
        self: *TextContext,
        font: *const Font,
        text: []const u8,
        font_size: f32,
        ranges: []const unicode.GsubFeatureRange,
        options: layout.ShapeOptions,
    ) !layout.GlyphRun {
        const state = self.getState();
        return text_shaper.TextShaper.shapeUtf8WithCachesAndGsubFeatureRanges(
            font,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            &state.output,
            text,
            font_size,
            ranges,
            options,
        );
    }

    pub fn shapeCascade(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        font_size: f32,
        options: layout.ShapeOptions,
    ) !layout.ShapedText {
        const state = self.getState();
        return layout.TextShaper.shapeUtf8CascadeWithCaches(
            cascade,
            if (state.cache_font_data) &state.font_fallback else null,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            state.shapedRunCache(),
            &state.output,
            text,
            font_size,
            options,
        );
    }

    pub fn shapeScriptRuns(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        font_size: f32,
        options: layout.ShapeOptions,
    ) !layout.ScriptedText {
        const state = self.getState();
        return layout.TextShaper.shapeUtf8ScriptRuns(
            cascade,
            &state.output,
            text,
            font_size,
            options,
        );
    }

    pub fn shapeParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        font_size: f32,
        options: layout.ParagraphOptions,
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
            text,
            font_size,
            options,
        );
    }

    pub fn layoutParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        font_size: f32,
        options: layout.ParagraphOptions,
    ) !layout.ParagraphLayout {
        const state = self.getState();
        return layout.TextShaper.layoutParagraphUtf8WithCaches(
            cascade,
            if (state.cache_font_data) &state.font_fallback else null,
            if (state.cache_font_data) &state.glyph_metrics else null,
            if (state.cache_font_data) &state.glyph_indices else null,
            state.shapedRunCache(),
            &state.output,
            text,
            font_size,
            options,
        );
    }

    pub fn layoutStyledParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        default_font_size: f32,
        spans: []const layout.StyledParagraphSpan,
        options: layout.ParagraphOptions,
    ) !StyledParagraph {
        const state = self.getState();
        const paragraph = try layout.TextShaper.layoutStyledParagraphUtf8(
            cascade,
            &state.output,
            &state.styled_output,
            text,
            default_font_size,
            spans,
            options,
        );
        return .{
            .layout = paragraph,
            .glyph_metadata = state.styled_output.glyphMetadata(),
        };
    }

    pub fn measureParagraph(
        self: *TextContext,
        cascade: layout.FontCascade,
        text: []const u8,
        font_size: f32,
        options: layout.ParagraphOptions,
    ) !layout.TextMetrics {
        const paragraph = try self.layoutParagraph(
            cascade,
            text,
            font_size,
            options,
        );
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
