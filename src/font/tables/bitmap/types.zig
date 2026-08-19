//! Shared records for modern OpenType embedded bitmap tables.

const std = @import("std");

const glyph = @import("../../../glyph.zig");

pub const Error = error{
    BadSfnt,
    InvalidBitmapSize,
} || std.mem.Allocator.Error || error{EndOfStream};

/// Minimal table view used by bitmap parsers.
///
/// Keeping checksum and directory ownership outside this module lets `Font`
/// enforce its borrowed-byte policy without coupling table grammars back to the
/// complete SFNT face implementation.
pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const StrikeSource = enum {
    sbix,
    cblc_cbdt,
    eblc_ebdt,
};

pub const GlyphPng = struct {
    /// Table family determines whether the vertical offset is a top bearing
    /// (CBDT/EBDT) or a bottom-edge offset (sbix).
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    data: []const u8,
};

/// Borrowed uncompressed 32-bit EBDT/CBDT color pixels.
///
/// OpenType stores these samples in premultiplied BGRA order in the sRGB
/// color space. Keeping that byte contract explicit prevents callers from
/// accidentally applying alpha a second time or treating the first channel as
/// red. Only image formats with byte-aligned rows expose this record, matching
/// Skrifa's high-level bitmap contract.
pub const GlyphBgra = struct {
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    data: []const u8,
};

pub const CompoundComponent = struct {
    glyph_id: glyph.GlyphId,
    x_offset: i8,
    y_offset: i8,
};

/// Allocator-owned result of flattening an EBDT/CBDT compound glyph.
///
/// The pixel payload is either one byte of coverage or four bytes of
/// premultiplied BGRA per pixel. Parent image metrics define the canvas and
/// placement; component metrics affect only their recursive source images.
pub const OwnedGlyphData = struct {
    allocator: std.mem.Allocator,
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    kind: Kind,
    data: []u8,

    pub const Kind = enum { mask8, premultiplied_bgra8 };

    pub fn deinit(self: *OwnedGlyphData) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

/// Borrowed single-channel EBDT/CBDT bitmap data.
///
/// Pixels are stored most-significant-bit first. `row_byte_aligned`
/// distinguishes image formats 1/6, whose rows start on byte boundaries,
/// from formats 2/5/7, whose complete image is tightly bit-packed.
pub const GlyphMask = struct {
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    bit_depth: u8,
    row_byte_aligned: bool,
    data: []const u8,

    /// Decode coverage to one byte per pixel, scaling the authored sample
    /// range to 0...255 exactly as Skrifa's `MaskData` contract does.
    pub fn decodeToSlice(self: GlyphMask, output: []u8) Error!void {
        const width: usize = self.width;
        const height: usize = self.height;
        const pixel_count = std.math.mul(usize, width, height) catch
            return error.BadSfnt;
        if (output.len < pixel_count) return error.BadSfnt;
        if (pixel_count == 0) return;
        const bits: usize = switch (self.bit_depth) {
            1, 2, 4, 8 => self.bit_depth,
            else => return error.BadSfnt,
        };
        const row_bits = std.math.mul(usize, width, bits) catch
            return error.BadSfnt;
        const row_bytes = (row_bits + 7) / 8;
        const required = if (self.row_byte_aligned)
            std.math.mul(usize, row_bytes, height) catch return error.BadSfnt
        else
            ((std.math.mul(usize, pixel_count, bits) catch
                return error.BadSfnt) + 7) / 8;
        if (self.data.len < required) return error.BadSfnt;

        const maximum: u16 = (@as(u16, 1) << @intCast(bits)) - 1;
        for (0..height) |y| {
            for (0..width) |x| {
                const bit_offset = if (self.row_byte_aligned)
                    y * row_bytes * 8 + x * bits
                else
                    (y * width + x) * bits;
                const byte = self.data[bit_offset / 8];
                const shift: u3 = @intCast(8 - bits - bit_offset % 8);
                const sample = (byte >> shift) & @as(u8, @intCast(maximum));
                output[y * width + x] = @intCast(
                    (@as(u16, sample) * 255) / maximum,
                );
            }
        }
    }

    pub fn decodeAlloc(
        self: GlyphMask,
        allocator: std.mem.Allocator,
    ) Error![]u8 {
        const pixel_count = std.math.mul(
            usize,
            self.width,
            self.height,
        ) catch return error.BadSfnt;
        const output = try allocator.alloc(u8, pixel_count);
        errdefer allocator.free(output);
        try self.decodeToSlice(output);
        return output;
    }
};

/// One high-level glyph selected across all strikes of a bitmap table family.
///
/// Keeping source kind and strike selection in one value is important when a
/// font mixes PNG, BGRA, and mask strikes: selecting each kind independently
/// and then imposing a renderer precedence could ignore a closer strike.
pub const GlyphData = union(enum) {
    png: GlyphPng,
    bgra: GlyphBgra,
    mask: GlyphMask,

    pub fn ppem(self: GlyphData) u16 {
        return switch (self) {
            inline else => |glyph_data| glyph_data.ppem,
        };
    }
};

test "bitmap masks decode byte-aligned and bit-aligned depths" {
    const Case = struct {
        width: u32,
        height: u32,
        depth: u8,
        aligned: bool,
        data: []const u8,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{ .width = 4, .height = 2, .depth = 1, .aligned = true, .data = &.{ 0xa0, 0x50 }, .expected = &.{ 255, 0, 255, 0, 0, 255, 0, 255 } },
        .{ .width = 4, .height = 1, .depth = 2, .aligned = true, .data = &.{0xe4}, .expected = &.{ 255, 170, 85, 0 } },
        .{ .width = 3, .height = 2, .depth = 4, .aligned = true, .data = &.{ 0xf8, 0x40, 0x05, 0xa0 }, .expected = &.{ 255, 136, 68, 0, 85, 170 } },
        .{ .width = 3, .height = 3, .depth = 1, .aligned = false, .data = &.{ 0xab, 0x00 }, .expected = &.{ 255, 0, 255, 0, 255, 0, 255, 255, 0 } },
        .{ .width = 5, .height = 2, .depth = 2, .aligned = false, .data = &.{ 0xe4, 0xc6, 0xc0 }, .expected = &.{ 255, 170, 85, 0, 255, 0, 85, 170, 255, 0 } },
        .{ .width = 3, .height = 2, .depth = 4, .aligned = false, .data = &.{ 0xf0, 0x84, 0xa5 }, .expected = &.{ 255, 0, 136, 68, 170, 85 } },
        .{ .width = 3, .height = 2, .depth = 8, .aligned = true, .data = &.{ 10, 20, 30, 40, 50, 60 }, .expected = &.{ 10, 20, 30, 40, 50, 60 } },
    };
    for (cases) |case| {
        const mask = GlyphMask{
            .source = .eblc_ebdt,
            .ppem = 12,
            .ppi = 0,
            .origin_offset_x = 0,
            .origin_offset_y = 0,
            .width = case.width,
            .height = case.height,
            .bit_depth = case.depth,
            .row_byte_aligned = case.aligned,
            .data = case.data,
        };
        var output: [10]u8 = undefined;
        try mask.decodeToSlice(&output);
        try std.testing.expectEqualSlices(
            u8,
            case.expected,
            output[0..case.expected.len],
        );
    }

    const truncated = GlyphMask{
        .source = .eblc_ebdt,
        .ppem = 12,
        .ppi = 0,
        .origin_offset_x = 0,
        .origin_offset_y = 0,
        .width = 8,
        .height = 2,
        .bit_depth = 1,
        .row_byte_aligned = true,
        .data = &.{0xff},
    };
    var output: [16]u8 = undefined;
    try std.testing.expectError(error.BadSfnt, truncated.decodeToSlice(&output));
}

pub const GlyphInfo = struct {
    source: StrikeSource,
    glyph_id: glyph.GlyphId,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    image_format: ?u16 = null,
    bit_depth: ?u8 = null,
    row_byte_aligned: bool = false,
    advance: ?u16 = null,
    data_offset: usize,
    data_length: usize,
    is_png: bool,
};

pub const StrikeInfo = struct {
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
    bit_depth: u8 = 0,
    start_glyph: glyph.GlyphId = 0,
    end_glyph: glyph.GlyphId = 0,
};

/// Metrics shared by CBLC index records and CBDT image payloads.
pub const Metrics = struct {
    height: u8,
    width: u8,
    bearing_x: i8,
    bearing_y: i8,
    advance: u8,
};

pub fn readSmallMetrics(
    data: []const u8,
    offset: usize,
) Error!Metrics {
    if (offset + 5 > data.len) return error.BadSfnt;
    return .{
        .height = data[offset],
        .width = data[offset + 1],
        .bearing_x = @bitCast(data[offset + 2]),
        .bearing_y = @bitCast(data[offset + 3]),
        .advance = data[offset + 4],
    };
}

pub fn readBigMetrics(
    data: []const u8,
    offset: usize,
) Error!Metrics {
    if (offset + 8 > data.len) return error.BadSfnt;
    return .{
        .height = data[offset],
        .width = data[offset + 1],
        .bearing_x = @bitCast(data[offset + 2]),
        .bearing_y = @bitCast(data[offset + 3]),
        .advance = data[offset + 4],
    };
}

pub fn ppemIsPreferred(
    candidate: u16,
    current: u16,
    size_px: f32,
) bool {
    const candidate_size: f32 = @floatFromInt(candidate);
    const current_size: f32 = @floatFromInt(current);
    const candidate_is_large_enough = candidate_size >= size_px;
    const current_is_large_enough = current_size >= size_px;

    // Prefer the smallest strike that avoids upscaling. If every strike is
    // smaller, use the largest one. This exact -> nearest larger -> largest
    // smaller policy matches modern Skrifa and HarfBuzz.
    if (candidate_is_large_enough != current_is_large_enough) {
        return candidate_is_large_enough;
    }
    return if (candidate_is_large_enough)
        candidate < current
    else
        candidate > current;
}

pub fn recordBestPpem(
    ppem: u16,
    size_px: f32,
    best_ppem: *?u16,
) void {
    if (best_ppem.* == null or
        ppemIsPreferred(ppem, best_ppem.*.?, size_px))
    {
        best_ppem.* = ppem;
    }
}

pub fn recordBestGlyphInfo(
    candidate: GlyphInfo,
    size_px: f32,
    best: *?GlyphInfo,
) void {
    if (best.* == null or
        ppemIsPreferred(candidate.ppem, best.*.?.ppem, size_px))
    {
        best.* = candidate;
    }
}
