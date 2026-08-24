const std = @import("std");
const ft = @import("freetype");

const options_mod = @import("options.zig");
const report = @import("report.zig");
const dirty_rect = @import("dirty_rect.zig");

const FreeTypeFace = struct {
    library: ft.FT_Library,
    face: ft.FT_Face,

    fn init(font_bytes: []const u8, options: options_mod.Options) !FreeTypeFace {
        var library: ft.FT_Library = null;
        if (ft.FT_Init_FreeType(&library) != 0) return error.FreeTypeFailed;
        errdefer _ = ft.FT_Done_FreeType(library);

        if (font_bytes.len > std.math.maxInt(c_long)) return error.InvalidArguments;
        var face: ft.FT_Face = null;
        if (ft.FT_New_Memory_Face(library, @ptrCast(font_bytes.ptr), @intCast(font_bytes.len), 0, &face) != 0) return error.FreeTypeFailed;
        errdefer _ = ft.FT_Done_Face(face);
        if (options.mode == .raster or options.mode == .raster_reuse) {
            if (ft.FT_Set_Pixel_Sizes(face, 0, @intFromFloat(@round(options.font_size))) != 0) return error.FreeTypeFailed;
        }

        const coords = options.normalizedVariationCoords();
        var fixed_coords_buf: [32]ft.FT_Fixed = undefined;
        if (coords.len > fixed_coords_buf.len) return error.InvalidArguments;
        if (coords.len != 0) {
            for (coords, fixed_coords_buf[0..coords.len]) |coord, *fixed| {
                fixed.* = @intFromFloat(@round(coord * 65536.0));
            }
            if (ft.FT_Set_Var_Blend_Coordinates(face, @intCast(coords.len), &fixed_coords_buf) != 0) return error.FreeTypeFailed;
        }

        return .{ .library = library, .face = face };
    }

    fn deinit(self: FreeTypeFace) void {
        _ = ft.FT_Done_Face(self.face);
        _ = ft.FT_Done_FreeType(self.library);
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !report.Result {
    if (options.mode == .outline_session or options.mode == .raster_prepare or options.mode == .raster_prepared) return error.InvalidArguments;
    const ft_face = try FreeTypeFace.init(font_bytes, options);
    defer ft_face.deinit();

    const glyph_id = resolveGlyphId(ft_face.face, options);
    if (options.dirty_rect) {
        if (options.mode != .raster_reuse) return error.InvalidArguments;
        return runDirty(io, allocator, ft_face.face, glyph_id, options);
    }
    var empty_target_pixels: [0]u8 = .{};
    const target_pixels: []u8 = if (options.mode == .raster or
        options.mode == .raster_reuse)
        try allocator.alloc(u8, @as(usize, options.target_size) * options.target_size)
    else
        empty_target_pixels[0..];
    defer if (options.mode == .raster or options.mode == .raster_reuse)
        allocator.free(target_pixels);

    if (options.warmup != 0) {
        var warmup_checksum: u64 = 0;
        try runIterations(ft_face.face, glyph_id, options, options.warmup, target_pixels, &warmup_checksum);
    }

    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runIterations(ft_face.face, glyph_id, options, options.iterations, target_pixels, &sample_checksum);
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

fn runDirty(io: std.Io, allocator: std.mem.Allocator, face: ft.FT_Face, glyph_id: ft.FT_UInt, options: options_mod.Options) !report.Result {
    const pixels = try allocator.alloc(u8, @as(usize, options.target_size) * options.target_size);
    defer allocator.free(pixels);
    @memset(pixels, 0);
    const flags: ft.FT_Int32 = ft.FT_LOAD_RENDER | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP;
    if (ft.FT_Load_Glyph(face, glyph_id, flags) != 0) return error.FreeTypeFailed;
    blitBitmap(face.*.glyph, options, pixels);
    const bounds = dirty_rect.nonZeroBounds(pixels, options.target_size);
    const dirty_pixels = if (bounds) |value| value.pixelCount() else 0;
    if (options.warmup != 0) {
        var ignored: u64 = 0;
        try runDirtyIterations(face, glyph_id, options, options.warmup, pixels, bounds, &ignored);
    }
    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    for (0..options.samples) |sample_index| {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runDirtyIterations(face, glyph_id, options, options.iterations, pixels, bounds, &sample_checksum);
        const duration = std.Io.Clock.now(.awake, io).nanoseconds - start;
        elapsed += duration;
        checksum = updateChecksum(checksum, sample_checksum);
        try samples.append(allocator, .{ .index = sample_index, .elapsed_ns = duration, .iterations = options.iterations, .checksum = sample_checksum });
    }
    return .{ .elapsed_ns = elapsed, .checksum = checksum, .samples = try samples.toOwnedSlice(allocator), .dirty_pixels = dirty_pixels };
}

fn runDirtyIterations(face: ft.FT_Face, glyph_id: ft.FT_UInt, options: options_mod.Options, iterations: usize, pixels: []u8, bounds: ?dirty_rect.Bounds, checksum: *u64) !void {
    const flags: ft.FT_Int32 = ft.FT_LOAD_RENDER | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        dirty_rect.clear(pixels, options.target_size, bounds);
        if (ft.FT_Load_Glyph(face, glyph_id, flags) != 0) return error.FreeTypeFailed;
        blitBitmap(face.*.glyph, options, pixels);
        checksum.* = updateChecksum(checksum.*, dirty_rect.checksum(pixels, options.target_size, bounds));
    }
}

fn blitBitmap(slot: ft.FT_GlyphSlot, options: options_mod.Options, target_pixels: []u8) void {
    if (slot == null) return;
    const glyph = slot.*;
    const bitmap = glyph.bitmap;
    const width: usize = @intCast(bitmap.width);
    const rows: usize = @intCast(bitmap.rows);
    const pitch_abs: usize = @intCast(if (bitmap.pitch < 0) -bitmap.pitch else bitmap.pitch);
    if (bitmap.buffer == null or width == 0 or rows == 0 or pitch_abs == 0) return;
    const target_size: i32 = @intCast(options.target_size);
    const baseline_y: i32 = @intFromFloat(@round(options.font_size));
    const origin_y: i32 = baseline_y - glyph.bitmap_top;
    const buffer: [*]const u8 = @ptrCast(bitmap.buffer);
    for (0..rows) |row| {
        const y = origin_y + @as(i32, @intCast(row));
        if (y < 0 or y >= target_size) continue;
        const src = if (bitmap.pitch >= 0) row * pitch_abs else (rows - 1 - row) * pitch_abs;
        for (0..@min(width, pitch_abs)) |col| {
            const x = glyph.bitmap_left + @as(i32, @intCast(col));
            if (x < 0 or x >= target_size) continue;
            const index = @as(usize, @intCast(y)) * options.target_size + @as(usize, @intCast(x));
            target_pixels[index] = @max(target_pixels[index], buffer[src + col]);
        }
    }
}

fn resolveGlyphId(face: ft.FT_Face, options: options_mod.Options) ft.FT_UInt {
    if (options.glyph_id) |glyph_id| return glyph_id;
    if (options.font_path == null and options.builtin_font == .gvar_compound) return 2;
    return ft.FT_Get_Char_Index(face, options.codepoint);
}

fn runIterations(face: ft.FT_Face, glyph_id: ft.FT_UInt, options: options_mod.Options, iterations: usize, target_pixels: []u8, checksum: *u64) !void {
    const load_flags: ft.FT_Int32 = switch (options.mode) {
        .charmap, .metrics, .bounds, .global_metrics, .family_name, .glyph_name, .attributes, .variations, .palettes, .strikes, .color_glyph, .bitmap => unreachable,
        .outline => ft.FT_LOAD_NO_SCALE | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP,
        .outline_session => unreachable,
        .raster, .raster_reuse => ft.FT_LOAD_RENDER | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP,
        .raster_prepare, .raster_prepared => unreachable,
    };
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        if (ft.FT_Load_Glyph(face, glyph_id, load_flags) != 0) return error.FreeTypeFailed;
        checksum.* = updateChecksum(checksum.*, switch (options.mode) {
            .charmap, .metrics, .bounds, .global_metrics, .family_name, .glyph_name, .attributes, .variations, .palettes, .strikes, .color_glyph, .bitmap => unreachable,
            .outline => outlineChecksum(face.*.glyph),
            .raster, .raster_reuse => rasterTargetChecksum(face.*.glyph, options, target_pixels),
            .outline_session, .raster_prepare, .raster_prepared => unreachable,
        });
    }
}

fn outlineChecksum(slot: ft.FT_GlyphSlot) u64 {
    var hasher = std.hash.Wyhash.init(0);
    if (slot == null) return hasher.final();
    const glyph = slot.*;
    hasher.update(std.mem.asBytes(&glyph.metrics.horiAdvance));
    hasher.update(std.mem.asBytes(&glyph.metrics.horiBearingX));
    if (glyph.format != ft.FT_GLYPH_FORMAT_OUTLINE) return hasher.final();
    const outline = glyph.outline;
    hasher.update(std.mem.asBytes(&outline.n_contours));
    hasher.update(std.mem.asBytes(&outline.n_points));
    const point_count: usize = @intCast(@max(outline.n_points, 0));
    const contour_count: usize = @intCast(@max(outline.n_contours, 0));
    if (point_count != 0) {
        if (outline.points == null or outline.tags == null) return hasher.final();
        const points: [*]const ft.FT_Vector = @ptrCast(outline.points);
        const tags: [*]const u8 = @ptrCast(outline.tags);
        for (points[0..point_count]) |point| {
            hasher.update(std.mem.asBytes(&point.x));
            hasher.update(std.mem.asBytes(&point.y));
        }
        for (tags[0..point_count]) |tag| hasher.update(std.mem.asBytes(&tag));
    }
    if (contour_count != 0) {
        if (outline.contours == null) return hasher.final();
        const contours: [*]const c_short = @ptrCast(outline.contours);
        for (contours[0..contour_count]) |contour| hasher.update(std.mem.asBytes(&contour));
    }
    return hasher.final();
}

fn rasterTargetChecksum(slot: ft.FT_GlyphSlot, options: options_mod.Options, target_pixels: []u8) u64 {
    @memset(target_pixels, 0);
    blitBitmap(slot, options, target_pixels);
    return std.hash.Wyhash.hash(0, target_pixels);
}

fn updateChecksum(seed: u64, value: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&value));
    return hasher.final();
}
