//! Prefix truncation and plain-text ellipsis materialization.

const std = @import("std");

const geometry = @import("geometry.zig");
const regions = @import("regions.zig");
const run_types = @import("../../types/runs.zig");

pub fn apply(
    buffer: anytype,
    max_lines: usize,
    ellipsis: bool,
    max_width: f32,
    alignment: anytype,
    content_omitted: bool,
) !void {
    if (buffer.lines.items.len < max_lines or
        (buffer.lines.items.len == max_lines and !content_omitted))
    {
        return;
    }
    if (max_lines == 0) {
        buffer.lines.clearRetainingCapacity();
        buffer.runs.clearRetainingCapacity();
        buffer.glyphs.clearRetainingCapacity();
        return;
    }

    buffer.lines.shrinkRetainingCapacity(max_lines);
    const last_line = &buffer.lines.items[max_lines - 1];
    const keep_glyphs = last_line.glyph_start + last_line.glyph_len;
    buffer.glyphs.shrinkRetainingCapacity(keep_glyphs);
    trimRunsToGlyphCount(buffer, keep_glyphs);

    if (ellipsis and content_omitted and keep_glyphs > 0) {
        try appendEllipsisToLastLine(buffer, max_width, alignment);
    }
}

fn trimRunsToGlyphCount(buffer: anytype, glyph_count: usize) void {
    // Truncation can cut through the last cascade run. Keep surviving run
    // ranges consistent with the shortened glyph array and each line's range.
    var run_count: usize = 0;
    for (buffer.runs.items) |*run| {
        if (run.glyph_start >= glyph_count) break;
        if (run.glyph_start + run.glyph_len > glyph_count) {
            run.glyph_len = glyph_count - run.glyph_start;
        }
        run_count += 1;
    }
    buffer.runs.shrinkRetainingCapacity(run_count);
    for (buffer.lines.items) |*line| {
        const run_range = geometry.runRangeForGlyphs(
            buffer.runs.items,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
        );
        line.run_start = run_range.start;
        line.run_len = run_range.len;
    }
}

fn appendEllipsisToLastLine(
    buffer: anytype,
    max_width: f32,
    alignment: anytype,
) !void {
    if (buffer.lines.items.len == 0 or buffer.runs.items.len == 0) return;
    const line = &buffer.lines.items[buffer.lines.items.len - 1];
    const ellipsis_count: usize = 3;
    const run_index = line.run_start + line.run_len - 1;
    var run = &buffer.runs.items[run_index];
    const font = run_types.fontForBackend(run.*);
    const dot_metrics =
        try font.horizontalMetrics(try font.glyphIndex('.'));
    const dot_advance = @as(f32, @floatFromInt(dot_metrics.advance_width)) *
        (run.font_size / @as(f32, @floatFromInt(font.units_per_em)));
    const ellipsis_width =
        dot_advance * @as(f32, @floatFromInt(ellipsis_count));
    const region = regions.stored(line.*, max_width);
    const width_limit = region.width;
    // Reflow may have selected this line using optical punctuation hanging.
    // Ellipsis changes the terminal glyph and therefore invalidates that
    // discount. Restore the complete advance sum before fitting synthetic
    // dots; the final punctuation pass will reapply any still-valid hanging.
    line.width = geometry.lineWidth(buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len]);

    // An ellipsis terminates visible content rather than continuing the word,
    // so a discretionary line-end hyphen is no longer semantically active.
    while (line.glyph_len > 0 and
        buffer.glyphs.items[
            line.glyph_start + line.glyph_len - 1
        ].isDiscretionaryHyphen())
    {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        if (run.glyph_len > 0) run.glyph_len -= 1;
    }

    while (line.glyph_len > 0 and
        line.width + ellipsis_width > width_limit)
    {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        if (run.glyph_len > 0) run.glyph_len -= 1;
    }

    const dot_glyph = try font.glyphIndex('.');
    const cluster = if (line.glyph_len > 0)
        buffer.glyphs.items[line.glyph_start + line.glyph_len - 1].cluster
    else
        0;
    for (0..ellipsis_count) |_| {
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = dot_glyph,
            .codepoint = '.',
            .cluster = cluster,
            .x_advance = dot_advance,
        });
        line.glyph_len += 1;
        run.glyph_len += 1;
        line.width += dot_advance;
    }
    line.run_len = geometry.runRangeForGlyphs(
        buffer.runs.items,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    ).len;
    line.x = region.x + geometry.alignedLineX(
        @min(line.width, region.width),
        region.width,
        alignment,
    );
}
