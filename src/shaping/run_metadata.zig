//! Immutable post-GSUB run metadata shared by positioning lookups.
//!
//! GPOS passes lookup options through a deep, performance-sensitive call
//! graph. Keeping these correlated sidecars behind one borrowed object avoids
//! repeatedly copying several slices while making their shared glyph/source
//! indexing contract explicit.

const std = @import("std");

const cluster_safety = @import("cluster_safety.zig");
const ligature_provenance = @import("../ligature_provenance.zig");

pub const UnsafeGlyphs = struct {
    /// Glyph zero is the safe cluster minimum; bits 1...63 map directly to
    /// HarfBuzz's unsafe-to-break output flags for short shaping runs.
    inline_mask: u64 = 0,

    pub fn markRange(self: *UnsafeGlyphs, start: usize, end: usize) bool {
        if (start >= end or end > @bitSizeOf(u64)) return false;
        self.inline_mask |= rangeMask(start + 1, end);
        return true;
    }

    pub fn isUnsafeBefore(self: *const UnsafeGlyphs, glyph_index: usize) bool {
        if (glyph_index >= @bitSizeOf(u64)) return false;
        return (self.inline_mask &
            (@as(u64, 1) << @as(u6, @intCast(glyph_index)))) != 0;
    }

    fn rangeMask(start: usize, end: usize) u64 {
        if (start >= end) return 0;
        const below_end = if (end == @bitSizeOf(u64))
            std.math.maxInt(u64)
        else
            (@as(u64, 1) << @as(u6, @intCast(end))) - 1;
        const below_start = if (start == 0)
            0
        else
            (@as(u64, 1) << @as(u6, @intCast(start))) - 1;
        return below_end & ~below_start;
    }
};

pub const Positioning = struct {
    /// Source-order index for each post-GSUB glyph.
    glyph_source_indices: ?[]const usize = null,
    /// Original scalar array indexed by `glyph_source_indices`.
    source_codepoints: ?[]const u21 = null,
    /// Cumulative GSUB substitution state for default-ignorable matching.
    glyph_substituted: ?[]const bool = null,
    /// Compact ligature component provenance parallel to the glyph stream.
    ligature_components: ?*const ligature_provenance.Store = null,
    /// Mutable output recorder keyed by immutable UTF-8 byte boundaries.
    source_boundaries: ?*cluster_safety.SourceBoundaries = null,
};

test "inline unsafe glyph ranges exclude the safe cluster minimum" {
    var unsafe_glyphs = UnsafeGlyphs{};
    try std.testing.expect(unsafe_glyphs.markRange(0, 4));
    try std.testing.expect(!unsafe_glyphs.isUnsafeBefore(0));
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(1));
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(2));
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(3));
    try std.testing.expect(!unsafe_glyphs.isUnsafeBefore(4));
}

test "long positioning relationships request source-byte fallback" {
    var unsafe_glyphs = UnsafeGlyphs{};
    try std.testing.expect(!unsafe_glyphs.markRange(0, 65));
    try std.testing.expectEqual(@as(u64, 0), unsafe_glyphs.inline_mask);
}
