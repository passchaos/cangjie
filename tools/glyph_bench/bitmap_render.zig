//! Canonical embedded-bitmap output shared by Cangjie and FreeType benches.
//!
//! Both engines select a strike from the requested size, decode one glyph,
//! and hash the same native-resolution representation: either one coverage
//! byte per pixel or premultiplied BGRA8. Row padding is excluded, and sbix's
//! bottom-edge offset is normalized to FreeType's top-bearing convention.

const std = @import("std");
const cangjie = @import("cangjie");
const ft = @import("freetype");
const imx = @import("imx");

const max_bitmap_dimension = 16 * 1024;
const max_bitmap_decode_bytes = 256 * 1024 * 1024;

const PixelKind = enum(u8) { mask8 = 1, premultiplied_bgra8 = 2 };

pub fn cangjieChecksum(
    allocator: std.mem.Allocator,
    face: *const cangjie.font.Face,
    glyph_id: cangjie.font.GlyphId,
    size_px: f32,
) !u64 {
    const color = face.color();
    if (try color.bitmapData(glyph_id, size_px)) |data| {
        return switch (data) {
            .png => |bitmap| pngChecksum(allocator, bitmap),
            .bgra => |bitmap| hashBgra(
                bitmap.ppem,
                bitmap.width,
                bitmap.height,
                bitmap.origin_offset_x,
                topBearing(
                    bitmap.source,
                    bitmap.height,
                    bitmap.origin_offset_y,
                ),
                bitmap.data,
            ),
            .mask => |bitmap| maskChecksum(allocator, bitmap),
        };
    }

    // Compound formats 8/9 need allocation and recursive flattening, while
    // ordinary glyphs stay on the borrowed-data path above. This ordering
    // avoids paying for two complete table lookups on the common case.
    if (try color.compoundBitmapAlloc(allocator, glyph_id, size_px)) |owned_value| {
        var owned = owned_value;
        defer owned.deinit();
        return switch (owned.kind) {
            .mask8 => hashMask(
                owned.ppem,
                owned.width,
                owned.height,
                owned.origin_offset_x,
                owned.origin_offset_y,
                owned.data,
            ),
            .premultiplied_bgra8 => hashBgra(
                owned.ppem,
                owned.width,
                owned.height,
                owned.origin_offset_x,
                owned.origin_offset_y,
                owned.data,
            ),
        };
    }
    return error.MissingBitmapGlyph;
}

fn pngChecksum(
    allocator: std.mem.Allocator,
    bitmap: cangjie.font.metadata.color.BitmapPng,
) !u64 {
    // Face.parse has already validated all embedded PNG chunks. Skip only the
    // duplicate CRC pass; imx still checks the complete decode grammar and
    // zlib integrity while producing the pixels consumed by this benchmark.
    var decoder = imx.PngDecoder.initWithOptions(
        bitmap.data,
        .{ .ignore_crc = true },
    ) catch return error.BadSfnt;
    var decoded = decoder.decodeNormalizedToColor8WithAlpha(
        allocator,
        .{
            .max_width = max_bitmap_dimension,
            .max_height = max_bitmap_dimension,
            .max_bytes = max_bitmap_decode_bytes,
        },
    ) catch |err| return switch (err) {
        error.AllocationFailed => error.OutOfMemory,
        error.ImageTooLarge => error.BitmapGlyphTooLarge,
        else => error.BadSfnt,
    };
    defer decoded.deinit();
    if (decoded.width() != bitmap.width or decoded.height() != bitmap.height) {
        return error.BadSfnt;
    }

    var converted: ?imx.buffer.RgbaImage = null;
    defer if (converted) |*image| image.deinit();
    const rgba = if (decoded.colorType() == .rgba8)
        decoded.bytesMut()
    else converted_bytes: {
        converted = decoded.toRgba8(allocator) catch |err| return switch (err) {
            error.AllocationFailed => error.OutOfMemory,
            else => error.BadSfnt,
        };
        break :converted_bytes converted.?.bytesMut();
    };

    const pixel_count = try checkedPixelCount(bitmap.width, bitmap.height);
    if (rgba.len != pixel_count * 4) return error.BadSfnt;
    var hasher = canonicalHasher(
        .premultiplied_bgra8,
        bitmap.ppem,
        bitmap.width,
        bitmap.height,
        bitmap.origin_offset_x,
        topBearing(bitmap.source, bitmap.height, bitmap.origin_offset_y),
    );
    canonicalizeRgbaToPremultipliedBgra(rgba);
    // A single contiguous update avoids one generic Wyhash dispatch and copy
    // per pixel. The decoded image is private to this call, so canonicalizing
    // its channel order in place does not affect any observable API value.
    hasher.update(rgba);
    return hasher.final();
}

fn maskChecksum(
    allocator: std.mem.Allocator,
    bitmap: cangjie.font.metadata.color.BitmapMask,
) !u64 {
    const pixels = try bitmap.decodeAlloc(allocator);
    defer allocator.free(pixels);
    return hashMask(
        bitmap.ppem,
        bitmap.width,
        bitmap.height,
        bitmap.origin_offset_x,
        bitmap.origin_offset_y,
        pixels,
    );
}

fn topBearing(
    source: cangjie.font.metadata.color.BitmapStrikeSource,
    height: u32,
    origin_offset_y: i16,
) i32 {
    return switch (source) {
        .sbix => @as(i32, @intCast(height)) + origin_offset_y,
        .cblc_cbdt, .eblc_ebdt => origin_offset_y,
    };
}

pub fn selectFreeTypeStrike(face: ft.FT_Face, size_px: f32) !u16 {
    if (face == null or face.*.num_fixed_sizes <= 0 or
        face.*.available_sizes == null)
    {
        return error.MissingBitmapStrike;
    }
    var best_index: usize = 0;
    var best_ppem = try fixedSizePpem(face.*.available_sizes[0]);
    const count: usize = @intCast(face.*.num_fixed_sizes);
    for (face.*.available_sizes[1..count], 1..) |candidate, index| {
        const candidate_ppem = try fixedSizePpem(candidate);
        if (ppemIsPreferred(candidate_ppem, best_ppem, size_px)) {
            best_index = index;
            best_ppem = candidate_ppem;
        }
    }
    if (ft.FT_Select_Size(face, @intCast(best_index)) != 0) {
        return error.FreeTypeFailed;
    }
    return best_ppem;
}

fn fixedSizePpem(size: ft.FT_Bitmap_Size) !u16 {
    if (size.y_ppem <= 0) return error.InvalidBitmapSize;
    // FreeType publishes the authored ppem as 26.6 even for bitmap strikes.
    // OpenType and sbix ppem values are integral, but round defensively.
    const rounded = @divFloor(size.y_ppem + 32, 64);
    if (rounded <= 0 or rounded > std.math.maxInt(u16)) {
        return error.InvalidBitmapSize;
    }
    return @intCast(rounded);
}

fn ppemIsPreferred(candidate: u16, current: u16, size_px: f32) bool {
    const candidate_size: f32 = @floatFromInt(candidate);
    const current_size: f32 = @floatFromInt(current);
    const candidate_is_large_enough = candidate_size >= size_px;
    const current_is_large_enough = current_size >= size_px;
    if (candidate_is_large_enough != current_is_large_enough) {
        return candidate_is_large_enough;
    }
    return if (candidate_is_large_enough)
        candidate < current
    else
        candidate > current;
}

pub fn freeTypeChecksum(
    face: ft.FT_Face,
    glyph_id: ft.FT_UInt,
    ppem: u16,
) !u64 {
    const flags: ft.FT_Int32 =
        ft.FT_LOAD_RENDER | ft.FT_LOAD_NO_HINTING | ft.FT_LOAD_COLOR;
    if (ft.FT_Load_Glyph(face, glyph_id, flags) != 0) {
        return error.FreeTypeFailed;
    }
    const slot = face.*.glyph;
    if (slot == null or slot.*.format != ft.FT_GLYPH_FORMAT_BITMAP) {
        return error.MissingBitmapGlyph;
    }
    const bitmap = slot.*.bitmap;
    const width: u32 = bitmap.width;
    const height: u32 = bitmap.rows;
    const pitch_abs: usize = @intCast(
        if (bitmap.pitch < 0) -bitmap.pitch else bitmap.pitch,
    );
    if (width != 0 and height != 0 and
        (bitmap.buffer == null or pitch_abs == 0))
    {
        return error.FreeTypeFailed;
    }

    const kind: PixelKind = switch (bitmap.pixel_mode) {
        ft.FT_PIXEL_MODE_MONO, ft.FT_PIXEL_MODE_GRAY, ft.FT_PIXEL_MODE_GRAY2, ft.FT_PIXEL_MODE_GRAY4 => .mask8,
        ft.FT_PIXEL_MODE_BGRA => .premultiplied_bgra8,
        else => return error.UnsupportedBitmapPixelMode,
    };
    var hasher = canonicalHasher(
        kind,
        ppem,
        width,
        height,
        freeTypePixelMetric(slot.*.metrics.horiBearingX),
        freeTypePixelMetric(slot.*.metrics.horiBearingY),
    );
    if (width == 0 or height == 0) return hasher.final();

    const buffer: [*]const u8 = @ptrCast(bitmap.buffer);
    for (0..height) |row| {
        const source_row = if (bitmap.pitch >= 0)
            @as(usize, row) * pitch_abs
        else
            (@as(usize, height) - 1 - row) * pitch_abs;
        switch (kind) {
            .premultiplied_bgra8 => {
                const byte_count = try std.math.mul(usize, width, 4);
                if (pitch_abs < byte_count) return error.FreeTypeFailed;
                hasher.update(buffer[source_row..][0..byte_count]);
            },
            .mask8 => {
                for (0..width) |column| {
                    const coverage = try freeTypeCoverage(
                        bitmap,
                        buffer[source_row..],
                        column,
                    );
                    hasher.update(&.{coverage});
                }
            },
        }
    }
    return hasher.final();
}

fn freeTypePixelMetric(value: ft.FT_Pos) i32 {
    // Bitmap slot metrics are 26.6 values. FreeType's integer bitmap_left/top
    // apply pixel-grid rounding, which loses authored fractional bearings and
    // disagrees with the source-table values Cangjie exposes. The exact 26.6
    // division recovers integer OpenType bitmap and sbix metrics.
    return @intCast(@divTrunc(value, 64));
}

fn freeTypeCoverage(
    bitmap: ft.FT_Bitmap,
    row: [*]const u8,
    column: usize,
) !u8 {
    return switch (bitmap.pixel_mode) {
        ft.FT_PIXEL_MODE_MONO => if ((row[column / 8] &
            (@as(u8, 0x80) >> @intCast(column % 8))) != 0) 255 else 0,
        ft.FT_PIXEL_MODE_GRAY => blk: {
            if (bitmap.num_grays <= 1) return error.FreeTypeFailed;
            const maximum: u32 = bitmap.num_grays - 1;
            break :blk @intCast((@as(u32, row[column]) * 255) / maximum);
        },
        ft.FT_PIXEL_MODE_GRAY2 => blk: {
            const shift: u3 = @intCast(6 - (column % 4) * 2);
            break :blk ((row[column / 4] >> shift) & 0x03) * 85;
        },
        ft.FT_PIXEL_MODE_GRAY4 => blk: {
            const shift: u3 = @intCast(4 - (column % 2) * 4);
            break :blk ((row[column / 2] >> shift) & 0x0f) * 17;
        },
        else => error.UnsupportedBitmapPixelMode,
    };
}

fn hashMask(
    ppem: u16,
    width: u32,
    height: u32,
    left: i32,
    top: i32,
    pixels: []const u8,
) !u64 {
    const pixel_count = try checkedPixelCount(width, height);
    if (pixels.len != pixel_count) return error.BadSfnt;
    var hasher = canonicalHasher(
        .mask8,
        ppem,
        width,
        height,
        left,
        top,
    );
    hasher.update(pixels);
    return hasher.final();
}

fn hashBgra(
    ppem: u16,
    width: u32,
    height: u32,
    left: i32,
    top: i32,
    pixels: []const u8,
) !u64 {
    const pixel_count = try checkedPixelCount(width, height);
    const byte_count = try std.math.mul(usize, pixel_count, 4);
    if (pixels.len != byte_count) return error.BadSfnt;
    var hasher = canonicalHasher(
        .premultiplied_bgra8,
        ppem,
        width,
        height,
        left,
        top,
    );
    hasher.update(pixels);
    return hasher.final();
}

fn checkedPixelCount(width: u32, height: u32) !usize {
    return std.math.mul(usize, width, height) catch error.BitmapGlyphTooLarge;
}

fn canonicalHasher(
    kind: PixelKind,
    ppem: u16,
    width: u32,
    height: u32,
    left: i32,
    top: i32,
) std.hash.Wyhash {
    var hasher = std.hash.Wyhash.init(0);
    const kind_value: u8 = @intFromEnum(kind);
    hasher.update(std.mem.asBytes(&kind_value));
    hasher.update(std.mem.asBytes(&ppem));
    hasher.update(std.mem.asBytes(&width));
    hasher.update(std.mem.asBytes(&height));
    hasher.update(std.mem.asBytes(&left));
    hasher.update(std.mem.asBytes(&top));
    return hasher;
}

fn canonicalizeRgbaToPremultipliedBgra(rgba: []u8) void {
    std.debug.assert(rgba.len % 4 == 0);
    for (0..rgba.len / 4) |index| {
        const pixel = rgba[index * 4 ..][0..4];
        const alpha = pixel[3];
        const red = pixel[0];
        pixel[0] = multiplyAlpha(alpha, pixel[2]);
        pixel[1] = multiplyAlpha(alpha, pixel[1]);
        pixel[2] = multiplyAlpha(alpha, red);
    }
}

fn multiplyAlpha(alpha: u8, color: u8) u8 {
    if (alpha == 0) return 0;
    if (alpha == 255) return color;
    const product = @as(u32, alpha) * color + 0x80;
    return @intCast((product + (product >> 8)) >> 8);
}

test "FreeType-compatible alpha multiplication rounds exactly" {
    try std.testing.expectEqual(@as(u8, 0), multiplyAlpha(0, 255));
    try std.testing.expectEqual(@as(u8, 128), multiplyAlpha(128, 255));
    try std.testing.expectEqual(@as(u8, 64), multiplyAlpha(128, 128));
    try std.testing.expectEqual(@as(u8, 255), multiplyAlpha(255, 255));
}

test "RGBA canonicalization produces FreeType premultiplied BGRA bytes" {
    var pixels = [_]u8{
        255, 0,   7,   128,
        30,  20,  10,  255,
        99,  127, 201, 0,
    };
    canonicalizeRgbaToPremultipliedBgra(&pixels);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 4, 0, 128, 128, 10, 20, 30, 255, 0, 0, 0, 0 },
        &pixels,
    );
}
