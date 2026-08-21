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
    profile: cangjie.debug.ShapeProfile,
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
        const format = cangjie.font.container.detectFormat(container) catch {
            if (options.hide_gsub_table) try hideSfntTable(container, "GSUB");
            return container;
        };
        if (format != .dfont) {
            if (options.hide_gsub_table) try hideSfntTable(container, "GSUB");
            return container;
        }

        const decoded = try cangjie.font.container.decodeAlloc(
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

pub fn parseFont(allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !cangjie.font.Face {
    return try cangjie.font.Face.parseIndex(allocator, font_bytes, options.face_index);
}

pub fn resolvedVariationCoords(allocator: std.mem.Allocator, font: *const cangjie.font.Face, options: *const options_mod.Options) ![]f32 {
    if (options.designVariationCoords().len == 0) {
        return try allocator.dupe(f32, options.normalizedVariationCoords());
    }
    return try font.variations().normalize(allocator, options.designVariationCoords());
}

pub fn runCangjie(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.font.Face, options: options_mod.Options) !BenchResult {
    var engine = cangjie.shaping.Engine.init(allocator, .{
        .cache_font_data = options.use_caches,
        .cache_shaped_runs = options.use_shaped_cache,
    });
    defer engine.deinit();

    const cascade_fonts = [_]*const cangjie.font.Face{font};
    const cascade = cangjie.font.Cascade.init(&cascade_fonts);
    const normalized_variation_coords = try resolvedVariationCoords(allocator, font, &options);
    defer allocator.free(normalized_variation_coords);

    const shape_options = cangjie.shaping.Options{
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
            _ = try shapeOnce(
                &engine,
                font,
                cascade,
                line,
                options,
                shape_options,
            );
        }
    }

    var profile = cangjie.debug.ShapeProfile{};
    if (options.profile) {
        engine.enableProfiling(
            &profile,
            io,
            options.profile_fast_path,
        );
    }
    defer if (options.profile) engine.disableProfiling();

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
                const glyphs = try shapeOnce(
                    &engine,
                    font,
                    cascade,
                    line,
                    options,
                    shape_options,
                );
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
    const cache_stats = engine.stats();

    return .{
        .elapsed_ns = elapsed,
        .glyph_count = glyph_count,
        .checksum = checksum,
        .profile = profile,
        .line_summaries = try line_summaries.toOwnedSlice(allocator),
        .samples = try samples.toOwnedSlice(allocator),
        .glyph_index_cache_hits = cache_stats.glyph_indices.hits,
        .glyph_index_cache_misses = cache_stats.glyph_indices.misses,
        .glyph_metrics_cache_hits = cache_stats.glyph_metrics.hits,
        .glyph_metrics_cache_misses = cache_stats.glyph_metrics.misses,
        .gdef_cache_hits = cache_stats.gdef_metadata.hits,
        .gdef_cache_misses = cache_stats.gdef_metadata.misses,
        .gsub_proof_cache_hits = cache_stats.gsub_table_proofs.hits,
        .gsub_proof_cache_misses = cache_stats.gsub_table_proofs.misses,
        .gpos_proof_cache_hits = cache_stats.gpos_table_proofs.hits,
        .gpos_proof_cache_misses = cache_stats.gpos_table_proofs.misses,
        .lookup_selection_cache_hits = cache_stats.lookup_selection.hits,
        .lookup_selection_cache_misses = cache_stats.lookup_selection.misses,
        .shaped_cache_hits = cache_stats.shaped_runs.hits,
        .shaped_cache_misses = cache_stats.shaped_runs.misses,
    };
}

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const cangjie.shaping.Glyph) ![]const u32 {
    const ids = try allocator.alloc(u32, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.outputGlyphId();
    return ids;
}

fn glyphXAdvances(allocator: std.mem.Allocator, font: *const cangjie.font.Face, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.shaping.Glyph) ![]const i32 {
    _ = options;
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = fontUnitPosition(font, font_size, glyph.x_advance);
    return values;
}

fn glyphYAdvances(allocator: std.mem.Allocator, font: *const cangjie.font.Face, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.shaping.Glyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        const runtime_value = fontUnitPosition(font, font_size, glyph.y_advance);
        value.* = if (usesHarfBuzzVerticalSummary(options.direction) and
            glyph.isVertical())
            if (usesSyntheticVerticalSpaceAdvance(glyph.codepoint))
                -runtime_value
            else
                try harfBuzzVerticalAdvance(font, glyph)
        else
            runtime_value;
    }
    return values;
}

fn glyphXOffsets(
    allocator: std.mem.Allocator,
    font: *const cangjie.font.Face,
    font_size: f32,
    options: options_mod.Options,
    normalized_variation_coords: []const f32,
    glyphs: []const cangjie.shaping.Glyph,
) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        if (usesHarfBuzzVerticalSummary(options.direction) and
            glyph.isVertical() and
            options.font_bold_x != 0)
        {
            const default_origin =
                @divTrunc(
                    @as(i32, (try font.metrics().horizontalAt(
                        glyph.glyph_id,
                        normalized_variation_coords,
                    )).advance_width),
                    2,
                );
            const runtime_delta =
                fontUnitPosition(font, font_size, glyph.x_offset) +
                default_origin;
            value.* =
                -try syntheticVerticalOriginX(
                    font,
                    glyph.glyph_id,
                    options,
                    normalized_variation_coords,
                ) +
                runtime_delta;
        } else {
            value.* = fontUnitPosition(font, font_size, glyph.x_offset);
        }
    }
    return values;
}

fn glyphYOffsets(allocator: std.mem.Allocator, font: *const cangjie.font.Face, font_size: f32, options: options_mod.Options, normalized_variation_coords: []const f32, glyphs: []const cangjie.shaping.Glyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = if (usesHarfBuzzVerticalSummary(options.direction) and glyph.isVertical()) vertical: {
            if (options.font_slant != 0 or options.font_bold_x != 0 or options.font_bold_y != 0) {
                const default_origin = try font.metrics().shapingVerticalOrigin(
                    glyph.glyph_id,
                    normalized_variation_coords,
                );
                const runtime_delta =
                    fontUnitPosition(font, font_size, glyph.y_offset) +
                    default_origin;
                break :vertical -try syntheticVerticalOriginY(
                    font,
                    glyph.glyph_id,
                    options,
                    normalized_variation_coords,
                ) + runtime_delta;
            }
            break :vertical fontUnitPosition(
                font,
                font_size,
                glyph.y_offset,
            );
        } else fontUnitPosition(font, font_size, glyph.y_offset);
    }
    return values;
}

fn usesHarfBuzzVerticalSummary(direction: options_mod.Direction) bool {
    return direction == .ttb or direction == .btt;
}

fn glyphFlags(allocator: std.mem.Allocator, text: []const u8, options: options_mod.Options, glyphs: []const cangjie.shaping.Glyph) ![]const u32 {
    const values = try allocator.alloc(u32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = @intFromBool(glyph.isUnsafeToBreakBefore()) |
            (@as(u32, @intFromBool(glyph.isSafeToInsertTatweel())) << 2);
    }
    if (!options.unsafe_to_concat) return values;
    if (options.direction != .rtl or !textContainsCodepoint(text, 0x200c)) return values;
    for (values) |*value| value.* |= 0x0000_0002;
    return values;
}

fn glyphExtents(allocator: std.mem.Allocator, font: *const cangjie.font.Face, font_size: f32, normalized_variation_coords: []const f32, glyphs: []const cangjie.shaping.Glyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len * 4);
    for (glyphs, 0..) |glyph, index| {
        const base = index * 4;
        const extents = font.glyphs().extentsAt(@intCast(glyph.glyph_id), normalized_variation_coords) catch {
            if (try bitmapGlyphExtents(font, glyph.glyph_id, font_size, values[base..][0..4])) continue;
            values[base + 0] = 0;
            values[base + 1] = 0;
            values[base + 2] = 0;
            values[base + 3] = 0;
            continue;
        };
        if (extents.width == 0 and extents.height == 0) {
            if (try bitmapGlyphExtents(font, glyph.glyph_id, font_size, values[base..][0..4])) continue;
        }
        values[base + 0] = extents.x_bearing;
        values[base + 1] = extents.y_bearing;
        values[base + 2] = extents.width;
        values[base + 3] = extents.height;
    }
    return values;
}

fn bitmapGlyphExtents(font: *const cangjie.font.Face, glyph_id: u32, font_size: f32, out: []i32) !bool {
    if (out.len < 4) return false;
    const bitmap_info = (try font.color().bitmapInfo(@intCast(glyph_id), font_size)) orelse return false;
    const ppem = @max(bitmap_info.ppem, 1);
    const scale = @as(f32, @floatFromInt(font.properties().units_per_em)) / @as(f32, @floatFromInt(ppem));
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

fn syntheticVerticalOriginX(font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, normalized_variation_coords: []const f32) !i32 {
    var advance = @as(i32, (try font.metrics().horizontalAt(glyph_id, normalized_variation_coords)).advance_width);
    if (options.font_bold_x != 0 and advance != 0) advance += syntheticStrength(font, options.font_bold_x);
    return @divTrunc(advance, 2) + syntheticStrength(font, options.font_bold_x);
}

fn syntheticVerticalOriginY(font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, normalized_coords: []const f32) !i32 {
    var bounds = try font.glyphs().boundsAt(glyph_id, normalized_coords);
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

    const font_advance = @as(i32, font.properties().ascender) + y_strength - @as(i32, font.properties().descender);
    const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
    return @as(i32, bounds.y_max) + @divTrunc(font_advance - glyph_height, 2) + y_strength;
}

fn syntheticStrength(font: *const cangjie.font.Face, value: f32) i32 {
    return @intFromFloat(@round(@as(f32, @floatFromInt(font.properties().units_per_em)) * value));
}

fn harfBuzzVerticalAdvance(font: *const cangjie.font.Face, glyph: cangjie.shaping.Glyph) !i32 {
    if (try font.metrics().vertical(glyph.glyph_id)) |metrics| return -@as(i32, @intCast(metrics.advance_height));
    return -defaultVerticalAdvance(font);
}

fn defaultVerticalAdvance(font: *const cangjie.font.Face) i32 {
    return @as(i32, font.properties().ascender) - @as(i32, font.properties().descender);
}

fn usesSyntheticVerticalSpaceAdvance(codepoint: u21) bool {
    return switch (codepoint) {
        0x0020,
        0x00a0,
        0x2000...0x200a,
        0x202f,
        0x205f,
        0x3000,
        => true,
        else => false,
    };
}

fn fontUnitPosition(font: *const cangjie.font.Face, font_size: f32, value: f32) i32 {
    const font_units = value * @as(f32, @floatFromInt(font.properties().units_per_em)) / font_size;
    return @intFromFloat(@round(font_units));
}

fn shapeOnce(
    engine: *cangjie.shaping.Engine,
    font: *const cangjie.font.Face,
    cascade: cangjie.font.Cascade,
    text: []const u8,
    options: options_mod.Options,
    shape_options: cangjie.shaping.Options,
) ![]const cangjie.shaping.Glyph {
    if (options.feature_range_count != 0) return shapeOnceWithGsubFeatureRanges(
        engine,
        font,
        text,
        options,
        shape_options,
    );
    if (options.use_caches) {
        if (options.use_shaped_cache) {
            const shaped = try engine.shapeText(
                cascade,
                .{
                    .text = text,
                    .font_size = options.size,
                    .options = shape_options,
                },
            );
            return shaped.glyphs;
        }
        const run = try engine.shape(
            font,
            .{
                .text = text,
                .font_size = options.size,
                .options = shape_options,
            },
        );
        return run.glyphs;
    }
    const run = try engine.shape(
        font,
        .{
            .text = text,
            .font_size = options.size,
            .options = shape_options,
        },
    );
    return run.glyphs;
}

// Keep CLI-only rare-path setup out of the benchmark's common per-line helper;
// otherwise its code-size change would contaminate the zero-range A/B intended
// to measure the shaping library rather than this dispatch wrapper.
noinline fn shapeOnceWithGsubFeatureRanges(
    engine: *cangjie.shaping.Engine,
    font: *const cangjie.font.Face,
    text: []const u8,
    options: options_mod.Options,
    shape_options: cangjie.shaping.Options,
) ![]const cangjie.shaping.Glyph {
    const ranges = options.featureRanges();
    const run = try engine.shape(
        font,
        .{
            .text = text,
            .font_size = options.size,
            .options = shape_options,
            .feature_ranges = ranges,
        },
    );
    return run.glyphs;
}

fn glyphsChecksum(glyphs: []const cangjie.shaping.Glyph) u64 {
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
