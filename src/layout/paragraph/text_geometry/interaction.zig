//! Source-affinity caret resolution and paragraph-space hit testing.

const std = @import("std");

const axes = @import("../axes.zig");
const records = @import("records.zig");

const CaretGeometry = records.CaretGeometry;
const CaretPosition = records.CaretPosition;
const Grapheme = records.Grapheme;

pub const View = records.GeometryView;

const LocatedGrapheme = struct {
    span_index: usize,
    grapheme: Grapheme,
};

pub fn caret(geometry: View, requested: CaretPosition) ?CaretGeometry {
    if (requested.byte_offset > geometry.source_byte_len or
        geometry.lines.len == 0)
    {
        return null;
    }

    if (requested.affinity == .downstream) {
        if (graphemeStartingAt(geometry, requested.byte_offset)) |found| {
            return caretForGrapheme(
                geometry,
                found.span_index,
                found.grapheme,
                false,
            );
        }
        if (emptyLineStartingAt(geometry, requested.byte_offset)) |line_index| {
            return emptyLineCaret(
                geometry,
                line_index,
                .{ .byte_offset = requested.byte_offset },
            );
        }
        if (requested.byte_offset == geometry.source_byte_len) {
            if (graphemeEndingAt(geometry, requested.byte_offset)) |found| {
                return caretForGrapheme(
                    geometry,
                    found.span_index,
                    found.grapheme,
                    true,
                );
            }
        }
        return null;
    }

    if (graphemeEndingAt(geometry, requested.byte_offset)) |found| {
        return caretForGrapheme(
            geometry,
            found.span_index,
            found.grapheme,
            true,
        );
    }
    if (requested.byte_offset == 0) {
        if (graphemeStartingAt(geometry, 0)) |found| {
            return caretForGrapheme(
                geometry,
                found.span_index,
                found.grapheme,
                false,
            );
        }
        if (emptyLineStartingAt(geometry, 0)) |line_index| {
            return emptyLineCaret(
                geometry,
                line_index,
                .{ .byte_offset = 0 },
            );
        }
    }
    return null;
}

pub fn hitTest(geometry: View, x: f32, y: f32) ?CaretGeometry {
    if (geometry.lines.len == 0) return null;
    const line_index = lineIndexAtPoint(geometry, x, y);
    const line = geometry.lines[line_index];
    var best: ?struct {
        span_index: usize,
        grapheme: Grapheme,
        inline_start: f32,
        distance: f32,
    } = null;
    const point_inline =
        axes.inlineCoordinate(geometry.writing_mode, x, y);

    for (
        geometry.spans[line.span_start .. line.span_start + line.span_len],
        line.span_start..,
    ) |span, span_index| {
        for (span.graphemes(geometry.graphemes)) |grapheme| {
            if (!std.math.isFinite(grapheme.inline_size) or grapheme.inline_size < 0) {
                continue;
            }
            const inline_start =
                axes.inlineStart(geometry.writing_mode, span.bounds) +
                grapheme.inline_position;
            const inline_end = inline_start + grapheme.inline_size;
            const distance = if (point_inline < inline_start)
                inline_start - point_inline
            else if (point_inline > inline_end)
                point_inline - inline_end
            else
                0;
            // At an exact shared boundary prefer the positive-inline-size
            // grapheme after the point. This makes an LTR internal ligature
            // caret round-trip as downstream while zero-size controls remain
            // hittable only when no visible neighbor is closer.
            const prefer_boundary_successor =
                best != null and
                distance == best.?.distance and
                point_inline == inline_start and
                best.?.grapheme.inline_size > 0 and
                grapheme.inline_size > 0;
            if (best == null or distance < best.?.distance or
                prefer_boundary_successor)
            {
                best = .{
                    .span_index = span_index,
                    .grapheme = grapheme,
                    .inline_start = inline_start,
                    .distance = distance,
                };
            }
        }
    }

    const found = best orelse return emptyLineCaret(
        geometry,
        line_index,
        .{
            .byte_offset = line.byte_start,
            .affinity = .downstream,
        },
    );
    const trailing_physical =
        point_inline >
        found.inline_start + found.grapheme.inline_size / 2;
    const span = geometry.spans[found.span_index];
    const logical_end = switch (span.direction) {
        .ltr => trailing_physical,
        .rtl => !trailing_physical,
    };
    return caretForGrapheme(
        geometry,
        found.span_index,
        found.grapheme,
        logical_end,
    );
}

fn graphemeStartingAt(
    geometry: View,
    byte_offset: usize,
) ?LocatedGrapheme {
    for (geometry.spans, 0..) |span, span_index| {
        if (byte_offset < span.byte_start or
            byte_offset >= span.byteEnd()) continue;
        for (span.graphemes(geometry.graphemes)) |grapheme| {
            if (grapheme.byte_start == byte_offset) {
                return .{
                    .span_index = span_index,
                    .grapheme = grapheme,
                };
            }
        }
    }
    return null;
}

fn graphemeEndingAt(
    geometry: View,
    byte_offset: usize,
) ?LocatedGrapheme {
    var found: ?LocatedGrapheme = null;
    for (geometry.spans, 0..) |span, span_index| {
        if (byte_offset <= span.byte_start or
            byte_offset > span.byteEnd()) continue;
        for (span.graphemes(geometry.graphemes)) |grapheme| {
            if (grapheme.byteEnd() == byte_offset) {
                found = .{
                    .span_index = span_index,
                    .grapheme = grapheme,
                };
            }
        }
    }
    return found;
}

fn caretForGrapheme(
    geometry: View,
    span_index: usize,
    grapheme: Grapheme,
    logical_end: bool,
) CaretGeometry {
    const span = geometry.spans[span_index];
    const inline_start =
        axes.inlineStart(geometry.writing_mode, span.bounds) +
        grapheme.inline_position;
    const inline_position = switch (span.direction) {
        .ltr => if (logical_end)
            inline_start + grapheme.inline_size
        else
            inline_start,
        .rtl => if (logical_end)
            inline_start
        else
            inline_start + grapheme.inline_size,
    };
    return .{
        .position = .{
            .byte_offset = if (logical_end)
                grapheme.byteEnd()
            else
                grapheme.byte_start,
            .affinity = if (logical_end) .upstream else .downstream,
        },
        .line_index = span.line_index,
        .rect = axes.caretRect(
            geometry.writing_mode,
            axes.blockStart(geometry.writing_mode, span.bounds),
            axes.blockSize(geometry.writing_mode, span.bounds),
            inline_position,
        ),
    };
}

fn emptyLineStartingAt(geometry: View, byte_offset: usize) ?usize {
    for (geometry.lines, 0..) |line, line_index| {
        if (line.span_len == 0 and line.byte_start == byte_offset) {
            return line_index;
        }
    }
    return null;
}

fn emptyLineCaret(
    geometry: View,
    line_index: usize,
    position: CaretPosition,
) CaretGeometry {
    const line = geometry.lines[line_index];
    return .{
        .position = position,
        .line_index = line_index,
        .rect = axes.caretRect(
            geometry.writing_mode,
            axes.blockStart(geometry.writing_mode, line.bounds),
            axes.blockSize(geometry.writing_mode, line.bounds),
            axes.inlineStart(geometry.writing_mode, line.bounds),
        ),
    };
}

fn lineIndexAtPoint(geometry: View, x: f32, y: f32) usize {
    var best_index: usize = 0;
    var best_distance = std.math.inf(f32);
    for (geometry.lines, 0..) |line, line_index| {
        const left = line.bounds.x;
        const right = left + line.bounds.width;
        const bottom = line.bounds.y + line.bounds.height;
        const dx = if (x < left)
            left - x
        else if (x > right)
            x - right
        else
            0;
        const dy = if (y < line.bounds.y)
            line.bounds.y - y
        else if (y > bottom)
            y - bottom
        else
            0;
        const distance = dx * dx + dy * dy;
        const inside_empty_line_block_band =
            if (geometry.writing_mode.isVertical()) dx == 0 else dy == 0;
        if (line.span_len == 0 and inside_empty_line_block_band) {
            return line_index;
        }
        if (distance < best_distance or
            (distance == best_distance and line_index > best_index))
        {
            best_distance = distance;
            best_index = line_index;
        }
    }
    return best_index;
}
