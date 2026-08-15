const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");
const report = @import("report.zig");

pub fn loadFontBytes(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options) ![]u8 {
    if (options.font_path) |path| {
        return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024));
    }
    return switch (options.builtin_font) {
        .minimal => try cangjie.testing.test_font.buildMinimalTtf(allocator),
        .gvar_compound => try cangjie.testing.test_font.buildGvarCompoundTtf(allocator),
        .cff2_variation => try cangjie.testing.test_font.buildCff2VariationOtf(allocator),
    };
}

pub fn run(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.font.Face, options: options_mod.Options) !report.Result {
    const glyph_id = try resolveGlyphId(font, options);
    if (options.warmup != 0) {
        var warmup_checksum: u64 = 0;
        try runIterations(allocator, font, glyph_id, options, options.warmup, &warmup_checksum);
    }

    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runIterations(allocator, font, glyph_id, options, options.iterations, &sample_checksum);
        const sample_elapsed = std.Io.Clock.now(.awake, io).nanoseconds - start;
        elapsed += sample_elapsed;
        checksum = updateChecksum(checksum, sample_checksum);
        try samples.append(allocator, .{
            .index = sample_index,
            .elapsed_ns = sample_elapsed,
            .iterations = options.iterations,
            .checksum = sample_checksum,
        });
    }
    return .{
        .elapsed_ns = elapsed,
        .checksum = checksum,
        .samples = try samples.toOwnedSlice(allocator),
    };
}

fn resolveGlyphId(font: *const cangjie.font.Face, options: options_mod.Options) !cangjie.font.GlyphId {
    if (options.glyph_id) |glyph_id| return glyph_id;
    if (options.font_path == null and options.builtin_font == .gvar_compound) return 2;
    return try font.glyphs().index(options.codepoint);
}

fn runIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    switch (options.mode) {
        .outline => try runOutlineIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster => try runRasterIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster_reuse => try runRasterReuseIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster_prepared => try runRasterPreparedIterations(allocator, font, glyph_id, options, iterations, checksum),
    }
}

fn runOutlineIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const coords = options.normalizedVariationCoords();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var outline = if (coords.len == 0)
            try font.glyphs().outline(allocator, glyph_id)
        else
            try font.glyphs().outlineAt(allocator, glyph_id, coords);
        checksum.* = updateChecksum(checksum.*, outlineChecksum(outline));
        outline.deinit();
    }
}

fn runRasterIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    var target = try cangjie.render.GrayTarget.init(allocator, options.target_size, options.target_size);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setHintSize(options.font_size);
    rasterizer.setSampling(options.samples_per_axis);
    const units_per_em = font.properties().units_per_em;
    const coords = options.normalizedVariationCoords();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        target.clear(0);
        {
            var outline = if (coords.len == 0)
                try font.glyphs().outline(allocator, glyph_id)
            else
                try font.glyphs().outlineAt(allocator, glyph_id, coords);
            defer outline.deinit();
            try rasterizer.drawOutline(&target, &outline, 0, options.font_size, options.font_size, units_per_em);
        }
        checksum.* = updateChecksum(checksum.*, bytesChecksum(target.pixels));
    }
}

fn runRasterReuseIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const coords = options.normalizedVariationCoords();
    var outline = if (coords.len == 0)
        try font.glyphs().outline(allocator, glyph_id)
    else
        try font.glyphs().outlineAt(allocator, glyph_id, coords);
    defer outline.deinit();

    var target = try cangjie.render.GrayTarget.init(allocator, options.target_size, options.target_size);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setHintSize(options.font_size);
    rasterizer.setSampling(options.samples_per_axis);
    const units_per_em = font.properties().units_per_em;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        target.clear(0);
        try rasterizer.drawOutline(&target, &outline, 0, options.font_size, options.font_size, units_per_em);
        checksum.* = updateChecksum(checksum.*, bytesChecksum(target.pixels));
    }
}

fn runRasterPreparedIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const coords = options.normalizedVariationCoords();
    var outline = if (coords.len == 0)
        try font.glyphs().outline(allocator, glyph_id)
    else
        try font.glyphs().outlineAt(allocator, glyph_id, coords);
    defer outline.deinit();

    var target = try cangjie.render.GrayTarget.init(allocator, options.target_size, options.target_size);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setHintSize(options.font_size);
    rasterizer.setSampling(options.samples_per_axis);
    var prepared = try rasterizer.prepare(
        &outline,
        0,
        options.font_size,
        options.font_size,
        font.properties().units_per_em,
    );
    defer prepared.deinit();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        target.clear(0);
        try rasterizer.drawPrepared(&target, &prepared);
        checksum.* = updateChecksum(checksum.*, bytesChecksum(target.pixels));
    }
}

fn outlineChecksum(outline: cangjie.font.Outline) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&outline.glyph_id));
    hasher.update(std.mem.asBytes(&outline.bounds));
    hasher.update(std.mem.asBytes(&outline.advance_width));
    hasher.update(std.mem.asBytes(&outline.left_side_bearing));
    for (outline.commands.items) |command| {
        hasher.update(std.mem.asBytes(&command));
    }
    return hasher.final();
}

fn bytesChecksum(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn updateChecksum(seed: u64, value: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&value));
    return hasher.final();
}
