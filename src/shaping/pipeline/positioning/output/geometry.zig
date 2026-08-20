//! Per-glyph advance, origin, and fallback-mark geometry.

const font_shaping = @import("../../../../font.zig").shaping;
const aat_kerx = @import("../../../../aat_kerx.zig");
const fallback_mark = @import("../../../fallback/mark.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const gpos = @import("../../../../gpos.zig");
const policy = @import("../policy.zig");
const space_fallback = @import("../../../../space_fallback.zig");
const unicode = @import("../../../../unicode.zig");
const types = @import("types.zig");

pub const Result = struct {
    horizontal_advance: f32,
    vertical_advance: f32,
    x_offset: f32,
    y_offset: f32,
    orientation: @import("../../../../layout/glyph_position.zig").Orientation,
};

pub fn resolve(
    input: types.Input,
    glyph_id: GlyphId,
    source_codepoint: u21,
    span_start: usize,
    glyph_class: @import("../../../../font.zig").GlyphClass,
    adjustment: gpos.Adjustment,
    kerx_adjustment: aat_kerx.Adjustment,
    synthetic_base: bool,
    hide_default_ignorable: bool,
    visible_not_found_variation_selector: bool,
    kern_x_advance: f32,
    kern_x_offset: f32,
    fallback_mark_base: *?fallback_mark.Base,
) !Result {
    const metrics = try policy.horizontalMetrics(
        input.font,
        input.metrics_cache,
        glyph_id,
        input.options.normalized_variation_coords,
    );
    const adjustment_x_advance = if (adjustment.x_advance_absolute)
        @as(f32, @floatFromInt(adjustment.x_advance)) -
            @as(f32, @floatFromInt(metrics.advance_width))
    else
        @as(f32, @floatFromInt(adjustment.x_advance));
    const attachment_cross_x =
        if (input.options.writing_mode.isVertical())
            @as(f32, @floatFromInt(adjustment.attachment_cross_offset)) *
                input.scale
        else
            0.0;
    const attachment_cross_y =
        if (input.options.writing_mode.isVertical())
            0.0
        else
            @as(f32, @floatFromInt(adjustment.attachment_cross_offset)) *
                input.scale;
    const gpos_x_offset =
        @as(f32, @floatFromInt(adjustment.x_placement)) * input.scale +
        attachment_cross_x;
    const mark_zeroing = policy.markAdvanceZeroing(
        input.early_zero_mark_shape,
        glyph_class,
        input.gdef_metadata.glyph_classes != null,
        source_codepoint,
        synthetic_base,
        adjustment.attachment_type == .mark,
        input.has_gpos_positioning,
        input.options,
    );
    const fallback_space_advance =
        if (!input.options.writing_mode.isVertical() and
        space_fallback.mayNeedHorizontalAdvanceFallback(source_codepoint))
            try space_fallback.advanceWidth(
                input.font,
                source_codepoint,
                glyph_id,
                metrics.advance_width,
            )
        else
            null;
    const default_vertical_advance_units: i32 =
        @as(i32, input.font.ascender) - @as(i32, input.font.descender);
    const fallback_space_vertical_advance =
        if (input.options.writing_mode.isVertical() and
        space_fallback.mayNeedVerticalAdvanceFallback(source_codepoint))
            try space_fallback.advanceHeight(
                input.font,
                source_codepoint,
                glyph_id,
                default_vertical_advance_units,
            )
        else
            null;
    const base_advance = if (hide_default_ignorable or
        mark_zeroing.zero_advance)
        0
    else if (fallback_space_advance) |value|
        value
    else
        metrics.advance_width;
    const horizontal_advance = if (hide_default_ignorable)
        0
    else
        (@as(f32, @floatFromInt(base_advance)) +
            adjustment_x_advance +
            @as(f32, @floatFromInt(kerx_adjustment.x_advance))) *
            input.scale +
            kern_x_advance;
    const orientation = policy.glyphOrientation(
        source_codepoint,
        input.options.writing_mode,
        input.options.text_orientation,
    );
    const use_sideways_vertical_advance = orientation == .sideways;
    const vertical_metrics =
        if (input.options.writing_mode.isVertical())
            try policy.verticalMetrics(
                input.font,
                input.metrics_cache,
                glyph_id,
                input.options.normalized_variation_coords,
            )
        else
            null;
    const unzeroed_vertical_advance =
        if (use_sideways_vertical_advance)
            (@as(f32, @floatFromInt(metrics.advance_width)) +
                adjustment_x_advance +
                @as(f32, @floatFromInt(kerx_adjustment.y_advance))) *
                input.scale
        else if (vertical_metrics) |value|
            @as(f32, @floatFromInt(value.advance_height)) * input.scale
        else
            input.font_size;
    const vertical_advance = if (mark_zeroing.zero_advance)
        0
    else if (fallback_space_vertical_advance) |value|
        (@as(f32, @floatFromInt(value)) +
            @as(f32, @floatFromInt(kerx_adjustment.y_advance))) *
            input.scale
    else if (use_sideways_vertical_advance)
        unzeroed_vertical_advance
    else if (vertical_metrics) |value|
        (@as(f32, @floatFromInt(value.advance_height)) +
            @as(f32, @floatFromInt(kerx_adjustment.y_advance))) *
            input.scale
    else
        input.font_size +
            @as(f32, @floatFromInt(kerx_adjustment.y_advance)) * input.scale;
    const vertical_x_offset = if (input.options.writing_mode.isVertical())
        -@as(
            f32,
            @floatFromInt(@divTrunc(@as(i32, metrics.advance_width), 2)),
        ) * input.scale
    else
        0.0;
    const vertical_y_offset =
        if (input.options.writing_mode.isVertical()) origin: {
            const origin_y = try font_shaping.shapingVerticalOriginYForShaping(
                input.font,
                glyph_id,
                input.options.normalized_variation_coords,
            );
            break :origin -@as(f32, @floatFromInt(origin_y)) * input.scale;
        } else 0.0;
    const zeroed_mark_x_offset =
        if (mark_zeroing.adjust_offsets and
        !input.options.writing_mode.isVertical())
            -@as(f32, @floatFromInt(metrics.advance_width)) * input.scale
        else
            0.0;
    const zeroed_mark_y_offset =
        if (mark_zeroing.adjust_offsets and
        input.options.writing_mode.isVertical())
            -unzeroed_vertical_advance
        else
            0.0;
    var fallback_mark_offset = fallback_mark.Offset{};
    if (input.fallback_mark_enabled and
        unicode.isNonspacingMarkCodepoint(source_codepoint))
    {
        if (fallback_mark_base.*) |*base| {
            fallback_mark_offset = fallback_mark.offset(
                input.font,
                glyph_id,
                source_codepoint,
                span_start,
                base,
                input.scale,
            ) catch .{};
            fallback_mark_offset.recordBreakSafety(
                input.source_boundaries,
                input.allocator,
            ) catch {};
        }
    }
    const kerx_state_x_offset =
        @as(f32, @floatFromInt(kerx_adjustment.x_offset)) * input.scale;
    const x_offset =
        if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (input.options.writing_mode.isVertical())
            if (kerx_adjustment.cross_stream_assigned or
                kerx_adjustment.cross_stream_reset)
                kerx_state_x_offset
            else if (kerx_adjustment.attachment_type == .cursive and
                kerx_adjustment.attachment_parent_index != null)
                vertical_x_offset + kerx_state_x_offset
            else
                vertical_x_offset +
                    gpos_x_offset +
                    kerx_state_x_offset +
                    zeroed_mark_x_offset +
                    fallback_mark_offset.x
        else
            gpos_x_offset +
                kerx_state_x_offset +
                kern_x_offset +
                zeroed_mark_x_offset +
                fallback_mark_offset.x;
    const y_offset =
        if (hide_default_ignorable or visible_not_found_variation_selector)
            0
        else if (input.options.writing_mode.isVertical())
            vertical_y_offset +
                @as(
                    f32,
                    @floatFromInt(
                        adjustment.y_placement + kerx_adjustment.y_offset,
                    ),
                ) * input.scale +
                attachment_cross_y +
                zeroed_mark_y_offset +
                fallback_mark_offset.y
        else
            @as(
                f32,
                @floatFromInt(
                    adjustment.y_placement + kerx_adjustment.y_offset,
                ),
            ) * input.scale +
                attachment_cross_y +
                zeroed_mark_y_offset +
                fallback_mark_offset.y;
    return .{
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
        .x_offset = x_offset,
        .y_offset = y_offset,
        .orientation = orientation,
    };
}
