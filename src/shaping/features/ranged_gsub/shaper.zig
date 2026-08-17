//! Public UTF-8 byte-ranged GSUB shaping API.
//!
//! The implementation is deliberately detached from `layout.shapeSegmentInto`:
//! ranged features are rare, while ordinary shaping is a performance-sensitive
//! path shared by paragraph layout and fallback itemization.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const Font = @import("../../../font.zig").Font;
const GlyphMetricsCache = @import("../../context/cache/root.zig").GlyphMetricsCache;
const GlyphIndexCache = @import("../../context/cache/root.zig").GlyphIndexCache;
const context_output = @import("../../context/output.zig");
const executor = @import("executor.zig");
const gsub = @import("../../../gsub.zig");
const run_types = @import("../../../layout/types/runs.zig");
const shaping_plan = @import("../../plan/root.zig");
const overrides = @import("overrides.zig");
const positioning = @import("positioning.zig");
const ranges_mod = @import("ranges.zig");
const shaping_sections = @import("../../../shaping_sections.zig");
const source_buffer = @import("source_buffer.zig");
const unicode = @import("../../../unicode.zig");

pub const Shaper = struct {
    /// Shape one font with UTF-8 byte-scoped OpenType GSUB feature values.
    ///
    /// Offsets use the public UTF-8 cluster coordinate system. Later
    /// overlapping entries for the same tag take precedence, matching
    /// HarfBuzz's user-feature order.
    pub fn shapeUtf8WithOptions(
        font: *const Font,
        buffer: *context_output.Buffer,
        text: []const u8,
        font_size: f32,
        ranges: []const ranges_mod.Range,
        options: shaping_plan.ShapeOptions,
    ) !run_types.GlyphRun {
        return shapeUtf8WithCaches(
            font,
            null,
            null,
            buffer,
            text,
            font_size,
            ranges,
            options,
        );
    }

    pub noinline fn shapeUtf8WithCaches(
        font: *const Font,
        metrics_cache: ?*GlyphMetricsCache,
        glyph_index_cache: ?*GlyphIndexCache,
        buffer: *context_output.Buffer,
        text: []const u8,
        font_size: f32,
        ranges: []const ranges_mod.Range,
        options: shaping_plan.ShapeOptions,
    ) linksection(shaping_sections.isolated_hotpaths) !run_types.GlyphRun {
        try validateInput(text, font_size, ranges, options);
        return shapeValidated(
            font,
            metrics_cache,
            glyph_index_cache,
            buffer,
            text,
            font_size,
            ranges,
            options,
        );
    }
};

fn shapeValidated(
    font: *const Font,
    metrics_cache: ?*GlyphMetricsCache,
    glyph_index_cache: ?*GlyphIndexCache,
    buffer: *context_output.Buffer,
    text: []const u8,
    font_size: f32,
    ranges: []const ranges_mod.Range,
    options: shaping_plan.ShapeOptions,
) !run_types.GlyphRun {
    const inferred_script = unicode.inferOpenTypeScript(text);
    const script_selection = try font_shaping.selectGsubScriptForShaping(
        font,
        inferred_script,
        options.script_tag,
    );
    const script = script_selection.tag orelse
        options.script_tag orelse
        unicode.openTypeScriptTag(inferred_script);
    if (usesStagedShaper(script)) return error.UnsupportedFeatureRanges;

    buffer.clear();
    var sources = source_buffer.Buffer{};
    defer sources.deinit(buffer.allocator);
    try sources.build(font, glyph_index_cache, buffer.allocator, text);
    try overrides.buildOrdinary(
        buffer.allocator,
        &sources.ordinary_overrides,
        options.features,
        ranges,
    );

    var gdef_metadata = try font_shaping.gdefLookupMetadataForShaping(font, buffer.allocator);
    defer gdef_metadata.deinit(buffer.allocator);
    try font_shaping.proveGsubTableForShaping(
        font,
    );

    var run_limits = try gsub.runtime.Limits.init(sources.glyph_ids.items.len);
    var random_state: u32 = 1;
    var gsub_options = gsub.runtime.Options{
        .script_tag = script,
        .language_tag = options.language_tag orelse
            unicode.inferOpenTypeLanguageTag(text),
        .features = sources.ordinary_overrides.items,
        .normalized_variation_coords = options.normalized_variation_coords,
        .apply_all_if_unselected = false,
        .glyph_source_indices = &sources.glyph_sources,
        .glyph_cluster_indices = &sources.glyph_clusters,
        .cluster_level = options.cluster_level orelse .monotone_characters,
        .glyph_substituted = &sources.glyph_substituted,
        .ligature_components = &sources.ligature_components,
        .source_codepoints = sources.codepoints.items,
        .random_state = &random_state,
    };
    run_limits.applyTo(&gsub_options);

    try font_shaping.applyGsubWithOptionsUsingGdefAfterProof(
        font,
        &sources.glyph_ids,
        buffer.allocator,
        gsub_options,
        gdef_metadata,
    );
    try executor.apply(
        font,
        buffer.allocator,
        ranges,
        options.features,
        &sources,
        gsub_options,
        gdef_metadata,
    );
    try font_shaping.validateShapedGlyphRunForShaping(font, sources.glyph_ids.items);
    try positioning.collect(
        font,
        metrics_cache,
        buffer,
        font_size,
        &sources,
        gdef_metadata,
        script,
        gsub_options.language_tag,
        options,
    );
    return try buffer.run(
        font,
        font_size,
        options.normalized_variation_coords,
    );
}

fn validateInput(
    text: []const u8,
    font_size: f32,
    ranges: []const ranges_mod.Range,
    options: shaping_plan.ShapeOptions,
) !void {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (!std.math.isFinite(font_size) or font_size <= 0) {
        return error.InvalidFontSize;
    }
    if (ranges.len == 0) return error.InvalidFeatureRange;
    if (options.writing_mode.isVertical() or
        options.direction != .ltr or
        options.script_position != .normal or
        options.not_found_variation_selector_glyph != null or
        options.context_before.len != 0 or
        options.context_after.len != 0)
    {
        return error.UnsupportedFeatureRanges;
    }
    for (ranges) |range| {
        if (!validOpenTypeTag(range.tag)) return error.InvalidFeatureTag;
        if (!ranges_mod.isSupportedGenericTag(range.tag)) {
            return error.UnsupportedFeatureRanges;
        }
        if (range.byte_start >= range.byte_end or
            range.byte_end > text.len or
            !utf8Boundary(text, range.byte_start) or
            !utf8Boundary(text, range.byte_end))
        {
            return error.InvalidFeatureRange;
        }
    }
}

fn validOpenTypeTag(tag: u32) bool {
    inline for (0..4) |shift_index| {
        const shift: u5 = @intCast((3 - shift_index) * 8);
        const byte: u8 = @intCast((tag >> shift) & 0xff);
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}

fn utf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset > text.len) return false;
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0xc0) != 0x80;
}

fn usesStagedShaper(script: unicode.OpenTypeScriptTag) bool {
    return switch (script) {
        .arab,
        .syrc,
        .mong,
        .phag,
        .nko,
        .mym2,
        .mymr,
        .khmr,
        .deva,
        .dev2,
        .beng,
        .bng2,
        .guru,
        .gur2,
        .gujr,
        .gjr2,
        .orya,
        .ory2,
        .taml,
        .tml2,
        .telu,
        .tel2,
        .knda,
        .knd2,
        .mlym,
        .mlm2,
        => true,
        else => false,
    };
}
