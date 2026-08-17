//! Width-independent paragraph shaping and repeatable visual reflow.

const paragraph_options = @import("../../layout/paragraph/options.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const retained = @import("../../layout/paragraph/retained.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
const styled_paragraph = @import("../../layout/styled_paragraph.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const reflow = @import("../../layout/line_break/reflow/root.zig");
const context = @import("../../shaping/context/root.zig");

pub const Options = paragraph_options.Options;
pub const Hyphenation = paragraph_options.Hyphenation;
pub const Punctuation = paragraph_options.Punctuation;
pub const Request = context.ParagraphRequest;
pub const StyledRequest = context.StyledParagraphRequest;
pub const StyledResult = context.Engine.StyledParagraph;
pub const Align = paragraph_types.TextAlign;
pub const WrapMode = paragraph_types.WrapMode;
pub const BaselineMetrics = reflow.BaselineMetrics;
pub const TextMetrics = paragraph_types.TextMetrics;
pub const InlineObject = inline_object.Object;
pub const InlineObjectKind = inline_object.Kind;
pub const PositionedInlineObject = inline_object.Positioned;
pub const object_replacement_character =
    inline_object.object_replacement_character;
pub const object_replacement_utf8 = inline_object.object_replacement_utf8;

pub const Shaped = retained.ShapedParagraph;
pub const ReflowBuffer = retained.ReflowBuffer;
pub const Layout = paragraph_types.ParagraphLayout;
pub const Line = paragraph_types.ParagraphLine;
pub const Position = paragraph_types.TextPosition;
pub const Rect = paragraph_types.TextRect;

pub const StyledSpan = styled_paragraph.Span;
pub const StyledGlyphMetadata = styled_buffer.Metadata;
