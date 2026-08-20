//! Prefix truncation and plain-text ellipsis materialization.

const std = @import("std");

const ellipsis_runs = @import("ellipsis_runs.zig");
const geometry = @import("geometry.zig");
const regions = @import("regions.zig");
const tabs = @import("../../paragraph/tabs.zig");
const run_types = @import("../../types/runs.zig");

pub fn apply(
    buffer: anytype,
    max_lines: usize,
    ellipsis: bool,
    max_width: f32,
    alignment: anytype,
    content_omitted: bool,
    options: anytype,
) !void {
    if (buffer.lines.items.len < max_lines or
        (buffer.lines.items.len == max_lines and !content_omitted))
    {
        return;
    }
    if (max_lines == 0) {
        keepPrefix(buffer, 0);
        return;
    }

    keepPrefix(buffer, max_lines);
    const keep_glyphs = buffer.glyphs.items.len;

    if (ellipsis and content_omitted and keep_glyphs > 0) {
        try appendEllipsisToLastLine(
            buffer,
            max_width,
            alignment,
            options,
        );
    }
}

/// Keep a complete visual-line prefix and synchronize glyph/run ownership.
///
/// This operation is writing-mode neutral. Horizontal truncation optionally
/// materializes x-axis dots through `apply`; vertical column layout uses the
/// same prefix transaction before its separate positive-down materializer.
pub fn keepPrefix(buffer: anytype, line_count: usize) void {
    if (line_count == 0) {
        buffer.lines.clearRetainingCapacity();
        buffer.runs.clearRetainingCapacity();
        buffer.glyphs.clearRetainingCapacity();
        return;
    }
    if (buffer.lines.items.len < line_count) return;
    if (buffer.lines.items.len > line_count) {
        buffer.lines.shrinkRetainingCapacity(line_count);
    }
    const last_line = &buffer.lines.items[line_count - 1];
    const keep_glyphs = last_line.glyph_start + last_line.glyph_len;
    buffer.glyphs.shrinkRetainingCapacity(keep_glyphs);
    trimRunsToGlyphCount(buffer, keep_glyphs);
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
    options: anytype,
) !void {
    if (buffer.lines.items.len == 0 or buffer.runs.items.len == 0) return;
    const line = &buffer.lines.items[buffer.lines.items.len - 1];
    const ellipsis_count: usize = 3;
    const run_index = line.run_start + line.run_len - 1;
    const run_template = buffer.runs.items[run_index];
    const font = run_types.fontForBackend(run_template);
    const dot_metrics =
        try font.horizontalMetrics(try font.glyphIndex('.'));
    const dot_advance = @as(f32, @floatFromInt(dot_metrics.advance_width)) *
        (run_template.font_size /
            @as(f32, @floatFromInt(font.units_per_em)));
    const ellipsis_width =
        dot_advance * @as(f32, @floatFromInt(ellipsis_count));
    const space_advance =
        geometry.defaultSpaceAdvance(buffer.glyphs.items);
    const fallback_tab_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        space_advance;
    const region = regions.stored(line.*, max_width);
    const width_limit = region.width;
    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        buffer.glyphs.items.len + ellipsis_count,
    );
    // Reflow may have selected this line using optical punctuation hanging.
    // Ellipsis changes the terminal glyph and therefore invalidates that
    // discount. Restore the complete advance sum before fitting synthetic
    // dots; the final punctuation pass will reapply any still-valid hanging.
    line.width = tabs.recomputeRangeWithTerminal(
        buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        options.tab_stops,
        fallback_tab_interval,
        space_advance,
        ellipsis_width,
    );

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
        line.width = tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_tab_interval,
            space_advance,
            ellipsis_width,
        );
    }

    while (line.glyph_len > 0 and line.width > width_limit) {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        line.width = tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_tab_interval,
            space_advance,
            ellipsis_width,
        );
    }

    const dot_glyph = try font.glyphIndex('.');
    const cluster = if (line.glyph_len > 0)
        buffer.glyphs.items[line.glyph_start + line.glyph_len - 1].cluster
    else
        0;
    const synthetic_run_index = try ellipsis_runs.prepare(
        buffer,
        buffer.glyphs.items.len,
        run_template,
    );
    for (0..ellipsis_count) |_| {
        buffer.glyphs.appendAssumeCapacity(.{
            .glyph_id = dot_glyph,
            .codepoint = '.',
            .cluster = cluster,
            .x_advance = dot_advance,
        });
        line.glyph_len += 1;
    }
    buffer.runs.items[synthetic_run_index].glyph_len += ellipsis_count;
    line.width = geometry.lineWidth(
        buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
    );
    line.run_len = geometry.runRangeForGlyphs(
        buffer.runs.items,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    ).len;
    const final_alignment =
        if (tabs.contains(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        ))
            line.resolved_alignment orelse alignment
        else
            alignment;
    line.resolved_alignment = final_alignment;
    line.x = region.x + geometry.alignedLineX(
        @min(line.width, region.width),
        region.width,
        final_alignment,
    );
}
