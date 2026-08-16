//! Shared TrueType compound-glyph validation values.

pub const GlyphId = u16;

pub const PointMatch = struct {
    parent_point: u16,
    child_point: u16,
};

pub const Component = struct {
    glyph: GlyphId,
    point_match: ?PointMatch = null,
};

pub const Links = struct {
    components: []Component = &.{},
};

pub const Limits = struct {
    max_points: u16,
    max_contours: u16,
    max_component_elements: u16,
    max_component_depth: u16,
};
