//! OpenType fvar grammar, concrete values, and owned reads.

const coordinates = @import("coordinates.zig");
const names = @import("names.zig");
const read = @import("read.zig");
const table = @import("table.zig");
const types = @import("types.zig");

pub const Axis = types.Axis;
pub const Coordinate = types.Coordinate;
pub const Instance = types.Instance;
pub const Info = types.Info;

pub const info = table.info;
pub const validate = table.validate;
pub const axisOffset = table.axisOffset;
pub const instanceOffset = table.instanceOffset;

pub const readAxes = read.axes;
pub const readInstances = read.instances;
pub const freeInstances = read.freeInstances;

pub const validateNameReferences = names.validateAll;
pub const validateAxisNameReferences = names.validateAxes;
pub const validateInstanceNameReferences = names.validateInstances;

pub const validateCoordinates = coordinates.validate;
pub const coordinateValueForAxis = coordinates.valueForAxis;
pub const quantizeNormalized = coordinates.quantizeNormalized;
