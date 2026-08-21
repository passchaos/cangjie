//! Physical inline-start-to-end caret topology over final grapheme geometry.

const std = @import("std");

const axes = @import("../axes.zig");
const records = @import("records.zig");
const WritingMode =
    @import("../../../shaping/pipeline/types.zig").WritingMode;

pub const Error = error{
    InvalidParagraphLayout,
    OutOfMemory,
};

const Atom = struct {
    inline_start: f32,
    inline_end: f32,
    start_position: records.CaretPosition,
    end_position: records.CaretPosition,
    stable_index: usize,
};

pub fn appendLine(
    allocator: std.mem.Allocator,
    writing_mode: WritingMode,
    spans: []const records.Span,
    graphemes: []const records.Grapheme,
    line: records.Line,
    line_index: usize,
    out: *std.ArrayList(records.VisualCaretStop),
) Error!void {
    var atoms = std.ArrayList(Atom).empty;
    defer atoms.deinit(allocator);
    for (line.spans(spans)) |span| {
        for (span.graphemes(graphemes)) |grapheme| {
            if (!std.math.isFinite(grapheme.inline_position) or
                !std.math.isFinite(grapheme.inline_size) or
                grapheme.inline_size < 0)
            {
                return error.InvalidParagraphLayout;
            }
            const inline_start =
                axes.inlineStart(writing_mode, span.bounds) +
                grapheme.inline_position;
            const start = records.CaretPosition{
                .byte_offset = grapheme.byte_start,
                .affinity = .downstream,
            };
            const end = records.CaretPosition{
                .byte_offset = grapheme.byteEnd(),
                .affinity = .upstream,
            };
            try atoms.append(allocator, .{
                .inline_start = inline_start,
                .inline_end = inline_start + grapheme.inline_size,
                .start_position = if (span.direction == .ltr) start else end,
                .end_position = if (span.direction == .ltr) end else start,
                .stable_index = atoms.items.len,
            });
        }
    }

    if (atoms.items.len == 0) {
        const position = records.CaretPosition{
            .byte_offset = line.byte_start,
            .affinity = .downstream,
        };
        try out.append(allocator, .{
            .line_index = line_index,
            .inline_position = axes.inlineStart(writing_mode, line.bounds),
            .from_start = position,
            .from_end = position,
        });
        return;
    }
    std.sort.heap(Atom, atoms.items, {}, atomLessThan);

    const first = atoms.items[0];
    try out.append(allocator, .{
        .line_index = line_index,
        .inline_position = first.inline_start,
        .from_start = first.start_position,
        .from_end = first.start_position,
    });
    var previous_atom = first;
    for (atoms.items[1..]) |atom| {
        if (previous_atom.inline_end == atom.inline_start) {
            try out.append(allocator, .{
                .line_index = line_index,
                .inline_position = atom.inline_start,
                .from_start = previous_atom.end_position,
                .from_end = atom.start_position,
            });
        } else {
            try out.append(allocator, .{
                .line_index = line_index,
                .inline_position = previous_atom.inline_end,
                .from_start = previous_atom.end_position,
                .from_end = previous_atom.end_position,
            });
            try out.append(allocator, .{
                .line_index = line_index,
                .inline_position = atom.inline_start,
                .from_start = atom.start_position,
                .from_end = atom.start_position,
            });
        }
        previous_atom = atom;
    }
    try out.append(allocator, .{
        .line_index = line_index,
        .inline_position = previous_atom.inline_end,
        .from_start = previous_atom.end_position,
        .from_end = previous_atom.end_position,
    });
}

pub fn next(
    geometry: records.GeometryView,
    current: records.CaretPosition,
) ?records.CaretGeometry {
    return adjacent(geometry, current, true);
}

pub fn previous(
    geometry: records.GeometryView,
    current: records.CaretPosition,
) ?records.CaretGeometry {
    return adjacent(geometry, current, false);
}

pub fn nextWord(
    geometry: records.GeometryView,
    words: []const records.SelectionRange,
    current: records.CaretPosition,
) ?records.CaretGeometry {
    return adjacentWord(geometry, words, current, true);
}

pub fn previousWord(
    geometry: records.GeometryView,
    words: []const records.SelectionRange,
    current: records.CaretPosition,
) ?records.CaretGeometry {
    return adjacentWord(geometry, words, current, false);
}

pub fn nextLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_inline: f32,
) ?records.CaretGeometry {
    return adjacentLine(geometry, current, preferred_inline, true);
}

pub fn previousLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_inline: f32,
) ?records.CaretGeometry {
    return adjacentLine(geometry, current, preferred_inline, false);
}

fn adjacent(
    geometry: records.GeometryView,
    requested: records.CaretPosition,
    forward: bool,
) ?records.CaretGeometry {
    const normalized = @import("interaction.zig").caret(
        geometry,
        requested,
    ) orelse return null;
    const current_index = stopIndex(
        geometry.visual_caret_stops,
        normalized.position,
        normalized.line_index,
    ) orelse return null;
    const target_index = if (forward)
        current_index + 1
    else if (current_index == 0)
        return null
    else
        current_index - 1;
    if (target_index >= geometry.visual_caret_stops.len) return null;
    const target = geometry.visual_caret_stops[target_index];
    if (target.line_index >= geometry.lines.len) return null;
    const line = geometry.lines[target.line_index];
    return .{
        .position = if (forward) target.from_start else target.from_end,
        .line_index = target.line_index,
        .rect = axes.caretRect(
            geometry.writing_mode,
            axes.blockStart(geometry.writing_mode, line.bounds),
            axes.blockSize(geometry.writing_mode, line.bounds),
            target.inline_position,
        ),
    };
}

fn adjacentWord(
    geometry: records.GeometryView,
    words: []const records.SelectionRange,
    requested: records.CaretPosition,
    forward: bool,
) ?records.CaretGeometry {
    const normalized = @import("interaction.zig").caret(
        geometry,
        requested,
    ) orelse return null;
    const current_index = stopIndex(
        geometry.visual_caret_stops,
        normalized.position,
        normalized.line_index,
    ) orelse return null;

    if (forward) {
        var index = current_index + 1;
        while (index < geometry.visual_caret_stops.len) : (index += 1) {
            if (wordStartAtStop(geometry.visual_caret_stops[index], words, true)) |position| {
                return geometryForStop(geometry, index, position);
            }
        }
        return null;
    }
    var index = current_index;
    while (index > 0) {
        index -= 1;
        if (wordStartAtStop(geometry.visual_caret_stops[index], words, false)) |position| {
            return geometryForStop(geometry, index, position);
        }
    }
    return null;
}

fn wordStartAtStop(
    stop: records.VisualCaretStop,
    words: []const records.SelectionRange,
    forward: bool,
) ?records.CaretPosition {
    const candidates = if (forward)
        [_]records.CaretPosition{ stop.from_start, stop.from_end }
    else
        [_]records.CaretPosition{ stop.from_end, stop.from_start };
    for (candidates) |candidate| {
        if (candidate.affinity != .downstream) continue;
        for (words) |word| {
            if (candidate.byte_offset == word.byte_start) return candidate;
        }
    }
    return null;
}

fn geometryForStop(
    geometry: records.GeometryView,
    stop_index: usize,
    position: records.CaretPosition,
) ?records.CaretGeometry {
    if (stop_index >= geometry.visual_caret_stops.len) return null;
    const stop = geometry.visual_caret_stops[stop_index];
    if (stop.line_index >= geometry.lines.len) return null;
    const line = geometry.lines[stop.line_index];
    return .{
        .position = position,
        .line_index = stop.line_index,
        .rect = axes.caretRect(
            geometry.writing_mode,
            axes.blockStart(geometry.writing_mode, line.bounds),
            axes.blockSize(geometry.writing_mode, line.bounds),
            stop.inline_position,
        ),
    };
}

fn adjacentLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_inline: f32,
    forward: bool,
) ?records.CaretGeometry {
    if (!std.math.isFinite(preferred_inline)) return null;
    const normalized = @import("interaction.zig").caret(
        geometry,
        current,
    ) orelse return null;
    const target_line_index = if (forward)
        normalized.line_index + 1
    else if (normalized.line_index == 0)
        return null
    else
        normalized.line_index - 1;
    if (target_line_index >= geometry.lines.len) return null;
    const line = geometry.lines[target_line_index];
    const stops = line.visualCaretStops(geometry.visual_caret_stops);
    if (stops.len == 0) return null;

    var best_index: usize = 0;
    var best_distance =
        @abs(preferred_inline - stops[0].inline_position);
    for (stops[1..], 1..) |stop, index| {
        const distance =
            @abs(preferred_inline - stop.inline_position);
        if (distance < best_distance or
            (distance == best_distance and
                stop.inline_position >=
                    stops[best_index].inline_position))
        {
            best_index = index;
            best_distance = distance;
        }
    }
    const stop = stops[best_index];
    return .{
        .position = if (preferred_inline < stop.inline_position)
            stop.from_start
        else
            stop.from_end,
        .line_index = target_line_index,
        .rect = axes.caretRect(
            geometry.writing_mode,
            axes.blockStart(geometry.writing_mode, line.bounds),
            axes.blockSize(geometry.writing_mode, line.bounds),
            stop.inline_position,
        ),
    };
}

fn stopIndex(
    stops: []const records.VisualCaretStop,
    position: records.CaretPosition,
    line_index: usize,
) ?usize {
    for (stops, 0..) |stop, index| {
        if (stop.line_index != line_index) continue;
        if (positionsEqual(stop.from_start, position) or
            positionsEqual(stop.from_end, position))
        {
            return index;
        }
    }
    return null;
}

fn positionsEqual(
    lhs: records.CaretPosition,
    rhs: records.CaretPosition,
) bool {
    return lhs.byte_offset == rhs.byte_offset and lhs.affinity == rhs.affinity;
}

fn atomLessThan(_: void, lhs: Atom, rhs: Atom) bool {
    if (lhs.inline_start != rhs.inline_start) return lhs.inline_start < rhs.inline_start;
    if (lhs.inline_end != rhs.inline_end) return lhs.inline_end < rhs.inline_end;
    return lhs.stable_index < rhs.stable_index;
}
