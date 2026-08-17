//! GDEF value types shared by public inspection and shaping metadata.

pub const GlyphClass = enum(u16) {
    unclassified = 0,
    base = 1,
    ligature = 2,
    mark = 3,
    component = 4,
    _,
};

pub const Header = struct {
    minor_version: u16,
    length: usize,
    glyph_class_def_offset: u16,
    attach_list_offset: u16,
    lig_caret_list_offset: u16,
    mark_attach_class_def_offset: u16,
    mark_glyph_sets_def_offset: ?u16 = null,
    item_variation_store_offset: ?u32 = null,
};

/// One resolved horizontal ligature caret in font design units.
pub const LigatureCaret = struct {
    position: f32,
};

/// One GDEF AttachList contour-point index.
pub const AttachmentPoint = struct {
    point_index: u16,
};
