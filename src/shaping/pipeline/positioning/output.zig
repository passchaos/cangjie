//! Final glyph construction after GSUB, GPOS, kerx, and legacy kern.
//!
//! The stage owns the one place where font-unit adjustments become public
//! user-space geometry. Input arrays remain post-GSUB indexed; default-
//! ignorable removal records an explicit input-to-output map before attachment
//! links are compacted.

const std = @import("std");

const aat_kerx = @import("../../../aat_kerx.zig");
const fallback_mark = @import("../../fallback/mark.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const GlyphPosition =
    @import("../../../layout/glyph_position.zig").GlyphPosition;
const gpos = @import("../../../gpos.zig");
const ligature_provenance =
    @import("../../../ligature_provenance.zig");
const stch_feature = @import("../../features/stch/root.zig");
const unicode = @import("../../../unicode.zig");
const ShapeStageProfile = @import("../../../shape_profile.zig").ShapeStageProfile;
const arabic = @import("output/arabic.zig");
const geometry = @import("output/geometry.zig");
const types = @import("output/types.zig");
const adjustments = @import("adjustments.zig");
const attachments = @import("attachments.zig");
const policy = @import("policy.zig");
const source_span = @import("source_span.zig");

pub const Input = types.Input;
pub const Result = types.Result;

pub fn emit(input: Input) !Result {
    if (canEmitSimpleAsciiHorizontal(input)) {
        return emitSimpleAsciiHorizontal(input);
    }
    if (canEmitSimpleDevanagariHorizontal(input)) {
        return emitSimpleDevanagariHorizontal(input);
    }
    const segment_glyph_start = input.output.items.len;
    try input.output.ensureUnusedCapacity(input.allocator, input.scratch.glyph_ids.items.len);

    const needs_attachment_remapping =
        input.has_gpos_attachments or input.has_kerx_state_attachments;
    if (needs_attachment_remapping) {
        try input.scratch.attachment_links.resize(
            input.allocator,
            input.scratch.glyph_ids.items.len,
        );
        @memset(input.scratch.attachment_links.items, .{});
        try input.scratch.glyph_output_indices.resize(
            input.allocator,
            input.scratch.glyph_ids.items.len,
        );
        @memset(
            input.scratch.glyph_output_indices.items,
            std.math.maxInt(usize),
        );
    }

    var previous_kern_glyph: ?GlyphId = null;
    var previous_kern_output_index: ?usize = null;
    var fallback_mark_base: ?fallback_mark.Base = null;
    var adjustment_cursor: usize = 0;
    const loop_start = profileNow(input.profile, input.profile_io);

    for (input.scratch.glyph_ids.items, 0..) |input_glyph_id, index| {
        const source_index = if (input.ascii_source)
            input.scratch.glyph_source_indices.items[index]
        else if (index < input.scratch.glyph_source_indices.items.len)
            @min(
                input.scratch.glyph_source_indices.items[index],
                input.scratch.codepoints.items.len -| 1,
            )
        else
            @min(index, input.scratch.codepoints.items.len -| 1);
        const cluster_index = if (input.ascii_source)
            input.scratch.glyph_cluster_indices.items[index]
        else if (index < input.scratch.glyph_cluster_indices.items.len)
            @min(
                input.scratch.glyph_cluster_indices.items[index],
                input.scratch.clusters.items.len -| 1,
            )
        else
            source_index;
        const span = if (input.ascii_source)
            source_span.forAsciiGlyph(
                index,
                source_index,
                cluster_index,
                input.scratch.clusters.items,
                input.scratch.source_ends.items,
                &input.scratch.ligature_components,
            )
        else
            source_span.forGlyph(
                index,
                source_index,
                cluster_index,
                input.scratch.clusters.items,
                input.scratch.source_ends.items,
                &input.scratch.ligature_components,
            ) orelse source_span.Span{
                .start = input.cluster_base,
                .end = input.cluster_base,
            };
        const source_codepoint = if (input.ascii_source)
            input.scratch.codepoints.items[source_index]
        else if (input.scratch.codepoints.items.len == 0)
            0
        else
            input.scratch.codepoints.items[source_index];
        var glyph_id = input_glyph_id;
        if (input.arabic_joining_features) |features| {
            if (try arabic.fallbackGlyph(
                input.font,
                input.glyph_index_cache,
                glyph_id,
                source_codepoint,
                source_index,
                features,
            )) |fallback_glyph| {
                glyph_id = fallback_glyph;
            }
        }
        const glyph_class = if (input.run_may_have_mark_attachments or
            input.kerx_lookup != null)
            input.gdef_metadata.glyphClass(glyph_id)
        else
            @import("../../../font.zig").GlyphClass.unclassified;
        const kerx_adjustment = if (index < input.kerx_adjustments.len)
            input.kerx_adjustments[index]
        else
            aat_kerx.Adjustment{};
        var kern_x_advance: f32 = 0;
        var kern_x_offset: f32 = 0;
        const needs_substitution_state = input.kerx_lookup != null or
            input.has_default_ignorable or
            input.options.not_found_variation_selector_glyph != null;
        const was_substituted = needs_substitution_state and
            (input.ascii_source or
                index < input.scratch.glyph_substituted.items.len) and
            input.scratch.glyph_substituted.items[index];
        const kerx_skips_glyph =
            input.kerx_lookup != null and policy.kerxMachineSkipsGlyph(
                glyph_class,
                input.gdef_metadata.glyph_classes != null,
                source_codepoint,
                was_substituted,
            );
        const active_kern = if (input.kerx_lookup) |lookup|
            if (input.kerning_enabled and !kerx_skips_glyph)
                if (previous_kern_glyph) |previous|
                    try lookup.kerning(
                        previous,
                        glyph_id,
                        input.options.writing_mode.isVertical(),
                        input.options.normalized_variation_coords,
                    )
                else
                    0
            else
                0
        else if (input.kern_lookup) |lookup|
            if (previous_kern_glyph) |previous|
                try lookup.kerning(previous, glyph_id)
            else
                0
        else
            0;

        if (!input.options.writing_mode.isVertical() and
            previous_kern_glyph != null)
        {
            const previous_adjustment = adjustments.find(
                input.gpos_adjustments,
                index - 1,
                &adjustment_cursor,
            );
            if (input.kerx_lookup != null or
                !previous_adjustment.pair_positioned)
            {
                if (active_kern != 0) {
                    if (previous_kern_output_index) |previous_output_index| {
                        if (input.kern_lookup != null and index != 0) {
                            try input.source_boundaries.markGlyphPair(
                                input.allocator,
                                input.scratch.glyph_source_indices.items,
                                index - 1,
                                index,
                            );
                        }
                        const kern_1 = active_kern >> 1;
                        const kern_2 = active_kern - kern_1;
                        input.output.items[previous_output_index].x_advance +=
                            @as(f32, @floatFromInt(kern_1)) * input.scale;
                        kern_x_advance =
                            @as(f32, @floatFromInt(kern_2)) * input.scale;
                        kern_x_offset = kern_x_advance;
                    }
                }
            }
        }

        const adjustment = adjustments.find(
            input.gpos_adjustments,
            index,
            &adjustment_cursor,
        );
        const provenance = if (input.ascii_source)
            input.scratch.ligature_components.infos.items[index]
        else if (index < input.scratch.ligature_components.infos.items.len)
            input.scratch.ligature_components.infos.items[index]
        else
            ligature_provenance.Info{};
        const stch_action: ligature_provenance.StchAction =
            provenance.flags.stch_action;
        const synthetic_base = provenance.flags.synthetic_base;
        const visible_not_found_variation_selector =
            input.options.not_found_variation_selector_glyph != null and
            unicode.isVariationSelector(source_codepoint) and
            !was_substituted and
            !synthetic_base;
        const hide_default_ignorable = input.has_default_ignorable and
            unicode.isDefaultIgnorableForShaping(source_codepoint) and
            !was_substituted and
            !synthetic_base and
            !visible_not_found_variation_selector;
        const skip_default_ignorable = hide_default_ignorable and
            (input.options.remove_default_ignorables or
                input.invisible_glyph_id == 0 or
                (glyph_id == 0 and
                    unicode.isVariationSelector(source_codepoint) and
                    !policy.variationSelectorFallbackShouldRender(
                        index,
                        source_index,
                        &input.scratch.ligature_components,
                    )));
        if (skip_default_ignorable) {
            if (needs_attachment_remapping) {
                input.scratch.glyph_output_indices.items[index] =
                    std.math.maxInt(usize);
            }
            if (input.kerx_lookup == null) previous_kern_glyph = glyph_id;
            continue;
        }

        const output_glyph_id =
            if (hide_default_ignorable and input.invisible_glyph_id != 0)
                input.invisible_glyph_id
            else
                glyph_id;
        const synthetic_glyph_id =
            if (visible_not_found_variation_selector)
                input.options.not_found_variation_selector_glyph
            else
                null;
        const resolved = try geometry.resolve(
            input,
            glyph_id,
            source_codepoint,
            span.start,
            glyph_class,
            adjustment,
            kerx_adjustment,
            synthetic_base,
            hide_default_ignorable,
            visible_not_found_variation_selector,
            kern_x_advance,
            kern_x_offset,
            &fallback_mark_base,
        );
        const positional_boundary_unsafe =
            input.gpos_unsafe_glyphs.isUnsafeBefore(index) or
            input.source_boundaries.isUnsafeBeforeByte(span.start);
        const safe_to_insert_tatweel =
            !positional_boundary_unsafe and
            input.source_boundaries.isSafeTatweelBeforeByte(span.start);
        if (needs_attachment_remapping) {
            input.scratch.glyph_output_indices.items[index] =
                input.output.items.len - segment_glyph_start;
        }
        input.output.appendAssumeCapacity(.{
            .glyph_id = output_glyph_id,
            .synthetic_glyph_id = synthetic_glyph_id,
            .codepoint = source_codepoint,
            .cluster = span.start,
            .source_byte_len = span.end - span.start,
            .flags = .{
                // HarfBuzz exposes tatweel insertion points as unsafe normal
                // line breaks: callers may reshape there only after actually
                // inserting the elongation character.
                .unsafe_to_break_before = positional_boundary_unsafe or
                    safe_to_insert_tatweel,
                .safe_to_insert_tatweel = safe_to_insert_tatweel,
            },
            .x_advance = if (visible_not_found_variation_selector)
                0
            else if (input.options.writing_mode.isVertical())
                0.0
            else
                resolved.horizontal_advance,
            .y_advance = if (hide_default_ignorable or
                visible_not_found_variation_selector)
                0
            else if (input.options.writing_mode.isVertical())
                resolved.vertical_advance
            else
                @as(f32, @floatFromInt(adjustment.y_advance)) * input.scale,
            .x_offset = resolved.x_offset,
            .y_offset = resolved.y_offset,
            .orientation = resolved.orientation,
        });
        if (input.options.writing_mode.isVertical() and active_kern != 0) {
            if (previous_kern_output_index) |previous_output_index| {
                const kern_1 = active_kern >> 1;
                const kern_2 = active_kern - kern_1;
                input.output.items[previous_output_index].y_advance +=
                    @as(f32, @floatFromInt(kern_1)) * input.scale;
                input.output.items[input.output.items.len - 1].y_advance +=
                    @as(f32, @floatFromInt(kern_2)) * input.scale;
                input.output.items[input.output.items.len - 1].y_offset +=
                    @as(f32, @floatFromInt(kern_2)) * input.scale;
            }
        }
        try stch_feature.appendOutput(
            input.allocator,
            &input.scratch.stch_actions,
            stch_action,
            input.output.items.len - segment_glyph_start,
        );
        if (needs_attachment_remapping and !hide_default_ignorable) {
            input.scratch.attachment_links.items[index] =
                attachments.linkFor(kerx_adjustment, adjustment);
        }
        if (input.fallback_mark_enabled and
            !hide_default_ignorable and
            !visible_not_found_variation_selector and
            !unicode.isNonspacingMarkCodepoint(source_codepoint))
        {
            fallback_mark_base = fallback_mark.baseForGlyph(
                input.font,
                glyph_id,
                span.end,
                resolved.y_offset,
                resolved.horizontal_advance,
                input.scale,
                input.options.shapingDirection() == .ltr,
            ) catch null;
        }
        if (!kerx_skips_glyph) {
            previous_kern_glyph = glyph_id;
            previous_kern_output_index = input.output.items.len - 1;
        }
    }

    if (input.profile) |profile| {
        profile.position_loop_ns += profileElapsed(loop_start, input.profile_io);
        profile.position_output_glyphs +=
            input.output.items.len - segment_glyph_start;
    }
    return .{ .segment_glyph_start = segment_glyph_start };
}

/// Emit the common Latin word-run shape without carrying the full AAT,
/// vertical, default-ignorable, mark, and fallback policy tree through every
/// glyph. The predicate deliberately names every dormant subsystem; feature
/// overrides may still produce arbitrary scalar GPOS adjustments, so this
/// path preserves all four adjustment fields and both break-safety sources.
fn canEmitSimpleAsciiHorizontal(input: Input) bool {
    return input.ascii_source and
        !input.options.writing_mode.isVertical() and
        input.arabic_joining_features == null and
        input.kerx_lookup == null and
        input.kern_lookup == null and
        !input.has_gpos_attachments and
        !input.has_kerx_state_attachments and
        !input.run_may_have_mark_attachments and
        !input.has_default_ignorable and
        !input.early_zero_mark_shape and
        !input.fallback_mark_enabled and
        input.options.not_found_variation_selector_glyph == null;
}

fn emitSimpleAsciiHorizontal(input: Input) !Result {
    const segment_glyph_start = input.output.items.len;
    try input.output.ensureUnusedCapacity(
        input.allocator,
        input.scratch.glyph_ids.items.len,
    );

    var adjustment_cursor: usize = 0;
    const loop_start = profileNow(input.profile, input.profile_io);
    for (input.scratch.glyph_ids.items, 0..) |glyph_id, index| {
        const source_index = input.scratch.glyph_source_indices.items[index];
        const cluster_index = input.scratch.glyph_cluster_indices.items[index];
        const span = source_span.forAsciiGlyph(
            index,
            source_index,
            cluster_index,
            input.scratch.clusters.items,
            input.scratch.source_ends.items,
            &input.scratch.ligature_components,
        );
        const adjustment = adjustments.find(
            input.gpos_adjustments,
            index,
            &adjustment_cursor,
        );
        const metrics = try policy.horizontalMetrics(
            input.font,
            input.metrics_cache,
            glyph_id,
            input.options.normalized_variation_coords,
        );
        const adjusted_advance = if (adjustment.x_advance_absolute)
            adjustment.x_advance
        else
            @as(i32, metrics.advance_width) + adjustment.x_advance;
        const positional_boundary_unsafe =
            input.gpos_unsafe_glyphs.isUnsafeBefore(index) or
            input.source_boundaries.isUnsafeBeforeByte(span.start);
        const safe_to_insert_tatweel =
            !positional_boundary_unsafe and
            input.source_boundaries.isSafeTatweelBeforeByte(span.start);

        input.output.appendAssumeCapacity(.{
            .glyph_id = glyph_id,
            .codepoint = input.scratch.codepoints.items[source_index],
            .cluster = span.start,
            .source_byte_len = span.end - span.start,
            .flags = .{
                .unsafe_to_break_before = positional_boundary_unsafe or
                    safe_to_insert_tatweel,
                .safe_to_insert_tatweel = safe_to_insert_tatweel,
            },
            .x_advance = @as(f32, @floatFromInt(adjusted_advance)) *
                input.scale,
            .y_advance = @as(f32, @floatFromInt(adjustment.y_advance)) *
                input.scale,
            .x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) *
                input.scale,
            .y_offset = @as(
                f32,
                @floatFromInt(
                    adjustment.y_placement +
                        adjustment.attachment_cross_offset,
                ),
            ) * input.scale,
            .orientation = .horizontal,
        });
        const provenance =
            input.scratch.ligature_components.infos.items[index];
        try stch_feature.appendOutput(
            input.allocator,
            &input.scratch.stch_actions,
            provenance.flags.stch_action,
            input.output.items.len - segment_glyph_start,
        );
    }

    if (input.profile) |profile| {
        profile.position_loop_ns += profileElapsed(loop_start, input.profile_io);
        profile.position_output_glyphs +=
            input.output.items.len - segment_glyph_start;
    }
    return .{ .segment_glyph_start = segment_glyph_start };
}

fn canEmitSimpleDevanagariHorizontal(input: Input) bool {
    // Unlike the ASCII path, this keeps general ligature-span recovery. Indic
    // output can otherwise omit branches for AAT, invisibles, fallback marks,
    // and vertical metrics once the surrounding pipeline proves those modes
    // inactive. The `stch` feature is Arabic-only, so no action sidecar needs
    // to be materialized here.
    return input.options.script_tag == .dev2 and
        input.options.direction == .ltr and
        !input.options.writing_mode.isVertical() and
        input.arabic_joining_features == null and
        input.kerx_lookup == null and
        input.kern_lookup == null and
        !input.has_gpos_attachments and
        !input.has_kerx_state_attachments and
        !input.has_default_ignorable and
        !input.early_zero_mark_shape and
        !input.fallback_mark_enabled and
        input.options.not_found_variation_selector_glyph == null;
}

noinline fn emitSimpleDevanagariHorizontal(
    input: Input,
) linksection(@import("../../../shaping_sections.zig").isolated_hotpaths) !Result {
    const segment_glyph_start = input.output.items.len;
    try input.output.ensureUnusedCapacity(
        input.allocator,
        input.scratch.glyph_ids.items.len,
    );

    var adjustment_cursor: usize = 0;
    const loop_start = profileNow(input.profile, input.profile_io);
    for (input.scratch.glyph_ids.items, 0..) |glyph_id, index| {
        const source_index = input.scratch.glyph_source_indices.items[index];
        const cluster_index = input.scratch.glyph_cluster_indices.items[index];
        const span = source_span.forGlyph(
            index,
            source_index,
            cluster_index,
            input.scratch.clusters.items,
            input.scratch.source_ends.items,
            &input.scratch.ligature_components,
        ) orelse source_span.Span{
            .start = input.cluster_base,
            .end = input.cluster_base,
        };
        const adjustment = adjustments.find(
            input.gpos_adjustments,
            index,
            &adjustment_cursor,
        );
        const metrics = try policy.horizontalMetrics(
            input.font,
            input.metrics_cache,
            glyph_id,
            input.options.normalized_variation_coords,
        );
        const adjusted_advance = if (adjustment.x_advance_absolute)
            adjustment.x_advance
        else
            @as(i32, metrics.advance_width) + adjustment.x_advance;
        const positional_boundary_unsafe =
            input.gpos_unsafe_glyphs.isUnsafeBefore(index) or
            input.source_boundaries.isUnsafeBeforeByte(span.start);
        const safe_to_insert_tatweel =
            !positional_boundary_unsafe and
            input.source_boundaries.isSafeTatweelBeforeByte(span.start);

        input.output.appendAssumeCapacity(.{
            .glyph_id = glyph_id,
            .codepoint = input.scratch.codepoints.items[source_index],
            .cluster = span.start,
            .source_byte_len = span.end - span.start,
            .flags = .{
                .unsafe_to_break_before = positional_boundary_unsafe or
                    safe_to_insert_tatweel,
                .safe_to_insert_tatweel = safe_to_insert_tatweel,
            },
            .x_advance = @as(f32, @floatFromInt(adjusted_advance)) *
                input.scale,
            .y_advance = @as(f32, @floatFromInt(adjustment.y_advance)) *
                input.scale,
            .x_offset = @as(f32, @floatFromInt(adjustment.x_placement)) *
                input.scale,
            .y_offset = @as(f32, @floatFromInt(
                adjustment.y_placement + adjustment.attachment_cross_offset,
            )) * input.scale,
            .orientation = .horizontal,
        });
    }

    if (input.profile) |profile| {
        profile.position_loop_ns += profileElapsed(loop_start, input.profile_io);
        profile.position_output_glyphs +=
            input.output.items.len - segment_glyph_start;
    }
    return .{ .segment_glyph_start = segment_glyph_start };
}

fn profileNow(profile: ?*ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null)
        std.Io.Clock.now(.awake, io.?).nanoseconds
    else
        0;
}

fn profileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}
