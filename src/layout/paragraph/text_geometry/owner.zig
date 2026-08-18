//! Flat ownership boundary for platform-neutral text geometry.

const std = @import("std");

const interaction = @import("interaction.zig");
const records = @import("records.zig");
const selection = @import("selection.zig");
const visual_carets = @import("visual_carets.zig");
const WritingMode =
    @import("../../../shaping/pipeline/types.zig").WritingMode;

pub const TextGeometry = struct {
    allocator: std.mem.Allocator,
    source_byte_len: usize,
    writing_mode: WritingMode = .horizontal_tb,
    lines: []records.Line,
    spans: []records.Span,
    graphemes: []records.Grapheme,
    word_starts: []usize,
    visual_caret_stops: []records.VisualCaretStop,

    pub fn deinit(self: *TextGeometry) void {
        self.allocator.free(self.word_starts);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.spans);
        self.allocator.free(self.lines);
        self.allocator.free(self.visual_caret_stops);
        self.* = undefined;
    }

    /// Resolve one exact source boundary and affinity into paragraph geometry.
    ///
    /// Returns null for offsets outside the source or inside a grapheme. At the
    /// paragraph edges, the only existing logical neighbor is selected even if
    /// the caller requests the opposite affinity.
    pub fn caret(
        self: TextGeometry,
        position: records.CaretPosition,
    ) ?records.CaretGeometry {
        return interaction.caret(self.interactionView(), position);
    }

    /// Return the closest grapheme caret for a paragraph-space point.
    ///
    /// The selected line is block-axis-nearest. Within it, the physical half
    /// of the closest positive-inline-size grapheme determines the logical
    /// boundary and affinity; RTL reverses inline source ownership. Empty lines
    /// resolve to their sole source boundary.
    pub fn hitTest(
        self: TextGeometry,
        x: f32,
        y: f32,
    ) ?records.CaretGeometry {
        return interaction.hitTest(self.interactionView(), x, y);
    }

    /// Build allocator-owned visual fragments for one exact logical UTF-8
    /// range. Invalid, partial-grapheme, or truncated-away ranges are rejected.
    pub fn selectionFragments(
        self: TextGeometry,
        allocator: std.mem.Allocator,
        range: records.SelectionRange,
    ) selection.Error![]records.SelectionFragment {
        return selection.build(allocator, self.geometryView(), range);
    }

    pub fn nextVisualCaret(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        return visual_carets.next(self.geometryView(), current);
    }

    pub fn previousVisualCaret(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        return visual_carets.previous(self.geometryView(), current);
    }

    /// Move to the nearest stop on the following visual line.
    ///
    /// `preferred_inline` is caller-owned state and should remain unchanged
    /// across a sequence of block-axis moves. It is physical x for horizontal
    /// text and physical y for vertical text.
    pub fn nextLineCaret(
        self: TextGeometry,
        current: records.CaretPosition,
        preferred_inline: f32,
    ) ?records.CaretGeometry {
        return visual_carets.nextLine(
            self.geometryView(),
            current,
            preferred_inline,
        );
    }

    /// Move to the nearest stop on the preceding visual line.
    pub fn previousLineCaret(
        self: TextGeometry,
        current: records.CaretPosition,
        preferred_inline: f32,
    ) ?records.CaretGeometry {
        return visual_carets.previousLine(
            self.geometryView(),
            current,
            preferred_inline,
        );
    }

    fn interactionView(self: TextGeometry) interaction.View {
        return self.geometryView();
    }

    fn geometryView(self: TextGeometry) records.GeometryView {
        return .{
            .source_byte_len = self.source_byte_len,
            .writing_mode = self.writing_mode,
            .lines = self.lines,
            .spans = self.spans,
            .graphemes = self.graphemes,
            .visual_caret_stops = self.visual_caret_stops,
        };
    }
};
