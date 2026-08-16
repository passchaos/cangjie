//! Source-visible STAT values and validated table layout.

pub const DesignAxis = struct {
    tag: [4]u8,
    name_id: u16,
    ordering: u16,
};

pub const AxisValue = struct {
    format: u16,
    flags: u16,
    name_id: u16,
    axis_index: ?u16 = null,
    value: ?f32 = null,
    linked_value: ?f32 = null,
    nominal_value: ?f32 = null,
    range_min_value: ?f32 = null,
    range_max_value: ?f32 = null,
    coordinates: []AxisValueCoordinate = &.{},
};

pub const AxisValueCoordinate = struct {
    axis_index: u16,
    value: f32,
};

/// Byte layout proved by `table.info`.
pub const Info = struct {
    minor_version: u16,
    design_axis_size: usize,
    design_axis_count: usize,
    design_axes_offset: usize,
    axis_value_count: usize,
    axis_value_offsets_offset: usize,
};
