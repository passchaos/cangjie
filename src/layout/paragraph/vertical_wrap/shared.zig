//! Shared value records for vertical wrapping.

pub const Range = struct {
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
};

pub const SoftCandidate = struct {
    /// Visible glyph prefix; boundary whitespace can make this smaller than
    /// `next_glyph_start`.
    glyph_end: usize,
    next_glyph_start: usize,
    byte_end: usize,
};
