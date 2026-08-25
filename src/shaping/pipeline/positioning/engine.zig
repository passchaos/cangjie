//! AAT kerx and legacy kern planning after GPOS engine selection.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const aat_kerx = @import("../../../aat_kerx.zig");
const fallback_mark = @import("../../fallback/mark.zig");
const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gsub_features = @import("../gsub/features.zig");
const pipeline_types = @import("../types.zig");
const policy = @import("policy.zig");

pub const Result = struct {
    kerx_lookup: ?@import("../../../font.zig").KerxLookupForShaping,
    kern_lookup: ?@import("../../../font.zig").KernLookupForShaping,
    summary: aat_kerx.Summary,
    kerning_enabled: bool,
    has_state_attachments: bool,
    has_gpos_positioning: bool,
    fallback_mark_enabled: bool,
};

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    glyph_ids: []const GlyphId,
    codepoints: []const u21,
    glyph_source_indices: []const usize,
    glyph_substituted: []const bool,
    gdef_metadata: GdefLookupMetadata,
    use_kerx_positioning: bool,
    has_gpos_attachments: bool,
    early_zero_mark_shape: bool,
    options: pipeline_types.LookupOptions,
    simple_pair_eligible: *std.ArrayList(bool),
    kerx_adjustments: *std.ArrayList(aat_kerx.Adjustment),
};

pub fn prepare(input: Input) !Result {
    const has_gdef_glyph_classes =
        input.gdef_metadata.glyph_classes != null;
    const has_gpos_positioning =
        font_shaping.hasGposTableForShaping(
            input.font,
        ) and
        !input.use_kerx_positioning;
    const kerning_enabled = gsub_features.enabled(
        if (input.options.writing_mode.isVertical())
            @import("../../../unicode.zig").tag("vkrn")
        else
            @import("../../../unicode.zig").tag("kern"),
        input.options.features,
        !input.options.writing_mode.isVertical(),
    );
    const kerx_lookup = if (input.use_kerx_positioning)
        try font_shaping.kerxLookupForShaping(
            input.font,
        )
    else
        null;
    var summary = aat_kerx.Summary{};
    if (kerx_lookup) |lookup| {
        const vertical = input.options.writing_mode.isVertical();
        if (try lookup.hasOutputSideAdjustments(vertical, kerning_enabled)) {
            try input.simple_pair_eligible.resize(
                input.allocator,
                input.glyph_ids.len,
            );
            for (
                input.glyph_ids,
                input.simple_pair_eligible.items,
                0..,
            ) |glyph_id, *eligible, index| {
                const source_index =
                    if (index < input.glyph_source_indices.len)
                        @min(
                            input.glyph_source_indices[index],
                            input.codepoints.len -| 1,
                        )
                    else
                        @min(index, input.codepoints.len -| 1);
                const source_codepoint =
                    if (input.codepoints.len == 0)
                        0
                    else
                        input.codepoints[source_index];
                const was_substituted =
                    index < input.glyph_substituted.len and
                    input.glyph_substituted[index];
                eligible.* = !policy.kerxMachineSkipsGlyph(
                    input.gdef_metadata.glyphClass(glyph_id),
                    has_gdef_glyph_classes,
                    source_codepoint,
                    was_substituted,
                );
            }
            summary = try lookup.collectOrderedAdjustments(
                input.glyph_ids,
                input.kerx_adjustments,
                input.allocator,
                vertical,
                input.options.shapingDirection() == .rtl,
                kerning_enabled,
                input.simple_pair_eligible.items,
                input.options.normalized_variation_coords,
            );
        }
    }
    const has_state_attachments =
        hasKerxAttachments(input.kerx_adjustments.items);
    const fallback_mark_enabled = fallback_mark.enabled(
        input.options.script_tag,
        input.early_zero_mark_shape,
        has_gpos_positioning,
        input.has_gpos_attachments or has_state_attachments,
        input.use_kerx_positioning,
        input.options.writing_mode.isVertical(),
    );
    const kern_lookup = if (kerx_lookup == null and
        !font_shaping.hasKerxTableForShaping(
            input.font,
        ) and
        !input.options.writing_mode.isVertical() and
        shouldApplyLegacyKernFallback(input.options.script_tag) and
        kerning_enabled)
        font_shaping.kernLookupForShaping(
            input.font,
        ) catch |err| switch (err) {
            error.MissingTable => null,
            else => return err,
        }
    else
        null;
    return .{
        .kerx_lookup = kerx_lookup,
        .kern_lookup = kern_lookup,
        .summary = summary,
        .kerning_enabled = kerning_enabled,
        .has_state_attachments = has_state_attachments,
        .has_gpos_positioning = has_gpos_positioning,
        .fallback_mark_enabled = fallback_mark_enabled,
    };
}

fn hasKerxAttachments(adjustments: []const aat_kerx.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none and
            adjustment.attachment_parent_index != null)
        {
            return true;
        }
    }
    return false;
}

fn shouldApplyLegacyKernFallback(
    script_tag: @import("../../../unicode.zig").OpenTypeScriptTag,
) bool {
    const indic = @import("../../../indic.zig");
    const myanmar = @import("../../../myanmar.zig");
    const use_shaper = @import("../../../use_shaper.zig");
    if (indic.shouldShape(script_tag) or
        use_shaper.shouldShape(script_tag) or
        myanmar.shouldShape(script_tag))
    {
        return false;
    }
    return switch (script_tag) {
        .deva, .dev2, .dev3, .hang, .khmr => false,
        else => true,
    };
}
