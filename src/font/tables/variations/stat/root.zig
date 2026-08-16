//! OpenType STAT grammar, concrete values, validation, and owned reads.

const read = @import("read.zig");
const table = @import("table.zig");
const types = @import("types.zig");
const validation = @import("validation.zig");

pub const DesignAxis = types.DesignAxis;
pub const AxisValue = types.AxisValue;
pub const AxisValueCoordinate = types.AxisValueCoordinate;
pub const Info = types.Info;

pub const info = table.info;
pub const axisValueOffset = table.axisValueOffset;
pub const validate = validation.validate;
pub const readElidedFallbackNameId = read.elidedFallbackNameId;
pub const readDesignAxes = read.designAxes;
pub const readAxisValues = read.axisValues;
pub const freeAxisValues = read.freeAxisValues;
