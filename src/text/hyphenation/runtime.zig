//! UTF-8 Liang-pattern matching.

const std = @import("std");
const model = @import("model.zig");

pub fn hyphenate(
    storage: *const model.Storage,
    allocator: std.mem.Allocator,
    word: []const u8,
    out: *std.ArrayList(usize),
) (std.mem.Allocator.Error || error{InvalidUtf8})!void {
    out.clearRetainingCapacity();
    if (!std.unicode.utf8ValidateSlice(word)) return error.InvalidUtf8;
    if (word.len == 0) return;

    var scalars = std.ArrayList(u21).empty;
    defer scalars.deinit(allocator);
    var byte_offsets = std.ArrayList(usize).empty;
    defer byte_offsets.deinit(allocator);
    try byte_offsets.append(allocator, 0);
    var iterator = std.unicode.Utf8Iterator{ .bytes = word, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        try scalars.append(
            allocator,
            model.normalizedCodepoint(storage.mappings, codepoint),
        );
        try byte_offsets.append(allocator, iterator.i);
    }
    if (scalars.items.len == 0) return;

    if (findException(storage, scalars.items)) |exception| {
        for (exception.boundaries) |boundary| {
            const index: usize = boundary;
            if (!allowedBoundary(storage, index, scalars.items.len)) continue;
            try out.append(allocator, byte_offsets.items[index]);
        }
        return;
    }

    const extended_len = scalars.items.len + 2;
    const extended = try allocator.alloc(u21, extended_len);
    defer allocator.free(extended);
    extended[0] = '.';
    @memcpy(extended[1 .. extended.len - 1], scalars.items);
    extended[extended.len - 1] = '.';

    const scores = try allocator.alloc(u8, extended_len + 1);
    defer allocator.free(scores);
    @memset(scores, 0);

    for (0..extended.len) |start| {
        var node_index: u32 = 0;
        var cursor = start;
        while (cursor < extended.len) : (cursor += 1) {
            const edge = model.findEdge(
                storage.nodes.items[node_index].edges.items,
                extended[cursor],
            ) orelse break;
            node_index = edge.child;
            for (storage.nodes.items[node_index].weights.items) |weight| {
                const score_index = start + weight.position;
                if (score_index < scores.len) {
                    scores[score_index] =
                        @max(scores[score_index], weight.value);
                }
            }
        }
    }

    for (1..scalars.items.len) |boundary| {
        if (!allowedBoundary(storage, boundary, scalars.items.len)) continue;
        // The leading boundary marker occupies extended scalar 0, so the score
        // between source scalars N-1/N is at extended gap N+1.
        if (scores[boundary + 1] & 1 == 0) continue;
        try out.append(allocator, byte_offsets.items[boundary]);
    }
}

fn allowedBoundary(
    storage: *const model.Storage,
    boundary: usize,
    scalar_count: usize,
) bool {
    return boundary >= storage.left_min and
        scalar_count - boundary >= storage.right_min;
}

fn findException(
    storage: *const model.Storage,
    word: []const u21,
) ?model.Exception {
    var low: usize = 0;
    var high: usize = storage.exceptions.items.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        switch (model.scalarSliceOrder(
            word,
            storage.exceptions.items[mid].word,
        )) {
            .lt => high = mid,
            .gt => low = mid + 1,
            .eq => return storage.exceptions.items[mid],
        }
    }
    return null;
}
