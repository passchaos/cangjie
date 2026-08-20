//! Values shared by LigatureSubst matching, metadata, and commit stages.

const accelerator = @import("../../../accelerator/model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const max_components = accelerator.max_ligature_components;

pub const Match = struct {
    ligature: GlyphId,
    component_count: usize,
    component_offsets: *const [max_components]usize,
    match_end: usize = 1,
};

pub const Change = struct {
    removed_len: usize,
    inserted_len: usize = 1,
    component_offsets: [max_components]usize,
    component_count: usize,
};
