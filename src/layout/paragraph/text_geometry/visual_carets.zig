//! Left-to-right visual caret topology over final grapheme geometry.

const std = @import("std");

const records = @import("records.zig");

pub const Error = error{
    InvalidParagraphLayout,
    OutOfMemory,
};

const Atom = struct {
    left: f32,
    right: f32,
    left_position: records.CaretPosition,
    right_position: records.CaretPosition,
    stable_index: usize,
};

pub fn appendLine(
    allocator: std.mem.Allocator,
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
                !std.math.isFinite(grapheme.width) or
                grapheme.width < 0)
            {
                return error.InvalidParagraphLayout;
            }
            const left = span.bounds.x + grapheme.inline_position;
            const start = records.CaretPosition{
                .byte_offset = grapheme.byte_start,
                .affinity = .downstream,
            };
            const end = records.CaretPosition{
                .byte_offset = grapheme.byteEnd(),
                .affinity = .upstream,
            };
            try atoms.append(allocator, .{
                .left = left,
                .right = left + grapheme.width,
                .left_position = if (span.direction == .ltr) start else end,
                .right_position = if (span.direction == .ltr) end else start,
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
            .x = line.bounds.x,
            .from_left = position,
            .from_right = position,
        });
        return;
    }
    std.sort.heap(Atom, atoms.items, {}, atomLessThan);

    const first = atoms.items[0];
    try out.append(allocator, .{
        .line_index = line_index,
        .x = first.left,
        .from_left = first.left_position,
        .from_right = first.left_position,
    });
    var previous_atom = first;
    for (atoms.items[1..]) |atom| {
        if (previous_atom.right == atom.left) {
            try out.append(allocator, .{
                .line_index = line_index,
                .x = atom.left,
                .from_left = previous_atom.right_position,
                .from_right = atom.left_position,
            });
        } else {
            try out.append(allocator, .{
                .line_index = line_index,
                .x = previous_atom.right,
                .from_left = previous_atom.right_position,
                .from_right = previous_atom.right_position,
            });
            try out.append(allocator, .{
                .line_index = line_index,
                .x = atom.left,
                .from_left = atom.left_position,
                .from_right = atom.left_position,
            });
        }
        previous_atom = atom;
    }
    try out.append(allocator, .{
        .line_index = line_index,
        .x = previous_atom.right,
        .from_left = previous_atom.right_position,
        .from_right = previous_atom.right_position,
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

pub fn nextLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_x: f32,
) ?records.CaretGeometry {
    return adjacentLine(geometry, current, preferred_x, true);
}

pub fn previousLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_x: f32,
) ?records.CaretGeometry {
    return adjacentLine(geometry, current, preferred_x, false);
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
        .position = if (forward) target.from_left else target.from_right,
        .line_index = target.line_index,
        .rect = .{
            .x = target.x,
            .y = line.bounds.y,
            .width = 0,
            .height = line.bounds.height,
        },
    };
}

fn adjacentLine(
    geometry: records.GeometryView,
    current: records.CaretPosition,
    preferred_x: f32,
    forward: bool,
) ?records.CaretGeometry {
    if (!std.math.isFinite(preferred_x)) return null;
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
    var best_distance = @abs(preferred_x - stops[0].x);
    for (stops[1..], 1..) |stop, index| {
        const distance = @abs(preferred_x - stop.x);
        if (distance < best_distance or
            (distance == best_distance and stop.x >= stops[best_index].x))
        {
            best_index = index;
            best_distance = distance;
        }
    }
    const stop = stops[best_index];
    return .{
        .position = if (preferred_x < stop.x)
            stop.from_left
        else
            stop.from_right,
        .line_index = target_line_index,
        .rect = .{
            .x = stop.x,
            .y = line.bounds.y,
            .width = 0,
            .height = line.bounds.height,
        },
    };
}

fn stopIndex(
    stops: []const records.VisualCaretStop,
    position: records.CaretPosition,
    line_index: usize,
) ?usize {
    for (stops, 0..) |stop, index| {
        if (stop.line_index != line_index) continue;
        if (positionsEqual(stop.from_left, position) or
            positionsEqual(stop.from_right, position))
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
    if (lhs.left != rhs.left) return lhs.left < rhs.left;
    if (lhs.right != rhs.right) return lhs.right < rhs.right;
    return lhs.stable_index < rhs.stable_index;
}
