//! Optional textual diagnostics and paragraph overlay construction.

pub const dumps = @import("dumps.zig");
pub const overlays = @import("overlays.zig");

pub const OverlayKind = overlays.OverlayKind;
pub const DebugOverlay = overlays.DebugOverlay;
pub const DebugOverlayList = overlays.DebugOverlayList;
pub const OverlayOptions = overlays.OverlayOptions;
pub const buildDebugOverlays = overlays.buildDebugOverlays;

pub const dumpUnicodeSegmentation = dumps.dumpUnicodeSegmentation;
pub const dumpBidiRuns = dumps.dumpBidiRuns;
pub const dumpBidiMap = dumps.dumpBidiMap;
pub const dumpLineBreaks = dumps.dumpLineBreaks;
pub const dumpFontFallback = dumps.dumpFontFallback;
pub const dumpShapeRuns = dumps.dumpShapeRuns;
pub const dumpGlyphClusters = dumps.dumpGlyphClusters;
pub const dumpParagraphLayout = dumps.dumpParagraphLayout;
pub const dumpHitTest = dumps.dumpHitTest;
pub const dumpSelectionRects = dumps.dumpSelectionRects;
pub const dumpDebugOverlays = dumps.dumpDebugOverlays;
pub const dumpMissingGlyphs = dumps.dumpMissingGlyphs;
pub const dumpFontCoverage = dumps.dumpFontCoverage;
pub const dumpShapePlanCacheStats = dumps.dumpShapePlanCacheStats;
pub const dumpShapedRunCacheStats = dumps.dumpShapedRunCacheStats;
pub const dumpFontFallbackCacheStats = dumps.dumpFontFallbackCacheStats;
pub const dumpGlyphMetricsCacheStats = dumps.dumpGlyphMetricsCacheStats;
pub const dumpGlyphIndexCacheStats = dumps.dumpGlyphIndexCacheStats;

test {
    _ = @import("tests.zig");
}
