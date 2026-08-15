//! Script, class, and orientation policies used by final positioning.

const Font = @import("../../../font.zig").Font;
const GlyphClass = @import("../../../font.zig").GlyphClass;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const indic = @import("../../../indic.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const cache = @import("../../context/cache/root.zig");
const pipeline_types = @import("../types.zig");
const unicode = @import("../../../unicode.zig");

pub const MarkAdvanceZeroing = struct {
    zero_advance: bool = false,
    adjust_offsets: bool = false,
};

pub fn kerxMachineSkipsGlyph(
    glyph_class: GlyphClass,
    has_gdef_glyph_classes: bool,
    source_codepoint: u21,
    was_substituted: bool,
) bool {
    if (glyph_class == .mark) return true;
    // HarfBuzz synthesizes a mark class from Unicode Mn only when the font has
    // no GDEF GlyphClassDef. Default-ignorables stay base-like during that
    // synthesis but remain transparent unless GSUB consumed them.
    if (!has_gdef_glyph_classes and
        unicode.isNonspacingMarkCodepoint(source_codepoint) and
        !unicode.isDefaultIgnorableForShaping(source_codepoint))
    {
        return true;
    }
    return unicode.isDefaultIgnorableForShaping(source_codepoint) and
        !was_substituted;
}

pub fn markAdvanceZeroing(
    use_shape: bool,
    glyph_class: GlyphClass,
    has_gdef_glyph_classes: bool,
    source_codepoint: u21,
    synthetic_base: bool,
    mark_attachment: bool,
    has_gpos_positioning: bool,
    options: pipeline_types.LookupOptions,
) MarkAdvanceZeroing {
    if (synthetic_base) return .{};

    const gdef_mark = glyph_class == .mark and
        (!unicode.isSpacingMarkCodepoint(source_codepoint) or use_shape) and
        !indic.shouldShape(options.script_tag);
    // A present ClassDef is authoritative even when this glyph is
    // unclassified; per-glyph Unicode fallback would override font intent.
    const synthesized_mark = !has_gdef_glyph_classes and
        unicode.isNonspacingMarkCodepoint(source_codepoint) and
        !unicode.isDefaultIgnorableForShaping(source_codepoint) and
        (use_shape or usesLateGdefMarkZeroing(options.script_tag));
    const attachment_mark_without_gdef =
        mark_attachment and !has_gdef_glyph_classes;
    const zero_advance =
        gdef_mark or synthesized_mark or attachment_mark_without_gdef;
    if (!zero_advance) return .{};

    const forward_direction =
        options.writing_mode.isVertical() or options.shapingDirection() == .ltr;
    return .{
        .zero_advance = true,
        // USE zeroes early, but shifts the provisional origin only when no
        // later GPOS pass can replace that placement.
        .adjust_offsets = use_shape and !has_gpos_positioning and forward_direction,
    };
}

pub fn glyphUsesSidewaysAdvance(
    _: u21,
    orientation: pipeline_types.TextOrientation,
) bool {
    return switch (orientation) {
        .sideways => true,
        .upright => false,
        // Mixed remains on vertical metrics until the browser/CSS reference
        // gate is independent of Pango's rotated-line geometry.
        .mixed => false,
    };
}

pub fn variationSelectorFallbackShouldRender(
    glyph_index: usize,
    source_index: usize,
    ligature_components: *const ligature_provenance.Store,
) bool {
    if (glyph_index == 0 or
        glyph_index - 1 >= ligature_components.infos.items.len)
    {
        return false;
    }
    const sources = ligature_components.componentSources(
        ligature_components.infos.items[glyph_index - 1],
    ) orelse return false;
    if (sources.len <= 1) return false;
    return source_index > sources[0] and
        source_index < sources[sources.len - 1];
}

pub fn runMayHaveMarkAttachments(
    glyphs: []const GlyphId,
    codepoints: []const u21,
    glyph_source_indices: []const usize,
    metadata: @import("../../../font.zig").GdefLookupMetadata,
) bool {
    const classes = metadata.glyph_classes orelse return true;
    for (glyphs, 0..) |glyph, index| {
        if (glyph < classes.len and
            classes[glyph] == @intFromEnum(GlyphClass.mark))
        {
            return true;
        }
        const source_index = if (index < glyph_source_indices.len)
            @min(glyph_source_indices[index], codepoints.len -| 1)
        else
            @min(index, codepoints.len -| 1);
        if (source_index < codepoints.len and
            unicode.isUnicodeMarkCodepoint(codepoints[source_index]))
        {
            return true;
        }
    }
    return false;
}

pub fn horizontalMetrics(
    font: *const Font,
    metrics_cache: ?*cache.GlyphMetricsCache,
    glyph_id: GlyphId,
    normalized_variation_coords: []const f32,
) !cache.GlyphMetrics {
    if (metrics_cache) |value| {
        return try value.horizontalMetricsAtCoords(
            font,
            glyph_id,
            normalized_variation_coords,
        );
    }
    const raw = if (normalized_variation_coords.len == 0)
        try font.horizontalMetrics(glyph_id)
    else
        try font.horizontalMetricsAtCoords(
            glyph_id,
            normalized_variation_coords,
        );
    return .{
        .advance_width = raw.advance_width,
        .left_side_bearing = raw.left_side_bearing,
    };
}

pub fn verticalMetrics(
    font: *const Font,
    metrics_cache: ?*cache.GlyphMetricsCache,
    glyph_id: GlyphId,
    normalized_variation_coords: []const f32,
) !?cache.VerticalGlyphMetrics {
    if (metrics_cache) |value| {
        return value.verticalMetricsAtCoords(
            font,
            glyph_id,
            normalized_variation_coords,
        ) catch |err| switch (err) {
            // Deployed CJK fonts sometimes advertise unusable vhea/vmtx line
            // metrics. Preserve the vertical contract with one-em fallback.
            error.InvalidMetrics => null,
            else => return err,
        };
    }
    const raw = (if (normalized_variation_coords.len == 0)
        font.verticalMetrics(glyph_id)
    else
        font.verticalMetricsAtCoords(
            glyph_id,
            normalized_variation_coords,
        )) catch |err| switch (err) {
        error.InvalidMetrics => null,
        else => return err,
    };
    return if (raw) |value| .{
        .advance_height = value.advance_height,
        .top_side_bearing = value.top_side_bearing,
    } else null;
}

fn usesLateGdefMarkZeroing(
    script_tag: unicode.OpenTypeScriptTag,
) bool {
    return switch (script_tag) {
        .arab, .hebr, .thai, .lao, .dflt => true,
        else => false,
    };
}

test "kerx machine skips GDEF marks and untouched Unicode controls" {
    const std = @import("std");
    try std.testing.expect(kerxMachineSkipsGlyph(.mark, true, 'A', false));
    try std.testing.expect(
        kerxMachineSkipsGlyph(.unclassified, false, 0x0301, false),
    );
    try std.testing.expect(
        !kerxMachineSkipsGlyph(.unclassified, true, 0x0301, false),
    );
    try std.testing.expect(
        kerxMachineSkipsGlyph(.unclassified, false, 0x200d, false),
    );
    try std.testing.expect(
        !kerxMachineSkipsGlyph(.unclassified, false, 0x200d, true),
    );
    try std.testing.expect(
        !kerxMachineSkipsGlyph(.base, true, 'A', false),
    );
}

test "USE mark zeroing synthesizes only marks without GDEF classes" {
    const std = @import("std");
    const options = pipeline_types.LookupOptions{ .script_tag = .brah };

    const nonspacing = markAdvanceZeroing(
        true,
        .unclassified,
        false,
        0x11038,
        false,
        false,
        false,
        options,
    );
    try std.testing.expect(nonspacing.zero_advance);
    try std.testing.expect(nonspacing.adjust_offsets);

    const spacing = markAdvanceZeroing(
        true,
        .unclassified,
        false,
        0x11000,
        false,
        false,
        false,
        options,
    );
    try std.testing.expectEqual(MarkAdvanceZeroing{}, spacing);

    const explicit_unclassified = markAdvanceZeroing(
        true,
        .unclassified,
        true,
        0x11038,
        false,
        false,
        false,
        options,
    );
    try std.testing.expectEqual(
        MarkAdvanceZeroing{},
        explicit_unclassified,
    );

    const dotted_circle = markAdvanceZeroing(
        true,
        .unclassified,
        false,
        0x11038,
        true,
        false,
        false,
        options,
    );
    try std.testing.expectEqual(MarkAdvanceZeroing{}, dotted_circle);
}

test "mark zeroing respects Indic and USE timing policies" {
    const std = @import("std");
    const malayalam = markAdvanceZeroing(
        false,
        .mark,
        true,
        0x0d41,
        false,
        false,
        false,
        .{ .script_tag = .mlm2 },
    );
    try std.testing.expectEqual(MarkAdvanceZeroing{}, malayalam);

    const tai_tham = markAdvanceZeroing(
        true,
        .mark,
        true,
        0x1a6e,
        false,
        false,
        false,
        .{ .script_tag = .lana },
    );
    try std.testing.expect(tai_tham.zero_advance);
    try std.testing.expect(tai_tham.adjust_offsets);

    const with_gpos = markAdvanceZeroing(
        true,
        .unclassified,
        false,
        0x11038,
        false,
        false,
        true,
        .{ .script_tag = .brah },
    );
    try std.testing.expect(with_gpos.zero_advance);
    try std.testing.expect(!with_gpos.adjust_offsets);

    // A forced RTL request normalizes to Brahmi's native LTR buffer.
    const native_ltr = markAdvanceZeroing(
        true,
        .unclassified,
        false,
        0x11038,
        false,
        false,
        false,
        .{
            .script_tag = .brah,
            .direction = .rtl,
            .native_direction_shaping = true,
        },
    );
    try std.testing.expect(native_ltr.adjust_offsets);
}
