const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");

pub const BenchResult = struct {
    elapsed_ns: i128,
    glyph_count: usize,
    checksum: u64,
    profile: cangjie.ShapeStageProfile,
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
    var gpos_proof_cache = cangjie.GposTableProofCache.init(allocator);
    defer gpos_proof_cache.deinit();
    if (options.use_caches) {
        layout_buffer.gdef_metadata_cache = &gdef_cache;
        layout_buffer.gpos_table_proof_cache = &gpos_proof_cache;
    }

    const cascade_fonts = [_]*const cangjie.Font{font};
    const cascade = cangjie.FontCascade.init(&cascade_fonts);
    const shape_options = cangjie.ShapeOptions{
        .direction = options.direction,
        .script_position = options.script_position,
    };

    var warmup_index: usize = 0;
    while (warmup_index < options.warmup) : (warmup_index += 1) {
        _ = try shapeOnce(font, cascade, &metrics_cache, &glyph_index_cache, &layout_buffer, options, shape_options);
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
    const start = std.Io.Clock.now(.awake, io).nanoseconds;
    var i: usize = 0;
    while (i < options.iterations) : (i += 1) {
        const glyphs = try shapeOnce(font, cascade, &metrics_cache, &glyph_index_cache, &layout_buffer, options, shape_options);
        glyph_count += glyphs.len;
        checksum = updateChecksum(checksum, glyphs);
    }
    const elapsed = std.Io.Clock.now(.awake, io).nanoseconds - start;

    return .{
        .elapsed_ns = elapsed,
        .glyph_count = glyph_count,
        .checksum = checksum,
        .profile = profile,
    };
}

fn shapeOnce(
    font: *const cangjie.Font,
    cascade: cangjie.FontCascade,
    metrics_cache: *cangjie.GlyphMetricsCache,
    glyph_index_cache: *cangjie.GlyphIndexCache,
    layout_buffer: *cangjie.LayoutBuffer,
    options: options_mod.Options,
    shape_options: cangjie.ShapeOptions,
) ![]const cangjie.GlyphPosition {
    if (options.use_caches) {
        const shaped = try cangjie.TextShaper.shapeUtf8CascadeFullyCachedWithOptions(cascade, null, metrics_cache, glyph_index_cache, layout_buffer, options.text, options.size, shape_options);
        return shaped.glyphs;
    }
    const run = try cangjie.TextShaper.shapeUtf8WithOptions(font, layout_buffer, options.text, options.size, shape_options);
    return run.glyphs;
}

fn updateChecksum(seed: u64, glyphs: []const cangjie.GlyphPosition) u64 {
    var hasher = std.hash.Wyhash.init(seed);
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
