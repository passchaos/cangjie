//! Value types shared by horizontal and vertical SFNT metric tables.

pub const Header = struct {
    version: u32,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    advance_max: u16,
    min_side_bearing: i16,
    min_opposite_side_bearing: i16,
    max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    metric_data_format: i16,
    long_metric_count: u16,
};

pub const Horizontal = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

/// Raw vmtx records and variation-adjusted vertical metrics share one value
/// type: both describe the final advance and top side bearing for one glyph.
pub const Vertical = struct {
    advance_height: u16,
    top_side_bearing: i16,
};
