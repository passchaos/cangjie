//! Allocation-free range transformation for text-document replacements.
//!
//! This module deliberately knows nothing about font or UI style payloads. Any
//! value with mutable `start` and `end` byte offsets can be transformed. The
//! complete input, edit, ordering, output capacity, and arithmetic are checked
//! before the first write, so callers may safely use overlapping or identical
//! input/output storage and failures leave output untouched.

const std = @import("std");

pub const Error = error{
    InvalidEdit,
    InvalidSpan,
    UnorderedSpans,
    NoSpaceLeft,
    Overflow,
};

pub const Edit = struct {
    document_len: usize,
    start: usize,
    old_end: usize,
    new_len: usize,

    pub fn removedLen(self: Edit) usize {
        return self.old_end - self.start;
    }

    pub fn nextDocumentLen(self: Edit) Error!usize {
        if (self.start > self.old_end or self.old_end > self.document_len) return error.InvalidEdit;
        return std.math.add(usize, self.document_len - self.removedLen(), self.new_len) catch error.Overflow;
    }
};

pub const Options = struct {
    /// Validate monotonic `(start, end)` ordering. Overlap remains legal because
    /// input order can encode precedence in attributed-text clients.
    require_ordered: bool = true,
};

pub const Result = struct {
    len: usize,
    changed: bool,
    removed: usize,
};

/// Return the exact number of surviving records without modifying storage.
pub fn transformedCount(spans: anytype, edit: Edit, options: Options) Error!usize {
    _ = try edit.nextDocumentLen();
    const Span = std.meta.Elem(@TypeOf(spans));
    assertSpanType(Span);
    var previous_start: usize = 0;
    var previous_end: usize = 0;
    var count: usize = 0;
    for (spans, 0..) |span, index| {
        const start = span.start;
        const end = span.end;
        if (start >= end or end > edit.document_len) return error.InvalidSpan;
        if (options.require_ordered and index != 0 and
            (start < previous_start or (start == previous_start and end < previous_end))) return error.UnorderedSpans;
        previous_start = start;
        previous_end = end;
        if (!fullyRemoved(start, end, edit)) count += 1;
        _ = try mappedRange(start, end, edit);
    }
    return count;
}

/// Transform ranges after replacing `[edit.start, edit.old_end)` with
/// `edit.new_len` bytes. Existing spans that strictly contain an insertion or
/// replacement inherit its new bytes. Spans touching only an edit boundary do
/// not inherit; callers may append an explicit insertion style if desired.
///
/// The returned slice aliases `out`. `out` may be the same storage as `spans`.
pub fn transform(comptime Span: type, spans: []const Span, out: []Span, edit: Edit, options: Options) Error!Result {
    assertSpanType(Span);
    const required = try transformedCount(spans, edit, options);
    if (out.len < required) return error.NoSpaceLeft;

    var write: usize = 0;
    var changed = false;
    for (spans) |source| {
        const mapped = (try mappedRange(source.start, source.end, edit)) orelse {
            changed = true;
            continue;
        };
        var span = source;
        if (span.start != mapped.start or span.end != mapped.end) changed = true;
        span.start = mapped.start;
        span.end = mapped.end;
        out[write] = span;
        write += 1;
    }
    return .{ .len = write, .changed = changed, .removed = spans.len - write };
}

const Range = struct { start: usize, end: usize };

fn mappedRange(start: usize, end: usize, edit: Edit) Error!?Range {
    const removed_len = edit.removedLen();
    if (end <= edit.start) return .{ .start = start, .end = end };
    if (start >= edit.old_end) {
        return .{
            .start = try shift(start, removed_len, edit.new_len),
            .end = try shift(end, removed_len, edit.new_len),
        };
    }
    if (start < edit.start and end > edit.old_end) {
        return .{ .start = start, .end = try shift(end, removed_len, edit.new_len) };
    }
    if (start < edit.start and end > edit.start) return .{ .start = start, .end = edit.start };
    if (start < edit.old_end and end > edit.old_end) {
        return .{
            .start = std.math.add(usize, edit.start, edit.new_len) catch return error.Overflow,
            .end = try shift(end, removed_len, edit.new_len),
        };
    }
    return null;
}

fn fullyRemoved(start: usize, end: usize, edit: Edit) bool {
    if (end <= edit.start or start >= edit.old_end) return false;
    return start >= edit.start and end <= edit.old_end;
}

fn shift(value: usize, removed_len: usize, new_len: usize) Error!usize {
    std.debug.assert(value >= removed_len);
    return std.math.add(usize, value - removed_len, new_len) catch error.Overflow;
}

fn assertSpanType(comptime Span: type) void {
    comptime {
        if (!@hasField(Span, "start") or !@hasField(Span, "end"))
            @compileError("span type must expose start and end fields");
        if (@FieldType(Span, "start") != usize or @FieldType(Span, "end") != usize)
            @compileError("span start and end fields must both be usize");
    }
}

const TestSpan = struct {
    start: usize,
    end: usize,
    tag: u8,
};

test "document span transform truncates removes shifts and preserves payload" {
    const spans = [_]TestSpan{
        .{ .start = 0, .end = 2, .tag = 1 },
        .{ .start = 1, .end = 9, .tag = 2 },
        .{ .start = 3, .end = 5, .tag = 3 },
        .{ .start = 4, .end = 8, .tag = 4 },
        .{ .start = 7, .end = 10, .tag = 5 },
        .{ .start = 9, .end = 12, .tag = 6 },
    };
    var out: [spans.len]TestSpan = undefined;
    const result = try transform(TestSpan, &spans, &out, .{ .document_len = 12, .start = 3, .old_end = 9, .new_len = 2 }, .{});
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(@as(usize, 2), result.removed);
    try std.testing.expect(result.changed);
    try std.testing.expectEqualSlices(TestSpan, &.{
        .{ .start = 0, .end = 2, .tag = 1 },
        .{ .start = 1, .end = 3, .tag = 2 },
        .{ .start = 5, .end = 6, .tag = 5 },
        .{ .start = 5, .end = 8, .tag = 6 },
    }, out[0..result.len]);
}

test "document span transform insertion inherits only strict containment" {
    var spans = [_]TestSpan{
        .{ .start = 0, .end = 2, .tag = 1 },
        .{ .start = 0, .end = 4, .tag = 2 },
        .{ .start = 2, .end = 4, .tag = 3 },
    };
    const result = try transform(TestSpan, &spans, &spans, .{ .document_len = 4, .start = 2, .old_end = 2, .new_len = 3 }, .{});
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualSlices(TestSpan, &.{
        .{ .start = 0, .end = 2, .tag = 1 },
        .{ .start = 0, .end = 7, .tag = 2 },
        .{ .start = 5, .end = 7, .tag = 3 },
    }, spans[0..result.len]);
}

test "document span transform validates atomically before in-place writes" {
    var unordered = [_]TestSpan{
        .{ .start = 4, .end = 6, .tag = 1 },
        .{ .start = 2, .end = 3, .tag = 2 },
    };
    const before = unordered;
    try std.testing.expectError(error.UnorderedSpans, transform(TestSpan, &unordered, &unordered, .{ .document_len = 8, .start = 1, .old_end = 2, .new_len = 0 }, .{}));
    try std.testing.expectEqualSlices(TestSpan, &before, &unordered);

    var short: [1]TestSpan = undefined;
    const two = [_]TestSpan{ .{ .start = 0, .end = 1, .tag = 1 }, .{ .start = 2, .end = 3, .tag = 2 } };
    try std.testing.expectError(error.NoSpaceLeft, transform(TestSpan, &two, &short, .{ .document_len = 4, .start = 1, .old_end = 1, .new_len = 1 }, .{}));
    try std.testing.expectError(error.InvalidEdit, transformedCount(&two, .{ .document_len = 1, .start = 0, .old_end = 2, .new_len = 0 }, .{}));
    try std.testing.expectError(error.InvalidSpan, transformedCount(&two, .{ .document_len = 2, .start = 0, .old_end = 0, .new_len = 0 }, .{}));
}

test "document span transform supports unordered precedence" {
    const spans = [_]TestSpan{
        .{ .start = 4, .end = 8, .tag = 1 },
        .{ .start = 0, .end = 10, .tag = 2 },
    };
    var out: [2]TestSpan = undefined;
    const result = try transform(TestSpan, &spans, &out, .{ .document_len = 10, .start = 2, .old_end = 6, .new_len = 1 }, .{ .require_ordered = false });
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u8, 1), out[0].tag);
    try std.testing.expectEqual(@as(usize, 3), out[0].start);
    try std.testing.expectEqual(@as(usize, 5), out[0].end);
    try std.testing.expectEqual(@as(usize, 0), out[1].start);
    try std.testing.expectEqual(@as(usize, 7), out[1].end);
}
