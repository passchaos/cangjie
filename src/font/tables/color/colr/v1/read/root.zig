//! Runtime decoding of COLR v1 transforms, gradients, and ColorLines.

const clip_boxes = @import("clip_box.zig");
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
pub const clipBox = clip_boxes.resolve;

test {
    _ = @import("tests/root.zig");
}
