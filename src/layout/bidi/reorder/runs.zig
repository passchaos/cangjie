//! Font-run ownership rebuilt after glyph permutation.

const std = @import("std");

pub const no_run = std.math.maxInt(usize);

pub fn buildGlyphRunIndices(
    allocator: std.mem.Allocator,
    runs: anytype,
    glyph_count: usize,
) ![]usize {
    var indices = std.ArrayList(usize).empty;
    errdefer indices.deinit(allocator);
    try buildGlyphRunIndicesInto(
        allocator,
        &indices,
        runs,
        glyph_count,
    );
    return try indices.toOwnedSlice(allocator);
}

pub fn buildGlyphRunIndicesInto(
    allocator: std.mem.Allocator,
    indices: *std.ArrayList(usize),
    font_runs: anytype,
    glyph_count: usize,
) !void {
    indices.clearRetainingCapacity();
    try indices.resize(allocator, glyph_count);
    // Synthetic inline objects and future non-font atoms deliberately remain
    // unowned. A sentinel prevents bidi permutation from borrowing the nearest
    // font and later exposing a fake `.notdef` render request.
    @memset(indices.items, no_run);
    for (font_runs, 0..) |run, run_index| {
        const end = @min(glyph_count, run.glyph_start + run.glyph_len);
        if (run.glyph_start >= end) continue;
        @memset(indices.items[run.glyph_start..end], run_index);
    }
}

pub fn rebuild(
    buffer: anytype,
    old_runs: anytype,
    visual_run_indices: []const usize,
) !void {
    buffer.runs.clearRetainingCapacity();
    if (visual_run_indices.len == 0 or old_runs.len == 0) return;
    var index: usize = 0;
    while (index < visual_run_indices.len) {
        if (visual_run_indices[index] == no_run) {
            index += 1;
            continue;
        }
        const start = index;
        const current_run_index = visual_run_indices[index];
        if (current_run_index >= old_runs.len) return error.InvalidBidiMap;
        index += 1;
        while (index < visual_run_indices.len and
            visual_run_indices[index] == current_run_index)
        {
            index += 1;
        }
        const source_run = old_runs[current_run_index];
        try buffer.runs.append(buffer.allocator, .{
            .font = source_run.font,
            .font_index = source_run.font_index,
            .font_size = source_run.font_size,
            .glyph_start = start,
            .glyph_len = index - start,
            .x_offset = 0,
            .y_offset = 0,
            .variation_coord_start = source_run.variation_coord_start,
            .variation_coord_len = source_run.variation_coord_len,
        });
    }
}

pub fn recomputeOffsets(buffer: anytype) void {
    var x_offset: f32 = 0;
    var y_offset: f32 = 0;
    var glyph_cursor: usize = 0;
    for (buffer.runs.items) |*run| {
        const run_start = @min(run.glyph_start, buffer.glyphs.items.len);
        for (buffer.glyphs.items[glyph_cursor..run_start]) |glyph| {
            x_offset += glyph.x_advance;
            y_offset += glyph.y_advance;
        }
        run.x_offset = x_offset;
        run.y_offset = y_offset;
        const run_end = @min(
            run_start + run.glyph_len,
            buffer.glyphs.items.len,
        );
        for (buffer.glyphs.items[run_start..run_end]) |glyph| {
            x_offset += glyph.x_advance;
            y_offset += glyph.y_advance;
        }
        glyph_cursor = run_end;
    }
}

pub fn range(
    font_runs: anytype,
    glyph_start: usize,
    glyph_end: usize,
) struct { start: usize, len: usize } {
    var start: ?usize = null;
    var end: usize = 0;
    for (font_runs, 0..) |run, index| {
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run.glyph_start >= glyph_end) continue;
        if (start == null) start = index;
        end = index + 1;
    }
    const actual_start = start orelse 0;
    return .{ .start = actual_start, .len = end - actual_start };
}
