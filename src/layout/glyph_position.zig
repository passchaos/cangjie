//! Public positioned-glyph data shared by shaping, paragraph layout, and
//! rendering integrations.

const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;

/// Compact flags deliberately share one byte. Positioned glyphs are retained
/// in large paragraph arrays, so adding independent booleans would raise the
/// public record from 48 to 56 bytes solely because of trailing alignment.
pub const Flags = packed struct(u8) {
    /// An invisible U+00AD source atom materialized at a selected line break.
    /// UAX #9 X9 otherwise removes the original scalar from visual ordering.
    discretionary_hyphen: bool = false,
    /// Reusing this shaped run across the boundary at the glyph's `cluster`
    /// would change OpenType contextual substitution results.
    unsafe_to_break_before: bool = false,
    _reserved: u6 = 0,
};

/// One positioned glyph after cmap mapping, GSUB substitution, and GPOS/kern
/// adjustment. `cluster` is a byte offset into the original UTF-8 text, so
/// hit testing and selection can map glyph positions back to source text.
pub const GlyphPosition = struct {
    glyph_id: GlyphId,
    /// Optional synthetic glyph id used only for shaping-diagnostic parity
    /// knobs such as HarfBuzz's not-found variation-selector glyph. The real
    /// OpenType pipeline still uses `glyph_id` for GSUB, GPOS, metrics, and
    /// rendering.
    synthetic_glyph_id: ?u32 = null,
    codepoint: u21,
    cluster: usize,
    /// Number of UTF-8 bytes in the source span represented by this glyph.
    /// This is usually one scalar, but it can include skipped variation
    /// selectors or all components collapsed into a GSUB ligature. Keeping the
    /// extent next to the cluster start lets caret logic recover the trailing
    /// source byte offset even when there is no following glyph.
    source_byte_len: usize = 0,
    x_advance: f32,
    y_advance: f32 = 0,
    x_offset: f32 = 0,
    y_offset: f32 = 0,
    vertical: bool = false,
    flags: Flags = .{},

    pub fn outputGlyphId(self: GlyphPosition) u32 {
        return self.synthetic_glyph_id orelse self.glyph_id;
    }

    pub fn isDiscretionaryHyphen(self: GlyphPosition) bool {
        return self.flags.discretionary_hyphen;
    }

    pub fn isUnsafeToBreakBefore(self: GlyphPosition) bool {
        return self.flags.unsafe_to_break_before;
    }
};

test "positioned glyph flags preserve the compact public layout" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(GlyphPosition));
}
