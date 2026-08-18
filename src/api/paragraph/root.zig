//! Width-independent paragraph shaping and repeatable visual reflow.

const paragraph_options = @import("../../layout/paragraph/options.zig");
const out_of_flow = @import("../../layout/paragraph/out_of_flow.zig");
const line_regions = @import("../../layout/paragraph/line_regions.zig");
const text_geometry = @import(
    "../../layout/paragraph/text_geometry/root.zig",
);
const inline_object = @import("../../layout/inline_object/root.zig");
const retained = @import("../../layout/paragraph/retained.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
const styled_paragraph = @import("../../layout/styled_paragraph.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const reflow = @import("../../layout/line_break/reflow/root.zig");
const context = @import("../../shaping/context/root.zig");

pub const Options = paragraph_options.Options;
pub const Hyphenation = paragraph_options.Hyphenation;
pub const Kashida = paragraph_options.Kashida;
pub const FontExpansion = paragraph_options.FontExpansion;
pub const Jstf = paragraph_options.Jstf;
pub const Punctuation = paragraph_options.Punctuation;
pub const PunctuationConvention =
    paragraph_options.PunctuationConvention;
pub const TabStop = paragraph_options.TabStop;
pub const TabAlignment = paragraph_options.TabAlignment;
pub const Request = context.ParagraphRequest;
pub const StyledRequest = context.StyledParagraphRequest;
pub const StyledResult = context.Engine.StyledParagraph;
pub const Align = paragraph_types.TextAlign;
pub const WrapMode = paragraph_types.WrapMode;
pub const WordBreak = paragraph_types.WordBreak;
pub const OverflowWrap = paragraph_types.OverflowWrap;
pub const WhiteSpaceCollapse = paragraph_types.WhiteSpaceCollapse;
pub const LineBreakStrategy = paragraph_types.LineBreakStrategy;
pub const BaselineMetrics = reflow.BaselineMetrics;
pub const TextMetrics = paragraph_types.TextMetrics;
pub const ContentWidths = paragraph_types.ContentWidths;
pub const InlineObject = inline_object.Object;
pub const InlineObjectKind = inline_object.Kind;
pub const PositionedInlineObject = inline_object.Positioned;
pub const OutOfFlowGeometry = inline_object.Geometry;
pub const OutOfFlowPlacement = inline_object.Placement;
pub const OutOfFlowResolution = inline_object.Resolution;
pub const OutOfFlowResolver = out_of_flow.Resolver;
pub const OutOfFlowPass = out_of_flow.Pass;
pub const OutOfFlowStep = out_of_flow.Step;
pub const OutOfFlowPlacementRequest = out_of_flow.PlacementRequest;
pub const Exclusion = paragraph_options.Exclusion;
pub const LineRegion = line_regions.Region;
pub const LineRegionResolver = line_regions.Resolver;
pub const LineRegionPass = line_regions.Pass;
pub const LineRegionStep = line_regions.Step;
pub const LineRegionRequest = line_regions.Request;
pub const object_replacement_character =
    inline_object.object_replacement_character;
pub const object_replacement_utf8 = inline_object.object_replacement_utf8;

pub const Shaped = retained.ShapedParagraph;
pub const ReflowBuffer = retained.ReflowBuffer;
pub const Breaker = retained.Breaker;
pub const BreakerInput = retained.BreakerInput;
pub const BreakerStep = retained.BreakerStep;
pub const BreakerCheckpoint = retained.BreakerCheckpoint;
pub const BreakerHeightExceeded = retained.BreakerHeightExceeded;
pub const Layout = paragraph_types.ParagraphLayout;
pub const Line = paragraph_types.ParagraphLine;
pub const Position = paragraph_types.TextPosition;
pub const Rect = paragraph_types.TextRect;

pub const StyledSpan = styled_paragraph.Span;
pub const StyledGlyphMetadata = styled_buffer.Metadata;

pub const TextGeometry = text_geometry.TextGeometry;
pub const TextGeometrySpan = text_geometry.Span;
pub const TextGeometryLine = text_geometry.Line;
pub const GraphemeGeometry = text_geometry.Grapheme;
pub const TextGeometryFontRun = text_geometry.FontRun;
pub const TextGeometryDirection = text_geometry.Direction;
pub const TextGeometryOptions = text_geometry.Options;
pub const TextGeometryAffinity = text_geometry.Affinity;
pub const TextGeometryCaretPosition = text_geometry.CaretPosition;
pub const TextGeometryCaret = text_geometry.CaretGeometry;
pub const TextGeometrySelectionRange = text_geometry.SelectionRange;
pub const TextGeometrySelectionFragment = text_geometry.SelectionFragment;
pub const TextGeometrySelectionError = text_geometry.SelectionError;
pub const TextGeometryVisualCaretStop = text_geometry.VisualCaretStop;

/// Build owned, platform-neutral text-run geometry from a final paragraph.
///
/// The returned arrays remain valid after the shaping engine or layout buffer
/// is reused. Source byte ranges still refer to `text`; font face pointers
/// retain their ordinary caller-owned lifetime.
pub const buildGeometry = text_geometry.build;

/// Styled counterpart of `buildGeometry`.
///
/// Source spans are used only to attach stable style identities; geometry is
/// always taken from the final unified paragraph after wrapping and bidi.
pub const buildStyledGeometry = text_geometry.buildStyled;
