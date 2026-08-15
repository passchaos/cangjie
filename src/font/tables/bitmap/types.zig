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
    data_offset: usize,
    data_length: usize,
    is_png: bool,
};

pub const StrikeInfo = struct {
    source: StrikeSource,
    ppem: u16,
    ppi: u16,
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
