//! Logical UTF-8 selection ranges mapped to visual line fragments.

const std = @import("std");

const records = @import("records.zig");

pub const Error = error{
    InvalidTextRange,
    OutOfMemory,
};

const Interval = struct {
    line_index: usize,
    left: f32,
    right: f32,
};

pub fn build(
    allocator: std.mem.Allocator,
    geometry: records.GeometryView,
    range: records.SelectionRange,
) Error![]records.SelectionFragment {
    try validateRange(geometry, range);
    if (range.byte_start == range.byte_end) {
        return allocator.alloc(records.SelectionFragment, 0);
    }

    var intervals = std.ArrayList(Interval).empty;
    defer intervals.deinit(allocator);
    for (geometry.spans) |span| {
        if (span.byteEnd() <= range.byte_start or
            span.byte_start >= range.byte_end)
        {
            continue;
        }
        for (span.graphemes(geometry.graphemes)) |grapheme| {
            if (grapheme.byte_start < range.byte_start or
                grapheme.byteEnd() > range.byte_end)
            {
                continue;
            }
            const left = span.bounds.x + grapheme.inline_position;
            if (!std.math.isFinite(left) or
                !std.math.isFinite(grapheme.width) or
                grapheme.width < 0)
            {
                return error.InvalidTextRange;
            }
            try intervals.append(allocator, .{
                .line_index = span.line_index,
                .left = left,
                .right = left + grapheme.width,
            });
        }
    }
    std.sort.heap(Interval, intervals.items, {}, intervalLessThan);

    var fragments = std.ArrayList(records.SelectionFragment).empty;
    errdefer fragments.deinit(allocator);
    var index: usize = 0;
    while (index < intervals.items.len) {
        const first = intervals.items[index];
        if (first.line_index >= geometry.lines.len) {
            return error.InvalidTextRange;
        }
        const left = first.left;
        var right = first.right;
        index += 1;
        while (index < intervals.items.len and
            intervals.items[index].line_index == first.line_index and
            intervals.items[index].left <= right)
        {
            right = @max(right, intervals.items[index].right);
            index += 1;
        }
        const line = geometry.lines[first.line_index];
        try fragments.append(allocator, .{
            .line_index = first.line_index,
            .rect = .{
                .x = left,
                .y = line.bounds.y,
                .width = @max(0, right - left),
                .height = line.bounds.height,
            },
        });
    }
    return fragments.toOwnedSlice(allocator);
}

fn validateRange(
    geometry: records.GeometryView,
    range: records.SelectionRange,
) Error!void {
    if (range.byte_start > range.byte_end or
        range.byte_end > geometry.source_byte_len)
    {
        return error.InvalidTextRange;
    }
    if (range.byte_start == range.byte_end) {
        if (!isBoundary(geometry, range.byte_start)) {
            return error.InvalidTextRange;
        }
        return;
    }

    var cursor = range.byte_start;
    for (geometry.graphemes) |grapheme| {
        if (grapheme.byteEnd() <= range.byte_start) continue;
        if (grapheme.byte_start >= range.byte_end) break;
        if (grapheme.byte_start != cursor or
            grapheme.byteEnd() > range.byte_end)
        {
            return error.InvalidTextRange;
        }
        cursor = grapheme.byteEnd();
    }
    if (cursor != range.byte_end) return error.InvalidTextRange;
}

fn isBoundary(geometry: records.GeometryView, byte_offset: usize) bool {
    if (byte_offset > geometry.source_byte_len) return false;
    for (geometry.graphemes) |grapheme| {
        if (grapheme.byte_start == byte_offset or
            grapheme.byteEnd() == byte_offset)
        {
            return true;
        }
    }
    for (geometry.lines) |line| {
        if (line.byte_start == byte_offset or line.byteEnd() == byte_offset) {
            return true;
        }
    }
    return false;
}

fn intervalLessThan(_: void, lhs: Interval, rhs: Interval) bool {
    if (lhs.line_index != rhs.line_index) {
        return lhs.line_index < rhs.line_index;
    }
    if (lhs.left != rhs.left) return lhs.left < rhs.left;
    return lhs.right < rhs.right;
}
