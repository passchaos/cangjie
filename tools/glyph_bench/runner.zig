const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");
const report = @import("report.zig");
const dirty_rect = @import("dirty_rect.zig");

pub fn loadFontBytes(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options) ![]u8 {
    if (options.font_path) |path| {
        return try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(256 * 1024 * 1024));
    }
    return switch (options.builtin_font) {
        .minimal => try cangjie.testing.test_font.buildMinimalTtf(allocator),
        .gvar_compound => try cangjie.testing.test_font.buildGvarCompoundTtf(allocator),
        .cff2_variation => try cangjie.testing.test_font.buildCff2VariationOtf(allocator),
        .cbdt_bgra => try cangjie.testing.test_font.buildCbdtBgraTtf(allocator),
    };
}

pub fn run(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.font.Face, options: options_mod.Options) !report.Result {
    const glyph_id = try resolveGlyphId(font, options);
    if (options.dirty_rect) {
        return switch (options.mode) {
            .raster_reuse => runRasterReuseDirty(io, allocator, font, glyph_id, options),
            .raster_prepared => runPreparedDirty(io, allocator, font, glyph_id, options),
            else => error.InvalidArguments,
        };
    }
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
        .dirty_pixels = 0,
    };
}

fn runRasterReuseDirty(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options) !report.Result {
    const coords = options.normalizedVariationCoords();
    const session = font.glyphs().session();
    var outline = if (coords.len == 0)
        try session.outline(allocator, glyph_id)
    else
        try session.outlineAt(allocator, glyph_id, coords);
    defer outline.deinit();
    var target = try cangjie.render.GrayTarget.init(allocator, options.target_size, options.target_size);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setHintSize(options.font_size);
    rasterizer.setSampling(options.samples_per_axis);
    const units_per_em = font.properties().units_per_em;

    // Discover the exact clipped antialiasing fringe once. The measured loop
    // still runs the ordinary scan converter on every iteration; only the
    // target clear and consumer are restricted to pixels that can change.
    try rasterizer.drawOutline(&target, &outline, 0, options.font_size, options.font_size, units_per_em);
    const bounds = dirty_rect.nonZeroBounds(target.pixels, target.width);
    const dirty_pixels = if (bounds) |value| value.pixelCount() else 0;
    if (options.warmup != 0) {
        var ignored: u64 = 0;
        try runRasterReuseDirtyIterations(&rasterizer, &target, &outline, units_per_em, bounds, options, options.warmup, &ignored);
    }
    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    for (0..options.samples) |sample_index| {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runRasterReuseDirtyIterations(&rasterizer, &target, &outline, units_per_em, bounds, options, options.iterations, &sample_checksum);
        const duration = std.Io.Clock.now(.awake, io).nanoseconds - start;
        elapsed += duration;
        checksum = updateChecksum(checksum, sample_checksum);
        try samples.append(allocator, .{ .index = sample_index, .elapsed_ns = duration, .iterations = options.iterations, .checksum = sample_checksum });
    }
    return .{ .elapsed_ns = elapsed, .checksum = checksum, .samples = try samples.toOwnedSlice(allocator), .dirty_pixels = dirty_pixels };
}

fn runRasterReuseDirtyIterations(rasterizer: *cangjie.render.Rasterizer, target: *cangjie.render.GrayTarget, outline: *const cangjie.font.Outline, units_per_em: u16, bounds: ?dirty_rect.Bounds, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    for (0..iterations) |_| {
        dirty_rect.clear(target.pixels, target.width, bounds);
        try rasterizer.drawOutline(target, outline, 0, options.font_size, options.font_size, units_per_em);
        checksum.* = updateChecksum(checksum.*, dirty_rect.checksum(target.pixels, target.width, bounds));
    }
}

fn runPreparedDirty(io: std.Io, allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options) !report.Result {
    const coords = options.normalizedVariationCoords();
    const session = font.glyphs().session();
    var outline = if (coords.len == 0)
        try session.outline(allocator, glyph_id)
    else
        try session.outlineAt(allocator, glyph_id, coords);
    defer outline.deinit();
    var target = try cangjie.render.GrayTarget.init(allocator, options.target_size, options.target_size);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setHintSize(options.font_size);
    rasterizer.setSampling(options.samples_per_axis);
    var prepared = try rasterizer.prepare(&outline, 0, options.font_size, options.font_size, font.properties().units_per_em);
    defer prepared.deinit();
    // Discover the exact clipped rectangle once outside timing. This keeps the
    // benchmark on public renderer APIs and includes the same antialiasing
    // fringe that repeated atlas updates must clear.
    try rasterizer.drawPrepared(&target, &prepared);
    const bounds = dirty_rect.nonZeroBounds(target.pixels, target.width);
    const dirty_pixels = if (bounds) |value| value.pixelCount() else 0;
    if (options.warmup != 0) {
        var ignored: u64 = 0;
        try runPreparedDirtyIterations(&rasterizer, &target, &prepared, bounds, options.warmup, &ignored);
    }
    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    for (0..options.samples) |sample_index| {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runPreparedDirtyIterations(&rasterizer, &target, &prepared, bounds, options.iterations, &sample_checksum);
        const duration = std.Io.Clock.now(.awake, io).nanoseconds - start;
        elapsed += duration;
        checksum = updateChecksum(checksum, sample_checksum);
        try samples.append(allocator, .{ .index = sample_index, .elapsed_ns = duration, .iterations = options.iterations, .checksum = sample_checksum });
    }
    return .{ .elapsed_ns = elapsed, .checksum = checksum, .samples = try samples.toOwnedSlice(allocator), .dirty_pixels = dirty_pixels };
}

fn runPreparedDirtyIterations(rasterizer: *cangjie.render.Rasterizer, target: *cangjie.render.GrayTarget, prepared: *const cangjie.render.Prepared, bounds: ?dirty_rect.Bounds, iterations: usize, checksum: *u64) !void {
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        dirty_rect.clear(target.pixels, target.width, bounds);
        try rasterizer.drawPrepared(target, prepared);
        checksum.* = updateChecksum(checksum.*, dirty_rect.checksum(target.pixels, target.width, bounds));
    }
}

fn resolveGlyphId(font: *const cangjie.font.Face, options: options_mod.Options) !cangjie.font.GlyphId {
    if (options.glyph_id) |glyph_id| return glyph_id;
    if (options.builtin_font == .cbdt_bgra) return 1;
    if (options.font_path == null and options.builtin_font == .gvar_compound) return 2;
    return try font.glyphs().index(options.codepoint);
}

fn runIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    switch (options.mode) {
        .charmap => try runCharmapIterations(font, options, iterations, checksum),
        .metrics => try runMetricsIterations(font, glyph_id, iterations, checksum),
        .global_metrics => try runGlobalMetricsIterations(font, iterations, checksum),
        .family_name => try runFamilyNameIterations(allocator, font, iterations, checksum),
        .glyph_name => try runGlyphNameIterations(font, glyph_id, iterations, checksum),
        .bitmap => try runBitmapIterations(font, glyph_id, options, iterations, checksum),
        .outline => try runOutlineIterations(allocator, font, glyph_id, options, iterations, checksum),
        .outline_session => try runOutlineSessionIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster => try runRasterIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster_reuse => try runRasterReuseIterations(allocator, font, glyph_id, options, iterations, checksum),
        .raster_prepared => try runRasterPreparedIterations(allocator, font, glyph_id, options, iterations, checksum),
    }
}

fn runGlyphNameIterations(
    font: *const cangjie.font.Face,
    glyph_id: cangjie.font.GlyphId,
    iterations: usize,
    checksum: *u64,
) !void {
    var buffer: [16]u8 = undefined;
    for (0..iterations) |_| {
        const value = try font.glyphs().resolvedName(glyph_id, &buffer);
        for (value) |byte| checksum.* = checksum.* *% 0x100000001b3 ^ byte;
    }
}

test "glyph name benchmark hashes post CFF and synthesized values" {
    const allocator = std.testing.allocator;
    const Source = enum { post, cff, synthesized };
    inline for ([_]Source{ .post, .cff, .synthesized }) |source| {
        const bytes = switch (source) {
            .post => blk: {
                var post: [41]u8 = .{0} ** 41;
                std.mem.writeInt(u32, post[0..4], 0x00020000, .big);
                std.mem.writeInt(u16, post[32..34], 2, .big);
                std.mem.writeInt(u16, post[34..36], 0, .big);
                std.mem.writeInt(u16, post[36..38], 258, .big);
                post[38] = 2;
                @memcpy(post[39..41], "A1");
                break :blk try cangjie.testing.test_font.buildMinimalTtfWithPost(
                    allocator,
                    &post,
                );
            },
            .cff => try cangjie.testing.test_font.buildCffGlyphNamesOtf(allocator),
            .synthesized => try cangjie.testing.test_font.buildMinimalTtf(allocator),
        };
        defer allocator.free(bytes);
        var face = try cangjie.font.Face.parse(allocator, bytes);
        defer face.deinit();
        var checksum: u64 = 0;
        try runGlyphNameIterations(&face, 1, 1, &checksum);
        const expected = switch (source) {
            .post => "A1",
            .cff => "customGlyph",
            .synthesized => "gid1",
        };
        var expected_checksum: u64 = 0;
        for (expected) |byte| {
            expected_checksum = expected_checksum *% 0x100000001b3 ^ byte;
        }
        try std.testing.expectEqual(expected_checksum, checksum);
    }
}

fn runFamilyNameIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, iterations: usize, checksum: *u64) !void {
    var buffer: [256]u8 = undefined;
    for (0..iterations) |_| {
        const value = (try font.names().englishOrFirst(allocator, .family)) orelse return error.InvalidArguments;
        const decoded = try value.decodeUtf8(&buffer);
        for (decoded) |byte| checksum.* = checksum.* *% 0x100000001b3 ^ byte;
    }
}

fn runGlobalMetricsIterations(
    font: *const cangjie.font.Face,
    iterations: usize,
    checksum: *u64,
) !void {
    for (0..iterations) |_| {
        const metrics = try font.metrics().global(null);
        checksum.* +%= metrics.units_per_em;
        checksum.* +%= metrics.glyph_count;
        checksum.* +%= @intFromBool(metrics.is_monospace);
        checksum.* +%= @as(u32, @bitCast(metrics.italic_angle));
        checksum.* +%= @as(u32, @bitCast(metrics.ascent));
        checksum.* +%= @as(u32, @bitCast(metrics.descent));
        checksum.* +%= @as(u32, @bitCast(metrics.leading));
        checksum.* +%= optionalFloatBits(metrics.cap_height);
        checksum.* +%= optionalFloatBits(metrics.x_height);
        checksum.* +%= optionalFloatBits(metrics.average_width);
        checksum.* +%= optionalFloatBits(metrics.max_width);
        if (metrics.underline) |value| {
            checksum.* +%= @as(u32, @bitCast(value.offset));
            checksum.* +%= @as(u32, @bitCast(value.thickness));
        }
        if (metrics.strikeout) |value| {
            checksum.* +%= @as(u32, @bitCast(value.offset));
            checksum.* +%= @as(u32, @bitCast(value.thickness));
        }
        checksum.* +%= @as(u32, @bitCast(metrics.bounds.x_min));
        checksum.* +%= @as(u32, @bitCast(metrics.bounds.y_min));
        checksum.* +%= @as(u32, @bitCast(metrics.bounds.x_max));
        checksum.* +%= @as(u32, @bitCast(metrics.bounds.y_max));
    }
}

fn optionalFloatBits(value: ?f32) u64 {
    return if (value) |item| @as(u32, @bitCast(item)) else 0;
}

fn runBitmapIterations(
    font: *const cangjie.font.Face,
    glyph_id: cangjie.font.GlyphId,
    options: options_mod.Options,
    iterations: usize,
    checksum: *u64,
) !void {
    for (0..iterations) |_| {
        const data = (try font.color().bitmapData(
            glyph_id,
            options.font_size,
        )) orelse return error.InvalidArguments;
        checksum.* +%= switch (data) {
            inline else => |glyph| glyph.width + glyph.height + glyph.data.len,
        };
    }
}

fn runCharmapIterations(
    font: *const cangjie.font.Face,
    options: options_mod.Options,
    iterations: usize,
    checksum: *u64,
) !void {
    for (0..iterations) |_| {
        checksum.* +%= try font.glyphs().index(options.codepoint);
    }
}

fn runMetricsIterations(
    font: *const cangjie.font.Face,
    glyph_id: cangjie.font.GlyphId,
    iterations: usize,
    checksum: *u64,
) !void {
    for (0..iterations) |_| {
        const value = try font.metrics().horizontal(glyph_id);
        checksum.* +%= (@as(u64, value.advance_width) << 16) |
            @as(u16, @bitCast(value.left_side_bearing));
    }
}

fn runOutlineSessionIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const coords = options.normalizedVariationCoords();
    const session = font.glyphs().session();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var outline = if (coords.len == 0)
            try session.outline(allocator, glyph_id)
        else
            try session.outlineAt(allocator, glyph_id, coords);
        checksum.* = updateChecksum(checksum.*, outlineChecksum(outline));
        outline.deinit();
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
            const session = font.glyphs().session();
            var outline = if (coords.len == 0)
                try session.outline(allocator, glyph_id)
            else
                try session.outlineAt(allocator, glyph_id, coords);
            defer outline.deinit();
            try rasterizer.drawOutline(&target, &outline, 0, options.font_size, options.font_size, units_per_em);
        }
        checksum.* = updateChecksum(checksum.*, bytesChecksum(target.pixels));
    }
}

fn runRasterReuseIterations(allocator: std.mem.Allocator, font: *const cangjie.font.Face, glyph_id: cangjie.font.GlyphId, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const coords = options.normalizedVariationCoords();
    const session = font.glyphs().session();
    var outline = if (coords.len == 0)
        try session.outline(allocator, glyph_id)
    else
        try session.outlineAt(allocator, glyph_id, coords);
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
    const session = font.glyphs().session();
    var outline = if (coords.len == 0)
        try session.outline(allocator, glyph_id)
    else
        try session.outlineAt(allocator, glyph_id, coords);
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
