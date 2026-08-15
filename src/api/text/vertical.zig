//! Unicode vertical orientation used by vertical text layout.

const unicode = @import("../../unicode.zig");

pub const Orientation = unicode.VerticalOrientation;
pub const orientation = unicode.verticalOrientationForCodepoint;
