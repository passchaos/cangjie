const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");

pub const BenchResult = struct {
    pub const LineSummary = struct {
        index: usize,
        text_bytes: usize,
        glyph_count: usize,
        checksum: u64,
        glyph_ids: []const u16 = &.{},
        clusters: []const u32 = &.{},
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
        .direction = options.direction,
        .reorder_bidi = options.reorder_bidi,
        .language_tag = options.language_tag,
        .script_position = options.script_position,
        .features = options.featureOverrides(),
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
        layout_buffer.profile_io = io;
    }
    defer if (options.profile) {
        layout_buffer.shape_profile = null;
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
                        .clusters = if (options.glyph_summary) try glyphClusters(allocator, glyphs) else &.{},
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

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const cangjie.GlyphPosition) ![]const u16 {
    const ids = try allocator.alloc(u16, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.glyph_id;
    return ids;
}

fn glyphClusters(allocator: std.mem.Allocator, glyphs: []const cangjie.GlyphPosition) ![]const u32 {
    const clusters = try allocator.alloc(u32, glyphs.len);
    for (glyphs, clusters) |glyph, *cluster| cluster.* = @intCast(glyph.cluster);
    return clusters;
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
        hasher.update(std.mem.asBytes(&glyph.glyph_id));
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
