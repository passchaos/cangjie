//! Script, class, and orientation policies used by final positioning.

const Font = @import("../../../font.zig").Font;
const GlyphClass = @import("../../../font.zig").GlyphClass;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const indic = @import("../../../indic.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const glyph_position = @import("../../../layout/glyph_position.zig");
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
    has_fallback_positioning: bool,
    options: pipeline_types.LookupOptions,
) MarkAdvanceZeroing {
    if (synthetic_base) return .{};

    const gdef_mark = glyph_class == .mark and
        (!unicode.isSpacingMarkCodepoint(source_codepoint) or use_shape) and
        !indic.shouldShape(options.script_tag);
    // HarfBuzz's default shaper zeroes late for every GDEF mark, and when a
    // font has no GlyphClassDef it synthesizes that class from Unicode Mn.
    // Script shapers with an explicit NONE policy must remain exempt: Indic,
    // Khmer, Hangul, and Myanmar Zawgyi intentionally retain authored
    // advances. Thai and Lao use the late-zero policy despite disabling
    // fallback mark positioning.
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
        // With no positioning engine, HarfBuzz shifts the provisional mark
        // origin in forward runs before either fallback mark geometry or final
        // output consumes it. GPOS owns the origin when it is available.
        .adjust_offsets = !has_gpos_positioning and
            !has_fallback_positioning and
            forward_direction,
    };
}

pub fn glyphOrientation(
    codepoint: u21,
    writing_mode: pipeline_types.WritingMode,
    orientation: pipeline_types.TextOrientation,
) glyph_position.Orientation {
    if (!writing_mode.isVertical()) return .horizontal;
    return switch (orientation) {
        .sideways => .sideways,
        .upright => .upright,
        // CSS Writing Modes keeps U, Tu, and Tr upright in mixed text. Tr's
        // rotated fallback belongs to lower-level UAX #50 renderers; CSS
        // requests upright geometry after `vert`/`vrt2` had a chance to
        // provide the typographic vertical glyph.
        .mixed => switch (unicode.verticalOrientationForCodepoint(codepoint)) {
            .rotated => .sideways,
            .upright, .transformed_upright, .transformed_rotated => .upright,
        },
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
    all_ascii: bool,
) bool {
    const classes = metadata.glyph_classes orelse return true;
    for (glyphs, 0..) |glyph, index| {
        if (glyph < classes.len and
            classes[glyph] == @intFromEnum(GlyphClass.mark))
        {
            return true;
        }
        if (all_ascii) continue;
        const source_index = if (index < glyph_source_indices.len)
            @min(glyph_source_indices[index], codepoints.len -| 1)
        else
            @min(index, codepoints.len -| 1);
        if (source_index < codepoints.len and
            isUnicodeMarkForPositioning(codepoints[source_index]))
        {
            return true;
        }
    }
    return false;
}

/// Reject ordinary CJK scalars before entering the complete Unicode mark
/// classifier. The two retained subranges are the only Unicode marks in the
/// admitted CJK blocks; keep this exact allow-list in sync with the exhaustive
/// proof test below rather than broadening it for visually mark-like symbols.
fn isUnicodeMarkForPositioning(codepoint: u21) bool {
    if (codepoint >= 0x3400 and codepoint <= 0x9fff) return false;
    if (codepoint >= 0x3000 and codepoint <= 0x30ff) {
        return (codepoint >= 0x302a and codepoint <= 0x302d) or
            (codepoint >= 0x3099 and codepoint <= 0x309a);
    }
    return unicode.isUnicodeMarkCodepoint(codepoint);
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
    if (indic.shouldShape(script_tag)) return false;
    return switch (script_tag) {
        .hang, .khmr, .qaag => false,
        else => true,
    };
}

test "ASCII mark proof consults GDEF without Unicode classification" {
    var classes = [_]u16{0} ** 3;
    try @import("std").testing.expect(!runMayHaveMarkAttachments(
        &.{ 1, 2 },
        &.{ 'A', 'B' },
        &.{ 0, 1 },
        .{ .glyph_classes = &classes },
        true,
    ));
    classes[2] = @intFromEnum(GlyphClass.mark);
    try @import("std").testing.expect(runMayHaveMarkAttachments(
        &.{ 1, 2 },
        &.{ 'A', 'B' },
        &.{ 0, 1 },
        .{ .glyph_classes = &classes },
        true,
    ));
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
        false,
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
        false,
        .{
            .script_tag = .brah,
            .direction = .rtl,
            .native_direction_shaping = true,
        },
    );
    try std.testing.expect(native_ltr.adjust_offsets);
}

test "generic shaping zeroes synthesized Unicode nonspacing marks late" {
    const std = @import("std");
    const latin = markAdvanceZeroing(
        false,
        .unclassified,
        false,
        0x0301,
        false,
        false,
        false,
        true,
        .{ .script_tag = .latn },
    );
    try std.testing.expect(latin.zero_advance);
    try std.testing.expect(!latin.adjust_offsets);

    const hangul = markAdvanceZeroing(
        false,
        .unclassified,
        false,
        0x0301,
        false,
        false,
        false,
        false,
        .{ .script_tag = .hang },
    );
    try std.testing.expectEqual(MarkAdvanceZeroing{}, hangul);

    const thai = markAdvanceZeroing(
        false,
        .unclassified,
        false,
        0x0e34,
        false,
        false,
        false,
        false,
        .{ .script_tag = .thai },
    );
    try std.testing.expect(thai.zero_advance);

    const zawgyi = markAdvanceZeroing(
        false,
        .unclassified,
        false,
        0x1037,
        false,
        false,
        false,
        false,
        .{ .script_tag = .qaag },
    );
    try std.testing.expectEqual(MarkAdvanceZeroing{}, zawgyi);
}

test "CJK mark shortcut exactly preserves Unicode classification" {
    const std = @import("std");

    // Exhaust every cheaply rejected scalar against the independent Unicode
    // classifier. The explicit exceptions use exact Unicode Mn data below.
    for (0x3000..0x3100) |value| {
        const codepoint: u21 = @intCast(value);
        if ((codepoint >= 0x302a and codepoint <= 0x302d) or
            (codepoint >= 0x3099 and codepoint <= 0x309a))
        {
            continue;
        }
        try std.testing.expectEqual(
            unicode.isUnicodeMarkCodepoint(codepoint),
            isUnicodeMarkForPositioning(codepoint),
        );
    }
    for (0x3400..0xa000) |value| {
        const codepoint: u21 = @intCast(value);
        try std.testing.expectEqual(
            unicode.isUnicodeMarkCodepoint(codepoint),
            isUnicodeMarkForPositioning(codepoint),
        );
    }

    for ([_]u21{ 0x302a, 0x302b, 0x302c, 0x302d, 0x3099, 0x309a }) |mark| {
        try std.testing.expect(unicode.isNonspacingMarkCodepoint(mark));
        try std.testing.expect(isUnicodeMarkForPositioning(mark));
    }
    for ([_]u21{ 0x3029, 0x302e, 0x3098, 0x309b }) |ordinary| {
        try std.testing.expectEqual(
            unicode.isUnicodeMarkCodepoint(ordinary),
            isUnicodeMarkForPositioning(ordinary),
        );
    }
}

test "CJK mark shortcut keeps GDEF authoritative and missing GDEF conservative" {
    const std = @import("std");
    var classes = [_]u16{0} ** 3;

    // A font-authored GDEF mark wins even for an ordinary Han source scalar.
    classes[2] = @intFromEnum(GlyphClass.mark);
    try std.testing.expect(runMayHaveMarkAttachments(
        &.{ 1, 2 },
        &.{ 0x4e00, 0x4e8c },
        &.{ 0, 1 },
        .{ .glyph_classes = &classes },
        false,
    ));

    // Missing GlyphClassDef still cannot prove that a run has no attachments.
    try std.testing.expect(runMayHaveMarkAttachments(
        &.{1},
        &.{0x4e00},
        &.{0},
        .{},
        false,
    ));
}
