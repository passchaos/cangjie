//! Flat ownership boundary for platform-neutral text geometry.

const std = @import("std");

const axes = @import("../axes.zig");
const interaction = @import("interaction.zig");
const records = @import("records.zig");
const selection = @import("selection.zig");
const unicode = @import("../../../unicode.zig");
const visual_carets = @import("visual_carets.zig");
const WritingMode =
    @import("../../../shaping/pipeline/types.zig").WritingMode;

const Affinity = records.Affinity;
const SelectionRange = records.SelectionRange;

pub const TextGeometry = struct {
    allocator: std.mem.Allocator,
    source: []u8,
    source_byte_len: usize,
    writing_mode: WritingMode = .horizontal_tb,
    lines: []records.Line,
    spans: []records.Span,
    graphemes: []records.Grapheme,
    words: []records.SelectionRange,
    word_starts: []usize,
    visual_caret_stops: []records.VisualCaretStop,

    pub fn deinit(self: *TextGeometry) void {
        self.allocator.free(self.source);
        self.allocator.free(self.word_starts);
        self.allocator.free(self.words);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.spans);
        self.allocator.free(self.lines);
        self.allocator.free(self.visual_caret_stops);
        self.* = undefined;
    }

    pub const AccessibilityRunIterator = struct {
        source: []const u8,
        lines: []const records.Line,
        spans: []const records.Span,
        graphemes: []const records.Grapheme,
        word_starts: []const usize,
        index: usize = 0,

        pub fn next(self: *AccessibilityRunIterator) ?records.AccessibilityRun {
            if (self.index >= self.spans.len) return null;
            const span_index = self.index;
            const span = self.spans[span_index];
            self.index += 1;
            if (span.byte_start > self.source.len or
                span.byte_len > self.source.len - span.byte_start or
                span.line_index >= self.lines.len)
            {
                return null;
            }
            const line = self.lines[span.line_index];
            return .{
                .span_index = span_index,
                .line_index = span.line_index,
                .text = self.source[span.byte_start..span.byteEnd()],
                .direction = span.direction,
                .bounds = span.bounds,
                .font_run = span.font_run,
                .style_index = span.style_index,
                .alignment = line.alignment,
                .graphemes = span.graphemes(self.graphemes),
                .word_starts = span.wordStarts(self.word_starts),
                .previous_on_line = span.previous_on_line,
                .next_on_line = span.next_on_line,
            };
        }
    };

    /// Iterate logical text runs ready for an AccessKit/UIA/AT-SPI adapter.
    ///
    /// The geometry owns `source`, so run text remains valid until `deinit`
    /// without retaining the caller's paragraph bytes or shaping engine.
    pub fn accessibilityRuns(self: TextGeometry) AccessibilityRunIterator {
        return .{
            .source = self.source,
            .lines = self.lines,
            .spans = self.spans,
            .graphemes = self.graphemes,
            .word_starts = self.word_starts,
        };
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

    pub fn cursorAt(
        self: TextGeometry,
        position: records.CaretPosition,
    ) ?records.Cursor {
        const resolved = self.caret(position) orelse return null;
        return .{ .position = resolved.position };
    }

    pub fn cursorFromPoint(
        self: TextGeometry,
        x: f32,
        y: f32,
    ) ?records.Cursor {
        const resolved = self.hitTest(x, y) orelse return null;
        return .{ .position = resolved.position };
    }

    pub fn cursorGeometry(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.CaretGeometry {
        return self.caret(cursor.position);
    }

    pub fn cursorNextVisual(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const resolved = self.nextVisualCaret(cursor.position) orelse
            return null;
        return .{
            .position = resolved.position,
            .preferred_inline = cursor.preferred_inline,
        };
    }

    pub fn cursorPreviousVisual(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const resolved = self.previousVisualCaret(cursor.position) orelse
            return null;
        return .{
            .position = resolved.position,
            .preferred_inline = cursor.preferred_inline,
        };
    }

    pub fn cursorNextVisualWord(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const resolved = self.nextVisualWord(cursor.position) orelse
            return null;
        return .{
            .position = resolved.position,
            .preferred_inline = cursor.preferred_inline,
        };
    }

    pub fn cursorPreviousVisualWord(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const resolved = self.previousVisualWord(cursor.position) orelse
            return null;
        return .{
            .position = resolved.position,
            .preferred_inline = cursor.preferred_inline,
        };
    }

    pub fn cursorNextLine(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const current = self.caret(cursor.position) orelse return null;
        const preferred = cursor.preferred_inline orelse
            axes.inlineCoordinate(
                self.writing_mode,
                current.rect.x,
                current.rect.y,
            );
        const resolved = self.nextLineCaret(
            current.position,
            preferred,
        ) orelse return null;
        return .{
            .position = resolved.position,
            .preferred_inline = preferred,
        };
    }

    pub fn cursorPreviousLine(
        self: TextGeometry,
        cursor: records.Cursor,
    ) ?records.Cursor {
        const current = self.caret(cursor.position) orelse return null;
        const preferred = cursor.preferred_inline orelse
            axes.inlineCoordinate(
                self.writing_mode,
                current.rect.x,
                current.rect.y,
            );
        const resolved = self.previousLineCaret(
            current.position,
            preferred,
        ) orelse return null;
        return .{
            .position = resolved.position,
            .preferred_inline = preferred,
        };
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

    /// Resolve the UAX #29 word containing `byte_offset` without allocating.
    ///
    /// The returned UTF-8 byte range is half-open and covers only segments
    /// classified as words; punctuation and whitespace return null. A word
    /// starting at an exact boundary wins. The paragraph-end boundary belongs
    /// to the final word when that word reaches the end of the source.
    ///
    /// This is a source-segmentation query, so it can return a range omitted
    /// from the visible geometry by max-lines truncation. Use `wordAt` when
    /// visual selection fragments, and therefore visible geometry, are needed.
    pub fn wordRangeAt(
        self: TextGeometry,
        byte_offset: usize,
    ) ?SelectionRange {
        if (byte_offset > self.source_byte_len) return null;
        for (self.words) |range| {
            if (byte_offset == range.byte_start or
                (byte_offset > range.byte_start and
                    byte_offset < range.byte_end) or
                (byte_offset == range.byte_end and
                    range.byte_end == self.source_byte_len))
            {
                return range;
            }
        }
        return null;
    }

    /// Resolve the UAX #29 extended grapheme neighboring `byte_offset`.
    ///
    /// An offset inside a grapheme always returns that complete half-open UTF-8
    /// byte range. At an exact boundary, upstream selects the preceding
    /// grapheme and downstream selects the following grapheme. Paragraph start
    /// and end normalize either affinity to their sole existing neighbor; an
    /// empty paragraph or an offset past the paragraph returns null.
    ///
    /// This walks the immutable owned source and does not allocate. In
    /// particular, it remains UAX #29-safe for graphemes omitted from visible
    /// geometry by max-lines truncation.
    pub fn graphemeRangeAt(
        self: TextGeometry,
        byte_offset: usize,
        affinity: Affinity,
    ) ?SelectionRange {
        if (byte_offset > self.source_byte_len or self.source.len == 0) {
            return null;
        }

        // TextGeometry construction validates and owns this UTF-8 source. Use
        // the zero-allocation iterator rather than retaining a second complete
        // source-grapheme table solely for point queries.
        var iterator = unicode.graphemeClustersAssumeValid(self.source);
        var previous: ?SelectionRange = null;
        while (iterator.next()) |grapheme| {
            const range = SelectionRange{
                .byte_start = grapheme.byte_start,
                .byte_end = grapheme.byte_start + grapheme.byte_len,
            };
            if (byte_offset == range.byte_start) {
                return if (affinity == .upstream)
                    previous orelse range
                else
                    range;
            }
            if (byte_offset > range.byte_start and
                byte_offset < range.byte_end)
            {
                return range;
            }
            previous = range;
        }

        // At paragraph end there is no following grapheme, so downstream is
        // normalized to the same final cluster selected by upstream.
        return if (byte_offset == self.source_byte_len) previous else null;
    }

    /// Resolve the UAX #29 word containing `byte_offset`.
    ///
    /// Punctuation and whitespace return null. At a boundary, the word that
    /// starts at the offset wins; callers can pass the preceding offset when
    /// they intentionally want the word on the other side. The returned visual
    /// fragments are allocator-owned because bidi can split one logical word.
    pub fn wordAt(
        self: TextGeometry,
        allocator: std.mem.Allocator,
        byte_offset: usize,
    ) !?records.WordGeometry {
        if (byte_offset > self.source_byte_len) return null;
        const range = self.wordRangeAt(byte_offset) orelse return null;
        const fragments = selection.build(
            allocator,
            self.geometryView(),
            range,
        ) catch |err| switch (err) {
            error.InvalidTextRange => return null,
            error.OutOfMemory => return error.OutOfMemory,
        };
        return .{
            .range = range,
            .fragments = fragments,
        };
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

    /// Move through UAX #29 word starts in physical visual order.
    ///
    /// This skips punctuation and whitespace segments. Mixed-direction lines
    /// therefore follow the rendered order rather than increasing UTF-8 byte
    /// offsets, matching editor Ctrl/Option-arrow behavior.
    pub fn nextVisualWord(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        return visual_carets.nextWord(
            self.geometryView(),
            self.words,
            current,
        );
    }

    /// Move to the previous UAX #29 word start in physical visual order.
    pub fn previousVisualWord(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        return visual_carets.previousWord(
            self.geometryView(),
            self.words,
            current,
        );
    }

    /// Move to the next visible UAX #29 word start in logical source order.
    ///
    /// If no later word remains, this returns the paragraph-end caret. Words
    /// removed by max-lines truncation are skipped rather than producing an
    /// inaccessible source position.
    pub fn nextLogicalWord(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        const normalized = interaction.caret(
            self.interactionView(),
            current,
        ) orelse return null;
        for (self.words) |word| {
            if (word.byte_start <= normalized.position.byte_offset) continue;
            if (self.caret(.{ .byte_offset = word.byte_start })) |caret_value| {
                return caret_value;
            }
        }
        var visible_end: usize = 0;
        for (self.lines) |line| visible_end = @max(visible_end, line.byteEnd());
        return self.caret(.{
            .byte_offset = visible_end,
            .affinity = .upstream,
        });
    }

    /// Move to the preceding visible UAX #29 word start in logical order.
    ///
    /// A caret inside a word moves to that word's start; a caret already at a
    /// word start moves to the previous word. If no word precedes it, the
    /// paragraph-start caret is returned.
    pub fn previousLogicalWord(
        self: TextGeometry,
        current: records.CaretPosition,
    ) ?records.CaretGeometry {
        const normalized = interaction.caret(
            self.interactionView(),
            current,
        ) orelse return null;
        var index = self.words.len;
        while (index > 0) {
            index -= 1;
            const word = self.words[index];
            if (word.byte_start >= normalized.position.byte_offset) continue;
            if (self.caret(.{ .byte_offset = word.byte_start })) |caret_value| {
                return caret_value;
            }
        }
        return self.caret(.{
            .byte_offset = 0,
            .affinity = .downstream,
        });
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
