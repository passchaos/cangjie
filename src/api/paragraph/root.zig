//! Width-independent paragraph shaping and repeatable visual reflow.

const layout = @import("../../layout.zig");
const context = @import("../../shaping/context/root.zig");

pub const Options = layout.ParagraphOptions;
pub const Request = context.ParagraphRequest;
pub const StyledRequest = context.StyledParagraphRequest;
pub const StyledResult = context.Engine.StyledParagraph;
pub const Align = layout.TextAlign;
pub const WrapMode = layout.WrapMode;
pub const BaselineMetrics = layout.BaselineMetrics;
pub const TextMetrics = layout.TextMetrics;

pub const Shaped = layout.ShapedParagraph;
pub const ReflowBuffer = layout.ReflowBuffer;
pub const Layout = layout.ParagraphLayout;
pub const Line = layout.ParagraphLine;
pub const Position = layout.TextPosition;
pub const Rect = layout.TextRect;

pub const StyledSpan = layout.StyledParagraphSpan;
pub const StyledGlyphMetadata = layout.StyledGlyphMetadata;
