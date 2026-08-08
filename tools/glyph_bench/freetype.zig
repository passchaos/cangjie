const std = @import("std");
const ft = @import("freetype");

const options_mod = @import("options.zig");
const report = @import("report.zig");

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
        if (options.mode == .raster) {
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
    if (options.mode == .raster_reuse) return error.InvalidArguments;
    const ft_face = try FreeTypeFace.init(font_bytes, options);
    defer ft_face.deinit();

    const glyph_id = resolveGlyphId(ft_face.face, options);
    if (options.warmup != 0) {
        var warmup_checksum: u64 = 0;
        try runIterations(ft_face.face, glyph_id, options, options.warmup, &warmup_checksum);
    }

    var samples = std.ArrayList(report.Sample).empty;
    errdefer samples.deinit(allocator);
    var elapsed: i128 = 0;
    var checksum: u64 = 0;
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, io).nanoseconds;
        try runIterations(ft_face.face, glyph_id, options, options.iterations, &sample_checksum);
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

fn resolveGlyphId(face: ft.FT_Face, options: options_mod.Options) ft.FT_UInt {
    if (options.glyph_id) |glyph_id| return glyph_id;
    if (options.font_path == null and options.builtin_font == .gvar_compound) return 2;
    return ft.FT_Get_Char_Index(face, options.codepoint);
}

fn runIterations(face: ft.FT_Face, glyph_id: ft.FT_UInt, options: options_mod.Options, iterations: usize, checksum: *u64) !void {
    const load_flags: ft.FT_Int32 = switch (options.mode) {
        .outline => ft.FT_LOAD_NO_SCALE | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP,
        .raster => ft.FT_LOAD_RENDER | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_NO_BITMAP,
        .raster_reuse => unreachable,
    };
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        if (ft.FT_Load_Glyph(face, glyph_id, load_flags) != 0) return error.FreeTypeFailed;
        checksum.* = updateChecksum(checksum.*, switch (options.mode) {
            .outline => outlineChecksum(face.*.glyph),
            .raster => bitmapChecksum(face.*.glyph),
            .raster_reuse => unreachable,
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
    for (outline.points[0..point_count]) |point| {
        hasher.update(std.mem.asBytes(&point.x));
        hasher.update(std.mem.asBytes(&point.y));
    }
    for (outline.tags[0..point_count]) |tag| hasher.update(std.mem.asBytes(&tag));
    for (outline.contours[0..contour_count]) |contour| hasher.update(std.mem.asBytes(&contour));
    return hasher.final();
}

fn bitmapChecksum(slot: ft.FT_GlyphSlot) u64 {
    var hasher = std.hash.Wyhash.init(0);
    if (slot == null) return hasher.final();
    const glyph = slot.*;
    const bitmap = glyph.bitmap;
    hasher.update(std.mem.asBytes(&glyph.bitmap_left));
    hasher.update(std.mem.asBytes(&glyph.bitmap_top));
    hasher.update(std.mem.asBytes(&bitmap.width));
    hasher.update(std.mem.asBytes(&bitmap.rows));
    hasher.update(std.mem.asBytes(&bitmap.pitch));
    hasher.update(std.mem.asBytes(&bitmap.pixel_mode));
    const width: usize = @intCast(bitmap.width);
    const rows: usize = @intCast(bitmap.rows);
    const pitch_abs: usize = @intCast(if (bitmap.pitch < 0) -bitmap.pitch else bitmap.pitch);
    if (bitmap.buffer == null or width == 0 or rows == 0 or pitch_abs == 0) return hasher.final();
    const buffer: [*]const u8 = @ptrCast(bitmap.buffer);
    for (0..rows) |row| {
        const offset = if (bitmap.pitch >= 0) row * pitch_abs else (rows - 1 - row) * pitch_abs;
        hasher.update(buffer[offset..][0..@min(width, pitch_abs)]);
    }
    return hasher.final();
}

fn updateChecksum(seed: u64, value: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&value));
    return hasher.final();
}
