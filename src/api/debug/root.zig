//! Optional diagnostic dumps and paragraph overlay construction.

const impl = @import("../../debug.zig");

pub const OverlayKind = impl.OverlayKind;
pub const Overlay = impl.DebugOverlay;
pub const OverlayList = impl.DebugOverlayList;
pub const OverlayOptions = impl.OverlayOptions;

pub const buildOverlays = impl.buildDebugOverlays;
pub const dumpBidiMap = impl.dumpBidiMap;
pub const dumpBidiRuns = impl.dumpBidiRuns;
pub const dumpOverlays = impl.dumpDebugOverlays;
pub const dumpFontCoverage = impl.dumpFontCoverage;
pub const dumpFontFallback = impl.dumpFontFallback;
pub const dumpGlyphClusters = impl.dumpGlyphClusters;
pub const dumpHitTest = impl.dumpHitTest;
pub const dumpLineBreaks = impl.dumpLineBreaks;
pub const dumpMissingGlyphs = impl.dumpMissingGlyphs;
pub const dumpParagraphLayout = impl.dumpParagraphLayout;
pub const dumpSelectionRects = impl.dumpSelectionRects;
pub const dumpShapeRuns = impl.dumpShapeRuns;
pub const dumpTextBufferLayoutStats = impl.dumpTextBufferLayoutStats;
pub const dumpUnicodeSegmentation = impl.dumpUnicodeSegmentation;
