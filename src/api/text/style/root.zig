//! Portable text, paragraph, locale, and range style records.

const core = @import("../../../core.zig");

pub const ByteRange = core.ByteRange;
pub const CharRange = core.CharRange;
pub const ClusterRange = core.ClusterRange;
pub const GraphemeRange = core.GraphemeRange;
pub const GlyphRange = core.GlyphRange;
pub const GlyphCluster = core.GlyphCluster;
pub const FontId = core.FontId;
pub const FontWeight = core.FontWeight;
pub const FontStyle = core.TextFontStyle;
pub const Language = core.Language;
pub const Locale = core.Locale;
pub const Overflow = core.OverflowMode;
pub const Paragraph = core.ParagraphStyle;
pub const Span = core.StyleSpan;
pub const Decoration = core.TextDecoration;
pub const Metrics = core.TextMetrics;
pub const Range = core.TextRange;
pub const TextSpan = core.TextSpan;
pub const Text = core.TextStyle;
pub const VerticalAlign = core.VerticalAlign;
pub const Wrap = core.WrapMode;
