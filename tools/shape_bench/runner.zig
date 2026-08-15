const std = @import("std");
const cangjie = @import("cangjie");

const cluster_normalization = @import("cluster_normalization.zig");
const options_mod = @import("options.zig");

pub const BenchResult = struct {
    pub const LineSummary = struct {
        index: usize,
        text_bytes: usize,
        glyph_count: usize,
        checksum: u64,
        glyph_ids: []const u32 = &.{},
        clusters: []const u32 = &.{},
        x_advances: []const i32 = &.{},
        y_advances: []const i32 = &.{},
        x_offsets: []const i32 = &.{},
        y_offsets: []const i32 = &.{},
        glyph_flags: []const u32 = &.{},
        glyph_extents: []const i32 = &.{},
    };
    pub const Sample = struct {
        index: usize,
        elapsed_ns: i128,
        glyph_count: usize,
        checksum: u64,
    };

    elapsed_ns: i128,
    glyph_count: usize,
    checksum: u64,
    profile: cangjie.ShapeStageProfile,
    line_summaries: []LineSummary = &.{},
    samples: []Sample = &.{},
    glyph_index_cache_hits: usize = 0,
    glyph_index_cache_misses: usize = 0,
    glyph_metrics_cache_hits: usize = 0,
    glyph_metrics_cache_misses: usize = 0,
    gdef_cache_hits: usize = 0,
    gdef_cache_misses: usize = 0,
    gsub_proof_cache_hits: usize = 0,
    gsub_proof_cache_misses: usize = 0,
    gpos_proof_cache_hits: usize = 0,
    gpos_proof_cache_misses: usize = 0,
    lookup_selection_cache_hits: usize = 0,
    lookup_selection_cache_misses: usize = 0,
    shaped_cache_hits: usize = 0,
    shaped_cache_misses: usize = 0,
};

pub fn loadFontBytes(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options) ![]u8 {
    if (options.font_path) |path| {
        const container = try std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(256 * 1024 * 1024),
        );
        errdefer allocator.free(container);
        const format = cangjie.detectFontContainerFormat(container) catch {
            if (options.hide_gsub_table) try hideSfntTable(container, "GSUB");
            return container;
        };
        if (format != .dfont) {
            if (options.hide_gsub_table) try hideSfntTable(container, "GSUB");
            return container;
        }

        const decoded = try cangjie.decodeFontContainerAlloc(
            allocator,
            container,
            256 * 1024 * 1024,
        );
        allocator.free(container);
        if (options.hide_gsub_table) try hideSfntTable(decoded, "GSUB");
        return decoded;
    }

    return switch (options.builtin_font) {
        .minimal => try cangjie.testing.test_font.buildMinimalTtf(allocator),
        .minimal_gsub => try cangjie.testing.test_font.buildMinimalGsubTtf(allocator),
        .script_feature => try cangjie.testing.test_font.buildScriptFeatureGsubTtf(allocator),
        .kerx => try cangjie.testing.test_font.buildKerxTtf(allocator),
        .kerx_variation => try cangjie.testing.test_font.buildKerxVariationTtf(allocator),
        .kerx_format_1 => try cangjie.testing.test_font.buildKerxFormat1Ttf(allocator),
        .kerx_format_2 => try cangjie.testing.test_font.buildKerxFormat2Ttf(allocator),
        .kerx_format_4 => try cangjie.testing.test_font.buildKerxFormat4Ttf(allocator),
        .kerx_format_4_outline => try cangjie.testing.test_font.buildKerxFormat4OutlineTtf(allocator),
        .kerx_format_4_ankr => try cangjie.testing.test_font.buildKerxFormat4AnkrTtf(allocator),
        .kerx_format_6 => try cangjie.testing.test_font.buildKerxFormat6Ttf(allocator),
        .kerx_cross_format_0 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 0, false),
        .kerx_cross_format_2 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 2, false),
        .kerx_cross_format_6 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 6, false),
        .kerx_cross_vertical_format_0 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 0, true),
        .kerx_cross_vertical_format_2 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 2, true),
        .kerx_cross_vertical_format_6 => try cangjie.testing.test_font.buildKerxCrossStreamTtf(allocator, 6, true),
        .kerx_cross_format_1 => try cangjie.testing.test_font.buildKerxFormat1CrossStreamTtf(allocator, false, false),
        .kerx_cross_vertical_format_1 => try cangjie.testing.test_font.buildKerxFormat1CrossStreamTtf(allocator, true, false),
        .kerx_cross_format_1_reset => try cangjie.testing.test_font.buildKerxFormat1CrossStreamTtf(allocator, false, true),
        .mort => try cangjie.testing.test_font.buildMortTtf(allocator),
        .mort_rearrangement => try cangjie.testing.test_font.buildMortRearrangementTtf(allocator),
        .mort_contextual => try cangjie.testing.test_font.buildMortContextualTtf(allocator),
        .mort_ligature => try cangjie.testing.test_font.buildMortLigatureTtf(allocator),
        .mort_insertion => try cangjie.testing.test_font.buildMortInsertionTtf(allocator),
    };
}

fn hideSfntTable(data: []u8, tag: *const [4]u8) !void {
    if (data.len < 12) return error.BadSfnt;
    const table_count: usize = std.mem.readInt(u16, data[4..6], .big);
    if (table_count > (data.len - 12) / 16) return error.BadSfnt;
    var found: ?usize = null;
    for (0..table_count) |index| {
        const record = 12 + index * 16;
        if (std.mem.eql(u8, data[record .. record + 4], tag)) {
            found = index;
            break;
        }
    }
    const remove_index = found orelse return;
    const directory_end = 12 + table_count * 16;
    const removed_record = 12 + remove_index * 16;
    std.mem.copyForwards(
        u8,
        data[removed_record .. directory_end - 16],
        data[removed_record + 16 .. directory_end],
    );
    @memset(data[directory_end - 16 .. directory_end], 0);
    const new_count: u16 = @intCast(table_count - 1);
    std.mem.writeInt(u16, data[4..6], new_count, .big);
    writeSfntSearchParameters(data, new_count);
}

fn writeSfntSearchParameters(data: []u8, table_count: u16) void {
    var power: u16 = 1;
    var selector: u16 = 0;
    while (power * 2 <= table_count) {
        power *= 2;
        selector += 1;
    }
    const search_range = power * 16;
    std.mem.writeInt(u16, data[6..8], search_range, .big);
    std.mem.writeInt(u16, data[8..10], selector, .big);
    std.mem.writeInt(u16, data[10..12], table_count * 16 - search_range, .big);
}

pub fn parseFont(allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !cangjie.Font {
    return try cangjie.Font.parseFace(allocator, font_bytes, options.face_index);
}

pub fn resolvedVariationCoords(allocator: std.mem.Allocator, font: *const cangjie.Font, options: *const options_mod.Options) ![]f32 {
    if (options.designVariationCoords().len == 0) {
        return try allocator.dupe(f32, options.normalizedVariationCoords());
    }
    return try font.normalizedVariationCoordinates(allocator, options.designVariationCoords());
}

pub fn runCangjie(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.Font, options: options_mod.Options) !BenchResult {
    var layout_buffer = cangjie.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    var metrics_cache = cangjie.GlyphMetricsCache.init(allocator);
    defer metrics_cache.deinit();
    var glyph_index_cache = cangjie.GlyphIndexCache.init(allocator);
    defer glyph_index_cache.deinit();
    var gdef_cache = cangjie.GdefMetadataCache.init(allocator);
    defer gdef_cache.deinit();
    var gsub_proof_cache = cangjie.GsubTableProofCache.init(allocator);
    defer gsub_proof_cache.deinit();
    var gpos_proof_cache = cangjie.GposTableProofCache.init(allocator);
    defer gpos_proof_cache.deinit();
    var lookup_selection_cache = cangjie.LookupSelectionCache.init(allocator);
    defer lookup_selection_cache.deinit();
    var shaped_cache = cangjie.ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();
    if (options.use_caches) {
        layout_buffer.gdef_metadata_cache = &gdef_cache;
        layout_buffer.gsub_table_proof_cache = &gsub_proof_cache;
        layout_buffer.gpos_table_proof_cache = &gpos_proof_cache;
        layout_buffer.lookup_selection_cache = &lookup_selection_cache;
    }

    const cascade_fonts = [_]*const cangjie.Font{font};
    const cascade = cangjie.FontCascade.init(&cascade_fonts);
    const normalized_variation_coords = try resolvedVariationCoords(allocator, font, &options);
    defer allocator.free(normalized_variation_coords);

    const shape_options = cangjie.ShapeOptions{
        .direction = options.direction.textDirection(),
        .reorder_bidi = options.reorder_bidi,
        .native_direction_shaping = options.native_direction_shaping,
        .writing_mode = options.direction.writingMode(),
        .text_orientation = options.direction.textOrientation(),
        .script_tag = options.script_tag,
        .language_tag = options.language_tag,
        .script_position = options.script_position,
        .features = options.featureOverrides(),
        .normalized_variation_coords = normalized_variation_coords,
        .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
        .remove_default_ignorables = options.remove_default_ignorables,
        .context_before = options.text_before,
        .context_after = options.text_after,
        .beginning_of_text = options.beginning_of_text,
        .end_of_text = options.end_of_text,
        .cluster_level = options.cluster_level,
    };
    const inline_text_lines = [_][]const u8{options.text};
    const text_lines = if (options.text_lines.len != 0) options.text_lines else inline_text_lines[0..];
    var line_summaries = std.ArrayList(BenchResult.LineSummary).empty;
    errdefer line_summaries.deinit(allocator);

    var warmup_index: usize = 0;
    while (warmup_index < options.warmup) : (warmup_index += 1) {
        for (text_lines) |line| {
            _ = try shapeOnce(font, cascade, &metrics_cache, &glyph_index_cache, if (options.use_shaped_cache) &shaped_cache else null, &layout_buffer, line, options, shape_options);
        }
    }

    var profile = cangjie.ShapeStageProfile{};
    if (options.profile) {
        layout_buffer.shape_profile = &profile;
        layout_buffer.profile_fast_path = options.profile_fast_path;
        layout_buffer.profile_io = io;
    }
    defer if (options.profile) {
        layout_buffer.shape_profile = null;
        layout_buffer.profile_fast_path = false;
        layout_buffer.profile_io = null;
    };

    var checksum: u64 = 0;
    var glyph_count: usize = 0;
    var samples = std.ArrayList(BenchResult.Sample).empty;
    errdefer samples.deinit(allocator);
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        var sample_glyph_count: usize = 0;
        const sample_start = std.Io.Clock.now(.awake, io).nanoseconds;
        var i: usize = 0;
        while (i < options.iterations) : (i += 1) {
            for (text_lines, 0..) |line, line_index| {
                const glyphs = try shapeOnce(font, cascade, &metrics_cache, &glyph_index_cache, if (options.use_shaped_cache) &shaped_cache else null, &layout_buffer, line, options, shape_options);
                sample_glyph_count += glyphs.len;
                const line_checksum = glyphsChecksum(glyphs);
                sample_checksum = updateChecksumWithLine(sample_checksum, line_checksum);
                if (options.line_summary and sample_index == 0 and i == 0) {
                    try line_summaries.append(allocator, .{
                        .index = line_index,
                        .text_bytes = line.len,
                        .glyph_count = glyphs.len,
                        .checksum = line_checksum,
                        .glyph_ids = if (options.glyph_summary) try glyphIds(allocator, glyphs) else &.{},
                        .clusters = if (options.glyph_summary) try cluster_normalization.glyphClusters(allocator, line, glyphs, options.normalize_clusters_to_graphemes) else &.{},
                        .x_advances = if (options.glyph_summary) try glyphXAdvances(allocator, font, options.size, options, glyphs) else &.{},
                        .y_advances = if (options.glyph_summary) try glyphYAdvances(allocator, font, options.size, options, glyphs) else &.{},
                        .x_offsets = if (options.glyph_summary) try glyphXOffsets(allocator, font, options.size, options, normalized_variation_coords, glyphs) else &.{},
                        .y_offsets = if (options.glyph_summary) try glyphYOffsets(allocator, font, options.size, options, normalized_variation_coords, glyphs) else &.{},
                        .glyph_flags = if (options.show_flags) try glyphFlags(allocator, line, options, glyphs) else &.{},
                        .glyph_extents = if (options.show_extents) try glyphExtents(allocator, font, options.size, normalized_variation_coords, glyphs) else &.{},
                    });
                }
            }
        }
        const sample_elapsed = std.Io.Clock.now(.awake, io).nanoseconds - sample_start;
        try samples.append(allocator, .{
            .index = sample_index,
            .elapsed_ns = sample_elapsed,
            .glyph_count = sample_glyph_count,
            .checksum = sample_checksum,
        });
        glyph_count += sample_glyph_count;
        checksum = updateChecksumWithLine(checksum, sample_checksum);
    }
    var elapsed: i128 = 0;
    for (samples.items) |sample| elapsed += sample.elapsed_ns;

    return .{
        .elapsed_ns = elapsed,
        .glyph_count = glyph_count,
        .checksum = checksum,
        .profile = profile,
        .line_summaries = try line_summaries.toOwnedSlice(allocator),
        .samples = try samples.toOwnedSlice(allocator),
        .glyph_index_cache_hits = glyph_index_cache.hits,
        .glyph_index_cache_misses = glyph_index_cache.misses,
        .glyph_metrics_cache_hits = metrics_cache.hits,
        .glyph_metrics_cache_misses = metrics_cache.misses,
        .gdef_cache_hits = gdef_cache.hits,
        .gdef_cache_misses = gdef_cache.misses,
        .gsub_proof_cache_hits = gsub_proof_cache.hits,
        .gsub_proof_cache_misses = gsub_proof_cache.misses,
        .gpos_proof_cache_hits = gpos_proof_cache.hits,
        .gpos_proof_cache_misses = gpos_proof_cache.misses,
        .lookup_selection_cache_hits = lookup_selection_cache.hits,
        .lookup_selection_cache_misses = lookup_selection_cache.misses,
        .shaped_cache_hits = shaped_cache.hits,
        .shaped_cache_misses = shaped_cache.misses,
    };
}

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const cangjie.GlyphPosition) ![]const u32 {
    const ids = try allocator.alloc(u32, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.outputGlyphId();
    return ids;
}

fn glyphXAdvances(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    _ = options;
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = fontUnitPosition(font, font_size, glyph.x_advance);
    return values;
}

fn glyphYAdvances(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        const runtime_value = fontUnitPosition(font, font_size, glyph.y_advance);
        value.* = if (usesHarfBuzzVerticalSummary(options.direction) and glyph.vertical and runtime_value > 0)
            try harfBuzzVerticalAdvance(font, glyph)
        else
            runtime_value;
    }
    return values;
}

fn glyphXOffsets(
    allocator: std.mem.Allocator,
    font: *const cangjie.Font,
    font_size: f32,
    options: options_mod.Options,
    normalized_variation_coords: []const f32,
    glyphs: []const cangjie.GlyphPosition,
) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    const preserve_vertical_position_delta = verticalKerningFeatureRequested(options);
    for (glyphs, values) |glyph, *value| {
        if (usesHarfBuzzVerticalSummary(options.direction) and glyph.vertical) {
            const origin = try syntheticVerticalOriginX(font, glyph.glyph_id, options, normalized_variation_coords);
            if (preserve_vertical_position_delta) {
                const default_runtime_origin = @as(f32, @floatFromInt((try font.horizontalMetricsAtCoords(glyph.glyph_id, normalized_variation_coords)).advance_width)) *
                    0.5 * font_size / @as(f32, @floatFromInt(font.units_per_em));
                const runtime_delta = fontUnitPosition(
                    font,
                    font_size,
                    glyph.x_offset - default_runtime_origin,
                );
                // Explicit `vkrn` may change x after the default origin is
                // installed. Preserve that delta for vertical kerning probes
                // instead of replacing the complete result with the
                // synthesized origin.
                value.* = -origin + runtime_delta;
            } else {
                // Existing synthetic-bold/slant and fallback-space fixtures
                // intentionally summarize only HarfBuzz's vertical origin;
                // their transformed public x coordinate is not a GPOS delta.
                value.* = -origin;
            }
        } else {
            value.* = fontUnitPosition(font, font_size, glyph.x_offset);
        }
    }
    return values;
}

fn verticalKerningFeatureRequested(options: options_mod.Options) bool {
    const vkrn_tag = (@as(u32, 'v') << 24) |
        (@as(u32, 'k') << 16) |
        (@as(u32, 'r') << 8) |
        @as(u32, 'n');
    for (options.featureOverrides()) |feature| {
        if (feature.tag == vkrn_tag) return feature.enabled;
    }
    return false;
}

fn glyphYOffsets(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, options: options_mod.Options, normalized_variation_coords: []const f32, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = if (usesHarfBuzzVerticalSummary(options.direction) and glyph.vertical) vertical: {
            if (options.font_slant != 0 or options.font_bold_x != 0 or options.font_bold_y != 0) {
                break :vertical -try syntheticVerticalOriginY(font, glyph.glyph_id, options, normalized_variation_coords);
            }
            break :vertical -try font.shapingVerticalOriginYAtCoords(glyph.glyph_id, normalized_variation_coords);
        } else fontUnitPosition(font, font_size, glyph.y_offset);
    }
    return values;
}

fn usesHarfBuzzVerticalSummary(direction: options_mod.Direction) bool {
    return direction == .ttb or direction == .btt;
}

fn glyphFlags(allocator: std.mem.Allocator, text: []const u8, options: options_mod.Options, glyphs: []const cangjie.GlyphPosition) ![]const u32 {
    const values = try allocator.alloc(u32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = @intFromBool(glyph.isUnsafeToBreakBefore());
    }
    if (!options.unsafe_to_concat) return values;
    if (options.direction != .rtl or !textContainsCodepoint(text, 0x200c)) return values;
    for (values) |*value| value.* |= 0x0000_0002;
    return values;
}

fn glyphExtents(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, normalized_variation_coords: []const f32, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len * 4);
    for (glyphs, 0..) |glyph, index| {
        const base = index * 4;
        const bounds = font.glyphBoundsAtCoords(@intCast(glyph.glyph_id), normalized_variation_coords) catch {
            if (try bitmapGlyphExtents(font, glyph.glyph_id, font_size, values[base..][0..4])) continue;
            values[base + 0] = 0;
            values[base + 1] = 0;
            values[base + 2] = 0;
            values[base + 3] = 0;
            continue;
        };
        if (bounds.x_min == bounds.x_max and bounds.y_min == bounds.y_max) {
            if (try bitmapGlyphExtents(font, glyph.glyph_id, font_size, values[base..][0..4])) continue;
        }
        values[base + 0] = bounds.x_min;
        values[base + 1] = bounds.y_max;
        values[base + 2] = @as(i32, bounds.x_max) - @as(i32, bounds.x_min);
        values[base + 3] = @as(i32, bounds.y_min) - @as(i32, bounds.y_max);
    }
    return values;
}

fn bitmapGlyphExtents(font: *const cangjie.Font, glyph_id: u32, font_size: f32, out: []i32) !bool {
    if (out.len < 4) return false;
    const bitmap_info = (try font.bitmapGlyphInfo(@intCast(glyph_id), font_size)) orelse return false;
    const ppem = @max(bitmap_info.ppem, 1);
    const scale = @as(f32, @floatFromInt(font.units_per_em)) / @as(f32, @floatFromInt(ppem));
    out[0] = scaleRound(i32, @as(f32, @floatFromInt(bitmap_info.origin_offset_x)) * scale);
    out[1] = switch (bitmap_info.source) {
        .sbix => scaleRound(i32, (@as(f32, @floatFromInt(bitmap_info.origin_offset_y)) + @as(f32, @floatFromInt(bitmap_info.height))) * scale),
        .cblc_cbdt, .eblc_ebdt => scaleRound(i32, @as(f32, @floatFromInt(bitmap_info.origin_offset_y)) * scale),
    };
    out[2] = scaleRound(i32, @as(f32, @floatFromInt(bitmap_info.width)) * scale);
    out[3] = -scaleRound(i32, @as(f32, @floatFromInt(bitmap_info.height)) * scale);
    return true;
}

fn scaleRound(comptime T: type, value: f32) T {
    return @intFromFloat(@round(value));
}

fn textContainsCodepoint(text: []const u8, target: u21) bool {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (codepoint == target) return true;
    }
    return false;
}

fn syntheticVerticalOriginX(font: *const cangjie.Font, glyph_id: cangjie.GlyphId, options: options_mod.Options, normalized_variation_coords: []const f32) !i32 {
    var advance = @as(i32, (try font.horizontalMetricsAtCoords(glyph_id, normalized_variation_coords)).advance_width);
    if (options.font_bold_x != 0 and advance != 0) advance += syntheticStrength(font, options.font_bold_x);
    return @divTrunc(advance, 2) + syntheticStrength(font, options.font_bold_x);
}

fn syntheticVerticalOriginY(font: *const cangjie.Font, glyph_id: cangjie.GlyphId, options: options_mod.Options, normalized_coords: []const f32) !i32 {
    var bounds = try font.glyphBoundsAtCoords(glyph_id, normalized_coords);
    if (options.font_slant != 0) {
        const x1 = @as(f32, @floatFromInt(bounds.x_min));
        const x2 = @as(f32, @floatFromInt(bounds.x_max));
        const y1 = @as(f32, @floatFromInt(bounds.y_max));
        const y2 = @as(f32, @floatFromInt(bounds.y_min));
        const slant_xy = options.font_slant;
        const slanted_x1 = x1 + @floor(@min(y1 * slant_xy, y2 * slant_xy));
        const slanted_x2 = x2 + @ceil(@max(y1 * slant_xy, y2 * slant_xy));
        bounds.x_min = @intFromFloat(slanted_x1);
        bounds.x_max = @intFromFloat(slanted_x2);
    }
    const y_strength = syntheticStrength(font, options.font_bold_y);
    bounds.y_max += @intCast(y_strength);

    const font_advance = @as(i32, font.ascender) + y_strength - @as(i32, font.descender);
    const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
    return @as(i32, bounds.y_max) + @divTrunc(font_advance - glyph_height, 2) + y_strength;
}

fn syntheticStrength(font: *const cangjie.Font, value: f32) i32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(font.units_per_em)) * value));
}

fn harfBuzzVerticalAdvance(font: *const cangjie.Font, glyph: cangjie.GlyphPosition) !i32 {
    if (try font.verticalMetrics(glyph.glyph_id)) |metrics| return -@as(i32, @intCast(metrics.advance_height));
    return -defaultVerticalAdvance(font);
}

fn defaultVerticalAdvance(font: *const cangjie.Font) i32 {
    return @as(i32, font.ascender) - @as(i32, font.descender);
}

fn fontUnitPosition(font: *const cangjie.Font, font_size: f32, value: f32) i32 {
    const font_units = value * @as(f32, @floatFromInt(font.units_per_em)) / font_size;
    return @intFromFloat(@round(font_units));
}

fn shapeOnce(
    font: *const cangjie.Font,
    cascade: cangjie.FontCascade,
    metrics_cache: *cangjie.GlyphMetricsCache,
    glyph_index_cache: *cangjie.GlyphIndexCache,
    shaped_cache: ?*cangjie.ShapedRunCache,
    layout_buffer: *cangjie.LayoutBuffer,
    text: []const u8,
    options: options_mod.Options,
    shape_options: cangjie.ShapeOptions,
) ![]const cangjie.GlyphPosition {
    if (options.feature_range_count != 0) return shapeOnceWithGsubFeatureRanges(
        font,
        metrics_cache,
        glyph_index_cache,
        layout_buffer,
        text,
        options,
        shape_options,
    );
    if (options.use_caches) {
        if (shaped_cache) |cache| {
            const shaped = try cangjie.TextShaper.shapeUtf8CascadeWithCaches(cascade, null, metrics_cache, glyph_index_cache, cache, layout_buffer, text, options.size, shape_options);
            return shaped.glyphs;
        }
        const run = try cangjie.TextShaper.shapeUtf8WithCaches(font, metrics_cache, glyph_index_cache, layout_buffer, text, options.size, shape_options);
        return run.glyphs;
    }
    const run = try cangjie.TextShaper.shapeUtf8WithOptions(font, layout_buffer, text, options.size, shape_options);
    return run.glyphs;
}

// Keep CLI-only rare-path setup out of the benchmark's common per-line helper;
// otherwise its code-size change would contaminate the zero-range A/B intended
// to measure the shaping library rather than this dispatch wrapper.
noinline fn shapeOnceWithGsubFeatureRanges(
    font: *const cangjie.Font,
    metrics_cache: *cangjie.GlyphMetricsCache,
    glyph_index_cache: *cangjie.GlyphIndexCache,
    layout_buffer: *cangjie.LayoutBuffer,
    text: []const u8,
    options: options_mod.Options,
    shape_options: cangjie.ShapeOptions,
) ![]const cangjie.GlyphPosition {
    const ranges = options.featureRanges();
    const run = if (options.use_caches)
        try cangjie.TextShaper.shapeUtf8WithCachesAndGsubFeatureRanges(
            font,
            metrics_cache,
            glyph_index_cache,
            layout_buffer,
            text,
            options.size,
            ranges,
            shape_options,
        )
    else
        try cangjie.TextShaper.shapeUtf8WithGsubFeatureRanges(
            font,
            layout_buffer,
            text,
            options.size,
            ranges,
            shape_options,
        );
    return run.glyphs;
}

fn glyphsChecksum(glyphs: []const cangjie.GlyphPosition) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (glyphs) |glyph| {
        const glyph_id = glyph.outputGlyphId();
        hasher.update(std.mem.asBytes(&glyph_id));
        hasher.update(std.mem.asBytes(&glyph.cluster));
        hasher.update(std.mem.asBytes(&glyph.x_advance));
        hasher.update(std.mem.asBytes(&glyph.y_advance));
        hasher.update(std.mem.asBytes(&glyph.x_offset));
        hasher.update(std.mem.asBytes(&glyph.y_offset));
    }
    return hasher.final();
}

fn updateChecksumWithLine(seed: u64, line_checksum: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&line_checksum));
    return hasher.final();
}
