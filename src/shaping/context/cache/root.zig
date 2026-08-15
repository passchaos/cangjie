//! Internal caches owned by `TextContext`.

const metadata = @import("metadata.zig");
const lookup = @import("lookup.zig");
const glyph = @import("glyph.zig");

pub const GdefMetadataCache = metadata.GdefMetadataCache;
pub const GsubTableProofCache = metadata.GsubTableProofCache;
pub const GposTableProofCache = metadata.GposTableProofCache;
pub const LayoutScriptSelections = lookup.LayoutScriptSelections;
pub const LookupSelectionCache = lookup.LookupSelectionCache;
pub const GlyphMetrics = glyph.GlyphMetrics;
pub const VerticalGlyphMetrics = glyph.VerticalGlyphMetrics;
pub const GlyphMetricsCache = glyph.GlyphMetricsCache;
pub const GlyphIndexCache = glyph.GlyphIndexCache;
