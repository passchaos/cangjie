//! Runtime decoding of COLR v1 transforms, gradients, and ColorLines.

const color_lines = @import("color_line.zig");
const gradients = @import("gradients.zig");
const paints = @import("paint.zig");
const transforms = @import("transforms.zig");

pub const Context = @import("types.zig").Context;

pub const paint = paints.read;
pub const transform = transforms.transform;
pub const linearGradient = gradients.linearGradient;
pub const radialGradient = gradients.radialGradient;
pub const sweepGradient = gradients.sweepGradient;
pub const colorLine = color_lines.read;
pub const colorStop = color_lines.stop;
pub const colorStops = color_lines.stops;
