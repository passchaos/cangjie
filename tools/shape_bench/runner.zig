const std = @import("std");
const cangjie = @import("cangjie");

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
        return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024));
    }

    return switch (options.builtin_font) {
        .minimal => try cangjie.testing.test_font.buildMinimalTtf(allocator),
        .minimal_gsub => try cangjie.testing.test_font.buildMinimalGsubTtf(allocator),
        .script_feature => try cangjie.testing.test_font.buildScriptFeatureGsubTtf(allocator),
    };
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
        .normalized_variation_coords = options.normalizedVariationCoords(),
        .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
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
                        .clusters = if (options.glyph_summary) try glyphClusters(allocator, line, glyphs, options.normalize_clusters_to_graphemes) else &.{},
                        .x_advances = if (options.glyph_summary) try glyphXAdvances(allocator, font, options.size, options, glyphs) else &.{},
                        .y_advances = if (options.glyph_summary) try glyphYAdvances(allocator, font, options.size, options, glyphs) else &.{},
                        .x_offsets = if (options.glyph_summary) try glyphXOffsets(allocator, font, options.size, options, glyphs) else &.{},
                        .y_offsets = if (options.glyph_summary) try glyphYOffsets(allocator, font, options.size, options, glyphs) else &.{},
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

fn glyphClusters(allocator: std.mem.Allocator, text: []const u8, glyphs: []const cangjie.GlyphPosition, normalize_to_graphemes: bool) ![]const u32 {
    const clusters = try allocator.alloc(u32, glyphs.len);
    if (!normalize_to_graphemes) {
        for (glyphs, clusters) |glyph, *cluster| cluster.* = @intCast(glyph.cluster);
        return clusters;
    }

    const graphemes = try cangjie.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    const indic_syllables = try indicSyllableClusters(allocator, text);
    defer allocator.free(indic_syllables);
    var previous_cluster: ?usize = null;
    var previous_raw_cluster: ?usize = null;
    for (glyphs, clusters, 0..) |glyph, *cluster, glyph_index| {
        const normalized = if (isPreBaseMatraCluster(text, glyph.cluster))
            normalizedPreBaseMatraClusterFromRun(indic_syllables, glyphs, glyph_index)
        else
            normalizedClusterStartForByte(text, graphemes, indic_syllables, glyph.cluster, previous_cluster, previous_raw_cluster);
        cluster.* = @intCast(normalized);
        previous_cluster = normalized;
        previous_raw_cluster = glyph.cluster;
    }
    return clusters;
}

const IndicSyllableCluster = struct {
    byte_start: usize,
    byte_len: usize,
    base_cluster: usize,
    initial_reph: bool,
    has_prebase_matra: bool,
};

fn normalizedClusterStartForByte(text: []const u8, graphemes: []const cangjie.GraphemeCluster, indic_syllables: []const IndicSyllableCluster, byte_offset: usize, previous_cluster: ?usize, previous_raw_cluster: ?usize) usize {
    if (codepointAtByte(text, byte_offset)) |codepoint| {
        if (isPreBaseMatra(codepoint)) {
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable| return syllable.base_cluster;
        } else if (codepoint == 0x094d) {
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable| return syllable.byte_start;
        } else if (isDevanagariDependentMark(codepoint)) {
            if (previous_cluster) |cluster| return cluster;
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable| return syllable.base_cluster;
        } else if (isDevanagariConsonant(codepoint)) {
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable| {
                if (syllable.has_prebase_matra) return if (byte_offset >= syllable.base_cluster)
                    if (previous_cluster) |cluster|
                        if (cluster >= syllable.byte_start and cluster < byte_offset) cluster else byte_offset
                    else
                        byte_offset
                else
                    syllable.byte_start;
                if (syllable.initial_reph and byte_offset != syllable.byte_start) {
                    if (previous_cluster == syllable.byte_start and previous_raw_cluster != syllable.byte_start and followsVirama(text, byte_offset)) return syllable.byte_start;
                    return if (isFirstPostHalantConsonant(text, syllable.byte_start, byte_offset))
                        syllable.byte_start
                    else
                        byte_offset;
                }
                return byte_offset;
            }
        } else if (codepoint == 0x200d) {
            if (previous_cluster) |cluster| return cluster;
            return byte_offset;
        } else if (codepoint == 0x200c) {
            return byte_offset;
        }
    }
    return graphemeClusterStartForByte(graphemes, byte_offset);
}

fn graphemeClusterStartForByte(graphemes: []const cangjie.GraphemeCluster, byte_offset: usize) usize {
    for (graphemes) |current| {
        if (byte_offset >= current.byte_start and byte_offset < current.byte_start + current.byte_len) return current.byte_start;
    }
    return byte_offset;
}

fn isPreBaseMatraCluster(text: []const u8, byte_offset: usize) bool {
    const codepoint = codepointAtByte(text, byte_offset) orelse return false;
    return isPreBaseMatra(codepoint);
}

fn normalizedPreBaseMatraClusterFromRun(indic_syllables: []const IndicSyllableCluster, glyphs: []const cangjie.GlyphPosition, glyph_index: usize) usize {
    const matra_cluster = glyphs[glyph_index].cluster;
    const syllable = indicSyllableContainingByte(indic_syllables, matra_cluster) orelse return matra_cluster;
    if (syllable.initial_reph) return syllable.byte_start;
    var best: ?usize = null;
    for (glyphs[glyph_index + 1 ..]) |candidate| {
        const candidate_cluster = candidate.cluster;
        if (candidate_cluster < syllable.byte_start or candidate_cluster >= syllable.byte_start + syllable.byte_len) continue;
        if (candidate_cluster >= matra_cluster) continue;
        best = candidate_cluster;
        break;
    }
    return best orelse syllable.base_cluster;
}

fn indicSyllableClusters(allocator: std.mem.Allocator, text: []const u8) ![]const IndicSyllableCluster {
    var clusters = std.ArrayList(IndicSyllableCluster).empty;
    errdefer clusters.deinit(allocator);

    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var cursor: usize = 0;
    var syllable_start: ?usize = null;
    var syllable_end: usize = 0;
    var saw_virama = false;
    var saw_post_virama_consonant = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        const byte_end = cursor;

        if (!isIndicSyllableCodepoint(codepoint)) {
            if (syllable_start) |start| {
                try appendIndicSyllable(&clusters, allocator, text, start, syllable_end);
                syllable_start = null;
            }
            saw_virama = false;
            saw_post_virama_consonant = false;
            continue;
        }

        if (syllable_start != null and isDevanagariBase(codepoint) and !saw_virama and byte_start != syllable_start.?) {
            try appendIndicSyllable(&clusters, allocator, text, syllable_start.?, syllable_end);
            syllable_start = byte_start;
            saw_virama = false;
            saw_post_virama_consonant = false;
        } else if (syllable_start == null) {
            syllable_start = byte_start;
            saw_virama = false;
            saw_post_virama_consonant = false;
        }
        syllable_end = byte_end;

        if (codepoint == 0x094d) {
            saw_virama = true;
        } else if (saw_virama and isDevanagariConsonant(codepoint)) {
            saw_post_virama_consonant = true;
            saw_virama = false;
        } else if (saw_post_virama_consonant and isDevanagariDependentMark(codepoint)) {
            // Keep the mark in this syllable.
        } else if (!isDevanagariDependentMark(codepoint) and codepoint != 0x200c and codepoint != 0x200d) {
            saw_virama = false;
        }
    }

    if (syllable_start) |start| {
        try appendIndicSyllable(&clusters, allocator, text, start, syllable_end);
    }
    return try clusters.toOwnedSlice(allocator);
}

fn appendIndicSyllable(clusters: *std.ArrayList(IndicSyllableCluster), allocator: std.mem.Allocator, text: []const u8, start: usize, end: usize) !void {
    const initial_reph = startsWithInitialReph(text[start..end]);
    try clusters.append(allocator, .{
        .byte_start = start,
        .byte_len = end - start,
        .base_cluster = indicSyllableBaseCluster(text[start..end], start, initial_reph),
        .initial_reph = initial_reph,
        .has_prebase_matra = hasPreBaseMatra(text[start..end]),
    });
}

fn indicSyllableContainingByte(syllables: []const IndicSyllableCluster, byte_offset: usize) ?IndicSyllableCluster {
    for (syllables) |current| {
        if (byte_offset >= current.byte_start and byte_offset < current.byte_start + current.byte_len) return current;
    }
    return null;
}

fn codepointAtByte(text: []const u8, byte_offset: usize) ?u21 {
    var view = std.unicode.Utf8View.init(text) catch return null;
    var it = view.iterator();
    var cursor: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start == byte_offset) return codepoint;
        if (byte_start > byte_offset) return null;
    }
    return null;
}

fn startsWithInitialReph(text: []const u8) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    const first = it.nextCodepoint() orelse return false;
    const second = it.nextCodepoint() orelse return false;
    if (first != 0x0930 or second != 0x094d) return false;
    const third = it.nextCodepoint() orelse return false;
    if (third == 0x200c or third == 0x200d) return false;
    if (isDevanagariConsonant(third)) return true;
    while (it.nextCodepoint()) |codepoint| {
        if (isDevanagariConsonant(codepoint)) return true;
    }
    return false;
}

fn isFirstPostHalantConsonant(text: []const u8, syllable_start: usize, byte_offset: usize) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    var cursor: usize = 0;
    var previous_was_virama = false;
    var seen_post_halant_consonant = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start < syllable_start) continue;
        if (byte_start > byte_offset) return false;

        const is_target = byte_start == byte_offset;
        if (previous_was_virama and isDevanagariConsonant(codepoint)) {
            if (is_target) return !seen_post_halant_consonant;
            seen_post_halant_consonant = true;
        } else if (is_target) {
            return false;
        }
        previous_was_virama = codepoint == 0x094d;
    }
    return false;
}

fn followsVirama(text: []const u8, byte_offset: usize) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    var cursor: usize = 0;
    var previous: ?u21 = null;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start == byte_offset) return previous == 0x094d;
        if (byte_start > byte_offset) return false;
        previous = codepoint;
    }
    return false;
}

fn indicSyllableBaseCluster(text: []const u8, byte_base: usize, initial_reph: bool) usize {
    if (initial_reph) return byte_base;

    var view = std.unicode.Utf8View.init(text) catch return byte_base;
    var it = view.iterator();
    var cursor: usize = 0;
    var base_cluster = byte_base;
    var saw_virama = false;
    var virama_before_ra = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;

        if (codepoint == 0x094d) {
            saw_virama = true;
            continue;
        }
        if (saw_virama and isDevanagariConsonant(codepoint)) {
            if (codepoint == 0x0930) {
                virama_before_ra = true;
            } else {
                base_cluster = byte_base + byte_start;
            }
            saw_virama = false;
            continue;
        }
        if (isDevanagariConsonant(codepoint) and !virama_before_ra and base_cluster == byte_base) {
            base_cluster = byte_base + byte_start;
        }
        if (!isDevanagariDependentMark(codepoint) and codepoint != 0x200c and codepoint != 0x200d) {
            saw_virama = false;
        }
    }

    return if (virama_before_ra) byte_base else base_cluster;
}

fn isIndicSyllableCodepoint(codepoint: u21) bool {
    return isDevanagariBase(codepoint) or
        isDevanagariDependentMark(codepoint) or
        codepoint == 0x094d or
        codepoint == 0x200c or
        codepoint == 0x200d;
}

fn isDevanagariBase(codepoint: u21) bool {
    return isDevanagariConsonant(codepoint) or isDevanagariIndependentVowel(codepoint);
}

fn isDevanagariConsonant(codepoint: u21) bool {
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        (codepoint >= 0x0958 and codepoint <= 0x095f);
}

fn isDevanagariIndependentVowel(codepoint: u21) bool {
    return (codepoint >= 0x0904 and codepoint <= 0x0914) or
        codepoint == 0x0960 or
        codepoint == 0x0961;
}

fn isDevanagariDependentMark(codepoint: u21) bool {
    return (codepoint >= 0x0900 and codepoint <= 0x0903) or
        (codepoint >= 0x093a and codepoint <= 0x094c) or
        (codepoint >= 0x094e and codepoint <= 0x094f) or
        (codepoint >= 0x0951 and codepoint <= 0x0957);
}

fn isPreBaseMatra(codepoint: u21) bool {
    return codepoint == 0x093f;
}

fn hasPreBaseMatra(text: []const u8) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    while (it.nextCodepoint()) |codepoint| {
        if (isPreBaseMatra(codepoint)) return true;
    }
    return false;
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
        value.* = if (options.direction == .ttb and glyph.vertical and runtime_value > 0)
            try harfBuzzVerticalAdvance(font, glyph)
        else
            runtime_value;
    }
    return values;
}

fn glyphXOffsets(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = if (options.direction == .ttb and glyph.vertical)
            -@divTrunc(@as(i32, (try font.horizontalMetrics(glyph.glyph_id)).advance_width), 2)
        else
            fontUnitPosition(font, font_size, glyph.x_offset);
    }
    return values;
}

fn glyphYOffsets(allocator: std.mem.Allocator, font: *const cangjie.Font, font_size: f32, options: options_mod.Options, glyphs: []const cangjie.GlyphPosition) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| {
        value.* = if (options.direction == .ttb and glyph.vertical)
            -@divTrunc(defaultVerticalAdvance(font), 2)
        else
            fontUnitPosition(font, font_size, glyph.y_offset);
    }
    return values;
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
