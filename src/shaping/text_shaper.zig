//! Public single-font shaping facade.
//!
//! Ordinary shaping delegates to the mature layout shaper. Ranged GSUB lives
//! behind the same public type while remaining in a separate module, so callers
//! get one coherent API without adding rare-path state to `ShapeOptions`.

const Font = @import("../font.zig").Font;
const layout = @import("../layout.zig");
const ranged_gsub = @import("features/ranged_gsub/shaper.zig");
const unicode = @import("../unicode.zig");

pub const TextShaper = struct {
    pub const shapeUtf8 = layout.TextShaper.shapeUtf8;
    pub const shapeUtf8WithOptions = layout.TextShaper.shapeUtf8WithOptions;
    pub const shapeUtf8WithCaches = layout.TextShaper.shapeUtf8WithCaches;
    pub const shapeUtf8Cascade = layout.TextShaper.shapeUtf8Cascade;
    pub const shapeUtf8CascadeWithOptions = layout.TextShaper.shapeUtf8CascadeWithOptions;
    pub const shapeUtf8CascadeCached = layout.TextShaper.shapeUtf8CascadeCached;
    pub const shapeUtf8CascadeCachedWithOptions = layout.TextShaper.shapeUtf8CascadeCachedWithOptions;
    pub const shapeUtf8CascadeFullyCached = layout.TextShaper.shapeUtf8CascadeFullyCached;
    pub const shapeUtf8CascadeFullyCachedWithOptions = layout.TextShaper.shapeUtf8CascadeFullyCachedWithOptions;
    pub const shapeUtf8CascadeWithCaches = layout.TextShaper.shapeUtf8CascadeWithCaches;
    pub const shapeUtf8ScriptRuns = layout.TextShaper.shapeUtf8ScriptRuns;
    pub const shapeParagraphUtf8 = layout.TextShaper.shapeParagraphUtf8;
    pub const shapeParagraphUtf8WithCaches = layout.TextShaper.shapeParagraphUtf8WithCaches;
    pub const layoutParagraphUtf8 = layout.TextShaper.layoutParagraphUtf8;
    pub const layoutParagraphUtf8WithOptions = layout.TextShaper.layoutParagraphUtf8WithOptions;
    pub const layoutParagraphUtf8Cached = layout.TextShaper.layoutParagraphUtf8Cached;
    pub const layoutParagraphUtf8CachedWithOptions = layout.TextShaper.layoutParagraphUtf8CachedWithOptions;
    pub const layoutParagraphUtf8FullyCached = layout.TextShaper.layoutParagraphUtf8FullyCached;
    pub const layoutParagraphUtf8FullyCachedWithOptions = layout.TextShaper.layoutParagraphUtf8FullyCachedWithOptions;
    pub const layoutParagraphUtf8WithCaches = layout.TextShaper.layoutParagraphUtf8WithCaches;
    pub const layoutStyledParagraphUtf8 = layout.TextShaper.layoutStyledParagraphUtf8;
    pub const measureParagraphUtf8 = layout.TextShaper.measureParagraphUtf8;
    pub const measureParagraphsUtf8 = layout.TextShaper.measureParagraphsUtf8;

    pub fn shapeUtf8WithGsubFeatureRanges(
        font: *const Font,
        buffer: *layout.LayoutBuffer,
        text: []const u8,
        font_size: f32,
        ranges: []const unicode.GsubFeatureRange,
        options: layout.ShapeOptions,
    ) !layout.GlyphRun {
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
        metrics_cache: ?*layout.GlyphMetricsCache,
        glyph_index_cache: ?*layout.GlyphIndexCache,
        buffer: *layout.LayoutBuffer,
        text: []const u8,
        font_size: f32,
        ranges: []const unicode.GsubFeatureRange,
        options: layout.ShapeOptions,
    ) !layout.GlyphRun {
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
