//! Internal caches owned by `Engine`.

const metadata = @import("metadata.zig");
const lookup = @import("lookup.zig");
const glyph = @import("glyph.zig");
const shaped_run = @import("shaped_run.zig");

pub const GdefMetadataCache = metadata.GdefMetadataCache;
pub const GsubTableProofCache = metadata.GsubTableProofCache;
pub const GposTableProofCache = metadata.GposTableProofCache;
pub const LayoutScriptSelections = lookup.LayoutScriptSelections;
pub const LookupSelectionCache = lookup.LookupSelectionCache;
pub const GlyphMetrics = glyph.GlyphMetrics;
pub const VerticalGlyphMetrics = glyph.VerticalGlyphMetrics;
pub const GlyphMetricsCache = glyph.GlyphMetricsCache;
pub const GlyphIndexCache = glyph.GlyphIndexCache;
pub const ShapedRunCacheKey = shaped_run.ShapedRunCacheKey;
pub const ShapedRunCacheEntry = shaped_run.ShapedRunCacheEntry;
pub const ShapedRunCache = shaped_run.ShapedRunCache;
