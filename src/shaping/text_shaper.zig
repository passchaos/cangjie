//! Public single-font shaping facade.
//!
//! Ordinary shaping is owned by `orchestrator.zig`. Ranged GSUB lives behind
//! this extended facade so callers get one coherent API without adding
//! rare-path state to run-wide shape options.

const Font = @import("../font.zig").Font;
const cache = @import("context/cache/root.zig");
const context_output = @import("context/output.zig");
const ordinary = @import("orchestrator.zig").TextShaper;
const ranged_gsub = @import("features/ranged_gsub/shaper.zig");
const run_types = @import("../layout/types/runs.zig");
const shaping_plan = @import("plan/root.zig");
const unicode = @import("../unicode.zig");

pub const TextShaper = struct {
    pub const shapeUtf8 = ordinary.shapeUtf8;
    pub const shapeUtf8WithOptions = ordinary.shapeUtf8WithOptions;
    pub const shapeUtf8WithCaches = ordinary.shapeUtf8WithCaches;
    pub const shapeUtf8Cascade = ordinary.shapeUtf8Cascade;
    pub const shapeUtf8CascadeWithOptions = ordinary.shapeUtf8CascadeWithOptions;
    pub const shapeUtf8CascadeCached = ordinary.shapeUtf8CascadeCached;
    pub const shapeUtf8CascadeCachedWithOptions =
        ordinary.shapeUtf8CascadeCachedWithOptions;
    pub const shapeUtf8CascadeFullyCached =
        ordinary.shapeUtf8CascadeFullyCached;
    pub const shapeUtf8CascadeFullyCachedWithOptions =
        ordinary.shapeUtf8CascadeFullyCachedWithOptions;
    pub const shapeUtf8CascadeWithCaches =
        ordinary.shapeUtf8CascadeWithCaches;
    pub const shapeUtf8ScriptRuns = ordinary.shapeUtf8ScriptRuns;
    pub const shapeParagraphUtf8 = ordinary.shapeParagraphUtf8;
    pub const shapeParagraphUtf8WithCaches =
        ordinary.shapeParagraphUtf8WithCaches;
    pub const layoutParagraphUtf8 = ordinary.layoutParagraphUtf8;
    pub const layoutParagraphUtf8WithOptions =
        ordinary.layoutParagraphUtf8WithOptions;
    pub const layoutParagraphUtf8Cached = ordinary.layoutParagraphUtf8Cached;
    pub const layoutParagraphUtf8CachedWithOptions =
        ordinary.layoutParagraphUtf8CachedWithOptions;
    pub const layoutParagraphUtf8FullyCached =
        ordinary.layoutParagraphUtf8FullyCached;
    pub const layoutParagraphUtf8FullyCachedWithOptions =
        ordinary.layoutParagraphUtf8FullyCachedWithOptions;
    pub const layoutParagraphUtf8WithCaches =
        ordinary.layoutParagraphUtf8WithCaches;
    pub const layoutStyledParagraphUtf8 =
        ordinary.layoutStyledParagraphUtf8;
    pub const measureParagraphUtf8 = ordinary.measureParagraphUtf8;
    pub const measureParagraphsUtf8 = ordinary.measureParagraphsUtf8;

    pub fn shapeUtf8WithGsubFeatureRanges(
        font: *const Font,
        buffer: *context_output.Buffer,
        text: []const u8,
        font_size: f32,
        ranges: []const unicode.GsubFeatureRange,
        options: shaping_plan.ShapeOptions,
    ) !run_types.GlyphRun {
        return ranged_gsub.Shaper.shapeUtf8WithOptions(
            font,
            buffer,
            text,
            font_size,
            ranges,
            options,
        );
    }

    pub fn shapeUtf8WithCachesAndGsubFeatureRanges(
        font: *const Font,
        metrics_cache: ?*cache.GlyphMetricsCache,
        glyph_index_cache: ?*cache.GlyphIndexCache,
        buffer: *context_output.Buffer,
        text: []const u8,
        font_size: f32,
        ranges: []const unicode.GsubFeatureRange,
        options: shaping_plan.ShapeOptions,
    ) !run_types.GlyphRun {
        return ranged_gsub.Shaper.shapeUtf8WithCaches(
            font,
            metrics_cache,
            glyph_index_cache,
            buffer,
            text,
            font_size,
            ranges,
            options,
        );
    }
};
