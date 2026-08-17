//! Flat ownership boundary for platform-neutral text geometry.

const std = @import("std");

const interaction = @import("interaction.zig");
const records = @import("records.zig");

pub const TextGeometry = struct {
    allocator: std.mem.Allocator,
    source_byte_len: usize,
    lines: []records.Line,
    spans: []records.Span,
    graphemes: []records.Grapheme,
    word_starts: []usize,

    pub fn deinit(self: *TextGeometry) void {
        self.allocator.free(self.word_starts);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.spans);
        self.allocator.free(self.lines);
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
    /// The selected line is y-nearest. Within it, the physical half of the
    /// closest positive-width grapheme determines the logical boundary and
    /// affinity; RTL reverses left/right source ownership. Empty lines resolve
    /// to their sole source boundary.
    pub fn hitTest(
        self: TextGeometry,
        x: f32,
        y: f32,
    ) ?records.CaretGeometry {
        return interaction.hitTest(self.interactionView(), x, y);
    }

    fn interactionView(self: TextGeometry) interaction.View {
        return .{
            .source_byte_len = self.source_byte_len,
            .lines = self.lines,
            .spans = self.spans,
            .graphemes = self.graphemes,
        };
    }
};
