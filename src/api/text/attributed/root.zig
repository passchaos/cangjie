//! Attributed UTF-8 records and standalone attributed layout helpers.

const core = @import("../../../core.zig");

pub const Text = core.AttributedText;
pub const Run = core.AttributedRun;
pub const RunLayout = core.AttributedRunLayout;
pub const GlyphRun = core.AttributedGlyphRun;
pub const GlyphRunLayout = core.AttributedGlyphRunLayout;
pub const ParagraphLayout = core.AttributedParagraphLayout;
pub const StyleRun = core.AttributedStyleRun;

pub const measureRuns = core.measureAttributedRunsUtf8;
pub const measure = core.measureAttributedTextUtf8;
pub const layoutRuns = core.layoutAttributedRunsUtf8;
pub const layoutGlyphRuns = core.layoutAttributedGlyphRunsUtf8;
pub const layoutParagraph = core.layoutAttributedParagraphUtf8;
