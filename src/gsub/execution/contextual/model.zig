//! Shared values for contextual GSUB matching and nested lookup mutation.

const accelerator = @import("../../accelerator/model.zig");

pub const max_components = accelerator.max_ligature_components;

pub const Change = struct {
    /// Number of input glyphs consumed by the nested lookup.
    removed_len: usize = 1,
    /// Number of replacement glyphs produced at the target position.
    inserted_len: usize = 1,
    /// Physical component offsets are present only for LigatureSubst. Ignored
    /// glyphs may remain between those components in the mutable run.
    component_offsets: ?[max_components]usize = null,
    component_count: usize = 0,
};

pub const ApplyResult = struct {
    matched: bool = false,
    next_pos: usize = 0,
};

/// Resume at the adjusted end of a contextual match after a nested mutation.
pub fn nextPositionAfterMutation(
    original_next: usize,
    match_start: usize,
    glyph_count_before: usize,
    glyph_count_after: usize,
) usize {
    if (glyph_count_after >= glyph_count_before) {
        return original_next + (glyph_count_after - glyph_count_before);
    }

    // A contraction shifts the match end left, but must not rewind onto the
    // position that was just consumed.
    return @max(
        match_start + 1,
        original_next -| (glyph_count_before - glyph_count_after),
    );
}
