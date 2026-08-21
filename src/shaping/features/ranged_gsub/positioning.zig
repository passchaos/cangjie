//! Final positioned-glyph emission for the first ranged-GSUB contract.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const attachment = @import("../../../attachment.zig");
const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gpos = @import("../../../gpos.zig");
const GlyphMetricsCache = @import("../../context/cache/root.zig").GlyphMetricsCache;
const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const context_output = @import("../../context/output.zig");
const shaping_plan = @import("../../plan/root.zig");
const run_metadata = @import("../../run_metadata.zig");
const source_span = @import("../../pipeline/positioning/source_span.zig");
const source_buffer = @import("source_buffer.zig");
const unicode = @import("../../../unicode.zig");

pub fn collect(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    layout_buffer: *context_output.Buffer,
    font_size: f32,
    sources: *source_buffer.Buffer,
    gdef_metadata: GdefLookupMetadata,
    script_tag: @import("../../../unicode.zig").OpenTypeScriptTag,
    language_tag: @import("../../../unicode.zig").OpenTypeLanguageTag,
    options: shaping_plan.ShapeOptions,
) !void {
    const allocator = layout_buffer.allocator;
    const scale = font_size / @as(f32, @floatFromInt(font.units_per_em));
    const metadata = run_metadata.Positioning{
        .glyph_source_indices = sources.glyph_sources.items,
        .source_codepoints = sources.codepoints.items,
        .glyph_substituted = sources.glyph_substituted.items,
        .ligature_components = &sources.ligature_components,
        .source_boundaries = &sources.source_boundaries,
    };
    sources.source_boundaries.reset(
        0,
        sources.text_byte_len,
        sources.source_byte_starts.items,
    );
    try font_shaping.collectGposAdjustmentsWithOptionsUsingGdefForShaping(
        font,
        sources.glyph_ids.items,
        &sources.gpos_adjustments,
        allocator,
        .{
            .script_tag = script_tag,
            .language_tag = language_tag,
            .features = options.features,
            .normalized_variation_coords = options.normalized_variation_coords,
            .apply_all_if_unselected = false,
            .run_metadata = &metadata,
            .unsafe_glyphs = &sources.unsafe_glyphs,
        },
        gdef_metadata,
    );
    std.sort.heap(
        gpos.Adjustment,
        sources.gpos_adjustments.items,
        {},
        adjustmentLessThan,
    );
    try sources.attachment_links.resize(
        allocator,
        sources.glyph_ids.items.len,
    );
    @memset(sources.attachment_links.items, .{});
    var output_indices = std.ArrayList(usize).empty;
    defer output_indices.deinit(allocator);
    try output_indices.resize(allocator, sources.glyph_ids.items.len);
    @memset(output_indices.items, std.math.maxInt(usize));
    var output_links = std.ArrayList(attachment.Link).empty;
    defer output_links.deinit(allocator);
    try output_links.ensureTotalCapacity(
        allocator,
        sources.glyph_ids.items.len,
    );
    try layout_buffer.glyphs.ensureUnusedCapacity(
        allocator,
        sources.glyph_ids.items.len,
    );
    const output_start = layout_buffer.glyphs.items.len;
    const invisible_glyph_id = try font.glyphIndex(' ');

    var adjustment_cursor: usize = 0;
    for (sources.glyph_ids.items, 0..) |glyph_id, index| {
        const source = if (index < sources.glyph_sources.items.len)
            sources.glyph_sources.items[index]
        else
            index;
        if (source >= sources.codepoints.items.len or
            source >= sources.source_byte_starts.items.len or
            source >= sources.source_byte_ends.items.len)
        {
            return error.InvalidShapingInput;
        }
        const adjustment = findAdjustment(
            sources.gpos_adjustments.items,
            index,
            &adjustment_cursor,
        );
        const was_substituted = index < sources.glyph_substituted.items.len and
            sources.glyph_substituted.items[index];
        const codepoint = sources.codepoints.items[source];
        const visible_not_found_selector =
            options.not_found_variation_selector_glyph != null and
            unicode.isVariationSelector(codepoint) and
            !was_substituted;
        const hide_default_ignorable =
            unicode.isDefaultIgnorableForShaping(codepoint) and
            !was_substituted and
            !visible_not_found_selector;
        if (hide_default_ignorable and
            (options.remove_default_ignorables or invisible_glyph_id == 0))
        {
            continue;
        }
        const zero_advance = hide_default_ignorable or
            visible_not_found_selector;
        const advance_width = if (zero_advance)
            0
        else
            try horizontalAdvance(
                font,
                metrics_cache,
                glyph_id,
                options.normalized_variation_coords,
            );
        const adjusted_advance: f32 = if (zero_advance)
            0
        else if (adjustment.x_advance_absolute)
            @floatFromInt(adjustment.x_advance)
        else
            @floatFromInt(
                @as(i32, advance_width) +
                    @as(i32, adjustment.x_advance),
            );
        const cluster_source = if (index < sources.glyph_clusters.items.len)
            sources.glyph_clusters.items[index]
        else
            source;
        const span = source_span.forGlyph(
            index,
            source,
            cluster_source,
            sources.source_byte_starts.items,
            sources.source_byte_ends.items,
            &sources.ligature_components,
        ) orelse return error.InvalidShapingInput;
        const output_index = layout_buffer.glyphs.items.len - output_start;
        output_indices.items[index] = output_index;
        layout_buffer.glyphs.appendAssumeCapacity(GlyphPosition{
            .glyph_id = if (hide_default_ignorable)
                invisible_glyph_id
            else
                glyph_id,
            .synthetic_glyph_id = if (visible_not_found_selector)
                options.not_found_variation_selector_glyph
            else
                null,
            .codepoint = codepoint,
            .cluster = span.start,
            .source_byte_len = span.end - span.start,
            .flags = .{
                .unsafe_to_break_before = sources.unsafe_glyphs.isUnsafeBefore(index) or
                    sources.source_boundaries.isUnsafeBeforeByte(
                        span.start,
                    ),
            },
            .x_advance = adjusted_advance * scale,
            .y_advance = if (zero_advance)
                0
            else
                @as(f32, @floatFromInt(adjustment.y_advance)) * scale,
            .x_offset = if (zero_advance)
                0
            else
                @as(f32, @floatFromInt(adjustment.x_placement)) * scale,
            .y_offset = if (zero_advance)
                0
            else
                (@as(f32, @floatFromInt(adjustment.y_placement)) +
                    @as(f32, @floatFromInt(adjustment.attachment_cross_offset))) * scale,
        });
        sources.attachment_links.items[index] = attachmentLink(adjustment);
        output_links.appendAssumeCapacity(.{});
    }
    for (sources.attachment_links.items, 0..) |link, input_index| {
        const output_index = output_indices.items[input_index];
        if (output_index == std.math.maxInt(usize) or
            output_index >= output_links.items.len)
        {
            continue;
        }
        const parent = link.parent_index orelse {
            output_links.items[output_index] = link;
            continue;
        };
        if (parent >= output_indices.items.len) continue;
        const output_parent = output_indices.items[parent];
        if (output_parent == std.math.maxInt(usize)) continue;
        var mapped = link;
        mapped.parent_index = output_parent;
        output_links.items[output_index] = mapped;
    }
    attachment.propagateOffsets(
        GlyphPosition,
        layout_buffer.glyphs.items[output_start..],
        output_links.items,
        .forward,
        .horizontal,
    );

    if (featureEnabled(
        @import("../../../unicode.zig").tag("kern"),
        options.features,
    )) {
        const kern = try font_shaping.kernLookupForShaping(
            font,
        );
        for (sources.glyph_ids.items, 0..) |glyph_id, index| {
            if (index == 0) continue;
            const output_index = output_indices.items[index];
            if (output_index == std.math.maxInt(usize)) continue;
            const value = try kern.kerning(
                sources.glyph_ids.items[index - 1],
                glyph_id,
            );
            layout_buffer.glyphs.items[output_start + output_index]
                .x_advance += @as(f32, @floatFromInt(value)) * scale;
        }
    }
}

fn horizontalAdvance(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_id: GlyphId,
    normalized_coords: []const f32,
) !u16 {
    if (metrics_cache) |cache| {
        return (try cache.horizontalMetricsAtCoords(
            font,
            glyph_id,
            normalized_coords,
        )).advance_width;
    }
    if (normalized_coords.len == 0) {
        return (try font.horizontalMetrics(glyph_id)).advance_width;
    }
    return (try font.horizontalMetricsAtCoords(
        glyph_id,
        normalized_coords,
    )).advance_width;
}

fn adjustmentLessThan(_: void, lhs: gpos.Adjustment, rhs: gpos.Adjustment) bool {
    return lhs.index < rhs.index;
}

fn findAdjustment(
    adjustments: []const gpos.Adjustment,
    index: usize,
    cursor: *usize,
) gpos.Adjustment {
    while (cursor.* < adjustments.len and adjustments[cursor.*].index < index) {
        cursor.* += 1;
    }
    if (cursor.* < adjustments.len and adjustments[cursor.*].index == index) {
        return adjustments[cursor.*];
    }
    return .{ .index = index };
}

fn attachmentLink(adjustment: gpos.Adjustment) attachment.Link {
    return switch (adjustment.attachment_type) {
        .none => .{},
        .mark => .{
            .kind = .mark,
            .parent_index = adjustment.attachment_parent_index,
            .cross_axis_resolved = true,
        },
        .cursive => .{
            .kind = .cursive,
            .parent_index = adjustment.attachment_parent_index,
        },
    };
}

fn featureEnabled(
    tag: u32,
    overrides: []const @import("../../../unicode.zig").FeatureOverride,
) bool {
    for (overrides) |override| {
        if (override.tag == tag) return override.enabled;
    }
    return true;
}
