//! Shared value records for vertical wrapping.

const discretionary_hyphen = @import("../../discretionary_hyphen.zig");

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
    /// Final visual column index used to resolve caller-supplied inline
    /// regions after balanced wrapping has chosen its source boundaries.
    visual_index: usize = 0,
    /// Source U+00AD selected as a visible terminal glyph for this column.
    ///
    /// Shaping may retain it as an invisible output or omit the
    /// default-ignorable entirely. Final column construction therefore either
    /// materializes the existing output or inserts a source-owning glyph at
    /// the recorded boundary.
    hyphen: ?discretionary_hyphen.VerticalCandidate = null,
};

pub const SoftCandidate = struct {
    /// Visible glyph prefix; boundary whitespace can make this smaller than
    /// `next_glyph_start`.
    glyph_end: usize,
    next_glyph_start: usize,
    byte_end: usize,
    hyphen: ?discretionary_hyphen.VerticalCandidate = null,
};
