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
    /// Synthetic non-rendering atom for one U+FFFC inline object anchor.
    inline_object: bool = false,
    /// Synthetic visible hyphen inserted at an automatic word boundary.
    automatic_hyphen: bool = false,
    /// HarfBuzz-compatible proof that U+0640 may be inserted before this
    /// cluster without interrupting cursive shaping.
    safe_to_insert_tatweel: bool = false,
    /// Output created by line-local source-level U+0640 insertion.
    ///
    /// It is anchored at an original UTF-8 boundary and therefore owns no
    /// caller source bytes, even though it passed through the complete shaper.
    kashida: bool = false,
    /// Synthetic non-rendering paragraph tab marker.
    ///
    /// Its reflow-computed advance positions the next field, but the marker
    /// never participates in cmap, GSUB, GPOS, kerning, or glyph rendering.
    tab: bool = false,
    /// Horizontal whitespace normalized by paragraph collapse policy.
    ///
    /// The source atom remains addressable, but a tab with this bit behaves
    /// as an ordinary collapsed blank rather than consulting the tab ruler.
    collapsed_whitespace: bool = false,
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
    /// Pen advances in renderer user space. X grows right; positive Y grows
    /// down, matching vertical column progression.
    x_advance: f32,
    y_advance: f32 = 0,
    /// Offsets follow the OpenType/HarfBuzz shaping coordinate system. X grows
    /// right and positive Y moves the glyph up from its current baseline.
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

    pub fn isInlineObject(self: GlyphPosition) bool {
        return self.flags.inline_object;
    }

    pub fn isAutomaticHyphen(self: GlyphPosition) bool {
        return self.flags.automatic_hyphen;
    }

    pub fn isSafeToInsertTatweel(self: GlyphPosition) bool {
        return self.flags.safe_to_insert_tatweel;
    }

    pub fn isKashida(self: GlyphPosition) bool {
        return self.flags.kashida;
    }

    pub fn isTab(self: GlyphPosition) bool {
        return self.flags.tab;
    }

    pub fn isActiveTab(self: GlyphPosition) bool {
        return self.flags.tab and !self.flags.collapsed_whitespace;
    }

    pub fn isCollapsedWhitespace(self: GlyphPosition) bool {
        return self.flags.collapsed_whitespace;
    }

    /// Logical source end represented by this output.
    ///
    /// Ordinary shaped glyphs keep the historical one-byte fallback for
    /// hand-constructed records whose source length is omitted. An automatic
    /// hyphen is different: it is a zero-length insertion at an existing
    /// source boundary and must never claim the following UTF-8 byte.
    pub fn sourceByteEnd(self: GlyphPosition) usize {
        if (self.isAutomaticHyphen() or self.isKashida()) return self.cluster;
        return self.cluster + @max(self.source_byte_len, 1);
    }
};

test "positioned glyph flags preserve the compact public layout" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(GlyphPosition));
}
