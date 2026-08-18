//! Shared value records for vertical wrapping.

pub const Range = struct {
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
    /// Flow-axis indentation reserved before this column's first glyph.
    /// Only the first column of each hard-break segment receives it.
    inline_indent: f32 = 0,
    /// Whether this column begins a source paragraph segment. Physical column
    /// placement uses this to insert block-axis paragraph spacing.
    starts_segment: bool = false,
};

pub const SoftCandidate = struct {
    /// Visible glyph prefix; boundary whitespace can make this smaller than
    /// `next_glyph_start`.
    glyph_end: usize,
    next_glyph_start: usize,
    byte_end: usize,
};
