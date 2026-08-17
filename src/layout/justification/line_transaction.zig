//! Atomic replacement of one logical line's glyph, run, and variation data.
//!
//! Source-level justification mechanisms shape candidates in isolated buffers.
//! This module performs the shared commit step only after a candidate has been
//! accepted, including split font runs that cross soft line boundaries.

const std = @import("std");

const bidi_runs = @import("../bidi/reorder/runs.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const run_types = @import("../types/runs.zig");

pub fn replace(
    buffer: anytype,
    line_index: usize,
    new_glyphs: []const GlyphPosition,
    new_runs: []const run_types.CascadeRun,
    new_variation_coords: []const f32,
    width: f32,
) !void {
    const line = buffer.lines.items[line_index];
    const old_glyph_len = line.glyph_len;
    const old_line_end = line.glyph_start + old_glyph_len;
    const glyph_delta: isize =
        @as(isize, @intCast(new_glyphs.len)) -
        @as(isize, @intCast(old_glyph_len));

    // One font run can cross a soft line boundary. Split surviving prefix and
    // suffix ranges explicitly; replacing `line.run_start/run_len` would drop
    // the portion owned by an adjacent line.
    var rebuilt_runs = std.ArrayList(run_types.CascadeRun).empty;
    defer rebuilt_runs.deinit(buffer.allocator);
    try rebuilt_runs.ensureTotalCapacity(
        buffer.allocator,
        buffer.runs.items.len + new_runs.len + 2,
    );
    for (buffer.runs.items) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        const prefix_end = @min(run_end, line.glyph_start);
        if (run.glyph_start < prefix_end) {
            var prefix = run;
            prefix.glyph_len = prefix_end - run.glyph_start;
            rebuilt_runs.appendAssumeCapacity(prefix);
        }
    }
    for (new_runs) |run| {
        var adjusted = run;
        const coord_end =
            run.variation_coord_start + run.variation_coord_len;
        if (coord_end > new_variation_coords.len) {
            return error.InvalidLineReplacement;
        }
        const variation_range = try buffer.internVariationCoords(
            new_variation_coords[run.variation_coord_start..coord_end],
        );
        adjusted.glyph_start += line.glyph_start;
        adjusted.variation_coord_start = variation_range.start;
        adjusted.variation_coord_len = variation_range.len;
        rebuilt_runs.appendAssumeCapacity(adjusted);
    }
    for (buffer.runs.items) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        const suffix_start = @max(run.glyph_start, old_line_end);
        if (suffix_start < run_end) {
            var suffix = run;
            suffix.glyph_start = addSigned(suffix_start, glyph_delta);
            suffix.glyph_len = run_end - suffix_start;
            rebuilt_runs.appendAssumeCapacity(suffix);
        }
    }

    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        buffer.glyphs.items.len - old_glyph_len + new_glyphs.len,
    );
    try buffer.runs.ensureTotalCapacity(
        buffer.allocator,
        rebuilt_runs.items.len,
    );

    buffer.glyphs.replaceRangeAssumeCapacity(
        line.glyph_start,
        old_glyph_len,
        new_glyphs,
    );
    buffer.runs.clearRetainingCapacity();
    buffer.runs.appendSliceAssumeCapacity(rebuilt_runs.items);

    var current = &buffer.lines.items[line_index];
    current.glyph_len = new_glyphs.len;
    current.width = width;
    for (buffer.lines.items[line_index + 1 ..]) |*later| {
        later.glyph_start = addSigned(later.glyph_start, glyph_delta);
    }
    for (buffer.lines.items) |*affected| {
        const range = geometry.runRangeForGlyphs(
            buffer.runs.items,
            affected.glyph_start,
            affected.glyph_start + affected.glyph_len,
        );
        affected.run_start = range.start;
        affected.run_len = range.len;
    }
    bidi_runs.recomputeOffsets(buffer);
}

fn addSigned(value: usize, delta: isize) usize {
    if (delta >= 0) return value + @as(usize, @intCast(delta));
    return value - @as(usize, @intCast(-delta));
}
