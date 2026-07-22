const std = @import("std");
const builtin = @import("builtin");
const cangjie = @import("cangjie");

const system_font_path = "/System/Library/Fonts/SFNSMono.ttf";
const known_sfns_mono_sha256 = hexToBytes("55caaed55254a28ac793847e8976be16c5ba7cbad1ec2ee2d5d86d4e6b3fa0c1");
const known_raster_sha256 = hexToBytes("34a1bfb1a733fcdd75878af95959d4341557f9991b94ae29110429a6fc5d20b2");

test "macOS SFNSMono parses shapes and rasterizes stable grayscale glyphs" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, system_font_path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);

    var font_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(font_bytes, &font_digest, .{});
    const known_font = std.mem.eql(u8, &font_digest, &known_sfns_mono_sha256);

    var font = cangjie.Font.parse(allocator, font_bytes) catch |err| switch (err) {
        error.BadSfnt,
        error.InvalidGlyph,
        error.MissingTable,
        error.UnsupportedCff,
        error.UnsupportedCmap,
        error.UnsupportedGlyph,
        => if (known_font) return err else return error.SkipZigTest,
        else => return err,
    };
    defer font.deinit();

    try std.testing.expectEqual(cangjie.FontFormat.truetype, font.format);
    try std.testing.expect(font.units_per_em >= 16);
    try std.testing.expect((try font.glyphIndex('C')) > 0);
    try std.testing.expect((try font.glyphIndex('j')) > 0);

    var layout_buffer = cangjie.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try cangjie.TextShaper.shapeUtf8(&font, &layout_buffer, "Cangjie", 36);
    try std.testing.expectEqual(@as(usize, 7), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 155.77734), run.width(), 0.001);

    var target = try cangjie.RenderTarget.init(allocator, 240, 96);
    defer target.deinit();

    var rasterizer = cangjie.Rasterizer.init(allocator);
    try rasterizer.renderRun(&target, run, 12, 60);

    const stats = rasterStats(&target);
    try std.testing.expectEqual(@as(usize, 1180), stats.covered);
    try std.testing.expectEqual(@as(u64, 216468), stats.coverage_sum);
    try std.testing.expectEqual(@as(u8, 255), stats.max_coverage);
    try std.testing.expectEqual(RasterBounds{ .min_x = 14, .min_y = 31, .max_x = 164, .max_y = 66 }, stats.bounds.?);

    if (known_font) {
        var raster_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(target.pixels, &raster_digest, .{});
        try std.testing.expectEqualSlices(u8, &known_raster_sha256, &raster_digest);
    }
}

const RasterBounds = struct {
    min_x: u32,
    min_y: u32,
    max_x: u32,
    max_y: u32,
};

const RasterStats = struct {
    covered: usize,
    coverage_sum: u64,
    max_coverage: u8,
    bounds: ?RasterBounds,
};

fn rasterStats(target: *const cangjie.RenderTarget) RasterStats {
    var stats = RasterStats{
        .covered = 0,
        .coverage_sum = 0,
        .max_coverage = 0,
        .bounds = null,
    };

    for (target.pixels, 0..) |coverage, index| {
        if (coverage == 0) continue;
        const x: u32 = @intCast(index % target.width);
        const y: u32 = @intCast(index / target.width);
        stats.covered += 1;
        stats.coverage_sum += coverage;
        stats.max_coverage = @max(stats.max_coverage, coverage);
        if (stats.bounds) |*bounds| {
            bounds.min_x = @min(bounds.min_x, x);
            bounds.min_y = @min(bounds.min_y, y);
            bounds.max_x = @max(bounds.max_x, x);
            bounds.max_y = @max(bounds.max_y, y);
        } else {
            stats.bounds = .{ .min_x = x, .min_y = y, .max_x = x, .max_y = y };
        }
    }

    return stats;
}

fn hexToBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    comptime {
        if (hex.len % 2 != 0) @compileError("hex string must have an even number of digits");
    }
    var bytes: [hex.len / 2]u8 = undefined;
    for (&bytes, 0..) |*byte, index| {
        byte.* = parseHexByte(hex[index * 2], hex[index * 2 + 1]);
    }
    return bytes;
}

fn parseHexByte(comptime high: u8, comptime low: u8) u8 {
    return (hexNibble(high) << 4) | hexNibble(low);
}

fn hexNibble(comptime digit: u8) u8 {
    return switch (digit) {
        '0'...'9' => digit - '0',
        'a'...'f' => digit - 'a' + 10,
        'A'...'F' => digit - 'A' + 10,
        else => @compileError("invalid hex digit"),
    };
}
