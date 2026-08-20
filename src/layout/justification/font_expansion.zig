//! Variable-font axis adaptation for justified logical lines.
//!
//! This follows the useful part of HarfBuzz's experimental justification
//! convention: prefer a custom `jstf` fvar axis and then the registered `wdth`
//! axis. It does not claim to implement the unrelated OpenType `JSTF` table.
//! Accepted candidates are shaped from source and committed transactionally so
//! glyph selection, advances, run coordinates, and rendering stay synchronized.

const std = @import("std");

const font_mod = @import("../../font.zig");
const Font = font_mod.Font;
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const line_transaction = @import("line_transaction.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const unicode = @import("../../unicode.zig");

const width_epsilon: f32 = 0.001;
const solver_iterations: usize = 14;

pub fn apply(
    buffer: anytype,
    options: anytype,
    recipe: anytype,
) !void {
    if (options.alignment != .justify or
        !options.font_expansion.enabled or
        buffer.lines.items.len == 0)
    {
        return;
    }

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    var trial_coords = std.ArrayList(f32).empty;
    defer trial_coords.deinit(buffer.allocator);

    var line_index: usize = 0;
    while (line_index < buffer.lines.items.len) : (line_index += 1) {
        const line = buffer.lines.items[line_index];
        const target = line.justification_target orelse continue;
        const source_range = reusableSourceRange(
            buffer.glyphs.items,
            line,
        ) orelse continue;
        if (!recipe.canExpandSourceRange(
            source_range.start,
            source_range.end,
        )) {
            continue;
        }
        const run = singleOwningRun(
            buffer.runs.items,
            line,
        ) orelse continue;
        const font = run_types.fontForBackend(run);
        const axes = try font.variationAxes(buffer.allocator);
        defer buffer.allocator.free(axes);
        const axis_index = preferredAxisIndex(axes) orelse continue;
        if (axes[axis_index].max_value <= axes[axis_index].default_value) {
            continue;
        }

        const current_coords = runCoords(buffer, run);
        try trial_coords.resize(buffer.allocator, axes.len);
        @memset(trial_coords.items, 0);
        const copied = @min(current_coords.len, trial_coords.items.len);
        @memcpy(trial_coords.items[0..copied], current_coords[0..copied]);
        const current_axis = trial_coords.items[axis_index];
        if (current_axis >= 1) continue;

        const natural_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        );
        if (target <= natural_width + width_epsilon) continue;

        var best_axis = current_axis;
        var best_width = natural_width;
        trial_coords.items[axis_index] = 1;
        try recipe.shapeLineAtCoords(
            &work,
            source_range.start,
            source_range.end - source_range.start,
            font,
            run.font_index,
            trial_coords.items,
        );
        const maximum_width = geometry.lineWidth(work.glyphs.items);
        if (maximum_width <= natural_width + width_epsilon) continue;
        if (maximum_width <= target + width_epsilon) {
            best_axis = 1;
            best_width = maximum_width;
        } else {
            var low = current_axis;
            var high: f32 = 1;
            var previous_trial: ?f32 = null;
            for (0..solver_iterations) |_| {
                const trial = quantizeNormalized((low + high) / 2);
                if (previous_trial != null and trial == previous_trial.?) break;
                previous_trial = trial;
                trial_coords.items[axis_index] = trial;
                try recipe.shapeLineAtCoords(
                    &work,
                    source_range.start,
                    source_range.end - source_range.start,
                    font,
                    run.font_index,
                    trial_coords.items,
                );
                const width = geometry.lineWidth(work.glyphs.items);
                if (width <= target + width_epsilon) {
                    low = trial;
                    if (width > best_width + width_epsilon) {
                        best_axis = trial;
                        best_width = width;
                    }
                } else {
                    high = trial;
                }
            }
        }
        if (best_axis == current_axis or
            best_width <= natural_width + width_epsilon)
        {
            continue;
        }

        trial_coords.items[axis_index] = best_axis;
        try recipe.shapeLineAtCoords(
            &work,
            source_range.start,
            source_range.end - source_range.start,
            font,
            run.font_index,
            trial_coords.items,
        );
        const final_width = geometry.lineWidth(work.glyphs.items);
        if (final_width <= natural_width + width_epsilon or
            final_width > target + width_epsilon)
        {
            continue;
        }
        try recipe.prepareCommit(
            line.glyph_start,
            line.glyph_len,
            work.glyphs.items.len,
        );
        try line_transaction.replace(
            buffer,
            line_index,
            work.glyphs.items,
            work.runs.items,
            work.variation_coords.items,
            final_width,
        );
        recipe.commit(
            line.glyph_start,
            line.glyph_len,
            work.glyphs.items.len,
        );
    }
}

const SourceRange = struct {
    start: usize,
    end: usize,
};

fn reusableSourceRange(
    glyphs: []const GlyphPosition,
    line: paragraph_types.ParagraphLine,
) ?SourceRange {
    if (line.glyph_len == 0) return null;
    var start: usize = std.math.maxInt(usize);
    var end: usize = 0;
    for (glyphs[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
        if (glyph.isInlineObject() or
            glyph.isDiscretionaryHyphen() or
            glyph.isKashida() or
            glyph.isAutomaticHyphen() or
            glyph.isTab() or
            isMandatoryBreak(glyph.codepoint))
        {
            return null;
        }
        start = @min(start, glyph.cluster);
        end = @max(end, glyph.sourceByteEnd());
    }
    if (start == std.math.maxInt(usize) or start >= end) return null;
    return .{ .start = start, .end = end };
}

fn singleOwningRun(
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
) ?run_types.CascadeRun {
    const line_end = line.glyph_start + line.glyph_len;
    var owner: ?run_types.CascadeRun = null;
    for (runs) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= line.glyph_start or run.glyph_start >= line_end) {
            continue;
        }
        if (owner != null) return null;
        owner = run;
    }
    const run = owner orelse return null;
    if (run.glyph_start > line.glyph_start or
        run.glyph_start + run.glyph_len < line_end)
    {
        return null;
    }
    return run;
}

fn runCoords(buffer: anytype, run: run_types.CascadeRun) []const f32 {
    const end = run.variation_coord_start + run.variation_coord_len;
    std.debug.assert(end <= buffer.variation_coords.items.len);
    return buffer.variation_coords.items[run.variation_coord_start..end];
}

fn preferredAxisIndex(axes: []const font_mod.VariationAxis) ?usize {
    for ([_][4]u8{ .{ 'j', 's', 't', 'f' }, .{ 'w', 'd', 't', 'h' } }) |tag| {
        for (axes, 0..) |axis, index| {
            if (std.mem.eql(u8, &axis.tag, &tag)) return index;
        }
    }
    return null;
}

fn quantizeNormalized(value: f32) f32 {
    const clamped = @min(@as(f32, 1), @max(@as(f32, -1), value));
    return @round(clamped * 16384) / 16384;
}

fn isMandatoryBreak(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

test "justification axis preference uses jstf before wdth" {
    const axes = [_]font_mod.VariationAxis{
        .{
            .tag = .{ 'w', 'd', 't', 'h' },
            .min_value = 50,
            .default_value = 100,
            .max_value = 200,
            .flags = 0,
            .name_id = 1,
        },
        .{
            .tag = .{ 'j', 's', 't', 'f' },
            .min_value = 0,
            .default_value = 0,
            .max_value = 100,
            .flags = 0,
            .name_id = 2,
        },
    };
    try std.testing.expectEqual(@as(?usize, 1), preferredAxisIndex(&axes));
}
