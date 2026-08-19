//! Modern OpenType embedded bitmap table surface.
//!
//! `Font` owns SFNT directory/checksum policy. This module owns strike
//! selection plus the sbix and CBLC/CBDT table grammars.

const std = @import("std");

pub const cblc = @import("cblc/root.zig");
pub const png = @import("png.zig");
pub const sbix = @import("sbix.zig");
pub const types = @import("types.zig");

pub const Error = types.Error;
pub const Table = types.Table;
pub const GlyphPng = types.GlyphPng;
pub const GlyphMask = types.GlyphMask;
pub const GlyphInfo = types.GlyphInfo;
pub const StrikeSource = types.StrikeSource;
pub const StrikeInfo = types.StrikeInfo;

pub fn validateRequestSize(size_px: f32) Error!void {
    // Selection compares a CSS/device pixel request against integer strike
    // ppem. NaN, infinity, and non-positive values have no ordered meaning.
    if (!std.math.isFinite(size_px) or size_px <= 0) {
        return error.InvalidBitmapSize;
    }
}

pub fn ppemIsPreferred(
    candidate: u16,
    current: u16,
    size_px: f32,
) bool {
    return types.ppemIsPreferred(candidate, current, size_px);
}

pub fn recordBestPpem(
    ppem: u16,
    size_px: f32,
    best_ppem: *?u16,
) void {
    types.recordBestPpem(ppem, size_px, best_ppem);
}

pub fn recordBestGlyphInfo(
    candidate: GlyphInfo,
    size_px: f32,
    best: *?GlyphInfo,
) void {
    types.recordBestGlyphInfo(candidate, size_px, best);
}

test "strike preference avoids upscaling when a larger strike exists" {
    try std.testing.expect(ppemIsPreferred(64, 16, 17));
    try std.testing.expect(!ppemIsPreferred(16, 64, 17));
    try std.testing.expect(ppemIsPreferred(64, 128, 17));
    try std.testing.expect(ppemIsPreferred(128, 64, 200));
    try std.testing.expect(!ppemIsPreferred(16, 64, 200));
    try std.testing.expect(!ppemIsPreferred(64, 64, 64));

    var best: ?u16 = null;
    for ([_]u16{ 128, 16, 64 }) |ppem| recordBestPpem(ppem, 17, &best);
    try std.testing.expectEqual(@as(?u16, 64), best);

    best = null;
    for ([_]u16{ 16, 128, 64 }) |ppem| recordBestPpem(ppem, 200, &best);
    try std.testing.expectEqual(@as(?u16, 128), best);

    // Candidate enumeration is glyph-specific. If the nearest nominal strike
    // has no image for this glyph, the larger image still wins over upscaling.
    best = null;
    for ([_]u16{ 16, 128 }) |ppem| recordBestPpem(ppem, 17, &best);
    try std.testing.expectEqual(@as(?u16, 128), best);
}
