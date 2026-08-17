//! Source-affinity caret resolution and paragraph-space hit testing.

const std = @import("std");

const records = @import("records.zig");

const CaretGeometry = records.CaretGeometry;
const CaretPosition = records.CaretPosition;
const Grapheme = records.Grapheme;

pub const View = struct {
    source_byte_len: usize,
    lines: []const records.Line,
    spans: []const records.Span,
    graphemes: []const Grapheme,
};

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
    const line_index = lineIndexAtY(geometry, y);
    const line = geometry.lines[line_index];
    var best: ?struct {
        span_index: usize,
        grapheme: Grapheme,
        left: f32,
        distance: f32,
    } = null;

    for (
        geometry.spans[line.span_start .. line.span_start + line.span_len],
        line.span_start..,
    ) |span, span_index| {
        for (span.graphemes(geometry.graphemes)) |grapheme| {
            if (!std.math.isFinite(grapheme.width) or grapheme.width < 0) {
                continue;
            }
            const left = span.bounds.x + grapheme.inline_position;
            const right = left + grapheme.width;
            const distance = if (x < left)
                left - x
            else if (x > right)
                x - right
            else
                0;
            // At an exact shared boundary prefer the positive-width grapheme
            // on the point's right. This makes an LTR internal ligature caret
            // round-trip as downstream while zero-width controls remain
            // hittable only when no visible neighbor is closer.
            const prefer_boundary_successor =
                best != null and
                distance == best.?.distance and
                x == left and
                best.?.grapheme.width > 0 and
                grapheme.width > 0;
            if (best == null or distance < best.?.distance or
                prefer_boundary_successor)
            {
                best = .{
                    .span_index = span_index,
                    .grapheme = grapheme,
                    .left = left,
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
        x > found.left + found.grapheme.width / 2;
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
    const left = span.bounds.x + grapheme.inline_position;
    const x = switch (span.direction) {
        .ltr => if (logical_end) left + grapheme.width else left,
        .rtl => if (logical_end) left else left + grapheme.width,
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
        .rect = .{
            .x = x,
            .y = span.bounds.y,
            .width = 0,
            .height = span.bounds.height,
        },
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
        .rect = .{
            .x = line.bounds.x,
            .y = line.bounds.y,
            .width = 0,
            .height = line.bounds.height,
        },
    };
}

fn lineIndexAtY(geometry: View, y: f32) usize {
    if (y <= geometry.lines[0].bounds.y) return 0;
    for (geometry.lines, 0..) |line, line_index| {
        if (y < line.bounds.y + line.bounds.height) return line_index;
    }
    return geometry.lines.len - 1;
}
