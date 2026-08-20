//! Portable text, paragraph, locale, and range style records.

const style = @import("../../../text/style/root.zig");

pub const ByteRange = style.ByteRange;
pub const CharRange = style.CharRange;
pub const ClusterRange = style.ClusterRange;
pub const GraphemeRange = style.GraphemeRange;
pub const GlyphRange = style.GlyphRange;
pub const GlyphCluster = style.GlyphCluster;
pub const FontId = style.FontId;
pub const FontWeight = style.FontWeight;
pub const FontStyle = style.TextFontStyle;
pub const Language = style.Language;
pub const Locale = style.Locale;
pub const Overflow = style.OverflowMode;
pub const Paragraph = style.ParagraphStyle;
pub const Span = style.StyleSpan;
pub const Decoration = style.TextDecoration;
pub const Metrics = style.TextMetrics;
pub const Range = style.TextRange;
pub const TextSpan = style.TextSpan;
pub const Text = style.TextStyle;
pub const VerticalAlign = style.VerticalAlign;
pub const Wrap = style.WrapMode;
pub const WordBreak = style.WordBreak;
pub const OverflowWrap = style.OverflowWrap;
pub const WhiteSpaceCollapse = style.WhiteSpaceCollapse;
pub const LineBreakStrategy = style.LineBreakStrategy;
pub const WritingMode =
    @import("../../../shaping/pipeline/types.zig").WritingMode;
pub const TextOrientation =
    @import("../../../shaping/pipeline/types.zig").TextOrientation;
