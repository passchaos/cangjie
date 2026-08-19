//! Vertical max-lines ellipsis materialization.
//!
//! Vertical paragraph advances grow down the physical y axis. Keeping this
//! separate from horizontal truncation prevents x-width fitting, horizontal
//! tab fields, and left/right alignment from leaking into column geometry.

const std = @import("std");

const font_shaping = @import("../../font.zig").shaping;
const ellipsis_runs = @import("../line_break/reflow/ellipsis_runs.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const positioning_policy =
    @import("../../shaping/pipeline/positioning/policy.zig");
const run_types = @import("../types/runs.zig");
const paragraph_options = @import("options.zig");
const vertical_block_metrics = @import("vertical_block_metrics.zig");
const vertical_inline_region = @import("vertical_inline_region.zig");
const vertical_tabs = @import("vertical_wrap/tabs.zig");
const white_space = @import("white_space.zig");

pub const synthetic_count: usize = 3;

/// Append three synthetic periods to the final visible vertical column.
///
/// The caller must already have truncated the paragraph to its visible column
/// prefix. The function trims only the final column, repairs its terminal font
/// run, and returns the number of synthetic glyphs appended. A fontless final
/// column cannot supply glyph metrics and therefore returns zero.
pub fn materialize(
    buffer: *@import("../../shaping/context/output.zig").Buffer,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    recipe: anytype,
) !usize {
    if (buffer.lines.items.len == 0 or
        buffer.glyphs.items.len == 0)
    {
        return 0;
    }
    const line = &buffer.lines.items[buffer.lines.items.len - 1];
    if (line.glyph_len == 0) return 0;

    const source_run: ?run_types.CascadeRun = if (line.run_len != 0) source: {
        const run_index = line.run_start + line.run_len - 1;
        if (run_index >= buffer.runs.items.len) {
            return error.InvalidParagraphLayout;
        }
        break :source buffer.runs.items[run_index];
    } else null;
    const terminal_source_boundary = buffer.glyphs.items[
        line.glyph_start + line.glyph_len - 1
    ].sourceByteEnd();
    const run_template = try recipe.ellipsisRun(
        buffer,
        terminal_source_boundary,
        source_run,
    ) orelse return 0;
    const coord_end =
        run_template.variation_coord_start + run_template.variation_coord_len;
    if (coord_end > buffer.variation_coords.items.len) {
        return error.InvalidParagraphLayout;
    }
    const normalized_coords =
        buffer.variation_coords.items[run_template.variation_coord_start..coord_end];
    const font = run_types.fontForBackend(run_template);
    const dot_glyph = try font.glyphIndex('.');
    const horizontal_metrics = try font.horizontalMetricsAtCoords(
        dot_glyph,
        normalized_coords,
    );
    const scale = run_template.font_size /
        @as(f32, @floatFromInt(font.units_per_em));
    const orientation = positioning_policy.glyphOrientation(
        '.',
        options.writing_mode,
        options.text_orientation,
    );
    const vertical_metrics = try positioning_policy.verticalMetrics(
        font,
        null,
        dot_glyph,
        normalized_coords,
    );
    const dot_advance = if (orientation == .sideways)
        @as(f32, @floatFromInt(horizontal_metrics.advance_width)) * scale
    else if (vertical_metrics) |metrics|
        @as(f32, @floatFromInt(metrics.advance_height)) * scale
    else
        run_template.font_size;
    const dot_x_offset = -@as(
        f32,
        @floatFromInt(
            @divTrunc(
                @as(i32, horizontal_metrics.advance_width),
                2,
            ),
        ),
    ) * scale;
    const dot_y_offset = -@as(
        f32,
        @floatFromInt(
            try font_shaping.verticalOriginYAtCoords(
                font,
                dot_glyph,
                normalized_coords,
            ),
        ),
    ) * scale;
    const ellipsis_advance =
        dot_advance * @as(f32, @floatFromInt(synthetic_count));
    const inline_limit = if (line.region_inline_size > 0 or
        std.math.isInf(line.region_inline_size))
        line.region_inline_size
    else if (options.max_width > 0 and std.math.isFinite(options.max_width))
        @max(0, options.max_width - line.indent)
    else
        std.math.inf(f32);
    const fallback_advance =
        white_space.defaultVerticalSpaceAdvance(buffer.glyphs.items);
    const fallback_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        fallback_advance;

    // Reserve every potentially growing owner before trimming source glyphs.
    // After mutation begins, run repair can therefore reuse existing capacity.
    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        buffer.glyphs.items.len + synthetic_count,
    );
    try buffer.runs.ensureUnusedCapacity(buffer.allocator, 1);

    line.height = vertical_tabs.recomputeRangeWithTerminal(
        buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        options.tab_stops,
        fallback_interval,
        fallback_advance,
        ellipsis_advance,
    );
    // A discretionary hyphen denotes continuation into another visible
    // column. Ellipsis terminates the visible source prefix, so retaining that
    // hyphen would render two mutually exclusive terminal markers.
    while (line.glyph_len > 0 and
        buffer.glyphs.items[
            line.glyph_start + line.glyph_len - 1
        ].isDiscretionaryHyphen())
    {
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        line.height = vertical_tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_interval,
            fallback_advance,
            ellipsis_advance,
        );
    }
    while (line.glyph_len > 0 and line.height > inline_limit) {
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        line.height = vertical_tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_interval,
            fallback_advance,
            ellipsis_advance,
        );
    }

    // This is a zero-length insertion at the visible source boundary, not
    // another output of the preceding scalar. Giving dots that scalar's
    // cluster would let an RTL level reverse the synthetic tail inside the
    // cluster. A boundary cluster has no UAX #9 scalar owner, so line-local
    // reorder preserves the dots as its final unseen outputs.
    const cluster = line.byteEnd();
    const synthetic_run_index = try ellipsis_runs.prepare(
        buffer,
        buffer.glyphs.items.len,
        run_template,
    );
    for (0..synthetic_count) |_| {
        buffer.glyphs.appendAssumeCapacity(.{
            .glyph_id = dot_glyph,
            .codepoint = '.',
            .cluster = cluster,
            .x_advance = 0,
            .y_advance = dot_advance,
            .x_offset = dot_x_offset,
            .y_offset = dot_y_offset,
            .orientation = orientation,
        });
        line.glyph_len += 1;
    }
    buffer.runs.items[synthetic_run_index].glyph_len += synthetic_count;
    line.height = vertical_tabs.recomputeRange(
        buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        options.tab_stops,
        fallback_interval,
        fallback_advance,
    );
    try refreshBlockMetrics(
        buffer,
        line,
        options,
        default_metrics,
    );
    line.y = vertical_inline_region.origin(
        line.*,
        options,
        line.height,
    );
    return synthetic_count;
}

fn refreshBlockMetrics(
    buffer: *@import("../../shaping/context/output.zig").Buffer,
    line: *@import("../types/paragraph.zig").ParagraphLine,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
) !void {
    const resolved = try vertical_block_metrics.resolve(
        buffer.runs.items,
        buffer.glyphs.items,
        options,
        default_metrics,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    );
    line.run_start = resolved.line_info.run_start;
    line.run_len = resolved.line_info.run_len;
    line.region_width = resolved.block_size;
    line.width = resolved.block_size;
    line.baseline = resolved.block_size / 2;
    line.ascent = resolved.line_info.metrics.ascent;
    line.descent = resolved.line_info.metrics.descent;
    line.leading = resolved.line_info.metrics.leading;
}
