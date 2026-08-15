//! HarfBuzz-style expansion of fixed and repeating `stch` glyph tiles.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const cache_mod = @import("../../context/cache/root.zig");
const GlyphMetricsCache = cache_mod.GlyphMetricsCache;
const ligature_provenance = @import("../../../ligature_provenance.zig");
const actions = @import("actions.zig");

pub fn apply(
    allocator: std.mem.Allocator,
    glyphs: *std.ArrayList(GlyphPosition),
    stch_actions: []const u8,
    segment_start: usize,
    rtl: bool,
    reverse_after_stch: bool,
    scale: f32,
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
) !void {
    const segment_len = glyphs.items.len - segment_start;
    if (segment_len == 0 or stch_actions.len != segment_len) return;
    std.debug.assert(hasStretch(stch_actions));

    var extra_glyphs_needed: usize = 0;
    var index = segment_len;
    while (index > 0) {
        if (actions.fromInt(stch_actions[index - 1]) == .none) {
            index -= 1;
            continue;
        }
        const metrics = try measureRun(
            font,
            metrics_cache,
            normalized_variation_coords,
            glyphs.items[segment_start..],
            stch_actions,
            index,
            rtl,
            scale,
        );
        extra_glyphs_needed += metrics.n_copies * metrics.n_repeating;
        index = metrics.start;
    }

    const old_len = glyphs.items.len;
    const new_len = old_len + extra_glyphs_needed;
    try glyphs.ensureUnusedCapacity(allocator, extra_glyphs_needed);
    const source = glyphs.items[segment_start..old_len];
    var output = std.ArrayList(GlyphPosition).empty;
    defer output.deinit(allocator);
    try output.ensureTotalCapacity(
        allocator,
        segment_len + extra_glyphs_needed,
    );

    index = 0;
    while (index < segment_len) {
        if (actions.fromInt(stch_actions[index]) == .none) {
            output.appendAssumeCapacity(source[index]);
            index += 1;
            continue;
        }
        const metrics = try measureRun(
            font,
            metrics_cache,
            normalized_variation_coords,
            source,
            stch_actions,
            runEnd(stch_actions, index),
            rtl,
            scale,
        );
        try appendRun(
            font,
            metrics_cache,
            normalized_variation_coords,
            source[metrics.start..metrics.end],
            stch_actions[metrics.start..metrics.end],
            metrics,
            rtl,
            reverse_after_stch,
            scale,
            &output,
        );
        index = metrics.end;
    }

    glyphs.items.len = new_len;
    @memcpy(
        glyphs.items[segment_start .. segment_start + output.items.len],
        output.items,
    );
}

fn hasStretch(stch_actions: []const u8) bool {
    for (stch_actions) |raw_action| {
        if (actions.fromInt(raw_action) != .none) return true;
    }
    return false;
}

const RunMetrics = struct {
    start: usize,
    end: usize,
    w_remaining_units: i32,
    extra_repeat_overlap_units: i32,
    n_repeating: usize,
    n_copies: usize,
};

fn measureRun(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    segment: []const GlyphPosition,
    stch_actions: []const u8,
    end: usize,
    rtl: bool,
    scale: f32,
) !RunMetrics {
    var index = end;
    var w_total: i32 = 0;
    var w_fixed: i32 = 0;
    var w_repeating: i32 = 0;
    var n_fixed: usize = 0;
    var n_repeating: usize = 0;

    while (index > 0 and
        actions.fromInt(stch_actions[index - 1]) != .none)
    {
        index -= 1;
        const width = try glyphAdvanceUnits(
            font,
            metrics_cache,
            normalized_variation_coords,
            segment[index].glyph_id,
        );
        switch (actions.fromInt(stch_actions[index])) {
            .fixed => {
                w_fixed += width;
                n_fixed += 1;
            },
            .repeating => {
                w_repeating += width;
                n_repeating += 1;
            },
            .none => {},
        }
    }
    const start = index;
    if (rtl) {
        var context = end;
        while (context < segment.len and
            actions.fromInt(stch_actions[context]) == .none and
            actions.isContext(stch_actions[context])) : (context += 1)
        {
            w_total += floatToFontUnits(segment[context].x_advance, scale);
        }
    } else {
        var context = index;
        while (context > 0 and
            actions.fromInt(stch_actions[context - 1]) == .none and
            actions.isContext(stch_actions[context - 1]))
        {
            context -= 1;
            w_total += floatToFontUnits(segment[context].x_advance, scale);
        }
    }

    var w_remaining = w_total - w_fixed;
    var n_copies: usize = 0;
    if (w_remaining > w_repeating and w_repeating > 0) {
        n_copies = @intCast(@divTrunc(w_remaining, w_repeating) - 1);
    }

    var extra_repeat_overlap: i32 = 0;
    const shortfall =
        w_remaining - w_repeating * @as(i32, @intCast(n_copies + 1));
    if (shortfall > 0 and n_repeating > 0) {
        n_copies += 1;
        const excess =
            @as(i32, @intCast(n_copies + 1)) * w_repeating - w_remaining;
        if (excess > 0) {
            extra_repeat_overlap = @divTrunc(
                excess,
                @as(i32, @intCast(n_copies * n_repeating)),
            );
            w_remaining = 0;
        }
    }

    const max_glyphs = 256;
    var max_copies: usize = 0;
    if (n_repeating > 0) {
        const base_glyphs = n_fixed + n_repeating;
        if (base_glyphs < max_glyphs) {
            max_copies = (max_glyphs - base_glyphs) / n_repeating;
        }
    }
    n_copies = @min(n_copies, max_copies);

    return .{
        .start = start,
        .end = end,
        .w_remaining_units = w_remaining,
        .extra_repeat_overlap_units = extra_repeat_overlap,
        .n_repeating = n_repeating,
        .n_copies = n_copies,
    };
}

fn runEnd(stch_actions: []const u8, start: usize) usize {
    var end = start;
    while (end < stch_actions.len and
        actions.fromInt(stch_actions[end]) != .none) : (end += 1)
    {}
    return end;
}

fn appendRun(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    run: []const GlyphPosition,
    run_actions: []const u8,
    metrics: RunMetrics,
    rtl: bool,
    reverse_after_stch: bool,
    scale: f32,
    output: *std.ArrayList(GlyphPosition),
) !void {
    var x_offset_units: i32 = @divTrunc(metrics.w_remaining_units, 2);
    if (!rtl and x_offset_units > 0) x_offset_units = 0;
    const overlap_units = metrics.extra_repeat_overlap_units;
    const output_start = output.items.len;
    for (run, run_actions) |glyph, raw_action| {
        try appendGlyphCopies(
            font,
            metrics_cache,
            normalized_variation_coords,
            glyph,
            actions.fromInt(raw_action),
            metrics.n_copies,
            rtl,
            &x_offset_units,
            overlap_units,
            scale,
            output,
        );
    }
    if (!rtl and reverse_after_stch) {
        std.mem.reverse(GlyphPosition, output.items[output_start..]);
    }
}

fn appendGlyphCopies(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    glyph: GlyphPosition,
    action: ligature_provenance.StchAction,
    n_copies: usize,
    rtl: bool,
    x_offset_units: *i32,
    overlap_units: i32,
    scale: f32,
    output: *std.ArrayList(GlyphPosition),
) !void {
    const repeat = if (action == .repeating) 1 + n_copies else 1;
    const width_units = try glyphAdvanceUnits(
        font,
        metrics_cache,
        normalized_variation_coords,
        glyph.glyph_id,
    );
    for (0..repeat) |copy_index| {
        var item = glyph;
        item.x_advance = 0;
        if (rtl) {
            x_offset_units.* -= width_units;
            if (copy_index > 0) x_offset_units.* += overlap_units;
        }
        item.x_offset = @as(f32, @floatFromInt(x_offset_units.*)) * scale;
        output.appendAssumeCapacity(item);
        if (!rtl) {
            x_offset_units.* += width_units;
            if (copy_index > 0) x_offset_units.* -= overlap_units;
        }
    }
}

fn glyphAdvanceUnits(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    normalized_variation_coords: []const f32,
    glyph_id: GlyphId,
) !i32 {
    if (metrics_cache) |cache| {
        const metrics = try cache.horizontalMetricsAtCoords(
            font,
            glyph_id,
            normalized_variation_coords,
        );
        return metrics.advance_width;
    }
    const metrics = if (normalized_variation_coords.len == 0)
        try font.horizontalMetrics(glyph_id)
    else
        try font.horizontalMetricsAtCoords(
            glyph_id,
            normalized_variation_coords,
        );
    return metrics.advance_width;
}

fn floatToFontUnits(value: f32, scale: f32) i32 {
    if (scale == 0) return 0;
    return @intFromFloat(@round(value / scale));
}
