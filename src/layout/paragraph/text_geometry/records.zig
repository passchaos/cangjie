//! Platform-neutral text-run, grapheme, line, and caret records.

const Face = @import("../../../font/face/root.zig").Face;
const paragraph_types = @import("../../types/paragraph.zig");
const pipeline_types = @import("../../../shaping/pipeline/types.zig");

pub const Direction = enum {
    ltr,
    rtl,
};

/// Selects which logical neighbor owns a caret at a shared source boundary.
///
/// This distinction is observable at soft wraps and bidi transitions, where
/// one UTF-8 byte offset can have two valid paragraph-space positions.
pub const Affinity = enum {
    /// Attach to the grapheme logically preceding the byte offset.
    upstream,
    /// Attach to the grapheme logically following the byte offset.
    downstream,
};

pub const CaretPosition = struct {
    byte_offset: usize,
    affinity: Affinity = .downstream,
};

pub const CaretGeometry = struct {
    position: CaretPosition,
    line_index: usize,
    rect: paragraph_types.TextRect,
};

/// Stateful editor cursor over an immutable TextGeometry owner.
///
/// The value stores only source position and preferred inline coordinate; all
/// geometry is resolved against the borrowed owner on demand. Keeping this
/// small lets applications maintain anchor/focus cursors without copying or
/// retaining platform-specific accessibility nodes.
pub const Cursor = struct {
    position: CaretPosition,
    preferred_inline: ?f32 = null,
};

/// Half-open logical UTF-8 source range used by selection geometry.
pub const SelectionRange = struct {
    byte_start: usize,
    byte_end: usize,
};

/// One logical word segment and its visual paragraph geometry.
///
/// The byte range follows UAX #29 and is always a complete grapheme range. A
/// bidi word can occupy more than one visual rectangle, so callers receive a
/// fragment slice rather than a single bounding box.
pub const WordGeometry = struct {
    range: SelectionRange,
    fragments: []SelectionFragment,

    pub fn deinit(self: *WordGeometry, allocator: @import("std").mem.Allocator) void {
        allocator.free(self.fragments);
        self.* = undefined;
    }
};

pub const LineBreakKind = enum {
    /// Final source line/column with no following boundary.
    none,
    /// Width-selected reusable line boundary.
    soft,
    /// Explicit Unicode mandatory line separator.
    hard,
};

/// One physically contiguous selected fragment on a visual line.
///
/// A logical selection can produce several fragments on one line when bidi
/// reordering places unselected source between selected source visually.
pub const SelectionFragment = struct {
    line_index: usize,
    rect: paragraph_types.TextRect,
};

/// One boundary in physical inline-axis traversal order.
///
/// Bidi transitions can assign distinct logical positions to one physical
/// coordinate. `inline_position` is x horizontally and y vertically.
/// `from_start` is selected when traversal arrives from a smaller physical
/// inline coordinate; `from_end` is selected in the reverse direction.
pub const VisualCaretStop = struct {
    line_index: usize,
    inline_position: f32,
    from_start: CaretPosition,
    from_end: CaretPosition,
};

/// Borrowed concrete view shared by interaction algorithms.
pub const GeometryView = struct {
    source_byte_len: usize,
    writing_mode: pipeline_types.WritingMode = .horizontal_tb,
    lines: []const Line,
    spans: []const Span,
    graphemes: []const Grapheme,
    visual_caret_stops: []const VisualCaretStop,
};

/// Stable identity and font properties copied from one final paragraph run.
///
/// `run_index` is the original index in the `ParagraphLayout.runs` slice
/// supplied to the builder and remains a numeric identity inside this owner.
/// Do not use it to index a layout after that layout's reusable buffer changes.
/// The face itself remains caller-owned and must outlive consumers that inspect
/// it through this record.
pub const FontRun = struct {
    run_index: usize,
    font: *const Face,
    cascade_index: usize,
    font_size: f32,
};

/// Geometry for one extended grapheme cluster.
///
/// Positions are relative to the owning span's physical inline origin:
/// `bounds.x` horizontally and `bounds.y` vertically. This matches the
/// character-position convention used by platform text-run accessibility
/// APIs. Logical-order graphemes in an RTL span therefore normally have
/// decreasing positions.
pub const Grapheme = struct {
    byte_start: usize,
    byte_len: usize,
    inline_position: f32,
    inline_size: f32,
    /// True when this grapheme's inline-size partition came from an authored
    /// horizontal GDEF LigCaretList rather than equal division of a shaped
    /// glyph advance.
    authored_ligature_caret: bool = false,

    pub fn byteEnd(self: Grapheme) usize {
        return self.byte_start + self.byte_len;
    }
};

/// One logical-order text span with uniform layout ownership.
///
/// Spans split whenever the line, final font run, resolved bidi direction, or
/// optional style index changes. A span without `font_run` represents source
/// such as an inline-object anchor that deliberately has no font ownership.
pub const Span = struct {
    line_index: usize,
    font_run: ?FontRun,
    style_index: ?u32,
    direction: Direction,
    byte_start: usize,
    byte_len: usize,
    bounds: paragraph_types.TextRect,
    grapheme_start: usize,
    grapheme_len: usize,
    /// Range in `TextGeometry.word_starts`.
    ///
    /// Each value is a grapheme index relative to this span. Only UAX #29
    /// segments classified as words are listed.
    word_start_start: usize,
    word_start_len: usize,
    previous_on_line: ?usize = null,
    next_on_line: ?usize = null,

    pub fn byteEnd(self: Span) usize {
        return self.byte_start + self.byte_len;
    }

    pub fn graphemes(
        self: Span,
        items: []const Grapheme,
    ) []const Grapheme {
        return items[self.grapheme_start .. self.grapheme_start + self.grapheme_len];
    }

    pub fn wordStarts(self: Span, items: []const usize) []const usize {
        return items[self.word_start_start .. self.word_start_start + self.word_start_len];
    }
};

/// Borrowed, platform-neutral accessibility view of one logical text run.
///
/// Character geometry is expressed as extended grapheme clusters because that
/// is the indivisible caret unit exposed by the layout. `word_starts` contains
/// grapheme indexes relative to `graphemes`.
pub const AccessibilityRun = struct {
    span_index: usize,
    line_index: usize,
    text: []const u8,
    direction: Direction,
    bounds: paragraph_types.TextRect,
    font_run: ?FontRun,
    style_index: ?u32,
    alignment: ?paragraph_types.TextAlign,
    graphemes: []const Grapheme,
    word_starts: []const usize,
    previous_on_line: ?usize,
    next_on_line: ?usize,
};

/// One final visual line retained independently from its text spans.
///
/// Empty lines still own a box and source boundary, allowing a trailing hard
/// break or an empty paragraph to expose a stable caret without fabricating a
/// font run.
pub const Line = struct {
    byte_start: usize,
    byte_len: usize,
    bounds: paragraph_types.TextRect,
    span_start: usize,
    span_len: usize,
    visual_caret_start: usize,
    visual_caret_len: usize,
    alignment: ?paragraph_types.TextAlign = null,
    break_kind: LineBreakKind = .none,

    pub fn byteEnd(self: Line) usize {
        return self.byte_start + self.byte_len;
    }

    pub fn spans(self: Line, items: []const Span) []const Span {
        return items[self.span_start .. self.span_start + self.span_len];
    }

    pub fn visualCaretStops(
        self: Line,
        items: []const VisualCaretStop,
    ) []const VisualCaretStop {
        return items[self.visual_caret_start .. self.visual_caret_start + self.visual_caret_len];
    }
};
