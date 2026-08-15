//! Runtime decoding of COLR v1 transforms, gradients, and ColorLines.

const gradients = @import("gradients.zig");
const transforms = @import("transforms.zig");

pub const Context = @import("types.zig").Context;

pub const transform = transforms.transform;
pub const linearGradient = gradients.linearGradient;
pub const radialGradient = gradients.radialGradient;
pub const sweepGradient = gradients.sweepGradient;
pub const colorLine = gradients.colorLine;
