//! Final positioned-glyph emission for the first ranged-GSUB contract.

const std = @import("std");

const attachment = @import("../../../attachment.zig");
const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gpos = @import("../../../gpos.zig");
const GlyphMetricsCache = @import("../../context/cache/root.zig").GlyphMetricsCache;
const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const layout = @import("../../../layout.zig");
const run_metadata = @import("../../run_metadata.zig");
const source_buffer = @import("source_buffer.zig");

pub fn collect(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    layout_buffer: *layout.LayoutBuffer,
    font_size: f32,
    sources: *source_buffer.Buffer,
    gdef_metadata: GdefLookupMetadata,
    script_tag: @import("../../../unicode.zig").OpenTypeScriptTag,
    language_tag: @import("../../../unicode.zig").OpenTypeLanguageTag,
    options: layout.ShapeOptions,
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
    try font.collectGposAdjustmentsWithOptionsUsingGdefForShaping(
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
    try layout_buffer.glyphs.ensureUnusedCapacity(
        allocator,
        sources.glyph_ids.items.len,
    );

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
        const advance_width = try horizontalAdvance(
            font,
            metrics_cache,
            glyph_id,
            options.normalized_variation_coords,
        );
        const adjustment = findAdjustment(
            sources.gpos_adjustments.items,
            index,
            &adjustment_cursor,
        );
        const adjusted_advance: f32 = if (adjustment.x_advance_absolute)
            @floatFromInt(adjustment.x_advance)
        else
            @floatFromInt(
                @as(i32, advance_width) +
                    @as(i32, adjustment.x_advance),
            );
        layout_buffer.glyphs.appendAssumeCapacity(GlyphPosition{
            .glyph_id = glyph_id,
            .codepoint = sources.codepoints.items[source],
            .cluster = sources.source_byte_starts.items[source],
            .source_byte_len = sources.source_byte_ends.items[source] -
                sources.source_byte_starts.items[source],
            .flags = .{
                .unsafe_to_break_before = sources.unsafe_glyphs.isUnsafeBefore(index) or
                    sources.source_boundaries.isUnsafeBeforeByte(
                        sources.source_byte_starts.items[source],
                    ),
            },
            .x_advance = adjusted_advance * scale,
            .y_advance = @as(f32, @floatFromInt(adjustment.y_advance)) * scale,
            .x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) * scale,
            .y_offset = (@as(f32, @floatFromInt(adjustment.y_placement)) +
                @as(f32, @floatFromInt(adjustment.attachment_cross_offset))) * scale,
        });
        sources.attachment_links.items[index] = attachmentLink(adjustment);
    }
    attachment.propagateOffsets(
        GlyphPosition,
        layout_buffer.glyphs.items[layout_buffer.glyphs.items.len - sources.glyph_ids.items.len ..],
        sources.attachment_links.items,
        .forward,
        .horizontal,
    );

    if (featureEnabled(
        @import("../../../unicode.zig").tag("kern"),
        options.features,
    )) {
        const kern = try font.kernLookupForShaping();
        for (layout_buffer.glyphs.items[layout_buffer.glyphs.items.len - sources.glyph_ids.items.len ..], 0..) |*glyph, index| {
            if (index == 0) continue;
            const value = try kern.kerning(
                sources.glyph_ids.items[index - 1],
                sources.glyph_ids.items[index],
            );
            glyph.x_advance += @as(f32, @floatFromInt(value)) * scale;
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
