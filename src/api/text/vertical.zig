//! Unicode vertical orientation used by vertical text layout.

const unicode = @import("../../unicode.zig");

pub const Orientation = unicode.VerticalOrientation;
pub const unicode_version = unicode.vertical_orientation_unicode_version;
pub const orientation = unicode.verticalOrientationForCodepoint;
