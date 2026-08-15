//! Font-run ownership rebuilt after glyph permutation.

const std = @import("std");

pub fn buildGlyphRunIndices(
    allocator: std.mem.Allocator,
    runs: anytype,
    glyph_count: usize,
) ![]usize {
    const indices = try allocator.alloc(usize, glyph_count);
    @memset(indices, 0);
    for (runs, 0..) |run, run_index| {
        const end = @min(glyph_count, run.glyph_start + run.glyph_len);
        if (run.glyph_start >= end) continue;
        @memset(indices[run.glyph_start..end], run_index);
    }
    return indices;
}

pub fn rebuild(
    buffer: anytype,
    old_runs: anytype,
    visual_run_indices: []const usize,
) !void {
    buffer.runs.clearRetainingCapacity();
    if (visual_run_indices.len == 0 or old_runs.len == 0) return;
    var start: usize = 0;
    var current_run_index = visual_run_indices[0];
    var index: usize = 1;
    while (index <= visual_run_indices.len) : (index += 1) {
        if (index < visual_run_indices.len and
            visual_run_indices[index] == current_run_index)
        {
            continue;
        }
        if (current_run_index >= old_runs.len) {
            return error.InvalidBidiMap;
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
        });
        if (index < visual_run_indices.len) {
            start = index;
            current_run_index = visual_run_indices[index];
        }
    }
}

pub fn recomputeOffsets(buffer: anytype) void {
    var x_offset: f32 = 0;
    var y_offset: f32 = 0;
    for (buffer.runs.items) |*run| {
        run.x_offset = x_offset;
        run.y_offset = y_offset;
        for (
            buffer.glyphs.items[run.glyph_start .. run.glyph_start + run.glyph_len],
        ) |glyph| {
            x_offset += glyph.x_advance;
            y_offset += glyph.y_advance;
        }
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
