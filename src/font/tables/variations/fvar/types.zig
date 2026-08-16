//! Source-visible fvar values and validated table layout.

pub const Axis = struct {
    tag: [4]u8,
    min_value: f32,
    default_value: f32,
    max_value: f32,
    flags: u16,
    name_id: u16,

    pub fn clamp(self: Axis, value: f32) f32 {
        return @min(self.max_value, @max(self.min_value, value));
    }

    pub fn normalize(self: Axis, value: f32) f32 {
        const clamped = self.clamp(value);
        if (clamped == self.default_value) return 0;
        if (clamped < self.default_value) {
            const span = self.default_value - self.min_value;
            if (span == 0) return 0;
            return (clamped - self.default_value) / span;
        }
        const span = self.max_value - self.default_value;
        if (span == 0) return 0;
        return (clamped - self.default_value) / span;
    }
};

pub const Coordinate = struct {
    tag: [4]u8,
    value: f32,
};

pub const Instance = struct {
    subfamily_name_id: u16,
    flags: u16,
    postscript_name_id: ?u16 = null,
    coordinates: []Coordinate,
};

/// Byte layout proved by `table.info`.
///
/// Offsets before `axisOffset`/`instanceOffset` are relative to fvar. Keeping
/// the record strides in this value lets validation and reading share one
/// interpretation instead of independently re-deriving table regions.
pub const Info = struct {
    axes_array_offset: usize,
    axis_count: usize,
    axis_size: usize,
    instance_count: usize,
    instance_size: usize,
    instances_array_offset: usize,
    postscript_name_id_offset: usize,
    has_postscript_name_id: bool,
};
