//! Public paragraph geometry, hit-testing, and selection records.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const axes = @import("../paragraph/axes.zig");
const inline_object = @import("../inline_object/root.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const run_types = @import("runs.zig");
const CascadeRun = run_types.CascadeRun;
const unicode = @import("../../unicode.zig");

pub const TextAlign = enum {
    /// Physical left edge, independent of paragraph direction.
    left,
    /// Center along the current writing mode's inline axis.
    center,
    /// Physical right edge, independent of paragraph direction.
    right,
    /// Fill each non-terminal soft-wrapped line by expanding its breakable
    /// inter-word spaces. Arabic-family runs first consume retained safe
    /// boundaries through source-level U+0640 insertion and reshaping; lines
    /// without spaces may use conservative inter-character expansion between
    /// adjacent CJK source atoms.
    /// Hard-break lines, the final line of a paragraph, ellipsized last lines,
    /// unbounded layouts, and lines without safe opportunities retain their
    /// natural width.
    justify,
    /// Align to logical inline start: left/right horizontally and top in the
    /// currently supported top-to-bottom vertical paragraph flow.
    start,
    /// Align to logical inline end: right/left horizontally and bottom in the
    /// currently supported top-to-bottom vertical paragraph flow.
    end,
};

/// Block-axis placement of one inline style inside its final line box.
pub const VerticalAlign = enum {
    /// Keep the font or object baseline on the line baseline.
    baseline,
    /// Align the inline box's top edge with the line's top edge.
    top,
    /// Center the inline box inside the line box.
    middle,
    /// Align the inline box's bottom edge with the line's bottom edge.
    bottom,
};

pub const WrapMode = enum {
    /// Preserve explicit Unicode hard breaks but do not introduce lines to
    /// satisfy `max_width`.
    no_wrap,
    /// Greedily wrap at UAX #14 opportunities, with grapheme-boundary
    /// emergency breaks when an unbreakable fragment exceeds `max_width`.
    word,
};

/// Tailoring of ordinary soft opportunities inside or between words.
pub const WordBreak = enum {
    /// Use Unicode UAX #14 plus optional dictionary and hyphenation boundaries.
    normal,
    /// Add a soft opportunity at every reusable grapheme boundary.
    break_all,
    /// Suppress opportunities between adjacent CJK/Hangul word characters.
    keep_all,
};

/// Policy for otherwise unbreakable content that exceeds the line measure.
pub const OverflowWrap = enum {
    /// Permit overflow rather than manufacturing an emergency boundary.
    normal,
    /// Use a safe grapheme boundary only after ordinary opportunities fail.
    break_word,
    /// Treat safe grapheme boundaries as ordinary soft opportunities.
    ///
    /// This differs from `break_word` for balanced layout and min-content
    /// measurement even when a greedy line happens to select the same edge.
    anywhere,
};

/// Treatment of collapsible ASCII horizontal whitespace in paragraph layout.
pub const WhiteSpaceCollapse = enum {
    /// Consecutive U+0020/U+0009 atoms form one ordinary blank. Leading,
    /// trailing, and soft-line-edge runs retain source carets but have zero
    /// advance.
    collapse,
    /// Preserve authored advances; ordinary line-edge whitespace may still be
    /// discarded when a soft wrap is selected.
    preserve,
    /// Preserve advances and make every authored blank a soft opportunity,
    /// including consecutive and trailing spaces.
    break_spaces,
};

/// Policy used to choose among otherwise valid soft line boundaries.
///
/// This is intentionally separate from `WrapMode`: wrapping controls whether
/// width may introduce a line at all, while this policy controls how the
/// complete set of safe boundaries is searched.
pub const LineBreakStrategy = enum {
    /// Commit the latest fitting opportunity while scanning source order.
    greedy,
    /// Keep greedy's line count, then minimize whole-segment raggedness over
    /// safe UAX #14, hyphenation, and emergency grapheme boundaries.
    balanced,
};

pub const TextMetrics = struct {
    width: f32,
    height: f32,
    /// Physical block-axis glyph origin of the first line: y horizontally and
    /// x vertically.
    baseline: f32,
    ascent: f32,
    descent: f32,
    leading: f32,
};

pub fn metrics(layout: ParagraphLayout) TextMetrics {
    if (layout.lines.len == 0) {
        return .{
            .width = 0,
            .height = 0,
            .baseline = 0,
            .ascent = 0,
            .descent = 0,
            .leading = 0,
        };
    }
    const first = layout.lines[0];
    return .{
        .width = layout.width,
        .height = layout.height,
        .baseline = if (layout.writing_mode.isVertical())
            first.x + first.baseline
        else
            first.y + first.baseline,
        .ascent = first.ascent,
        .descent = first.descent,
        .leading = first.leading,
    };
}

/// Intrinsic inline-size bounds independent from a chosen container width.
pub const ContentWidths = struct {
    /// Widest fragment when every policy-allowed soft opportunity is taken.
    min: f32,
    /// Widest hard-break segment when no soft opportunity is taken.
    max: f32,
};

/// A laid-out visual line. Glyph and run ranges are indexes into the owning
/// ParagraphLayout arrays, keeping line objects small and cheap to copy.
pub const ParagraphLine = struct {
    glyph_start: usize,
    glyph_len: usize,
    run_start: usize,
    run_len: usize,
    /// Logical UTF-8 source range represented by this visual line.
    ///
    /// Soft wrapping excludes discarded boundary whitespace from the next
    /// line but keeps it in the preceding line's source range. Explicit line
    /// separators are included in the preceding line. A trailing hard break
    /// therefore creates an empty final line at `text.len`.
    byte_start: usize,
    byte_len: usize,
    /// Physical top-left corner of the line/column box.
    x: f32,
    y: f32,
    /// First-line or paragraph-segment inline indentation reserved before
    /// alignment: physical x horizontally and positive-down y vertically.
    indent: f32 = 0,
    /// Physical x and measure of the selected contiguous line fragment.
    region_x: f32 = 0,
    region_width: f32 = 0,
    /// Final alignment selected for this line's inline axis.
    ///
    /// Horizontal reflow resolves paragraph `.start`/`.end` to left/right and
    /// pins tab-ruler lines to logical start. Vertical columns retain
    /// `.start`/`.center`/`.end` because their physical targets are top/center/
    /// bottom. Null is the compatibility sentinel for manually constructed
    /// lines whose post-processing should use paragraph options.
    resolved_alignment: ?TextAlign = null,
    /// Portion of edge glyph advance protruding before the occupied inline box.
    ///
    /// Glyph positions and caret geometry still include this ink. This is
    /// physical left horizontally and top vertically.
    hang_start: f32 = 0,
    /// Portion of edge glyph advance protruding after the occupied inline box.
    ///
    /// This is physical right horizontally and bottom vertically. `width`
    /// reports occupied inline measure horizontally; `height` does so
    /// vertically.
    hang_end: f32 = 0,
    /// Physical line-box width. In a vertical column this is the block size,
    /// not the accumulated glyph advance.
    width: f32,
    /// Full-advance measure requested for a justified soft-wrapped line.
    ///
    /// This remains null for hard-break, terminal, truncated, and naturally
    /// aligned lines. Keeping the target on the selected line lets later
    /// source-level Kashida reshaping run before generic spacing expansion.
    justification_target: ?f32 = null,
    /// Physical line-box height. In a vertical column this is occupied inline
    /// measure after subtracting optical hanging; glyph/caret advances retain
    /// the complete source extent.
    height: f32,
    /// Line-local block-axis glyph origin: distance from top horizontally and
    /// from left vertically.
    baseline: f32,
    ascent: f32,
    descent: f32,
    leading: f32,
    inline_object_start: usize = 0,
    inline_object_len: usize = 0,

    pub fn glyphs(self: ParagraphLine, paragraph: ParagraphLayout) []const GlyphPosition {
        return paragraph.glyphs[self.glyph_start .. self.glyph_start + self.glyph_len];
    }

    pub fn runs(self: ParagraphLine, paragraph: ParagraphLayout) []const CascadeRun {
        return paragraph.runs[self.run_start .. self.run_start + self.run_len];
    }

    pub fn byteEnd(self: ParagraphLine) usize {
        return self.byte_start + self.byte_len;
    }

    pub fn inlineObjects(
        self: ParagraphLine,
        paragraph: ParagraphLayout,
    ) []const inline_object.Positioned {
        return paragraph.inline_objects[self.inline_object_start .. self.inline_object_start + self.inline_object_len];
    }
};

pub const TextPosition = struct {
    glyph_index: usize,
    cluster: usize,
    trailing: bool = false,
};

pub const TextRect = axes.PhysicalRect;

pub const ParagraphLayout = struct {
    glyphs: []const GlyphPosition,
    runs: []const CascadeRun,
    /// Flat owner for each run's normalized fvar coordinate range.
    normalized_variation_coords: []const f32 = &.{},
    lines: []const ParagraphLine,
    inline_objects: []const inline_object.Positioned = &.{},
    /// Selects how public physical rectangles map to inline and block axes.
    writing_mode: pipeline_types.WritingMode = .horizontal_tb,
    width: f32,
    height: f32,

    /// Return the closest glyph caret for a point in paragraph coordinates.
    /// This is midpoint-based along the inline axis: left/right horizontally
    /// and top/bottom vertically.
    pub fn hitTest(self: ParagraphLayout, x: f32, y: f32) TextPosition {
        if (self.lines.len == 0) return .{ .glyph_index = 0, .cluster = 0 };
        const line_index = self.lineIndexAtPoint(x, y);
        const line = self.lines[line_index];
        if (line.glyph_len == 0) return .{ .glyph_index = line.glyph_start, .cluster = 0 };

        const line_bounds = physicalLineRect(line);
        const local_inline =
            axes.inlineCoordinate(self.writing_mode, x, y) -
            axes.inlineStart(self.writing_mode, line_bounds);
        if (local_inline <= 0) {
            const glyph = self.glyphs[line.glyph_start];
            return .{ .glyph_index = line.glyph_start, .cluster = glyph.cluster };
        }

        var pen_inline: f32 = 0;
        const glyph_end = line.glyph_start + line.glyph_len;
        for (self.glyphs[line.glyph_start..glyph_end], line.glyph_start..) |glyph, glyph_index| {
            if (glyph.isInlineObject()) {
                const object = self.inlineObjectAtByte(glyph.cluster) orelse
                    continue;
                if (object.kind == .in_flow) {
                    const object_inline_size =
                        if (self.writing_mode.isVertical())
                            object.height
                        else
                            object.width;
                    const midpoint =
                        pen_inline + object_inline_size / 2;
                    if (local_inline < midpoint) {
                        return .{
                            .glyph_index = glyph_index,
                            .cluster = glyph.cluster,
                        };
                    }
                    if (local_inline < pen_inline + object_inline_size) {
                        return .{
                            .glyph_index = glyph_index,
                            .cluster = glyph.cluster + glyph.source_byte_len,
                            .trailing = true,
                        };
                    }
                }
            }
            const advance = axes.glyphAdvance(self.writing_mode, glyph);
            const midpoint = pen_inline + advance / 2;
            if (local_inline < midpoint) {
                return .{ .glyph_index = glyph_index, .cluster = glyph.cluster };
            }
            if (local_inline < pen_inline + advance) {
                return textPositionAtGlyphTrailingEdge(self, glyph_index);
            }
            pen_inline += advance;
        }

        return textPositionAtGlyphTrailingEdge(self, glyph_end - 1);
    }

    fn inlineObjectAtByte(
        self: ParagraphLayout,
        byte_index: usize,
    ) ?inline_object.Positioned {
        for (self.inline_objects) |object| {
            if (object.byte_index == byte_index) return object;
        }
        return null;
    }

    /// Convert a logical TextPosition back to a zero-inline-size caret
    /// rectangle. Its block extent comes from resolved line metrics, not glyph
    /// bounds, so selections remain stable across mixed glyph shapes.
    pub fn caretRect(self: ParagraphLayout, position: TextPosition) TextRect {
        if (self.lines.len == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const glyph_index = @min(position.glyph_index, self.glyphs.len);
        const line = self.lineForCaret(glyph_index);
        const line_bounds = physicalLineRect(line);
        return axes.caretRect(
            self.writing_mode,
            axes.blockStart(self.writing_mode, line_bounds),
            axes.blockSize(self.writing_mode, line_bounds),
            self.caretInlineInLine(
                line,
                glyph_index,
                position.trailing,
            ),
        );
    }

    pub fn selectionRect(self: ParagraphLayout, start: usize, end: usize) TextRect {
        if (self.lines.len == 0 or start == end) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        var buffer: [32]TextRect = undefined;
        const rects = self.selectionRectsInto(&buffer, start, end);
        if (rects.len == 0) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        var found = false;
        var min_x: f32 = std.math.inf(f32);
        var min_y: f32 = std.math.inf(f32);
        var max_x: f32 = -std.math.inf(f32);
        var max_y: f32 = -std.math.inf(f32);

        for (rects) |rect| {
            min_x = @min(min_x, rect.x);
            min_y = @min(min_y, rect.y);
            max_x = @max(max_x, rect.x + rect.width);
            max_y = @max(max_y, rect.y + rect.height);
            found = true;
        }

        if (!found) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        return .{ .x = min_x, .y = min_y, .width = max_x - min_x, .height = max_y - min_y };
    }

    pub fn selectionRectForBytes(self: ParagraphLayout, byte_start: usize, byte_end: usize) TextRect {
        if (byte_start == byte_end) return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        const start = self.textPositionForCluster(@min(byte_start, byte_end));
        const end = self.textPositionForCluster(@max(byte_start, byte_end));
        return self.selectionRect(
            start.glyph_index + @intFromBool(start.trailing),
            end.glyph_index + @intFromBool(end.trailing),
        );
    }

    pub fn selectionRects(self: ParagraphLayout, allocator: std.mem.Allocator, start: usize, end: usize) ![]TextRect {
        if (self.lines.len == 0 or start == end) return try allocator.alloc(TextRect, 0);
        var rects = std.ArrayList(TextRect).empty;
        errdefer rects.deinit(allocator);
        const range_start = @min(start, end);
        const range_end = @max(start, end);
        for (self.lines) |line| {
            if (selectionRectForLine(self, line, range_start, range_end)) |rect| {
                try rects.append(allocator, rect);
            }
        }
        return try rects.toOwnedSlice(allocator);
    }

    pub fn selectionRectsForBytes(self: ParagraphLayout, allocator: std.mem.Allocator, byte_start: usize, byte_end: usize) ![]TextRect {
        if (byte_start == byte_end) return try allocator.alloc(TextRect, 0);
        const start = self.textPositionForCluster(@min(byte_start, byte_end));
        const end = self.textPositionForCluster(@max(byte_start, byte_end));
        return try self.selectionRects(
            allocator,
            start.glyph_index + @intFromBool(start.trailing),
            end.glyph_index + @intFromBool(end.trailing),
        );
    }

    pub fn selectionRectsInto(self: ParagraphLayout, buffer: []TextRect, start: usize, end: usize) []TextRect {
        if (self.lines.len == 0 or start == end or buffer.len == 0) return buffer[0..0];
        const range_start = @min(start, end);
        const range_end = @max(start, end);
        var count: usize = 0;
        for (self.lines) |line| {
            if (count >= buffer.len) break;
            if (selectionRectForLine(self, line, range_start, range_end)) |rect| {
                buffer[count] = rect;
                count += 1;
            }
        }
        return buffer[0..count];
    }

    pub fn snapToGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var best = clusters[0].byte_start;
        for (clusters) |cluster| {
            const start = cluster.byte_start;
            const end = cluster.byte_start + cluster.byte_len;
            if (byte_pos <= start) {
                best = start;
                break;
            }
            if (byte_pos < end) {
                best = if (byte_pos - start < end - byte_pos) start else end;
                break;
            }
            best = end;
        }
        return self.textPositionForCluster(best);
    }

    pub fn nextGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        for (clusters) |cluster| {
            const end = cluster.byte_start + cluster.byte_len;
            if (end > byte_pos) return self.textPositionForCluster(end);
        }
        return self.textPositionForCluster(clusters[clusters.len - 1].byte_start + clusters[clusters.len - 1].byte_len);
    }

    pub fn previousGraphemeCaret(self: ParagraphLayout, clusters: []const unicode.GraphemeCluster, position: TextPosition) TextPosition {
        if (clusters.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var previous = clusters[0].byte_start;
        for (clusters) |cluster| {
            if (cluster.byte_start >= byte_pos) return self.textPositionForCluster(previous);
            previous = cluster.byte_start;
        }
        return self.textPositionForCluster(previous);
    }

    pub fn snapToWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var best = words[0].byte_start;
        for (words) |word| {
            const start = word.byte_start;
            const end = word.byte_start + word.byte_len;
            if (byte_pos <= start) {
                best = start;
                break;
            }
            if (byte_pos < end) {
                best = if (byte_pos - start < end - byte_pos) start else end;
                break;
            }
            best = end;
        }
        return self.textPositionForCluster(best);
    }

    pub fn nextWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        for (words) |word| {
            const end = word.byte_start + word.byte_len;
            if (end > byte_pos) return self.textPositionForCluster(end);
        }
        return self.textPositionForCluster(words[words.len - 1].byte_start + words[words.len - 1].byte_len);
    }

    pub fn previousWordCaret(self: ParagraphLayout, words: []const unicode.WordSegment, position: TextPosition) TextPosition {
        if (words.len == 0) return position;
        const byte_pos = positionByteOffset(self, position);
        var previous = words[0].byte_start;
        for (words) |word| {
            if (word.byte_start >= byte_pos) return self.textPositionForCluster(previous);
            previous = word.byte_start;
        }
        return self.textPositionForCluster(previous);
    }

    fn lineIndexAtPoint(self: ParagraphLayout, x: f32, y: f32) usize {
        var best_index: usize = 0;
        var best_distance = std.math.inf(f32);
        for (self.lines, 0..) |line, index| {
            const left = if (line.region_width > 0 or
                std.math.isInf(line.region_width))
                line.region_x
            else
                line.x;
            const width = if (line.region_width > 0 or
                std.math.isInf(line.region_width))
                line.region_width
            else
                line.width;
            const right = left + width;
            const bottom = line.y + line.height;
            const dx = if (x < left)
                left - x
            else if (x > right)
                x - right
            else
                0;
            const dy = if (y < line.y)
                line.y - y
            else if (y > bottom)
                y - bottom
            else
                0;
            const distance = dx * dx + dy * dy;
            if (distance < best_distance or
                (distance == best_distance and index > best_index))
            {
                best_distance = distance;
                best_index = index;
            }
        }
        return best_index;
    }

    fn textPositionForCluster(self: ParagraphLayout, cluster: usize) TextPosition {
        if (self.glyphs.len == 0) return .{ .glyph_index = 0, .cluster = cluster };
        var nearest_after_index: ?usize = null;
        var nearest_after_cluster: usize = std.math.maxInt(usize);
        var nearest_before_index: usize = 0;
        var nearest_before_end: usize = 0;
        for (self.glyphs, 0..) |glyph, index| {
            const glyph_start = glyph.cluster;
            const glyph_end = glyph.sourceByteEnd();
            if (cluster == glyph_start) return .{ .glyph_index = index, .cluster = glyph_start };
            if (cluster > glyph_start and cluster < glyph_end) {
                return .{ .glyph_index = index, .cluster = glyph_start, .trailing = cluster - glyph_start >= glyph_end - cluster };
            }
            if (glyph_start > cluster and glyph_start < nearest_after_cluster) {
                nearest_after_index = index;
                nearest_after_cluster = glyph_start;
            }
            if (glyph_end <= cluster and glyph_end >= nearest_before_end) {
                nearest_before_index = index;
                nearest_before_end = glyph_end;
            }
        }
        if (nearest_after_index) |index| {
            return .{ .glyph_index = index, .cluster = self.glyphs[index].cluster };
        }
        return .{ .glyph_index = nearest_before_index, .cluster = cluster, .trailing = true };
    }

    fn lineForCaret(self: ParagraphLayout, glyph_index: usize) ParagraphLine {
        for (self.lines) |line| {
            const line_start = line.glyph_start;
            const line_end = line.glyph_start + line.glyph_len;
            if (glyph_index >= line_start and glyph_index <= line_end) return line;
        }
        return self.lines[self.lines.len - 1];
    }

    fn caretInlineInLine(self: ParagraphLayout, line: ParagraphLine, glyph_index: usize, trailing: bool) f32 {
        var inline_position = axes.inlineStart(
            self.writing_mode,
            physicalLineRect(line),
        );
        const clamped_index = @min(glyph_index, line.glyph_start + line.glyph_len);
        var index = line.glyph_start;
        while (index < clamped_index) : (index += 1) {
            inline_position += axes.glyphAdvance(
                self.writing_mode,
                self.glyphs[index],
            );
        }
        if (trailing and clamped_index < line.glyph_start + line.glyph_len) {
            inline_position += axes.glyphAdvance(
                self.writing_mode,
                self.glyphs[clamped_index],
            );
        }
        return inline_position;
    }
};

pub fn positionByteOffset(
    layout_value: ParagraphLayout,
    position: TextPosition,
) usize {
    if (layout_value.glyphs.len == 0) return position.cluster;
    if (position.glyph_index >= layout_value.glyphs.len) return position.cluster;
    const glyph = layout_value.glyphs[position.glyph_index];
    if (!position.trailing) return glyph.cluster;
    return trailingByteOffsetForGlyph(layout_value, position.glyph_index);
}

pub fn positionForCluster(
    layout_value: ParagraphLayout,
    cluster: usize,
) TextPosition {
    return layout_value.textPositionForCluster(cluster);
}

fn textPositionAtGlyphTrailingEdge(layout_value: ParagraphLayout, glyph_index: usize) TextPosition {
    return .{
        .glyph_index = glyph_index,
        // `TextPosition.cluster` is the byte offset represented by the caret.
        // For a trailing edge this may be beyond the glyph's leading cluster
        // when source metadata folded variation selectors or a GSUB ligature
        // into a single rendered glyph. Keeping the visible hit-test result and
        // the internal byte-offset conversion in sync avoids snapping trailing
        // clicks back to the start of an extended source span.
        .cluster = trailingByteOffsetForGlyph(layout_value, glyph_index),
        .trailing = true,
    };
}

fn trailingByteOffsetForGlyph(layout_value: ParagraphLayout, glyph_index: usize) usize {
    const glyph = layout_value.glyphs[glyph_index];
    const glyph_end = glyph.sourceByteEnd();
    if (glyph_index + 1 < layout_value.glyphs.len) {
        const next_cluster = layout_value.glyphs[glyph_index + 1].cluster;
        if (next_cluster > glyph.cluster) return next_cluster;
    }
    return glyph_end;
}

fn selectionRectForLine(layout_value: ParagraphLayout, line: ParagraphLine, range_start: usize, range_end: usize) ?TextRect {
    const line_start = line.glyph_start;
    const line_end = line.glyph_start + line.glyph_len;
    const overlap_start = @max(range_start, line_start);
    const overlap_end = @min(range_end, line_end);
    if (overlap_start >= overlap_end) return null;

    const inline_start = layout_value.caretInlineInLine(
        line,
        overlap_start,
        false,
    );
    const inline_end = layout_value.caretInlineInLine(
        line,
        overlap_end,
        false,
    );
    return axes.selectionRect(
        layout_value.writing_mode,
        physicalLineRect(line),
        inline_start,
        inline_end,
    );
}

fn physicalLineRect(line: ParagraphLine) TextRect {
    return axes.rect(line.x, line.y, line.width, line.height);
}
